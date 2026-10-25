import Foundation
import SwiftData

/// Reading a `CadenceArchive` back into a live store — the half [[T-19]] shipped without.
///
/// `CadenceDataExportService` writes a complete, human-readable copy of everything Cadence
/// persists and stops there, on the stated ground that an unverified restore is worse than none.
/// This is the verified one. It does not invent a second format: it consumes exactly the document
/// that exporter writes, table for table and field for field.
///
/// ## The four decisions, stated rather than left for a reader to infer
///
/// **1. Merge, never replace.** An import adds the archive's rows to the destination store; it
/// deletes nothing, ever. The other branch — wipe the store, then insert — was rejected because
/// the store is CloudKit-backed (`.private("iCloud.com.haoranwei.Cadence")`), so a replace is not
/// a local truncation: it is thousands of *deletions* pushed at every other signed-in device, and
/// it is not undoable from inside the app. It also fails badly in the case a restore exists for —
/// an archive that turns out to be older or thinner than the user believed — because by then the
/// rows it did not contain are gone from every device.
///
/// What that costs the user, plainly: **an import cannot roll a store back to the archive's exact
/// state.** Rows created after the archive was written survive it. If the user genuinely wants the
/// store to *equal* the archive, the supported route is `PrivacyDataResetService` first and an
/// import into the empty store after — two deliberate acts, each of which says what it does.
///
/// **2. Incoming records keep their ids.** A restore must be able to run twice. Minting fresh ids
/// would make the second run duplicate the entire store, and would make an import over a
/// half-restored store duplicate the half that landed — the failure mode most likely to be
/// *reached*, since a restore is something people retry. Keeping ids makes an import over the same
/// store an update rather than a copy: `CadenceArchiveImportMode` then decides what "update"
/// means, and both answers are non-destructive at row level. **One table also matches on more than
/// its id:** a tag the destination already holds under another id — same stable slug, same
/// archived state — is treated as that row rather than inserted beside it ([[T-3110]]); see
/// `tagAliases(_:against:)`.
///
/// **3. CloudKit.** This writes through whatever store the caller's `ModelContext` belongs to. On
/// a synced device that means every inserted row is uploaded, so "restore my backup here" is
/// "push these rows at my other devices" from theirs. That is the correct behaviour for a restore
/// and it is why the write is arranged the way it is: **validation completes before the first
/// insert.** A malformed archive is refused having written nothing, so there is no such thing as a
/// half-uploaded rejected import. See `validate(_:against:)`.
///
/// **4. Partial failure.** Three failure classes, and they are answered differently rather than
/// hidden behind one word. The line that matters runs between the first two and the third: **a
/// throw from this service means nothing was written; a returned outcome means the archive is on
/// disk.**
/// - *The archive is bad.* Unreadable JSON, a format version this build does not know, a repeated
///   id, or a reference to a row that exists neither in the archive nor in the destination — all
///   throw from `validate(_:against:)`, which runs to completion before anything is inserted. The
///   store is untouched and the thrown `CadenceArchiveImportFailure` names the table, the row and
///   the field.
/// - *The write itself fails.* `apply(_:mode:in:foldingLegacyNotes:)` inserts and then commits
///   once. If that commit throws, it rolls the context back and rethrows, so the import leaves
///   nothing pending for an unrelated later `save()` to pick up. The caller must hand this a
///   context it is willing to have rolled back — `importArchive(_:mode:into:)` makes a private one
///   for exactly that reason.
/// - *The archive committed and the legacy-note fold after it did not.* The fold is a second write
///   (see below), so it cannot be reported as a refusal without telling the user that data which is
///   already on their disk is not. It **returns**, with the committed counts intact and
///   `CadenceArchiveImportOutcome.legacyNoteFoldFailure` naming what is still outstanding — the
///   distinction [[T-1111]] exists to keep.
///
/// ## The legacy note tables
///
/// `DailyNote` / `WeeklyNote` / `PermNote` / `EventNote` / `Document` are exported because a
/// pre-migration archive is their only copy. They are imported for the same reason, and then
/// `NoteMigrationService.migrateIfNeeded(in:source:saveChanges:)` is run over the result. That is
/// the right order and not merely a convenient one: the migration is guarded by
/// `Note.legacySourceKindRaw` / `Note.legacySourceID` and by `Note.canonicalKey`, both of which the
/// archive carries, so a legacy row whose canonical `Note` came in from the same archive is
/// recognised as already folded and is not duplicated. A pre-migration archive folds; a
/// post-migration one does not move.
///
/// **That fold is a second commit, and the importer is therefore not one transaction.** The
/// archive's own rows land in a single `save()`; `NoteMigrationService` then reads the settled
/// store and saves its own inserts. The source sweep in `CadenceNoteFolderMoveCommitTests` counts
/// the `save()` calls *in this file* and so cannot see the second one — read it as "no per-row
/// save", which is what it actually guarantees, not as atomicity.
nonisolated enum CadenceArchiveImportService {

    /// The highest `CadenceArchive.formatVersion` this build knows how to read.
    ///
    /// Deliberately the exporter's own constant rather than a second number: the two are the same
    /// fact, and a reader that lags its writer by a hand-edit is how an app comes to refuse the
    /// file it wrote this morning. A *newer* archive is refused (this build cannot know what
    /// changed); an older one is read, because `formatVersion` is only bumped for changes a reader
    /// must know about.
    nonisolated static var readableFormatVersion: Int { CadenceDataExportService.formatVersion }

    // MARK: - Entry points

    /// Decode, validate, apply, commit — the whole import, from bytes.
    ///
    /// Runs on a `ModelContext` of its own over the caller's container, so the rollback on a failed
    /// commit discards the import and nothing else. Handing the app's shared context to
    /// `apply(_:mode:in:)` directly would put every other pending edit in the blast radius.
    @discardableResult
    nonisolated static func importArchive(
        _ data: Data,
        mode: CadenceArchiveImportMode = .mergeKeepingExistingRows,
        into container: ModelContainer
    ) throws -> CadenceArchiveImportOutcome {
        let archive = try CadenceDataExportService.decode(data)
        return try apply(archive, mode: mode, in: ModelContext(container))
    }

    /// What an import *would* do, having written nothing.
    ///
    /// This is a full validation pass, so it throws everything `apply` throws. That is the point:
    /// a preview that only counted rows would let a surface promise an import that then fails.
    nonisolated static func plan(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode = .mergeKeepingExistingRows,
        in modelContext: ModelContext
    ) throws -> CadenceArchiveImportPlan {
        let destination = try DestinationIndex(in: modelContext)
        return try makePlan(archive, mode: mode, against: destination)
    }

    /// The same preview, from the bytes a file importer hands back.
    ///
    /// Exists so a surface can show a plan without owning a decoder: the entry point in Settings
    /// has a `URL` and nothing else, and a view that reached for `CadenceDataExportService.decode`
    /// itself would be a second place that knows the document format. Throws everything
    /// `decode(_:)` and `plan(_:mode:in:)` throw, and writes nothing either way.
    nonisolated static func plan(
        _ data: Data,
        mode: CadenceArchiveImportMode = .mergeKeepingExistingRows,
        in modelContext: ModelContext
    ) throws -> CadenceArchiveImportPlan {
        try plan(CadenceDataExportService.decode(data), mode: mode, in: modelContext)
    }

    /// The stored URL for an archived saved link: `CadenceSavedLinkURL.normalized`'s rule, so an
    /// archive cannot restore a `file://` or third-party scheme the Mac would open on one click
    /// (T-3106). A scheme other than `http(s)://` is demoted to `https://<raw>`, exactly as a typed
    /// one is; a blank field stays blank rather than becoming `https://`.
    nonisolated static func importedSavedLinkURL(_ raw: String) -> String {
        CadenceSavedLinkURL.normalized(raw) ?? ""
    }

    /// Apply an archive to `modelContext`, commit the archive once, and then fold its legacy notes.
    ///
    /// The caller owns the unit of work and must be willing to have this context rolled back; see
    /// the type's note. Nothing is inserted until `validate(_:against:)` has returned.
    ///
    /// **This throws for a refused import and returns for a committed one — including a committed
    /// one whose fold failed** ([[T-1111]]). The two are different facts and used to arrive as the
    /// same one: the fold is a *second* write, after the archive's own commit, so a throw from it
    /// reached the caller as an undifferentiated failure over rows that were already durable. For a
    /// restore that is the worst direction to be wrong in — the user is told to retry an operation
    /// they have in fact already performed, and a merge-mode retry over committed rows is not the
    /// operation they think they are repeating. So a fold failure is reported in
    /// `CadenceArchiveImportOutcome.legacyNoteFoldFailure` and the counts that *did* commit survive
    /// it; only a failure that left the store untouched still throws.
    @discardableResult
    nonisolated static func apply(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode = .mergeKeepingExistingRows,
        in modelContext: ModelContext,
        foldingLegacyNotes fold: (ModelContext) throws -> Int = foldLegacyNotes(in:)
    ) throws -> CadenceArchiveImportOutcome {
        var destination = try DestinationIndex(in: modelContext)
        let plan = try makePlan(archive, mode: mode, against: destination)
        // [[T-3170]]: everything past validation reads the archive with its blocks already undone,
        // so no `TaskBundle` row is written and every member arrives holding a real time.
        let archive = unbundled(archive)

        var tally = Tally()
        let wired = write(archive, mode: mode, into: &destination, tally: &tally, in: modelContext)
        wire(wired, using: destination)
        reconcileFocusCounters(using: destination)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        // Past this line the archive is on disk. Everything below reports, and nothing below may
        // throw, because a throw here would describe committed work as a refusal.
        var foldedNotes = 0
        var foldFailure: String?
        do {
            foldedNotes = try fold(modelContext)
        } catch {
            // The fold's own half-written inserts, and only those: `rollback()` discards changes
            // made since the last `save()`, and the last `save()` is the archive's own. Left
            // pending they would ride out on the next unrelated commit through this context.
            modelContext.rollback()
            foldFailure = error.localizedDescription
        }

        return CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: tally.inserted,
            overwrittenRecordCount: tally.overwritten,
            skippedRecordCount: tally.skipped,
            notesFoldedFromLegacyRows: foldedNotes,
            legacyNoteFoldFailure: foldFailure
        )
    }

    /// Fold any legacy note rows an import brought in that are not already represented by a `Note`.
    ///
    /// Run after the archive's commit rather than inside it so the migration reads a settled store,
    /// and with `saveChanges: true` so its inserts and placeholder restorations are committed.
    /// A failure here leaves the imported rows in place and the fold undone, which the next launch
    /// repairs: `PersistenceController` runs the same migration.
    ///
    /// A separate declaration so `apply` can be handed a failing one. A store that refuses this
    /// second write is not something a test can induce on a real container, and the outcome
    /// distinction this feeds is the whole of [[T-1111]] — an untestable branch is how the two
    /// outcomes collapsed back into one the first time.
    nonisolated static func foldLegacyNotes(in modelContext: ModelContext) throws -> Int {
        try NoteMigrationService.migrateIfNeeded(
            in: modelContext,
            source: "archive-import",
            saveChanges: true
        ).changedNoteCount
    }

    // MARK: - Validation

    /// Everything that must be true of the document before a single row is inserted.
    ///
    /// Three checks, in the order a failure is cheapest to explain:
    ///
    /// 1. **Format version.** An archive from a newer build may have renamed a key or dropped a
    ///    table; this build would read the difference as absence and import a quietly incomplete
    ///    store. Refused.
    /// 2. **Duplicate ids within a table.** The exporter cannot produce one, so a file that has
    ///    one has been edited or concatenated. Importing it would make the winner depend on
    ///    iteration order.
    /// 3. **Dangling references.** Relationships travel as ids, so every non-`nil` reference must
    ///    name a row that either arrives in this archive or is already in the destination store.
    ///    A reference to neither would produce an orphan — a task in no list, a subtask under no
    ///    task — that no repair pass can reconstruct, because the row it named is gone.
    ///    `DataIntegrityRepairService` exists to fix relationships that *went* stale, not to
    ///    absorb input nobody validated.
    private nonisolated static func validate(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode,
        against destination: DestinationIndex
    ) throws -> [String: Set<UUID>] {
        guard archive.formatVersion <= readableFormatVersion else {
            throw CadenceArchiveImportFailure.unsupportedFormatVersion(
                found: archive.formatVersion,
                readableUpTo: readableFormatVersion
            )
        }

        var archiveIDs: [String: Set<UUID>] = [:]
        archiveIDs["Context"] = try uniqueIDs(archive.contexts, table: "Context")
        archiveIDs["Area"] = try uniqueIDs(archive.areas, table: "Area")
        archiveIDs["Project"] = try uniqueIDs(archive.projects, table: "Project")
        archiveIDs["Pursuit"] = try uniqueIDs(archive.pursuits, table: "Pursuit")
        archiveIDs["Tag"] = try uniqueIDs(archive.tags, table: "Tag")
        archiveIDs["AppTask"] = try uniqueIDs(archive.tasks, table: "AppTask")
        archiveIDs["TaskBundle"] = try uniqueIDs(archive.taskBundles, table: "TaskBundle")
        archiveIDs["FocusSessionLog"] = try uniqueIDs(archive.focusSessions, table: "FocusSessionLog")
        archiveIDs["Subtask"] = try uniqueIDs(archive.subtasks, table: "Subtask")
        archiveIDs["Note"] = try uniqueIDs(archive.notes, table: "Note")
        archiveIDs["SavedLink"] = try uniqueIDs(archive.savedLinks, table: "SavedLink")
        archiveIDs["MarkdownImageAsset"] = try uniqueIDs(archive.markdownImageAssets, table: "MarkdownImageAsset")
        archiveIDs["Goal"] = try uniqueIDs(archive.goals, table: "Goal")
        archiveIDs["GoalListLink"] = try uniqueIDs(archive.goalListLinks, table: "GoalListLink")
        archiveIDs["Habit"] = try uniqueIDs(archive.habits, table: "Habit")
        archiveIDs["HabitCompletion"] = try uniqueIDs(archive.habitCompletions, table: "HabitCompletion")
        archiveIDs["DailyNote"] = try uniqueIDs(archive.legacyDailyNotes, table: "DailyNote")
        archiveIDs["WeeklyNote"] = try uniqueIDs(archive.legacyWeeklyNotes, table: "WeeklyNote")
        archiveIDs["PermNote"] = try uniqueIDs(archive.legacyPermNotes, table: "PermNote")
        archiveIDs["EventNote"] = try uniqueIDs(archive.legacyEventNotes, table: "EventNote")
        archiveIDs["Document"] = try uniqueIDs(archive.legacyDocuments, table: "Document")
        archiveIDs["SidebarLayoutPreference"] = try uniqueIDs(
            archive.sidebarLayoutPreferenceRecords,
            table: "SidebarLayoutPreference"
        )
        archiveIDs["LookPreference"] = try uniqueIDs(
            archive.lookPreferenceRecords,
            table: "LookPreference"
        )
        archiveIDs["NoteTemplatePreference"] = try uniqueIDs(
            archive.noteTemplatePreferenceRecords,
            table: "NoteTemplatePreference"
        )

        let destinationIDs = destination.idsByEntityName
        var known: [String: Set<UUID>] = [:]
        for (name, ids) in archiveIDs {
            known[name] = ids.union(destinationIDs[name] ?? [])
        }

        func check(
            _ id: UUID?,
            _ entity: String,
            table: String,
            record: UUID,
            field: String
        ) throws {
            guard let id else { return }
            guard known[entity, default: []].contains(id) else {
                throw CadenceArchiveImportFailure.danglingReference(
                    table: table,
                    record: record,
                    field: field,
                    missing: id
                )
            }
        }

        for record in archive.areas {
            try check(record.contextID, "Context", table: "Area", record: record.id, field: "contextID")
        }
        for record in archive.projects {
            try check(record.contextID, "Context", table: "Project", record: record.id, field: "contextID")
            try check(record.areaID, "Area", table: "Project", record: record.id, field: "areaID")
        }
        for record in archive.pursuits {
            try check(record.contextID, "Context", table: "Pursuit", record: record.id, field: "contextID")
        }
        for record in archive.tasks {
            try check(record.areaID, "Area", table: "AppTask", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "AppTask", record: record.id, field: "projectID")
            try check(record.goalID, "Goal", table: "AppTask", record: record.id, field: "goalID")
            try check(record.contextID, "Context", table: "AppTask", record: record.id, field: "contextID")
            try check(record.bundleID, "TaskBundle", table: "AppTask", record: record.id, field: "bundleID")
            for tagID in record.tagIDs {
                try check(tagID, "Tag", table: "AppTask", record: record.id, field: "tagIDs")
            }
        }
        for record in archive.focusSessions {
            try check(record.taskID, "AppTask", table: "FocusSessionLog", record: record.id, field: "taskID")
            try check(record.areaID, "Area", table: "FocusSessionLog", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "FocusSessionLog", record: record.id, field: "projectID")
        }
        for record in archive.subtasks {
            try check(record.parentTaskID, "AppTask", table: "Subtask", record: record.id, field: "parentTaskID")
        }
        for record in archive.notes {
            try check(record.areaID, "Area", table: "Note", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "Note", record: record.id, field: "projectID")
            for tagID in record.tagIDs {
                try check(tagID, "Tag", table: "Note", record: record.id, field: "tagIDs")
            }
        }
        for record in archive.savedLinks {
            try check(record.areaID, "Area", table: "SavedLink", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "SavedLink", record: record.id, field: "projectID")
        }
        for record in archive.goals {
            try check(record.contextID, "Context", table: "Goal", record: record.id, field: "contextID")
            try check(record.pursuitID, "Pursuit", table: "Goal", record: record.id, field: "pursuitID")
            try check(record.parentGoalID, "Goal", table: "Goal", record: record.id, field: "parentGoalID")
        }
        for record in archive.goalListLinks {
            try check(record.goalID, "Goal", table: "GoalListLink", record: record.id, field: "goalID")
            try check(record.areaID, "Area", table: "GoalListLink", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "GoalListLink", record: record.id, field: "projectID")
        }
        for record in archive.habits {
            try check(record.contextID, "Context", table: "Habit", record: record.id, field: "contextID")
            try check(record.pursuitID, "Pursuit", table: "Habit", record: record.id, field: "pursuitID")
            try check(record.goalID, "Goal", table: "Habit", record: record.id, field: "goalID")
        }
        for record in archive.habitCompletions {
            try check(record.habitID, "Habit", table: "HabitCompletion", record: record.id, field: "habitID")
        }
        for record in archive.legacyDocuments {
            try check(record.areaID, "Area", table: "Document", record: record.id, field: "areaID")
            try check(record.projectID, "Project", table: "Document", record: record.id, field: "projectID")
        }

        try validateGoalHierarchy(archive, mode: mode, against: destination)

        return archiveIDs
    }

    /// **[[T-1109]]. The one property of the goal tree that no existence check implies.**
    ///
    /// A resolvable `parentGoalID` is not an acyclic one. A goal that is its own parent, or a pair
    /// pointing at each other, satisfies every check above: no id is repeated and every reference
    /// names a row that exists. What it produces is a component with **no root**, and the Goals
    /// surfaces that list goals have no other way in — every one of them starts at
    /// `GoalAssignmentRules.topLevelGoals`, which is `parentGoal == nil`, and descends with
    /// `GoalAssignmentRules.nestedGoals(under:)`. So the goals import, sync to every other
    /// device, and appear nowhere. ([[T-5002]] deleted the Goals pages themselves; the widgets
    /// and the MCP read tools still read the same two rules.)
    /// `aRootlessGoalCycleIsInTheStoreAndOnNoGoalsRow` measures that consequence on its own, built
    /// by hand rather than through an import, so it still stands if this guard ever moves.
    ///
    /// **The graph checked is the one the import will leave behind, not the archive's own edges.**
    /// A cycle can close through a row the archive never carries: overwrite one goal's parent edge
    /// and the untouched destination row on the other side completes it. So the map starts as the
    /// destination's and then has this import's edges written over it, exactly as `upsert` and
    /// `wire` will write them.
    ///
    /// **A cycle that was already there is not this import's to refuse.** Every goal has a single
    /// optional parent, so this is a functional graph: each component holds at most one cycle and
    /// cycles are node-disjoint. "Is this cycle new" is therefore answerable exactly — a cycle is
    /// new if and only if it contains an edge this import writes — rather than approximated by a
    /// depth limit, which would decide a different question. macOS deliberately *flattens* deeper
    /// descendants (`GoalAssignmentRules.nestedGoals(under:)`); it does not forbid them, and a
    /// validator that did would refuse valid archives.
    private nonisolated static func validateGoalHierarchy(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode,
        against destination: DestinationIndex
    ) throws {
        var parents: [UUID: UUID] = [:]
        for (id, goal) in destination.goals {
            if let parentID = goal.parentGoal?.id { parents[id] = parentID }
        }

        // The edges this import actually writes. A matched row in merge mode is skipped, so its
        // parent stays whatever the destination holds and nothing here changes.
        var changed: Set<UUID> = []
        for record in archive.goals {
            let existing = destination.goals[record.id]
            guard existing == nil || mode == .restoreOverwritingExistingRows else { continue }
            guard record.parentGoalID != existing?.parentGoal?.id else { continue }
            if let parentID = record.parentGoalID {
                parents[record.id] = parentID
                changed.insert(record.id)
            } else {
                parents.removeValue(forKey: record.id)
            }
        }

        // Walking from a changed row alone is sufficient and not merely cheaper: a new cycle
        // contains a changed row by definition, and from any node in a cycle the only path is
        // around it. Sorted so a document with two new cycles names the same one every time.
        var settled: Set<UUID> = []
        for start in changed.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !settled.contains(start) else { continue }
            var path: [UUID] = []
            var position: [UUID: Int] = [:]
            var node: UUID? = start
            while let current = node {
                if let index = position[current] {
                    let cycle = Array(path[index...])
                    if let offender = cycle
                        .filter(changed.contains)
                        .min(by: { $0.uuidString < $1.uuidString }) {
                        let rotation = cycle.firstIndex(of: offender) ?? 0
                        throw CadenceArchiveImportFailure.parentCycle(
                            table: "Goal",
                            record: offender,
                            field: "parentGoalID",
                            cycle: Array(cycle[rotation...]) + Array(cycle[..<rotation])
                        )
                    }
                    break
                }
                if settled.contains(current) { break }
                position[current] = path.count
                path.append(current)
                node = parents[current]
            }
            settled.formUnion(path)
        }
    }

    private nonisolated static func uniqueIDs<Record: Identifiable>(
        _ records: [Record],
        table: String
    ) throws -> Set<UUID> where Record.ID == UUID {
        var seen: Set<UUID> = []
        for record in records where !seen.insert(record.id).inserted {
            throw CadenceArchiveImportFailure.duplicateRecordID(table: table, id: record.id)
        }
        return seen
    }

    private nonisolated static func makePlan(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode,
        against destination: DestinationIndex
    ) throws -> CadenceArchiveImportPlan {
        // Validated as written — a task naming a block the file does not carry is still a refusal,
        // exactly as before — and planned as it will be written ([[T-3170]]): blocks undone, so the
        // preview counts no block to insert and compares each member at the time it will arrive at.
        var archiveIDs = try validate(archive, mode: mode, against: destination)
        archiveIDs["TaskBundle"] = []
        let archive = unbundled(archive)
        let destinationIDs = destination.idsByEntityName

        var inserts: [String: Int] = [:]
        var matches: [String: Int] = [:]
        for (name, ids) in archiveIDs {
            let existing = destinationIDs[name] ?? []
            inserts[name] = ids.subtracting(existing).count
            matches[name] = ids.intersection(existing).count
        }
        // [[T-3110]]: a tag matched by its slug is a matched row, not an insert, so the preview
        // says what `write` will do — and a second import of the same file still reads as a no-op.
        let aliasedTags = tagAliases(archive, against: destination)
        if !aliasedTags.isEmpty {
            inserts["Tag", default: 0] -= aliasedTags.count
            matches["Tag", default: 0] += aliasedTags.count
        }
        // [[T-3146]], widened by [[T-4720]]: and a note matched by the shared key its kind keys
        // on — a day, a week or a calendar event — for the same reason.
        let aliasedSharedKeyNotes = sharedKeyNoteAliases(archive, against: destination)
        var presentNotes = destination.notes
        if !aliasedSharedKeyNotes.isEmpty {
            inserts["Note", default: 0] -= aliasedSharedKeyNotes.count
            matches["Note", default: 0] += aliasedSharedKeyNotes.count
            // So `differingCounts` below compares each aliased record against the row it will
            // actually be written onto rather than skipping it for having no row under its id.
            for (recordID, note) in aliasedSharedKeyNotes { presentNotes[recordID] = note }
        }
        // Both normalizations `write` applies, replayed here so the preview compares what the
        // write will store: an aliased tag id, and an aliased note's references ([[T-3146]]).
        let noteReferenceRedirects = aliasedNoteReferenceRedirects(aliasedSharedKeyNotes)
        func asWritten(_ record: CadenceArchiveTask) -> CadenceArchiveTask {
            var record = record
            record.tagIDs = aliasedTagIDs(record.tagIDs, aliasedTags)
            record.notes = redirectingNoteReferences(in: record.notes, noteReferenceRedirects)
            return record
        }
        func asWritten(_ record: CadenceArchiveNote) -> CadenceArchiveNote {
            var record = record
            record.tagIDs = aliasedTagIDs(record.tagIDs, aliasedTags)
            record.content = redirectingNoteReferences(in: record.content, noteReferenceRedirects)
            return record
        }

        // [[T-3111]], [[T-3131]]. Read-only: this compares, it writes nothing, and it does not
        // change what either mode does to the rows it counts.
        func differing<Record: Identifiable, Model>(
            _ records: [Record],
            _ present: [UUID: Model],
            _ differs: (Record, Model) -> Bool
        ) -> Int where Record.ID == UUID {
            records.filter { record in
                guard let model = present[record.id] else { return false }
                return differs(record, model)
            }.count
        }
        let differingCounts: [String: Int] = [
            "AppTask": differing(archive.tasks, destination.tasks) { record, present in
                matchedTaskDiffers(asWritten(record), from: present)
            },
            "Area": differing(archive.areas, destination.areas, matchedAreaDiffers),
            "Project": differing(archive.projects, destination.projects, matchedProjectDiffers),
            "Subtask": differing(archive.subtasks, destination.subtasks, matchedSubtaskDiffers),
            "Note": differing(archive.notes, presentNotes) { record, present in
                matchedNoteDiffers(
                    asWritten(record),
                    from: present,
                    foldedFrom: legacyFoldSource(of: present, in: archive, against: destination)
                )
            },
            "SavedLink": differing(archive.savedLinks, destination.savedLinks, matchedSavedLinkDiffers),
        ]

        let buildEntities = Set(CadenceSchema.schema.entities.map(\.name))
        return CadenceArchiveImportPlan(
            mode: mode,
            insertCountsByEntityName: inserts,
            matchedCountsByEntityName: matches,
            entityNamesOnlyInTheArchive: archive.schemaEntityNames
                .filter { !buildEntities.contains($0) }
                .sorted(),
            linkedCalendarCount: archive.areas.filter { !$0.linkedCalendarID.isEmpty }.count
                + archive.projects.filter { !$0.linkedCalendarID.isEmpty }.count,
            differingMatchedCountsByEntityName: differingCounts
        )
    }

    /// **The archive with its blocks undone** ([[T-3170]]): every `TaskBundle` record removed, and
    /// each block's day and time pushed down onto the tasks that named it.
    ///
    /// **Why the import does this at all.** The Block feature is leaving the product and every
    /// archive the owner has taken so far contains blocks, so the import must keep *reading* them.
    /// What it must not do is restore them: a member carries `scheduledStartMin == -1` because its
    /// block owned the slot, so a restored block hands the user tasks on a date with no time, drawn
    /// by no surface once the block views are gone.
    ///
    /// **Why on the record and not in the store.** Retiring the rows after `write` would leave the
    /// plan describing a different import from the one `apply` performs — a block counted as an
    /// insert that never lands, members compared at `-1` against a store holding their real times —
    /// so a second import of the same file would never read as the no-op a restore has to be. Done
    /// here, before planning, the preview, the write and the re-import comparison are all about
    /// the same rows. It also leaves alone any block already in the destination, which is the
    /// launch pass's to retire (`TaskBundleRetirement.runIfNeeded`), not an import's.
    ///
    /// **The layout is the launch pass's, called rather than re-spelled**: `TaskBundleRetirement.layout`
    /// orders the members and gives each its slot, and each then takes the walk's five field writes —
    /// detached, `bundleOrder` 0, the block's day, their own start, `calendarEventID` cleared.
    /// Membership is read from the task side (`bundleID`), as the store walk reads `task.bundle`.
    /// A task naming a block the archive does not carry is left as it is; `validate` has already
    /// either refused it or found that block in the destination.
    nonisolated static func unbundled(_ archive: CadenceArchive) -> CadenceArchive {
        guard !archive.taskBundles.isEmpty else { return archive }
        var result = archive
        let blocks = Dictionary(archive.taskBundles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var membersByBlock: [UUID: [Int]] = [:]
        for (index, task) in result.tasks.enumerated() {
            guard let blockID = task.bundleID, blocks[blockID] != nil else { continue }
            membersByBlock[blockID, default: []].append(index)
        }
        for (blockID, indices) in membersByBlock {
            guard let block = blocks[blockID] else { continue }
            let placed = TaskBundleRetirement.layout(
                indices,
                bundleOrder: { result.tasks[$0].bundleOrder },
                createdAt: { result.tasks[$0].createdAt },
                estimatedMinutes: { result.tasks[$0].estimatedMinutes },
                blockStart: block.startMin,
                blockDuration: block.durationMinutes
            )
            for (index, start) in placed {
                result.tasks[index].bundleID = nil
                result.tasks[index].bundleOrder = 0
                result.tasks[index].scheduledDate = block.dateKey
                result.tasks[index].scheduledStartMin = start
                result.tasks[index].calendarEventID = ""
            }
        }
        result.taskBundles = []
        return result
    }

    /// Whether overwriting `present` with `record` would change it — every scalar field the
    /// importer writes, and the area, project, goal, context, bundle and tag links ([[T-3111]]).
    ///
    /// **Compared through the exporter's own record**, `CadenceArchiveTask(present)`, rather than
    /// field by field: that initializer is the definition of what the archive says about a task,
    /// including the millisecond timestamp normalization, so a store that was just imported from
    /// this archive compares equal by construction and a field added to the record is compared
    /// without anyone remembering to come back here.
    ///
    /// Two deliberate normalizations. Tag ids are compared as a set, because the importer wires
    /// them as a set and a hand-ordered archive is not a different task. And `actualMinutes` is left
    /// out, because it is not a field either mode leaves alone or replaces — it is the focus-session
    /// total `reconcileFocusCounters` raises in both (`CadenceArchiveImportPresentation.focusMinutesNote`).
    nonisolated static func matchedTaskDiffers(_ record: CadenceArchiveTask, from present: AppTask) -> Bool {
        var incoming = record
        var current = CadenceArchiveTask(present)
        current.actualMinutes = incoming.actualMinutes
        incoming.tagIDs = incoming.tagIDs.sorted { $0.uuidString < $1.uuidString }
        current.tagIDs = current.tagIDs.sorted { $0.uuidString < $1.uuidString }
        return incoming != current
    }

    /// `matchedTaskDiffers` for an area ([[T-3131]]): every field `write` copies, and the context
    /// link. `loggedMinutes` is left out for the reason `actualMinutes` is — it is the focus-session
    /// total `reconcileFocusCounters` raises in both modes, not a field either one leaves or replaces.
    nonisolated static func matchedAreaDiffers(_ record: CadenceArchiveArea, from present: Area) -> Bool {
        var current = CadenceArchiveArea(present)
        current.loggedMinutes = record.loggedMinutes
        return record != current
    }

    /// `matchedAreaDiffers` for a project: the same fields, the same `loggedMinutes` exclusion, and
    /// the area link beside the context one.
    nonisolated static func matchedProjectDiffers(_ record: CadenceArchiveProject, from present: Project) -> Bool {
        var current = CadenceArchiveProject(present)
        current.loggedMinutes = record.loggedMinutes
        return record != current
    }

    /// A subtask is written verbatim and wired to its parent task, so there is nothing to normalise.
    nonisolated static func matchedSubtaskDiffers(_ record: CadenceArchiveSubtask, from present: Subtask) -> Bool {
        record != CadenceArchiveSubtask(present)
    }

    /// A saved link's `url` is the one field `write` does not copy verbatim: it goes through
    /// `importedSavedLinkURL` ([[T-3106]]). So the archive's string is compared as the importer would
    /// store it — `" example.com "` restores as `"https://example.com"`, and that is not a difference.
    nonisolated static func matchedSavedLinkDiffers(_ record: CadenceArchiveSavedLink, from present: SavedLink) -> Bool {
        var incoming = record
        incoming.url = importedSavedLinkURL(record.url)
        return incoming != CadenceArchiveSavedLink(present)
    }

    /// One legacy row the post-commit fold may have poured into an empty dated note. See
    /// `matchedNoteDiffers`.
    nonisolated struct LegacyFoldSource: Equatable, Sendable {
        /// `NoteMigrationService.LegacyKind`'s raw value — `"daily"` or `"weekly"`.
        let kindRaw: String
        let id: UUID
        let content: String
        let createdAt: Date
        let updatedAt: Date
    }

    /// The legacy daily or weekly row `present` says it was filled from, read from this archive
    /// first and from the store second — the two places the fold reads.
    ///
    /// The kind strings are `NoteMigrationService.LegacyKind`'s raw values, restated because that
    /// enum is main-actor isolated by the target default and this importer is not. They cannot
    /// drift silently: `anEmptyDailyNoteTheLegacyFoldFilledIsNotADifference` re-imports a filled
    /// placeholder and goes red the moment these stop naming the fold's own kinds.
    private nonisolated static func legacyFoldSource(
        of present: Note,
        in archive: CadenceArchive,
        against destination: DestinationIndex
    ) -> LegacyFoldSource? {
        guard let id = UUID(uuidString: present.legacySourceID) else { return nil }
        switch present.legacySourceKindRaw {
        case "daily":
            if let row = archive.legacyDailyNotes.first(where: { $0.id == id }) {
                return LegacyFoldSource(kindRaw: "daily", id: id, content: row.content,
                                        createdAt: row.createdAt, updatedAt: row.updatedAt)
            }
            if let model = destination.legacyDailyNotes[id] {
                let row = CadenceArchiveDailyNote(model)
                return LegacyFoldSource(kindRaw: "daily", id: id, content: row.content,
                                        createdAt: row.createdAt, updatedAt: row.updatedAt)
            }
        case "weekly":
            if let row = archive.legacyWeeklyNotes.first(where: { $0.id == id }) {
                return LegacyFoldSource(kindRaw: "weekly", id: id, content: row.content,
                                        createdAt: row.createdAt, updatedAt: row.updatedAt)
            }
            if let model = destination.legacyWeeklyNotes[id] {
                let row = CadenceArchiveWeeklyNote(model)
                return LegacyFoldSource(kindRaw: "weekly", id: id, content: row.content,
                                        createdAt: row.createdAt, updatedAt: row.updatedAt)
            }
        default:
            break
        }
        return nil
    }

    /// `matchedTaskDiffers` for a note ([[T-3131]]): every field `write` copies, and the area,
    /// project and tag links. Three things the importer does on the way in are replayed on the
    /// archive's copy first, so a store that was just imported from this archive compares equal:
    ///
    /// - **Folder filing.** `write` files the note through `CadenceListNoteFiling.fileWithoutCommitting`,
    ///   which is `CadenceNoteFolderPath.normalized` — a hand-edited `"/Planning/"` is stored as
    ///   `"Planning"`.
    /// - **Tag order.** The importer wires tags as a set, exactly as for a task.
    /// - **The legacy fold.** `apply` runs `NoteMigrationService` after the commit, and its one edit
    ///   to a note that already exists is `restoreEmptyDatedNote`: an empty, untagged daily or
    ///   weekly note with no legacy source is given the matching legacy row's content, the earlier
    ///   `createdAt`, the later `updatedAt` and that row as its source. When `present` names such a
    ///   row and the archive's copy is exactly such a placeholder, the same edit is applied to the
    ///   archive's copy before comparing. Overwriting would put the empty body back and the fold
    ///   would fill it again, so that is not a difference either mode resolves.
    ///
    /// And the `id` is not compared ([[T-3146]]). A daily note matched by its date key keeps the
    /// **destination's** id, exactly as an aliased tag does, so the two ids differ by construction
    /// and comparing them would report every aliased note as differing for ever — including on the
    /// second run of an import that has already been applied. For a note matched by its id the two
    /// are equal anyway, so nothing else changes.
    nonisolated static func matchedNoteDiffers(
        _ record: CadenceArchiveNote,
        from present: Note,
        foldedFrom legacy: LegacyFoldSource? = nil
    ) -> Bool {
        var incoming = record
        var current = CadenceArchiveNote(present)
        incoming.id = current.id
        incoming.folderPath = CadenceNoteFolderPath.normalized(record.folderPath)
        if let legacy,
           record.kindRaw == NoteKind.daily.rawValue || record.kindRaw == NoteKind.weekly.rawValue,
           record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.tagIDs.isEmpty,
           record.legacySourceKindRaw.isEmpty, record.legacySourceID.isEmpty,
           !legacy.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            incoming.content = legacy.content
            incoming.createdAt = min(record.createdAt, legacy.createdAt)
            incoming.updatedAt = max(record.updatedAt, legacy.updatedAt)
            incoming.legacySourceKindRaw = legacy.kindRaw
            incoming.legacySourceID = legacy.id.uuidString
        }
        incoming.tagIDs = incoming.tagIDs.sorted { $0.uuidString < $1.uuidString }
        current.tagIDs = current.tagIDs.sorted { $0.uuidString < $1.uuidString }
        return incoming != current
    }

    // MARK: - Tags that are already here under another id

    /// Each archive tag that is logically a tag the destination already holds, mapped to that
    /// destination row ([[T-3110]]).
    ///
    /// **Why a tag, and only a tag, is matched on more than its id.** Every other table here has no
    /// identity but its UUID. A tag has one the whole app already enforces: `TagSupport.resolution`
    /// reuses the row carrying a typed name's slug rather than minting a second, and
    /// `deduplicateTags` groups by the same `TagSupport.stableSlug`. The import was the one writer
    /// left that inserts a second active `bug` beside the first — the file's own documented
    /// restore route (reset, then import) reaches it as soon as the user opens a tag picker in
    /// between — and since [[T-528]] nothing automatic merges the pair, so the user's tasks were
    /// split across two tags identical in every picker.
    ///
    /// **Matched, not merged afterwards, and that is what keeps the importer's decisions.** A
    /// `deduplicateTags` pass after the import would *delete* a row — decision 1 says an import
    /// deletes nothing — and would pick the survivor by `preferredDuplicateTagSort`, letting a
    /// freshly typed default-coloured `bug` outrank the user's recoloured one: [[T-528]]'s harm by
    /// another route. Matching instead lets each mode keep its own meaning: merge leaves the tag
    /// already here exactly as it is, overwrite replaces its fields with the archive's copy, and
    /// neither deletes or re-ids anything. Re-running the import finds the same match, so
    /// decision 2's "an import can run twice" still holds.
    ///
    /// Three limits, each deliberate:
    /// - **Same archived state only.** An active and an archived tag may share a slug — both tag
    ///   editors draw that case — and only the active one is in a picker, so they are not the
    ///   duplicate the user sees. Folding one into the other would also decide whether the user's
    ///   tag is archived, which is the call [[T-528]] refused to let a merge make.
    /// - **Never onto a row the archive also carries by id.** That row is about to be matched by
    ///   its own record, which in overwrite mode may rename it; aliasing a second record onto it
    ///   would hang that record's tasks on whatever name it ends with. Such a record is inserted,
    ///   as before.
    /// - **Never between two archive records.** An archive that already holds two `bug` rows is
    ///   restored as it was written; repairing the archive's own shape is not this importer's call.
    ///   So a destination row takes at most one archive record: of two unmatched records with its
    ///   slug, only the first is aliased onto it and the other is inserted under its own id, and
    ///   the store ends with the archive's two rows rather than one.
    ///
    /// When several destination rows qualify, the lowest `order`, then the oldest, then the
    /// smallest id wins, and the same rule picks among several archive records for one row —
    /// deterministic, and independent of the file's own order, so the preview and the write name
    /// the same pairs.
    private nonisolated static func tagAliases(
        _ archive: CadenceArchive,
        against destination: DestinationIndex
    ) -> [UUID: Tag] {
        func key(slug: String, name: String, isArchived: Bool) -> String {
            "\(isArchived ? "archived" : "active")|\(TagSupport.stableSlug(storedSlug: slug, name: name))"
        }
        let archiveIDs = Set(archive.tags.map(\.id))
        var candidates: [String: Tag] = [:]
        for tag in destination.tags.values where !archiveIDs.contains(tag.id) {
            let slot = key(slug: tag.slug, name: tag.name, isArchived: tag.isArchived)
            if let current = candidates[slot], !Self.tagPrecedes(tag, current) { continue }
            candidates[slot] = tag
        }
        guard !candidates.isEmpty else { return [:] }
        // One archive record per destination row. Two unmatched archive records sharing a slot
        // are two rows the archive was written with, so only the first in `archiveTagPrecedes`
        // order is that row here; the other is inserted under its own id, as before [[T-3110]].
        var claimed: Set<UUID> = []
        var aliases: [UUID: Tag] = [:]
        let unmatched = archive.tags
            .filter { destination.tags[$0.id] == nil }
            .sorted(by: Self.archiveTagPrecedes)
        for record in unmatched {
            if let target = candidates[key(slug: record.slug, name: record.name, isArchived: record.isArchived)],
               claimed.insert(target.id).inserted {
                aliases[record.id] = target
            }
        }
        return aliases
    }

    // MARK: - Daily notes that are already here under another id

    /// Each archive **daily** note that is logically a note the destination already holds for the
    /// same day, mapped to that destination row ([[T-3146]]).
    ///
    /// **Why a daily note, like a tag, is matched on more than its id.** A daily note's identity is
    /// its day, not its UUID: `Note.canonicalKey` says so, `DataIntegrityRepairService`'s
    /// `repairDuplicateNotes` groups on it, and the app mints at most one daily note per date key.
    /// The import was the writer that could produce a second one — the file's own documented
    /// restore route is reset, then import, and the app makes today's daily note from the template
    /// the moment the user opens the day in between. The archive's note for that date then arrived
    /// under its own id, and the next launch's repair glued the two bodies together with
    /// `mergeNoteFields`' `\n\n---\n\n` rule, because the template body is not empty. What the
    /// user saw was their restored day with the template stapled above it.
    ///
    /// **Matched, not merged afterwards**, for the reasons `tagAliases` gives: an import deletes
    /// nothing, and matching lets each mode keep its own meaning — merge leaves the note already
    /// here exactly as it is, overwrite replaces its fields with the archive's copy, and neither
    /// deletes or re-ids anything. Re-running the import finds the same match.
    ///
    /// **All three shared-key kinds** ([[T-4720]]). The owner's decision of 2026-10-22 named daily
    /// notes and this matched `.daily` alone; the owner's decision of 2026-10-24 took the larger of
    /// the two options and extended it to weekly and meeting notes, declining a "weekly only"
    /// middle. The three are the three `Note.canonicalKey` gives a *shared* identity to —
    /// `daily:<dateKey>`, `weekly:<weekKey>` and `meeting:<calendarEventID>` — and
    /// `repairDuplicateNotes` groups on all three, so `mergeNoteFields` glued two non-empty bodies
    /// with `\n\n---\n\n` for any of them, not just for days. `.permanent` and `.list` key on
    /// their own UUID, have no shared identity to collide on, and are not aliased here.
    ///
    /// Each kind's key field is the one `canonicalKey` reads for it, which is why this asks the
    /// record for all three and lets `canonicalKey` pick: a meeting note keys on
    /// `calendarEventID`, not on `dateKey`, and a single `dateKey` parameter would have silently
    /// keyed every meeting note as the dateless fallback and aliased nothing.
    ///
    /// **What merge mode now does with the archive's copy**, which the glue used to hide: nothing.
    /// A matched row is a row merge leaves exactly as it is, so the body the archive carries for
    /// that day is not imported, where before it arrived stapled under a `---`. That is merge
    /// doing what its own sentence says and what it does for every other matched row, the preview
    /// counts the note as already here rather than as an insert, and overwrite is the mode that
    /// takes the archive's copy. [[T-4721]] records it as a consequence the owner has not ruled on.
    ///
    /// The three limits are the tag ones, and for the same reasons: a row the archive also carries
    /// by id is never aliased onto (its own record is about to match it), no two archive records
    /// share one destination row, and a note with no date key has no shared identity to collide on
    /// so it is skipped outright. Among several candidates the lowest `order`, then the oldest,
    /// then the smallest id wins, so the preview and the write name the same pairs.
    private nonisolated static func sharedKeyNoteAliases(
        _ archive: CadenceArchive,
        against destination: DestinationIndex
    ) -> [UUID: Note] {
        // Asked of `Note.canonicalKey` rather than spelled `"daily:\(dateKey)"` here, so the one
        // rule that decides whether two notes are the same note cannot drift into two. The `id`
        // argument is the per-note fallback that only a *keyless* row of a shared kind reaches,
        // and `sharedKey`'s own guard rejects those before asking — one placeholder serves every
        // call. The guard is on the kind's *own* key field, so an empty one is skipped the way a
        // dateless daily note was: it has no shared identity to collide on.
        let keyPlaceholder = UUID()
        func sharedKey(kindRaw: String, dateKey: String, weekKey: String, calendarEventID: String) -> String? {
            func present(_ value: String) -> Bool {
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard let kind = NoteKind(rawValue: kindRaw) else { return nil }
            switch kind {
            case .daily: guard present(dateKey) else { return nil }
            case .weekly: guard present(weekKey) else { return nil }
            case .meeting: guard present(calendarEventID) else { return nil }
            case .permanent, .list: return nil
            }
            return Note.canonicalKey(
                kind: kind,
                dateKey: dateKey,
                weekKey: weekKey,
                calendarEventID: calendarEventID,
                id: keyPlaceholder
            )
        }
        let archiveIDs = Set(archive.notes.map(\.id))
        var candidates: [String: Note] = [:]
        for note in destination.notes.values where !archiveIDs.contains(note.id) {
            guard let slot = sharedKey(
                kindRaw: note.kindRaw,
                dateKey: note.dateKey,
                weekKey: note.weekKey,
                calendarEventID: note.calendarEventID
            ) else { continue }
            if let current = candidates[slot], !Self.notePrecedes(note, current) { continue }
            candidates[slot] = note
        }
        guard !candidates.isEmpty else { return [:] }
        var claimed: Set<UUID> = []
        var aliases: [UUID: Note] = [:]
        let unmatched = archive.notes
            .filter { destination.notes[$0.id] == nil }
            .sorted(by: Self.archiveNotePrecedes)
        for record in unmatched {
            guard let slot = sharedKey(
                      kindRaw: record.kindRaw,
                      dateKey: record.dateKey,
                      weekKey: record.weekKey,
                      calendarEventID: record.calendarEventID
                  ),
                  let target = candidates[slot],
                  claimed.insert(target.id).inserted
            else { continue }
            aliases[record.id] = target
        }
        return aliases
    }

    /// `[[note:<archive id>|…]]` -> `[[note:<destination id>|…]]` for every note this import
    /// matched under another id ([[T-3146]], widened to all three shared-key kinds by [[T-4720]]).
    ///
    /// An aliased note keeps the destination's id, so a reference the archive wrote to its own copy
    /// names a row this store will never hold, and an id-named reference resolves to its row or to
    /// **nothing** (`NoteReferenceTarget`) — it would simply go dead. Before this matching existed
    /// the archive's note was inserted under its own id and the next launch's repair merged the
    /// pair and re-pointed the references (`DataIntegrityRepairService.redirectNoteReferences`,
    /// [[T-3115]] part 3); matching removes that merge, so the import has to do the re-pointing the
    /// merge used to do.
    ///
    /// **Scope is the repair's own scope**: `Note.content` and `AppTask.notes`, the two markdown
    /// fields `redirectNoteReferences` rewrites. The legacy tables are not re-pointed there and are
    /// not re-pointed here.
    private nonisolated static func aliasedNoteReferenceRedirects(_ aliases: [UUID: Note]) -> [UUID: UUID] {
        var redirects: [UUID: UUID] = [:]
        for (recordID, note) in aliases where recordID != note.id {
            redirects[recordID] = note.id
        }
        return redirects
    }

    /// `NoteReferenceParser.redirectingNoteReferences` with the count dropped — the importer
    /// reports rows, not references, and the helper already short-circuits an empty map.
    private nonisolated static func redirectingNoteReferences(
        in content: String,
        _ redirects: [UUID: UUID]
    ) -> String {
        NoteReferenceParser.redirectingNoteReferences(in: content, redirects: redirects).content
    }

    /// `archiveTagPrecedes` for note records.
    private nonisolated static func archiveNotePrecedes(_ lhs: CadenceArchiveNote, _ rhs: CadenceArchiveNote) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func notePrecedes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// `tagPrecedes` for archive records, so which of two same-slug records takes the row already
    /// here does not depend on the order the file happens to list them in.
    private nonisolated static func archiveTagPrecedes(_ lhs: CadenceArchiveTag, _ rhs: CadenceArchiveTag) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func tagPrecedes(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// A record's tag ids as the destination's rows, each once. An aliased archive tag and the
    /// destination tag it names are one row, so a task carrying both must not carry it twice.
    private nonisolated static func resolvedTags(_ ids: [UUID], in tags: [UUID: Tag]) -> [Tag] {
        var seen: Set<ObjectIdentifier> = []
        return ids.compactMap { tags[$0] }.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// The same translation for the preview, which compares ids rather than rows.
    private nonisolated static func aliasedTagIDs(_ ids: [UUID], _ aliases: [UUID: Tag]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.map { aliases[$0]?.id ?? $0 }.filter { seen.insert($0).inserted }
    }

    // MARK: - Writing

    /// Pass one: every row, as itself. Relationships are left alone here because a row's target may
    /// be later in the same document — the whole reason the archive is flat tables of ids rather
    /// than a nested tree.
    private nonisolated static func write(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode,
        into destination: inout DestinationIndex,
        tally: inout Tally,
        in modelContext: ModelContext
    ) -> WiringWorklist {
        var worklist = WiringWorklist()
        // Computed before anything is inserted, for the reason `aliasedTags` is: the preview and
        // the write must name the same pairs ([[T-3146]]). It is read first because the task table
        // below already needs `noteReferenceRedirects`.
        let aliasedSharedKeyNotes = sharedKeyNoteAliases(archive, against: destination)
        let noteReferenceRedirects = aliasedNoteReferenceRedirects(aliasedSharedKeyNotes)

        _ = upsert(
            archive.contexts, into: &destination.contexts,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Context(name: "") },
            fields: { record, model in
                model.id = record.id
                model.name = record.name
                model.colorHex = record.colorHex
                model.icon = record.icon
                model.order = record.order
                model.isArchived = record.isArchived
            }
        )

        worklist.areas = upsert(
            archive.areas, into: &destination.areas,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Area(name: "") },
            fields: { record, model in
                model.id = record.id
                model.name = record.name
                model.desc = record.desc
                model.statusRaw = record.statusRaw
                model.colorHex = record.colorHex
                model.icon = record.icon
                model.order = record.order
                model.linkedCalendarID = record.linkedCalendarID
                model.loggedMinutes = raisedFocusCounter(alreadyHere: model.loggedMinutes, inArchive: record.loggedMinutes)
                model.hideDueDateIfEmpty = record.hideDueDateIfEmpty
                model.hideSectionDueDateIfEmpty = record.hideSectionDueDateIfEmpty
                model.sectionNamesRaw = record.sectionNamesRaw
                model.sectionConfigsRaw = record.sectionConfigsRaw
            }
        )

        worklist.projects = upsert(
            archive.projects, into: &destination.projects,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Project(name: "") },
            fields: { record, model in
                model.id = record.id
                model.name = record.name
                model.desc = record.desc
                model.statusRaw = record.statusRaw
                model.colorHex = record.colorHex
                model.icon = record.icon
                model.dueDate = record.dueDate
                model.order = record.order
                model.linkedCalendarID = record.linkedCalendarID
                model.loggedMinutes = raisedFocusCounter(alreadyHere: model.loggedMinutes, inArchive: record.loggedMinutes)
                model.hideDueDateIfEmpty = record.hideDueDateIfEmpty
                model.hideSectionDueDateIfEmpty = record.hideSectionDueDateIfEmpty
                model.sectionNamesRaw = record.sectionNamesRaw
                model.sectionConfigsRaw = record.sectionConfigsRaw
            }
        )

        worklist.pursuits = upsert(
            archive.pursuits, into: &destination.pursuits,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Pursuit(title: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.desc = record.desc
                model.icon = record.icon
                model.colorHex = record.colorHex
                model.kindRaw = record.kindRaw
                model.statusRaw = record.statusRaw
                model.order = record.order
                model.createdAt = record.createdAt
            }
        )

        // Computed before the upsert below inserts anything, so it reads exactly the destination
        // `makePlan` read and the preview and the write agree on every aliased row.
        let aliasedTags = tagAliases(archive, against: destination)
        func copyTagFields(_ record: CadenceArchiveTag, onto model: Tag) {
            // The stored `slug`, not `TagSupport.slug(for:)` recomputed. `Tag.init` derives a
            // slug from the name, and a restore must return the row the user had rather than
            // the row today's derivation would produce.
            model.slug = record.slug
            model.name = record.name
            model.desc = record.desc
            model.colorHex = record.colorHex
            model.order = record.order
            model.isArchived = record.isArchived
            model.createdAt = record.createdAt
            model.updatedAt = record.updatedAt
        }
        _ = upsert(
            archive.tags.filter { aliasedTags[$0.id] == nil }, into: &destination.tags,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Tag(name: "") },
            fields: { record, model in
                model.id = record.id
                copyTagFields(record, onto: model)
            }
        )
        // [[T-3110]]: an archive tag that is the same tag as one already here — same stable slug,
        // same archived state, under another id — is that row, not a second one beside it. Each
        // mode then does to it what it does to any matched row, except that the destination's id
        // is kept: other rows and other devices already point at it. Registering the alias is what
        // makes `wire` hang the archive's tasks and notes on the existing tag.
        for record in archive.tags {
            guard let existing = aliasedTags[record.id] else { continue }
            switch mode {
            case .mergeKeepingExistingRows:
                tally.skipped += 1
            case .restoreOverwritingExistingRows:
                copyTagFields(record, onto: existing)
                tally.overwritten += 1
            }
            destination.tags[record.id] = existing
        }

        _ = upsert(
            archive.taskBundles, into: &destination.taskBundles,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in
                TaskBundle(
                    title: record.title,
                    dateKey: record.dateKey,
                    startMin: record.startMin,
                    durationMinutes: record.durationMinutes
                )
            },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.dateKey = record.dateKey
                model.startMin = record.startMin
                model.durationMinutes = record.durationMinutes
                model.createdAt = record.createdAt
            }
        )

        worklist.goals = upsert(
            archive.goals, into: &destination.goals,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Goal(title: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.desc = record.desc
                model.startDate = record.startDate
                model.endDate = record.endDate
                model.progressTypeRaw = record.progressTypeRaw
                model.targetHours = record.targetHours
                model.loggedHours = record.loggedHours
                model.colorHex = record.colorHex
                model.icon = record.icon
                model.statusRaw = record.statusRaw
                model.kindRaw = record.kindRaw
                model.order = record.order
                model.createdAt = record.createdAt
                model.dependsOnGoalIDsJSON = record.dependsOnGoalIDsJSON
            }
        )

        worklist.tasks = upsert(
            archive.tasks, into: &destination.tasks,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in AppTask(title: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.notes = redirectingNoteReferences(in: record.notes, noteReferenceRedirects)
                model.priorityRaw = record.priorityRaw
                model.statusRaw = record.statusRaw
                model.dueDate = record.dueDate
                model.scheduledDate = record.scheduledDate
                model.scheduledStartMin = record.scheduledStartMin
                model.estimatedMinutes = record.estimatedMinutes
                model.actualMinutes = raisedFocusCounter(alreadyHere: model.actualMinutes, inArchive: record.actualMinutes)
                model.calendarEventID = record.calendarEventID
                model.recurrenceRaw = record.recurrenceRaw
                model.recurrenceSeriesIDRaw = record.recurrenceSeriesIDRaw
                model.recurrenceSourceTaskIDRaw = record.recurrenceSourceTaskIDRaw
                model.recurrenceSpawnedTaskIDRaw = record.recurrenceSpawnedTaskIDRaw
                model.recurrenceOccurrenceIndex = record.recurrenceOccurrenceIndex
                model.recurrenceEndModeRaw = record.recurrenceEndModeRaw
                model.recurrenceEndDate = record.recurrenceEndDate
                model.recurrenceEndCount = record.recurrenceEndCount
                model.sectionName = record.sectionName
                model.order = record.order
                model.bundleOrder = record.bundleOrder
                model.createdAt = record.createdAt
                model.completedAt = record.completedAt
            }
        )

        worklist.focusSessions = upsert(
            archive.focusSessions, into: &destination.focusSessions,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in
                FocusSessionLog(
                    minutes: record.minutes,
                    previousMinutes: record.previousMinutes,
                    loggedAt: record.loggedAt,
                    dayKey: record.dayKey
                )
            },
            fields: { record, model in
                model.id = record.id
                model.minutes = record.minutes
                model.previousMinutes = record.previousMinutes
                model.loggedAt = record.loggedAt
                model.dayKey = record.dayKey
            }
        )

        worklist.subtasks = upsert(
            archive.subtasks, into: &destination.subtasks,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Subtask(title: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.isDone = record.isDone
                model.order = record.order
                model.createdAt = record.createdAt
            }
        )

        func copyNoteFields(_ record: CadenceArchiveNote, onto model: Note) {
            model.kindRaw = record.kindRaw
            model.title = record.title
            model.content = redirectingNoteReferences(in: record.content, noteReferenceRedirects)
            model.order = record.order
            model.createdAt = record.createdAt
            model.updatedAt = record.updatedAt
            model.dateKey = record.dateKey
            model.weekKey = record.weekKey
            model.calendarEventID = record.calendarEventID
            model.calendarID = record.calendarID
            model.eventDateKey = record.eventDateKey
            model.eventStartMin = record.eventStartMin
            model.eventEndMin = record.eventEndMin
            model.legacySourceKindRaw = record.legacySourceKindRaw
            model.legacySourceID = record.legacySourceID
            // Through the shared filing helper, not `model.folderPath = record.folderPath`.
            // The folder convention is a convention over a `String`, and it survives only
            // because exactly one normalizer writes it (`CadenceNoteFolderSupport.swift`) —
            // an archive is the one source of paths that has not already been through it.
            // Idempotent on anything Cadence wrote, so a real round trip is unchanged; a
            // hand-edited `"/Planning/"` is filed under `Planning` rather than becoming a
            // third group no surface can merge with the other two.
            //
            // The non-committing door, and the only caller of it (T-1093). Every interactive
            // filing goes through `CadenceListNoteFiling.move(_:toFolder:in:commit:)`, which
            // commits; an import commits once for the whole archive, in `apply` below, so a
            // per-note `save()` here would be hundreds of commits and a half-written store on
            // the first refusal.
            CadenceListNoteFiling.fileWithoutCommitting(model, toFolder: record.folderPath)
        }
        worklist.notes = upsert(
            archive.notes.filter { aliasedSharedKeyNotes[$0.id] == nil }, into: &destination.notes,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Note(kind: .list) },
            fields: { record, model in
                model.id = record.id
                copyNoteFields(record, onto: model)
            }
        )
        // [[T-3146]], widened by [[T-4720]]: an archive note whose shared key this store already
        // holds a note under — the same day, the same week, the same calendar event — is that
        // note, not a second one beside it. Same shape as the tag alias above — the
        // destination's id is kept, each mode then does what it does to any matched row, and
        // overwrite's pair joins the wiring worklist so the archive's area, project and tags land
        // on the row that survived.
        for record in archive.notes {
            guard let existing = aliasedSharedKeyNotes[record.id] else { continue }
            switch mode {
            case .mergeKeepingExistingRows:
                tally.skipped += 1
            case .restoreOverwritingExistingRows:
                copyNoteFields(record, onto: existing)
                tally.overwritten += 1
                worklist.notes.append((record, existing))
            }
            destination.notes[record.id] = existing
        }

        // No wiring pass: the layout references nothing but destination raw values, which are
        // strings this build either recognises or drops when it reads them.
        _ = upsert(
            archive.sidebarLayoutPreferenceRecords, into: &destination.sidebarLayoutPreferences,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in SidebarLayoutPreference() },
            fields: { record, model in
                model.id = record.id
                model.orderRaw = record.orderRaw
                model.hiddenRaw = record.hiddenRaw
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        // Nor here: the look references nothing but its own strings, and a pair this build has no
        // reader for is carried verbatim rather than interpreted — the same rule
        // `CadenceLookPreferenceStore.publishedPairs` applies on a live device.
        _ = upsert(
            archive.lookPreferenceRecords, into: &destination.lookPreferences,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in LookPreference() },
            fields: { record, model in
                model.id = record.id
                model.accentPaletteID = record.accentPaletteID
                model.sidebarTabColorsRaw = record.sidebarTabColorsRaw
                model.taskPresentationRaw = record.taskPresentationRaw
                // [[T-3116]] part (4): an archive written before [[T-1347]] has no calendar field at
                // all, which says nothing about the user's calendar settings — it does not say
                // "none". So a missing field leaves the row's own value: the model default on an
                // insert, and the destination's pairs on an overwrite, which used to blank them.
                // A field that is present, even empty, is the archive's copy and is written.
                if let calendarPresentationRaw = record.calendarPresentationRaw {
                    model.calendarPresentationRaw = calendarPresentationRaw
                }
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        // Nor here: the template overrides reference nothing but their own JSON, and a template id
        // this build has no stencil for is carried verbatim rather than interpreted — the same rule
        // `NoteTemplateLibrary.setOverride` applies on a live device, where it leaves keys it does
        // not recognise alone.
        _ = upsert(
            archive.noteTemplatePreferenceRecords, into: &destination.noteTemplatePreferences,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in NoteTemplatePreference() },
            fields: { record, model in
                model.id = record.id
                model.overridesRaw = record.overridesRaw
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        worklist.savedLinks = upsert(
            archive.savedLinks, into: &destination.savedLinks,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in SavedLink(title: "", url: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.url = importedSavedLinkURL(record.url)
                model.order = record.order
                model.createdAt = record.createdAt
            }
        )

        _ = upsert(
            archive.markdownImageAssets,
            into: &destination.markdownImageAssets,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in
                MarkdownImageAsset(
                    data: record.data,
                    mimeType: record.mimeType,
                    pixelWidth: record.pixelWidth,
                    pixelHeight: record.pixelHeight,
                    displayWidth: record.displayWidth
                )
            },
            fields: { record, model in
                model.id = record.id
                model.data = record.data
                model.mimeType = record.mimeType
                model.originalFilename = record.originalFilename
                model.altText = record.altText
                model.pixelWidth = record.pixelWidth
                model.pixelHeight = record.pixelHeight
                model.displayWidth = record.displayWidth
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        worklist.goalListLinks = upsert(
            archive.goalListLinks, into: &destination.goalListLinks,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in GoalListLink() },
            fields: { record, model in
                model.id = record.id
                model.createdAt = record.createdAt
            }
        )

        worklist.habits = upsert(
            archive.habits, into: &destination.habits,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Habit(title: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.icon = record.icon
                model.colorHex = record.colorHex
                model.frequencyTypeRaw = record.frequencyTypeRaw
                model.frequencyDaysRaw = record.frequencyDaysRaw
                model.targetCount = record.targetCount
                model.order = record.order
                model.createdAt = record.createdAt
                model.reminderMinuteOfDay = record.reminderMinuteOfDay
            }
        )

        worklist.habitCompletions = upsert(
            archive.habitCompletions,
            into: &destination.habitCompletions,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in HabitCompletion(date: record.date) },
            fields: { record, model in
                model.id = record.id
                model.date = record.date
                model.count = record.count
                model.createdAt = record.createdAt
            }
        )

        _ = upsert(
            archive.legacyDailyNotes, into: &destination.legacyDailyNotes,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in DailyNote(date: record.date) },
            fields: { record, model in
                model.id = record.id
                model.date = record.date
                model.content = record.content
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        _ = upsert(
            archive.legacyWeeklyNotes, into: &destination.legacyWeeklyNotes,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in WeeklyNote(weekKey: record.weekKey) },
            fields: { record, model in
                model.id = record.id
                model.weekKey = record.weekKey
                model.content = record.content
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        _ = upsert(
            archive.legacyPermNotes, into: &destination.legacyPermNotes,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in PermNote() },
            fields: { record, model in
                model.id = record.id
                model.content = record.content
                model.updatedAt = record.updatedAt
            }
        )

        _ = upsert(
            archive.legacyEventNotes, into: &destination.legacyEventNotes,
            mode: mode, tally: &tally, in: modelContext,
            make: { record in
                EventNote(calendarEventID: record.calendarEventID, eventTitle: record.title)
            },
            fields: { record, model in
                model.id = record.id
                model.calendarEventID = record.calendarEventID
                model.calendarID = record.calendarID
                model.title = record.title
                model.content = record.content
                model.eventDateKey = record.eventDateKey
                model.eventStartMin = record.eventStartMin
                model.eventEndMin = record.eventEndMin
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        worklist.legacyDocuments = upsert(
            archive.legacyDocuments, into: &destination.legacyDocuments,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Document() },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.content = record.content
                model.order = record.order
                model.createdAt = record.createdAt
                model.updatedAt = record.updatedAt
            }
        )

        return worklist
    }

    /// Pass two: the graph.
    ///
    /// Every reference here was proved resolvable by `validate(_:against:)`, so a `nil` lookup at
    /// this point would be a bug in this file rather than bad input — which is why these read as
    /// plain dictionary lookups and not as another layer of guards.
    ///
    /// Only the to-one side is written. `Cadence/Models/AGENTS.md` measured that SwiftData
    /// back-populates the inverse array synchronously inside the owning context (T-387), and the
    /// hand-severing rule there is about *deletes*, which an import never performs.
    private nonisolated static func wire(
        _ worklist: WiringWorklist,
        using destination: DestinationIndex
    ) {
        for (record, model) in worklist.areas {
            model.context = record.contextID.flatMap { destination.contexts[$0] }
        }
        for (record, model) in worklist.projects {
            model.context = record.contextID.flatMap { destination.contexts[$0] }
            model.area = record.areaID.flatMap { destination.areas[$0] }
        }
        for (record, model) in worklist.pursuits {
            model.context = record.contextID.flatMap { destination.contexts[$0] }
        }
        for (record, model) in worklist.goals {
            model.context = record.contextID.flatMap { destination.contexts[$0] }
            model.pursuit = record.pursuitID.flatMap { destination.pursuits[$0] }
            model.parentGoal = record.parentGoalID.flatMap { destination.goals[$0] }
        }
        for (record, model) in worklist.tasks {
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
            model.goal = record.goalID.flatMap { destination.goals[$0] }
            model.context = record.contextID.flatMap { destination.contexts[$0] }
            model.bundle = record.bundleID.flatMap { destination.taskBundles[$0] }
            model.tags = resolvedTags(record.tagIDs, in: destination.tags)
        }
        for (record, model) in worklist.focusSessions {
            model.task = record.taskID.flatMap { destination.tasks[$0] }
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
        }
        for (record, model) in worklist.subtasks {
            model.parentTask = record.parentTaskID.flatMap { destination.tasks[$0] }
        }
        for (record, model) in worklist.notes {
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
            model.tags = resolvedTags(record.tagIDs, in: destination.tags)
        }
        for (record, model) in worklist.savedLinks {
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
        }
        for (record, model) in worklist.goalListLinks {
            model.goal = record.goalID.flatMap { destination.goals[$0] }
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
        }
        for (record, model) in worklist.habits {
            model.context = record.contextID.flatMap { destination.contexts[$0] }
            model.pursuit = record.pursuitID.flatMap { destination.pursuits[$0] }
            model.goal = record.goalID.flatMap { destination.goals[$0] }
        }
        for (record, model) in worklist.habitCompletions {
            model.habit = record.habitID.flatMap { destination.habits[$0] }
        }
        for (record, model) in worklist.legacyDocuments {
            model.area = record.areaID.flatMap { destination.areas[$0] }
            model.project = record.projectID.flatMap { destination.projects[$0] }
        }
    }

    /// Pass three: raise the focus counters the restored session rows have just made too low.
    ///
    /// **Why an import has to do this at all** ([[T-1114]]). `AppTask.actualMinutes`,
    /// `Area.loggedMinutes` and `Project.loggedMinutes` are cached scalars over `FocusSessionLog`
    /// rows, not independent facts — `FocusSessionLog`'s own note says so and
    /// `CadenceFocusLedger.reconcile(in:)` is the rule. An import is the one writer that can add a
    /// subject's rows without touching the subject: in merge mode a matched task keeps the
    /// destination's copy, sessions it does not have are inserted beside it, and the counter is
    /// left at the number it held before those sessions existed. A destination task reading 10
    /// with one `(previousMinutes: 0, minutes: 10)` row, given an archive's second
    /// `(previousMinutes: 10, minutes: 20)` row, holds 10 while its own ledger says 30 — and
    /// nothing re-runs the ledger, whose only scheduled caller is
    /// `PersistenceController.performStartupMaintenance`. The minutes would come back at the next
    /// launch. Until then a restore has visibly restored less than it restored, and an hours-mode
    /// `Goal` reading `actualMinutes` is reading the low number.
    ///
    /// **In the transaction, not in the post-commit seam.** [[T-1112]] gave the *flow* a
    /// post-commit effect, but that one exists to reconcile the OS's pending reminders — work that
    /// is outside the store and must happen after the rows are durable. This is inside the store,
    /// and a counter that disagrees with its rows should never be committed in the first place:
    /// running here makes the raise part of the same `save()` as the rows that caused it, so there
    /// is no window and no second commit to fail on its own. It is also below `importArchive`
    /// rather than beside it, so a caller reaching for `apply` directly gets it too.
    ///
    /// **The rows come from the index, so no fetch can fail here.**
    /// `CadenceFocusLedger.reconcile(in:)` swallows a failed fetch and answers `false`, which would
    /// read as "the counters were already right"; `reconcile(rows:)` takes what `DestinationIndex`
    /// already holds — the destination's rows, fetched before the first insert, plus every row this
    /// import inserted. Wiring must have happened first: a row whose subject is still `nil`
    /// belongs to no counter.
    ///
    /// Only raising is what makes this safe in **both** modes. Overwrite mode writes the archive's
    /// scalar over the destination's, and that scalar can be older than sessions this device
    /// logged since; the raise puts those minutes back rather than letting the archive's number
    /// stand against the store's own rows. It cannot put back minutes that have no rows at all,
    /// which is why `raisedFocusCounter` below has to run first.
    private nonisolated static func reconcileFocusCounters(using destination: DestinationIndex) {
        CadenceFocusLedger.reconcile(rows: Array(destination.focusSessions.values))
    }

    /// What a matched row's focus counter becomes: **the higher of the two, never the archive's
    /// alone** ([[T-3145]]).
    ///
    /// `reconcileFocusCounters` above raises a counter back to the sum of the `FocusSessionLog`
    /// rows behind it. A counter with **no** rows behind it — minutes banked before the ledger
    /// existed — has nothing to be raised back to, so overwrite writing the archive's scalar over
    /// it lowered it permanently and the next launch could not put it back. [[T-1114]] recorded
    /// that as overwrite doing what it says; the owner reversed that on 2026-10-22, and this is
    /// the reversal.
    ///
    /// **It invents no data.** Every app write to these three counters only ever raises them
    /// (`CadenceFocusLedger`), and `DataIntegrityRepairService` already folds two copies of a
    /// container together with `max` — so `max` is the rule the rest of the store already keeps,
    /// and the number that survives is one of the two numbers that were really there.
    ///
    /// Called from inside each `fields` closure, so `alreadyHere` is the destination's **pre-import**
    /// value: `upsert` hands a matched row to `fields` before anything on it is written, and a row
    /// it just inserted holds the model default of `0`, for which this returns the archive's figure
    /// unchanged. Merge mode never reaches it for a matched row at all — it skips those.
    private nonisolated static func raisedFocusCounter(alreadyHere: Int, inArchive: Int) -> Int {
        max(alreadyHere, inArchive)
    }

    /// One table. Returns the rows pass two still has to wire — always the ones just inserted, and
    /// in `.restoreOverwritingExistingRows` the matched ones too, because overwriting a row's
    /// fields and leaving its old relationships would produce a row that is neither copy.
    private nonisolated static func upsert<Record: Identifiable, Model: PersistentModel>(
        _ records: [Record],
        into existing: inout [UUID: Model],
        mode: CadenceArchiveImportMode,
        tally: inout Tally,
        in modelContext: ModelContext,
        make: (Record) -> Model,
        fields: (Record, Model) -> Void
    ) -> [(Record, Model)] where Record.ID == UUID {
        var wired: [(Record, Model)] = []
        for record in records {
            if let model = existing[record.id] {
                switch mode {
                case .mergeKeepingExistingRows:
                    tally.skipped += 1
                case .restoreOverwritingExistingRows:
                    fields(record, model)
                    tally.overwritten += 1
                    wired.append((record, model))
                }
            } else {
                let model = make(record)
                fields(record, model)
                modelContext.insert(model)
                existing[record.id] = model
                tally.inserted += 1
                wired.append((record, model))
            }
        }
        return wired
    }

    // MARK: - Working state

    private struct Tally {
        var inserted = 0
        var overwritten = 0
        var skipped = 0
    }

    /// Rows pass two must wire, kept per table so the second pass is a set of typed loops rather
    /// than a bag of existentials.
    private struct WiringWorklist {
        var areas: [(CadenceArchiveArea, Area)] = []
        var projects: [(CadenceArchiveProject, Project)] = []
        var pursuits: [(CadenceArchivePursuit, Pursuit)] = []
        var goals: [(CadenceArchiveGoal, Goal)] = []
        var tasks: [(CadenceArchiveTask, AppTask)] = []
        var focusSessions: [(CadenceArchiveFocusSessionLog, FocusSessionLog)] = []
        var subtasks: [(CadenceArchiveSubtask, Subtask)] = []
        var notes: [(CadenceArchiveNote, Note)] = []
        var savedLinks: [(CadenceArchiveSavedLink, SavedLink)] = []
        var goalListLinks: [(CadenceArchiveGoalListLink, GoalListLink)] = []
        var habits: [(CadenceArchiveHabit, Habit)] = []
        var habitCompletions: [(CadenceArchiveHabitCompletion, HabitCompletion)] = []
        var legacyDocuments: [(CadenceArchiveLegacyDocument, Document)] = []
    }

    /// Every row already in the destination store, by id, per model.
    ///
    /// Fetched once. The alternative — a `FetchDescriptor` with an id predicate per record — is one
    /// query per row of the archive, which on a real store is thousands of round trips to decide
    /// something a single fetch already knows.
    private struct DestinationIndex {
        var contexts: [UUID: Context]
        var areas: [UUID: Area]
        var projects: [UUID: Project]
        var pursuits: [UUID: Pursuit]
        var tags: [UUID: Tag]
        var tasks: [UUID: AppTask]
        var taskBundles: [UUID: TaskBundle]
        var focusSessions: [UUID: FocusSessionLog]
        var subtasks: [UUID: Subtask]
        var notes: [UUID: Note]
        var savedLinks: [UUID: SavedLink]
        var markdownImageAssets: [UUID: MarkdownImageAsset]
        var goals: [UUID: Goal]
        var goalListLinks: [UUID: GoalListLink]
        var habits: [UUID: Habit]
        var habitCompletions: [UUID: HabitCompletion]
        var legacyDailyNotes: [UUID: DailyNote]
        var legacyWeeklyNotes: [UUID: WeeklyNote]
        var legacyPermNotes: [UUID: PermNote]
        var legacyEventNotes: [UUID: EventNote]
        var legacyDocuments: [UUID: Document]
        var sidebarLayoutPreferences: [UUID: SidebarLayoutPreference]
        var lookPreferences: [UUID: LookPreference]
        var noteTemplatePreferences: [UUID: NoteTemplatePreference]

        init(in modelContext: ModelContext) throws {
            contexts = try Self.index(Context.self, in: modelContext) { $0.id }
            areas = try Self.index(Area.self, in: modelContext) { $0.id }
            projects = try Self.index(Project.self, in: modelContext) { $0.id }
            pursuits = try Self.index(Pursuit.self, in: modelContext) { $0.id }
            tags = try Self.index(Tag.self, in: modelContext) { $0.id }
            tasks = try Self.index(AppTask.self, in: modelContext) { $0.id }
            taskBundles = try Self.index(TaskBundle.self, in: modelContext) { $0.id }
            focusSessions = try Self.index(FocusSessionLog.self, in: modelContext) { $0.id }
            subtasks = try Self.index(Subtask.self, in: modelContext) { $0.id }
            notes = try Self.index(Note.self, in: modelContext) { $0.id }
            savedLinks = try Self.index(SavedLink.self, in: modelContext) { $0.id }
            markdownImageAssets = try Self.index(MarkdownImageAsset.self, in: modelContext) { $0.id }
            goals = try Self.index(Goal.self, in: modelContext) { $0.id }
            goalListLinks = try Self.index(GoalListLink.self, in: modelContext) { $0.id }
            habits = try Self.index(Habit.self, in: modelContext) { $0.id }
            habitCompletions = try Self.index(HabitCompletion.self, in: modelContext) { $0.id }
            legacyDailyNotes = try Self.index(DailyNote.self, in: modelContext) { $0.id }
            legacyWeeklyNotes = try Self.index(WeeklyNote.self, in: modelContext) { $0.id }
            legacyPermNotes = try Self.index(PermNote.self, in: modelContext) { $0.id }
            legacyEventNotes = try Self.index(EventNote.self, in: modelContext) { $0.id }
            legacyDocuments = try Self.index(Document.self, in: modelContext) { $0.id }
            sidebarLayoutPreferences = try Self.index(SidebarLayoutPreference.self, in: modelContext) { $0.id }
            lookPreferences = try Self.index(LookPreference.self, in: modelContext) { $0.id }
            noteTemplatePreferences = try Self.index(NoteTemplatePreference.self, in: modelContext) { $0.id }
        }

        /// Keyed by the entity name `CadenceSchema` reports, so validation and the plan can talk
        /// about tables in the same vocabulary `CadenceArchive.recordCountsByEntityName` uses.
        var idsByEntityName: [String: Set<UUID>] {
            [
                "Context": Set(contexts.keys),
                "Area": Set(areas.keys),
                "Project": Set(projects.keys),
                "Pursuit": Set(pursuits.keys),
                "Tag": Set(tags.keys),
                "AppTask": Set(tasks.keys),
                "TaskBundle": Set(taskBundles.keys),
                "FocusSessionLog": Set(focusSessions.keys),
                "Subtask": Set(subtasks.keys),
                "Note": Set(notes.keys),
                "SavedLink": Set(savedLinks.keys),
                "MarkdownImageAsset": Set(markdownImageAssets.keys),
                "Goal": Set(goals.keys),
                "GoalListLink": Set(goalListLinks.keys),
                "Habit": Set(habits.keys),
                "HabitCompletion": Set(habitCompletions.keys),
                "DailyNote": Set(legacyDailyNotes.keys),
                "WeeklyNote": Set(legacyWeeklyNotes.keys),
                "PermNote": Set(legacyPermNotes.keys),
                "EventNote": Set(legacyEventNotes.keys),
                "Document": Set(legacyDocuments.keys),
                "SidebarLayoutPreference": Set(sidebarLayoutPreferences.keys),
                "LookPreference": Set(lookPreferences.keys),
                "NoteTemplatePreference": Set(noteTemplatePreferences.keys),
            ]
        }

        private static func index<Model: PersistentModel>(
            _ type: Model.Type,
            in modelContext: ModelContext,
            id: (Model) -> UUID
        ) throws -> [UUID: Model] {
            var index: [UUID: Model] = [:]
            for model in try modelContext.fetch(FetchDescriptor<Model>()) {
                index[id(model)] = model
            }
            return index
        }
    }
}

// MARK: - Mode

/// What happens to a row the archive carries that the destination store already has under the same
/// id. Neither mode deletes anything; they differ only in who wins a collision.
nonisolated enum CadenceArchiveImportMode: String, CaseIterable, Sendable {
    /// The destination's copy stays exactly as it is. Rows the store does not have are added.
    ///
    /// **The default**, and the reason is that this is the only mode that cannot destroy something
    /// the archive does not know about. A restore into an empty store — the case a backup exists
    /// for — behaves identically under both modes, so the default is chosen by what it does in the
    /// *other* case: merging a colleague's archive, or re-importing a months-old file after
    /// working normally since, must not silently revert today's edits to a row that happens to
    /// share an id.
    case mergeKeepingExistingRows

    /// The archive's copy wins: every field and every relationship of a matched row is overwritten.
    ///
    /// For a restore where the store has drifted and the archive is believed to be the good copy.
    /// It still deletes nothing, so a row added since the archive was written survives it.
    case restoreOverwritingExistingRows
}

// MARK: - Plan

/// What an import would do, before it does it.
///
/// Exists so a surface can show the user a count *and the mode's consequence* before writing, which
/// is the difference between a confirmation and an informed one. Counts are per entity name — the
/// same keys `CadenceArchive.recordCountsByEntityName` uses — so a screen can name the tables that
/// actually change rather than quoting one total.
nonisolated struct CadenceArchiveImportPlan: Equatable, Sendable {
    let mode: CadenceArchiveImportMode
    /// Rows in the archive whose id the destination store does not have. These are inserted under
    /// either mode.
    let insertCountsByEntityName: [String: Int]
    /// Rows in the archive whose id the destination store already has. `mode` decides whether these
    /// are left alone or overwritten; neither deletes them.
    let matchedCountsByEntityName: [String: Int]
    /// Entity names the archive's own header lists that this build's `CadenceSchema` does not have.
    ///
    /// Non-empty means the archive was written by a build that persisted something this one does
    /// not, so those rows cannot be restored here. It is reported rather than thrown because the
    /// rest of the document is still importable, and a refusal would strand the user's only copy of
    /// everything else.
    let entityNamesOnlyInTheArchive: [String]
    /// Lists in the archive that carry an Apple Calendar link.
    ///
    /// **T-1084.** `CadenceArchiveArea.linkedCalendarID` / `CadenceArchiveProject.linkedCalendarID`
    /// hold an `EKCalendar.calendarIdentifier`, which Apple documents as local to the device that
    /// issued it. An archive taken on one Mac and imported on another therefore restores lists
    /// pointing at a calendar the importing machine never issued. [[T-624]]'s evidence gate keeps
    /// that *inert* — such a link reads as `.unverified` rather than as a break with a repair
    /// beside it — so the whole of the exposure is that the user is not told, which is what
    /// `CadenceArchiveImportPresentation.calendarLinksNote` says in the preview.
    ///
    /// Counted over the archive rather than over the rows this mode would write, exactly as
    /// `entityNamesOnlyInTheArchive` is: the sentence is a fact about the file the reader chose,
    /// and both are worded that way.
    let linkedCalendarCount: Int

    /// Matched rows whose copy here is **not** the archive's copy ([[T-3111]]) — a subset of
    /// `matchedCountsByEntityName`, never added to it.
    ///
    /// The figure that tells a no-op re-import from a merge that declined to repair something: a
    /// task CloudKit stripped of its area and tags still matches by id, so merge counts it skipped
    /// and leaves the links gone. Compared today: `"AppTask"`, `"Area"`, `"Project"`, `"Subtask"`,
    /// `"Note"` and `"SavedLink"`, each by its own comparator in `CadenceArchiveImportService`
    /// (`matchedTaskDiffers`, `matchedNoteDiffers` and so on, [[T-3131]]); an absent key means *not compared*, not *identical*. Defaulted so a plan built
    /// without a store behind it reads as no differences.
    var differingMatchedCountsByEntityName: [String: Int] = [:]

    var totalInsertCount: Int { insertCountsByEntityName.values.reduce(0, +) }
    var totalMatchedCount: Int { matchedCountsByEntityName.values.reduce(0, +) }
    var totalDifferingMatchedCount: Int { differingMatchedCountsByEntityName.values.reduce(0, +) }

    /// Whether applying this plan would change the store at all. False for a second import of the
    /// same file in `.mergeKeepingExistingRows`, which is the idempotence a restore has to have.
    var changesAnything: Bool {
        totalInsertCount > 0 || (mode == .restoreOverwritingExistingRows && totalMatchedCount > 0)
    }
}

// MARK: - Outcome

/// One finished import, as counts the caller can put in a sentence.
///
/// **Every value of this type describes a committed import.** A refused one throws instead, so a
/// caller holding an outcome knows the archive is on disk — `legacyNoteFoldFailure` narrows that to
/// *which part* of the work is still outstanding rather than reopening the question of whether any
/// of it landed ([[T-1111]]).
nonisolated struct CadenceArchiveImportOutcome: Equatable, Sendable {
    let plan: CadenceArchiveImportPlan
    let insertedRecordCount: Int
    let overwrittenRecordCount: Int
    let skippedRecordCount: Int
    /// Legacy note rows this import folded into `Note` by running `NoteMigrationService`. Zero for
    /// an archive taken after that migration had already run on the exporting device.
    let notesFoldedFromLegacyRows: Int
    /// Why the post-commit legacy-note fold did not finish, or `nil` when it did.
    ///
    /// Carried as the message rather than the `Error` so the outcome stays `Equatable` and
    /// `Sendable` — a caller that wanted to branch on the error *kind* would be deciding whether
    /// the import landed, and it did.
    let legacyNoteFoldFailure: String?

    init(
        plan: CadenceArchiveImportPlan,
        insertedRecordCount: Int,
        overwrittenRecordCount: Int,
        skippedRecordCount: Int,
        notesFoldedFromLegacyRows: Int,
        legacyNoteFoldFailure: String? = nil
    ) {
        self.plan = plan
        self.insertedRecordCount = insertedRecordCount
        self.overwrittenRecordCount = overwrittenRecordCount
        self.skippedRecordCount = skippedRecordCount
        self.notesFoldedFromLegacyRows = notesFoldedFromLegacyRows
        self.legacyNoteFoldFailure = legacyNoteFoldFailure
    }

    /// The archive committed and every follow-up write it owns finished too.
    var isComplete: Bool { legacyNoteFoldFailure == nil }
}

// MARK: - Failure

/// Why an archive was refused. Every case names the row, because "the import failed" over a
/// four-thousand-row document tells the user nothing they can act on.
nonisolated enum CadenceArchiveImportFailure: LocalizedError, Equatable, Sendable {
    /// The file was written by a build whose archive shape this one does not know.
    case unsupportedFormatVersion(found: Int, readableUpTo: Int)
    /// Two rows in one table share an id. The exporter cannot produce this.
    case duplicateRecordID(table: String, id: UUID)
    /// A relationship names a row that is in neither the archive nor the destination store.
    case danglingReference(table: String, record: UUID, field: String, missing: UUID)
    /// A parent chain this import would write leads back to itself ([[T-1109]]). Every reference in
    /// it resolves, so the checks above pass; what it produces is a component with no root, which
    /// the Goals page has no way to draw. `cycle` starts at `record` and is in parent order.
    case parentCycle(table: String, record: UUID, field: String, cycle: [UUID])

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case let .unsupportedFormatVersion(found, readableUpTo):
            return """
                This archive is version \(found) and this version of Cadence can read up to \
                version \(readableUpTo). Update Cadence and try again.
                """
        case let .duplicateRecordID(table, id):
            return "This archive lists \(table) \(id.uuidString) twice, so it cannot be imported."
        case let .danglingReference(table, record, field, missing):
            return """
                \(table) \(record.uuidString) refers to \(missing.uuidString) in \(field), which is \
                in neither this archive nor your data. Nothing was imported.
                """
        case let .parentCycle(table, record, field, cycle):
            let chain = (cycle + [record]).map(\.uuidString).joined(separator: " -> ")
            return """
                \(table) \(record.uuidString) would end up as its own ancestor through \(field) \
                (\(chain)), so nothing in that chain could ever be shown. Nothing was imported.
                """
        }
    }
}

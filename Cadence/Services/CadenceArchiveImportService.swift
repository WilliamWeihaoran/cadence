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
/// means, and both answers are non-destructive at row level.
///
/// **3. CloudKit.** This writes through whatever store the caller's `ModelContext` belongs to. On
/// a synced device that means every inserted row is uploaded, so "restore my backup here" is
/// "push these rows at my other devices" from theirs. That is the correct behaviour for a restore
/// and it is why the write is arranged the way it is: **validation completes before the first
/// insert.** A malformed archive is refused having written nothing, so there is no such thing as a
/// half-uploaded rejected import. See `validate(_:against:)`.
///
/// **4. Partial failure.** Two failure classes, and they are answered differently rather than
/// hidden behind one word:
/// - *The archive is bad.* Unreadable JSON, a format version this build does not know, a repeated
///   id, or a reference to a row that exists neither in the archive nor in the destination — all
///   throw from `validate(_:against:)`, which runs to completion before anything is inserted. The
///   store is untouched and the thrown `CadenceArchiveImportFailure` names the table, the row and
///   the field.
/// - *The write itself fails.* `apply(_:mode:in:)` inserts and then commits once. If that commit
///   throws, it rolls the context back and rethrows, so the import leaves nothing pending for an
///   unrelated later `save()` to pick up. The caller must hand this a context it is willing to
///   have rolled back — `importArchive(_:mode:into:)` makes a private one for exactly that reason.
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

    /// Apply an archive to `modelContext` and commit once.
    ///
    /// The caller owns the unit of work and must be willing to have this context rolled back; see
    /// the type's note. Nothing is inserted until `validate(_:against:)` has returned.
    @discardableResult
    nonisolated static func apply(
        _ archive: CadenceArchive,
        mode: CadenceArchiveImportMode = .mergeKeepingExistingRows,
        in modelContext: ModelContext
    ) throws -> CadenceArchiveImportOutcome {
        var destination = try DestinationIndex(in: modelContext)
        let plan = try makePlan(archive, mode: mode, against: destination)

        var tally = Tally()
        let wired = write(archive, mode: mode, into: &destination, tally: &tally, in: modelContext)
        wire(wired, using: destination)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        // Fold any legacy note rows this import brought in that are not already represented by a
        // `Note`. Run after the commit above rather than inside it so the migration reads a
        // settled store, and with `saveChanges: true` so its own inserts are committed by the
        // service that made them. A failure here leaves the imported rows in place and the fold
        // undone, which the next launch repairs: `PersistenceController` runs the same migration.
        let migration = try NoteMigrationService.migrateIfNeeded(
            in: modelContext,
            source: "archive-import",
            saveChanges: true
        )

        return CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: tally.inserted,
            overwrittenRecordCount: tally.overwritten,
            skippedRecordCount: tally.skipped,
            notesFoldedFromLegacyRows: migration.insertedTotal
        )
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

        return archiveIDs
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
        let archiveIDs = try validate(archive, against: destination)
        let destinationIDs = destination.idsByEntityName

        var inserts: [String: Int] = [:]
        var matches: [String: Int] = [:]
        for (name, ids) in archiveIDs {
            let existing = destinationIDs[name] ?? []
            inserts[name] = ids.subtracting(existing).count
            matches[name] = ids.intersection(existing).count
        }

        let buildEntities = Set(CadenceSchema.schema.entities.map(\.name))
        return CadenceArchiveImportPlan(
            mode: mode,
            insertCountsByEntityName: inserts,
            matchedCountsByEntityName: matches,
            entityNamesOnlyInTheArchive: archive.schemaEntityNames
                .filter { !buildEntities.contains($0) }
                .sorted()
        )
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
                model.loggedMinutes = record.loggedMinutes
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
                model.loggedMinutes = record.loggedMinutes
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

        _ = upsert(
            archive.tags, into: &destination.tags,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Tag(name: "") },
            fields: { record, model in
                model.id = record.id
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
        )

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
                model.notes = record.notes
                model.priorityRaw = record.priorityRaw
                model.statusRaw = record.statusRaw
                model.dueDate = record.dueDate
                model.scheduledDate = record.scheduledDate
                model.scheduledStartMin = record.scheduledStartMin
                model.estimatedMinutes = record.estimatedMinutes
                model.actualMinutes = record.actualMinutes
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

        worklist.notes = upsert(
            archive.notes, into: &destination.notes,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in Note(kind: .list) },
            fields: { record, model in
                model.id = record.id
                model.kindRaw = record.kindRaw
                model.title = record.title
                model.content = record.content
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
        )

        worklist.savedLinks = upsert(
            archive.savedLinks, into: &destination.savedLinks,
            mode: mode, tally: &tally, in: modelContext,
            make: { _ in SavedLink(title: "", url: "") },
            fields: { record, model in
                model.id = record.id
                model.title = record.title
                model.url = record.url
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
            model.tags = record.tagIDs.compactMap { destination.tags[$0] }
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
            model.tags = record.tagIDs.compactMap { destination.tags[$0] }
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

    var totalInsertCount: Int { insertCountsByEntityName.values.reduce(0, +) }
    var totalMatchedCount: Int { matchedCountsByEntityName.values.reduce(0, +) }

    /// Whether applying this plan would change the store at all. False for a second import of the
    /// same file in `.mergeKeepingExistingRows`, which is the idempotence a restore has to have.
    var changesAnything: Bool {
        totalInsertCount > 0 || (mode == .restoreOverwritingExistingRows && totalMatchedCount > 0)
    }
}

// MARK: - Outcome

/// One finished import, as counts the caller can put in a sentence.
nonisolated struct CadenceArchiveImportOutcome: Equatable, Sendable {
    let plan: CadenceArchiveImportPlan
    let insertedRecordCount: Int
    let overwrittenRecordCount: Int
    let skippedRecordCount: Int
    /// Legacy note rows this import folded into `Note` by running `NoteMigrationService`. Zero for
    /// an archive taken after that migration had already run on the exporting device.
    let notesFoldedFromLegacyRows: Int
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
        }
    }
}

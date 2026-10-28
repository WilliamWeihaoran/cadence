import Foundation
import OSLog
import SwiftData

nonisolated struct DataIntegrityRepairReport: Codable, Equatable {
    var source: String
    var startedAt: Date
    var finishedAt: Date
    var success: Bool
    var errorMessage: String?
    var duplicateContextsMerged: Int = 0
    var duplicateAreasMerged: Int = 0
    var duplicateProjectsMerged: Int = 0
    var duplicateNotesMerged: Int = 0
    /// [[T-6435]]: `AppTask` rows folded into another row carrying the same `id`.
    var duplicateTasksMerged: Int = 0
    var duplicateHabitCompletionsRemoved: Int = 0
    var duplicateRecurrenceOccurrencesRemoved: Int = 0
    var habitRemindersCleared: Int = 0
    var defaultNoteTitlesCleared: Int = 0
    var movedAreas: Int = 0
    var movedProjects: Int = 0
    var movedTasks: Int = 0
    var movedGoals: Int = 0
    var movedHabits: Int = 0
    var movedNotes: Int = 0
    var movedDocuments: Int = 0
    var movedLinks: Int = 0
    var movedGoalLinks: Int = 0
    var movedFocusSessions: Int = 0
    /// [[T-3115]] part 3: `[[note:<merged-away id>|…]]` references re-pointed at the survivor.
    var noteReferencesRedirected: Int = 0

    /// **How many `AppTask` rows this repair actually materialised, and `nil` when it read none.**
    ///
    /// Not a counter of work done and deliberately not a term in `changed` below: it is the size of
    /// the read, which is what [[T-1443]] is about. The nil/zero distinction is the one
    /// `CadenceWidgetGenerationRecord.rowsFetched` and `NoteMigrationReport.noteTableScanned` already
    /// draw — `nil` means no pass here reached the task table at all (a repair with no
    /// `removingForkedOccurrences:` over a store with no duplicate container does not), and a
    /// number means it did and that is how many rows came back.
    var taskRowsFetched: Int?

    /// **How many `AppTask` rows the same-id scan ([[T-6435]]) read with `id` as the only fetched
    /// property**, and `nil` when it did not run.
    ///
    /// Kept apart from `taskRowsFetched` on purpose: that counter is [[T-1443]]'s bound on *whole*
    /// rows, and this scan asks the store for one column. Folding the two together would either
    /// hide a whole-table read behind an id scan or make the T-1443 bound unreadable. Like
    /// `taskRowsFetched` it is the size of a read and not a term in `changed`.
    var taskIdentitiesScanned: Int?

    /// **True when this repair deliberately did not look for duplicates at all** ([[T-6482]]).
    ///
    /// Not a counter and deliberately not a term in `changed`: nothing was repaired, so nothing
    /// needs saving. It exists because without it a deferred repair and a store with nothing wrong
    /// with it write the *same* report — `success: true`, every counter zero — and `lastReport()`
    /// is read back by the next launch and by `repairAndRecordFailure`'s fallback. "I found nothing"
    /// and "I did not look" are different facts about a launch and this is the one that tells them
    /// apart.
    var duplicateMergesDeferred: Bool = false

    var changed: Bool {
        duplicateContextsMerged > 0 ||
            duplicateAreasMerged > 0 ||
            duplicateProjectsMerged > 0 ||
            duplicateNotesMerged > 0 ||
            duplicateTasksMerged > 0 ||
            duplicateHabitCompletionsRemoved > 0 ||
            duplicateRecurrenceOccurrencesRemoved > 0 ||
            habitRemindersCleared > 0 ||
            defaultNoteTitlesCleared > 0 ||
            movedAreas > 0 ||
            movedProjects > 0 ||
            movedTasks > 0 ||
            movedGoals > 0 ||
            movedHabits > 0 ||
            movedNotes > 0 ||
            movedDocuments > 0 ||
            movedLinks > 0 ||
            movedGoalLinks > 0 ||
            movedFocusSessions > 0 ||
            noteReferencesRedirected > 0
    }
}

/// **In an extension, so the memberwise initializer survives.** An `init` in the struct body would
/// suppress it, and both `repairIfNeeded` and `DataIntegrityRepairServiceTests` build the report
/// memberwise from its head fields and then assign counters.
///
/// **`nonisolated` is load-bearing and is not decoration.** The `nonisolated` on the struct itself
/// does not reach an extension, and the app and widget targets set
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — so without it the `Decodable` witness declared
/// here is main-actor isolated while the conformance is not, which is
/// *"conformance ... crosses into main actor-isolated code"*: a warning against a zero baseline
/// under `-scheme Cadence`, and an error under the Swift 6 language mode `CadenceMCPServer`
/// already builds in. Measured, not assumed — the first spelling of this extension produced
/// exactly that warning on the app build while the MCP scheme stayed silent, because that target
/// is the one *without* the MainActor default.
nonisolated extension DataIntegrityRepairReport {
    /// **Hand-written because synthesized decoding ignores property defaults (T-445).**
    ///
    /// This report is archived to `UserDefaults` under `dataIntegrityRepair.lastReport.v1` and read
    /// back on the next launch. Every counter above has an `= 0` default, which reads as "an older
    /// blob missing this key still decodes" and is not what `Codable` synthesis does: the generated
    /// `init(from:)` calls `decode(Int.self, forKey:)` for a non-optional `Int` and throws
    /// `keyNotFound` when the key is absent. The default is applied by the *memberwise* initializer
    /// only. So every counter added to this struct silently invalidated every stored report written
    /// before it — twice already, `habitRemindersCleared` (T-428) after the T-359 counters — and
    /// `lastReport()` swallows the throw with `try?`, so the failure surfaced as `nil`: no crash, no
    /// log, and `repairAndRecordFailure` handing back nothing on exactly the launch where the repair
    /// failed and the previous report was the thing worth having.
    ///
    /// `decodeIfPresent(…) ?? 0` per counter is the whole fix, and it is deliberately exhaustive
    /// rather than clever. The five head fields stay `decode`: they have been written by every
    /// version of this key, they have no defaults to apply, and a blob missing `success` is not an
    /// older report — it is not this report.
    ///
    /// `DataIntegrityRepairServiceTests.aStoredReportSurvivesEveryCounterThisStructWillEverGain`
    /// re-derives the counter list from an encoded report rather than restating it, so a *third*
    /// counter added without a line here fails that test instead of being decoded as a throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        success = try container.decode(Bool.self, forKey: .success)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        duplicateContextsMerged = try container.decodeIfPresent(Int.self, forKey: .duplicateContextsMerged) ?? 0
        duplicateAreasMerged = try container.decodeIfPresent(Int.self, forKey: .duplicateAreasMerged) ?? 0
        duplicateProjectsMerged = try container.decodeIfPresent(Int.self, forKey: .duplicateProjectsMerged) ?? 0
        duplicateNotesMerged = try container.decodeIfPresent(Int.self, forKey: .duplicateNotesMerged) ?? 0
        duplicateTasksMerged = try container.decodeIfPresent(Int.self, forKey: .duplicateTasksMerged) ?? 0
        duplicateHabitCompletionsRemoved = try container.decodeIfPresent(Int.self, forKey: .duplicateHabitCompletionsRemoved) ?? 0
        duplicateRecurrenceOccurrencesRemoved = try container.decodeIfPresent(Int.self, forKey: .duplicateRecurrenceOccurrencesRemoved) ?? 0
        habitRemindersCleared = try container.decodeIfPresent(Int.self, forKey: .habitRemindersCleared) ?? 0
        defaultNoteTitlesCleared = try container.decodeIfPresent(Int.self, forKey: .defaultNoteTitlesCleared) ?? 0
        movedAreas = try container.decodeIfPresent(Int.self, forKey: .movedAreas) ?? 0
        movedProjects = try container.decodeIfPresent(Int.self, forKey: .movedProjects) ?? 0
        movedTasks = try container.decodeIfPresent(Int.self, forKey: .movedTasks) ?? 0
        movedGoals = try container.decodeIfPresent(Int.self, forKey: .movedGoals) ?? 0
        movedHabits = try container.decodeIfPresent(Int.self, forKey: .movedHabits) ?? 0
        movedNotes = try container.decodeIfPresent(Int.self, forKey: .movedNotes) ?? 0
        movedDocuments = try container.decodeIfPresent(Int.self, forKey: .movedDocuments) ?? 0
        movedLinks = try container.decodeIfPresent(Int.self, forKey: .movedLinks) ?? 0
        movedGoalLinks = try container.decodeIfPresent(Int.self, forKey: .movedGoalLinks) ?? 0
        movedFocusSessions = try container.decodeIfPresent(Int.self, forKey: .movedFocusSessions) ?? 0
        noteReferencesRedirected = try container.decodeIfPresent(Int.self, forKey: .noteReferencesRedirected) ?? 0
        taskRowsFetched = try container.decodeIfPresent(Int.self, forKey: .taskRowsFetched)
        taskIdentitiesScanned = try container.decodeIfPresent(Int.self, forKey: .taskIdentitiesScanned)
        duplicateMergesDeferred = try container.decodeIfPresent(Bool.self, forKey: .duplicateMergesDeferred) ?? false
    }
}

/// How T-622's forked-occurrence collapse actually removes the rows it decided on.
///
/// **This is a seam because `DataIntegrityRepairService.swift` is in `CadenceMCPServer`'s explicit
/// Sources phase and the removal is not.** Deleting an `AppTask` properly means severing every
/// inverse that names it and taking its subtasks with it, and this repository has exactly one
/// spelling of that — `CadenceTaskMutationSupport.detachRelationships` / `deleteSubtask` — in a
/// file the MCP target does not compile. Cancelling the removed rows' reminders needs
/// `NotificationManager`, which it does not compile either and, being a command-line tool with no
/// notification centre, has no business running. Adding both files (and their own closures) to
/// that target to serve one pass is a large source list bought for nothing;
/// re-spelling `detachRelationships` beside the pass is the drift this repository forbids. So the
/// *decision* stays here, where the report and the counter are, and the *removal* is handed in.
///
/// `nil` means "this process has no task-deletion core", which is the MCP tool's true answer, not
/// a silent skip: `CadenceMCPStorePreparation.prepare` says so at its call. The app supplies
/// `CadenceForkedOccurrenceRemover.removeAndCancelReminders`, and
/// `DataIntegrityRepairServiceTests.theAppStartupMaintenanceCollapsesAForkedSeries` holds by
/// effect that it does — the one thing a default of `nil` cannot enforce on its own.
///
/// Same shape and same reason as `CadenceListTaskSweep`: a piece of a cascade that cannot be
/// spelled where the cascade lives, named at file scope so nobody has to write the function type
/// out and hope it still means the same thing.
///
/// - Parameters are the rows `collapsibleDuplicateOccurrences` chose to remove and the context
///   holding them; the return is the ids actually removed, which is what the report counts.
typealias CadenceForkedOccurrenceRemoval = ([AppTask], ModelContext) -> [UUID]

/// **Scope: duplicate rows, the references a merge invalidates, and single-row fields that name
/// something impossible. Not an orphan sweep** (T-328).
///
/// The main shape it repairs is the *same* row present twice, which is what a restore, a CloudKit
/// round trip or a pre-merge migration leaves behind. It merges duplicate `Context`, `Area`,
/// `Project`, `AppTask` ([[T-6435]]) and `Note` rows, collapses duplicate habit-days and forked recurring occurrences, and
/// re-points the tasks, notes, documents, links, goal links and focus session rows each merge
/// would otherwise strand.
///
/// One counter is not a merge: `habitRemindersCleared` (T-428) clears a `Habit.reminderMinuteOfDay`
/// outside `0...1439`. It is here rather than beside the sweeps because its predicate reads a
/// single scalar on a row that is present, so unlike an orphan check it cannot be made false by a
/// record that has not synced yet — the argument is spelled out on the method.
///
/// It deliberately does **not** collect orphans. It never asks whether a `Subtask` has a
/// `parentTask`, whether a `TaskBundle` has members, whether a `HabitCompletion` has a `habit`, or
/// whether a `MarkdownImageAsset` is referenced by anything. Those rows exist as states the schema
/// permits, and the shared delete helpers — `CadenceListDeleteHelpers`, `ModelContext.deleteNote`,
/// `CadenceTaskMutationSupport` — are what keep them from being produced.
///
/// **Why that boundary is deliberate rather than unfinished.** Every pass here is conservative
/// against a partially-synced store, and that is the property that makes it safe to run unattended.
/// A merge cannot fire unless it can see *both* rows, so a store that has only received half of
/// CloudKit's records merges less; it never destroys something unique. An orphan sweep inverts
/// exactly that. `PersistenceController.performStartupMaintenance` calls this immediately after the
/// container opens, so on a fresh device — or any launch that races the first sync — a `Subtask`
/// with no `parentTask` is indistinguishable from one whose `AppTask` has not arrived yet. Deleting
/// it is unrecoverable, and it is the *empty* store that would delete the most. "Repair found
/// nothing to do" is the correct behaviour there; "repair deleted the rows whose owners were still
/// in flight" is not.
///
/// **[[T-6482]]: that argument covered the rows being merged and not their children, so the merges
/// now have a gate of their own.** Seeing both rows makes a merge *correct about the pair*; it says
/// nothing about a `Subtask`, a `FocusSessionLog`, or a task or note filed under the copy that is
/// still in flight when the copy is deleted. `DataIntegrityRepairDeletionPolicy` is where a caller
/// says whether its store can still be importing, and `.deferDuplicateMerges` leaves every
/// duplicate alone until it cannot be.
///
/// So a future orphan sweep is not a matter of adding four fetches. It needs a reason to believe
/// the store is complete — a sync-state gate, a user-initiated entry point instead of startup, or a
/// report-only pass that counts without deleting. Until one of those exists, the honest position is
/// that this covers duplicates and says so. `DataIntegrityRepairServiceTests` pins the boundary by
/// value so it cannot be crossed by accident.
/// **Whether a repair is allowed to delete rows on this run** ([[T-6482]]).
///
/// Every pass that merges a duplicate ends by deleting the copy, and the forked-occurrence
/// collapse deletes outright. `DataIntegrityRepairService`'s own doc comment argues that those
/// passes are safe against a half-synced store because a merge has to *see both rows* — true of
/// the rows being merged, and false of their children. A `Subtask` or `FocusSessionLog` of the
/// deleted copy, or a task or note filed under a deleted duplicate `Context`/`Area`/`Project`,
/// that is still in CloudKit flight when the delete lands arrives with its parent gone. The row
/// survives and is unreachable, and nothing can re-point it afterwards: `Subtask.parentTask`,
/// `FocusSessionLog.task/area/project` and `AppTask.area/project/goal/context` are relationships
/// with **no stored id beside them**, so a child that arrives orphaned carries no record of which
/// parent it wanted. That is why the fix is a gate in front of the delete rather than a repair
/// behind it.
///
/// The caller decides, and nothing here guesses: a store that mirrors to CloudKit cannot tell a
/// row that is absent from one that has not arrived, and a store that does not mirror has nothing
/// in flight to wait for. `PersistenceController.repairDeletionPolicyForLaunch` is the one place
/// the app answers it.
nonisolated enum DataIntegrityRepairDeletionPolicy: Equatable {
    /// Run every pass, including the four merges and the forked-occurrence collapse.
    case mergeDuplicates
    /// Run only the passes that edit fields on rows the store already holds, and leave every
    /// duplicate exactly where it is. Strictly less repair, never more.
    case deferDuplicateMerges
}

nonisolated enum DataIntegrityRepairService {
    private struct RepairState {
        var deletedAreas = Set<ObjectIdentifier>()
        var deletedProjects = Set<ObjectIdentifier>()
        var deletedContexts = Set<ObjectIdentifier>()
        var deletedNotes = Set<ObjectIdentifier>()
    }

    /// **The four tables every repair reads, whatever the store holds.**
    ///
    /// `repairDuplicateNotes`,
    /// `repairStoredDefaultNoteTitles` and the duplicate-context grouping each read one of these
    /// unconditionally, so fetching them unconditionally buys nothing that is not used.
    ///
    /// **The other eight moved to `ContainerMergeStore` ([[T-1443]]), and the boundary is which
    /// pass can read them rather than which table is big.** Every single read of `areas`,
    /// `projects`, `tasks`, `goals`, `documents`, `links`, `goalLinks` and `focusSessions` in this
    /// file sits inside `mergeContext` / `mergeArea` / `mergeProject` / `rePointTasksAlreadyIn` or
    /// one of the two `*Score` helpers those call — and every one of those is reached only from
    /// the `group.count > 1` branch below, i.e. only when there is a duplicate container to merge.
    /// A launch over a store with no duplicate container used to fetch all eight anyway and read
    /// none of them. Splitting the type rather than making the fields optional is what makes that
    /// unreadable-by-construction instead of a comment: a pass holding a `RepairStore` cannot spell
    /// `store.tasks`.
    private struct RepairStore {
        var contexts: [Context]
        var habits: [Habit]
        var notes: [Note]
    }

    /// The tables a **container merge** reads, fetched only when there is a container to merge.
    ///
    /// It carries the always-read tables rather than replacing them, because `mergeContext`
    /// re-points `habits` and `areaScore` / `projectScore` read `notes`: a merge needs both halves
    /// and there is exactly one fetch of each per repair either way.
    private struct ContainerMergeStore {
        var base: RepairStore
        var tasks: [AppTask]
        var areas: [Area]
        var projects: [Project]
        var goals: [Goal]
        var documents: [Document]
        var links: [SavedLink]
        var goalLinks: [GoalListLink]
        var focusSessions: [FocusSessionLog]
        var pursuits: [Pursuit]

        var habits: [Habit] { base.habits }
        var notes: [Note] { base.notes }

        init(base: RepairStore, tasks: [AppTask], fetchedFrom context: ModelContext) throws {
            self.base = base
            self.tasks = tasks
            areas = try context.fetch(FetchDescriptor<Area>())
            projects = try context.fetch(FetchDescriptor<Project>())
            goals = try context.fetch(FetchDescriptor<Goal>())
            documents = try context.fetch(FetchDescriptor<Document>())
            links = try context.fetch(FetchDescriptor<SavedLink>())
            goalLinks = try context.fetch(FetchDescriptor<GoalListLink>())
            focusSessions = try context.fetch(FetchDescriptor<FocusSessionLog>())
            pursuits = try context.fetch(FetchDescriptor<Pursuit>())
        }
    }

    /// The spawned occurrences, and nothing else.
    ///
    /// Byte-for-byte the filter `CadenceTaskRecurrenceWorkflowSupport.duplicateOccurrenceGroups`
    /// applies to whatever array it is handed — `!recurrenceSeriesIDRaw.isEmpty` there is
    /// `!= ""` here because that is the spelling SwiftData can push into the store — so moving it
    /// from the loop to the fetch cannot change which groups come out. A row with an empty series
    /// id or occurrence index 0 was never in a group, and the rows that *are* excluded are excluded
    /// by the predicate the pass would have applied to them anyway.
    private static var spawnedOccurrenceDescriptor: FetchDescriptor<AppTask> {
        FetchDescriptor<AppTask>(
            predicate: #Predicate<AppTask> { task in
                task.recurrenceSeriesIDRaw != "" && task.recurrenceOccurrenceIndex > 0
            }
        )
    }

    /// Every `AppTask` fetch this service takes goes through here, so `taskRowsFetched` is the
    /// number of rows that were really materialised rather than a number kept in step by hand.
    private static func fetchTasks(
        _ descriptor: FetchDescriptor<AppTask>,
        in context: ModelContext,
        report: inout DataIntegrityRepairReport
    ) throws -> [AppTask] {
        let rows = try context.fetch(descriptor)
        report.taskRowsFetched = (report.taskRowsFetched ?? 0) + rows.count
        return rows
    }

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "DataIntegrity")
    private static let lastReportKey = "dataIntegrityRepair.lastReport.v1"

    /// **`deleting:` defaults to today's behaviour on purpose** ([[T-6482]]). The gate is a
    /// property of the *caller's* store — only a launch over a mirroring container has an import to
    /// race — and every other call site here reaches a store that cannot import behind its back: a
    /// test's own temp store, the MCP tool's `cloudKitDatabase: .none` open, an archive import that
    /// just wrote the rows itself. Making the parameter required would have made ninety call sites
    /// restate the safe answer and left the one unsafe one no more visible than it is now.
    @discardableResult
    static func repairIfNeeded(
        in context: ModelContext,
        source: String = "unknown",
        saveChanges: Bool = true,
        removingForkedOccurrences remove: CadenceForkedOccurrenceRemoval? = nil,
        deleting policy: DataIntegrityRepairDeletionPolicy = .mergeDuplicates
    ) throws -> DataIntegrityRepairReport {
        var report = DataIntegrityRepairReport(
            source: source,
            startedAt: Date(),
            finishedAt: Date(),
            success: false
        )

        do {
            try repair(in: context, remove: remove, deleting: policy, report: &report)
            if report.changed && saveChanges {
                try context.save()
            }
            report.finishedAt = Date()
            report.success = true
            record(report)
            log(report)
            return report
        } catch {
            report.finishedAt = Date()
            report.success = false
            report.errorMessage = error.localizedDescription
            record(report)
            logger.error("Data integrity repair failed from \(source, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    static func repairAndRecordFailure(
        in context: ModelContext,
        source: String,
        saveChanges: Bool = true,
        removingForkedOccurrences remove: CadenceForkedOccurrenceRemoval? = nil,
        deleting policy: DataIntegrityRepairDeletionPolicy = .mergeDuplicates
    ) -> DataIntegrityRepairReport? {
        do {
            return try repairIfNeeded(
                in: context,
                source: source,
                saveChanges: saveChanges,
                removingForkedOccurrences: remove,
                deleting: policy
            )
        } catch {
            return lastReport()
        }
    }

    static func lastReport() -> DataIntegrityRepairReport? {
        guard let data = CadenceDefaults.store.data(forKey: lastReportKey) else { return nil }
        return try? JSONDecoder().decode(DataIntegrityRepairReport.self, from: data)
    }

    /// **The four merges and the forked-occurrence collapse are behind `policy`; the stored-title
    /// pass is not** ([[T-6482]]).
    ///
    /// The division is not "destructive vs harmless", it is **which pass can be made wrong by a
    /// record that has not arrived yet**. Every pass in the gated block ends in a `delete`, and a
    /// deleted row is the one thing a late child cannot be re-pointed onto, because the child
    /// carries no id of the parent it wanted — see `DataIntegrityRepairDeletionPolicy`.
    /// `repairStoredDefaultNoteTitles` reads one scalar on the row in front of it and writes
    /// another, which its own doc comment already argues no later record can falsify, and it stays
    /// outside the gate so a deferred launch is not a launch that repairs nothing at all.
    ///
    /// **Deferring costs a table read and nothing else.** The eight container tables are fetched
    /// inside the gated block ([[T-1443]]), so a deferred repair leaves `taskRowsFetched` and
    /// `taskIdentitiesScanned` `nil` exactly as a store with no duplicate container does; it is
    /// cheaper than the run it replaces, never more expensive.
    private static func repair(
        in context: ModelContext,
        remove: CadenceForkedOccurrenceRemoval?,
        deleting policy: DataIntegrityRepairDeletionPolicy,
        report: inout DataIntegrityRepairReport
    ) throws {
        let store = try RepairStore(
            contexts: context.fetch(FetchDescriptor<Context>()),
            habits: context.fetch(FetchDescriptor<Habit>()),
            notes: context.fetch(FetchDescriptor<Note>())
        )
        var state = RepairState()

        switch policy {
        case .deferDuplicateMerges:
            report.duplicateMergesDeferred = true
        case .mergeDuplicates:
            let activeContexts = store.contexts.filter { !$0.isArchived && !normalizedName($0).isEmpty }
            let duplicateContextGroups = Dictionary(grouping: activeContexts) { normalizedName($0) }
                .values
                .filter { $0.count > 1 }

            // T-1443. The eight container tables are fetched here and nowhere else, because this
            // branch is the only thing that reads them. The grouping above needs `contexts` alone,
            // and the four passes below need none of the eight — so a store with no duplicate
            // container never materialises its task table for this service at all.
            if !duplicateContextGroups.isEmpty {
                let tasks = try fetchTasks(FetchDescriptor<AppTask>(), in: context, report: &report)
                let merging = try ContainerMergeStore(base: store, tasks: tasks, fetchedFrom: context)
                for group in duplicateContextGroups {
                    guard let canonical = canonicalContext(among: group) else {
                        continue
                    }

                    for duplicate in group where duplicate !== canonical {
                        mergeContext(duplicate, into: canonical, in: merging, modelContext: context, state: &state, report: &report)
                    }
                }
            }

            // T-6435. After the container merges, so a same-id pair they re-filed is merged where
            // it now lives; before the forked-occurrence collapse, which groups by series slot and
            // would otherwise see a same-id pair as a fork and cancel the survivor's reminders by
            // its id.
            try repairDuplicateTasks(modelContext: context, report: &report)
            try repairDuplicateNotes(in: store, modelContext: context, state: &state, report: &report)
            try repairDuplicateRecurrenceOccurrences(
                modelContext: context,
                remove: remove,
                report: &report
            )
        }

        repairStoredDefaultNoteTitles(in: store, state: state, report: &report)
    }

    /// T-733: `Note.title` defaulted to the literal `"Untitled"` until this build, so the word is
    /// **stored text** on every note any earlier build created. That is what made a new note's
    /// title field pre-filled and the caret land after it — typing `Target` produced
    /// `UntitledTarget`. Dropping the default fixes the notes this build makes and does nothing at
    /// all for the ones already on disk, because a property default is not persisted: it is applied
    /// by the initializer, and rows in the store were initialized by the old one.
    ///
    /// **A data edit at load, not a schema change.** There is no `SchemaMigrationPlan` in this
    /// project and this needs none — no column is added, removed or retyped, and nothing here would
    /// be legal in a migration plan anyway. It is the same kind of pass as
    /// `repairDuplicateNotes` above and it is placed beside it deliberately. (It sat beside
    /// `repairOutOfRangeHabitReminders` until [[T-2077]] removed that pass.)
    ///
    /// **Idempotent, and by construction rather than by a flag.** The predicate is "this row's
    /// title is exactly the retired default"; the edit makes it the empty string, which is not that
    /// literal. So a second run over the same store matches nothing, `defaultNoteTitlesCleared`
    /// stays 0, `changed` stays false for this pass, and no save is taken. There is no
    /// "already migrated" marker to get out of step with the store — running it twice, or on a
    /// device that has already run it, or on a row that arrives from CloudKit *after* it ran, all
    /// reach the same fixed point. Every device writes the same empty string, so it cannot ping-pong
    /// the way a pass that invented a value would.
    ///
    /// **Safe under partial sync**, which is the boundary this whole service is held to ([[T-328]]).
    /// The predicate reads **one scalar on the row in front of it**. No record arriving later can
    /// make a title stop being `"Untitled"`, so a half-synced store cannot produce a false positive
    /// — it simply sees fewer `Note` rows and clears fewer of them. It edits a field rather than
    /// deleting a row, and the field it edits has a per-kind fallback behind it.
    ///
    /// **The cost, stated rather than hidden: this also clears a title someone deliberately typed
    /// as "Untitled".** The store cannot tell that note from one the old default named, because
    /// they are byte-for-byte the same value — there is no provenance on the field. The user was
    /// told and accepted it. What such a user loses is small and visible: a `.list` note reads
    /// `Untitled` either way (`Note.displayTitle`'s own fallback for that kind is the same word),
    /// a notepad note reads `Notepad`, and retyping the title restores it.
    ///
    /// **T-741 widened that same cost to the note's own heading.** See
    /// `clearRetiredHeadingIfPresent` below: clearing `title` alone on a `.list` or `.permanent`
    /// row left its literal `"# Untitled"` first line in place, which is the field
    /// `MarkdownNoteTitleSync` reads on the note's next content commit — so the word came straight
    /// back, and the launch after that cleared it again, forever.
    ///
    /// **The literal is frozen here on purpose and is not `CadenceTitleNormalization
    /// .defaultCompactTitle`.** That constant is the app's *display* placeholder and is free to be
    /// renamed; this is a historical value — the exact bytes a retired default wrote — and a
    /// migration that stopped matching them because a display string was reworded would silently
    /// stop migrating. The two being equal today is a coincidence worth not depending on.
    private static func repairStoredDefaultNoteTitles(
        in store: RepairStore,
        state: RepairState,
        report: inout DataIntegrityRepairReport
    ) {
        for note in store.notes {
            guard !state.deletedNotes.contains(ObjectIdentifier(note)) else { continue }
            guard note.title == retiredStoredNoteTitleDefault else { continue }
            note.title = ""
            report.defaultNoteTitlesCleared += 1
            clearRetiredHeadingIfPresent(on: note)
        }
    }

    /// The matching half of the repair above ([[T-741]]). Clearing `title` alone repairs nothing
    /// for a `.list` or `.permanent` row: the retired initializer interpolated the same default
    /// into the note's own first line too (`"# \(title)\n\n"`), and `MarkdownNoteTitleSync` reads
    /// that heading back on the note's very next content commit — finding it unequal to the
    /// now-empty `title` and writing the word straight back into the field this pass just cleared.
    /// The next launch clears it again: an oscillation, not a one-time cost, and leaving `content`
    /// alone did not avoid touching the body, it guaranteed a second edit would.
    ///
    /// Blanks the heading to `"# "` — an H1 with nothing after it, the same shape a note born
    /// today seeds for an empty title (`CadenceListNoteFiling.seededContent`,
    /// `NoteMigrationService.createPermanentNote`) — which `MarkdownNoteTitleSync` reads as "leave
    /// the stored title alone" rather than a name to sync.
    ///
    /// Scoped to the exact literal on the exact first line, and only for the two kinds that ever
    /// read it (`NoteKind.syncsTitleFromH1`): `.meeting` has its own title field and
    /// `.daily`/`.weekly` are named by their date keys, so neither looks at the body, and a
    /// coincidental `# Untitled` further down is a section heading a user wrote, not this bug.
    private static func clearRetiredHeadingIfPresent(on note: Note) {
        guard note.kind.syncsTitleFromH1 else { return }
        guard String(note.content.prefix(while: { $0 != "\n" })) == retiredStoredNoteHeading else { return }
        note.content = "# " + String(note.content.dropFirst(retiredStoredNoteHeading.count))
    }

    /// The exact string `Note.title` defaulted to before T-733. Matched untrimmed and
    /// case-sensitively: `" Untitled "` and `"untitled"` are things a person typed, and this pass
    /// is only entitled to the value the old initializer wrote.
    private static let retiredStoredNoteTitleDefault = "Untitled"

    /// The same literal, as the retired initializer interpolated it into a note's first line —
    /// `"# \(title)\n\n"` with `title` at its own retired default. See
    /// `clearRetiredHeadingIfPresent`.
    private static let retiredStoredNoteHeading = "# \(retiredStoredNoteTitleDefault)"

    /// **The two habit passes this service used to run were removed by [[T-2077]].**
    ///
    /// `repairOutOfRangeHabitReminders` ([[T-428]]) wrote `Habit.reminderMinuteOfDay = nil` on
    /// every habit whose stored minute fell outside `0...1439`, and
    /// `repairDuplicateHabitCompletions` ([[T-359]]) **deleted** `HabitCompletion` rows it judged
    /// to be a second device's copy of one check-in. Both ran on **launch**, from
    /// `PersistenceController.performStartupMaintenance`, with no user action. The owner retired
    /// habits at the depth "remove the UI and stop writing, keep the schema" — the rows stay and
    /// stay recoverable — so a startup pass that rewrites a habit, and above all one that deletes
    /// a check-in the owner can no longer see or restore from any surface, is exactly the write
    /// this ticket exists to stop. Neither pass was repairing something a live surface reads any
    /// more: nothing schedules a habit reminder and nothing draws a habit day.
    ///
    /// `duplicateHabitCompletionsRemoved` and `habitRemindersCleared` stay on
    /// `DataIntegrityRepairReport` and stay decoded, for the reason that type's own
    /// `init(from:)` note gives — a persisted report written by an earlier build still carries
    /// them, and dropping the keys would make an old report undecodable. They are simply never
    /// raised above zero now.
    ///
    /// **What was deliberately NOT removed: the context/area/project merges' re-pointing of
    /// `goal.context` and `habit.context`.** Those run only when a duplicate `Context` already
    /// exists and is about to be deleted, and they move a surviving goal or habit onto the
    /// canonical row rather than letting the delete nullify its filing. Removing them would make
    /// this ticket *lose* data on the very rows it exists to preserve, which is the opposite of
    /// the depth the owner chose. They write a relationship to keep an existing row intact; they
    /// never create one.

    /// T-622: two devices can each complete the same occurrence of a recurring task and each spawn
    /// a successor for the slot after it.
    ///
    /// `spawnNextOccurrenceIfNeeded` guards on `recurrenceSpawnedTaskID == nil` against the local
    /// replica and then inserts, and the pointer it writes is a single `String` — so CloudKit keeps
    /// both successors and can name only one. Nothing collapsed them: this service had a
    /// duplicate-habit-completion pass and a duplicate-note pass and **no duplicate-task pass of
    /// any kind**. The user sees the same occurrence twice, in the same list, each with its own
    /// reminders, and the series continues down whichever branch their device happens to point at.
    ///
    /// **This is a duplicate pass, not the orphan sweep the header rules out.** Its predicate is
    /// "these two rows claim the same slot in the same series", which needs to see *both* rows —
    /// so a half-synced store collapses less and never destroys something unique, which is the
    /// monotonicity every other pass here has. `CadenceTaskRecurrenceWorkflowSupport` owns the
    /// survivor rule and the removability test, deliberately not restated here — the same reason
    /// the habit-day collapse lived in `CadenceHabitCompletionStore` until [[T-2077]] retired it.
    ///
    /// **The predecessor is re-pointed at the survivor, not cleared.** Each device wrote its own
    /// successor's id into the single `recurrenceSpawnedTaskIDRaw`, so the replica that recorded
    /// the *removed* branch would otherwise be left pointing at nothing — and a series whose
    /// pointer is nil spawns a second successor the next time anyone completes it, which is the
    /// fork again. `repairDanglingRecurrenceLinks` is deliberately **not** used here: clearing the
    /// pointer is right when the user deleted an occurrence and wrong when the occurrence is still
    /// there under a different id.
    ///
    /// Deferred commit: `repairIfNeeded` saves once, after every pass, when anything changed.
    private static func repairDuplicateRecurrenceOccurrences(
        modelContext: ModelContext,
        remove: CadenceForkedOccurrenceRemoval?,
        report: inout DataIntegrityRepairReport
    ) throws {
        guard let remove else { return }
        let spawned = try fetchTasks(Self.spawnedOccurrenceDescriptor, in: modelContext, report: &report)
        let groups = CadenceTaskRecurrenceWorkflowSupport.duplicateOccurrenceGroups(among: spawned)
        var survivorByRemovedID: [UUID: UUID] = [:]
        for group in groups {
            guard let collapse = CadenceTaskRecurrenceWorkflowSupport
                .collapsibleDuplicateOccurrences(among: group) else { continue }
            for removed in collapse.removable {
                survivorByRemovedID[removed.id] = collapse.survivor.id
            }
        }
        guard !survivorByRemovedID.isEmpty else { return }

        // T-1443. The *whole* table, and it has to be: the predecessor holding the pointer at a
        // removed branch is usually the series origin, whose `recurrenceOccurrenceIndex` is 0 and
        // which the fetch above therefore never returns. This read is the one the answer needs, and
        // it is taken only on a launch that found a fork to collapse — never on a warm one.
        let everyTask = try fetchTasks(FetchDescriptor<AppTask>(), in: modelContext, report: &report)

        // Recorded before the delete, while the pointers still name the rows that are going.
        var rePointing: [(AppTask, UUID)] = []
        for task in everyTask where survivorByRemovedID[task.id] == nil {
            guard let spawnedID = task.recurrenceSpawnedTaskID,
                  let survivorID = survivorByRemovedID[spawnedID] else { continue }
            rePointing.append((task, survivorID))
        }

        var removedIDs: [UUID] = []
        for group in groups {
            guard let collapse = CadenceTaskRecurrenceWorkflowSupport
                .collapsibleDuplicateOccurrences(among: group) else { continue }
            removedIDs += remove(collapse.removable, modelContext)
        }

        for (predecessor, survivorID) in rePointing {
            predecessor.recurrenceSpawnedTaskID = survivorID
        }
        report.duplicateRecurrenceOccurrencesRemoved += removedIDs.count
    }

    /// **[[T-6435]]: two `AppTask` rows carrying one `id`, folded into one.**
    ///
    /// `id` is an app-level attribute with no uniqueness (CloudKit forbids `.unique`), and three
    /// things write a second row under an id the store already holds: an archive import in merge
    /// mode that ran before the first CloudKit import had landed the rows it would have matched
    /// (`CadenceArchiveImportService` writes archive ids verbatim), a store-backup restore that
    /// CloudKit then re-exports beside the server's own copies, and two devices each importing
    /// the same archive. [[T-6451]] stopped the trap such a pair caused in every id-keyed map
    /// (`CadenceIdentityMap.firstWins`); this removes the pair itself, so a task is no longer
    /// drawn twice in a list and the copy a note embed resolves to is the only copy.
    ///
    /// **Which row survives** — `preferredDuplicateTask`, the rule the ledger records:
    /// 1. the **earliest `createdAt`**;
    /// 2. then the higher `taskScore`, the same shape as the note pass's `noteScore` (non-empty
    ///    notes, capped; a title; then the scheduling a person set);
    /// 3. then the greater `scalarFingerprint`, every stored scalar of the row in one string;
    /// 4. and when all three tie, **the group is left alone**.
    ///
    /// The order differs from `preferredNoteSort`'s (score, `updatedAt`, `createdAt`, `id`) on
    /// purpose, for [[T-3101]]'s reason: a survivor rule has to give the same answer on every
    /// device, or two devices each delete the copy the other kept and both deletes sync. The note
    /// pass's last resort, `id`, is the one thing a same-id pair cannot be told apart by, and its
    /// first, a score over content, moves with every edit. `createdAt` is minted once at insert,
    /// travels with the record and is never written again, so it is the only immutable
    /// discriminator these rows have and it goes first. Rules 2 and 3 read only the row's own
    /// scalars — never a relationship, whose far side may not have synced yet — so two devices
    /// holding the same version of both rows agree. Rule 4 is the honest end of the line: two rows
    /// equal in every scalar give a device nothing to choose by that another device would choose
    /// the same way, and guessing there risks *both* copies going. A wrong "leave it" is a visible
    /// duplicate; a wrong "merge" is a lost task. [[T-6481]] holds the residual.
    ///
    /// **How the fields merge** — `mergeTaskFields`, following `mergeNoteFields`: the survivor's
    /// value stands, and an empty one is filled from the copy; `notes` is appended with the note
    /// pass's separator unless the survivor already contains it; tags are the union; `createdAt`
    /// and `order` take the `min` and `actualMinutes` the `max`, as the container merges do for
    /// their own counters. A finished copy finishes an open survivor, because a completion is a
    /// deliberate act and nothing else in the store records it.
    ///
    /// **What is re-pointed** — `rePointChildren`: every `Subtask` and every `FocusSessionLog`
    /// the copy holds moves to the survivor, except a child that is an exact copy of one the
    /// survivor already holds (same `id` and every field), which is deleted rather than drawn
    /// twice — and, for a ledger row, rather than counted twice by
    /// `CadenceFocusLedger.reconcile`. The to-one filings (`area`/`project`/`context`/`sectionName`
    /// as one unit, `goal`, `bundle`) fill an empty survivor slot. Nothing that names a task *by
    /// id* needs re-pointing — note embeds, `recurrenceSpawnedTaskIDRaw`, reminders — because the
    /// survivor carries the same id, which is also why no reminder is cancelled here.
    ///
    /// **Safe under partial sync**, by the monotonicity every merge here has ([[T-328]]): it fires
    /// only when it can see both rows, so a half-imported store merges less. What it cannot see is
    /// a child of the copy still in flight — that child lands after its parent is gone and arrives
    /// unparented. The container merges carry the same window and there is no sync-state gate in
    /// this service to reuse ([[T-6482]]).
    ///
    /// **The scan reads one column.** Finding a pair needs every row's `id`, and [[T-1443]] took
    /// the whole-table read off the warm launch; `propertiesToFetch = [\.id]` asks the store for
    /// the id alone and `taskIdentitiesScanned` counts it, apart from `taskRowsFetched`.
    ///
    /// Deferred commit: `repairIfNeeded` saves once, after every pass, when anything changed.
    private static func repairDuplicateTasks(
        modelContext: ModelContext,
        report: inout DataIntegrityRepairReport
    ) throws {
        var descriptor = FetchDescriptor<AppTask>()
        descriptor.propertiesToFetch = [\.id]
        let scanned = try modelContext.fetch(descriptor).filter { !$0.isDeleted }
        report.taskIdentitiesScanned = (report.taskIdentitiesScanned ?? 0) + scanned.count

        let groups = Dictionary(grouping: scanned, by: \.id).values.filter { $0.count > 1 }
        for group in groups {
            guard let survivor = preferredDuplicateTask(among: group) else {
                logger.info("Left \(group.count, privacy: .public) same-id tasks unmerged: no field tells them apart")
                continue
            }
            for duplicate in group where duplicate !== survivor {
                mergeTask(duplicate, into: survivor, modelContext: modelContext)
                report.duplicateTasksMerged += 1
            }
        }
    }

    /// The row a same-id group keeps, or `nil` when no rule separates the best two. See
    /// `repairDuplicateTasks` for why the order is what it is.
    private static func preferredDuplicateTask(among group: [AppTask]) -> AppTask? {
        let ranked = group.sorted(by: taskRanksAbove)
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, !taskRanksAbove(best, ranked[1]) { return nil }
        return best
    }

    private static func taskRanksAbove(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        let lhsScore = taskScore(lhs)
        let rhsScore = taskScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return scalarFingerprint(lhs) > scalarFingerprint(rhs)
    }

    /// `noteScore`'s shape over a task's own scalars. No relationship is read: a tag or a subtask
    /// that has not synced yet would score the same row differently on two devices.
    private static func taskScore(_ task: AppTask) -> Int {
        var score = 0
        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += min(task.notes.count, 2_000)
        }
        if !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 100 }
        if !task.dueDate.isEmpty { score += 10 }
        if !task.scheduledDate.isEmpty { score += 10 }
        if task.scheduledStartMin >= 0 { score += 5 }
        if task.priority != .none { score += 5 }
        if task.recurrenceRule != .none { score += 5 }
        return score
    }

    /// Every stored scalar of the row, in one string, so that two rows differing in any of them are
    /// ordered the same way on every device. The unit separator keeps `("ab", "c")` apart from
    /// `("a", "bc")`.
    private static func scalarFingerprint(_ task: AppTask) -> String {
        let fields: [String] = [
            task.title, task.notes, task.priorityRaw, task.statusRaw, task.dueDate, task.scheduledDate,
            String(task.scheduledStartMin), String(task.estimatedMinutes), String(task.actualMinutes),
            task.calendarEventID, task.recurrenceRaw, task.recurrenceSpawnedTaskIDRaw,
            task.recurrenceSeriesIDRaw, task.recurrenceSourceTaskIDRaw, String(task.recurrenceOccurrenceIndex),
            task.recurrenceEndModeRaw, task.recurrenceEndDate, String(task.recurrenceEndCount),
            task.sectionName, String(task.order), String(task.bundleOrder),
            task.completedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
        ]
        return fields.joined(separator: "\u{1F}")
    }

    private static func mergeTask(_ source: AppTask, into target: AppTask, modelContext: ModelContext) {
        mergeTaskFields(from: source, into: target)
        rePointChildren(of: source, to: target, modelContext: modelContext)
        detachByIdentity(source)
        modelContext.delete(source)
    }

    private static func mergeTaskFields(from source: AppTask, into target: AppTask) {
        if target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.title = source.title
        }

        let targetNotes = target.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceNotes = source.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceNotes.isEmpty, !targetNotes.contains(sourceNotes) {
            target.notes = targetNotes.isEmpty ? source.notes : "\(target.notes)\n\n---\n\n\(source.notes)"
        }

        if target.priority == .none, source.priority != .none {
            target.priorityRaw = source.priorityRaw
        }
        if target.status == .todo, source.status != .todo {
            target.statusRaw = source.statusRaw
            target.completedAt = source.completedAt
        }
        if target.dueDate.isEmpty {
            target.dueDate = source.dueDate
        }
        if target.scheduledDate.isEmpty, !source.scheduledDate.isEmpty {
            target.scheduledDate = source.scheduledDate
            target.scheduledStartMin = source.scheduledStartMin
        } else if target.scheduledDate == source.scheduledDate, target.scheduledStartMin < 0 {
            target.scheduledStartMin = source.scheduledStartMin
        }
        if target.calendarEventID.isEmpty {
            target.calendarEventID = source.calendarEventID
        }
        if target.recurrenceRule == .none, source.recurrenceRule != .none {
            target.recurrenceRaw = source.recurrenceRaw
            target.recurrenceEndModeRaw = source.recurrenceEndModeRaw
            target.recurrenceEndDate = source.recurrenceEndDate
            target.recurrenceEndCount = source.recurrenceEndCount
        }
        if target.recurrenceSeriesIDRaw.isEmpty, !source.recurrenceSeriesIDRaw.isEmpty {
            target.recurrenceSeriesIDRaw = source.recurrenceSeriesIDRaw
            target.recurrenceOccurrenceIndex = source.recurrenceOccurrenceIndex
        }
        if target.recurrenceSourceTaskIDRaw.isEmpty {
            target.recurrenceSourceTaskIDRaw = source.recurrenceSourceTaskIDRaw
        }
        if target.recurrenceSpawnedTaskIDRaw.isEmpty {
            target.recurrenceSpawnedTaskIDRaw = source.recurrenceSpawnedTaskIDRaw
        }
        target.actualMinutes = max(target.actualMinutes, source.actualMinutes)
        target.order = min(target.order, source.order)
        target.createdAt = min(target.createdAt, source.createdAt)

        // The filing is one unit: an area from one copy and a project from the other could name
        // two different lists, and `context` is derived from them.
        if target.area == nil, target.project == nil, target.context == nil {
            target.area = source.area
            target.project = source.project
            target.context = source.context
            target.sectionName = source.sectionName
        }
        if target.goal == nil {
            target.goal = source.goal
        }
        if target.bundle == nil, let bundle = source.bundle {
            target.bundle = bundle
            target.bundleOrder = source.bundleOrder
        }
        let mergedTaskTags = mergedTags(primary: target.tags ?? [], secondary: source.tags ?? [])
        if Set(mergedTaskTags.map(\.id)) != Set((target.tags ?? []).map(\.id)) {
            target.tags = mergedTaskTags
        }
    }

    /// Moves the copy's subtasks and focus-ledger rows to the survivor. A child that is an exact
    /// copy of one the survivor already holds is deleted instead: the restore or import that made
    /// the task pair made its children in pairs too, and re-pointing both would draw each subtask
    /// twice and count each focus session twice. The copy being removed is the same row on every
    /// device (that is what `preferredDuplicateTask` guarantees), so this deletes the same child
    /// record everywhere and never the one that stays.
    private static func rePointChildren(of source: AppTask, to target: AppTask, modelContext: ModelContext) {
        let keptSubtasks = target.subtasks ?? []
        var arrivingSubtasks: [Subtask] = []
        for subtask in source.subtasks ?? [] {
            if keptSubtasks.contains(where: { isSameSubtask($0, subtask) }) {
                modelContext.delete(subtask)
            } else {
                arrivingSubtasks.append(subtask)
            }
        }
        source.subtasks = []
        for subtask in arrivingSubtasks {
            subtask.parentTask = target
        }
        if !arrivingSubtasks.isEmpty {
            target.subtasks = keptSubtasks + arrivingSubtasks
        }

        let keptSessions = target.focusSessions ?? []
        var arrivingSessions: [FocusSessionLog] = []
        for session in source.focusSessions ?? [] {
            if keptSessions.contains(where: { isSameFocusSession($0, session) }) {
                modelContext.delete(session)
            } else {
                arrivingSessions.append(session)
            }
        }
        source.focusSessions = []
        for session in arrivingSessions {
            session.task = target
        }
        if !arrivingSessions.isEmpty {
            target.focusSessions = keptSessions + arrivingSessions
        }
    }

    private static func isSameSubtask(_ lhs: Subtask, _ rhs: Subtask) -> Bool {
        lhs !== rhs && lhs.id == rhs.id && lhs.title == rhs.title && lhs.isDone == rhs.isDone
    }

    private static func isSameFocusSession(_ lhs: FocusSessionLog, _ rhs: FocusSessionLog) -> Bool {
        lhs !== rhs && lhs.id == rhs.id && lhs.minutes == rhs.minutes &&
            lhs.previousMinutes == rhs.previousMinutes && lhs.loggedAt == rhs.loggedAt &&
            lhs.dayKey == rhs.dayKey
    }

    /// Takes the copy out of every inverse array before it is deleted, by **identity**.
    ///
    /// Not `CadenceTaskMutationSupport.detachRelationships`, because the MCP target does not compile
    /// it. That helper used to filter each inverse by `$0.id != task.id`, which for a same-id pair
    /// removed the *survivor* from its own area, project, context, goal, bundle and tags too; it
    /// has detached by identity as well since [[T-6483]].
    private static func detachByIdentity(_ task: AppTask) {
        if let area = task.area { area.tasks = (area.tasks ?? []).filter { $0 !== task } }
        if let project = task.project { project.tasks = (project.tasks ?? []).filter { $0 !== task } }
        if let context = task.context { context.tasks = (context.tasks ?? []).filter { $0 !== task } }
        if let goal = task.goal { goal.tasks = (goal.tasks ?? []).filter { $0 !== task } }
        if let bundle = task.bundle { bundle.tasks = (bundle.tasks ?? []).filter { $0 !== task } }
        for tag in task.tags ?? [] {
            tag.tasks = (tag.tasks ?? []).filter { $0 !== task }
        }
        task.area = nil
        task.project = nil
        task.context = nil
        task.goal = nil
        task.bundle = nil
        task.tags = []
    }

    private static func mergeContext(
        _ duplicate: Context,
        into canonical: Context,
        in store: ContainerMergeStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) {
        guard !state.deletedContexts.contains(ObjectIdentifier(duplicate)) else { return }

        mergeContextFields(from: duplicate, into: canonical)

        for area in store.areas where area.context === duplicate && !state.deletedAreas.contains(ObjectIdentifier(area)) {
            _ = mergeArea(area, intoContext: canonical, in: store, modelContext: modelContext, state: &state, report: &report)
        }

        for project in store.projects where project.context === duplicate && !state.deletedProjects.contains(ObjectIdentifier(project)) {
            _ = mergeProject(project, intoContext: canonical, preferredArea: project.area, in: store, modelContext: modelContext, state: &state, report: &report)
        }

        for task in store.tasks where task.context === duplicate {
            task.context = canonical
            report.movedTasks += 1
        }
        for goal in store.goals where goal.context === duplicate {
            goal.context = canonical
            report.movedGoals += 1
        }
        for habit in store.habits where habit.context === duplicate {
            habit.context = canonical
            report.movedHabits += 1
        }
        // [[T-3019]] (1): `Context`'s sixth to-many. Left out, the default `.nullify` orphaned the
        // duplicate's pursuits with `context == nil`, and `PursuitToGoalMigration` then turned each
        // into a `Goal` filed under no context — [[T-743]]'s shape one model over. Retired model,
        // so no report counter: re-pointed to the survivor like every other leg, and not counted.
        for pursuit in store.pursuits where pursuit.context === duplicate {
            pursuit.context = canonical
        }

        modelContext.delete(duplicate)
        state.deletedContexts.insert(ObjectIdentifier(duplicate))
        report.duplicateContextsMerged += 1
    }

    @discardableResult
    private static func mergeArea(
        _ source: Area,
        intoContext canonicalContext: Context,
        in store: ContainerMergeStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) -> Area? {
        guard !state.deletedAreas.contains(ObjectIdentifier(source)) else { return nil }

        let existing = store.areas
            .filter { area in
                area !== source &&
                    !state.deletedAreas.contains(ObjectIdentifier(area)) &&
                    area.context === canonicalContext &&
                    area.id == source.id
            }
            .max { areaScore($0, in: store) < areaScore($1, in: store) }

        guard let target = existing else {
            if source.context !== canonicalContext {
                source.context = canonicalContext
                report.movedAreas += 1
            }
            return source
        }

        mergeAreaFields(from: source, into: target)

        for task in store.tasks where task.area === source {
            task.area = target
            task.context = target.context
            report.movedTasks += 1
        }
        for project in store.projects where project.area === source && !state.deletedProjects.contains(ObjectIdentifier(project)) {
            project.area = target
            _ = mergeProject(project, intoContext: canonicalContext, preferredArea: target, in: store, modelContext: modelContext, state: &state, report: &report)
        }
        for note in store.notes where note.area === source {
            note.area = target
            report.movedNotes += 1
        }
        for document in store.documents where document.area === source {
            document.area = target
            report.movedDocuments += 1
        }
        for link in store.links where link.area === source {
            link.area = target
            report.movedLinks += 1
        }
        for goalLink in store.goalLinks where goalLink.area === source {
            goalLink.area = target
            report.movedGoalLinks += 1
        }
        // T-743. `Area.focusSessions` is new with T-621 and was never added to the re-points
        // above: without this, the duplicate's `FocusSessionLog` rows kept pointing at a row
        // about to be deleted, and the survivor's `loggedMinutes` could no longer be explained
        // by its own rows.
        for session in store.focusSessions where session.area === source {
            session.area = target
            report.movedFocusSessions += 1
        }

        modelContext.delete(source)
        state.deletedAreas.insert(ObjectIdentifier(source))
        report.duplicateAreasMerged += 1
        return target
    }

    @discardableResult
    private static func mergeProject(
        _ source: Project,
        intoContext canonicalContext: Context,
        preferredArea: Area?,
        in store: ContainerMergeStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) -> Project? {
        guard !state.deletedProjects.contains(ObjectIdentifier(source)) else { return nil }

        let existing = store.projects
            .filter { project in
                project !== source &&
                    !state.deletedProjects.contains(ObjectIdentifier(project)) &&
                    project.context === canonicalContext &&
                    project.id == source.id
            }
            .max { projectScore($0, in: store) < projectScore($1, in: store) }

        guard let target = existing else {
            if source.context !== canonicalContext {
                source.context = canonicalContext
                report.movedProjects += 1
            }
            if let preferredArea, source.area !== preferredArea {
                source.area = preferredArea
            }
            // T-340. No duplicate to merge, but the list still moved: this project has just been
            // adopted into the canonical context, and its tasks were never re-derived.
            rePointTasksAlreadyIn(source, in: store, report: &report)
            return source
        }

        mergeProjectFields(from: source, into: target)
        if target.area == nil, let preferredArea {
            target.area = preferredArea
        }

        for task in store.tasks where task.project === source {
            task.project = target
            task.context = target.resolvedContext
            report.movedTasks += 1
        }
        // T-340. The loop above walks only the tasks arriving from `source`; the ones already in
        // `target` inherit from `target` too and nothing has ever re-derived them.
        //
        // Runs after the arrivals so it also covers them — the guard turns that into a no-op rather
        // than a second `movedTasks` increment.
        rePointTasksAlreadyIn(target, in: store, report: &report)
        for note in store.notes where note.project === source {
            note.project = target
            report.movedNotes += 1
        }
        for document in store.documents where document.project === source {
            document.project = target
            report.movedDocuments += 1
        }
        for link in store.links where link.project === source {
            link.project = target
            report.movedLinks += 1
        }
        for goalLink in store.goalLinks where goalLink.project === source {
            goalLink.project = target
            report.movedGoalLinks += 1
        }
        // T-743. Same gap as `mergeArea`'s: `Project.focusSessions` was never added to this
        // merge's re-points, so a duplicate's ledger rows survived pointing at a project about
        // to be deleted.
        for session in store.focusSessions where session.project === source {
            session.project = target
            report.movedFocusSessions += 1
        }

        modelContext.delete(source)
        state.deletedProjects.insert(ObjectIdentifier(source))
        report.duplicateProjectsMerged += 1
        return target
    }

    /// Re-derives `AppTask.context` for every task filed in a project the merge has just moved.
    ///
    /// The shared rule for "what context does this list put its tasks in" is `resolvedContext`, and
    /// this is `CadenceTaskMutationSupport.reassignInheritedContext` applied where repair, rather
    /// than an editor, is the thing that moved the list. It is not spelled as a call to that helper
    /// because this pass has to count what it changed.
    ///
    /// **Correcting [[T-340]]'s stated mechanism.** The ticket describes the gap as the merge
    /// changing the surviving project's *area*, and so changing what it resolves to. That does not
    /// happen on either branch. A merge target is only ever selected by
    /// `project.context === canonicalContext`, and the no-duplicate branch assigns
    /// `source.context = canonicalContext` outright — so in both cases the survivor's own `context`
    /// is non-`nil` and dominates `resolvedContext` whatever happens to `area`, and
    /// `mergeProjectFields` touches neither field. The area never gets to decide.
    ///
    /// The gap is real anyway, for a different reason: a task filed in the survivor whose `context`
    /// is neither the duplicate nor the canonical one is re-pointed by nothing. `mergeContext`
    /// sweeps `task.context === duplicate` and the loop above sweeps the arrivals; a resident task
    /// carrying `nil`, or a third context left by an earlier state, falls between them. That is
    /// pre-merge data of exactly the kind this service exists to find.
    ///
    /// The guard is what keeps this from reporting work it did not do: an already-correct task is
    /// skipped, so a repair pass that changes nothing leaves `report.changed` false and
    /// `performStartupMaintenance` does not save.
    private static func rePointTasksAlreadyIn(
        _ project: Project,
        in store: ContainerMergeStore,
        report: inout DataIntegrityRepairReport
    ) {
        let resolved = project.resolvedContext
        for task in store.tasks where task.project === project {
            guard task.context !== resolved else { continue }
            task.context = resolved
            report.movedTasks += 1
        }
    }

    /// Which copy of a same-named group survives the merge.
    ///
    /// **The lowest `id.uuidString`, and nothing else, because the rule has to give the same answer
    /// on every device** ([[T-3101]]). It used to be a `contextScore` that counted the areas,
    /// projects, tasks, goals and habits *this device could currently see*, minus `order` — every
    /// term of which is local. `PersistenceController.performStartupMaintenance` runs this service
    /// the instant the container opens, with no gate on CloudKit sync state ([[T-328]]), so two
    /// devices part-way through importing the same pair score it oppositely, each deletes the copy
    /// the other kept, and both deletes then sync: the group's children end up re-pointed at a row
    /// that no longer exists anywhere, i.e. `context == nil` on every one of them. [[T-622]] states
    /// the shape outright — a rule that reads local state "is not a tie-break, it is a second fork"
    /// — and `CadenceTaskRecurrenceWorkflowSupport.collapsibleDuplicateOccurrences` has defended
    /// the smaller case this way since. `id` is immutable, travels with the CloudKit record and is
    /// totally ordered, so every device that can see the group computes the same survivor with no
    /// coordination.
    ///
    /// **Nothing is lost by giving up the score**, which is why this is a strictly better rule
    /// rather than a trade. `mergeContext` re-points all six of the duplicate's to-many
    /// relationships into the survivor before deleting it, so the children go to the same place
    /// whichever row wins; the score only ever decided which row's own *fields* were kept, and
    /// `mergeContextFields` now carries what it can of those across instead.
    private static func canonicalContext(among group: [Context]) -> Context? {
        group.min { $0.id.uuidString < $1.id.uuidString }
    }

    private static func areaScore(_ area: Area, in store: ContainerMergeStore) -> Int {
        let taskCount = store.tasks.filter { $0.area === area }.count
        let projectCount = store.projects.filter { $0.area === area }.count
        let noteCount = store.notes.filter { $0.area === area }.count
        let documentCount = store.documents.filter { $0.area === area }.count
        return taskCount + projectCount * 10 + noteCount * 5 + documentCount * 5
    }

    private static func projectScore(_ project: Project, in store: ContainerMergeStore) -> Int {
        let taskCount = store.tasks.filter { $0.project === project }.count
        let noteCount = store.notes.filter { $0.project === project }.count
        let documentCount = store.documents.filter { $0.project === project }.count
        return taskCount + noteCount * 5 + documentCount * 5
    }

    private static func repairDuplicateNotes(
        in store: RepairStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) throws {
        let grouped = Dictionary(grouping: store.notes) { $0.canonicalKey }
        var redirects: [UUID: UUID] = [:]

        for group in grouped.values where group.count > 1 {
            let liveNotes = group.filter { !state.deletedNotes.contains(ObjectIdentifier($0)) }
            guard liveNotes.count > 1,
                  let canonical = liveNotes.max(by: { preferredNoteSort($0, $1) }) else {
                continue
            }

            for duplicate in liveNotes where duplicate !== canonical {
                guard !state.deletedNotes.contains(ObjectIdentifier(duplicate)) else { continue }
                let mergedAwayID = duplicate.id
                mergeNote(duplicate, into: canonical, modelContext: modelContext, state: &state, report: &report)
                if mergedAwayID != canonical.id {
                    redirects[mergedAwayID] = canonical.id
                }
            }
        }

        // T-3115 part 3. Inside this pass, so the re-pointed references land in the same save as
        // the merge that would otherwise have stranded them.
        guard !redirects.isEmpty else { return }
        let liveNotes = store.notes.filter { !state.deletedNotes.contains(ObjectIdentifier($0)) }
        let tasks = try fetchTasks(FetchDescriptor<AppTask>(), in: modelContext, report: &report)
        report.noteReferencesRedirected += try redirectNoteReferences(
            redirects,
            in: modelContext,
            notes: liveNotes,
            tasks: tasks
        )
    }

    /// The entities `redirectNoteReferences` rewrites, compared to `CadenceMarkdownSourceInventory`
    /// by `DataIntegrityRepairServiceTests` so a new markdown source has to be decided here too.
    static let noteReferenceRedirectEntityNames: Set<String> = [
        "Note", "AppTask", "Document", "DailyNote", "WeeklyNote", "PermNote", "EventNote",
    ]

    /// **The one place a note merge re-points the references to the copy it deleted** ([[T-3115]]
    /// part 3), and the function any future note-merging path must call in the same save.
    ///
    /// An id-named reference deliberately never falls back to its label (`NoteReferenceTarget`),
    /// so a merge that drops the loser's UUID would otherwise leave every inbound
    /// `[[note:<loser>|Title]]` dead for good. Every markdown field in the store that can hold one
    /// is rewritten through `NoteReferenceParser.redirectingNoteReferences`, which changes the id
    /// slot only and leaves the label as written.
    ///
    /// The fields are `CadenceMarkdownSourceInventory.Source` minus one: `Note.content`,
    /// `AppTask.notes`, and the legacy `Document` / `DailyNote` / `WeeklyNote` / `PermNote` /
    /// `EventNote` bodies (still live text; a not-yet-folded legacy row would otherwise carry a dead
    /// reference into the `Note` it becomes). **Not** `NoteTemplatePreference.overridesRaw`: that
    /// row is mirrored to `UserDefaults` by `CadenceNoteTemplatePreferenceStore`, and writing the
    /// row behind the mirror's back is a second, worse bug than a stale id in a stencil. The
    /// inventory is not compiled by `CadenceMCPServer`, which runs this service, so the list is
    /// spelled here and `DataIntegrityRepairServiceTests` compares it to the inventory.
    ///
    /// `redirects` maps a merged-away id to its survivor; a chain (`a -> b`, `b -> c`) is followed
    /// to its end. Rows already deleted in this context are skipped. Returns how many references
    /// were re-pointed; a fetch failure throws, because a merge whose references could not be
    /// re-pointed must not be saved as if they had been.
    static func redirectNoteReferences(
        _ redirects: [UUID: UUID],
        in modelContext: ModelContext,
        notes: [Note]? = nil,
        tasks: [AppTask]? = nil
    ) throws -> Int {
        let resolved = resolvedRedirects(redirects)
        guard !resolved.isEmpty else { return 0 }
        var redirected = 0
        func rewrite<Model: PersistentModel>(
            _ rows: [Model],
            at keyPath: ReferenceWritableKeyPath<Model, String>
        ) {
            for row in rows where !row.isDeleted {
                let result = NoteReferenceParser.redirectingNoteReferences(
                    in: row[keyPath: keyPath],
                    redirects: resolved
                )
                guard result.redirected > 0 else { continue }
                row[keyPath: keyPath] = result.content
                redirected += result.redirected
            }
        }
        rewrite(try notes ?? modelContext.fetch(FetchDescriptor<Note>()), at: \.content)
        rewrite(try tasks ?? modelContext.fetch(FetchDescriptor<AppTask>()), at: \.notes)
        rewrite(try modelContext.fetch(FetchDescriptor<Document>()), at: \.content)
        rewrite(try modelContext.fetch(FetchDescriptor<DailyNote>()), at: \.content)
        rewrite(try modelContext.fetch(FetchDescriptor<WeeklyNote>()), at: \.content)
        rewrite(try modelContext.fetch(FetchDescriptor<PermNote>()), at: \.content)
        rewrite(try modelContext.fetch(FetchDescriptor<EventNote>()), at: \.content)
        return redirected
    }

    /// Follows each chain to the id that survives, and stops on a cycle rather than looping.
    private static func resolvedRedirects(_ redirects: [UUID: UUID]) -> [UUID: UUID] {
        var resolved: [UUID: UUID] = [:]
        for start in redirects.keys {
            var seen: Set<UUID> = [start]
            var current = start
            while let next = redirects[current], !seen.contains(next) {
                seen.insert(next)
                current = next
            }
            if current != start { resolved[start] = current }
        }
        return resolved
    }

    private static func mergeNote(
        _ source: Note,
        into target: Note,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) {
        guard !state.deletedNotes.contains(ObjectIdentifier(source)) else { return }

        mergeNoteFields(from: source, into: target)
        modelContext.delete(source)
        state.deletedNotes.insert(ObjectIdentifier(source))
        report.duplicateNotesMerged += 1
    }

    private static func mergeNoteFields(from source: Note, into target: Note) {
        let targetTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if (targetTitle.isEmpty || targetTitle == "Untitled"), !sourceTitle.isEmpty, sourceTitle != "Untitled" {
            target.title = source.title
        }

        let targetContent = target.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceContent = source.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceContent.isEmpty, !targetContent.contains(sourceContent) {
            target.content = targetContent.isEmpty ? source.content : "\(target.content)\n\n---\n\n\(source.content)"
        }

        target.createdAt = min(target.createdAt, source.createdAt)
        target.updatedAt = max(target.updatedAt, source.updatedAt)
        fillEmptyString(\.dateKey, on: target, from: source)
        fillEmptyString(\.weekKey, on: target, from: source)
        fillEmptyString(\.calendarEventID, on: target, from: source)
        fillEmptyString(\.calendarID, on: target, from: source)
        fillEmptyString(\.eventDateKey, on: target, from: source)
        fillEmptyString(\.legacySourceKindRaw, on: target, from: source)
        fillEmptyString(\.legacySourceID, on: target, from: source)
        fillEmptyString(\.folderPath, on: target, from: source)

        if target.eventStartMin < 0, source.eventStartMin >= 0 {
            target.eventStartMin = source.eventStartMin
        }
        if target.eventEndMin < 0, source.eventEndMin >= 0 {
            target.eventEndMin = source.eventEndMin
        }
        if target.area == nil {
            target.area = source.area
        }
        if target.project == nil {
            target.project = source.project
        }

        target.tags = mergedTags(primary: target.tags ?? [], secondary: source.tags ?? [])
    }

    private static func fillEmptyString(_ keyPath: ReferenceWritableKeyPath<Note, String>, on target: Note, from source: Note) {
        if target[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target[keyPath: keyPath] = source[keyPath: keyPath]
        }
    }

    private static func mergedTags(primary: [Tag], secondary: [Tag]) -> [Tag] {
        var tagsByID: [UUID: Tag] = [:]
        for tag in primary + secondary {
            tagsByID[tag.id] = tag
        }
        return TagSupport.sorted(Array(tagsByID.values))
    }

    private static func preferredNoteSort(_ lhs: Note, _ rhs: Note) -> Bool {
        let lhsScore = noteScore(lhs)
        let rhsScore = noteScore(rhs)
        if lhsScore != rhsScore { return lhsScore < rhsScore }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func noteScore(_ note: Note) -> Int {
        var score = 0
        if !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += min(note.content.count, 2_000)
        }
        if !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.title != "Untitled" {
            score += 100
        }
        score += (note.tags ?? []).count * 20
        if note.area != nil { score += 20 }
        if note.project != nil { score += 20 }
        if !note.calendarID.isEmpty { score += 10 }
        if !note.eventDateKey.isEmpty { score += 10 }
        if note.eventStartMin >= 0 { score += 5 }
        if note.eventEndMin >= 0 { score += 5 }
        return score
    }

    private static func normalizedName(_ context: Context) -> String {
        normalizedContextName(context.name)
    }

    /// **The key two active contexts are fused on**, exposed so the two surfaces that create a
    /// context can refuse the name this pass would later fuse ([[T-3125]]).
    ///
    /// The owner's decision of 2026-10-22 is to refuse a duplicate name at creation rather than to
    /// narrow this merge — narrowing it would take `mergeArea` and `mergeProject` with it, since
    /// `mergeContext` is their only entry point. A guard that spells its own rule would be a second
    /// definition of "the same name", and the guard and the merge disagreeing is the one way this
    /// fix can fail: a name the guard allows and this pass fuses loses the separation with no undo.
    /// So both read this.
    ///
    /// `isArchived` is **not** folded in here. `repair` groups `activeContexts` and each caller
    /// filters its own rows, because an archived context is not in any picker and is not the
    /// duplicate the user sees.
    static func normalizedContextName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The **active** context `name` would be fused with, or `nil` when creating it is safe
    /// ([[T-3125]]).
    ///
    /// One function rather than a guard on each creating surface. There are two — the iOS context
    /// editor and MCP `create_context` — and the failure mode a second copy of this rule brings is
    /// specific: a surface whose guard is *looser* than the merge still creates the pair, and the
    /// separation is then lost at the next launch with no undo. The surfaces decide what to say
    /// about the answer; what counts as the same name is decided here, beside the merge that acts
    /// on it.
    ///
    /// An **empty** name is never a clash. `repair` filters `normalizedName($0).isEmpty` out of its
    /// grouping, so unnamed contexts are not fused with each other, and both surfaces refuse an
    /// empty name on their own terms before reaching this.
    ///
    /// Archived rows are skipped, matching `activeContexts`: an archived context is in no picker,
    /// is not the duplicate the user sees, and is not what the merge groups.
    ///
    /// `excluding` is the row being **renamed** ([[T-4722]]): a rename writes the name onto a row
    /// that already exists, so that row is not a second copy of itself. Without it, fixing the
    /// case of a list's own name ("work" to "Work") would be refused as a clash with itself.
    static func activeContextSharingName(
        _ name: String,
        among contexts: [Context],
        excluding renamed: Context? = nil
    ) -> Context? {
        let normalized = normalizedContextName(name)
        guard !normalized.isEmpty else { return nil }
        let renamedID = renamed?.persistentModelID
        return contexts.first {
            !$0.isArchived && $0.persistentModelID != renamedID && normalizedContextName($0.name) == normalized
        }
    }

    /// A name no **active** context carries: `name` itself when it is free, else `name` under the
    /// lowest free `" (n)"` starting at 2 ([[T-4910]]).
    ///
    /// **Why a suffix and not a refusal.** The three writers that un-archive a context — iOS
    /// `iOSSettingsView.restore`, macOS `SettingsView.restoreContext` and MCP `update_context` with
    /// `isArchived: false` — wrote `isArchived = false` unconditionally, so restoring a context
    /// whose name an active row has since taken made exactly the duplicate pair this
    /// service's `mergeContext` fuses on the next launch, with no undo. The owner's
    /// decision of 2026-10-24 is to restore under a suffixed name rather than refuse: you cannot
    /// pick a name from a Restore button, so a refusal leaves the user at a dead end with no way
    /// forward from the control they pressed. A suffixed name is one they can then rename.
    ///
    /// **Creation and rename are deliberately not routed here.** [[T-3125]] and [[T-4722]] refuse,
    /// and should: both reach the user through a field they are already typing in, so there is a
    /// name to pick and `CadenceContextNameClashCopy` asks them to pick it. Restore is the one
    /// entry point with no field.
    ///
    /// `excluding` is the row being restored, for `activeContextSharingName`'s own reason — a row
    /// is not a second copy of itself. The clash test is that function, not a second spelling of
    /// it, so what counts as "taken" here is what the merge groups on: trimmed and case-folded.
    /// An **empty** name is never a clash there, so it is returned unsuffixed here.
    ///
    /// **The suffix is built on the trimmed name**, although a free name comes back exactly as it
    /// was given. `normalizedContextName` trims, so suffixing a name with trailing space would put
    /// the space *inside* the key — `"Work "` becoming `"Work  (2)"`, which is a different key
    /// from the `"Work (2)"` already here and so reads as free. Climbing on the trimmed base means
    /// the numbers this walks are the numbers the clash test sees.
    ///
    /// Terminates: each candidate is distinct and each taken one needs a distinct row of
    /// `contexts`, so the loop cannot outrun a finite table.
    static func availableContextName(
        _ name: String,
        among contexts: [Context],
        excluding restored: Context? = nil
    ) -> String {
        guard activeContextSharingName(name, among: contexts, excluding: restored) != nil else { return name }
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var suffix = 2
        while true {
            let candidate = "\(base) (\(suffix))"
            if activeContextSharingName(candidate, among: contexts, excluding: restored) == nil { return candidate }
            suffix += 1
        }
    }

    /// Carries across what can be carried of the copy this merge is about to delete.
    ///
    /// [[T-3101]]: `mergeArea` and `mergeProject` have had a field merge since they were written
    /// and `mergeContext` never did, so the loser's `colorHex`, `icon` and `order` went with the
    /// row. Those are the marks that tell one list from another in the sidebar, and a merge that
    /// drops them is why a user looking at the survivor cannot tell what happened.
    ///
    /// **The honest limit, stated rather than implied: one row holds one colour.** Where both
    /// copies carry a colour the user chose, the loser's is still gone — there is nowhere to put
    /// it. What this recovers is the case the audit actually describes, a *second* copy the user
    /// decorated while the first was left as it was born;
    /// `DataIntegrityRepairServiceTests.mergingDuplicateContextsKeepsTheDecorationOnlyTheDeletedCopyHad`
    /// is the test for it. `unstyledContextColorHex` / `unstyledContextIcon` below are what make
    /// "left as it was born" a question the store can answer; everything here reads only the two
    /// rows' own fields, so two devices merging the same pair write the same result.
    ///
    /// **Two fields are deliberately not merged.**
    /// - `name`: the group key is `normalizedName`, so both copies already hold the same name up
    ///   to case and surrounding whitespace. There is no second name to keep, only a second
    ///   spelling, and the survivor's is as good as the loser's.
    /// - `isArchived`: `repair` groups `activeContexts` only, so every member of a group is
    ///   already `false`. A line here would be unreachable, and an unreachable line is worse than
    ///   the absent one it replaces.
    private static func mergeContextFields(from source: Context, into target: Context) {
        if target.colorHex == unstyledContextColorHex, source.colorHex != unstyledContextColorHex {
            target.colorHex = source.colorHex
        }
        if target.icon == unstyledContextIcon, source.icon != unstyledContextIcon {
            target.icon = source.icon
        }
        // Lower `order` is nearer the top of the sidebar, so the merged row keeps the more
        // prominent of the two slots. `min` is commutative, which matters: it is the one field
        // here whose answer must not depend on which copy the survivor rule happened to pick.
        target.order = min(target.order, source.order)
    }

    /// The appearance `Context.init` gives a row nobody has styled.
    ///
    /// **A second spelling of the model's own defaults, and deliberately not a constant on
    /// `Context`.** `Cadence/Models/*.swift`'s `colorHex` defaults are literals because
    /// `CadenceMCPServer` compiles `Models/` and not `Theme.swift` ([[T-262]]), and
    /// `CadenceSeedColourSourceTests.theSeedsMirrorModelDefaultsThatCannotReadTheToken` pins each
    /// of those four files to the standard palette's blue *by its source text*. Pointing the
    /// stored default at a named constant would have been a quiet rewrite of that guard, which is
    /// not this ticket's to make.
    ///
    /// **So the drift is closed from the other end, behaviourally rather than by a second source
    /// scan.** `DataIntegrityRepairServiceTests.mergingDuplicateContextsKeepsTheDecorationOnlyTheDeletedCopyHad`
    /// builds its surviving copy with `Context(name:)` and **no** appearance arguments, so that row
    /// carries whatever the model's defaults are on the day the test runs. Move either default and
    /// these two stop matching it, the merge stops recognising an unstyled row, and that test goes
    /// red naming the field — which is the signal a `#expect(a == b)` over two constants could not
    /// give.
    private static let unstyledContextColorHex = "#4a9eff"
    private static let unstyledContextIcon = "square.stack.fill"

    private static func mergeAreaFields(from source: Area, into target: Area) {
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
        }
        target.loggedMinutes = max(target.loggedMinutes, source.loggedMinutes)
        target.hideDueDateIfEmpty = target.hideDueDateIfEmpty && source.hideDueDateIfEmpty
        target.hideSectionDueDateIfEmpty = target.hideSectionDueDateIfEmpty && source.hideSectionDueDateIfEmpty
        target.sectionConfigs = mergedSectionConfigs(primary: target.sectionConfigs, secondary: source.sectionConfigs)
        if target.status != .active && source.status == .active {
            target.status = .active
        }
    }

    private static func mergeProjectFields(from source: Project, into target: Project) {
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
        }
        if target.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.dueDate = source.dueDate
        }
        target.loggedMinutes = max(target.loggedMinutes, source.loggedMinutes)
        target.hideDueDateIfEmpty = target.hideDueDateIfEmpty && source.hideDueDateIfEmpty
        target.hideSectionDueDateIfEmpty = target.hideSectionDueDateIfEmpty && source.hideSectionDueDateIfEmpty
        target.sectionConfigs = mergedSectionConfigs(primary: target.sectionConfigs, secondary: source.sectionConfigs)
        if target.status != .active && source.status == .active {
            target.status = .active
        }
    }

    private static func mergedSectionConfigs(primary: [TaskSectionConfig], secondary: [TaskSectionConfig]) -> [TaskSectionConfig] {
        var result = primary
        var seen = Set(primary.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for config in secondary {
            let key = config.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(config)
        }
        return result
    }

    private static func record(_ report: DataIntegrityRepairReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        CadenceDefaults.store.set(data, forKey: lastReportKey)
    }

    private static func log(_ report: DataIntegrityRepairReport) {
        guard report.changed else { return }
        logger.info(
            "Data integrity repair merged contexts=\(report.duplicateContextsMerged, privacy: .public), areas=\(report.duplicateAreasMerged, privacy: .public), projects=\(report.duplicateProjectsMerged, privacy: .public), notes=\(report.duplicateNotesMerged, privacy: .public), tasks=\(report.duplicateTasksMerged, privacy: .public), habitCompletions=\(report.duplicateHabitCompletionsRemoved, privacy: .public), habitReminders=\(report.habitRemindersCleared, privacy: .public), movedTasks=\(report.movedTasks, privacy: .public) from \(report.source, privacy: .public)"
        )
    }
}

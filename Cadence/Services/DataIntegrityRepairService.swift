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

    var changed: Bool {
        duplicateContextsMerged > 0 ||
            duplicateAreasMerged > 0 ||
            duplicateProjectsMerged > 0 ||
            duplicateNotesMerged > 0 ||
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
            movedGoalLinks > 0
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
/// a silent skip: `CadenceStoreMaintenance.prepare` says so at its call. The app supplies
/// `CadenceForkedOccurrenceRemover.removeAndCancelReminders`, and
/// `DataIntegrityRepairServiceTests.theAppStartupRepairSuppliesTheForkedOccurrenceRemover` pins
/// that it does — the one thing a default of `nil` cannot enforce on its own.
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
/// `Project` and `Note` rows, collapses duplicate habit-days and forked recurring occurrences, and
/// re-points the tasks, notes, documents, links and goal links each merge would otherwise strand.
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
/// container opens, with no gate on sync state at all, so on a fresh device — or any launch that
/// races the first sync — a `Subtask` with no `parentTask` is indistinguishable from one whose
/// `AppTask` has not arrived yet. Deleting it is unrecoverable, and it is the *empty* store that
/// would delete the most. "Repair found nothing to do" is the correct behaviour there; "repair
/// deleted the rows whose owners were still in flight" is not.
///
/// So a future orphan sweep is not a matter of adding four fetches. It needs a reason to believe
/// the store is complete — a sync-state gate, a user-initiated entry point instead of startup, or a
/// report-only pass that counts without deleting. Until one of those exists, the honest position is
/// that this covers duplicates and says so. `DataIntegrityRepairServiceTests` pins the boundary by
/// value so it cannot be crossed by accident.
nonisolated enum DataIntegrityRepairService {
    private struct RepairState {
        var deletedAreas = Set<ObjectIdentifier>()
        var deletedProjects = Set<ObjectIdentifier>()
        var deletedContexts = Set<ObjectIdentifier>()
        var deletedNotes = Set<ObjectIdentifier>()
    }

    private struct RepairStore {
        var contexts: [Context]
        var areas: [Area]
        var projects: [Project]
        var tasks: [AppTask]
        var goals: [Goal]
        var habits: [Habit]
        var notes: [Note]
        var documents: [Document]
        var links: [SavedLink]
        var goalLinks: [GoalListLink]
        var habitCompletions: [HabitCompletion]
    }

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "DataIntegrity")
    private static let lastReportKey = "dataIntegrityRepair.lastReport.v1"

    @discardableResult
    static func repairIfNeeded(
        in context: ModelContext,
        source: String = "unknown",
        saveChanges: Bool = true,
        removingForkedOccurrences remove: CadenceForkedOccurrenceRemoval? = nil
    ) throws -> DataIntegrityRepairReport {
        var report = DataIntegrityRepairReport(
            source: source,
            startedAt: Date(),
            finishedAt: Date(),
            success: false
        )

        do {
            try repair(in: context, remove: remove, report: &report)
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
        removingForkedOccurrences remove: CadenceForkedOccurrenceRemoval? = nil
    ) -> DataIntegrityRepairReport? {
        do {
            return try repairIfNeeded(
                in: context,
                source: source,
                saveChanges: saveChanges,
                removingForkedOccurrences: remove
            )
        } catch {
            return lastReport()
        }
    }

    static func lastReport() -> DataIntegrityRepairReport? {
        guard let data = UserDefaults.standard.data(forKey: lastReportKey) else { return nil }
        return try? JSONDecoder().decode(DataIntegrityRepairReport.self, from: data)
    }

    private static func repair(
        in context: ModelContext,
        remove: CadenceForkedOccurrenceRemoval?,
        report: inout DataIntegrityRepairReport
    ) throws {
        let store = try RepairStore(
            contexts: context.fetch(FetchDescriptor<Context>()),
            areas: context.fetch(FetchDescriptor<Area>()),
            projects: context.fetch(FetchDescriptor<Project>()),
            tasks: context.fetch(FetchDescriptor<AppTask>()),
            goals: context.fetch(FetchDescriptor<Goal>()),
            habits: context.fetch(FetchDescriptor<Habit>()),
            notes: context.fetch(FetchDescriptor<Note>()),
            documents: context.fetch(FetchDescriptor<Document>()),
            links: context.fetch(FetchDescriptor<SavedLink>()),
            goalLinks: context.fetch(FetchDescriptor<GoalListLink>()),
            habitCompletions: context.fetch(FetchDescriptor<HabitCompletion>())
        )
        var state = RepairState()

        let activeContexts = store.contexts.filter { !$0.isArchived && !normalizedName($0).isEmpty }
        let groups = Dictionary(grouping: activeContexts) { normalizedName($0) }

        for group in groups.values where group.count > 1 {
            guard let canonical = group.max(by: { contextScore($0, in: store) < contextScore($1, in: store) }) else {
                continue
            }

            for duplicate in group where duplicate !== canonical {
                mergeContext(duplicate, into: canonical, in: store, modelContext: context, state: &state, report: &report)
            }
        }

        repairDuplicateNotes(in: store, modelContext: context, state: &state, report: &report)
        repairDuplicateHabitCompletions(in: store, modelContext: context, report: &report)
        repairDuplicateRecurrenceOccurrences(
            in: store,
            modelContext: context,
            remove: remove,
            report: &report
        )
        repairOutOfRangeHabitReminders(in: store, report: &report)
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
    /// `repairOutOfRangeHabitReminders` above and it is placed beside it deliberately.
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
        }
    }

    /// The exact string `Note.title` defaulted to before T-733. Matched untrimmed and
    /// case-sensitively: `" Untitled "` and `"untitled"` are things a person typed, and this pass
    /// is only entitled to the value the old initializer wrote.
    private static let retiredStoredNoteTitleDefault = "Untitled"

    /// T-428: a `Habit.reminderMinuteOfDay` already on disk outside `0...1439` is invisible **and**
    /// inert, and until this pass nothing moved it. `HabitNotificationPlanner.reminder(for:now:)`
    /// skips it (T-363), so it schedules nothing; both editors open it as no reminder (T-410), so
    /// it shows nothing. The user cannot see the value, cannot act on it, and the habit quietly
    /// has no reminder while the field says otherwise. Clearing it to `nil` is the app agreeing
    /// with itself: `nil` is what every reader already behaves as if it read.
    ///
    /// **Cleared, not clamped.** `1440` is not 23:59 and `-15` is not 00:00; a clamp invents a
    /// time the user never chose and then schedules a real daily alarm at it, which is the
    /// `?? now` failure T-363 removed from the planner wearing a tidier number. `nil` says "no
    /// reminder", which is both true and repairable — the pickers can set a real one.
    ///
    /// **Why this is allowed where an orphan sweep is not ([[T-328]]).** The boundary above is not
    /// "repair never deletes"; it is that repair must stay *conservative under partial CloudKit
    /// sync*, because `PersistenceController.performStartupMaintenance` runs it the instant the
    /// container opens with no gate on sync state. What makes an orphan sweep unsafe there is that
    /// its predicate is a claim about a **second row**: "this `Subtask` has no `parentTask`" is
    /// indistinguishable from "its `AppTask` has not arrived yet", so the emptier the store the
    /// more it destroys. This predicate reads **one scalar on the row in front of it**. No record
    /// arriving later can make `1440` a minute of the day, so a half-synced store cannot produce a
    /// false positive here — it simply sees fewer `Habit` rows and repairs fewer of them, which is
    /// the same monotonicity the merges have. It also clears a field rather than deleting a row,
    /// and the field it clears is one no surface can render and no reconcile can schedule.
    ///
    /// The pass is idempotent and order-independent across devices, so a device that has not run
    /// it yet re-syncing the corrupt value is not a loop: every device writes the same `nil`.
    ///
    /// `DataIntegrityRepairServiceTests.repairLeavesOrphanedRowsAloneRatherThanCollectingThemAtStartup`
    /// still holds — that store has no `Habit` in it at all, and a habit whose reminder is `nil`
    /// or in range is left alone here, so `changed` stays `false` for a store with nothing wrong.
    private static func repairOutOfRangeHabitReminders(
        in store: RepairStore,
        report: inout DataIntegrityRepairReport
    ) {
        for habit in store.habits {
            guard let minuteOfDay = habit.reminderMinuteOfDay else { continue }
            guard !HabitReminderTime.namesATimeOfDay(minuteOfDay) else { continue }
            habit.reminderMinuteOfDay = nil
            report.habitRemindersCleared += 1
        }
    }

    /// T-359: two devices can each mint a `HabitCompletion` for the same habit and the same day.
    /// The `id`s differ, so CloudKit keeps both, and before this pass `completionCountsByDate()`
    /// added them — one real check-in satisfying a `targetCount` of 2, or a `.timesPerWeek` target
    /// reached with half the check-ins it names.
    ///
    /// This is [[T-328]]'s missing fetch, not a second repair mechanism beside it: that ticket
    /// counted `HabitCompletion` among the models this service never looks at, and the fetch above
    /// is now one of the ones it does.
    ///
    /// The collapse rule is `CadenceHabitCompletionStore`'s, deliberately not restated here — the
    /// read (`HabitCompletion.collapsedCount(of:)`), the writer and this pass have to agree about
    /// what a duplicated habit-day is worth, and the way they agree is by being one function.
    ///
    /// Grouped by **`(habit.id, date)`** rather than by habit instance, because two `Habit` rows
    /// carrying one `id` is a state a restore can leave behind and their days are the same day.
    /// Rows with no habit are left alone: an unowned completion is an orphan, which is the other
    /// half of [[T-328]] and not this ticket. Rows with an empty `date` are left alone too — they
    /// describe no day, so "the same day twice" is not a claim that can be made about them.
    private static func repairDuplicateHabitCompletions(
        in store: RepairStore,
        modelContext: ModelContext,
        report: inout DataIntegrityRepairReport
    ) {
        struct HabitDay: Hashable {
            let habitID: UUID
            let date: String
        }

        var rowsByDay: [HabitDay: [HabitCompletion]] = [:]
        for completion in store.habitCompletions {
            guard let habit = completion.habit, !completion.date.isEmpty else { continue }
            rowsByDay[HabitDay(habitID: habit.id, date: completion.date), default: []].append(completion)
        }

        for rows in rowsByDay.values where rows.count > 1 {
            report.duplicateHabitCompletionsRemoved += CadenceHabitCompletionStore.collapseDuplicates(
                rows,
                modelContext: modelContext
            )
        }
    }

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
    /// survivor rule and the removability test, deliberately not restated here: the same reason
    /// the habit-day collapse lives in `CadenceHabitCompletionStore`.
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
        in store: RepairStore,
        modelContext: ModelContext,
        remove: CadenceForkedOccurrenceRemoval?,
        report: inout DataIntegrityRepairReport
    ) {
        guard let remove else { return }
        let groups = CadenceTaskRecurrenceWorkflowSupport.duplicateOccurrenceGroups(among: store.tasks)
        var survivorByRemovedID: [UUID: UUID] = [:]
        for group in groups {
            guard let collapse = CadenceTaskRecurrenceWorkflowSupport
                .collapsibleDuplicateOccurrences(among: group) else { continue }
            for removed in collapse.removable {
                survivorByRemovedID[removed.id] = collapse.survivor.id
            }
        }
        guard !survivorByRemovedID.isEmpty else { return }

        // Recorded before the delete, while the pointers still name the rows that are going.
        var rePointing: [(AppTask, UUID)] = []
        for task in store.tasks where survivorByRemovedID[task.id] == nil {
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

    private static func mergeContext(
        _ duplicate: Context,
        into canonical: Context,
        in store: RepairStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) {
        guard !state.deletedContexts.contains(ObjectIdentifier(duplicate)) else { return }

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

        modelContext.delete(duplicate)
        state.deletedContexts.insert(ObjectIdentifier(duplicate))
        report.duplicateContextsMerged += 1
    }

    @discardableResult
    private static func mergeArea(
        _ source: Area,
        intoContext canonicalContext: Context,
        in store: RepairStore,
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
        in store: RepairStore,
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
        in store: RepairStore,
        report: inout DataIntegrityRepairReport
    ) {
        let resolved = project.resolvedContext
        for task in store.tasks where task.project === project {
            guard task.context !== resolved else { continue }
            task.context = resolved
            report.movedTasks += 1
        }
    }

    private static func contextScore(_ context: Context, in store: RepairStore) -> Int {
        let areaCount = store.areas.filter { $0.context === context }.count
        let projectCount = store.projects.filter { $0.context === context }.count
        let taskCount = store.tasks.filter { $0.context === context }.count
        let goalCount = store.goals.filter { $0.context === context }.count
        let habitCount = store.habits.filter { $0.context === context }.count
        return areaCount * 25 + projectCount * 20 + taskCount + goalCount * 10 + habitCount * 10 - context.order
    }

    private static func areaScore(_ area: Area, in store: RepairStore) -> Int {
        let taskCount = store.tasks.filter { $0.area === area }.count
        let projectCount = store.projects.filter { $0.area === area }.count
        let noteCount = store.notes.filter { $0.area === area }.count
        let documentCount = store.documents.filter { $0.area === area }.count
        return taskCount + projectCount * 10 + noteCount * 5 + documentCount * 5
    }

    private static func projectScore(_ project: Project, in store: RepairStore) -> Int {
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
    ) {
        let grouped = Dictionary(grouping: store.notes) { $0.canonicalKey }

        for group in grouped.values where group.count > 1 {
            let liveNotes = group.filter { !state.deletedNotes.contains(ObjectIdentifier($0)) }
            guard liveNotes.count > 1,
                  let canonical = liveNotes.max(by: { preferredNoteSort($0, $1) }) else {
                continue
            }

            for duplicate in liveNotes where duplicate !== canonical {
                mergeNote(duplicate, into: canonical, modelContext: modelContext, state: &state, report: &report)
            }
        }
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
        context.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

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
        UserDefaults.standard.set(data, forKey: lastReportKey)
    }

    private static func log(_ report: DataIntegrityRepairReport) {
        guard report.changed else { return }
        logger.info(
            "Data integrity repair merged contexts=\(report.duplicateContextsMerged, privacy: .public), areas=\(report.duplicateAreasMerged, privacy: .public), projects=\(report.duplicateProjectsMerged, privacy: .public), notes=\(report.duplicateNotesMerged, privacy: .public), habitCompletions=\(report.duplicateHabitCompletionsRemoved, privacy: .public), habitReminders=\(report.habitRemindersCleared, privacy: .public), movedTasks=\(report.movedTasks, privacy: .public) from \(report.source, privacy: .public)"
        )
    }
}

import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-321 and T-366: two surfaces that reported success for a write that may never have landed.
///
/// - **T-321** — the iOS context editor, the iOS list editor and macOS's `EditListSheet` mutated,
///   ran `try? modelContext.save()` (or, for the Mac's Save button, no save at all) and dismissed.
///   The dismissal was the report of success and it happened either way. The list editor is the
///   worst of the three because it re-points every task in the list *before* the save, so a
///   swallowed failure left the reassignment half-applied with the editor closed over it.
/// - **T-366** — `TaskEmbedFieldEditorPopover` mutated the live task, swallowed the save, then
///   called `onChanged()` unconditionally. `onChanged()` repaints the note's rendered task card,
///   so the card showed values the store does not hold and nothing else on screen disagreed.
///
/// **Two halves, both load-bearing.** The behavioural half runs the commit units against a real
/// container with a refused `commit`, because that is where the decision now lives. The source
/// half pins that the four surfaces use them and that nothing reporting success sits above the
/// failure branch — `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so a
/// scan is the only tool available for two of the four views, and the other two are private
/// methods on SwiftUI views that no test can call either way.
@MainActor
struct CadenceEditorSaveCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - The edit commit itself

    /// The success path: the edit is in the store, and nothing is left pending for an autosave to
    /// finish later.
    @Test func acommittedEditIsInTheStoreBeforeTheEditorCouldClose() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        modelContext.insert(area)
        try modelContext.save()

        area.name = "Work & Life"
        var undoRan = false
        try CadencePendingChangePersistence.commitEdit(in: modelContext) {
            undoRan = true
        }
        #expect(!undoRan, "the undo ran on the success path")

        #expect(!modelContext.hasChanges)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Area>()).map(\.name) == ["Work & Life"])
    }

    /// The failure path, asserted from a **second context on the same container**: a single-context
    /// assertion passes against the bug, because the editor's own context reports the new name
    /// whether or not the save threw.
    @Test func arefusedEditRunsTheUndoAndRethrows() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        modelContext.insert(area)
        try modelContext.save()

        area.name = "Work & Life"
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitEdit(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                undo: { area.name = "Work" }
            )
        }

        #expect(area.name == "Work", "the editor is holding a name the store never took")
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Area>()).map(\.name) == ["Work"])
    }

    /// **What `rollback()` actually does to an edit, measured** — and why `commitEdit`'s undo is
    /// a snapshot while `commitDelete`'s is a rollback.
    ///
    /// The delete half is unconditional: rows marked deleted come back, which is what the cascades
    /// rely on. The edit half is *not* undone where anyone can see it until something refreshes the
    /// object: immediately after `rollback()` the live `Area` still answers with the assigned
    /// value, and only a fetch brings it back in line with the store. The store itself was never
    /// wrong.
    ///
    /// **The assertion order below is load-bearing.** The first version of this test fetched before
    /// reading the field and therefore measured the opposite result, which is exactly the trap: a
    /// fetch anywhere between the rollback and the read hides the staleness.
    ///
    /// So an editor cannot use `rollback()` and then truthfully say "Nothing was changed" — nothing
    /// guarantees a fetch happens first, and `EditAreaSheet` binds straight to the model rather
    /// than through a `@Query`. That is a *secondary* reason, though. The one that does not depend
    /// on SwiftData's refresh timing is `arefusedListEditLeavesUnrelatedPendingWorkAlone`: this is
    /// the app's single `ModelContext`, and a rollback discards work the editor knows nothing
    /// about.
    @Test func rollbackRestoresAnEditOnlyOnceSomethingRefreshesTheObject() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let kept = Area(name: "Work")
        let removed = Area(name: "Errands")
        modelContext.insert(kept)
        modelContext.insert(removed)
        try modelContext.save()

        kept.name = "Work & Life"
        modelContext.delete(removed)
        modelContext.rollback()

        // Read the field before anything fetches.
        #expect(
            kept.name == "Work & Life",
            """
            rollback now restores a live reference immediately. If that is genuinely fixed, \
            commitEdit may offer a rollback undo again — but the single-context objection stands.
            """
        )

        // The fetch is both the delete assertion and the thing that refreshes `kept`.
        #expect(
            try modelContext.fetch(FetchDescriptor<Area>()).count == 2,
            "rollback did not undo the delete, so commitDelete's undo is wrong too"
        )
        #expect(kept.name == "Work", "the fetch did not bring the live reference back in line")

        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Area>())
                .map(\.name).sorted() == ["Errands", "Work"],
            "the store took an edit that was never committed"
        )
    }

    /// The iOS list editor's edit branch reaches past the list into every task in it, and
    /// `CadenceListEditSnapshot` is what carries all of that back.
    @Test func arefusedListEditPutsTheListAndItsReassignedTasksBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let context = Context(name: "Personal")
        let first = AppTask(title: "Draft")
        let second = AppTask(title: "Review")
        modelContext.insert(area)
        modelContext.insert(context)
        for task in [first, second] {
            task.area = area
            task.sectionName = "Backlog"
            modelContext.insert(task)
        }
        area.sectionConfigs = [TaskSectionConfig(name: "Backlog")]
        try modelContext.save()
        // The stored blob, not the normalising `sectionConfigs` façade — that is what the snapshot
        // puts back, and the only value an exact-undo assertion can be written against.
        let sectionConfigsRawBefore = area.sectionConfigsRaw

        let tasks = [first, second]
        let undo = CadenceListEditSnapshot(area, tasks: tasks)

        // What `save()`'s edit branch does: rename the list, move it, rewrite the columns, then
        // re-point the tasks that named the column it renamed.
        area.name = "Work & Life"
        area.context = context
        area.sectionConfigs = [TaskSectionConfig(name: "Later")]
        first.sectionName = "Later"
        second.sectionName = "Later"

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitEdit(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                undo: undo.restore
            )
        }

        #expect(area.name == "Work")
        #expect(area.context == nil, "the list stayed in the context the refused save moved it to")
        #expect(area.sectionConfigsRaw == sectionConfigsRawBefore)
        #expect(area.sectionConfigs.contains { $0.name == "Backlog" })
        #expect(!area.sectionConfigs.contains { $0.name == "Later" })
        #expect([first.sectionName, second.sectionName] == ["Backlog", "Backlog"])
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Area>()).map(\.name) == ["Work"])
    }

    /// The snapshot undo leaves unrelated pending work alone — which is the other half of why it
    /// is not a rollback. `hasChanges` is the assertion that can tell the two apart; an equality
    /// check on the edited field cannot, because a live reference reads back whatever the context
    /// currently holds either way.
    @Test func arefusedListEditLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let unrelated = AppTask(title: "Being typed elsewhere")
        modelContext.insert(area)
        modelContext.insert(unrelated)
        try modelContext.save()

        unrelated.title = "Half-typed"
        let undo = CadenceListEditSnapshot(area)
        area.name = "Work & Life"

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitEdit(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                undo: undo.restore
            )
        }

        #expect(area.name == "Work")
        #expect(unrelated.title == "Half-typed")
        #expect(modelContext.hasChanges, "the undo discarded the unrelated pending edit as well")
    }

    /// macOS's lifecycle rows settle every task still open in the list before they commit, so the
    /// snapshot has to carry the statuses back too — otherwise a refused archive leaves the list
    /// active and its tasks cancelled.
    @Test func arefusedLifecycleChangePutsTheSettledTasksBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let open = AppTask(title: "Draft")
        open.area = area
        modelContext.insert(area)
        modelContext.insert(open)
        try modelContext.save()

        let remaining = TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
        #expect(remaining.map(\.title) == ["Draft"], "the fixture has no open task to settle")
        let undo = CadenceListEditSnapshot(area, tasks: remaining)

        area.status = .archived
        TaskContainerLifecycleService.settleRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            outcome: .cancelled,
            in: modelContext,
            reconciler: .inert
        )
        #expect(open.status == .cancelled, "the settle did nothing, so the undo below proves nothing")

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitEdit(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                undo: undo.restore
            )
        }

        #expect(area.status == .active)
        #expect(open.status == .todo)
        #expect(open.completedAt == nil)
    }

    /// The sentences the editors show, held next to the units that produce the failure so four
    /// surfaces cannot come to word the same event differently.
    @Test func thesaveFailureNoticesSayNothingWasChanged() {
        #expect(
            CadencePendingChangePersistence.editFailureNotice
                == "Couldn't save these changes. Nothing was changed."
        )
        #expect(CadenceTaskFieldEditCommit.saveFailureNotice == "Couldn't save this change.")
    }

    // MARK: - T-366: the embed field commit

    private func embeddedTask(in modelContext: ModelContext) -> AppTask {
        let task = AppTask(title: "Ship the fix")
        task.priority = .none
        task.sectionName = "Backlog"
        task.scheduledDate = "2026-06-01"
        task.dueDate = "2026-06-02"
        task.estimatedMinutes = 30
        modelContext.insert(task)
        return task
    }

    @Test func acommittedFieldEditReachesTheStoreAndReportsTrue() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        try modelContext.save()

        let landed = CadenceTaskFieldEditCommit.commit(task, in: modelContext) {
            task.priority = .high
            task.estimatedMinutes = 50
        }

        #expect(landed)
        let stored = try #require(try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.priority == .high)
        #expect(stored.estimatedMinutes == 50)
    }

    /// The card is refreshed on `true` and nothing else, so this is the assertion that stands in
    /// for "the note editor did not repaint the card".
    @Test func arefusedFieldEditReportsFalseAndPutsEveryFieldBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        try modelContext.save()

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        ) {
            task.priority = .high
            task.estimatedMinutes = 50
            task.sectionName = "Doing"
            task.scheduledDate = "2026-07-04"
            task.scheduledStartMin = 540
            task.dueDate = "2026-07-05"
        }

        #expect(!landed, "the popover would have repainted the card over a refused save")
        #expect(task.priority == .none)
        #expect(task.estimatedMinutes == 30)
        #expect(task.sectionName == "Backlog")
        #expect(task.scheduledDate == "2026-06-01")
        #expect(task.scheduledStartMin == -1)
        #expect(task.dueDate == "2026-06-02")

        let stored = try #require(try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.priority == .none)
        #expect(stored.scheduledDate == "2026-06-01")
    }

    /// The undo is a snapshot, not `rollback()`, and this is what says so: the popover opens over a
    /// note editor sharing this context, and a refused priority edit must not take the note text
    /// with it.
    @Test func arefusedFieldEditLeavesTheNoteBeingTypedAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        let note = Note(kind: .list, title: "Plan")
        modelContext.insert(note)
        try modelContext.save()

        note.content = "Half a sentence"

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        ) {
            task.priority = .high
        }

        #expect(!landed)
        #expect(task.priority == .none)
        #expect(note.content == "Half a sentence")
        #expect(
            modelContext.hasChanges,
            "the undo rolled the context back and took the note being typed with it"
        )
    }

    /// `markDone` mints the next occurrence of a recurring task and inserts it, which no field
    /// snapshot can restore. A refused status edit therefore has to delete it — otherwise the next
    /// successful save anywhere commits a task the user never completed anything to earn.
    @Test func arefusedCompletionTakesTheSpawnedNextOccurrenceBackOut() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        task.recurrenceRule = .daily
        task.scheduledDate = DateFormatters.todayKey()
        try modelContext.save()

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        ) {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        }

        #expect(!landed)
        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil, "the task still points at a successor")
        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1,
            "the spawned occurrence outlived the completion that minted it"
        )
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// A successor the task already had is not a successor this edit minted, so it must survive.
    @Test func arefusedEditLeavesAnAlreadySpawnedSuccessorAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        let successor = AppTask(title: "Tomorrow's occurrence")
        modelContext.insert(successor)
        task.recurrenceRule = .daily
        task.recurrenceSpawnedTaskID = successor.id
        try modelContext.save()

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        ) {
            task.priority = .high
        }

        #expect(!landed)
        #expect(task.recurrenceSpawnedTaskID == successor.id)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>()).count == 2)
    }

    /// `applyRecurrenceRule(scope: .thisAndFuture)` writes the rule to every later occurrence, so
    /// the popover hands those tasks in and all of them come back.
    @Test func arefusedSeriesRecurrenceEditRestoresEveryOccurrenceItTouched() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let first = embeddedTask(in: modelContext)
        let second = AppTask(title: "Ship the fix")
        modelContext.insert(second)
        first.recurrenceRule = .daily
        second.recurrenceRule = .daily
        first.recurrenceSpawnedTaskID = second.id
        first.recurrenceSeriesIDRaw = first.id.uuidString
        second.recurrenceSeriesIDRaw = first.id.uuidString
        try modelContext.save()

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: first,
            allTasks: [first, second],
            scope: .thisAndFuture
        )
        #expect(targets.count == 2, "the fixture is not a two-occurrence series")

        let landed = CadenceTaskFieldEditCommit.commit(
            first,
            alsoRestoring: targets,
            in: modelContext,
            reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        ) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                .weekly,
                to: first,
                allTasks: [first, second],
                scope: .thisAndFuture
            )
        }

        #expect(!landed)
        #expect(first.recurrenceRule == .daily)
        #expect(second.recurrenceRule == .daily, "the later occurrence kept a rule the store never took")
    }

    /// The date edits reconcile OS notifications as part of the mutation, before anyone knows the
    /// commit will be accepted. So the failure path reconciles again — **after** the restore, or it
    /// would re-derive the reminders from the values it just undid.
    @Test func therefusedDateEditReconcilesAgainstTheRestoredTask() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        try modelContext.save()

        final class Observed { var scheduledDate: String?; var runs = 0 }
        let observed = Observed()
        let recorder = CadenceWindDownReconciler(isLive: false) { _ in
            observed.runs += 1
            observed.scheduledDate = task.scheduledDate
        }

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: recorder,
            commit: { _ in throw CommitRefused() }
        ) {
            task.scheduledDate = "2026-07-04"
        }

        #expect(!landed)
        #expect(observed.runs == 1, "the failure path did not reconcile")
        #expect(
            observed.scheduledDate == "2026-06-01",
            "the reconcile read the refused date, so the reminders match a day the store never took"
        )
    }

    /// And it does not reconcile on the success path — the mutation helpers already did, and a
    /// second full pass per keystroke of a stepper is not free.
    @Test func acommittedFieldEditDoesNotReconcileASecondTime() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = embeddedTask(in: modelContext)
        try modelContext.save()

        final class Counter { var runs = 0 }
        let counter = Counter()
        let recorder = CadenceWindDownReconciler(isLive: false) { _ in counter.runs += 1 }

        #expect(CadenceTaskFieldEditCommit.commit(task, in: modelContext, reconciler: recorder) {
            task.priority = .high
        })
        #expect(counter.runs == 0)
    }

    // MARK: - The four surfaces

    private struct SaveSurface {
        let path: String
        /// The save function, and how many copies of it the file holds — `EditListSheet` has one
        /// per sheet.
        let function: String
        var occurrences: Int = 1
        /// Spellings that may only run once the commit has landed.
        let successSpellings: [String]
    }

    private var saveSurfaces: [SaveSurface] {
        [
            SaveSurface(
                path: "Cadence/iOS/iOSSettingsContextSection.swift",
                function: "save",
                successSpellings: ["dismiss()"]
            ),
            SaveSurface(
                path: "Cadence/iOS/iOSListEditorViews.swift",
                function: "save",
                successSpellings: ["dismiss()"]
            ),
            SaveSurface(
                path: "Cadence/macOS/Sheets/EditListSheet.swift",
                function: "saveEdits",
                occurrences: 2,
                successSpellings: ["dismiss()"]
            ),
            SaveSurface(
                path: "Cadence/macOS/Sheets/EditListSheet.swift",
                function: "apply",
                occurrences: 2,
                successSpellings: ["dismiss()"]
            ),
            SaveSurface(
                path: "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift",
                function: "commit",
                successSpellings: ["onChanged()"]
            )
        ]
    }

    /// The failure branch sits above everything that reports success, in every one of them.
    ///
    /// Position alone is not control flow, so each branch has to `return` as well — otherwise the
    /// notice is set and the next statements dismiss over it anyway.
    @Test func everyEditorCommitsBeforeItReportsSuccess() throws {
        let failureBranch = #"(saveFailureNotice|failureNotice) = (CadencePendingChangePersistence\.editFailureNotice|CadenceTaskFieldEditCommit\.saveFailureNotice)\s*return"#

        for surface in saveSurfaces {
            let raw = try CadenceSourceScan.sourceFile(surface.path)
            #expect(raw.count > 400, "\(surface.path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(surface.path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(surface.path): the stripper changed the length")

            for body in bodies(of: surface.function, in: stripped, expected: surface.occurrences) {
                let label = "\(surface.path): \(surface.function)()"
                #expect(!body.isEmpty, "\(label) read as an empty body")
                #expect(
                    CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                    "\(label) still swallows a save"
                )
                #expect(
                    CadenceSourceScan.matchCount(failureBranch, in: body) == 1,
                    "\(label) has no failure branch that both reports and returns"
                )

                let failure = try #require(
                    body.range(of: failureBranch, options: .regularExpression),
                    "\(label): no failure branch"
                )
                for spelling in surface.successSpellings {
                    let success = try #require(
                        body.range(of: spelling),
                        "\(label) no longer spells \(spelling)"
                    )
                    #expect(
                        success.lowerBound > failure.upperBound,
                        "\(label): \(spelling) runs before the failed commit has returned"
                    )
                }
            }
        }
    }

    /// Each surface goes through the shared commit rather than re-deriving one, and each names the
    /// undo shape its own reach calls for.
    @Test func eachEditorNamesTheUndoItsReachCallsFor() throws {
        let contextEditor = try scanned("Cadence/iOS/iOSSettingsContextSection.swift")
        let contextSave = try #require(CadenceSourceScan.functionBody(named: "save", in: contextEditor))
        #expect(contextSave.contains("CadencePendingChangePersistence.commitInsert(of: context, in: modelContext)"))
        #expect(contextSave.contains("CadencePendingChangePersistence.commitEdit(in: modelContext)"))
        // A three-field edit restores three fields; it does not roll the app's context back.
        #expect(CadenceSourceScan.matchCount(#"rollback\(\)"#, in: contextSave) == 0)
        #expect(CadenceSourceScan.matchCount(#"context\.\w+ = previous\w+"#, in: contextSave) == 3)

        let listEditor = try scanned("Cadence/iOS/iOSListEditorViews.swift")
        let listSave = try #require(CadenceSourceScan.functionBody(named: "save", in: listEditor))
        #expect(CadenceSourceScan.matchCount(#"commitInsert\(of: (area|project), in: modelContext\)"#, in: listSave) == 2)
        // The two edit branches re-point every task in the list, so each snapshots the list *and*
        // its tasks — and neither reaches for a rollback.
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceListEditSnapshot\((area|project), tasks: \1\.tasks \?\? \[\]\)"#,
                in: listSave
            ) == 2
        )
        #expect(listSave.contains("reassignTasks("))

        let sheet = try scanned("Cadence/macOS/Sheets/EditListSheet.swift")
        for body in bodies(of: "saveEdits", in: sheet, expected: 2) {
            #expect(body.contains("CadenceListEditSnapshot("))
            #expect(body.contains("undo: undo.restore"))
            #expect(body.contains("applyEdits()"))
        }
        for body in bodies(of: "apply", in: sheet, expected: 2) {
            // The settle reaches every task still open in the list, so the snapshot is handed the
            // same set the service walks rather than an empty one.
            #expect(body.contains("TaskContainerLifecycleService.remainingActiveTasks(in:"))
            #expect(body.contains("undo: undo.restore"))
            #expect(body.contains("settleRemainingActiveTasks("))
        }

        // No editor rolls the app's single context back to undo an edit. See
        // `rollbackUndoesADeleteButNotAnEdit`.
        for path in [
            "Cadence/iOS/iOSSettingsContextSection.swift",
            "Cadence/iOS/iOSListEditorViews.swift",
            "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift"
        ] {
            #expect(
                CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: try scanned(path)) == 0,
                "\(path) undoes an edit with a rollback"
            )
        }
        // `EditListSheet` legitimately keeps one per sheet: the delete cascades roll back, which is
        // the undo shape a delete *does* want.
        #expect(CadenceSourceScan.matchCount(#"commitCascade\("#, in: sheet) == 2)
        #expect(CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: sheet) == 0)
    }

    /// The popover's single refresh call, and the two dismissals that are now guarded on it.
    @Test func theEmbedPopoverRefreshesTheCardOnlyOnACommittedEdit() throws {
        let popover = try scanned("Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift")

        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: popover) == 0,
            "the popover still swallows a save somewhere"
        )
        #expect(
            CadenceSourceScan.matchCount(#"onChanged\(\)"#, in: popover) == 1,
            "the card is refreshed from somewhere other than the one commit"
        )
        #expect(popover.contains("CadenceTaskFieldEditCommit.commit("))

        for guarded in [
            "guard setStatus(action.target(from: task.status)) else { return }",
            "guard applyRecurrenceRule(rule, scope: .thisTask) else { return }",
            "guard applyRecurrenceRule(pendingRecurrenceRule, scope: scope) else { return }"
        ] {
            #expect(popover.contains(guarded), "the popover closes over a refused edit: \(guarded)")
        }

        // The series edit hands the later occurrences to the commit rather than leaving them
        // written to and unrestorable.
        let apply = try #require(CadenceSourceScan.functionBody(named: "applyRecurrenceRule", in: popover))
        #expect(apply.contains("CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets("))
        #expect(apply.contains("commit(alsoRestoring: targets)"))
    }

    /// Non-vacuity for every scan above: the reader really opened these files and really read
    /// code, and the two `== 0` needles match the spelling they hunt.
    @Test func thesourceScanActuallyReadsTheseEditors() throws {
        #expect(try scanned("Cadence/iOS/iOSSettingsContextSection.swift")
            .contains("struct iOSContextEditorSheet: View"))
        #expect(try scanned("Cadence/iOS/iOSListEditorViews.swift")
            .contains("struct iOSListEditorSheet: View"))
        #expect(try scanned("Cadence/macOS/Sheets/EditListSheet.swift")
            .contains("struct EditAreaSheet: View"))
        #expect(try scanned("Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift")
            .contains("struct TaskEmbedFieldEditorPopover: View"))

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try CadencePendingChangePersistence.commitEdit(in: c) {}") == 0)
        #expect(CadenceSourceScan.matchCount(#"onChanged\(\)"#, in: "onChanged()") == 1)
        #expect(CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: "modelContext.rollback()") == 1)
        #expect(CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: "undo: undo.restore") == 0)
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceListEditSnapshot\((area|project), tasks: \1\.tasks \?\? \[\]\)"#,
                in: "CadenceListEditSnapshot(area, tasks: area.tasks ?? [])"
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceListEditSnapshot\((area|project), tasks: \1\.tasks \?\? \[\]\)"#,
                in: "CadenceListEditSnapshot(area, tasks: project.tasks ?? [])"
            ) == 0
        )
    }

    // MARK: - Scan helpers

    private func scanned(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(path): the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "\(path): the stripper changed the length")
        return stripped
    }

    /// Every copy of `func <name>(` in the file, because `EditListSheet` holds one per sheet and
    /// scanning only the first would leave the project sheet unpinned.
    private func bodies(of name: String, in source: String, expected: Int) -> [String] {
        var searched = Substring(source)
        var found: [String] = []
        while let range = searched.range(of: "func \(name)(") {
            let remainder = String(searched[range.lowerBound...])
            if let body = CadenceSourceScan.functionBody(named: name, in: remainder) {
                found.append(body)
            }
            searched = searched[range.upperBound...]
        }
        #expect(found.count == expected, "expected \(expected) copies of \(name)(), found \(found.count)")
        return found
    }
}

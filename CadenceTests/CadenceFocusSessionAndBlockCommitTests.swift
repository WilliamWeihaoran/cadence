import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-636(c) and T-636(e): two more commits the timeline and the focus timer never made.**
///
/// **(c) The focus timer's Complete.** `CadenceFocusSupport.complete` logged the elapsed minutes,
/// called `CadenceTaskRecurrenceWorkflowSupport.markDone` — which reaches
/// `spawnNextOccurrenceIfNeeded` → `context.insert(nextTask)` — and ended
/// `try? modelContext.save()`. That is half 1 of the rule (`AGENTS.md`, "The `try? save()` rule"),
/// the same insert [[T-636]](a) fixed in `toggleCompletion`, reached through the other door.
///
/// It carries a second defect the rule does *not* cover, and it is the reason the minutes are
/// undone here rather than left to correct themselves: `logElapsedSeconds` writes with `+=`. The
/// rule's standing justification for swallowing a commit — *"the next fetch corrects it"* — reads
/// a field the store owns, and an **accumulator** is not that. A fetch re-reads whatever the
/// counter now holds, so a write that did not land stays lost, and `actualMinutes` feeds
/// `area.loggedMinutes` / `project.loggedMinutes`, which an hours-based `Goal` reads.
///
/// **(e) The timeline's Create Block.** `SchedulingActions.createBundle(title:…in:)` inserts into
/// the context it is handed and commits nothing — correct, because that signature is this repo's
/// statement that the *caller* owns the unit of work. `SchedulePanel` was that caller and committed
/// nothing either, then added the ticked tasks to the block and let the canvas dismiss its draft
/// popover. Half 3: an insert that reaches no commit at all.
@MainActor
struct CadenceFocusSessionAndBlockCommitTests {

    private struct CommitRefused: Error {}

    private static let panelPath = "Cadence/macOS/Views/SchedulePanel.swift"
    private static let monthGridPath = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
    private static let dayCanvasPath = "Cadence/macOS/Views/TimelineDayCanvas.swift"
    private static let focusViewPath = "Cadence/iOS/iOSFocusView.swift"
    private static let statusEditingPath = "Cadence/Shared/CadenceTaskStatusEditing.swift"

    // MARK: - T-636(c), behavioural

    /// A refused focus completion leaves the task open, the successor un-inserted **and the
    /// banked minutes exactly where they were** — the half a snapshot has to cover because
    /// `commitSettle` cannot see it.
    @Test func arefusedFocusCompletionUnbanksTheMinutesAndUninsertsTheSuccessor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Launch")
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        task.actualMinutes = 10
        project.loggedMinutes = 90
        context.insert(project)
        context.insert(task)
        task.project = project
        try context.save()

        #expect(throws: CommitRefused.self) {
            try CadenceFocusSupport.complete(task, elapsedSeconds: 25 * 60, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .todo, "the task settled over a refused commit")
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(task.actualMinutes == 10, "the accumulator kept minutes the store never took")
        #expect(project.loggedMinutes == 90, "and so did the list behind it")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1, "a successor was left pending")
    }

    /// The accepted path, without which the test above passes over a helper that logs nothing and
    /// settles nothing.
    @Test func anAcceptedFocusCompletionBanksTheMinutesAndCommitsTheSuccessor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Work")
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(area)
        context.insert(task)
        task.area = area
        try context.save()

        try CadenceFocusSupport.complete(task, elapsedSeconds: 25 * 60, modelContext: context)

        #expect(task.status == .done)
        #expect(task.actualMinutes == 25)
        #expect(area.loggedMinutes == 25)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(!context.hasChanges, "the session was left pending in the context")
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).count == 2)
    }

    /// A session under a whole minute banks nothing, so a refusal has nothing to put back — and
    /// the settle still has to undo. Pins that the snapshot is not doing the work the settle does.
    @Test func arefusedSubMinuteFocusCompletionStillUnsettlesTheTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try CadenceFocusSupport.complete(task, elapsedSeconds: 20, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.actualMinutes == 0)
        #expect(task.status == .todo)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    // MARK: - T-636(c), source shape

    /// The wrapper records the refusal for the shared alert **and** answers it, and the focus view
    /// clears its stopwatch only below that answer. The seconds exist nowhere but the timer, so a
    /// reset over a refusal loses them for good.
    @Test func thefocusViewClearsItsStopwatchOnlyOnceTheStoreHasTheSession() throws {
        let wrapper = try CadenceCommitSurfaceScan.scanned(Self.statusEditingPath)
        let complete = try CadenceCommitSurfaceScan.declarationBody(named: "completeFocusSession", in: wrapper)
        #expect(complete.contains("CadenceTaskSettleFailureCenter.shared.record()"))
        #expect(complete.contains("return false"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: complete) == 0)
        #expect(wrapper.contains("-> Bool {"))

        let view = try CadenceCommitSurfaceScan.scanned(Self.focusViewPath)
        let guarded = try CadenceCommitSurfaceScan.declarationBody(named: "complete", in: view)
        #expect(guarded.contains("guard CadenceTaskStatusEditing.completeFocusSession("))
        #expect(guarded.contains("else { return }"))
        #expect(
            guarded.range(of: "else { return }")!.upperBound < guarded.range(of: "resetTimer()")!.lowerBound,
            "the reset is above the guard, so a refusal still clears the clock"
        )
        #expect(view.contains("struct iOSFocusView: View"))
    }

    // MARK: - T-636(e), behavioural

    /// A refused block creation un-inserts the block **and puts its members back** — the five
    /// fields `addTask` writes, which `commitInsert` cannot see.
    @Test func arefusedBlockCreationLeavesNoBlockAndNoMovedTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write the brief")
        task.scheduledDate = "2026-04-30"
        task.scheduledStartMin = 600
        task.calendarEventID = "evt-1"
        context.insert(task)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try SchedulingActions.insertBundle(
                title: "Deep work",
                dateKey: "2026-05-01",
                startMin: 540,
                endMin: 660,
                adding: [task],
                in: context
            ) { _ in throw CommitRefused() }
        }

        #expect(task.bundle == nil, "the task stayed in a block the store never took")
        #expect(task.scheduledDate == "2026-04-30", "the task was left on the block's day")
        #expect(task.scheduledStartMin == 600, "the task lost its time slot anyway")
        #expect(task.calendarEventID == "evt-1")
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    /// The accepted path: the block **and** its membership are in the store together, read back
    /// through a second context so the creating context's own memory cannot satisfy it.
    @Test func anAcceptedBlockCreationCommitsTheBlockAndItsMembersTogether() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write the brief")
        task.scheduledDate = "2026-04-30"
        task.scheduledStartMin = 600
        context.insert(task)
        try context.save()

        let bundle = try SchedulingActions.insertBundle(
            title: "Deep work",
            dateKey: "2026-05-01",
            startMin: 540,
            endMin: 660,
            adding: [task],
            in: context
        )

        #expect(bundle.dateKey == "2026-05-01")
        #expect(!context.hasChanges, "the block or its members were left pending")
        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<TaskBundle>())
        #expect(stored.count == 1)
        #expect((stored.first?.tasks ?? []).map(\.title) == ["Write the brief"])
        let storedTask = try reader.fetch(FetchDescriptor<AppTask>()).first
        #expect(storedTask?.scheduledDate == "2026-05-01")
        #expect(storedTask?.scheduledStartMin == -1)
    }

    /// A block created with nothing ticked is still a commit: the drag makes an empty block on
    /// purpose, and it must not be left pending either.
    @Test func ablockCreatedWithNoTickedTasksIsCommittedToo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        try SchedulingActions.insertBundle(
            title: "",
            dateKey: "2026-05-01",
            startMin: 540,
            endMin: 600,
            adding: [],
            in: context
        )

        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<TaskBundle>()).count == 1)
    }

    // MARK: - T-636(e), source shape

    /// The panel is the frame that owns the unit of work, so the commit is there, and the refusal
    /// is named on the panel — the draft popover has already dismissed itself by then.
    @Test func theschedulePanelCommitsTheBlockItCreatesAndNamesArefusal() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.panelPath)
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "createBundle", in: source)

        #expect(body.contains("try SchedulingActions.insertBundle("))
        #expect(body.contains("bundleCreateFailed = true"))
        #expect(
            CadenceSourceScan.matchCount(#"SchedulingActions\.createBundle\("#, in: source) == 0,
            "the panel still calls the spelling that commits nothing"
        )
        #expect(source.contains("@State private var bundleCreateFailed = false"))
        #expect(source.contains("CadenceTaskMutationSupport.bundleCreateFailureAlertTitle"))
        #expect(source.contains("Text(CadenceTaskMutationSupport.bundleSaveFailureNotice)"))

        // The event branch beside it is deliberately untouched: EventKit failures already travel
        // through `CalendarManager.lastWriteFailure`.
        #expect(source.contains(".calendarWriteFailureAlert()"))
        #expect(source.contains("calendarManager.createStandaloneEvent("))
        #expect(source.contains("struct SchedulePanel: View"))
    }

    /// The create family's sentence has no "nothing was changed" clause and the title is its own —
    /// a refused *creation* has nothing the user could fear losing, which is exactly what the
    /// delete and edit families' second sentences exist to deny.
    @Test func theblockCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise() {
        #expect(CadenceTaskMutationSupport.bundleCreateFailureAlertTitle == "Couldn't Create Block")
        #expect(
            CadenceTaskMutationSupport.bundleCreateFailureAlertTitle
                != CadenceTaskMutationSupport.bundleEditFailureAlertTitle
        )
        #expect(
            CadenceTaskMutationSupport.bundleCreateFailureAlertTitle
                != CadenceTaskMutationSupport.bundleDeleteFailureAlertTitle
        )
        #expect(!CadenceTaskMutationSupport.bundleSaveFailureNotice.contains("Nothing"))
    }

    // MARK: - T-655, behavioural

    /// A refused drag-created task leaves **nothing** behind — not the task and not the subtasks
    /// the quick-create popover typed alongside it. `AppTask.subtasks` declares no cascade, so an
    /// undo that removed only the task would strand those rows in the context.
    @Test func arefusedDragCreatedTaskLeavesNoTaskAndNoSubtasksBehind() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Ops")
        context.insert(area)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try SchedulingActions.insertTask(
                title: "Dragged into a list",
                dateKey: "2026-05-01",
                startMin: 600,
                endMin: 660,
                containerSelection: .area(area.id),
                sectionName: TaskSectionDefaults.defaultName,
                subtaskTitles: ["First", "Second"],
                areas: [area],
                projects: [],
                in: context
            ) { _ in throw CommitRefused() }
        }

        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<Subtask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty, "the task is still pending")
        #expect(try context.fetch(FetchDescriptor<Subtask>()).isEmpty, "the subtasks are still pending")
    }

    /// The accepted path, read back through a second context so the creating context's own memory
    /// cannot satisfy it: the task, its slot, its container and its subtasks are all in the store.
    @Test func anAcceptedDragCreatedTaskCommitsItsSlotContainerAndSubtasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Ops")
        context.insert(area)
        try context.save()

        let created = try SchedulingActions.insertTask(
            title: "Dragged into a list",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            containerSelection: .area(area.id),
            sectionName: TaskSectionDefaults.defaultName,
            subtaskTitles: ["First"],
            areas: [area],
            projects: [],
            in: context
        )

        #expect(created?.title == "Dragged into a list")
        #expect(!context.hasChanges, "the task or its subtasks were left pending")
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.scheduledDate == "2026-05-01")
        #expect(stored.scheduledStartMin == 600)
        #expect(stored.estimatedMinutes == 60)
        #expect(stored.area?.id == area.id)
        #expect(try reader.fetch(FetchDescriptor<Subtask>()).map(\.title) == ["First"])
    }

    /// An empty title is "nothing to create" rather than a failure — the same answer
    /// `TaskCreationService.createTask` gives — so it neither throws nor commits anything.
    @Test func adragCreatedTaskWithNoTitleIsNothingToCreateRatherThanArefusal() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let created = try SchedulingActions.insertTask(
            title: "   ",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            containerSelection: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            areas: [],
            projects: [],
            in: context
        ) { _ in throw CommitRefused() }

        #expect(created == nil)
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// A refused drop-a-task-on-a-task leaves no block **and both tasks where they were**. The
    /// block being un-inserted does not put either task back: both were detached from whatever
    /// block they were in, moved onto the block's day and stripped of their slot and calendar link.
    @Test func arefusedDropOfATaskOnATaskLeavesNoBlockAndBothTasksWhereTheyWere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = AppTask(title: "Target")
        target.scheduledDate = "2026-05-01"
        target.scheduledStartMin = 600
        target.calendarEventID = "evt-target"
        let dragged = AppTask(title: "Dragged")
        dragged.scheduledDate = "2026-04-28"
        dragged.scheduledStartMin = 780
        dragged.calendarEventID = "evt-dragged"
        context.insert(target)
        context.insert(dragged)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try SchedulingActions.insertBundle(
                from: target,
                adding: dragged,
                in: context
            ) { _ in throw CommitRefused() }
        }

        #expect(target.bundle == nil)
        #expect(dragged.bundle == nil)
        #expect(target.scheduledStartMin == 600)
        #expect(target.calendarEventID == "evt-target")
        #expect(dragged.scheduledDate == "2026-04-28")
        #expect(dragged.scheduledStartMin == 780)
        #expect(dragged.calendarEventID == "evt-dragged")
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty, "the block is still pending")
    }

    /// **Why the test above asserts the context and its sibling asserts the store**, and it is a
    /// finding rather than a weaker claim: `CadenceTaskMutationSupport.addTask` — the shared
    /// mutation `createBundle(from:adding:)` moves each task with — ends `try? modelContext.save()`.
    /// So the pair is already committed before this frame's `commit` is asked at all, and an
    /// injected refusal cannot model the store's answer to the insert itself. In the app the two
    /// are the same `save()` and refuse together; in a test they are not.
    ///
    /// Pinned rather than described so the day that swallow goes this test goes red and the pair
    /// above can be strengthened in the same change. `SchedulingActions.addTask`, the macOS
    /// spelling `insertBundle(title:…adding:in:)` uses, has no save of its own — which is exactly
    /// why `arefusedBlockCreationLeavesNoBlockAndNoMovedTasks` *can* read the store. [[T-760]].
    @Test func theSharedTwoTaskBlockMutationCommitsThroughAswallowedSaveOfItsOwn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = AppTask(title: "Target")
        target.scheduledDate = "2026-05-01"
        target.scheduledStartMin = 600
        let dragged = AppTask(title: "Dragged")
        context.insert(target)
        context.insert(dragged)
        try context.save()

        _ = CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)

        // Nothing here asked for a commit, and the store has one anyway.
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<TaskBundle>()).count == 1)

        let shared = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/CadenceTaskMutationSupport.swift")
        let addTask = try CadenceCommitSurfaceScan.declarationBody(named: "addTask", in: shared)
        #expect(addTask.contains("try? modelContext.save()"), "the swallow this test is about is gone")
    }

    /// The accepted drop: the block and both memberships are in the store together.
    @Test func anAcceptedDropOfATaskOnATaskCommitsTheBlockAndBothMembers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = AppTask(title: "Target")
        target.scheduledDate = "2026-05-01"
        target.scheduledStartMin = 600
        let dragged = AppTask(title: "Dragged")
        context.insert(target)
        context.insert(dragged)
        try context.save()

        let bundle = try #require(
            try SchedulingActions.insertBundle(from: target, adding: dragged, in: context)
        )

        #expect(bundle.dateKey == "2026-05-01")
        #expect(!context.hasChanges, "the block or its members were left pending")
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<TaskBundle>()).first)
        #expect((stored.tasks ?? []).count == 2)
    }

    /// A pair the shared mutation refuses — the same task dropped on itself — is "nothing to make",
    /// so there is no block, nothing to commit and nothing to report. It must not throw: the drop
    /// would raise an alert over a gesture that simply did not apply.
    @Test func adropOfATaskOnItselfMakesNoBlockAndRaisesNoRefusal() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Target")
        task.scheduledDate = "2026-05-01"
        task.scheduledStartMin = 600
        context.insert(task)
        try context.save()

        let bundle = try SchedulingActions.insertBundle(
            from: task,
            adding: task,
            in: context
        ) { _ in throw CommitRefused() }

        #expect(bundle == nil)
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    /// The task family's title is its own, and its sentence makes no promise — the same shape the
    /// block family's pair has, and the reason both live beside their notice rather than at a call
    /// site.
    @Test func thetaskCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise() {
        #expect(TaskCreationService.createFailureAlertTitle == "Couldn't Create Task")
        #expect(
            TaskCreationService.createFailureAlertTitle
                != CadenceTaskMutationSupport.deleteFailureAlertTitle
        )
        #expect(
            TaskCreationService.createFailureAlertTitle
                != CadenceTaskMutationSupport.bundleCreateFailureAlertTitle
        )
        #expect(!TaskCreationService.saveFailureNotice.contains("Nothing"))
    }

    // MARK: - T-655, source shape

    /// The calendar grid's day column owns two units of work — drag out a range and name a task,
    /// drag out a range and tick tasks into a block — and committed neither.
    @Test func themonthGridCommitsBothThingsItsDragCreatesAndNamesEitherRefusal() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.monthGridPath)
        let taskBody = try CadenceCommitSurfaceScan.declarationBody(named: "createTask", in: source)
        let bundleBody = try CadenceCommitSurfaceScan.declarationBody(named: "createBundle", in: source)

        #expect(taskBody.contains("try SchedulingActions.insertTask("))
        #expect(taskBody.contains("taskCreateFailed = true"))
        #expect(bundleBody.contains("try SchedulingActions.insertBundle("))
        #expect(bundleBody.contains("bundleCreateFailed = true"))

        // Neither pending spelling survives anywhere in the file, so a second day column cannot
        // reintroduce one below the two this reads.
        #expect(
            CadenceSourceScan.matchCount(#"SchedulingActions\.createTask\("#, in: source) == 0,
            "the grid still calls the task spelling that commits nothing"
        )
        #expect(
            CadenceSourceScan.matchCount(#"SchedulingActions\.createBundle\("#, in: source) == 0,
            "the grid still calls the block spelling that commits nothing"
        )
        #expect(source.contains("@State private var taskCreateFailed = false"))
        #expect(source.contains("@State private var bundleCreateFailed = false"))
        #expect(source.contains("TaskCreationService.createFailureAlertTitle"))
        #expect(source.contains("Text(TaskCreationService.saveFailureNotice)"))
        #expect(source.contains("CadenceTaskMutationSupport.bundleCreateFailureAlertTitle"))
        #expect(source.contains("Text(CadenceTaskMutationSupport.bundleSaveFailureNotice)"))

        // The event branch beside them stays as it is, for the reason the panel's does: EventKit
        // failures already travel through `CalendarManager.lastWriteFailure`.
        #expect(source.contains("calendarManager.createStandaloneEvent("))
        #expect(source.contains("struct CalDayColumn: View"))
    }

    /// Dropping a task on a scheduled task makes a block out of the two, and the canvas is the
    /// frame that owns it: every frame below is handed its `ModelContext`.
    @Test func thetimelineCanvasCommitsTheBlockADroppedTaskFormsAndNamesArefusal() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.dayCanvasPath)
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "formBundle", in: source)

        #expect(body.contains("try SchedulingActions.insertBundle("))
        #expect(body.contains("bundleCreateFailed = true"))
        #expect(
            CadenceSourceScan.matchCount(#"SchedulingActions\.createBundle\("#, in: source) == 0,
            "the canvas still calls the spelling that commits nothing"
        )
        #expect(source.contains("@State private var bundleCreateFailed = false"))
        #expect(source.contains("CadenceTaskMutationSupport.bundleCreateFailureAlertTitle"))
        #expect(source.contains("Text(CadenceTaskMutationSupport.bundleSaveFailureNotice)"))
        #expect(source.contains("struct TimelineDayCanvas: View"))
    }

    /// The comment-stripper the two scans above read through is discriminating on these files:
    /// both quote the retired spelling in prose, and a raw read would count those quotations as
    /// the call sites the counts above require to be gone.
    @Test func themonthGridAndCanvasScansReadCodeRatherThanTheirOwnProse() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.dayCanvasPath)
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the canvas file carries no comment, so the stripper proved nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")
    }
}

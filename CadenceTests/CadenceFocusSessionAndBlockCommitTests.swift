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
}

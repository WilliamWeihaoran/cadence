// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types (or AppKit) that do not exist there. The gate preserves
// exactly the coverage this file had before; narrowing it so any cross-platform half runs on iOS
// too is follow-up, not part of making the target iOS-capable.
#if os(macOS)
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
/// **(e) The timeline's Create Block.** SchedulingActions.createBundle(title:…in:) inserted into
/// the context it is handed and commits nothing — correct, because that signature is this repo's
/// statement that the *caller* owns the unit of work. `SchedulePanel` was that caller and committed
/// nothing either, then added the ticked tasks to the block and let the canvas dismiss its draft
/// popover. Half 3: an insert that reaches no commit at all.
///
/// **[[T-3170]] removed (e)'s surface.** The empty-slot Create Block — the popover's Block tab,
/// `SchedulePanel`'s and the month grid's `createBundle`, and `SchedulingActions.insertBundle(title:
/// …adding:in:)` behind them — is gone with the Block feature, so its three behavioural pins
/// retired with it and its two source pins now hold the absence. The drag-a-task-onto-a-task block
/// (T-655 below) is a separate gesture. [[T-3170]]'s next pass took it off the Mac timeline, with
/// SchedulingActions.insertBundle(from:adding:in:), and its trio pass deleted the shared
/// CadenceTaskMutationSupport.insertBundle(from:adding:) once no surface called it, so T-655's
/// block-forming behavioural pins retired too; the canvas's source pin holds the absence.
@MainActor
struct CadenceFocusSessionAndBlockCommitTests {

    private struct CommitRefused: Error {}

    private static let panelPath = "Cadence/macOS/Views/SchedulePanel.swift"
    private static let viewportPath = "Cadence/macOS/Views/SchedulePanelShellViews.swift"
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

    // MARK: - T-5060(b), the focus note's live controls

    /// **The checklist circles in an iOS focus note act** ([[T-5060]] (b), the owner's option (a),
    /// decided 2026-10-24): the preview is handed a toggle for the checklist and for both embed
    /// controls, where it used to be handed `onOpenReference` and nothing else, which left every
    /// circle drawn as a `.disabled` button (`iOSMarkdownPreview.swift`, `.disabled(onToggleChecklist == nil)`).
    ///
    /// A scan, because `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS.
    /// The behaviour the wiring buys is measured by the test below it.
    @Test func theIOSFocusNoteHandsItsPreviewALiveChecklistAndLiveEmbedToggles() throws {
        let view = try CadenceCommitSurfaceScan.scanned(Self.focusViewPath)
        let notes = try CadenceCommitSurfaceScan.declarationBody(named: "taskNotes", in: view)
        #expect(notes.contains("onToggleChecklist: { lineIndex in toggleChecklistItem(at: lineIndex, on: task) }"),
                "the focus note's checklist circles are disabled again")
        #expect(notes.contains("onToggleEmbeddedTask: { toggleEmbeddedTask(id: $0) }"))
        #expect(notes.contains("onToggleEmbeddedSubtask: { toggleEmbeddedSubtask(taskID: $0, subtaskID: $1) }"))
        // The reference opener it already had, so this reads an addition and not a replacement.
        #expect(notes.contains("onOpenReference: openMarkdownReference"))

        // The write path: the task's own notes, rewritten by the shared checklist rule and
        // committed through the shared field transaction, which puts the text back on a refusal.
        let toggle = try CadenceCommitSurfaceScan.declarationBody(named: "toggleChecklistItem", in: view)
        let rewrite = try #require(toggle.range(of: "MarkdownChecklistSupport.toggledText(task.notes, lineIndex: lineIndex)"))
        let commit = try #require(
            toggle.range(of: "CadenceTaskFieldEditCommit.commit(task, in: modelContext) {"),
            "the focus note writes its checklist outside the shared field transaction"
        )
        #expect(rewrite.upperBound <= commit.lowerBound)
        #expect(toggle.contains("task.notes = toggled"))

        // The two embed toggles go through the same shared paths the editing surface's cards use,
        // rather than a second spelling of completion.
        let embed = try CadenceCommitSurfaceScan.declarationBody(named: "toggleEmbeddedTask", in: view)
        #expect(embed.contains("CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)"))
        let subtask = try CadenceCommitSurfaceScan.declarationBody(named: "toggleEmbeddedSubtask", in: view)
        #expect(subtask.contains("CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: modelContext)"))
        #expect(view.contains("struct iOSFocusView: View"))
    }

    /// The behaviour the wiring above buys, and the half a scan cannot claim: the composition the
    /// focus note's handler performs ticks the line the user tapped and leaves every other line
    /// alone, and a refused save puts the whole note back.
    @Test func tickingAFocusNotesChecklistLineWritesThatLineAndRollsBackARefusedSave() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Ship the build")
        task.notes = "- [ ] archive\n- [ ] upload\n- [ ] notes"
        context.insert(task)
        try context.save()

        let toggled = try #require(MarkdownChecklistSupport.toggledText(task.notes, lineIndex: 1))
        #expect(CadenceTaskFieldEditCommit.commit(task, in: context) { task.notes = toggled })
        #expect(task.notes == "- [ ] archive\n- [x] upload\n- [ ] notes",
                "the tap ticked a line other than the one it landed on")

        let before = task.notes
        let refusedText = try #require(MarkdownChecklistSupport.toggledText(task.notes, lineIndex: 2))
        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: context,
            commit: { _ in throw CommitRefused() }
        ) {
            task.notes = refusedText
        }
        #expect(landed == false)
        #expect(task.notes == before, "a refused save left the focus note carrying a tick the store does not hold")
    }

    // MARK: - T-6412, the focus note names a refused tick

    /// **A refused tick in the iOS focus note is named** ([[T-6412]]). Both write paths put the
    /// store back on a refusal, so the circle does not move; without a sentence that read as a
    /// tap that missed. The notice is the shared sentence, set only in the refusal branch, cleared
    /// by the next write that lands, drawn above the note card, and bare -- the retry is the same
    /// tap (`onlyNoticesNoLaterAttemptClearsOfferToDismissThemselves` counts it among the bare).
    @Test func theIOSFocusNoteNamesARefusedTickAndClearsItOnTheNextOneThatLands() throws {
        let view = try CadenceCommitSurfaceScan.scanned(Self.focusViewPath)
        #expect(view.contains("@State private var noteFailureNotice: String?"))

        let refusal = "noteFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice"
        for (name, guardLine) in [
            ("toggleChecklistItem", "guard landed else {"),
            ("toggleEmbeddedSubtask", "guard CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: modelContext) else {")
        ] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: view)
            let guarded = try #require(body.range(of: guardLine), "\(name) no longer branches on the commit's answer")
            let named = try #require(body.range(of: refusal), "\(name) does not name its refusal")
            let returned = try #require(body.range(of: "return", range: named.upperBound..<body.endIndex))
            let cleared = try #require(body.range(of: "noteFailureNotice = nil"), "\(name) never clears the notice")
            #expect(guarded.upperBound <= named.lowerBound, "\(name) names a refusal outside its refusal branch")
            #expect(returned.upperBound <= cleared.lowerBound, "\(name) clears the notice inside the refusal branch")
            #expect(CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: refusal), in: body) == 1)
            #expect(CadenceSourceScan.matchCount(#"noteFailureNotice = nil"#, in: body) == 1)
            #expect(CadenceSourceScan.matchCount(#"_ = CadenceNoteTaskEmbedEditing"#, in: body) == 0,
                    "\(name) discards the commit's answer again")
        }
        let checklist = try CadenceCommitSurfaceScan.declarationBody(named: "toggleChecklistItem", in: view)
        #expect(checklist.contains("let landed = CadenceTaskFieldEditCommit.commit(task, in: modelContext) {"))

        // Drawn above the card, bare, and reset when the focus moves to another task's note.
        let notes = try CadenceCommitSurfaceScan.declarationBody(named: "taskNotes", in: view)
        let notice = try #require(notes.range(of: "CadenceInlineFailureNotice(text: noteFailureNotice)"),
                                  "the focus note draws no refusal")
        let card = try #require(notes.range(of: "iOSMarkdownPreview("))
        #expect(notice.upperBound <= card.lowerBound, "the refusal is drawn below the note card")
        #expect(!notes.contains("CadenceInlineFailureNotice(text: noteFailureNotice) {"),
                "a notice the next landed tick clears offers a dismissal")
        #expect(notes.contains(".onChange(of: task.id) { _, _ in noteFailureNotice = nil }"),
                "another task's note inherits this one's refusal")
    }

    // MARK: - T-636(e), source shape

    /// The panel no longer creates a block at all ([[T-3170]]): no Block tab reaches it, so it has
    /// no `createBundle`, no refusal flag and no alert for one. Its event branch is untouched.
    @Test func theSchedulePanelNoLongerCreatesABlockFromAnEmptySlot() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.panelPath)

        #expect(CadenceSourceScan.matchCount(#"func createBundle\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"SchedulingActions\.(createBundle|insertBundle)\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bonCreateBundle\b"#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bbundleCreateFailed\b"#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"bundleCreateFailureAlertTitle"#, in: source) == 0)

        // The event branch beside it is deliberately untouched: EventKit failures already travel
        // through `CalendarManager.lastWriteFailure`.
        #expect(source.contains(".calendarWriteFailureAlert()"))
        #expect(source.contains("calendarManager.createStandaloneEvent("))
        #expect(source.contains("struct SchedulePanel: View"))
    }

    /// **[[T-3170]], the macOS show/edit pass: the Today Timeline panel has no Block arm left.**
    ///
    /// Two halves, because the panel and its viewport are two files and either one alone would let
    /// the surface back:
    ///
    /// 1. `SchedulePanel` reads no block table and runs no block mutation — no `@Query` over
    ///    `TaskBundle`, no day filter over one, and no `SchedulingActions` block call.
    /// 2. `SchedulePanelTimelineViewport` hands the canvas no block argument at all. It used to
    ///    pass **empty** block arrays and refusing closures, a starve, because the canvas still
    ///    declared the four parameters for the Calendar page. [[T-3170]]'s trio pass deleted
    ///    `TimelineBundleBlock` and the four parameters with it, so the starve became a deletion
    ///    and any of the four labels reappearing here is the arm coming back.
    @Test func theTodayTimelinePanelNeitherDrawsABlockNorEditsOne() throws {
        let panel = try CadenceCommitSurfaceScan.scanned(Self.panelPath)

        #expect(CadenceSourceScan.matchCount(#"@Query[^\n]*\[TaskBundle\]"#, in: panel) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bTaskBundle\b"#, in: panel) == 0)
        #expect(CadenceSourceScan.matchCount(#"\btodayBundles\b"#, in: panel) == 0)
        #expect(CadenceSourceScan.matchCount(#"SchedulingActions\.(dropBundle|addTask)\("#, in: panel) == 0)
        // Non-vacuity: the right file, and the task arm beside the removed block arm is untouched.
        #expect(panel.contains("struct SchedulePanel: View"))
        #expect(panel.contains("SchedulingActions.commitDropTask(task, to: todayKey, startMin: startMin, in: modelContext)"))

        let viewport = try CadenceCommitSurfaceScan.scanned(Self.viewportPath)

        #expect(CadenceSourceScan.matchCount(#"\bTaskBundle\b"#, in: viewport) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bbundles:"#, in: viewport) == 0)
        #expect(CadenceSourceScan.matchCount(#"\ballBundles:"#, in: viewport) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bonDropBundleAtMinute:"#, in: viewport) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bonDropTaskOnBundle:"#, in: viewport) == 0)
        // Non-vacuity: the right declaration, still hosting the canvas it starves.
        #expect(viewport.contains("struct SchedulePanelTimelineViewport: View"))
        #expect(viewport.contains("TimelineDayCanvas("))
    }

    // `theblockCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise` was declared here. It held
    // `bundleCreateFailureAlertTitle`, `bundleSaveFailureNotice` and `bundleDeleteFailureNotice`,
    // the last of the Block failure wording, which [[T-3170]]'s trio pass deleted with
    // `TimelineBundleBlock`. The task family's equivalent is
    // `thetaskCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise` below.

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

    // Five behavioural pins of CadenceTaskMutationSupport.insertBundle(from:adding:) were
    // declared here -- `arefusedDropOfATaskOnATaskLeavesNoBlockAndBothTasksWhereTheyWere`,
    // `theSharedTwoTaskBlockMutationNoLongerCommitsThroughASwallowedSaveOfItsOwn`,
    // `arefusedSharedTwoTaskBlockMutationLeavesTheStoreUntouched`,
    // `anAcceptedDropOfATaskOnATaskCommitsTheBlockAndBothMembers` and
    // `adropOfATaskOnItselfMakesNoBlockAndRaisesNoRefusal`. [[T-3170]]'s trio pass deleted
    // `insertBundle` and `addTask` once no surface could form a block or add to one, so there is
    // no drop left to refuse or accept.

    /// The task family's title is its own, and its sentence makes no promise — the same shape the
    /// block family's pair had until [[T-3170]] deleted it, and the reason the title lives beside
    /// its notice rather than at a call site.
    @Test func thetaskCreateFailureTitleIsItsOwnAndItsSentenceMakesNoPromise() {
        #expect(TaskCreationService.createFailureAlertTitle == "Couldn't Create Task")
        #expect(
            TaskCreationService.createFailureAlertTitle
                != CadenceTaskMutationSupport.deleteFailureAlertTitle
        )
        #expect(!TaskCreationService.saveFailureNotice.contains("Nothing"))
    }

    // MARK: - T-655, source shape

    /// The calendar grid's day column owned two units of work — drag out a range and name a task,
    /// drag out a range and tick tasks into a block — and committed neither. The block half is
    /// gone ([[T-3170]]); the task half commits and names its refusal.
    @Test func themonthGridCommitsTheTaskItsDragCreatesAndNamesARefusal() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.monthGridPath)
        let taskBody = try CadenceCommitSurfaceScan.declarationBody(named: "createTask", in: source)

        // Through the Today timeline's write since [[T-3171]] (iv), which commits through
        // `SchedulingActions.insertTask` itself.
        #expect(taskBody.contains("try SchedulePanelDataSupport.insertDragCreatedTask("))
        #expect(taskBody.contains("taskCreateFailed = true"))
        #expect(CadenceSourceScan.matchCount(#"func createBundle\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"SchedulingActions\.insertBundle\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bbundleCreateFailed\b"#, in: source) == 0)

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
        #expect(source.contains("TaskCreationService.createFailureAlertTitle"))
        #expect(source.contains("Text(TaskCreationService.saveFailureNotice)"))

        // The event branch beside them stays as it is, for the reason the panel's does: EventKit
        // failures already travel through `CalendarManager.lastWriteFailure`.
        #expect(source.contains("calendarManager.createStandaloneEvent("))
        #expect(source.contains("struct CalDayColumn: View"))
    }

    /// Dropping a task on a scheduled task used to make a block out of the two, and the canvas was
    /// the frame that committed it. [[T-3170]] removed the gesture from the Mac timeline, so the
    /// canvas has no `formBundle`, no refusal flag and no alert for one, and nothing in it calls
    /// either `SchedulingActions` spelling.
    @Test func thetimelineCanvasNoLongerFormsABlockFromADroppedTask() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.dayCanvasPath)

        #expect(CadenceSourceScan.matchCount(#"func formBundle\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"SchedulingActions\.(createBundle|insertBundle)\("#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bbundleCreateFailed\b"#, in: source) == 0)
        #expect(CadenceSourceScan.matchCount(#"bundleCreateFailureAlertTitle"#, in: source) == 0)
        // Non-vacuity: the canvas is still the frame that owns the task create it commits.
        #expect(source.contains("struct TimelineDayCanvas: View"))
        #expect(source.contains("onDropTaskAtMinute: onDropTaskAtMinute,"))
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

#endif

#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8141]]: a task in iPad Today drags onto the calendar beside it — and the press that lifts
/// it is the same press that opens the row's context menu.**
///
/// The owner's words were *"if i want to drag a task in today's view onto the calendar, it doesnt
/// work. it doesnt drag at all"*, and the drag never lifting is the load-bearing half: a drop that
/// is taken and does nothing ([[T-8091]]) looks different and has a different cause.
///
/// **What was wrong, and the differential that found it** (measured on `Cadence-iPadPro11`,
/// 2026-10-28, four builds):
///
/// 1. Baseline — a press-and-drag from a Today row onto the Timeline pane moved nothing, and a
///    1.3 s still press opened **no context menu**, although `iOSTaskRow` has carried `.contextMenu`
///    all along.
/// 2. `.draggable` added to the row and nothing else — still nothing. So a missing payload was not
///    the cause.
/// 3. `.iOSSwipeActions` removed from the row — the context menu opened every time, and the row
///    lifted. So the swipe container was the blocker.
/// 4. Inside the container, `shouldBeRequiredToFailBy` forced to `false` — the menu opened with the
///    container still on. That delegate method is the whole of it: it declares every non-pan
///    recognizer must wait for `iOSRowHorizontalPanRecognizer` to fail, and a still finger never
///    makes it decide, so the wait never ends until touch-up.
///
/// Excluding `UILongPressGestureRecognizer` from the requirement was tried in between and changed
/// nothing on screen — the recognizers SwiftUI installs for a lift and for a context menu are not
/// that class — which is why the fix is a timed yield rather than a class test.
///
/// Three things are asked here: the yield's rule, the drop's write, and the wiring of both halves,
/// read from source because the iOS views cannot compile in this macOS-built target.
@MainActor
struct CadenceIOSTaskRowDragLiftTests {

    // MARK: - The yield that lets the press through

    /// The relation, not the figure (`docs/AGENT_BRIEF.md`): the yield has to resolve *before* the
    /// system's own press duration, or the hold the user is making is already over by the time the
    /// row stands down and nothing lifts.
    @Test func theRowYieldsItsTouchBeforeTheSystemPressDurationIsUp() {
        #expect(CadenceSwipeActionSupport.stillPressYieldSeconds > 0)
        #expect(
            CadenceSwipeActionSupport.stillPressYieldSeconds < CadenceSwipeActionSupport.systemLongPressSeconds,
            "an undecided row pan yields no sooner than the press it is blocking, so nothing can lift"
        )
    }

    @Test func onlyAnUndecidedPanYieldsAndOnlyOnceItHasWaited() {
        let delay = CadenceSwipeActionSupport.stillPressYieldSeconds

        // A still finger: undecided, and past the wait.
        #expect(CadenceSwipeActionSupport.yieldsStillPress(claim: .undecided, elapsed: delay))
        #expect(CadenceSwipeActionSupport.yieldsStillPress(claim: .undecided, elapsed: delay * 4))
        // Still inside the wait: the swipe may yet declare itself.
        #expect(!CadenceSwipeActionSupport.yieldsStillPress(claim: .undecided, elapsed: delay / 2))
        #expect(!CadenceSwipeActionSupport.yieldsStillPress(claim: .undecided, elapsed: 0))
        // A claimed axis is not holding anything hostage: horizontal has taken the touch, and
        // vertical has already failed on its own.
        for claim in [CadenceSwipeAxisClaim.horizontal, .vertical] {
            #expect(
                !CadenceSwipeActionSupport.yieldsStillPress(claim: claim, elapsed: delay * 4),
                "\(claim) asked to be failed a second time"
            )
        }
    }

    /// The axis test is unchanged by the yield: a swipe that declares itself inside the wait still
    /// claims the row, which is what [[T-2059]]'s fix bought and what this must not spend.
    @Test func aDragThatTurnsHorizontalInsideTheWaitStillClaimsTheRow() {
        let metrics = CadenceSwipeActionMetrics.standard
        let sideways = CGSize(width: -(metrics.claimDistance + 1), height: 2)
        #expect(CadenceSwipeActionSupport.axisClaim(translation: sideways, metrics: metrics) == .horizontal)
        #expect(
            !CadenceSwipeActionSupport.yieldsStillPress(
                claim: CadenceSwipeActionSupport.axisClaim(translation: sideways, metrics: metrics),
                elapsed: CadenceSwipeActionSupport.stillPressYieldSeconds * 10
            )
        )
    }

    // MARK: - What a dropped task writes

    private final class CountingCommit {
        var refuses = false
        private(set) var commitCount = 0
        struct Refused: Error {}

        func commit(_ modelContext: ModelContext) throws {
            commitCount += 1
            if refuses { throw Refused() }
            try modelContext.save()
        }
    }

    private func todayTask(in modelContext: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Dragged out of Today")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = -1
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    /// Day **and** minute, in one commit. Either alone reads on screen as a drop that did nothing:
    /// a minute without the day draws the block on a day the user was not looking at, and a day
    /// without the minute leaves the task untimed in the column it was dragged out of.
    @Test func aDroppedTaskTakesTheDayAndTheMinuteItLandedOn() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try todayTask(in: modelContext)
        let seam = CountingCommit()

        let landed = CadenceTimelineBlockEdit.commitDrop(
            task, dateKey: "2026-06-02", startMin: 690,
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(landed)
        #expect(seam.commitCount == 1, "the day and the minute were written in two transactions")
        #expect(task.scheduledDate == "2026-06-02")
        #expect(task.scheduledStartMin == 690)
    }

    /// A refused save answers `false` and leaves **both** fields as they were, so the row the user
    /// dragged is still in the list it came from and nothing has half-landed.
    @Test func aRefusedDropAnswersFalseAndLeavesTheTaskWhereItWas() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try todayTask(in: modelContext)
        let seam = CountingCommit()
        seam.refuses = true

        let landed = CadenceTimelineBlockEdit.commitDrop(
            task, dateKey: "2026-06-02", startMin: 690,
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(!landed)
        #expect(task.scheduledDate == "2026-06-01", "a refused drop left the new day on the task")
        #expect(task.scheduledStartMin == -1, "a refused drop left the new minute on the task")
    }

    /// The host's half: an id that names nothing is refused rather than swallowed, and an id that
    /// names a task is the one written.
    @Test func anIdThatNamesNoTaskIsRefusedAndTheRightTaskIsTheOneWritten() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let wanted = try todayTask(in: modelContext)
        let other = AppTask(title: "Not the one dragged")
        other.scheduledDate = "2026-06-01"
        other.scheduledStartMin = -1
        modelContext.insert(other)
        try modelContext.save()

        #expect(
            !CadenceTimelineBlockEdit.commitDrop(
                taskID: UUID(), among: [wanted, other],
                dateKey: "2026-06-02", startMin: 690, in: modelContext, reconciler: .inert
            ),
            "a payload naming no task of ours was accepted"
        )
        #expect(wanted.scheduledStartMin == -1)
        #expect(other.scheduledStartMin == -1)

        #expect(
            CadenceTimelineBlockEdit.commitDrop(
                taskID: wanted.id, among: [wanted, other],
                dateKey: "2026-06-02", startMin: 690, in: modelContext, reconciler: .inert
            )
        )
        #expect(wanted.scheduledStartMin == 690)
        #expect(other.scheduledStartMin == -1, "the drop wrote a task the payload did not name")
    }

    // MARK: - The wiring, read from source

    private let rowFile = "Cadence/iOS/iOSTaskViews.swift"
    private let swipeFile = "Cadence/iOS/iOSSwipeActionRow.swift"
    private let timelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"

    /// The source half of the drag. Without this the press lifts nothing at all, which is the
    /// owner's sentence.
    @Test func theTaskRowOffersTheSharedDragPayload() throws {
        let source = try CadenceSourceScan.sourceFile(rowFile)
        let row = try #require(CadenceSourceScan.declarationBody("struct iOSTaskRow: View", in: source))
        #expect(row.count > 1_000, "non-vacuity: iOSTaskRow read as \(row.count) characters")
        // `.timelineTaskDragSource` since [[T-8451]]: it offers the same `TaskDragPayload` string
        // and additionally records the lift on the shared `TimelineTaskDragSession`, which is the
        // only thing that tells a timeline day column WHICH task is over it while the finger is
        // still down.
        #expect(
            CadenceSourceScan.matchCount(#"\.timelineTaskDragSource\(taskID: task\.id\)"#, in: row) == 1,
            "the row stopped offering a drag payload, so nothing it is dragged onto can be handed a task"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.draggable\("#, in: row) == 0,
            "the row lifts through a bare .draggable again, so the hover plate cannot be its length"
        )
    }

    /// The yield is **scheduled**, not merely declared. The method existed for one build without
    /// this call and the context menu stayed dead on screen, which is exactly what a source scan
    /// of the declaration alone would have passed.
    @Test func theRowPanSchedulesItsYieldFromTouchesBegan() throws {
        let source = try CadenceSourceScan.sourceFile(swipeFile)
        let began = try #require(
            CadenceSourceScan.declarationBody(
                "override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent)",
                in: source
            )
        )
        #expect(
            CadenceSourceScan.matchCount(#"scheduleStillPressYield\(\)"#, in: began) == 1,
            "a touch no longer arms the yield, so an undecided pan blocks the press again"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceSwipeActionSupport\.yieldsStillPress\("#, in: source) == 1,
            "the yield's rule is spelled in the view layer, where this target cannot ask it"
        )
    }

    /// The destination half, on the column both grid spans build — the single-day pane Today shows
    /// and the Calendar page's scrolling run.
    @Test func theTimelineDayColumnTakesATaskPayloadAtTheMinuteItLandedOn() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: source)
        )
        #expect(column.count > 1_000, "non-vacuity: the day column read as \(column.count) characters")
        // Since [[T-8142]] the drop is a delegate, so the column can answer while the finger is
        // still over it; the payload decode and the minute moved into that delegate with it.
        #expect(CadenceSourceScan.matchCount(#"\.onDrop\(\s*of: \[UTType\.text\],\s*delegate: iOSTimelineTaskDropDelegate\("#, in: column) == 1)
        let delegate = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTimelineTaskDropDelegate: DropDelegate", in: source)
        )
        #expect(CadenceSourceScan.matchCount(#"TaskDragPayload\.taskID\(from: payload as String\)"#, in: delegate) == 2)
        // The same minute arithmetic the column's tap and the dropped `+` already use, reached
        // through the hover's resolve, so the three cannot name different quarter-hours for one
        // pixel -- and the release and the hover cannot name different minutes either.
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.resolve\(\s*atY: (y|info\.location\.y),"#, in: delegate) == 2)
    }

    /// **Both hosts pass a real action.** [[T-8091]] is this wiring one host short: a drop target
    /// whose action is absent still accepts the drop and still springs the card back.
    @Test func bothGridHostsWireTheDropToTheSharedCommit() throws {
        for file in ["Cadence/iOS/iOSTodaySchedulePanel.swift", "Cadence/iOS/iOSCalendarView.swift"] {
            let source = try CadenceSourceScan.sourceFile(file)
            #expect(
                CadenceSourceScan.matchCount(#"onDropTaskAtMinute:"#, in: source) == 1,
                "\(file) builds the timeline grid without a drop action"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.commitDrop\("#, in: source) == 1,
                "\(file) writes a dropped task some way other than the shared commit"
            )
        }
    }
}
#endif

import Foundation
import Testing
#if os(macOS)
import SwiftUI
#endif
@testable import Cadence

#if os(macOS)
/// [[T-5350]]: a Week-view block drag onto another day left the source column's own
/// `activeDragTaskID` set — drag-to-create there refused, its next drop previewed the old task at
/// the old task's offset — and the receiving column, holding no id, ignored where the block had
/// been grabbed. The drag is now one `TimelineTaskDragSession` the page's columns share.
@Suite
@MainActor
struct TimelineTaskDragSessionTests {
    private let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
    private let taskA = UUID()
    private let taskB = UUID()

    @Test
    func theGrabOffsetIsFixedAtTheSourceAndReusedByTheDayTheBlockIsDroppedOn() {
        let session = TimelineTaskDragSession()
        session.begin(taskID: taskA)

        // Monday: task A starts 9:00 and is grabbed by its middle, 9:30 — 30 points below its top.
        let grab = session.enteredOffset(
            pointerY: metrics.yOffset(for: 9 * 60 + 30),
            taskStartMin: 9 * 60,
            metrics: metrics
        )
        #expect(grab == 30)

        // Tuesday, entered with the pointer at 14:30: the block's top must sit at 14:00, so the
        // offset is still Monday's 30, not recomputed against the task's unchanged 9:00 start.
        let tuesday = session.enteredOffset(
            pointerY: metrics.yOffset(for: 14 * 60 + 30),
            taskStartMin: 9 * 60,
            metrics: metrics
        )
        #expect(tuesday == grab)
        #expect(metrics.snappedMinute(fromY: metrics.yOffset(for: 14 * 60 + 30) - session.currentOffset) == 14 * 60)
    }

    @Test
    func endingTheDragOnTheTargetDayFreesTheSourceDaysDragToCreate() {
        let session = TimelineTaskDragSession()
        session.begin(taskID: taskA)
        let monday = [taskA]
        let tuesday: [UUID] = []
        #expect(session.isDragging(anyOf: monday))
        #expect(!session.isDragging(anyOf: tuesday), "a drag from Monday disabled Tuesday's drag-to-create")

        // Tuesday's `performDrop` ends the one shared session.
        session.end()
        #expect(!session.isDragging(anyOf: monday))
        #expect(session.taskID == nil)
        #expect(session.currentOffset == 0)
    }

    @Test
    func aLeftoverSessionGivesWayToThePayloadActuallyBeingDropped() {
        let session = TimelineTaskDragSession()
        session.begin(taskID: taskA)
        _ = session.enteredOffset(pointerY: 600, taskStartMin: 9 * 60, metrics: metrics)
        #expect(session.currentOffset == 60)

        session.reconcile(payloadTaskID: taskA)
        #expect(session.taskID == taskA, "the session's own payload ended it")

        session.reconcile(payloadTaskID: taskB)
        #expect(session.taskID == nil)
        #expect(session.currentOffset == 0, "task B was placed by task A's grab")
    }

    @Test
    func aDragFromOutsideTheTimelineHasNoOffset() {
        let session = TimelineTaskDragSession()
        #expect(session.enteredOffset(pointerY: 600, taskStartMin: 9 * 60, metrics: metrics) == 0)
        #expect(session.currentOffset == 0)
    }

    @Test
    func theBlockLayersBindingBeginsAndEndsTheSharedSession() {
        let session = TimelineTaskDragSession()
        let binding = session.taskIDBinding
        binding.wrappedValue = taskA
        #expect(session.taskID == taskA)
        binding.wrappedValue = nil
        #expect(session.taskID == nil)
    }

    /// The sharing itself is wiring: the scroller hands one session to every column, the canvas
    /// prefers it, and the drop delegate ends it on a drop but not on leaving a column.
    @Test
    func theDayColumnsShareOneSessionAndTheDropEndsIt() throws {
        let scroller = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift")
        let scrollerBody = try #require(CadenceSourceScan.declarationBody("struct CalendarTimelineDayScroller", in: scroller))
        #expect(scrollerBody.contains("@State private var taskDragSession = TimelineTaskDragSession()"))
        #expect(scrollerBody.contains(".environment(\\.timelineTaskDragSession, taskDragSession)"))

        let canvas = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDayCanvas.swift")
        )
        #expect(canvas.contains("@Environment(\\.timelineTaskDragSession) private var sharedDragSession"))
        #expect(canvas.contains("sharedDragSession ?? ownDragSession"))
        #expect(!canvas.contains("@State private var activeDragTaskID"))
        #expect(!canvas.contains("@State private var dragYOffset"))

        let delegate = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDropInteractionSupport.swift")
        let perform = try #require(CadenceSourceScan.functionBody(named: "performDrop", in: delegate))
        #expect(perform.contains("dragSession.end()"))
        let exited = try #require(CadenceSourceScan.functionBody(named: "dropExited", in: delegate))
        #expect(!exited.contains("dragSession.end()"), "leaving a column ended a cross-day drag")
        let entered = try #require(CadenceSourceScan.functionBody(named: "dropEntered", in: delegate))
        #expect(entered.contains("dragSession.enteredOffset("))
    }
}
#endif

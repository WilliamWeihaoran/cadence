import Foundation
import Testing
#if os(macOS)
import SwiftUI
#endif
@testable import Cadence

#if os(macOS)
@Suite(.serialized)
@MainActor
struct TimelineMetricsTests {

    // MARK: - 1. Close to / past midnight

    @Test func blockFrameNearMidnightExtendsPastDayBoundaryWithoutNegativeOrNaNValues() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        // Starts at 23:45 (1425) and runs 30 minutes, spilling past minute 1440 (next day).
        let frame = computeTimelineBlockFrame(
            startMinute: 1425,
            durationMinutes: 30,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )

        #expect(frame.y == CGFloat(1425))
        #expect(frame.height == CGFloat(30))
        #expect(frame.y.isFinite && frame.height.isFinite)
        #expect(frame.width > 0)
        // The bottom edge legitimately runs past the canvas's total height (1440) —
        // the day canvas clips this visually; the math itself must stay well-formed.
        #expect(frame.y + frame.height > metrics.totalHeight)
    }

    @Test func yToMinsClampsAtEndOfVisibleDayRatherThanReturningOutOfRangeMinutes() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        // A y-coordinate far below the last row should clamp instead of returning >= 1440.
        let mins = metrics.yToMins(CGFloat(10_000))
        #expect(mins == metrics.endHour * 60 - 5)

        let negativeMins = metrics.yToMins(CGFloat(-500))
        #expect(negativeMins == metrics.startHour * 60)
    }

    // MARK: - 2. Extremely short durations

    @Test func extremelyShortDurationsNeverCollapseBlockHeightBelowMinimum() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        for duration in [1, 2, 3, 5] {
            let height = metrics.height(for: duration, minHeight: TimelineBlockStyle.schedule.minHeight)
            #expect(height >= TimelineBlockStyle.schedule.minHeight)
            #expect(height > 0)
        }

        let frame = computeTimelineBlockFrame(
            startMinute: 600,
            durationMinutes: 1,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        #expect(frame.height >= TimelineBlockStyle.schedule.minHeight)
    }

    // MARK: - 3. Very long durations

    @Test func veryLongDurationsScaleHeightWithoutOverflowOrClipping() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        // Full-day duration (24h) should scale linearly, matching the full canvas height.
        let fullDayHeight = metrics.height(for: 24 * 60, minHeight: TimelineBlockStyle.schedule.minHeight)
        #expect(fullDayHeight == metrics.totalHeight)

        let frame = computeTimelineBlockFrame(
            startMinute: 0,
            durationMinutes: 24 * 60,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        #expect(frame.height == metrics.totalHeight)
        #expect(frame.y == 0)
        #expect(frame.width > 0 && frame.width.isFinite)
    }

    // MARK: - 4. Overlapping tasks/events at the same slot

    @Test func overlappingTasksAtTheSameSlotAllGetDistinctColumnsAndNoneAreDropped() {
        let taskA = AppTask(title: "A")
        taskA.scheduledDate = "2026-06-02"
        taskA.scheduledStartMin = 600
        taskA.estimatedMinutes = 30

        let taskB = AppTask(title: "B")
        taskB.scheduledDate = "2026-06-02"
        taskB.scheduledStartMin = 600
        taskB.estimatedMinutes = 30

        let taskC = AppTask(title: "C")
        taskC.scheduledDate = "2026-06-02"
        taskC.scheduledStartMin = 605
        taskC.estimatedMinutes = 10

        let result = computeUnifiedLayouts(tasks: [taskA, taskB, taskC], bundles: [], events: [])

        #expect(result.tasks.count == 3)
        let columns = Set(result.tasks.map(\.column))
        // All three overlap in time, so each must land in its own column.
        #expect(columns.count == 3)
        #expect(result.tasks.allSatisfy { $0.totalColumns == 3 })
        // No task should be silently dropped.
        let ids = Set(result.tasks.map { $0.task.id })
        #expect(ids == Set([taskA.id, taskB.id, taskC.id]))
    }

    @Test func overlappingBundleAndTaskShareColumnsWithoutCollision() {
        let task = AppTask(title: "Overlapping task")
        task.scheduledDate = "2026-06-02"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 60

        let bundle = TaskBundle(
            title: "Overlapping bundle",
            dateKey: "2026-06-02",
            startMin: 550,
            durationMinutes: 30
        )

        let result = computeUnifiedLayouts(tasks: [task], bundles: [bundle], events: [])

        #expect(result.tasks.count == 1)
        #expect(result.bundles.count == 1)
        #expect(result.tasks[0].column != result.bundles[0].column)
        #expect(result.tasks[0].totalColumns == 2)
        #expect(result.bundles[0].totalColumns == 2)
    }

    @Test func nonOverlappingTasksEachGetTheirOwnFullWidthColumn() {
        let earlyTask = AppTask(title: "Early")
        earlyTask.scheduledDate = "2026-06-02"
        earlyTask.scheduledStartMin = 480
        earlyTask.estimatedMinutes = 30

        let laterTask = AppTask(title: "Later")
        laterTask.scheduledDate = "2026-06-02"
        laterTask.scheduledStartMin = 600
        laterTask.estimatedMinutes = 30

        let result = computeUnifiedLayouts(tasks: [earlyTask, laterTask], bundles: [], events: [])
        #expect(result.tasks.allSatisfy { $0.column == 0 && $0.totalColumns == 1 })
    }

    // MARK: - 5. Snapping behavior at grid boundaries

    @Test func snapFiveKeepsExactIncrementsAndFloorsOffIncrements() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        #expect(metrics.snap5(600) == 600)
        #expect(metrics.snap5(605) == 605)
        #expect(metrics.snap5(604) == 600)
        #expect(metrics.snap5(601) == 600)
        #expect(metrics.snap5(609) == 605)
    }

    @Test func snappedMinuteFromYMatchesExactHourBoundaryAndJustOffBoundary() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        // Exactly on an hour boundary (10:00 == minute 600, y == 600 at hourHeight 60).
        #expect(metrics.snappedMinute(fromY: CGFloat(600)) == 600)
        // Just one pixel off should still floor to the nearest 5-minute grid line.
        #expect(metrics.snappedMinute(fromY: CGFloat(601)) == 600)
        #expect(metrics.snappedMinute(fromY: CGFloat(604)) == 600)
        #expect(metrics.snappedMinute(fromY: CGFloat(606)) == 605)
    }

    // MARK: - 6. Drag-to-create upward (end above start) must swap, not go negative

    @Test func draftSelectionBeginSwapsStartAndEndWhenDraggingUpward() {
        var dragStartMin: Int? = nil
        var dragEndMin: Int? = nil
        var pendingStartMin: Int? = nil
        var pendingEndMin: Int? = nil
        var showPopover = false
        var selectedTaskID: UUID? = UUID()

        // Gesture anchor (mouse-down) is at minute 600; the live pointer has moved
        // upward to minute 540 — i.e. `endMin` is *before* `startMin`.
        TimelineDayCanvasStateSupport.beginDraftSelection(
            startMin: 600,
            endMin: 540,
            dragStartMin: &dragStartMin,
            dragEndMin: &dragEndMin,
            pendingStartMin: &pendingStartMin,
            pendingEndMin: &pendingEndMin,
            showNewTaskPopover: &showPopover,
            selectedTaskID: &selectedTaskID
        )

        #expect(dragStartMin == 540)
        #expect(dragEndMin == 600)
        #expect((dragEndMin ?? 0) > (dragStartMin ?? 0))
    }

    @Test func draftSelectionCommitSwapsStartAndEndWhenDraggingUpward() {
        var dragStartMin: Int? = nil
        var dragEndMin: Int? = nil
        var pendingStartMin: Int? = nil
        var pendingEndMin: Int? = nil
        var showPopover = false

        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: 600,
            endMin: 540,
            dragStartMin: &dragStartMin,
            dragEndMin: &dragEndMin,
            pendingStartMin: &pendingStartMin,
            pendingEndMin: &pendingEndMin,
            showNewTaskPopover: &showPopover
        )

        #expect(pendingStartMin == 540)
        #expect(pendingEndMin == 600)
        #expect((pendingEndMin ?? 0) - (pendingStartMin ?? 0) >= 5)
        #expect(showPopover)
    }

    @Test func draftSelectionCommitNeverProducesNegativeOrZeroDuration() {
        var dragStartMin: Int? = nil
        var dragEndMin: Int? = nil
        var pendingStartMin: Int? = nil
        var pendingEndMin: Int? = nil
        var showPopover = false

        // Degenerate case: start and end land on the same minute (no visible drag distance).
        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: 300,
            endMin: 300,
            dragStartMin: &dragStartMin,
            dragEndMin: &dragEndMin,
            pendingStartMin: &pendingStartMin,
            pendingEndMin: &pendingEndMin,
            showNewTaskPopover: &showPopover
        )

        #expect(pendingStartMin == 300)
        #expect(pendingEndMin == 305)
    }

    // MARK: - 7. Negative / out-of-range minute values

    @Test func pixelConversionFunctionsHandleUnscheduledAndOutOfRangeMinutesWithoutCrashing() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)

        // -1 is the sentinel for "unscheduled" — must not crash and must stay finite.
        let unscheduledOffset = metrics.yOffset(for: -1)
        #expect(unscheduledOffset.isFinite)

        // Duration bottoming out at a negative/zero value must still fall back to a
        // sane default rather than producing a zero/negative height.
        let unscheduledHeight = metrics.height(for: -1, minHeight: TimelineBlockStyle.schedule.minHeight)
        #expect(unscheduledHeight >= TimelineBlockStyle.schedule.minHeight)

        // A minute at/after end-of-day (>= 1440) must still produce a finite offset.
        let overflowOffset = metrics.yOffset(for: 1500)
        #expect(overflowOffset.isFinite)

        let frame = computeTimelineBlockFrame(
            startMinute: -1,
            durationMinutes: -1,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        #expect(frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite)
        #expect(frame.width >= 0)
        #expect(frame.height > 0)
    }

    @Test func unifiedLayoutsHandleUnscheduledSentinelMinutesWithoutCrashing() {
        // Defensive coverage: even though call sites filter scheduledStartMin >= 0
        // before reaching the timeline canvas, the pure layout function itself must
        // not crash or misbehave if it ever receives the unscheduled sentinel.
        let unscheduled = AppTask(title: "Unscheduled")
        unscheduled.scheduledDate = "2026-06-02"
        unscheduled.scheduledStartMin = -1
        unscheduled.estimatedMinutes = 30

        let result = computeUnifiedLayouts(tasks: [unscheduled], bundles: [], events: [])
        #expect(result.tasks.count == 1)
        #expect(result.tasks[0].column == 0)
        #expect(result.tasks[0].totalColumns == 1)
    }
}
#endif

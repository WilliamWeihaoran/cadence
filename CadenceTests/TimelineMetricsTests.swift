import Foundation
import SwiftData
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

    @Test func theCanvasGridKeepsExactIncrementsAndFloorsOffIncrements() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        #expect(metrics.snapToGrid(600) == 600)
        #expect(metrics.snapToGrid(605) == 605)
        #expect(metrics.snapToGrid(604) == 600)
        #expect(metrics.snapToGrid(601) == 600)
        #expect(metrics.snapToGrid(609) == 605)
    }

    /// **The two platforms snap to different grids on purpose (T-1293).**
    ///
    /// The Mac drags — both ends of a block in one gesture, previewed before it commits, under a
    /// pointer — so its grid is also the shortest block the drag can make, and that is the shortest
    /// block the canvas draws. iOS taps and drops: one *start*, no preview, on a 58pt hour row
    /// where five minutes is under five points. One rule, *snap to what the input can aim at*, and
    /// two answers to it.
    ///
    /// This test exists to make a convergence deliberate rather than tidy. Anyone who makes these
    /// two numbers equal has to come here and say which gesture changed, and the last assertion is
    /// the one that costs something: the phone's typed picker offers exactly the minutes the
    /// phone's timeline can produce, so raising the touch grid strands times the picker can no
    /// longer re-select and lowering it strands times the timeline can no longer reach.
    @Test func theTwoTimelineGridsDifferBecauseTheGesturesDo() throws {
        #expect(CadenceScheduleSupport.pointerTimeGridMinutes == 5)
        #expect(CadenceScheduleSupport.touchTimeGridMinutes == 15)

        // macOS's canvas asks the pointer grid, through `snapToGrid` and through the y-based form
        // every drag, drop and resize on that surface actually calls.
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        #expect(metrics.snapToGrid(609) == 605)
        #expect(metrics.snappedMinute(fromY: 609) == 605)

        // The shortest block a drag can make is the shortest block the canvas can draw. Coarsen the
        // pointer grid alone and the minimum becomes unreachable by the one gesture that creates
        // blocks; fine it alone and a drag can ask for a block shorter than the canvas draws.
        #expect(TimelineDayRange.minimumDuration == CadenceScheduleSupport.pointerTimeGridMinutes)

        // iOS's tap and its dropped `+` both land on the touch grid, which is the shared
        // function's default. On the pointer grid the same pixel would read 70.
        #expect(CadenceScheduleSupport.timelineMinute(atY: 71, hourHeight: 58) == 60)
        #expect(
            CadenceScheduleSupport.timelineMinute(
                atY: 71,
                hourHeight: 58,
                snapMinutes: CadenceScheduleSupport.pointerTimeGridMinutes
            ) == 70
        )

        // And the phone's typed control offers exactly the grid its timeline produces.
        let picker = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceStartTimeFieldRow.swift")
        )
        #expect(picker.contains("by: CadenceScheduleSupport.touchTimeGridMinutes"))
        #expect(!picker.contains("by: 15"), "the picker re-typed the grid it shares with the timeline")
    }

    @Test func snappedMinuteFromYMatchesExactHourBoundaryAndJustOffBoundary() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        // Exactly on an hour boundary (10:00 == minute 600, y == 600 at hourHeight 60).
        #expect(metrics.snappedMinute(fromY: CGFloat(600)) == 600)
        // Just one pixel off should still floor to the canvas's grid line (five minutes: see
        // `theTwoTimelineGridsDifferBecauseTheGesturesDo`).
        #expect(metrics.snappedMinute(fromY: CGFloat(601)) == 600)
        #expect(metrics.snappedMinute(fromY: CGFloat(604)) == 600)
        #expect(metrics.snappedMinute(fromY: CGFloat(606)) == 605)
    }

    // MARK: - 6. Drag-to-create upward (end above start) must swap, not go negative
    //
    // Moved to `TimelineDraftAndResizeTests`, along with the rest of the draft-selection state
    // machine, when the canvas's four draft `@State` optionals became one `TimelineDraftSelection`.

    // MARK: - 7. Negative / out-of-range minute values

    @Test func pixelConversionFunctionsHandleUnscheduledAndOutOfRangeMinutesWithoutCrashing() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)

        // -1 is the sentinel for "unscheduled". `yOffset` does *not* special-case it: it is a
        // linear map, so -1 lands one minute's worth of pixels above the top of the canvas. That
        // is the value the drawing layer actually receives, so it is the value asserted — "is
        // finite" was true of every conceivable implementation and hid the question entirely.
        #expect(metrics.yOffset(for: -1) == -1)
        #expect(metrics.yOffset(for: 0) == 0)
        #expect(metrics.yOffset(for: 60) == 60)

        // A negative/zero duration floors at the 5-minute minimum, then at the style's minHeight.
        #expect(metrics.height(for: -1, minHeight: TimelineBlockStyle.schedule.minHeight) == 24)
        #expect(metrics.height(for: 5, minHeight: TimelineBlockStyle.schedule.minHeight) == 24)
        // ...and above the floor it is the linear value, not the floor.
        #expect(metrics.height(for: 90, minHeight: TimelineBlockStyle.schedule.minHeight) == 90)

        // A minute at/after end-of-day (>= 1440) is likewise not clamped here.
        #expect(metrics.yOffset(for: 1_500) == 1_500)

        let frame = computeTimelineBlockFrame(
            startMinute: -1,
            durationMinutes: -1,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        #expect(frame.y == -1)
        // A non-positive duration is only floored at minHeight. This used to become a 60-minute
        // default here, which was the reason a zero-estimate task was drawn an hour tall while the
        // overlap solver had reserved half an hour for it. "How long is a task with no estimate" is
        // `AppTask.timelineDurationMinutes`' question now; this function draws what it is handed.
        #expect(frame.height == TimelineBlockStyle.schedule.minHeight)
        #expect(frame.height == 24)
        #expect(frame.x == TimelineBlockStyle.schedule.leadingInset)
        // (300 - leadingInset) * blockWidthFraction - columnSpacing, in binary floating point.
        let expectedWidth = (300 - TimelineBlockStyle.schedule.leadingInset)
            * TimelineBlockStyle.schedule.blockWidthFraction
            - TimelineBlockStyle.schedule.columnSpacing
        #expect(abs(frame.width - expectedWidth) < 0.0001)
        #expect(abs(frame.width - 260.8) < 0.0001)
    }

    @Test func unifiedLayoutsDropTheUnscheduledSentinelRatherThanLayingItOut() {
        // `scheduledStartMin == -1` means "unscheduled", not "minute -1". Laid out, it drew a
        // block above the top of the canvas and held column 0 against every real block for the
        // whole day. Both production callers filter it; the layout function now says so itself.
        let unscheduled = AppTask(title: "Unscheduled")
        unscheduled.scheduledDate = "2026-06-02"
        unscheduled.scheduledStartMin = -1
        unscheduled.estimatedMinutes = 30

        let scheduled = AppTask(title: "Scheduled")
        scheduled.scheduledDate = "2026-06-02"
        scheduled.scheduledStartMin = 600
        scheduled.estimatedMinutes = 30

        let result = computeUnifiedLayouts(tasks: [unscheduled, scheduled], bundles: [], events: [])

        #expect(result.tasks.map { $0.task.id } == [scheduled.id])
        // ...and the real task keeps the full width it would have had to share.
        #expect(result.tasks[0].totalColumns == 1)
    }

    // MARK: - 8. Repositioning an existing scheduled task across a day boundary

    @Test func droppingScheduledTaskOnADifferentDayColumnUpdatesBothDateAndStartMinute() throws {
        // Simulates dragging a task block from one day column to another in the
        // Week/2W calendar view: `CalDayColumn` wires `TimelineDayCanvas.onDropTaskAtMinute`
        // straight to `SchedulingActions.dropTask(task, to: <target column's dateKey>, startMin:)`.
        // The task must land on the *new* day, not just move within its original day.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write report")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = 540 // 9:00 AM on the 1st
        task.estimatedMinutes = 45
        context.insert(task)

        // Dropped onto the Wednesday (6/3) column at a new time.
        SchedulingActions.dropTask(task, to: "2026-06-03", startMin: 780)

        #expect(task.scheduledDate == "2026-06-03")
        #expect(task.scheduledDate != "2026-06-01")
        #expect(task.scheduledStartMin == 780)
        // Duration/estimate must be preserved across the move — only the slot changes.
        #expect(task.estimatedMinutes == 45)
    }

    @Test func droppingTaskNearMidnightOnANewDayClampsStartMinuteWithoutCrossingIntoTheFollowingDay() throws {
        // A drop very close to the bottom of the target day's timeline must clamp to a
        // valid in-range minute for *that* day rather than silently rolling into day+1.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Late task")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = 60
        task.estimatedMinutes = 30
        context.insert(task)

        // 1_600 is past the end of the day entirely. The old version of this test passed 1_438,
        // which already satisfied both of its own bounds — so deleting the clamp left it green.
        SchedulingActions.dropTask(task, to: "2026-06-02", startMin: 1_600)

        #expect(task.scheduledDate == "2026-06-02")
        // dayEndMin (1_440) - minimumBundleDuration (5). The exact value, not a range: a range
        // wide enough to hold the input is not an assertion about clamping.
        #expect(task.scheduledStartMin == 1_435)

        // The floor is the same clamp read from the other end.
        SchedulingActions.dropTask(task, to: "2026-06-02", startMin: -50)
        #expect(task.scheduledStartMin == 0)

        // And a drop that needs no clamping must pass through untouched.
        SchedulingActions.dropTask(task, to: "2026-06-02", startMin: 1_438)
        #expect(task.scheduledStartMin == 1_435)
        SchedulingActions.dropTask(task, to: "2026-06-02", startMin: 600)
        #expect(task.scheduledStartMin == 600)
    }

    @Test func droppingABundledTaskOntoAnotherDayColumnMovesItAndClearsBundleMembership() throws {
        // Cross-day reposition must also detach the task from any bundle it was part
        // of on the origin day — otherwise it would visually move while the bundle
        // (still pinned to the old day) kept a stale reference to it.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Bundled follow-up")
        let bundle = TaskBundle(title: "Morning sweep", dateKey: "2026-06-01", startMin: 540, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)
        #expect(task.scheduledDate == "2026-06-01")

        SchedulingActions.dropTask(task, to: "2026-06-05", startMin: 900)

        #expect(task.bundle == nil)
        #expect(bundle.sortedTasks.isEmpty)
        #expect(task.scheduledDate == "2026-06-05")
        #expect(task.scheduledStartMin == 900)
    }
}
#endif

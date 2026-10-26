import Foundation
import Testing
#if os(macOS)
import SwiftUI
#endif
@testable import Cadence

/// "How long is this task's block" used to be answered six different ways. The audit's own summary
/// of the result: a zero-estimate task was **drawn** 60 minutes tall, **columned** for overlap as
/// 30 minutes, and **labelled** "9:00 – 9:05" inside the block it had just drawn.
///
/// These tests assert the three answers against each other rather than each against a constant, so
/// re-introducing any one of the old rules fails here even if the new constant is copied along
/// with it.
@Suite(.serialized)
@MainActor
struct TimelineEffectiveDurationTests {

    // MARK: - The rule itself

    @Test func aTaskWithNoEstimateIsTheDefaultLengthRatherThanZero() {
        let task = AppTask(title: "No estimate")
        task.estimatedMinutes = 0

        #expect(task.timelineDurationMinutes == 30)
        #expect(task.timelineDurationMinutes == AppTask.defaultTimelineDurationMinutes)
    }

    @Test func aDeliberateShortEstimateIsKeptRatherThanRoundedUpToTheDefault() {
        // The rejected candidate rule. `scheduledEndMin` used to read `max(estimatedMinutes, 30)`,
        // which cannot tell "unset" from "ten minutes" — it rounded a real ten-minute task up to
        // half an hour, contradicting the block drawn for it and the label inside that block.
        let task = AppTask(title: "Ten minutes")
        task.scheduledStartMin = 540
        task.estimatedMinutes = 10

        #expect(task.timelineDurationMinutes == 10)
        #expect(task.scheduledEndMin == 550)
    }

    @Test func anEstimateBelowTheWritePathFloorIsRaisedToIt() {
        // Every write path already clamps to 5 (`SchedulingActions`, `TaskCreationService`,
        // `CadenceTaskMutationSupport`); the card editors let a smaller number be typed, so the
        // read path has to agree rather than draw a one-minute sliver.
        let task = AppTask(title: "One minute")
        task.estimatedMinutes = 1

        #expect(task.timelineDurationMinutes == 5)
        #expect(task.timelineDurationMinutes == AppTask.minimumTimelineDurationMinutes)
    }

    @Test func aNegativeEstimateIsUnsetRatherThanNegativeLength() {
        let task = AppTask(title: "Nonsense")
        task.estimatedMinutes = -20

        #expect(task.timelineDurationMinutes == AppTask.defaultTimelineDurationMinutes)
    }

    @Test func anOrdinaryEstimateIsPassedThroughUntouched() {
        let task = AppTask(title: "Ordinary")
        task.scheduledStartMin = 600
        task.estimatedMinutes = 45

        #expect(task.timelineDurationMinutes == 45)
        #expect(task.scheduledEndMin == 645)
    }

    @Test func anUnscheduledTaskHasNoEndMinuteEvenThoughItHasALength() {
        let task = AppTask(title: "Unscheduled")
        task.estimatedMinutes = 0

        #expect(task.scheduledStartMin == -1)
        #expect(task.scheduledEndMin == -1)
        #expect(task.timelineDurationMinutes == 30)
    }

    // MARK: - The iOS timeline reads the same rule (T-6921)

    @Test func theIOSTimelineTaskRangeIsTheStartPlusTheSharedDurationForEveryEstimate() {
        // A relation, not a figure: for Estimate None (0), a 5-minute estimate, a 10-minute one
        // and an ordinary one, the range the iOS block is labelled and edited from is exactly
        // `scheduledStartMin ..< scheduledEndMin`, the span the Board card and the Mac read.
        // `blockRange`'s `max(15, _)` gave 0 -> 15 and 5 -> 15 here.
        for estimate in [0, 5, 10, 45] {
            let task = AppTask(title: "Estimate \(estimate)")
            task.scheduledStartMin = 540
            task.estimatedMinutes = estimate

            let range = CadenceScheduleSupport.taskTimelineRange(for: task)
            #expect(range.start == task.scheduledStartMin, "estimate \(estimate)")
            #expect(range.end - range.start == task.timelineDurationMinutes, "estimate \(estimate)")
            #expect(range.end == task.scheduledEndMin, "estimate \(estimate)")
        }
    }

    @Test func theIOSTimelineDrawsAndColumnsItsTaskBlocksFromTheSharedRangeNotTheFifteenMinuteFloor() throws {
        // The iOS file does not compile into this target, so the wiring is pinned by source: the
        // task range comes from `taskTimelineRange`, and no task range is built from the raw
        // estimate through `blockRange`.
        let code = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(code.contains("CadenceScheduleSupport.taskTimelineRange(for: task)"))
        #expect(!code.contains("fallbackDuration: task.estimatedMinutes"))
        #expect(!code.contains("CadenceScheduleSupport.blockRange("))
    }

    #if os(macOS)

    // 1 pt == 1 minute, so a frame's y and height read directly as minutes.
    private let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)

    /// Deliberately the production entry point the block draws itself with, not a local call to
    /// `computeTimelineBlockFrame` — so a call site regressing to raw `estimatedMinutes` is caught
    /// here rather than only the rule it should be calling.
    private func frame(for task: AppTask) -> TimelineBlockFrame {
        TimelineTaskBlockInteractionSupport.frame(
            task: task,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
    }

    // MARK: - The three answers, checked against each other

    @Test func theBlockDrawnForAZeroEstimateTaskEndsWhereTheOverlapSolverSaysItEnds() {
        // The solver placed both of these in column 0 — it decided they do not overlap. If the
        // drawn block is longer than the length the solver reserved, a task sits on top of the very
        // neighbour it was laid out beside. This is the 60-vs-30 disagreement, stated as the
        // invariant it broke.
        let noEstimate = AppTask(title: "No estimate")
        noEstimate.scheduledDate = "2026-06-02"
        noEstimate.scheduledStartMin = 540
        noEstimate.estimatedMinutes = 0

        let neighbour = AppTask(title: "Right after")
        neighbour.scheduledDate = "2026-06-02"
        neighbour.scheduledStartMin = 570
        neighbour.estimatedMinutes = 30

        let layouts = computeUnifiedLayouts(tasks: [noEstimate, neighbour], events: [], cascadeGapMinutes: 24)
        #expect(layouts.tasks.allSatisfy { $0.column == 0 && $0.totalColumns == 1 })

        let first = frame(for: noEstimate)
        let second = frame(for: neighbour)
        #expect(first.y + first.height <= second.y)
    }

    @Test func theTimeRangeInsideAZeroEstimateBlockNamesTheMinuteTheBlockIsDrawnTo() {
        // "9:00 – 9:05" printed inside a block an hour tall, because the label read
        // `max(estimatedMinutes, 5)` and the geometry read `estimatedMinutes > 0 ? … : 60`.
        let task = AppTask(title: "No estimate")
        task.scheduledDate = "2026-06-02"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 0

        let drawn = frame(for: task)
        let drawnEndMinute = Int(drawn.y + drawn.height)

        #expect(TimelineTaskBlockInteractionSupport.timeRangeLabel(for: task)
            == TimeFormatters.timeRange(startMin: 540, endMin: drawnEndMinute))
    }

    @Test func theExportedRangeIsTheSameRangeTheBlockDraws() {
        // `SchedulePanel`'s markdown export went through its own `max(estimatedMinutes, 30)`; it
        // reads `scheduledEndMin` now, which has to be the drawn end.
        let task = AppTask(title: "No estimate")
        task.scheduledDate = "2026-06-02"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 0

        let drawn = frame(for: task)
        #expect(task.scheduledEndMin == Int(drawn.y + drawn.height))
    }

    @Test func aShortEstimateIsDrawnAndLabelledAtItsOwnLengthNotTheDefault() {
        // The other half of rejecting `max(estimatedMinutes, 30)`: a ten-minute block stays ten
        // minutes on every surface. (It is drawn at `style.minHeight` because a 10 pt block is
        // unusable, which is a drawing floor, not a change of duration — the label and the export
        // still say 9:10.)
        let task = AppTask(title: "Ten minutes")
        task.scheduledDate = "2026-06-02"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 10

        #expect(task.scheduledEndMin == 550)
        #expect(TimelineTaskBlockInteractionSupport.timeRangeLabel(for: task)
            == TimeFormatters.timeRange(startMin: 540, endMin: 550))
    }

    @Test func blockGeometryDrawsExactlyTheDurationItIsHandedWithNoFallbackOfItsOwn() {
        // `computeBlockFrame` is geometry. Bundles and events reach it with durations already
        // clamped to at least 5 at construction, so the `> 0 ? … : 60` it used to carry was
        // reachable only from tasks — and it is the task rule's job to answer that.
        let drawn = computeTimelineBlockFrame(
            startMinute: 540,
            durationMinutes: 25,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )

        #expect(drawn.height == 25)
    }

    #endif
}

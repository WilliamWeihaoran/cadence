#if os(macOS)
import SwiftUI

struct TimelineMetrics {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat

    var totalMinutes: Int { (endHour - startHour) * 60 }
    var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    func snap5(_ mins: Int) -> Int { (mins / 5) * 5 }

    func yToMins(_ y: CGFloat) -> Int {
        let mins = Int(y / hourHeight * 60) + startHour * 60
        return max(startHour * 60, min(endHour * 60 - 5, mins))
    }

    func snappedMinute(fromY y: CGFloat) -> Int {
        snap5(yToMins(y))
    }

    func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute - startHour * 60) * hourHeight / 60
    }

    func height(for durationMinutes: Int, minHeight: CGFloat) -> CGFloat {
        max(minHeight, CGFloat(max(durationMinutes, 5)) * hourHeight / 60)
    }
}

struct TimelineBlockStyle {
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let sideMarginFraction: CGFloat
    let columnSpacing: CGFloat
    let minHeight: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    /// Fraction of the available canvas width that blocks may occupy (0–1).
    /// The remainder is kept clear as a drag-to-create strip on the right.
    let blockWidthFraction: CGFloat

    static let schedule = TimelineBlockStyle(
        leadingInset: 8,
        trailingInset: 0,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 24,
        cornerRadius: 6,
        horizontalPadding: 8,
        verticalPadding: 4,
        blockWidthFraction: 0.9
    )

    static let calendar = TimelineBlockStyle(
        leadingInset: 4,
        trailingInset: 4,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 22,
        cornerRadius: 5,
        horizontalPadding: 6,
        verticalPadding: 3,
        blockWidthFraction: 0.95
    )
}

enum TimelineDropBehavior {
    case wholeColumn
    case perHour
}

func computeTimelineBlockFrame(
    startMinute: Int,
    durationMinutes: Int,
    column: Int,
    totalColumns: Int,
    totalWidth: CGFloat,
    metrics: TimelineMetrics,
    style: TimelineBlockStyle
) -> TimelineBlockFrame {
    TimelineMetricsSupport.computeBlockFrame(
        startMinute: startMinute,
        durationMinutes: durationMinutes,
        column: column,
        totalColumns: totalColumns,
        totalWidth: totalWidth,
        metrics: metrics,
        style: style
    )
}

// MARK: - Unified Layout (tasks + events, overlap-aware)

/// Computes column assignments for tasks and events together so they never visually overlap.
func computeUnifiedLayouts(
    tasks: [AppTask],
    events: [CalendarEventItem]
) -> (tasks: [TimelineBlockLayout], events: [TimelineEventLayout]) {
    TimelineMetricsSupport.computeUnifiedLayouts(tasks: tasks, events: events)
}

func computeTimelineLayouts(_ tasks: [AppTask]) -> [TimelineBlockLayout] {
    TimelineMetricsSupport.computeTaskLayouts(tasks)
}
#endif

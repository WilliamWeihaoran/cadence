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

    static let schedule = TimelineBlockStyle(
        leadingInset: 8,
        trailingInset: 0,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 24,
        cornerRadius: 6,
        horizontalPadding: 8,
        verticalPadding: 4
    )

    static let calendar = TimelineBlockStyle(
        leadingInset: 4,
        trailingInset: 4,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 22,
        cornerRadius: 5,
        horizontalPadding: 6,
        verticalPadding: 3
    )
}

enum TimelineDropBehavior {
    case wholeColumn
    case perHour
}

struct TimelineBlockLayout {
    let task: AppTask
    let column: Int
    let totalColumns: Int
}

struct TimelineBlockFrame {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var centerX: CGFloat { x + (width / 2) }
    var centerY: CGFloat { y + (height / 2) }
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
    let y = metrics.yOffset(for: startMinute)
    let height = metrics.height(
        for: durationMinutes > 0 ? durationMinutes : 60,
        minHeight: style.minHeight
    )
    let availableWidth = max(0, totalWidth - style.leadingInset - style.trailingInset)
    let innerAvailableWidth = availableWidth * max(0, 1 - (style.sideMarginFraction * 2))
    let leftMargin = style.leadingInset + availableWidth * style.sideMarginFraction
    let columnWidth = innerAvailableWidth / CGFloat(max(totalColumns, 1))
    let width = max(0, columnWidth - style.columnSpacing)
    let x = leftMargin + CGFloat(column) * columnWidth
    return TimelineBlockFrame(x: x, y: y, width: width, height: height)
}

func computeTimelineLayouts(_ tasks: [AppTask]) -> [TimelineBlockLayout] {
    let sorted = tasks.sorted { $0.scheduledStartMin < $1.scheduledStartMin }
    var layouts: [TimelineBlockLayout] = []

    for task in sorted {
        let tStart = task.scheduledStartMin
        let tEnd = tStart + max(task.estimatedMinutes > 0 ? task.estimatedMinutes : 60, 5)
        let overlapping = layouts.filter { layout in
            let oStart = layout.task.scheduledStartMin
            let oEnd = oStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 60, 5)
            return tStart < oEnd && tEnd > oStart
        }
        let usedCols = Set(overlapping.map(\.column))
        var col = 0
        while usedCols.contains(col) { col += 1 }
        layouts.append(TimelineBlockLayout(task: task, column: col, totalColumns: 1))
    }

    return layouts.map { layout in
        let tStart = layout.task.scheduledStartMin
        let tEnd = tStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 60, 5)
        let overlapping = layouts.filter { candidate in
            let oStart = candidate.task.scheduledStartMin
            let oEnd = oStart + max(candidate.task.estimatedMinutes > 0 ? candidate.task.estimatedMinutes : 60, 5)
            return tStart < oEnd && tEnd > oStart
        }
        let totalCols = (overlapping.map(\.column).max() ?? 0) + 1
        return TimelineBlockLayout(task: layout.task, column: layout.column, totalColumns: totalCols)
    }
}
#endif

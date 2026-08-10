#if os(macOS)
import SwiftUI

struct TimelineBlockLayout {
    let task: AppTask
    let column: Int
    let totalColumns: Int
}

struct TimelineBundleLayout {
    let bundle: TaskBundle
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

struct TimelineEventLayout {
    let item: CalendarEventItem
    let column: Int
    let totalColumns: Int
}

enum TimelineMetricsSupport {
    static func computeBlockFrame(
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
        let availableWidth = max(0, totalWidth - style.leadingInset - style.trailingInset) * style.blockWidthFraction
        let innerAvailableWidth = availableWidth * max(0, 1 - (style.sideMarginFraction * 2))
        let leftMargin = style.leadingInset + availableWidth * style.sideMarginFraction
        let columnWidth = innerAvailableWidth / CGFloat(max(totalColumns, 1))
        let width = max(0, columnWidth - style.columnSpacing)
        let x = leftMargin + CGFloat(column) * columnWidth
        return TimelineBlockFrame(x: x, y: y, width: width, height: height)
    }

    static func computeUnifiedLayouts(
        tasks: [AppTask],
        bundles: [TaskBundle],
        events: [CalendarEventItem]
    ) -> (tasks: [TimelineBlockLayout], bundles: [TimelineBundleLayout], events: [TimelineEventLayout]) {
        struct RawSlot {
            enum Kind { case task(AppTask); case bundle(TaskBundle); case event(CalendarEventItem) }
            let kind: Kind
            let startMin: Int
            let endMin: Int
            var column: Int = 0
            var totalColumns: Int = 1
        }

        var slots: [RawSlot] = []
        for task in tasks {
            let start = task.scheduledStartMin
            let end = start + max(task.estimatedMinutes > 0 ? task.estimatedMinutes : 30, 5)
            slots.append(RawSlot(kind: .task(task), startMin: start, endMin: end))
        }
        for bundle in bundles {
            let end = bundle.startMin + max(bundle.durationMinutes, 5)
            slots.append(RawSlot(kind: .bundle(bundle), startMin: bundle.startMin, endMin: end))
        }
        for event in events {
            let end = event.startMin + max(event.durationMinutes, 5)
            slots.append(RawSlot(kind: .event(event), startMin: event.startMin, endMin: end))
        }

        slots.sort { $0.startMin < $1.startMin }

        for i in slots.indices {
            let usedCols = Set(slots[0..<i].filter { other in
                slots[i].startMin < other.endMin && slots[i].endMin > other.startMin
            }.map(\.column))
            var col = 0
            while usedCols.contains(col) { col += 1 }
            slots[i].column = col
        }

        for i in slots.indices {
            let overlapping = slots.filter { other in
                slots[i].startMin < other.endMin && slots[i].endMin > other.startMin
            }
            slots[i].totalColumns = (overlapping.map(\.column).max() ?? 0) + 1
        }

        var taskLayouts: [TimelineBlockLayout] = []
        var bundleLayouts: [TimelineBundleLayout] = []
        var eventLayouts: [TimelineEventLayout] = []
        for slot in slots {
            switch slot.kind {
            case .task(let task):
                taskLayouts.append(TimelineBlockLayout(task: task, column: slot.column, totalColumns: slot.totalColumns))
            case .bundle(let bundle):
                bundleLayouts.append(TimelineBundleLayout(bundle: bundle, column: slot.column, totalColumns: slot.totalColumns))
            case .event(let event):
                eventLayouts.append(TimelineEventLayout(item: event, column: slot.column, totalColumns: slot.totalColumns))
            }
        }
        return (taskLayouts, bundleLayouts, eventLayouts)
    }
}
#endif

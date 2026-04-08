#if os(macOS)
import SwiftUI
import EventKit

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

struct CalendarEventItem: Identifiable {
    let id: String
    let title: String
    let startMin: Int
    let durationMinutes: Int
    let calendarColor: Color
    let calendarTitle: String
    let ekEvent: EKEvent

    init(event: EKEvent) {
        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "Untitled"
        let cal = Calendar.current
        let start = event.startDate ?? Date()
        let comps = cal.dateComponents([.hour, .minute], from: start)
        self.startMin = max(0, (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let end = event.endDate ?? start
        let raw = max(5, Int(end.timeIntervalSince(start) / 60))
        self.durationMinutes = min(raw, 24 * 60 - self.startMin)
        self.calendarColor = Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
        self.calendarTitle = event.calendar?.title ?? ""
        self.ekEvent = event
    }
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
        events: [CalendarEventItem]
    ) -> (tasks: [TimelineBlockLayout], events: [TimelineEventLayout]) {
        struct RawSlot {
            enum Kind { case task(AppTask); case event(CalendarEventItem) }
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
        var eventLayouts: [TimelineEventLayout] = []
        for slot in slots {
            switch slot.kind {
            case .task(let task):
                taskLayouts.append(TimelineBlockLayout(task: task, column: slot.column, totalColumns: slot.totalColumns))
            case .event(let event):
                eventLayouts.append(TimelineEventLayout(item: event, column: slot.column, totalColumns: slot.totalColumns))
            }
        }
        return (taskLayouts, eventLayouts)
    }

    static func computeTaskLayouts(_ tasks: [AppTask]) -> [TimelineBlockLayout] {
        let sorted = tasks.sorted { $0.scheduledStartMin < $1.scheduledStartMin }
        var layouts: [TimelineBlockLayout] = []

        for task in sorted {
            let tStart = task.scheduledStartMin
            let tEnd = tStart + max(task.estimatedMinutes > 0 ? task.estimatedMinutes : 30, 5)
            let overlapping = layouts.filter { layout in
                let oStart = layout.task.scheduledStartMin
                let oEnd = oStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 30, 5)
                return tStart < oEnd && tEnd > oStart
            }
            let usedCols = Set(overlapping.map(\.column))
            var col = 0
            while usedCols.contains(col) { col += 1 }
            layouts.append(TimelineBlockLayout(task: task, column: col, totalColumns: 1))
        }

        return layouts.map { layout in
            let tStart = layout.task.scheduledStartMin
            let tEnd = tStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 30, 5)
            let overlapping = layouts.filter { candidate in
                let oStart = candidate.task.scheduledStartMin
                let oEnd = oStart + max(candidate.task.estimatedMinutes > 0 ? candidate.task.estimatedMinutes : 30, 5)
                return tStart < oEnd && tEnd > oStart
            }
            let totalCols = (overlapping.map(\.column).max() ?? 0) + 1
            return TimelineBlockLayout(task: layout.task, column: layout.column, totalColumns: totalCols)
        }
    }
}
#endif

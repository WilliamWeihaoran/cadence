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

    /// The rect a drag-to-create draft occupies: one full-width block slot for the drawn range.
    ///
    /// The ghost the user drags out and the popover anchored to it have to be the *same* rect as
    /// the block that gets created, so both go through `computeBlockFrame` rather than re-deriving
    /// `totalWidth - insets` by hand. Deriving the width independently is what made the ghost the
    /// only rect on the canvas that ignored `style.blockWidthFraction` — edit the fraction and
    /// every real block moved while the ghost and its popover arrow stayed put.
    static func computeDraftFrame(
        startMinute: Int,
        endMinute: Int,
        totalWidth: CGFloat,
        metrics: TimelineMetrics,
        style: TimelineBlockStyle
    ) -> TimelineBlockFrame {
        computeBlockFrame(
            startMinute: startMinute,
            durationMinutes: max(5, endMinute - startMinute),
            column: 0,
            totalColumns: 1,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    /// Whether a canvas point falls inside any already-occupied block.
    ///
    /// The drag-to-create gate: a drag that starts on top of a block belongs to that block, not
    /// to the create layer. Lives beside `computeBlockFrame` because it hit-tests the rects that
    /// function produces — it used to sit next to the row-index reconstruction it shared a
    /// coordinate assumption with, and drifted with it.
    static func isInsideBlockedBlock(point: CGPoint, blockedFrames: [TimelineBlockFrame]) -> Bool {
        blockedFrames.contains { frame in
            point.x >= frame.x &&
            point.x <= frame.x + frame.width &&
            point.y >= frame.y &&
            point.y <= frame.y + frame.height
        }
    }

    /// The "drop here to bundle" shelf pinned to the top of a task block.
    ///
    /// One definition, read by the shelf that draws it *and* by the canvas drop delegate that has
    /// to know the shelf owns that region. Which of the two competing drops wins used to be
    /// decided by a 750 ms wall-clock window armed by whichever async payload callback returned
    /// first — so the same gesture bundled a task or moved it to a minute depending on timing.
    static func bundleDropShelfFrame(blockFrame: TimelineBlockFrame) -> TimelineBlockFrame {
        let shelfHeight = bundleDropShelfHeight(blockHeight: blockFrame.height)
        return TimelineBlockFrame(
            x: blockFrame.x,
            y: blockFrame.y,
            width: blockFrame.width,
            height: shelfHeight + (bundleDropShelfPadding * 2)
        )
    }

    /// Inset around the shelf capsule; part of its hit target.
    static let bundleDropShelfPadding: CGFloat = 5

    static func bundleDropShelfHeight(blockHeight: CGFloat) -> CGFloat {
        max(12, min(max(30, blockHeight * 0.38), 46, blockHeight - 10))
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
        // Precondition, now enforced rather than assumed: only tasks with a real minute-of-day
        // are laid out. `scheduledStartMin == -1` is the "unscheduled" sentinel — `SchedulingActions`
        // writes it in seven places — and it is not a position. A -1 task reaching here drew a
        // block just above the top of the canvas with a hit target at negative Y, labelled itself
        // "11:59 PM – 12:29 AM" through `TimeFormatters`' modulo normalisation, and held column 0
        // against every real block for the whole day. Both current callers filter it; nothing in
        // this layer said they had to.
        for task in tasks where task.scheduledStartMin >= 0 {
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

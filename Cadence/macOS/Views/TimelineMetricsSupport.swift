#if os(macOS)
import SwiftUI

struct TimelineBlockLayout {
    let task: AppTask
    let column: Int
    let totalColumns: Int
}

// `TimelineBundleLayout` was declared here, beside `TimelineBlockLayout`. [[T-3170]] deleted the
// only view that consumed one, `TimelineBundleBlock`, so the solver no longer produces them.

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
    /// How many earlier events in this same column this one is drawn over (T-3161). 0 for an
    /// ordinary column block; tasks and bundles have no equivalent and always draw at 0.
    let cascadeDepth: Int
}

enum TimelineMetricsSupport {
    static func computeBlockFrame(
        startMinute: Int,
        durationMinutes: Int,
        column: Int,
        totalColumns: Int,
        cascadeDepth: Int = 0,
        totalWidth: CGFloat,
        metrics: TimelineMetrics,
        style: TimelineBlockStyle
    ) -> TimelineBlockFrame {
        let y = metrics.yOffset(for: startMinute)
        // No zero-duration fallback here. This is geometry: it draws the length it is handed, and
        // "how long is a task with no estimate" is `AppTask.timelineDurationMinutes`' question, not
        // this function's. The `> 0 ? : 60` that used to sit here was reachable only from tasks —
        // bundle and event durations are clamped to at least 5 at construction — and it was the
        // reason a zero-estimate task was *drawn* an hour tall while being *columned* as 30 minutes,
        // so it could overlap the very neighbour it had been laid out beside.
        let height = metrics.height(for: durationMinutes, minHeight: style.minHeight)
        let availableWidth = max(0, totalWidth - style.leadingInset - style.trailingInset) * style.blockWidthFraction
        let innerAvailableWidth = availableWidth * max(0, 1 - (style.sideMarginFraction * 2))
        let leftMargin = style.leadingInset + availableWidth * style.sideMarginFraction
        let columnWidth = innerAvailableWidth / CGFloat(max(totalColumns, 1))
        let slotWidth = max(0, columnWidth - style.columnSpacing)
        // The cascade (T-3161). A block at depth 0 is exactly what it always was; a deeper one is
        // pushed off its column's leading edge and keeps the column's trailing edge, so it runs
        // *over* the blocks it indented past rather than beside them. The trailing edge is the
        // column's and not the canvas's on purpose: a cascading event that ran to the canvas edge
        // would paint over a task sitting in a column to its right, and the owner ruled on events
        // only. In a cluster of events alone the column *is* the canvas width, so the screenshot's
        // "all three run to the right edge" is reproduced either way.
        let indent = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: slotWidth, depth: cascadeDepth)
        let width = max(0, slotWidth - indent)
        let x = leftMargin + CGFloat(column) * columnWidth + indent
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

    /// Column + cascade placement for everything drawn on one day's canvas.
    ///
    /// `cascadeGapMinutes` is the zoom-derived threshold from `CadenceCalendarOverlapLayout` — the
    /// block header's height in minutes at the current `hourHeight`. It is required rather than
    /// defaulted because a silently-absent threshold is indistinguishable from "nothing cascades",
    /// which is the bug this ticket exists to fix.
    static func computeUnifiedLayouts(
        tasks: [AppTask],
        events: [CalendarEventItem],
        cascadeGapMinutes: Int
    ) -> (tasks: [TimelineBlockLayout], events: [TimelineEventLayout]) {
        struct RawSlot {
            enum Kind { case task(AppTask); case event(CalendarEventItem) }
            let kind: Kind
            let startMin: Int
            let endMin: Int
            /// Only events cascade. Tasks keep the equal-column packing they have always had —
            /// the owner ruled on events and explicitly left this open. (Blocks packed the same
            /// way until [[T-3170]] removed them; the rule is unchanged, it has one fewer kind.)
            var mayCascade: Bool { if case .event = kind { return true } else { return false } }
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
            let end = start + task.timelineDurationMinutes
            slots.append(RawSlot(kind: .task(task), startMin: start, endMin: end))
        }
        for event in events {
            let end = event.startMin + max(event.durationMinutes, 5)
            slots.append(RawSlot(kind: .event(event), startMin: event.startMin, endMin: end))
        }

        // Draw order is start order, and that is load-bearing now rather than incidental: the
        // blocks layer renders these arrays in order at one `zIndex`, so the later-starting event
        // is the one painted on top — and, because SwiftUI hit-tests topmost first, the one that
        // receives the click in the region where a cascade covers its predecessor.
        // Stable by construction. `Array.sort` is not stable, so two blocks starting in the same
        // minute used to swap places between passes — which, once draw order decides who is on top
        // and who answers the click, is a visible flicker rather than a tidiness point.
        slots = slots.enumerated().sorted { lhs, rhs in
            if lhs.element.startMin != rhs.element.startMin { return lhs.element.startMin < rhs.element.startMin }
            return lhs.offset < rhs.offset
        }.map(\.element)

        let placements = CadenceCalendarOverlapLayout.solve(
            slots: slots.map {
                CadenceCalendarOverlapLayout.Slot(
                    startMin: $0.startMin,
                    endMin: $0.endMin,
                    mayCascade: $0.mayCascade
                )
            },
            cascadeGapMinutes: cascadeGapMinutes
        )

        var taskLayouts: [TimelineBlockLayout] = []
        var eventLayouts: [TimelineEventLayout] = []
        for (slot, placement) in zip(slots, placements) {
            switch slot.kind {
            case .task(let task):
                taskLayouts.append(TimelineBlockLayout(task: task, column: placement.column, totalColumns: placement.totalColumns))
            case .event(let event):
                eventLayouts.append(TimelineEventLayout(
                    item: event,
                    column: placement.column,
                    totalColumns: placement.totalColumns,
                    cascadeDepth: placement.cascadeDepth
                ))
            }
        }
        return (taskLayouts, eventLayouts)
    }
}
#endif

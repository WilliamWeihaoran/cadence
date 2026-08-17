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
        clampStart(Int(y / hourHeight * 60) + startHour * 60)
    }

    /// Clamps a minute so a block of `duration` minutes still fits inside the **visible** canvas.
    ///
    /// `TimelineDayRange.clampStart` is the same clamp over the whole day. The two differ only in
    /// their bounds — they used to differ in their floor as well, and a third spelling used
    /// `1440 - 15`. A canvas whose `startHour` is not 0 must never resolve a gesture to a minute
    /// it cannot draw, which is why the visible clamp exists at all.
    func clampStart(_ minute: Int, duration: Int = TimelineDayRange.minimumDuration) -> Int {
        let usableDuration = max(TimelineDayRange.minimumDuration, duration)
        let lower = startHour * 60
        let upper = max(lower, endHour * 60 - usableDuration)
        return min(max(minute, lower), upper)
    }

    func snappedMinute(fromY y: CGFloat) -> Int {
        snap5(yToMins(y))
    }

    func yOffset(for minute: Int) -> CGFloat {
        yOffset(forFractionalMinute: CGFloat(minute))
    }

    /// Minute → canvas Y, for callers that track a sub-minute position (the current-time line) or
    /// a range boundary (the work-hours band). Both used to carry their own copy of this
    /// expression, so a top inset or a non-linear zoom here would have moved every block while
    /// leaving the red line and the amber band behind.
    func yOffset(forFractionalMinute minute: CGFloat) -> CGFloat {
        (minute - CGFloat(startHour * 60)) * hourHeight / 60
    }

    func height(for durationMinutes: Int, minHeight: CGFloat) -> CGFloat {
        max(minHeight, CGFloat(max(durationMinutes, 5)) * hourHeight / 60)
    }
}

// MARK: - Day range

/// The minute range a stored `scheduledStartMin` lives in.
///
/// A `TimelineMetrics`' visible range can be narrower than a day; this is the whole day, and it is
/// what the persistence layer clamps against. Both clamps now share one floor — they were written
/// four times with three different bounds, one of them the bare literal `1425`.
enum TimelineDayRange {
    static let startMin = 0
    static let endMin = 24 * 60
    /// Shortest slot anything scheduled on the timeline may occupy.
    static let minimumDuration = 5

    /// Clamps a start minute so a block of `duration` minutes still ends inside the day.
    static func clampStart(_ minute: Int, duration: Int = minimumDuration) -> Int {
        let usableDuration = max(minimumDuration, duration)
        return min(max(minute, startMin), max(startMin, endMin - usableDuration))
    }
}

// MARK: - Zoom

/// Zoom level → how much of the day fills the viewport.
///
/// The render path and the remembered-scroll-position path have to agree exactly or the hour
/// restored on relaunch is not the hour saved on exit. This existed as the same ternary in three
/// files, and widening `TimelineZoomControl`'s `range` past its top level would have silently
/// collapsed the new level into the last one in all three with no compiler complaint — so the
/// range the control is given comes from here too.
enum TimelineZoom {
    static let levels = 1...3

    static func targetHours(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 12
        case 2: return 8
        default: return 4
        }
    }

    static func hourHeight(viewportHeight: CGFloat, level: Int) -> CGFloat {
        viewportHeight / targetHours(level)
    }
}

// MARK: - Shared block geometry

/// Which end of a block an edge-resize gesture is dragging.
enum TimelineResizeEdge {
    case start
    case end
}

/// Geometry every block type on the canvas draws itself with.
///
/// These were per-file literals. `resizeHandleHeight` in particular was declared twice — once
/// shared by the task and bundle blocks, once privately by the event block — and the event
/// block's resize *reconstruction* read its private copy, so enlarging the shared handle would
/// have left event resizing off by the difference with nothing to catch it.
enum TimelineBlockGeometry {
    /// Tallest a resize strip is ever drawn. Every block with room for it gets exactly this.
    static let maximumResizeHandleHeight: CGFloat = 8

    /// Thinnest strip still worth drawing. A strip below this is not a reliable pointer target —
    /// it cannot be grabbed on purpose, it can only be hit by accident — so the handles are
    /// dropped entirely rather than shrunk past it.
    static let minimumResizeHandleHeight: CGFloat = 5

    /// Interior height the block keeps for its own tap target, never surrendered to the handles.
    ///
    /// The handles used to be a flat 8 pt each regardless of how tall the block was drawn, and
    /// `height(for:minHeight:)` floors a block at 22 pt (`.calendar`) or 24 pt (`.schedule`) — so
    /// 16 of those points were resize strip and a 6–8 pt sliver was left to open the task. Because
    /// the strips carry a `minimumDistance: 0` drag that outranks the tap underneath, a click that
    /// missed the sliver did not merely fail to open the inspector, it dismissed it.
    static let minimumTapCoreHeight: CGFloat = 16

    /// Height of each of the two resize strips on a block drawn `blockHeight` points tall.
    ///
    /// `0` means the block is too short to carry them and draws none: the whole block is then tap
    /// target, and its length is edited from the inspector the tap now reliably opens. Because
    /// this reads the *drawn* height, zooming in on a short block brings the handles back.
    static func resizeHandleHeight(blockHeight: CGFloat) -> CGFloat {
        let available = (blockHeight - minimumTapCoreHeight) / 2
        guard available >= minimumResizeHandleHeight else { return 0 }
        return min(maximumResizeHandleHeight, available)
    }

    /// Interior of a block that no resize strip covers. Never below `minimumTapCoreHeight` for a
    /// block that draws handles, and the block's whole height for one that does not.
    static func tapCoreHeight(blockHeight: CGFloat) -> CGFloat {
        max(0, blockHeight - 2 * resizeHandleHeight(blockHeight: blockHeight))
    }

    /// Vertical slop before a press on a resize strip counts as a resize rather than a click.
    static let resizeActivationDistance: CGFloat = 3

    /// Whether a press on a resize strip has moved far enough to be a resize.
    ///
    /// The strips carry `DragGesture(minimumDistance: 0)`, which fires on mouse-**down**. Starting
    /// the resize there meant a press that never moved had already cleared the selection and, on
    /// an event, already queued an EventKit write. Resize is a vertical operation, so only
    /// vertical travel arms it.
    static func isResizeDrag(translation: CGSize) -> Bool {
        abs(translation.height) >= resizeActivationDistance
    }

    /// Width of the grab capsule drawn inside a resize strip on a block of the given width.
    static func handleCapsuleWidth(blockWidth: CGFloat) -> CGFloat {
        min(18, max(10, blockWidth - 18))
    }
}

/// One edge-resize gesture, from the first `onChanged` to `onEnded`.
///
/// This replaces the `activeResizeEdge` / `resizeOriginStartMin` / `resizeOriginEndMin` trio that
/// each of the three block types declared separately, along with three verbatim copies of the
/// handle-local-Y → snapped-minute conversion that read them.
struct TimelineResizeSession: Equatable {
    let edge: TimelineResizeEdge
    let originStartMin: Int
    let originEndMin: Int
    /// Minutes between the pointer and the edge it grabbed, measured when it grabbed it.
    ///
    /// Without it the edge jumps to whatever minute is under the pointer, which is the edge's own
    /// minute only while the block is drawn at its exact geometric height. `height(for:minHeight:)`
    /// floors a short block at `style.minHeight`, so the bottom handle of a 10-minute block at
    /// `hourHeight` 50 is drawn ~16 pt below the minute the block ends at — grabbing it used to
    /// stretch the block to the handle before the pointer had moved at all.
    let grabMinuteOffset: Int

    static func begin(
        edge: TimelineResizeEdge,
        localY: CGFloat,
        blockTopY: CGFloat,
        blockDrawnHeight: CGFloat,
        originStartMin: Int,
        originEndMin: Int,
        metrics: TimelineMetrics
    ) -> TimelineResizeSession {
        let pointerMinute = metrics.resizePointerMinute(
            edge: edge,
            localY: localY,
            blockTopY: blockTopY,
            blockDrawnHeight: blockDrawnHeight
        )
        let grabbedEdgeMinute = edge == .start ? originStartMin : originEndMin
        return TimelineResizeSession(
            edge: edge,
            originStartMin: originStartMin,
            originEndMin: originEndMin,
            grabMinuteOffset: pointerMinute - grabbedEdgeMinute
        )
    }
}

extension TimelineMetrics {
    /// Canvas minute under a resize-handle pointer.
    ///
    /// The handles are `.overlay(alignment:)`s on the *drawn* block and their drag gestures read
    /// the handle's own local space, so the pointer's canvas Y is measured against where the
    /// handle is actually drawn — `blockDrawnHeight`, floor included, not the geometric height.
    func resizePointerMinute(
        edge: TimelineResizeEdge,
        localY: CGFloat,
        blockTopY: CGFloat,
        blockDrawnHeight: CGFloat
    ) -> Int {
        let handleTopOffset: CGFloat
        switch edge {
        case .start:
            handleTopOffset = 0
        case .end:
            // Reads the *same* height function the strip is drawn with. This was the shared
            // constant, which was correct only while the strip's height was constant.
            handleTopOffset = max(
                0,
                blockDrawnHeight - TimelineBlockGeometry.resizeHandleHeight(blockHeight: blockDrawnHeight)
            )
        }
        return snappedMinute(fromY: blockTopY + handleTopOffset + localY)
    }

    /// The block's minute range partway through an edge-resize gesture.
    ///
    /// The un-dragged edge stays pinned to its origin and the dragged one follows the pointer,
    /// never crossing to within 5 minutes of the other.
    func resizedRange(
        session: TimelineResizeSession,
        localY: CGFloat,
        blockTopY: CGFloat,
        blockDrawnHeight: CGFloat
    ) -> (start: Int, end: Int) {
        let pointerMinute = resizePointerMinute(
            edge: session.edge,
            localY: localY,
            blockTopY: blockTopY,
            blockDrawnHeight: blockDrawnHeight
        )
        let edgeMinute = pointerMinute - session.grabMinuteOffset
        switch session.edge {
        case .start:
            return (min(edgeMinute, session.originEndMin - 5), session.originEndMin)
        case .end:
            return (session.originStartMin, max(edgeMinute, session.originStartMin + 5))
        }
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
        cornerRadius: 10,
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
        cornerRadius: 9,
        horizontalPadding: 6,
        verticalPadding: 3,
        blockWidthFraction: 0.95
    )
}

enum CalendarVisualStyle {
    static let majorGridOpacity: Double = 0.36
    static let minorGridOpacity: Double = 0.30
    static let majorGridLineWidth: CGFloat = 0.95
    static let minorGridLineWidth: CGFloat = 0.85
    static let dividerOpacity: Double = 0.18
    static let columnGridOpacity: Double = 0.09
    static let timelineDaySeparatorOpacity: Double = 0.16
    static let timelineDaySeparatorLineWidth: CGFloat = 0.95
    static let chipRadius: CGFloat = 6
    static let cardShadow = Theme.cardElevationShadow
    static let selectedCardShadow = Theme.overlayCardShadow
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
    bundles: [TaskBundle] = [],
    events: [CalendarEventItem]
) -> (tasks: [TimelineBlockLayout], bundles: [TimelineBundleLayout], events: [TimelineEventLayout]) {
    TimelineMetricsSupport.computeUnifiedLayouts(tasks: tasks, bundles: bundles, events: events)
}
#endif

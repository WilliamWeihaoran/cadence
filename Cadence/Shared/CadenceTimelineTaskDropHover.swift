import CoreGraphics
import Foundation

/// What a day column shows while a dragged TASK is over it, and the minute it lands at
/// ([[T-8142]]).
///
/// **The decision is macOS's, read for both platforms** ([[T-8201]]). The Mac canvas has always
/// answered a hovering task with that task's own block, drawn at the minute the release will write
/// and at its own length, in a blue-tinted plate with a blue outline (`TimelineDraggedTaskPreview`,
/// which reads `fillOpacity` and `strokeOpacity` from here). Nothing about that is pointer-shaped:
/// a finger dragging a row is asking the same question a pointer is -- *where will this go?* -- so
/// the iOS column draws the same plate. The grid it snaps to is the one platform difference that
/// does name its constraint (`CadenceScheduleSupport.touchTimeGridMinutes` against
/// `pointerTimeGridMinutes`, T-1293), and it arrives here through `timelineMinute`.
///
/// **Why this is not the dropped `+`'s ghost slot, and does not have to be.** The capture palette's
/// `+` hovering the same column shows a "New task" row (`iOSNewTaskDropGhost.slot`). That names a
/// thing that does not exist yet; this names a task that does, at its own length. macOS draws the
/// same two different things for the same reason -- `TimelineDraftGhostLayer` for a range being
/// created, `TimelineDraggedTaskPreview` for a task being moved -- so the canvas is not saying
/// "here" in two voices, it is saying two different things.
///
/// **The minute here and the minute committed are one call.** The column computes both the hover
/// and the release through `resolve(atY:hourHeight:durationMinutes:)`, so the plate under the finger
/// is where the block lands.
struct CadenceTimelineTaskDropHover: Equatable, Sendable {
    /// The minute the dragged block's top resolves to.
    let startMinute: Int
    /// The hovering task's own length, or `nil` while the drag has not yet named a task the host
    /// holds. The payload is read asynchronously, and until it arrives the plate claims only the
    /// start -- one grid step tall -- rather than inventing a length.
    let durationMinutes: Int?

    /// The plate's fill and outline, the Mac preview's figures.
    static let fillOpacity: Double = 0.16
    static let strokeOpacity: Double = 0.55

    /// The minute a task whose top is at `y` lands at, clamped -- once its length is known -- so
    /// the whole block stays on the drawn day ([[T-5370]], which is the same clamp macOS's
    /// `TimelineMetrics.snappedStart(fromY:duration:)` applies). Snap, then clamp, the order macOS
    /// uses, so a block whose length is off the grid still ends exactly at the canvas's last minute.
    static func resolve(
        atY y: CGFloat,
        hourHeight: CGFloat,
        durationMinutes: Int?,
        startHour: Int = CadenceScheduleSupport.calendarStartHour,
        endHour: Int = CadenceScheduleSupport.calendarEndHour
    ) -> CadenceTimelineTaskDropHover {
        let minute = CadenceScheduleSupport.timelineMinute(
            atY: y,
            hourHeight: hourHeight,
            startHour: startHour,
            endHour: endHour
        )
        guard let durationMinutes, durationMinutes > 0 else {
            return CadenceTimelineTaskDropHover(startMinute: minute, durationMinutes: nil)
        }
        let lower = startHour * 60
        let upper = max(lower, endHour * 60 - durationMinutes)
        return CadenceTimelineTaskDropHover(
            startMinute: min(max(minute, lower), upper),
            durationMinutes: durationMinutes
        )
    }

    /// The range the plate is drawn over: the task's own length once known, one touch-grid step
    /// until then, clamped into the drawn hours the way every block on the column is.
    var drawnRange: (start: Int, end: Int) {
        let length = durationMinutes ?? CadenceScheduleSupport.touchTimeGridMinutes
        return CadenceScheduleSupport.timelineVisibleRange(start: startMinute, end: startMinute + length)
    }
}

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

extension CadenceTimelineTaskDropHover {

    /// How the plate arranges the two things it says — the hovering task's title, and the range
    /// the release will write ([[T-8455]]).
    enum LabelLayout: Equatable, Sendable {
        /// The title over the range. The plate's shape wherever there is room for two rows.
        case stacked
        /// The title and the range on one row, for a plate with room for only one.
        case inline
    }

    /// What two stacked rows cost: the padding above and below them, both line heights, and the
    /// gap between them. `CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize:)` is the
    /// measured table the timed blocks already derive their own header heights from; a font size
    /// off that table takes its documented 1.2x fallback, which is what this decision wants —
    /// it chooses between two arrangements rather than protecting a header from a cascade.
    static func stackedLabelHeight(
        verticalPadding: CGFloat,
        rowSpacing: CGFloat,
        titleFontSize: CGFloat,
        timeFontSize: CGFloat
    ) -> CGFloat {
        verticalPadding * 2
            + CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: titleFontSize)
            + rowSpacing
            + CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: timeFontSize)
    }

    /// The arrangement a plate `plateHeight` points tall can carry.
    ///
    /// **Why the plate needs this and the block under it does not** ([[T-8455]]). A block drawn on
    /// the canvas says its title and nothing else, so a one-grid-step block has room for what it
    /// says. The plate says one more thing — *where this lands* — and [[T-8451]] gave it the title
    /// as well, which at one grid step took the only row there was: a 15-minute task hovered
    /// reading its own name and no time at all, where before it read `4 PM - 4:15 PM`. A plate
    /// that cannot stack them puts them on one row instead, so neither height drops either.
    ///
    /// **This is not the Mac preview's capsule, and the Mac is not the model here.**
    /// `TimelineDraggedTaskPreview` hangs a *duration* capsule — "1h" — outside its block's
    /// top-trailing corner, which does survive any height but says a different fact: at one grid
    /// step the Mac plate states its duration and, its body being under both of
    /// `timelineBlockBody`'s height gates, neither its title nor its clock range. Porting the
    /// capsule would restore neither of the two things this plate is for. What the two platforms
    /// should agree on is *what the plate says at a given height*, which is why that decision is
    /// here rather than in either view. The Mac half is [[T-8456]].
    static func labelLayout(
        plateHeight: CGFloat,
        verticalPadding: CGFloat,
        rowSpacing: CGFloat,
        titleFontSize: CGFloat,
        timeFontSize: CGFloat
    ) -> LabelLayout {
        let stacked = stackedLabelHeight(
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            titleFontSize: titleFontSize,
            timeFontSize: timeFontSize
        )
        return plateHeight >= stacked ? .stacked : .inline
    }
}

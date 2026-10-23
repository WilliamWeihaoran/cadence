#if os(macOS)
import Foundation

/// What a timeline event block may offer to change, and what it does with the answer
/// ([[T-5241]], [[T-5242]]).
///
/// Pure, so the three rules below are testable without a view or an `EKEvent`:
///
/// - **A read-only event offers no gesture at all.** Birthdays, Holidays and subscribed feeds are
///   drawn on the timeline and EventKit refuses every write to them. The block used to let them be
///   dragged and resized anyway, so the refusal arrived as an alert *after* the block had already
///   moved. iOS refuses before trying (`iOSCalendarManager.canModify`); `isEditable` is the
///   caller's `CalendarEventEditPopover.isEditable(_:)`, which is that same rule.
/// - **A resize handle sits only on an edge the event has.** A multi-day timed event is drawn as
///   one segment per day, clipped at midnight. A clip is not an edge:
///   `CalendarEventItem.eventDateRangeForEditedSegment` moves the event's start only from its first
///   segment and its end only from its last, so a drag on a midnight edge wrote back the range the
///   event already had.
/// - **Live drag state survives a write only when a store change is coming to replace it.** The
///   block holds the dragged shape until the refreshed item arrives (`.onChange` on the item's
///   `startMin`/`durationMinutes`). A refused write changes nothing, and neither does a write of the
///   range the event already has, so in both cases that observation never fires: the block kept
///   drawing a time the event is not at, and `handleBlockTap` ignored every later click on it.
enum TimelineEventBlockEditGate {
    /// Whether the move gesture is attached.
    static func allowsMove(isEditable: Bool) -> Bool {
        isEditable
    }

    /// Whether `edge` draws a resize handle on this segment.
    static func drawsResizeHandle(
        edge: TimelineResizeEdge,
        isEditable: Bool,
        isFirstSegment: Bool,
        isLastSegment: Bool
    ) -> Bool {
        guard isEditable else { return false }
        switch edge {
        case .start: return isFirstSegment
        case .end: return isLastSegment
        }
    }

    /// Whether the block must put itself back after asking for `requested`: the write was refused,
    /// or it asked for the range the event already spans.
    static func clearsLiveState(
        after failure: CalendarWriteFailure?,
        requested: (start: Date, end: Date),
        current: (start: Date, end: Date)
    ) -> Bool {
        if failure != nil { return true }
        return requested.start == current.start && requested.end == current.end
    }

    /// Whether a finished move gesture writes anything ([[T-5354]]).
    ///
    /// The move recogniser starts after 4pt, so a click whose pointer slips sideways is a "move"
    /// that ends on the minute the event already starts at. Writing it raised the recurring-scope
    /// dialog for nothing on a series member. A click is a click — the resize handle's rule, and
    /// iOS's, which skips the commit when the snapped delta is zero.
    static func commitsMove(to newStartMin: Int, from storedStartMin: Int) -> Bool {
        newStartMin != storedStartMin
    }

    /// The start minute a move gesture resolves to for a block whose top is at canvas `topY`
    /// ([[T-5355]]).
    ///
    /// A single-day event stops where it still ends by the canvas's last minute — iOS's
    /// `latestStart = dayEndMinute - duration` (`CadenceTimelineBlockEditSupport.editedRange`).
    /// The bare `snappedMinute(fromY:)` clamps for a 5-minute block, so an hour-long event dropped
    /// on the last slot was written as 23:55-00:55 the next day. A multi-day event already spans
    /// midnight and its segment moves the whole event by the delta, so it keeps the start-only clamp.
    static func movedStartMinute(
        topY: CGFloat,
        durationMinutes: Int,
        isMultiDayTimedEvent: Bool,
        metrics: TimelineMetrics
    ) -> Int {
        let snapped = metrics.snappedMinute(fromY: max(0, topY))
        guard !isMultiDayTimedEvent else { return snapped }
        return metrics.clampStart(snapped, duration: durationMinutes)
    }
}
#endif

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
///   caller's `CalendarEventEditPopover.isEditable(_:)`, which is that same rule. An
///   organizer-cancelled event is view-only too ([[T-18014]], [[T-18179]]), so it offers none either.
/// - **A resize handle sits only on an edge the event has.** A multi-day timed event is drawn as
///   one segment per day, clipped at midnight. A clip is not an edge:
///   `CalendarEventItem.eventDateRangeForResizedSegment` moves the event's start only from its first
///   segment and its end only from its last, so a drag on a midnight edge wrote back the range the
///   event already had.
/// - **Live drag state survives a write only when a store change is coming to replace it.** The
///   block holds the dragged shape until the refreshed item arrives (`.onChange` on the item's
///   `startMin`/`durationMinutes`). A refused write changes nothing, and neither does a write of the
///   range the event already has, so in both cases that observation never fires: the block kept
///   drawing a time the event is not at, and `handleBlockTap` ignored every later click on it.
enum TimelineEventBlockEditGate {
    /// Whether the move gesture is attached -- and, through `drawsResizeHandle` and the all-day
    /// chip's `calendarEventDraggable`, whether any gesture may write a new time.
    ///
    /// The same view-only rule `allowsDelete` reads ([[T-18179]]): an organizer-cancelled invite on
    /// a writable calendar used to stay draggable and resizable while its popover said it "can only
    /// be viewed here" and Cmd+Delete over it did nothing. Move, resize, delete and the popover now
    /// answer from one rule.
    static func allowsMove(isEditable: Bool, isCancelled: Bool) -> Bool {
        isViewOnly(isEditable: isEditable, isCancelled: isCancelled) == false
    }

    /// Whether the hovered block registers a Cmd+Delete action ([[T-18175]]).
    ///
    /// The popover draws no Delete for a read-only event (Birthdays, Holidays, subscribed feeds)
    /// nor for an organizer-cancelled one ([[T-18014]]); the keyboard used to ask "Delete Calendar
    /// Event?" for both anyway -- a confirmation that could only end in a refusal on a read-only
    /// calendar, and that really deleted a cancelled invite the editor treats as view-only. This is
    /// the editor's own rule, read from `viewOnlyNotice` rather than restated: a view-only notice
    /// means no delete, from any surface.
    static func allowsDelete(isEditable: Bool, isCancelled: Bool) -> Bool {
        isViewOnly(isEditable: isEditable, isCancelled: isCancelled) == false
    }

    /// The editor's view-only rule, read rather than restated: a view-only notice means no write,
    /// from any surface.
    private static func isViewOnly(isEditable: Bool, isCancelled: Bool) -> Bool {
        CadenceCalendarEventEditingSupport.viewOnlyNotice(
            calendarName: "",
            isEventEditable: isEditable,
            isEventCancelled: isCancelled
        ) != nil
    }

    /// Whether `edge` draws a resize handle on this segment.
    static func drawsResizeHandle(
        edge: TimelineResizeEdge,
        isEditable: Bool,
        isCancelled: Bool,
        isFirstSegment: Bool,
        isLastSegment: Bool
    ) -> Bool {
        guard allowsMove(isEditable: isEditable, isCancelled: isCancelled) else { return false }
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

    /// Whether a finished resize gesture writes anything ([[T-18548]]).
    ///
    /// A handle dragged past the 3pt activation distance and released back on its own row, or an
    /// end handle pulled below 24:00 on an event that already ends there (the range clamps to the
    /// day), resolves to the range the event already spans. Writing it raised "Change recurring
    /// event?" for nothing on a series member -- the move's [[T-5354]] rule, for the edges.
    /// Compared against the stored range, never the live one.
    static func commitsResize(start: Int, end: Int, storedStart: Int, storedEnd: Int) -> Bool {
        start != storedStart || end != storedEnd
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

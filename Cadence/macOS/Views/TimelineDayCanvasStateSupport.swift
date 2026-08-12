#if os(macOS)
import SwiftUI

/// The drag-to-create draft range, as one value.
///
/// This was four independent `@State` optionals on `TimelineDayCanvas` — `dragStartMin`,
/// `dragEndMin`, `pendingStartMin`, `pendingEndMin` — coalesced *per field* at the point of use
/// (`dragStartMin ?? pendingStartMin`, `dragEndMin ?? pendingEndMin`). Any state where one member
/// of a pair was nil and the other was not produced a range built from a live drag's start and a
/// committed draft's end. Keeping start and end in one payload makes that unrepresentable, and
/// the case tells the ghost apart from the committed draft the popover is anchored to.
enum TimelineDraftSelection: Equatable {
    /// The pointer is still down: draw the ghost, no popover yet.
    case live(start: Int, end: Int)
    /// The gesture ended: this is the range the popover is anchored to *and* the range it creates.
    case pending(start: Int, end: Int)

    var start: Int {
        switch self {
        case .live(let start, _), .pending(let start, _): return start
        }
    }

    var end: Int {
        switch self {
        case .live(_, let end), .pending(_, let end): return end
        }
    }

    var range: (start: Int, end: Int) { (start, end) }

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

enum TimelineDayCanvasStateSupport {
    /// Orders the raw gesture pair and floors it at five minutes.
    ///
    /// `startMin` is always the gesture's fixed anchor point and `endMin` tracks the live drag
    /// location, so it moves both later (normal drag) and earlier (upward drag) than the anchor.
    /// Swapping via min/max rather than clamping `endMin` against a frozen anchor is what lets an
    /// upward drag extend the block upward instead of collapsing it to a fixed 5-minute block at
    /// the mouse-down point.
    static func normalizedDraftRange(startMin: Int, endMin: Int) -> (start: Int, end: Int) {
        let lower = min(startMin, endMin)
        let upper = max(startMin, endMin)
        return (lower, max(upper, lower + 5))
    }

    static func clearDraftCreation(
        draft: inout TimelineDraftSelection?,
        showNewTaskPopover: inout Bool,
        selectedEventID: inout String?
    ) {
        draft = nil
        showNewTaskPopover = false
        selectedEventID = nil
    }

    static func beginDraftSelection(
        startMin: Int,
        endMin: Int,
        draft: inout TimelineDraftSelection?,
        showNewTaskPopover: inout Bool,
        selectedTaskID: inout UUID?
    ) {
        showNewTaskPopover = false
        selectedTaskID = nil
        let range = normalizedDraftRange(startMin: startMin, endMin: endMin)
        draft = .live(start: range.start, end: range.end)
    }

    static func commitDraftSelection(
        startMin: Int,
        endMin: Int,
        draft: inout TimelineDraftSelection?,
        showNewTaskPopover: inout Bool
    ) {
        let range = normalizedDraftRange(startMin: startMin, endMin: endMin)
        draft = .pending(start: range.start, end: range.end)
        showNewTaskPopover = true
    }

    static func resetCanvasSelection(
        selectedTaskID: inout UUID?,
        selectedEventID: inout String?,
        activeDragTaskID: inout UUID?,
        selectedBundleID: inout UUID?,
        activeDragBundleID: inout UUID?,
        draft: inout TimelineDraftSelection?,
        showNewTaskPopover: inout Bool
    ) {
        clearDraftCreation(
            draft: &draft,
            showNewTaskPopover: &showNewTaskPopover,
            selectedEventID: &selectedEventID
        )
        selectedTaskID = nil
        activeDragTaskID = nil
        selectedBundleID = nil
        activeDragBundleID = nil
    }
}
#endif

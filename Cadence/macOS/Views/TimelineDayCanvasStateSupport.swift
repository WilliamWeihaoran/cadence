#if os(macOS)
import SwiftUI

enum TimelineDayCanvasStateSupport {
    static func clearDraftCreation(
        dragStartMin: inout Int?,
        dragEndMin: inout Int?,
        pendingStartMin: inout Int?,
        pendingEndMin: inout Int?,
        showNewTaskPopover: inout Bool,
        selectedEventID: inout String?
    ) {
        dragStartMin = nil
        dragEndMin = nil
        pendingStartMin = nil
        pendingEndMin = nil
        showNewTaskPopover = false
        selectedEventID = nil
    }

    static func beginDraftSelection(
        startMin: Int,
        endMin: Int,
        dragStartMin: inout Int?,
        dragEndMin: inout Int?,
        pendingStartMin: inout Int?,
        pendingEndMin: inout Int?,
        showNewTaskPopover: inout Bool,
        selectedTaskID: inout UUID?
    ) {
        showNewTaskPopover = false
        pendingStartMin = nil
        pendingEndMin = nil
        selectedTaskID = nil
        // `startMin` is always the gesture's fixed anchor point and `endMin` tracks the
        // live drag location, so it moves both later (normal drag) and earlier (upward
        // drag) than the anchor. Swap via min/max instead of clamping endMin against a
        // frozen dragStartMin, otherwise dragging upward collapses the selection to a
        // fixed 5-minute block anchored at the mouse-down point instead of extending
        // the block upward toward the current pointer position.
        let lower = min(startMin, endMin)
        let upper = max(startMin, endMin)
        dragStartMin = lower
        dragEndMin = max(upper, lower + 5)
    }

    static func commitDraftSelection(
        startMin: Int,
        endMin: Int,
        dragStartMin: inout Int?,
        dragEndMin: inout Int?,
        pendingStartMin: inout Int?,
        pendingEndMin: inout Int?,
        showNewTaskPopover: inout Bool
    ) {
        // Same swap as `beginDraftSelection`: `startMin`/`endMin` reflect the raw
        // gesture anchor/current-location minutes, which are reversed when the user
        // drags upward. Always resolve to (min, max) rather than trusting `startMin`
        // as the block start.
        let lower = min(startMin, endMin)
        let upper = max(startMin, endMin)
        let actualStart = lower
        let actualEnd = max(upper, actualStart + 5)
        pendingStartMin = actualStart
        pendingEndMin = actualEnd
        showNewTaskPopover = true
        dragStartMin = nil
        dragEndMin = nil
    }

    static func resetCanvasSelection(
        selectedTaskID: inout UUID?,
        selectedEventID: inout String?,
        activeDragTaskID: inout UUID?,
        selectedBundleID: inout UUID?,
        activeDragBundleID: inout UUID?,
        dragStartMin: inout Int?,
        dragEndMin: inout Int?,
        pendingStartMin: inout Int?,
        pendingEndMin: inout Int?,
        showNewTaskPopover: inout Bool
    ) {
        clearDraftCreation(
            dragStartMin: &dragStartMin,
            dragEndMin: &dragEndMin,
            pendingStartMin: &pendingStartMin,
            pendingEndMin: &pendingEndMin,
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

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
        if dragStartMin == nil {
            dragStartMin = startMin
        }
        dragEndMin = max(endMin, (dragStartMin ?? 0) + 5)
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
        let actualStart = dragStartMin ?? startMin
        let actualEnd = max(endMin, actualStart + 5)
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
    }
}
#endif

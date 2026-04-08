#if os(macOS)
import SwiftUI

enum TimelineTaskBlockStateSupport {
    static func handleTap(
        taskID: UUID,
        selectedTaskID: Binding<UUID?>,
        activeDragTaskID: Binding<UUID?>,
        onSelect: () -> Void
    ) {
        onSelect()
        activeDragTaskID.wrappedValue = nil
        selectedTaskID.wrappedValue = taskID
    }

    static func selectionBinding(taskID: UUID, selectedTaskID: Binding<UUID?>) -> Binding<Bool> {
        Binding(
            get: { selectedTaskID.wrappedValue == taskID },
            set: { isPresented in
                if isPresented {
                    selectedTaskID.wrappedValue = taskID
                } else if selectedTaskID.wrappedValue == taskID {
                    selectedTaskID.wrappedValue = nil
                }
            }
        )
    }

    static func endResize(
        activeResizeEdge: inout TimelineTaskBlock.ResizeEdge?,
        resizeOriginStartMin: inout Int?,
        resizeOriginEndMin: inout Int?
    ) {
        activeResizeEdge = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin = nil
    }
}
#endif

#if os(macOS)
import SwiftUI

struct KanbanPriorityMetaButton: View {
    let item: KanbanMetaItem
    @Binding var priority: TaskPriority
    @Binding var isPresented: Bool
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            KanbanMetaChip(item: item)
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $isPresented) {
            KanbanPriorityPickerPopover(priority: $priority, isPresented: $isPresented)
        }
    }
}

struct KanbanDateMetaButton<PopoverContent: View>: View {
    let item: KanbanMetaItem
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onHoverChanged: (Bool) -> Void
    @ViewBuilder let popoverContent: () -> PopoverContent

    var body: some View {
        Button {
            onOpen()
        } label: {
            KanbanMetaChip(item: item)
        }
        .buttonStyle(.cadencePlain)
        .onHover(perform: onHoverChanged)
        .popover(isPresented: $isPresented, content: popoverContent)
    }
}
#endif

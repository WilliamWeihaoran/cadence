#if os(macOS)
import SwiftUI

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
            KanbanMetaChip(item: item, isFocused: isPresented, onHoverChanged: onHoverChanged)
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $isPresented, content: popoverContent)
    }
}
#endif

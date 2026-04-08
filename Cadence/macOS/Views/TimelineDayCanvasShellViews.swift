#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct TimelineCanvasDropSurface: View {
    let width: CGFloat
    let totalHeight: CGFloat
    let isDropTargeted: Bool
    let hasPreviewTask: Bool
    let dropDelegate: TimelineDropDelegate
    let onTap: () -> Void

    var body: some View {
        Color.clear
            .background(isDropTargeted && !hasPreviewTask ? Theme.blue.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .frame(width: width, height: totalHeight)
            .onTapGesture(perform: onTap)
            .onDrop(of: [UTType.text.identifier], delegate: dropDelegate)
    }
}

struct TimelineDraftGhostLayer: View {
    let startMinute: Int
    let endMinute: Int
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle

    var body: some View {
        let y = metrics.yOffset(for: startMinute)
        let height = metrics.height(for: endMinute - startMinute, minHeight: style.minHeight)
        let ghostWidth = max(0, width - style.leadingInset - style.trailingInset)

        RoundedRectangle(cornerRadius: style.cornerRadius)
            .fill(Theme.blue.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(Theme.blue.opacity(0.55), lineWidth: 1)
            )
            .frame(width: ghostWidth, height: height)
            .offset(x: style.leadingInset, y: y)
            .allowsHitTesting(false)
    }
}

struct TimelineDraftPopoverAnchor<PopoverContent: View>: View {
    let startMinute: Int
    let endMinute: Int
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var isPresented: Bool
    let onDismissed: () -> Void
    @ViewBuilder let content: () -> PopoverContent

    var body: some View {
        let y = metrics.yOffset(for: startMinute)
        let height = metrics.height(for: endMinute - startMinute, minHeight: style.minHeight)
        let ghostWidth = max(0, width - style.leadingInset - style.trailingInset)

        Color.clear
            .frame(width: ghostWidth, height: height)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                content()
            }
            .onChange(of: isPresented) { _, value in
                if !value { onDismissed() }
            }
            .padding(.top, y)
            .padding(.leading, style.leadingInset)
    }
}
#endif

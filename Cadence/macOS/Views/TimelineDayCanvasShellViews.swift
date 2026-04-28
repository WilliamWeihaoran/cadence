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

    private var durationMinutes: Int {
        max(5, endMinute - startMinute)
    }

    private var durationLabel: String {
        if durationMinutes < 60 { return "\(durationMinutes)m" }
        if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
        return String(format: "%.1fh", Double(durationMinutes) / 60.0)
    }

    var body: some View {
        let y = metrics.yOffset(for: startMinute)
        let height = metrics.height(for: durationMinutes, minHeight: style.minHeight)
        let ghostWidth = max(0, width - style.leadingInset - style.trailingInset)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Theme.blue.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .stroke(Theme.blue.opacity(0.55), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Text(TimeFormatters.timeRange(startMin: startMinute, endMin: endMinute))
                Text(durationLabel)
                    .foregroundStyle(Theme.blue.opacity(0.95))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.blue.opacity(0.28), lineWidth: 1)
            )
            .padding(.top, 6)
            .padding(.leading, 6)
        }
        .frame(width: ghostWidth, height: height, alignment: .topLeading)
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

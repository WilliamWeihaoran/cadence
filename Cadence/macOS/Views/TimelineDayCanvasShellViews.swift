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
            .suppressWindowBackgroundDrag()
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
        CadenceTaskPresentationSupport.estimateLabel(minutes: durationMinutes)
    }

    var body: some View {
        let frame = TimelineMetricsSupport.computeDraftFrame(
            startMinute: startMinute,
            endMinute: endMinute,
            totalWidth: width,
            metrics: metrics,
            style: style
        )

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Theme.blue.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .strokeBorder(Theme.blue.opacity(0.55), lineWidth: 1)
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
            .background(Theme.surfaceElevated)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.blue.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: Theme.chipShadow, radius: 4, x: 0, y: 2)
            .padding(.top, 6)
            .padding(.leading, 6)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .position(x: frame.centerX, y: frame.centerY)
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
        // Same rect as `TimelineDraftGhostLayer`, from the same function and placed by the same
        // mechanism. These two used to be positioned differently — `.offset` for the ghost,
        // `.padding` for the anchor — and coincided only because `.padding` on a `Color.clear`
        // inside a `.topLeading` ZStack happened to land where `.offset` did. Any alignment or
        // container change would have pointed the popover arrow at empty canvas.
        let frame = TimelineMetricsSupport.computeDraftFrame(
            startMinute: startMinute,
            endMinute: endMinute,
            totalWidth: width,
            metrics: metrics,
            style: style
        )

        Color.clear
            .frame(width: frame.width, height: frame.height)
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
            .position(x: frame.centerX, y: frame.centerY)
    }
}
#endif

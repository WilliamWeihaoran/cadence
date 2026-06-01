#if os(macOS)
import AppKit
import SwiftUI

struct macOSRootMainShell<Content: View>: View {
    let columnVisibility: NavigationSplitViewVisibility
    @Binding var selection: SidebarItem?
    let showTimelineSidebar: Bool
    let timelineSidebarOverlay: AnyView
    @ViewBuilder let detailContent: () -> Content
    @AppStorage("mainSidebarWidth") private var storedSidebarWidth = 264.0
    @State private var sidebarWidth = 264.0
    @State private var isSidebarResizing = false

    private let minSidebarWidth = 220.0
    private let maxSidebarWidth = 390.0

    var body: some View {
        HStack(spacing: 0) {
            if columnVisibility != .detailOnly {
                SidebarView(selection: $selection)
                    .frame(width: CGFloat(clampedSidebarWidth))
                    .contentShape(Rectangle())
                    .background(
                        LinearGradient(
                            colors: [Theme.surface.opacity(0.98), Theme.surfaceElevated.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.85))
                            .frame(width: 1)
                    }
                    .overlay(alignment: .trailing) {
                        SidebarResizeHandle(
                            width: $sidebarWidth,
                            isResizing: $isSidebarResizing,
                            minWidth: minSidebarWidth,
                            maxWidth: maxSidebarWidth,
                            onResizeEnded: persistSidebarWidth
                        )
                        .frame(width: 10)
                        .offset(x: 5)
                    }
                    .zIndex(10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ZStack(alignment: .trailing) {
                detailContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)

                if showTimelineSidebar {
                    timelineSidebarOverlay
                }
            }
            .clipped()
            .zIndex(0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            sidebarWidth = clampedWidth(storedSidebarWidth)
            storedSidebarWidth = sidebarWidth
        }
        .onChange(of: storedSidebarWidth) { _, newValue in
            guard !isSidebarResizing else { return }
            sidebarWidth = clampedWidth(newValue)
        }
    }

    private var clampedSidebarWidth: Double {
        clampedWidth(sidebarWidth)
    }

    private func clampedWidth(_ value: Double) -> Double {
        min(max(value, minSidebarWidth), maxSidebarWidth)
    }

    private func persistSidebarWidth() {
        sidebarWidth = clampedWidth(sidebarWidth)
        storedSidebarWidth = sidebarWidth
    }
}

private struct SidebarResizeHandle: NSViewRepresentable {
    typealias NSViewType = SidebarResizeHandleView

    @Binding var width: Double
    @Binding var isResizing: Bool
    let minWidth: Double
    let maxWidth: Double
    let onResizeEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            width: $width,
            isResizing: $isResizing,
            minWidth: minWidth,
            maxWidth: maxWidth,
            onResizeEnded: onResizeEnded
        )
    }

    func makeNSView(context: NSViewRepresentableContext<SidebarResizeHandle>) -> SidebarResizeHandleView {
        SidebarResizeHandleView(coordinator: context.coordinator)
    }

    func updateNSView(
        _ nsView: SidebarResizeHandleView,
        context: NSViewRepresentableContext<SidebarResizeHandle>
    ) {
        context.coordinator.width = $width
        context.coordinator.isResizing = $isResizing
        context.coordinator.minWidth = minWidth
        context.coordinator.maxWidth = maxWidth
        context.coordinator.onResizeEnded = onResizeEnded
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var width: Binding<Double>
        var isResizing: Binding<Bool>
        var minWidth: Double
        var maxWidth: Double
        var onResizeEnded: () -> Void
        private var dragStartScreenX: CGFloat?
        private var dragStartWidth: Double?

        init(
            width: Binding<Double>,
            isResizing: Binding<Bool>,
            minWidth: Double,
            maxWidth: Double,
            onResizeEnded: @escaping () -> Void
        ) {
            self.width = width
            self.isResizing = isResizing
            self.minWidth = minWidth
            self.maxWidth = maxWidth
            self.onResizeEnded = onResizeEnded
        }

        func beginDrag(screenX: CGFloat) {
            dragStartScreenX = screenX
            dragStartWidth = width.wrappedValue
            isResizing.wrappedValue = true
        }

        func updateDrag(screenX: CGFloat) {
            guard let dragStartScreenX, let dragStartWidth else { return }
            let delta = Double(screenX - dragStartScreenX)
            width.wrappedValue = clamped(dragStartWidth + delta)
        }

        func endDrag() {
            width.wrappedValue = clamped(width.wrappedValue)
            dragStartScreenX = nil
            dragStartWidth = nil
            isResizing.wrappedValue = false
            onResizeEnded()
        }

        private func clamped(_ value: Double) -> Double {
            min(max(value, minWidth), maxWidth)
        }
    }
}

private final class SidebarResizeHandleView: NSView {
    var coordinator: SidebarResizeHandle.Coordinator
    private var isHovered = false
    private var isDragging = false

    init(coordinator: SidebarResizeHandle.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        wantsLayer = true
        updateHandleAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHandleAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHandleAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isDragging = true
        NSCursor.resizeLeftRight.set()
        coordinator.beginDrag(screenX: NSEvent.mouseLocation.x)
        updateHandleAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        coordinator.updateDrag(screenX: NSEvent.mouseLocation.x)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        coordinator.endDrag()
        updateHandleAppearance()
    }

    private func updateHandleAppearance() {
        let alpha = isDragging ? 0.26 : (isHovered ? 0.18 : 0)
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }
}

struct macOSRootOverlayStack: View {
    let handleSearchSelection: (GlobalSearchResult) -> Void

    var body: some View {
        TaskCreationLayerView()
        SuccessToastLayerView()
        DeleteConfirmationLayerView()
        DatePickerLayerView()
        GlobalSearchLayerView(onSelect: handleSearchSelection)
    }
}
#endif

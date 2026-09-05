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
                    .background(Theme.surface)
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
        .preferredColorScheme(Theme.preferredColorScheme)
        .overlay(alignment: .top) {
            WindowTopDragRegion()
                .frame(height: 10)
                .frame(maxWidth: .infinity)
        }
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

        /// T-1037. Arrow-key resizing and the `NSAccessibility` increment/decrement actions both
        /// go through this rather than `beginDrag`/`updateDrag`/`endDrag`: there is no pointer
        /// location to anchor a delta to, only "make it `delta` wider or narrower right now."
        func adjustWidth(by delta: Double) {
            width.wrappedValue = clamped(width.wrappedValue + delta)
            onResizeEnded()
        }

        private func clamped(_ value: Double) -> Double {
            min(max(value, minWidth), maxWidth)
        }
    }
}

/// T-1036 / T-1037. The handle's accent tint used to be computed inline on the private
/// `SidebarResizeHandleView` as `isDragging ? 0.26 : (isHovered ? 0.18 : 0)` — no seam a test could
/// reach. Pulled out so all four states, including T-1037's keyboard-focus indicator, are one
/// place, assertable with no `NSView`/`NSScreen` involved at all.
nonisolated enum SidebarResizeHandleAppearance: Equatable {
    case rest
    case focused
    case hovered
    case dragging

    /// Alpha applied to `NSColor.controlAccentColor` over `Theme.surface`.
    var accentAlpha: Double {
        switch self {
        case .rest: return 0
        case .focused: return 0.12
        case .hovered: return 0.18
        case .dragging: return 0.26
        }
    }

    /// Drag always wins over hover, matching the pre-existing behavior — `mouseDown` also makes
    /// the view first responder, so without this order a drag would show the dimmer focus tint
    /// instead of its own. Focus is the new, lowest-priority state: it only shows once neither a
    /// drag nor a hover is already saying something.
    static func resolve(isDragging: Bool, isHovered: Bool, isFocused: Bool) -> Self {
        if isDragging { return .dragging }
        if isHovered { return .hovered }
        if isFocused { return .focused }
        return .rest
    }
}

private final class SidebarResizeHandleView: NSView {
    var coordinator: SidebarResizeHandle.Coordinator
    private var isHovered = false
    private var isDragging = false
    private var isFocused = false

    /// T-1037. Points per arrow-key press / accessibility increment-decrement action.
    private static let arrowKeyStepWidth: Double = 8

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // T-1036 (second half). Re-subscribed on every window change rather than once in `init`,
        // because an `NSViewRepresentable`'s view can move between windows across its lifetime and
        // a stale observer on the old window would never fire again.
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
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
        // T-1036. This runs on every geometry change — continuously during a resize drag, since
        // the handle's clamped frame stops moving while the pointer keeps going — and AppKit does
        // not send `mouseExited` for a tracking area that is mid teardown-and-rebuild. Polling the
        // pointer directly is what actually clears a latched hover; `mouseEntered`/`mouseExited`
        // below are only the fast path for the ordinary case where nothing is rebuilding the area.
        refreshHoverFromCurrentMouseLocation()
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

    /// T-1036 (second half). A drag that is in progress when the window resigns key (Cmd-Tab away,
    /// a sheet raised elsewhere) never gets a `mouseUp` — without this, `isDragging` stays `true`
    /// forever, which is the same latch the tracking-area fix addresses for hover.
    @objc private func handleWindowDidResignKey() {
        guard isDragging else { return }
        isDragging = false
        coordinator.endDrag()
        updateHandleAppearance()
    }

    private func refreshHoverFromCurrentMouseLocation() {
        guard let window else { return }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let localPoint = convert(windowPoint, from: nil)
        let hovered = bounds.contains(localPoint)
        guard hovered != isHovered else { return }
        isHovered = hovered
        updateHandleAppearance()
    }

    // MARK: - T-1037: keyboard focus, resizing, accessibility

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            isFocused = true
            updateHandleAppearance()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isFocused = false
            updateHandleAppearance()
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .some(.leftArrow):
            coordinator.adjustWidth(by: -Self.arrowKeyStepWidth)
        case .some(.rightArrow):
            coordinator.adjustWidth(by: Self.arrowKeyStepWidth)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .slider }

    override func accessibilityLabel() -> String? { "Sidebar width" }

    override func accessibilityValue() -> Any? { Int(coordinator.width.wrappedValue.rounded()) }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityPerformIncrement() -> Bool {
        coordinator.adjustWidth(by: Self.arrowKeyStepWidth)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        coordinator.adjustWidth(by: -Self.arrowKeyStepWidth)
        return true
    }

    private func updateHandleAppearance() {
        let appearance = SidebarResizeHandleAppearance.resolve(
            isDragging: isDragging,
            isHovered: isHovered,
            isFocused: isFocused
        )
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(appearance.accentAlpha).cgColor
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

extension View {
    func suppressWindowBackgroundDrag() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in }
                .onEnded { _ in }
        )
    }
}
#endif

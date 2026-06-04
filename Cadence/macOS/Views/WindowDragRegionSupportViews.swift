#if os(macOS)
import AppKit
import SwiftUI

struct WindowTopDragRegion: NSViewRepresentable {
    typealias NSViewType = WindowTopDragRegionView

    func makeNSView(context: NSViewRepresentableContext<WindowTopDragRegion>) -> WindowTopDragRegionView {
        WindowTopDragRegionView()
    }

    func updateNSView(
        _ nsView: WindowTopDragRegionView,
        context: NSViewRepresentableContext<WindowTopDragRegion>
    ) {}
}

final class WindowTopDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
#endif

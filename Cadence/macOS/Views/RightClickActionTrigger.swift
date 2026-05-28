#if os(macOS)
import SwiftUI
import AppKit

struct RightClickActionTrigger: NSViewRepresentable {
    typealias NSViewType = RightClickActionView

    let action: () -> Void

    func makeNSView(context: NSViewRepresentableContext<RightClickActionTrigger>) -> RightClickActionView {
        let view = RightClickActionView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickActionView, context: NSViewRepresentableContext<RightClickActionTrigger>) {
        nsView.action = action
    }

    final class RightClickActionView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
            return event.type == .rightMouseDown ? self : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action()
        }
    }
}
#endif

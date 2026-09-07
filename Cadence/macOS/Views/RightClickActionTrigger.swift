#if os(macOS)
import SwiftUI
import AppKit

/// A transparent overlay that turns a right-click anywhere over it into one action.
///
/// **T-1096 — it used to accept a right-click that landed somewhere else.** `hitTest(_:)` took a
/// point and never looked at it: any `.rightMouseDown` in the window got this view back, so the
/// first of these AppKit views AppKit asked was the one that answered, whatever the pointer was
/// over. That is the whole of the spatial contract for `hitTest(_:)` discarded — the argument is
/// the *only* thing that says "this click is mine". These overlays sit on macOS task rows, timeline
/// blocks, calendar month tasks, Kanban cards and sidebar lists, so the neighbour whose event this
/// could take is another row of the same list.
///
/// The event filter is still needed and still first-class: a *primary* click has to pass straight
/// through to the SwiftUI button underneath, which is why an unconditional `super.hitTest` alone
/// would be wrong. The rule is now both halves — the point must land on this view **and** the
/// current event must be a right-click.
///
/// `super.hitTest(point)` is what does the spatial half, deliberately: AppKit hands `hitTest(_:)` a
/// point in the **superview's** coordinate system, so `bounds.contains(point)` would be testing the
/// right point against the wrong rectangle. The superclass also folds in `isHidden` and a zero-size
/// frame for free. <https://developer.apple.com/documentation/AppKit/NSView/hitTest(_:)>
///
/// Sidebar list rows used to carry a byte-identical private copy of this type
/// (`SidebarRightClickEditTrigger`, with its own `RightClickEditView`) and therefore a byte-identical
/// copy of the defect. It is gone; that call site uses this one.
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
            hitTest(point, currentEvent: window?.currentEvent ?? NSApp.currentEvent)
        }

        /// The rule, with the event handed in.
        ///
        /// The ambient read above is untestable — neither `NSWindow.currentEvent` nor
        /// `NSApp.currentEvent` is settable, so a test host reads `nil` from both and every branch
        /// below collapses to "no". Taking the event as an argument is what lets
        /// `CadenceRightClickTriggerHitTestTests` put a real `.rightMouseDown` next to a real frame
        /// and ask where the boundary is.
        func hitTest(_ point: NSPoint, currentEvent: NSEvent?) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            guard let currentEvent else { return nil }
            return currentEvent.type == .rightMouseDown ? hit : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action()
        }
    }
}
#endif

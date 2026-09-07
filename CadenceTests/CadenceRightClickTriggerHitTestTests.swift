import Testing
import AppKit
import Foundation
@testable import Cadence

#if os(macOS)
/// **T-1096.** `RightClickActionTrigger.RightClickActionView.hitTest(_:)` used to be this:
///
/// ```swift
/// override func hitTest(_ point: NSPoint) -> NSView? {
///     guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
///     return event.type == .rightMouseDown ? self : nil
/// }
/// ```
///
/// `point` is named and never read. `hitTest(_:)` is the one method whose entire job is to answer
/// *"is this point mine"*, and this answered *"is the current event a right-click"* — a question
/// with the same answer for every view in the window. These overlays sit on macOS task rows,
/// timeline blocks, calendar month tasks, Kanban cards and sidebar list rows, so the sibling that
/// could be answered for is another row of the same list.
///
/// The audit that found it (`docs/audits/2026-09-05/appkit-behavior.md`, AK-1) marked it *inferred*:
/// it measured the source and did not reproduce a wrong-row click, because whether AppKit ever asks
/// the wrong one of these depends on the SwiftUI hosting and clipping hierarchy around it. These
/// tests do not settle that either. What they do settle is the half that is a framework contract
/// rather than a hierarchy question: a point outside the view is now refused, and a primary click
/// inside it still passes through to the button underneath.
///
/// **Why the event is an argument.** Neither `NSWindow.currentEvent` nor `NSApp.currentEvent` is
/// settable, so in a test host both read `nil` and every branch collapses to "no" — the shipped
/// `hitTest(_:)` override is untestable as written. `hitTest(_:currentEvent:)` is the seam; the
/// override is one line that reads the ambient event and calls it.
///
/// **`@MainActor`, and not decoration.** Every line below touches AppKit — `NSView(frame:)`,
/// `addSubview`, `setHidden:`, `setFrame:`, `hitTest:` — and Swift Testing runs an unannotated
/// `@Test` on a cooperative background thread. Without this the suite still passes, and prints five
/// Main Thread Checker backtraces into the run log on the way: real UI-API-off-the-main-thread
/// violations, and a warning baseline of zero does not have room for them. Same annotation, same
/// reason, as `MarkdownEditorImageRelayoutTests` and `MarkdownImagePasteTests`.
@MainActor
struct CadenceRightClickTriggerHitTestTests {

    /// A 200×100 parent with the trigger inset inside it, so `point` is in a coordinate system
    /// that is genuinely not the view's own. A nil superview would make `convert(_:from:)` fall
    /// back to the window base and quietly turn the interesting cases into the boring one.
    private func makeTrigger() -> (parent: NSView, view: RightClickActionTrigger.RightClickActionView) {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let view = RightClickActionTrigger.RightClickActionView(frame: NSRect(x: 20, y: 40, width: 160, height: 30))
        parent.addSubview(view)
        return (parent, view)
    }

    private func mouseEvent(_ type: NSEvent.EventType) -> NSEvent {
        let event = NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        // `mouseEvent(with:...)` is documented to return nil only for a non-mouse event type, and
        // both types below are mouse types. Failing loudly beats a suite of vacuous nil-vs-nil
        // expectations if AppKit ever disagrees.
        return try! #require(event)
    }

    // MARK: - The half that was missing

    @Test func aRightClickInsideTheViewIsClaimed() {
        let (_, view) = makeTrigger()
        #expect(view.hitTest(NSPoint(x: 100, y: 55), currentEvent: mouseEvent(.rightMouseDown)) === view)
    }

    @Test func aRightClickBelowTheViewIsRefused() {
        let (_, view) = makeTrigger()
        // y = 10 is in the parent, 30pt under the trigger's frame. The old rule claimed it.
        #expect(view.hitTest(NSPoint(x: 100, y: 10), currentEvent: mouseEvent(.rightMouseDown)) == nil)
    }

    @Test func aRightClickAboveTheViewIsRefused() {
        let (_, view) = makeTrigger()
        #expect(view.hitTest(NSPoint(x: 100, y: 90), currentEvent: mouseEvent(.rightMouseDown)) == nil)
    }

    @Test func aRightClickBesideTheViewIsRefused() {
        let (_, view) = makeTrigger()
        // x = 5 is inside the parent's width and outside the trigger's 20pt leading inset.
        #expect(view.hitTest(NSPoint(x: 5, y: 55), currentEvent: mouseEvent(.rightMouseDown)) == nil)
    }

    @Test func aHiddenViewClaimsNothing() {
        let (_, view) = makeTrigger()
        view.isHidden = true
        #expect(view.hitTest(NSPoint(x: 100, y: 55), currentEvent: mouseEvent(.rightMouseDown)) == nil)
    }

    @Test func aZeroSizeViewClaimsNothing() {
        let (_, view) = makeTrigger()
        view.frame = NSRect(x: 100, y: 55, width: 0, height: 0)
        #expect(view.hitTest(NSPoint(x: 100, y: 55), currentEvent: mouseEvent(.rightMouseDown)) == nil)
    }

    // MARK: - The half that was already right, and has to stay right

    @Test func aPrimaryClickInsideTheViewPassesThrough() {
        let (_, view) = makeTrigger()
        // The overlay sits on top of a SwiftUI button. Claiming a left click here would eat the
        // row's own tap, so `super.hitTest` alone would not have been the fix.
        #expect(view.hitTest(NSPoint(x: 100, y: 55), currentEvent: mouseEvent(.leftMouseDown)) == nil)
    }

    @Test func noCurrentEventClaimsNothing() {
        let (_, view) = makeTrigger()
        #expect(view.hitTest(NSPoint(x: 100, y: 55), currentEvent: nil) == nil)
    }

    // MARK: - The duplicate that carried the same defect

    @Test func theSidebarNoLongerCarriesItsOwnCopyOfThisView() throws {
        // `SidebarSupportViews.swift` held a private `SidebarRightClickEditTrigger` /
        // `RightClickEditView` pair that was byte-identical to this one, including the defect
        // above. Fixing one copy and leaving the other is how this comes back.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Cadence/macOS/Views/SidebarSupportViews.swift"),
            encoding: .utf8
        )
        #expect(!source.contains("SidebarRightClickEditTrigger"))
        #expect(!source.contains("RightClickEditView"))
        #expect(source.contains("RightClickActionTrigger(action: onEdit)"))
    }
}
#endif

import Foundation
import Testing
#if os(macOS)
import AppKit
import SwiftUI
#endif

@testable import Cadence

#if os(macOS)
/// Cmd+Z in the Mac note editor ([[T-17181]], [[T-17182]]).
///
/// Both run the real `CadenceTextView` and `MarkdownEditorCoordinator`. A headless test has no run
/// loop, so `groupsByEvent` is off and each user step is grouped by hand — the shape the app's
/// event loop gives a keystroke.
@MainActor
struct MarkdownEditorUndoHistoryTests {
    private static func makeTextView(_ text: String) -> CadenceTextView {
        let view = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.isEditable = true
        view.isRichText = true
        view.allowsUndo = true
        view.string = text
        return view
    }

    private static func type(_ text: String, atEndOf view: CadenceTextView, in manager: UndoManager) {
        let end = (view.string as NSString).length
        manager.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.insertText(text, replacementRange: NSRange(location: end, length: 0))
        manager.endUndoGrouping()
    }

    // MARK: - T-17181: a body rewritten from outside the view

    /// The defect: the user types, then links an unlinked mention (or applies a template, or an
    /// external write lands), and the host hands the editor a rewritten body. The first Cmd+Z
    /// must take the rewrite back and the second the typing — not replay the typing record at
    /// offsets the rewrite shifted, which gave `"[[Sam]] Call Soday now"`.
    @Test func undoAfterAnExternalRewriteTakesTheRewriteBackThenTheTyping() {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("Call Sam today")
        view.delegate = coordinator
        let manager = coordinator.undoManager
        manager.groupsByEvent = false

        Self.type(" now", atEndOf: view, in: manager)
        #expect(view.string == "Call Sam today now")

        manager.beginUndoGrouping()
        coordinator.applyExternalText("[[Sam]] Call Sam today now", to: view)
        manager.endUndoGrouping()
        #expect(view.string == "[[Sam]] Call Sam today now")

        manager.undo()
        #expect(view.string == "Call Sam today now")
        manager.undo()
        #expect(view.string == "Call Sam today")

        manager.redo()
        manager.redo()
        #expect(view.string == "[[Sam]] Call Sam today now")
    }

    /// The other half of the rule: every host opens its editor on `""` and fills it from the note
    /// on appear. That load is not an edit, so Cmd+Z straight after opening a note must not blank
    /// it.
    @Test func theLoadIntoAnEmptyEditorIsNotAnUndoableStep() {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("")
        view.delegate = coordinator
        // Left grouping by event, the app's own setting: any registration opens a group that
        // `undo()` closes, so a load that wrongly registered would be undone below. An explicit
        // empty group would make `canUndo` read true and hide that.

        coordinator.applyExternalText("# Groceries\n\nMilk", to: view)

        #expect(view.string == "# Groceries\n\nMilk")
        #expect(coordinator.undoManager.canUndo == false)
        if coordinator.undoManager.canUndo { coordinator.undoManager.undo() }
        #expect(view.string == "# Groceries\n\nMilk")
    }

    // MARK: - T-17182: one history per editor

    /// The defect: the editor is rebuilt per note, but its text view used the window's undo
    /// manager, so the note just left stayed on the stack. Opening another note showed
    /// "Undo Typing" and Cmd+Z there reverted the detached view instead of anything on screen.
    @Test func anotherNotesEditorStartsWithNoUndoHistory() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        window.contentView = container

        let first = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let noteA = Self.makeTextView("Note A")
        noteA.delegate = first
        container.addSubview(noteA)
        window.makeFirstResponder(noteA)
        let managerA = try #require(noteA.undoManager)
        managerA.groupsByEvent = false
        Self.type(" typed", atEndOf: noteA, in: managerA)
        #expect(managerA.canUndo)

        noteA.removeFromSuperview()
        let second = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let noteB = Self.makeTextView("Note B")
        noteB.delegate = second
        container.addSubview(noteB)
        window.makeFirstResponder(noteB)

        #expect(noteB.undoManager?.canUndo == false)
        _ = noteB.tryToPerform(Selector(("undo:")), with: nil)
        #expect(noteA.string == "Note A typed")
        #expect(noteB.string == "Note B")
    }

    /// And within one note Cmd+Z still reaches the editor's history through the responder chain,
    /// the route the Edit menu takes.
    @Test func undoThroughTheResponderChainReachesTheEditorsOwnHistory() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("Note")
        view.delegate = coordinator
        window.contentView = view
        window.makeFirstResponder(view)
        coordinator.undoManager.groupsByEvent = false

        Self.type(" typed", atEndOf: view, in: coordinator.undoManager)
        #expect(view.undoManager === coordinator.undoManager)

        _ = view.tryToPerform(Selector(("undo:")), with: nil)
        #expect(view.string == "Note")
    }
}
#endif

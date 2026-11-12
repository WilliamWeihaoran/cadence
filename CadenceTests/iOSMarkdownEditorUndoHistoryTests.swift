import Foundation
import Testing
#if os(iOS)
import SwiftUI
import UIKit
#endif

@testable import Cadence

#if os(iOS)
/// Undo in the iOS note editor after a body rewritten from outside the typing ([[T-17184]], the
/// twin of the Mac's [[T-17181]]).
///
/// Runs the real `iOSMarkdownTextView` and `iOSMarkdownEditor.Coordinator` in a key window on the
/// iOS test host, with the main run loop turned between steps so UIKit closes each event's undo
/// group and the editor's own debounced restyle lands, as it does in the app.
///
/// Measured before the fix on `Cadence-iPhone15`: with the run loop turned, the first undo after
/// a host rewrite left the text unchanged and the second found nothing — the rewrite could not be
/// taken back and the typing before it was gone. With the rewrite landing in the keystroke's own
/// turn, as the typing transforms do, the typing record replayed at shifted offsets instead:
/// `"Call Sam today"`, type `" now"`, prepend `[[Sam]] `, undo gave `"[[Sam]] Call Soday now"`.
@Suite @MainActor
struct iOSMarkdownEditorUndoHistoryTests {
    private struct Hosted {
        let window: UIWindow
        let view: iOSMarkdownTextView
        let coordinator: iOSMarkdownEditor.Coordinator
        let manager: UndoManager
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// One app turn: closes the event's undo group and lets the debounced restyle fire.
    private static func turnRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    /// Opens an editor on `text` with no history, the way `makeUIView` does.
    private static func host(_ text: String) throws -> Hosted {
        let editor = iOSMarkdownEditor(text: .constant(""), isFocused: .constant(true))
        let coordinator = editor.makeCoordinator()
        let window = UIWindow(windowScene: try #require(scene))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let view = iOSMarkdownTextView()
        view.frame = window.bounds
        view.delegate = coordinator
        window.addSubview(view)
        window.makeKeyAndVisible()
        _ = view.becomeFirstResponder()
        let manager = try #require(view.undoManager)
        manager.removeAllActions()
        coordinator.applyRewrite(text, to: view)
        turnRunLoop()
        return Hosted(window: window, view: view, coordinator: coordinator, manager: manager)
    }

    private static func type(_ text: String, atEndOf hosted: Hosted) {
        hosted.view.selectedRange = NSRange(location: (hosted.view.text as NSString).length, length: 0)
        hosted.view.insertText(text)
        turnRunLoop()
    }

    private static func undo(_ hosted: Hosted) {
        hosted.manager.undo()
        turnRunLoop()
    }

    private static func redo(_ hosted: Hosted) {
        hosted.manager.redo()
        turnRunLoop()
    }

    /// The defect: the user types, then the host rewrites the draft (a toolbar or slash-strip
    /// command, a reference picker, Link on an unlinked mention) and the text flows down through
    /// `updateUIView`. The first undo must take the rewrite back and the second the typing.
    @Test func undoAfterAHostRewriteTakesTheRewriteBackThenTheTyping() throws {
        let hosted = try Self.host("Call Sam today")
        Self.type(" now", atEndOf: hosted)
        #expect(hosted.view.text == "Call Sam today now")

        hosted.coordinator.applyRewrite("[[Sam]] Call Sam today now", to: hosted.view)
        Self.turnRunLoop()
        #expect(hosted.view.text == "[[Sam]] Call Sam today now")

        Self.undo(hosted)
        #expect(hosted.view.text == "Call Sam today now")
        Self.undo(hosted)
        #expect(hosted.view.text == "Call Sam today")

        Self.redo(hosted)
        Self.redo(hosted)
        #expect(hosted.view.text == "[[Sam]] Call Sam today now")
    }

    /// The coordinator's own rewrites — a hardware-keyboard format command here — take the same
    /// route, so undo after Cmd+B un-bolds and then undoes the typing before it.
    @Test func undoAfterAFormatCommandTakesTheCommandBackThenTheTyping() throws {
        let hosted = try Self.host("Ship it")
        Self.type(" today", atEndOf: hosted)

        hosted.view.selectedRange = NSRange(location: 0, length: 4)
        hosted.coordinator.apply(.bold, to: hosted.view)
        Self.turnRunLoop()
        #expect(hosted.view.text == "**Ship** it today")

        Self.undo(hosted)
        #expect(hosted.view.text == "Ship it today")
        Self.undo(hosted)
        #expect(hosted.view.text == "Ship it")
    }

    // MARK: - [[T-17322]]: a restyle in the keystroke's own turn

    private static let fencedNote = "Intro\n\n```\nlet a = 1\n```\n\nAfter"

    private static func isDrawnAsCanvas(_ location: Int, in view: UITextView) -> Bool {
        view.textStorage.attribute(.cadenceMarkdownBlockCanvas, at: location, effectiveRange: nil) != nil
    }

    /// The measurement [[T-17322]] was filed from, re-run: a restyle straight after a keystroke,
    /// before the run loop turns. `applyMarkdownStyle` replaces the storage with the same string,
    /// and the keystroke's undo survives it.
    @Test func aRestyleInTheKeystrokesTurnKeepsTheKeystrokesUndo() throws {
        let hosted = try Self.host("Call Sam today")
        hosted.view.selectedRange = NSRange(location: 14, length: 0)
        Self.turnRunLoop()

        hosted.view.insertText(" now")
        hosted.coordinator.applyMarkdownStyle(to: hosted.view, text: hosted.view.text)
        Self.turnRunLoop()
        #expect(hosted.manager.canUndo)

        Self.undo(hosted)
        #expect(hosted.view.text == "Call Sam today")
    }

    /// Typing inside a fenced code block the caret has revealed grows the revealed block, so the
    /// selection change the keystroke raises asks for a restyle in the keystroke's own turn. That
    /// restyle must not take the keystroke's undo with it. (Unlike the caret-move test below, this
    /// one cannot observe *when* the restyle ran: removing the selection-change restyle leaves it
    /// green, measured by agent fix1848a's mutation M1.)
    @Test func typingInsideARevealedCodeBlockStaysUndoable() throws {
        let hosted = try Self.host(Self.fencedNote)
        let caret = (Self.fencedNote as NSString).range(of: "let a = 1").upperBound
        hosted.view.selectedRange = NSRange(location: caret, length: 0)
        Self.turnRunLoop()

        let fence = (Self.fencedNote as NSString).range(of: "```").location
        #expect(!Self.isDrawnAsCanvas(fence, in: hosted.view), "the caret inside the fence reveals its source")

        hosted.view.insertText("2")
        Self.turnRunLoop()
        #expect(hosted.view.text == "Intro\n\n```\nlet a = 12\n```\n\nAfter")
        #expect(hosted.manager.canUndo)

        Self.undo(hosted)
        #expect(hosted.view.text == Self.fencedNote)
    }

    /// The caret moving into a fenced block in the same turn as a keystroke — the selection
    /// change restyles to reveal the fence's source at once.
    @Test func aCaretMoveIntoACodeBlockInTheKeystrokesTurnKeepsTheKeystrokesUndo() throws {
        let hosted = try Self.host(Self.fencedNote)
        hosted.view.selectedRange = NSRange(location: (Self.fencedNote as NSString).length, length: 0)
        Self.turnRunLoop()

        let fence = (Self.fencedNote as NSString).range(of: "```").location
        #expect(Self.isDrawnAsCanvas(fence, in: hosted.view), "the fence is drawn while the caret is outside it")

        hosted.view.insertText(" now")
        let caret = (Self.fencedNote as NSString).range(of: "let a").upperBound
        hosted.view.selectedRange = NSRange(location: caret, length: 0)
        // The restyle is in the keystroke's turn: the fence shows its source before the run loop turns.
        #expect(!Self.isDrawnAsCanvas(fence, in: hosted.view), "the caret move did not restyle in the keystroke's turn")
        Self.turnRunLoop()
        #expect(hosted.view.text == Self.fencedNote + " now")
        #expect(hosted.manager.canUndo)

        Self.undo(hosted)
        #expect(hosted.view.text == Self.fencedNote)
    }

    /// The other half of the rule: an editor opens on its note's text, and filling an empty view
    /// with no history is the load, not an edit — undo straight after opening must not blank it.
    @Test func theLoadIntoAnEmptyIOSEditorIsNotAnUndoableStep() throws {
        let hosted = try Self.host("")
        hosted.coordinator.applyRewrite("# Groceries\n\nMilk", to: hosted.view)
        Self.turnRunLoop()

        #expect(hosted.view.text == "# Groceries\n\nMilk")
        #expect(hosted.manager.canUndo == false)
        if hosted.manager.canUndo { Self.undo(hosted) }
        #expect(hosted.view.text == "# Groceries\n\nMilk")
    }
}
#endif

/// [[T-17184]]'s wiring, on both legs: every path that hands the editor a different body goes
/// through the undoable write. The behaviour is pinned above on an iOS destination.
@Suite struct iOSMarkdownEditorRewriteWiringTests {
    @Test func everyRewriteOfTheBodyGoesThroughTheUndoableWrite() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditor.swift")
        )
        let update = try cadenceFunctionBody("func updateUIView(", in: source)
        #expect(update.contains("applyRewrite(text, to: textView)"))
        #expect(!update.contains("applyMarkdownStyle(to: textView, text: text)"))

        for declaration in [
            "func apply(_ command: MarkdownFormatCommand, to textView: UITextView)",
            "func adjustListIndentation(",
            "private func applyTypingTransformIfNeeded(",
        ] {
            let body = try cadenceFunctionBody(declaration, in: source)
            #expect(body.contains("applyRewrite("), "\(declaration) rewrites the body outside the undoable write")
            #expect(!body.contains("applyMarkdownStyle("), "\(declaration) restyles new text wholesale")
        }

        let rewrite = try cadenceFunctionBody("func applyRewrite(", in: source)
        #expect(rewrite.contains("MarkdownProgrammaticEditSupport.minimalEdit("))
        #expect(rewrite.contains("replaceProgrammatically(edit.range, with: edit.replacement, in: textView)"))
    }
}

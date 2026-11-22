import Foundation
import SwiftUI
import Testing
@testable import Cadence

// [[T-19606]]: what a tap on a rendered `[[wiki link]]` in the iOS note editor does, held by what
// it DOES on an iOS destination.
//
// The ticket's hypothesis was that the note's text view is editable, so UIKit never delivers link
// activation and `[[link]]` navigation "may never have existed on iOS". It does exist, and it does
// not depend on UIKit's link activation: `iOSMarkdownEditor.makeUIView` attaches its own tap
// recognizer, whose `handleReferenceTap` hit-tests the reference under the finger and hands it to
// the host's `onOpenReference` -- in every note host, `iOSMarkdownReferenceResolver` and then
// `iOSMarkdownReferenceSheets`, which opens `iOSNoteEditorCover(reachedFrom:)`.
//
// What the sighting tapped were two references that resolve to NO note in the seeded store:
// `Beta Project` is the stock seed's PROJECT (`CadenceUITestSupport`), not a note, and the
// `today-geometry` scenario seeds only today's daily note. A reference to a note that does not
// exist opens nothing, by design and on both platforms ([[T-348]]; the Mac's
// `TaskNoteLinkRouting.note(id:title:in:)` returns nil the same way). The last test pins that.
#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

@Suite @MainActor
struct iOSMarkdownReferenceTapRoutingTests {
    private static let markdown = "See [[Beta Project]] today"

    /// A tap the test places: `handleReferenceTap` reads only `state`, `view` and `location(in:)`.
    private final class ScriptedTap: UITapGestureRecognizer {
        var point: CGPoint = .zero
        override var state: UIGestureRecognizer.State {
            get { .ended }
            set {}
        }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    private final class Opened {
        var targets: [MarkdownReferenceDisplayTarget] = []
    }

    private struct Fixture {
        let window: UIWindow
        let textView: iOSMarkdownTextView
        let coordinator: iOSMarkdownEditor.Coordinator
        let opened: Opened
    }

    /// The editor as the sighting had it: editable, styled, in a key window, and first responder
    /// (the caret was in the note, the reference just typed).
    private static func makeFixture() throws -> Fixture {
        let opened = Opened()
        let editor = iOSMarkdownEditor(
            text: .constant(markdown),
            isFocused: .constant(true),
            onOpenReference: { opened.targets.append($0) }
        )
        let coordinator = iOSMarkdownEditor.Coordinator(parent: editor)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let textView = iOSMarkdownTextView()
        textView.frame = window.bounds
        textView.delegate = coordinator
        window.addSubview(textView)
        window.makeKeyAndVisible()
        textView.text = markdown
        coordinator.applyMarkdownStyle(to: textView, text: markdown)
        _ = textView.becomeFirstResponder()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return Fixture(window: window, textView: textView, coordinator: coordinator, opened: opened)
    }

    /// The centre of the glyph drawn for `markdown`'s character at `location`, in text-view
    /// coordinates.
    private static func point(atCharacter location: Int, in textView: UITextView) -> CGPoint {
        let layoutManager = textView.layoutManager
        layoutManager.ensureLayout(for: textView.textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textView.textContainer)
        return CGPoint(x: rect.midX + textView.textContainerInset.left, y: rect.midY + textView.textContainerInset.top)
    }

    private static func tap(_ point: CGPoint, on fixture: Fixture) {
        let recognizer = ScriptedTap(target: nil, action: nil)
        recognizer.point = point
        fixture.textView.addGestureRecognizer(recognizer)
        defer { fixture.textView.removeGestureRecognizer(recognizer) }
        fixture.coordinator.handleReferenceTap(recognizer)
    }

    @Test func aTapOnAReferenceInTheFocusedEditableEditorAsksTheHostToOpenIt() throws {
        let fixture = try Self.makeFixture()
        defer { fixture.window.isHidden = true }
        #expect(fixture.textView.isEditable && fixture.textView.isFirstResponder, "non-vacuity: the sighting's editable, focused editor")

        let location = (Self.markdown as NSString).range(of: "Beta").location + 1
        Self.tap(Self.point(atCharacter: location, in: fixture.textView), on: fixture)

        #expect(fixture.opened.targets.map(\.title) == ["Beta Project"])
        #expect(fixture.opened.targets.map(\.kind) == [.note])
        #expect(!fixture.textView.isFirstResponder, "opening a reference puts the keyboard away")
    }

    @Test func aTapOnPlainProseBesideAReferenceOpensNothing() throws {
        let fixture = try Self.makeFixture()
        defer { fixture.window.isHidden = true }

        Self.tap(Self.point(atCharacter: 1, in: fixture.textView), on: fixture)

        #expect(fixture.opened.targets.isEmpty)
        #expect(fixture.textView.isFirstResponder)
    }

    /// The host's half, with the sighting's two references: a dated reference opens that day's
    /// note when it exists, and a name that only a project carries opens nothing.
    @Test func theHostOpensANoteThatExistsAndNothingForANameNoNoteCarries() {
        let yesterday = Note(kind: .daily, title: "2026-11-21", dateKey: "2026-11-21")
        let notepad = Note(kind: .permanent, title: "Beta notes")
        let notes = [notepad, yesterday]

        let dated = MarkdownReferenceDisplaySupport.target(forWikiLabel: "2026-11-21")
        #expect(iOSMarkdownReferenceResolver.note(for: dated, in: notes) === yesterday)

        let projectName = MarkdownReferenceDisplaySupport.target(forWikiLabel: "Beta Project")
        #expect(iOSMarkdownReferenceResolver.note(for: projectName, in: notes) == nil)
        #expect(iOSMarkdownReferenceResolver.note(for: dated, in: [notepad]) == nil, "no such day's note: nothing opens")
    }
}
#endif

#if os(macOS)
import AppKit
import Testing
@testable import Cadence

/// T-5882. **The markdown editor's insert-link shortcut is Cmd+Shift+K, and plain Cmd+K is not it.**
///
/// Cmd+K is Search app-wide. `RootCommandEventSupport.handleCommandKeyEvent` consumes key code 40
/// from an app-wide local monitor, which runs before `performKeyEquivalent` reaches the editor's
/// text view, so an editor binding on plain Cmd+K cannot fire however it is written here. The owner
/// kept one meaning for Cmd+K and moved the editor's link shortcut; these two cases are what fails
/// if it moves back.
///
/// The events are synthesized against no window and nothing is dispatched — `handle` reads only
/// `charactersIgnoringModifiers` and `modifierFlags`, so no responder sees a key.
@Suite
@MainActor
struct CadenceEditorLinkShortcutTests {
    @Test func commandShiftKWrapsTheSelectionAsALink() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        #expect(MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command, .shift]), in: textView))
        #expect(textView.string == "[alpha](url)")
    }

    @Test func plainCommandKIsNotTheEditorsLinkShortcut() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        // Unhandled, so `performKeyEquivalent` falls through to the responder chain — which is
        // moot in the running app, where the root monitor has already presented Search.
        #expect(!MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command]), in: textView))
        #expect(textView.string == "alpha")
    }

    /// Cmd+Shift+K is free: no other shortcut in the editor's own table takes shifted `k`, and the
    /// case above is the one that claims it.
    @Test func noOtherEditorShortcutClaimsShiftedK() throws {
        let textView = NSTextView()
        textView.string = "alpha"
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        _ = MarkdownKeyboardShortcutSupport.handle(try keyEvent("k", [.command, .shift]), in: textView)

        #expect(textView.string.hasPrefix("["))
        #expect(!textView.string.contains("**"))
        #expect(!textView.string.contains("~~"))
    }

    private func keyEvent(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 40
            )
        )
    }
}

/// [[T-8766]]. **On iPad, Cmd+K opens Search, as it does on the Mac.** `Cadence/iOS/` is invisible
/// to this macOS target and a hardware key cannot be pressed from it, so the wiring is read from
/// source: the root shell binds plain Cmd+K to a button that routes both shells to Search, and the
/// note editor's text view (the one iOS responder with its own key table) leaves plain Cmd+K
/// unbound, so the root's binding is reachable while typing.
@Suite
struct CadenceiPadSearchKeyCommandTests {
    @Test func theRootShellBindsCommandKToOpenSearch() throws {
        let root = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
        #expect(root.components(separatedBy: ".keyboardShortcut(\"k\", modifiers: .command)").count - 1 == 1)
        #expect(root.contains("Button(\"Search\", action: openSearch)\n                .keyboardShortcut(\"k\", modifiers: .command)"))
        // Hidden with opacity, not `.hidden()`, which can take the shortcut with it.
        #expect(!root.contains(".keyboardShortcut(\"k\", modifiers: .command)\n                .hidden()"))

        let body = try #require(root.range(of: "func openSearch() {").map { String(root[$0.upperBound...].prefix(200)) })
        #expect(body.contains("let destination = CadenceFeatureDestination.search"))
        #expect(body.contains("selection = destination.item"))
        #expect(body.contains("apply(destination.compactRoute)"))
    }

    @Test func theCompactRouteItTakesPushesSearch() {
        #expect(CadenceFeatureDestination.search.compactRoute.pushedDestination == .search)
    }

    @Test func theNoteEditorLeavesPlainCommandKUnbound() throws {
        let editor = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTextView.swift"))
        #expect(editor.contains("command(\"k\", [.command, .shift],"))
        #expect(!editor.contains("command(\"k\", [.command],"))
        #expect(!editor.contains("input: \"k\", modifierFlags: .command"))
        #expect(!editor.contains("input: \"k\", modifierFlags: [.command]"))
    }

    // MARK: - [[T-8791]] Cmd+K raises the field, by request

    @MainActor @Test func aFocusRequestIsHonouredOnceAndNothingIsHonouredUnasked() {
        let request = CadenceSearchFocusRequest()
        // Search reached without Cmd+K: nothing to honour.
        #expect(!request.take())
        request.request()
        #expect(request.generation == 1)
        #expect(request.take())
        // A later appearance (a sidebar tap after the Cmd+K one) does not focus again.
        #expect(!request.take())
        // A second Cmd+K while Search is up is a new, observable request.
        request.request()
        #expect(request.generation == 2)
        #expect(request.take())
        #expect(!request.take())
    }

    @Test func commandKRequestsFocusAndSearchHonoursOnlyTheRequest() throws {
        let root = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
        let openSearch = try #require(root.range(of: "func openSearch() {").map { String(root[$0.upperBound...].prefix(400)) })
        #expect(openSearch.contains("searchFocusRequest.request()"))
        // Only Cmd+K asks: one call in the whole root.
        #expect(root.components(separatedBy: "searchFocusRequest.request()").count - 1 == 1)
        #expect(root.contains(".environment(searchFocusRequest)"))

        let search = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift"))
        #expect(search.contains(".searchFocused($isSearchFieldFocused)"))
        let honour = try #require(CadenceSourceScan.functionBody(named: "honourSearchFocusRequest", in: search))
        #expect(honour.contains("searchFocusRequest?.take() == true"))
        #expect(honour.contains("isSearchFieldFocused = true"))
        // The field is raised in exactly one place, the request's; never unconditionally on appear.
        #expect(search.components(separatedBy: "isSearchFieldFocused = true").count - 1 == 1)
    }
}

/// [[T-13281]]. **On iPad (or any iOS device with a hardware keyboard), Cmd+N is New Task, as it
/// is on the Mac** ([[T-5953]]'s File > New Task). The iOS root shell bound Cmd+K alone
/// ([[T-8766]]), so the key the Mac spends on capture did nothing at all on an iPad keyboard. Read
/// from source for the reason `CadenceiPadSearchKeyCommandTests` gives: `Cadence/iOS/` is invisible
/// to this macOS target. The key and the title are read off the Mac's own menu data, so the two
/// platforms cannot drift apart again by editing one side.
@Suite
struct CadenceiPadNewTaskKeyCommandTests {
    private static func root() throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
    }

    @Test func theRootShellBindsTheMacsNewTaskKeyToOpenTheComposer() throws {
        let root = try Self.root()
        let binding = ".keyboardShortcut(\"\(CadenceNewItemMenu.newTaskShortcut)\", modifiers: .command)"
        #expect(root.components(separatedBy: binding).count - 1 == 1)
        #expect(root.contains("Button(\"\(CadenceNewItemMenu.newTask.title)\", action: openNewTask)\n                \(binding)"))
        // Hidden with opacity, not `.hidden()`, which can take the shortcut with it.
        #expect(!root.contains("\(binding)\n                .hidden()"))
    }

    /// The key asks the capture host for the composer a plain tap on the `+` opens: the same seed,
    /// through a host mounted on the root so it works from either shell and every page.
    @Test func theKeyRequestsTheTapsComposerThroughARootCaptureHost() throws {
        let root = try Self.root()
        #expect(root.components(separatedBy: ".iOSCaptureHost(keyboardCapture)").count - 1 == 1)
        let body = try #require(root.range(of: "func openNewTask() {").map { String(root[$0.upperBound...].prefix(200)) })
        #expect(body.contains("keyboardCapture.request(.task(CadenceCaptureSeedResolver.seed(for: .tap,"))
    }

    /// A tap's seed is the empty one, so Cmd+N opens an unscoped New Task like the Mac's item does.
    @MainActor @Test func aTapsSeedIsTheEmptyComposerSeed() {
        #expect(CadenceCaptureSeedResolver.seed(for: .tap, dropKey: nil, todayKey: "2026-11-08") == CadenceTaskComposerSeed())
    }

    /// The note editor's text view is the one iOS responder with its own key table; plain Cmd+N must
    /// stay unbound there so the root's binding is reached while typing. Cmd+Option+N is its note
    /// link and stays.
    @Test func theNoteEditorLeavesPlainCommandNUnbound() throws {
        let editor = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTextView.swift"))
        #expect(editor.contains("command(\"n\", [.command, .alternate],"))
        #expect(!editor.contains("command(\"n\", [.command],"))
        #expect(!editor.contains("input: \"n\", modifierFlags: .command"))
        #expect(!editor.contains("input: \"n\", modifierFlags: [.command]"))
    }
}

#endif

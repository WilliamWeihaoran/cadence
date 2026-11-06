#if os(macOS)
import Testing
@testable import Cadence

/// **[[T-10054]]: a second Cmd+K closes the open search palette.**
///
/// Cmd+\ and Cmd+O toggle their overlays; Cmd+K, the third key the root monitor's doc comment
/// groups with them, used to be swallowed while the palette was up and do nothing. Keeper decided:
/// it toggles too. The disposition is pure, so the cases are enumerated rather than pressed.
@Suite("Root presented search key disposition")
struct RootPresentedSearchKeyDispositionTests {
    private static let kKey: UInt16 = 40
    private static let escape: UInt16 = 53
    /// Any key the palette's own field should receive. `n`, as in the modal tests.
    private static let unrelatedKey: UInt16 = 45

    private func disposition(_ keyCode: UInt16, command: Bool) -> RootPresentedSearchKeyDisposition {
        RootCommandEventSupport.presentedGlobalSearchKeyDisposition(keyCode: keyCode, hasCommand: command)
    }

    @Test("A second Cmd+K closes the palette it opened")
    func aSecondCommandKClosesThePalette() {
        #expect(disposition(Self.kKey, command: true) == .dismiss, "Cmd+K is inert against its own palette again")
    }

    @Test("Escape still closes the palette, with or without Command")
    func escapeStillClosesThePalette() {
        #expect(disposition(Self.escape, command: false) == .dismiss)
        #expect(disposition(Self.escape, command: true) == .dismiss)
    }

    @Test("A bare k and every other key reach the palette's field")
    func otherKeysReachThePalette() {
        // A bare `k` is a letter the user is typing into the query, not a shortcut.
        #expect(disposition(Self.kKey, command: false) == .passToPalette, "typing k closes the palette")
        #expect(disposition(Self.unrelatedKey, command: false) == .passToPalette)
        #expect(disposition(Self.unrelatedKey, command: true) == .passToPalette, "an unrelated Cmd-key closes the palette")
    }
}
#endif

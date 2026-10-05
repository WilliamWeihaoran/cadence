import AppKit
import Testing
@testable import Cadence

#if os(macOS)

/// **T-1742, the half of the fix a unit test can carry.**
///
/// The defect was that Escape closed exactly one of the inspector's five child panels —
/// *"Escape closed only ["Estimate"] of ["Priority", "Estimate", "Do", "Due", "Repeat"]"*,
/// measured 2026-10-03 and reproduced 2026-10-04. The fix is a local `NSEvent` key-down
/// monitor held for the life of the panel, because an instrumented run showed the key-down is
/// addressed to the app's **main** window for all five panels and no popover window is ever
/// key — so neither `onExitCommand` (which rides the key window's responder chain) nor
/// `.onKeyPress` (which needs SwiftUI focus, and only the roller has it) can reach the other four.
///
/// **What this file does NOT claim.** It says nothing about delivery — which window AppKit hands
/// a key-down to is not a thing a unit test can observe, and asserting it here would be the
/// source-agreement-as-verification this ticket has already recorded three times. The delivery
/// guard is
/// `CadenceInspectorHeaderPanelPlacementUITests.testEscapeClosesEachInspectorChildPanelAndLeavesTheInspectorOpen`
/// and nothing else.
///
/// **What it does claim** is the monitor's predicate: which of the key-downs the monitor sees —
/// and while a panel is open it sees *every* key-down the app receives — it consumes. Getting that
/// wrong is how a dismissal modifier turns into a key thief, so the rows below are mostly
/// controls: a plain Escape must be taken, and four other events must be let through untouched.
@Suite("T-1742: the key-down an open inspector child panel consumes")
struct CadenceTaskInspectorChildPanelEscapeKeyTests {

    /// The escape key code is stated here independently rather than read back from the type under
    /// test, so a mutation of the constant cannot keep this file green by moving both sides.
    private static let escape: UInt16 = 53
    private static let returnKey: UInt16 = 36
    private static let letterA: UInt16 = 0

    @Test("plain Escape closes the panel")
    func plainEscapeClosesThePanel() {
        #expect(TaskInspectorChildPanelEscapeKey.closesPanel(keyCode: Self.escape, modifiers: []))
    }

    /// **The non-vacuity control, and the reason it is two keys and not one.** With a single
    /// non-matching row, a predicate reduced to `true` still fails somewhere and the suite looks
    /// honest. Return is the pointed one: the estimate roller already binds Return to close
    /// itself, so a predicate that swallowed Return would take that key away from the roller
    /// while *also* closing the panel, and the UI test could not tell the difference.
    @Test("another key is not the panel's to take", arguments: [
        (CadenceTaskInspectorChildPanelEscapeKeyTests.returnKey, "Return"),
        (CadenceTaskInspectorChildPanelEscapeKeyTests.letterA, "A")
    ])
    func anotherKeyIsNotThePanelsToTake(keyCode: UInt16, name: String) {
        #expect(
            TaskInspectorChildPanelEscapeKey.closesPanel(keyCode: keyCode, modifiers: []) == false,
            "\(name) must reach whatever else wanted it"
        )
    }

    /// Escape with a command-family modifier composes a different meaning (⌘⎋ is a system
    /// accelerator), so the panel leaves those alone even though the key code matches.
    @Test("Escape under a command-family modifier is left alone", arguments: [
        (NSEvent.ModifierFlags.command, "command"),
        (NSEvent.ModifierFlags.option, "option"),
        (NSEvent.ModifierFlags.control, "control")
    ])
    func escapeUnderACommandFamilyModifierIsLeftAlone(modifier: NSEvent.ModifierFlags, name: String) {
        #expect(
            TaskInspectorChildPanelEscapeKey.closesPanel(
                keyCode: Self.escape,
                modifiers: modifier
            ) == false,
            "⎋ with \(name) held is not the panel's key"
        )
    }

    /// Shift is the deliberate exception to the rule above: it composes nothing with Escape, and a
    /// user still wants the panel gone. Without this row, "ignore modifiers that compose" and
    /// "ignore every modifier" would both pass, and they are different rules.
    @Test("Shift-Escape still closes the panel")
    func shiftEscapeStillClosesThePanel() {
        #expect(TaskInspectorChildPanelEscapeKey.closesPanel(keyCode: Self.escape, modifiers: .shift))
    }

    /// `NSEvent` delivers `modifierFlags` with device-dependent bits set that are not in
    /// `.deviceIndependentFlagsMask`. A predicate that compared the raw flags to `[]` would reject
    /// a real Escape on hardware that sets them, which is exactly the kind of thing that passes in
    /// a test and fails on a desk.
    @Test("device-dependent modifier bits do not stop a real Escape")
    func deviceDependentModifierBitsDoNotStopARealEscape() {
        let deviceDependentOnly = NSEvent.ModifierFlags(rawValue: 0x101)
        #expect(deviceDependentOnly.intersection(.deviceIndependentFlagsMask).isEmpty)
        #expect(
            TaskInspectorChildPanelEscapeKey.closesPanel(
                keyCode: Self.escape,
                modifiers: deviceDependentOnly
            )
        )
    }
}

#endif

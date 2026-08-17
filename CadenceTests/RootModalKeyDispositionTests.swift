#if os(macOS)
import Testing
@testable import Cadence

/// The root key monitor's modal guard.
///
/// These exist because the bug they pin was invisible to every other kind of check. The guard
/// returned `NSEvent?`, and `nil` meant both "the modal consumed this key" and "no modal is open".
/// The caller could only read `nil` one way — as "not handled" — so every consume-path fell through
/// into the app's global shortcut table. It compiled, it read correctly, and the only way to see it
/// was to press Cmd+Return while hovering a task with the delete confirmation open.
///
/// The disposition is now a three-case enum and pure, so the whole space can simply be enumerated.
@Suite("Root modal key disposition")
struct RootModalKeyDispositionTests {
    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let escape: UInt16 = 53
    /// Any key an overlay does not claim. `n`, as it happens.
    private static let unrelatedKey: UInt16 = 45

    private func disposition(
        _ keyCode: UInt16,
        delete: Bool = false,
        datePicker: Bool = false
    ) -> RootModalKeyDisposition {
        RootCommandEventSupport.modalKeyDisposition(
            keyCode: keyCode,
            hasDeleteRequest: delete,
            hasDatePickerRequest: datePicker
        )
    }

    @Test("A confirmed delete is never also a global shortcut")
    func aConfirmedDeleteIsNeverAlsoAGlobalShortcut() {
        // The regression itself. `.act` is what tells the caller to swallow the event; anything
        // else here means Cmd+Return deletes one task and toggles completion on another.
        #expect(disposition(Self.returnKey, delete: true) == .act(.confirmDelete))
        #expect(disposition(Self.keypadEnter, delete: true) == .act(.confirmDelete))
    }

    @Test("Escape cancels whichever modal is open")
    func escapeCancelsWhicheverModalIsOpen() {
        #expect(disposition(Self.escape, delete: true) == .act(.cancelDelete))
        #expect(disposition(Self.escape, datePicker: true) == .act(.cancelDatePicker))
    }

    @Test("The date picker claims the same three keys")
    func theDatePickerClaimsTheSameThreeKeys() {
        #expect(disposition(Self.returnKey, datePicker: true) == .act(.confirmDatePicker))
        #expect(disposition(Self.keypadEnter, datePicker: true) == .act(.confirmDatePicker))
    }

    @Test("A key the modal does not claim reaches the overlay, not the app")
    func aKeyTheModalDoesNotClaimReachesTheOverlayNotTheApp() {
        // `.passToOverlay` and `.noModal` both used to be spelled `nil`. They are opposites: one
        // must stop at the overlay's own buttons, the other must carry on into the shortcut table.
        #expect(disposition(Self.unrelatedKey, delete: true) == .passToOverlay)
        #expect(disposition(Self.unrelatedKey, datePicker: true) == .passToOverlay)
    }

    @Test("With nothing open, every key is the app's own")
    func withNothingOpenEveryKeyIsTheAppsOwn() {
        for key in [Self.returnKey, Self.keypadEnter, Self.escape, Self.unrelatedKey] {
            #expect(disposition(key) == .noModal)
        }
    }

    @Test("The delete confirmation outranks the date picker")
    func theDeleteConfirmationOutranksTheDatePicker() {
        // Order matters when both are somehow up: the destructive one has to be the one Return
        // answers, and it must not confirm both.
        #expect(disposition(Self.returnKey, delete: true, datePicker: true) == .act(.confirmDelete))
        #expect(disposition(Self.escape, delete: true, datePicker: true) == .act(.cancelDelete))
    }
}
#endif

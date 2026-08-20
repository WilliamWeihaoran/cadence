import CloudKit
import Foundation
import Observation

/// Asks CloudKit for this device's account state, on either platform.
///
/// The state and its precedence rules are `CadenceCloudAccountState`'s and the verdict is
/// `CadenceSyncHealth`'s; this owns only the call and the "when was that" stamp. It exists as a
/// shared type because iOS's Settings screen had the whole thing as four `@State` properties plus a
/// `CKContainer.default().accountStatus` closure, and macOS was about to gain a second copy of
/// exactly that when it finally got a sync surface of its own (T-189). Four `@State`s and a
/// completion handler is not a decision worth having two spellings of, and the last time this repo
/// let a two-platform pair drift it was `CompactTagStrip` — three hand-written copies.
///
/// Deliberately **not** a singleton. It holds no cache anything else needs, and each settings
/// surface wants its own "last checked" for the button the user just pressed.
@MainActor
@Observable
final class CadenceCloudAccountProbe {
    private(set) var state: CadenceCloudAccountState = .notChecked
    private(set) var lastChecked: Date?

    var isChecking: Bool { state == .checking }

    /// True once a real answer — or a real failure — has landed.
    private var hasResult: Bool {
        switch state {
        case .notChecked, .checking: return false
        default: return true
        }
    }

    /// For `onAppear`: asks once, and does not re-ask on every re-appearance of the same page.
    func refreshIfNeeded() {
        guard !hasResult, !isChecking else { return }
        refresh()
    }

    /// For the "Check iCloud Status" button: always asks.
    func refresh() {
        state = .checking

        CKContainer.default().accountStatus { [weak self] status, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Back through the shared initializer rather than assigning a case directly, so
                // the error-beats-status precedence is decided in exactly one place.
                self.state = CadenceCloudAccountState(
                    accountStatus: status,
                    accountError: error?.localizedDescription,
                    isChecking: false
                )
                self.lastChecked = Date()
            }
        }
    }
}

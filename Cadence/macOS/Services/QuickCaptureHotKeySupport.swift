#if os(macOS)
import SwiftUI

/// T-5883. **The quick-capture hotkey, in words the user can read, and whether it is live.**
///
/// The hotkey was ⌃Space and nothing else: `GlobalHotKeyManager` asked Carbon for it at launch, and
/// a refusal went to `Logger` — so a Mac with two input sources, where macOS hands ⌃Space to
/// "Select the previous input source", got an app whose quick-capture key silently did nothing and
/// whose UI named no key to try instead. Both halves were the defect. The owner kept ⌃Space (the
/// clash only bites with a second input source) and asked for the key to be named in Settings and
/// for a failed registration to be visible there.
///
/// The copy lives here rather than in the Settings view so the registration path and the row that
/// reports it read one spelling of the shortcut.
nonisolated enum QuickCaptureHotKeyCopy {
    /// How the shortcut is written wherever it is shown. One spelling, one place.
    static let shortcutSymbol = "⌃Space"
    static let title = "Quick Capture"
    static let detail = "Press \(shortcutSymbol) from any app to capture a task."
    static let unavailableTitle = "\(shortcutSymbol) is not available"
    /// Said without naming a culprit the app cannot actually identify: Carbon reports only that the
    /// combination is taken, never by whom. The input-source shortcut is the likely one on this
    /// key, so it is offered as the thing to check rather than asserted as the cause.
    static let unavailableDetail = """
        Another app or a macOS shortcut already owns it, so quick capture will not open from \
        outside Cadence. macOS gives \(shortcutSymbol) to "Select the previous input source" when \
        more than one input source is installed.
        """
}

/// Whether the launch-time registration took, for the one row that reports it.
nonisolated enum QuickCaptureHotKeyRegistration: Equatable {
    /// Before `registerIfNeeded` has run, and after `unregister()`.
    case notAttempted
    case registered
    /// The `OSStatus` Carbon refused with, kept so the Settings row can say more than "failed" if
    /// it ever needs to.
    case failed(Int32)

    /// The Settings row shows the failure notice for this and nothing else. `notAttempted` is not a
    /// failure — it is the state before the app delegate has asked — and must not raise a warning
    /// on a surface that can be drawn first.
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// What the one Settings row draws, derived from the registration rather than decided inside the
/// view — so the two states can be asserted without standing a settings pane up.
nonisolated struct QuickCaptureHotKeyRowContent: Equatable {
    let systemImage: String
    let title: String
    let detail: String
    /// The row reports a problem rather than stating a setting.
    let isWarning: Bool

    static func make(for registration: QuickCaptureHotKeyRegistration) -> QuickCaptureHotKeyRowContent {
        guard registration.isFailure else {
            return QuickCaptureHotKeyRowContent(
                systemImage: "keyboard",
                title: QuickCaptureHotKeyCopy.title,
                detail: QuickCaptureHotKeyCopy.detail,
                isWarning: false
            )
        }
        return QuickCaptureHotKeyRowContent(
            systemImage: "exclamationmark.triangle.fill",
            title: QuickCaptureHotKeyCopy.unavailableTitle,
            detail: QuickCaptureHotKeyCopy.unavailableDetail,
            isWarning: true
        )
    }
}

@Observable
final class QuickCaptureHotKeyStatus {
    static let shared = QuickCaptureHotKeyStatus()

    var registration: QuickCaptureHotKeyRegistration = .notAttempted

    private init() {}
}
#endif

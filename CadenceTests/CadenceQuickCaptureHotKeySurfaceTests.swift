#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// T-5883. **The quick-capture hotkey is named in Settings, and a refused registration says so.**
///
/// The key stayed ⌃Space — the owner's decision — because the macOS "select the previous input
/// source" clash only bites with a second input source installed. What was actually broken is that
/// ⌃Space appeared nowhere in the app and `GlobalHotKeyManager`'s two refusal paths ended at
/// `Logger`, so the user saw an inert key and no explanation.
///
/// Nothing here registers a real hotkey: `RegisterEventHotKey` would take a system-wide key from
/// whatever owns it on this Mac. These assert the state machine and the copy the row draws.
@Suite
struct CadenceQuickCaptureHotKeySurfaceTests {
    @Test func theShortcutIsNamedAndIsControlSpace() {
        #expect(QuickCaptureHotKeyCopy.shortcutSymbol == "⌃Space")
        #expect(QuickCaptureHotKeyCopy.detail.contains(QuickCaptureHotKeyCopy.shortcutSymbol))
        #expect(QuickCaptureHotKeyCopy.unavailableTitle.contains(QuickCaptureHotKeyCopy.shortcutSymbol))
    }

    @Test func onlyARefusedRegistrationCountsAsAFailure() {
        #expect(QuickCaptureHotKeyRegistration.failed(-9878).isFailure)
        #expect(!QuickCaptureHotKeyRegistration.registered.isFailure)
        // The state before the app delegate has asked. A pane drawn first must not cry wolf.
        #expect(!QuickCaptureHotKeyRegistration.notAttempted.isFailure)
    }

    @Test func theSettingsRowStatesTheShortcutWhenItRegistered() {
        let content = QuickCaptureHotKeyRowContent.make(for: .registered)

        #expect(!content.isWarning)
        #expect(content.title == QuickCaptureHotKeyCopy.title)
        #expect(content.detail.contains("⌃Space"))
        #expect(content.systemImage == "keyboard")
    }

    @Test func theSettingsRowWarnsWhenRegistrationWasRefused() {
        let content = QuickCaptureHotKeyRowContent.make(for: .failed(-9878))

        #expect(content.isWarning)
        #expect(content.title != QuickCaptureHotKeyCopy.title)
        #expect(content.systemImage == "exclamationmark.triangle.fill")
        // It must name the likely culprit, which is the whole reason the owner kept the key.
        #expect(content.detail.contains("input source"))
    }

    @Test func aPaneDrawnBeforeRegistrationStatesTheShortcutRatherThanAWarning() {
        let content = QuickCaptureHotKeyRowContent.make(for: .notAttempted)

        #expect(!content.isWarning)
        #expect(content.title == QuickCaptureHotKeyCopy.title)
    }

    /// The row has to be reachable, not merely defined. Settings → Navigation is the pane the app
    /// opens on by default, and this is the one check that the derived content is actually wired
    /// into a view rather than left as dead copy.
    @Test func theNavigationSettingsPaneDrawsTheQuickCaptureRow() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsSectionViews.swift")

        #expect(source.contains("SettingsQuickCaptureSection(registration: hotKeyStatus.registration)"))
        #expect(source.contains("QuickCaptureHotKeyRowContent.make(for: registration)"))
        #expect(source.contains("QuickCaptureHotKeyCopy.shortcutSymbol"))
    }

    /// Both refusal paths in `GlobalHotKeyManager.registerIfNeeded` publish, rather than only
    /// logging. A `logger.error` with no `publish` beside it is exactly the defect this closes.
    @Test func bothRegistrationRefusalsPublishAFailure() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Services/GlobalHotKeyManager.swift")

        #expect(source.contains("publish(.failed(installStatus))"))
        #expect(source.contains("publish(.failed(registerStatus))"))
        #expect(source.contains("publish(.registered)"))
    }
}
#endif

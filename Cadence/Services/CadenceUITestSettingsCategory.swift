import Foundation

/// **[[T-11451]] — the SETTINGS CATEGORY a seeded launch opens on, selected by environment variable.**
///
/// [[T-3200]] got a window capture to the right root PAGE, and `settings` is one of them — but the
/// macOS settings pane is a rail of sixteen categories over one `@State` that starts on
/// `.navigation` and is persisted nowhere. So a capture could photograph Settings and only ever
/// Settings → Navigation, and every other pane was reachable only by clicking its row. That made
/// each of them an ATTENDED sighting waiting on macOS UI automation, which is not approved here
/// (`requests=0 granted=0`, measured 2026-11-04 by agent `macsee1100`), rather than a thing anyone
/// could simply look at. Measured the same day: [[T-11202]]'s three macOS clauses are all pure
/// rendered chrome, and all of them sat behind one click.
///
/// **The gate is the whole design, and it is [[T-3200]]'s gate, not a second one.**
/// `CADENCE_UI_TEST_MODE=1` AND a recognised `CADENCE_UI_TEST_SETTINGS_CATEGORY`. Either half alone
/// answers `nil`, and `nil` means "the app decides" — so a shipping launch reaches exactly the
/// `.navigation` it opened on before this file existed. The first half is also one of
/// `CadenceEventKitLaunchGate`'s disarm signals, so a launch that can be steered here is a launch
/// that cannot reach a real `EKEventStore`.
///
/// The vocabulary is `CadenceSettingsCategoryKind`'s own raw values — the shared category table,
/// not a second list of names to keep in step. `scripts/run-macos-app.sh` reads them out of that
/// enum rather than retyping them, the same way it reads the scenarios and the pages.
enum CadenceUITestSettingsCategory {

    static let categoryVariable = "CADENCE_UI_TEST_SETTINGS_CATEGORY"

    /// The settings category this launch asked for, or `nil` when it asked for none, asked outside
    /// UI-test mode, or named a category this build does not know.
    static func requested(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CadenceSettingsCategoryKind? {
        guard environment[CadenceEventKitLaunchGate.uiTestModeVariable] == "1" else { return nil }
        guard let raw = environment[categoryVariable], !raw.isEmpty else { return nil }
        return CadenceSettingsCategoryKind(rawValue: raw)
    }
}

import Foundation

/// **[[T-3200]] — the PAGE a seeded launch opens on, selected by environment variable.**
///
/// A window capture (`scripts/run-macos-app.sh capture`) can photograph whatever the app drew, but
/// nothing could take it to the page that needed looking at: the accessibility tree is
/// intermittently empty ([[T-3199]]), there is no page keyboard shortcut, no preference persists
/// the selected root tab, and the two routes that would work (a `CGEvent` click, `open
/// cadence://...`) drive the owner's cursor or can launch the shipping configuration. So the page
/// is chosen the way [[T-3186]] chooses the SCENARIO: one variable, read once at root.
///
/// **The gate is the whole design.** `CADENCE_UI_TEST_MODE=1` AND a recognised
/// `CADENCE_UI_TEST_PAGE`. Either half alone answers `nil`, and `nil` means "the app decides" —
/// so a shipping launch reaches exactly the initial selection it had before this file existed.
/// The first half is also one of `CadenceEventKitLaunchGate`'s disarm signals, so a launch that
/// can be steered here is a launch that cannot reach a real `EKEventStore`.
///
/// The raw values are the launcher's vocabulary: `scripts/run-macos-app.sh` reads them out of
/// this enum rather than retyping them, the same way it reads the scenario names.
enum CadenceUITestLaunchPage: String, CaseIterable {
    case today = "today"
    case allTasks = "all-tasks"
    case inbox = "inbox"
    case notes = "notes"
    case calendar = "calendar"
    case focus = "focus"
    case settings = "settings"

    static let pageVariable = "CADENCE_UI_TEST_PAGE"

    /// The page this launch asked for, or `nil` when it asked for none, asked outside UI-test
    /// mode, or named a page this build does not know.
    static func requested(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CadenceUITestLaunchPage? {
        guard environment[CadenceEventKitLaunchGate.uiTestModeVariable] == "1" else { return nil }
        guard let raw = environment[pageVariable], !raw.isEmpty else { return nil }
        return CadenceUITestLaunchPage(rawValue: raw)
    }
}

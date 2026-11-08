import Foundation
import Testing
@testable import Cadence

/// **[[T-13283]]: the `Open Today` App Shortcut goes to Today.**
///
/// `OpenCadenceTodayIntent.openAppWhenRun` only brings the app forward; without a route of its
/// own the shortcut left the app on whatever page it was last on, on both platforms. This drives
/// the intent's real `perform()` and reads the route it records on the shared manager both roots
/// consume. No shortcut is run and no app is opened.
@MainActor
struct OpenTodayIntentRoutingTests {
    @Test func openTodayIntentRecordsATodayRoute() async throws {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        _ = manager.takeUnappliedRoute()

        _ = try await OpenCadenceTodayIntent().perform()

        #expect(
            manager.route?.deepLink == .today,
            "the Open Today shortcut recorded no Today route, so it opens the app wherever it was left (T-13283)"
        )
        #expect(
            manager.takeUnappliedRoute() == .today,
            "the Today route is not offered to a root, so a cold-launch shortcut goes nowhere (T-13283, T-3049)"
        )
    }
}

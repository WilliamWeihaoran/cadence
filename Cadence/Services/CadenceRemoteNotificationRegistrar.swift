import Foundation
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one place in the app that asks the system to subscribe to CloudKit's silent pushes, and the
/// one place that says so when the system refuses.
///
/// **Why it is here rather than in `Cadence/macOS/Services/` (T-626).** It used to live beside
/// `CadenceAppDelegate`, inside that file's `#if os(macOS)`, and it was the *only* caller of the
/// platform registration call in the whole app. So on iOS Cadence never subscribed at all: no
/// subscription means CloudKit never tells the device its private database changed, and a
/// `NSPersistentCloudKitContainer`-backed store that is only told at launch is a store that looks
/// like it has stopped syncing. macOS was fine — the owner's live store has zero pending exported
/// objects — which is exactly why nobody saw it.
///
/// **Shared, not copied.** The platform difference is one type, so it is spelled as one type:
/// `Application` below. Everything either platform's launch does — the test-host guard, the
/// already-registered guard, the call itself, the failure sentence — has exactly one spelling, and
/// `CadenceLaunchWiringTests.onlyTheRegistrarAsksTheSystemToRegister` pins that: the app contains a
/// single `registerForRemoteNotifications` call site, on both platforms, in this file. A second
/// delegate that re-derived any of this would be the near-copy the repository's guides forbid, and
/// it would be the half that drifts.
enum CadenceRemoteNotificationRegistrar {

    /// `NSApplication` and `UIApplication` declare the same three members this needs — `shared`,
    /// `isRegisteredForRemoteNotifications` and the registration call — so the body below is
    /// genuinely one body rather than two behind a directive.
#if os(macOS)
    typealias Application = NSApplication
#else
    typealias Application = UIApplication
#endif

    private static let logger = Logger(
        subsystem: "com.haoranwei.Cadence",
        category: "RemoteNotifications"
    )

    /// Called from launch, once per platform: `CadenceAppDelegate.applicationDidFinishLaunching`
    /// on macOS, `CadenceIOSAppDelegate.application(_:didFinishLaunchingWithOptions:)` on iOS.
    @MainActor
    static func registerIfNeeded() {
        guard CadenceLaunchCapabilities.shouldRegisterForRemoteNotifications else { return }
        let application = Application.shared
        guard !application.isRegisteredForRemoteNotifications else { return }
        application.registerForRemoteNotifications()
    }

    /// The failure half, shared for the same reason the registration is: a device that silently
    /// fails to subscribe is indistinguishable from one that synced and had nothing to say, and
    /// this sentence in the log is the only difference.
    static func noteRegistrationFailure(_ error: Error) {
        logger.error(
            "Failed to register for CloudKit remote notifications: \(error.localizedDescription, privacy: .public)"
        )
    }
}

/// Launches that must not reach the push server: both test hosts, the UI-test mode, and the
/// local-store-only mode, which by definition has no CloudKit store to be told about.
private enum CadenceLaunchCapabilities {
    static var shouldRegisterForRemoteNotifications: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment["XCTestSessionIdentifier"] != nil { return false }
        if environment["CADENCE_UI_TEST_MODE"] == "1" { return false }
        if environment["CADENCE_LOCAL_STORE_ONLY"] == "1" { return false }
        return true
    }
}

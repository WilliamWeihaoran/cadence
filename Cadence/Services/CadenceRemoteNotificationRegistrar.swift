import Foundation
import Observation
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

    /// The success half. Nothing renders this on its own — it exists so that the monitor below
    /// can distinguish "this launch asked and was told yes" from "this launch never asked",
    /// which is what keeps the failure state from being inferred out of a silence.
    ///
    /// `into:` exists so a test can watch the answer land without writing to process-wide state —
    /// the same seam `noteRegistrationFailure` uses, and the reason the failure path below is
    /// pinned by what it *does* rather than by a grep for the type's name.
    ///
    /// It is `nil`-defaulted rather than `= .shared`, which reads better and does not compile
    /// clean: a default argument expression is evaluated in a **nonisolated** context, so naming
    /// a `@MainActor` singleton there is a warning today and an error under full Swift 6
    /// concurrency checking. Measured, not assumed — it warned on the first iOS build of this
    /// change, and the warning baseline here is zero.
    @MainActor
    static func noteRegistrationSucceeded(into monitor: CadencePushRegistrationMonitor? = nil) {
        (monitor ?? .shared).noteRegistered()
    }

    /// The failure half, shared for the same reason the registration is: a device that silently
    /// fails to subscribe is indistinguishable from one that synced and had nothing to say.
    ///
    /// **It used to be this log line and nothing else, and that is how T-1309 hid for so long.**
    /// A signed iOS build carried no push entitlement at all — the shared entitlements file only
    /// had macOS's spelling of the key — so this callback fired on every launch of the owner's
    /// phone, wrote one line to the unified log, and left an app that looked completely healthy
    /// while it was never subscribed to CloudKit's change pushes. The entitlement is fixed; a
    /// failure that reaches nothing but `log stream` is the half that would have let the *next*
    /// one hide just as well, so the state now reaches `CadenceSyncHealth` and the iCloud card
    /// on both platforms.
    @MainActor
    static func noteRegistrationFailure(
        _ error: Error,
        into monitor: CadencePushRegistrationMonitor? = nil
    ) {
        logger.error(
            "Failed to register for CloudKit remote notifications: \(error.localizedDescription, privacy: .public)"
        )
        (monitor ?? .shared).noteFailure(error.localizedDescription)
    }
}

/// What the system said, this launch, when Cadence asked to subscribe to CloudKit's silent pushes.
///
/// Three states rather than a `Bool?` because "never asked" is a real and common answer — both
/// test hosts, UI-test mode and local-store-only mode all return early from `registerIfNeeded()`,
/// and none of those is a failure to report to anyone.
enum CadencePushRegistrationState: Equatable {
    /// This launch has not asked, or has asked and not yet been answered.
    case notAttempted
    /// The system handed back a device token.
    case registered
    /// The system refused, with this description.
    case failed(String)
}

/// The one launch-scoped record of that answer, and the only thing any view reads about push.
///
/// `@Observable` and a singleton, unlike `CadenceCloudAccountProbe` next door, and for the
/// opposite reason: the account probe is a question each settings surface asks for itself, while
/// this is one fact about the process that arrives asynchronously from an app delegate callback
/// with no view anywhere near it. A second instance would be a second instance that never hears
/// the answer.
@MainActor
@Observable
final class CadencePushRegistrationMonitor {
    static let shared = CadencePushRegistrationMonitor()

    private(set) var state: CadencePushRegistrationState = .notAttempted

    /// Test-only seam: the type is a singleton because the delegate callback has nowhere else to
    /// put its answer, but a test asserting what the settings card says must not have to fake an
    /// APNs failure to do it.
    init(state: CadencePushRegistrationState = .notAttempted) {
        self.state = state
    }

    func noteRegistered() { state = .registered }

    func noteFailure(_ message: String) { state = .failed(message) }
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

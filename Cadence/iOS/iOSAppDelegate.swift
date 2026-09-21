#if os(iOS)
import Foundation
import UIKit

/// iOS's half of launch, and it exists for one reason: until T-626 nothing on this platform ever
/// asked the system to subscribe to CloudKit's silent pushes.
///
/// **What it deliberately does not do.** There is no
/// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` here, and that is measured
/// rather than assumed: `CadenceAppDelegate` on macOS has never implemented the AppKit equivalent
/// either, and the owner's Mac syncs — its live store holds 264 CloudKit metadata rows and **zero**
/// pending exported objects. SwiftData's CloudKit mirroring takes delivery of its own pushes; a
/// hand-written handler here would shadow that with a completion call that reports work it did not
/// do.
///
/// The registration itself is `CadenceRemoteNotificationRegistrar`, shared with macOS rather than
/// re-derived. This type owns only the two things a delegate must own: when to ask, and what to say
/// when the system says no.
@MainActor
final class CadenceIOSAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CadenceRemoteNotificationRegistrar.noteRegistrationSucceeded()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CadenceRemoteNotificationRegistrar.noteRegistrationFailure(error)
    }
}
#endif

#if os(macOS)
import AppKit
import Foundation

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
        CadenceSyncActivityLog.shared.startIfNeeded()
        GlobalHotKeyManager.shared.registerIfNeeded()
        CadenceWindowRestorationSupport.clampWindowsOntoConnectedScreens(
            NSApplication.shared.windows,
            screens: NSScreen.screens
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // T-7811: the markdown editors' typed-but-uncommitted buffers live in view state; commit
        // them before the process goes. Each flush commits its own write.
        MarkdownEditorTerminationFlush.shared.flushAllBeforeTermination()
        // T-5305: the focus stopwatch is memory-only; bank it before it is gone.
        FocusManager.shared.bankBeforeTermination()
        // T-5360: a tick still inside its 2.5s fill has not been written yet; finish it.
        TaskCompletionAnimationManager.shared.settleAllPendingBeforeTermination()
        GlobalHotKeyManager.shared.unregister()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CadenceRemoteNotificationRegistrar.noteRegistrationSucceeded()
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CadenceRemoteNotificationRegistrar.noteRegistrationFailure(error)
    }
}
#endif

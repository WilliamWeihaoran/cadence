#if os(macOS)
import AppKit
import Foundation

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {

    /// [[T-18756]]: the app is one window, so AppKit's automatic window tabbing is off before the
    /// first window exists. Left on, View offered Show Tab Bar / Show All Tabs and the tab strip's
    /// + answered `newWindowForTab:` with a second main window -- the two-window state [[T-5953]]
    /// calls a correctness hazard (`.shared` overlays drawn in both, two writers on one store).
    /// File > New Window keeps its item, with no shortcut, for [[T-3186]]'s zero-window recovery.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
        CadenceSyncActivityLog.shared.startIfNeeded()
        GlobalHotKeyManager.shared.registerIfNeeded()
        // [[T-18622]]: an MCP or widget write withdraws or re-arms its reminders now, not when
        // Cadence is next frontmost, and with no window open. Not in a test host, whose marker
        // would be the one beside the app's own store.
        if !NotificationManager.isTestEnvironment {
            CadenceExternalWriteReminderWatch.shared.start()
        }
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
        // T-5360: a tick still inside its fill (`CadenceTaskCompletionTiming.animationDuration`)
        // has not been written yet; finish it. [[T-18623]]: this also withdraws its reminders
        // synchronously, since the write's own async reconcile cannot outlive this method.
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

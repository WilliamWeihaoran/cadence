#if os(macOS)
import AppKit
import Foundation

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
        GlobalHotKeyManager.shared.registerIfNeeded()
        CadenceWindowRestorationSupport.clampWindowsOntoConnectedScreens(
            NSApplication.shared.windows,
            screens: NSScreen.screens
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregister()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CadenceRemoteNotificationRegistrar.noteRegistrationFailure(error)
    }
}
#endif

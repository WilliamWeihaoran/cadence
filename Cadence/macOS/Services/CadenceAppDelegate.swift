#if os(macOS)
import AppKit
import Foundation
import OSLog

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "RemoteNotifications")

    func applicationDidFinishLaunching(_ notification: Notification) {
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
        GlobalHotKeyManager.shared.registerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregister()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for CloudKit remote notifications: \(error.localizedDescription, privacy: .public)")
    }
}

enum CadenceRemoteNotificationRegistrar {
    @MainActor
    static func registerIfNeeded() {
        guard CadenceLaunchCapabilities.shouldRegisterForRemoteNotifications else { return }
        let application = NSApplication.shared
        guard !application.isRegisteredForRemoteNotifications else { return }
        application.registerForRemoteNotifications()
    }
}

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
#endif

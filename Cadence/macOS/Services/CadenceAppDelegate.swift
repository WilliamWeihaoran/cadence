#if os(macOS)
import AppKit
import Foundation
import OSLog

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "RemoteNotifications")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CadenceLaunchCapabilities.shouldRegisterForRemoteNotifications else { return }
        guard !NSApp.isRegisteredForRemoteNotifications else { return }
        NSApp.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for CloudKit remote notifications")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for CloudKit remote notifications: \(error.localizedDescription, privacy: .public)")
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

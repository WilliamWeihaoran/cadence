#if os(macOS)
import AppKit
import Foundation

@MainActor
final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CadenceLaunchCapabilities.shouldRegisterForRemoteNotifications else { return }
        guard !NSApp.isRegisteredForRemoteNotifications else { return }
        NSApp.registerForRemoteNotifications()
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

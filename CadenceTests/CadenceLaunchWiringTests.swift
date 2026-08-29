import Foundation
import Testing
@testable import Cadence

/// **T-468: two launch callers for one registrar.**
///
/// `CadenceRemoteNotificationRegistrar.registerIfNeeded()` was called from `CadenceApp.init()`
/// *and* from `CadenceAppDelegate.applicationDidFinishLaunching`, while every doc and commit
/// message in the repo described the delegate as **the** registration site. That mismatch is the
/// defect: a launch audit, or an App Review answer about what the app does on cold start, is
/// written from the description and would have been wrong.
///
/// **What is not claimed here.** Whether the two callers produced two `registerForRemoteNotifications()`
/// calls to the OS is *inferred*, not measured. `registerIfNeeded()` guards on
/// `isRegisteredForRemoteNotifications`, which only becomes true once the system has completed a
/// registration round trip, so the second caller plausibly fired again — but nothing in a test host
/// can observe that, and this suite does not pretend to. What it pins is exactly what a source scan
/// can prove: **one** production call site, and it is the owner the docs name.
@MainActor
struct CadenceLaunchWiringTests {

    /// The whole ticket in one assertion: one qualified call to the registrar in the whole app
    /// target, in the file that owns launch.
    ///
    /// Scanned over comment- and literal-stripped source, which is load-bearing rather than tidy:
    /// `CadenceApp.init()` now carries a tombstone comment *naming* the call it no longer makes,
    /// and a raw-text scan would count that comment as the second caller it exists to forbid.
    @Test func exactlyOneProductionCallSiteRegistersForSilentPush() throws {
        let owner = "Cadence/macOS/Services/CadenceAppDelegate.swift"
        let sources = try launchWiringSources()
        let callers = try launchRegistrarCallInstrument().sweep(
            sources.keys.sorted(),
            atLeast: 500,
            including: owner,
            read: { sources[$0] ?? "" }
        )

        #expect(callers == [owner], "silent-push registration is called from \(callers)")

        // The call site is launch, not some later lifecycle hook that happens to live in the same
        // file — scoped to the function body, because asserting over the whole file passes on any
        // line in it.
        let delegate = try #require(sources[owner])
        let launch = try #require(
            CadenceSourceScan.functionBody(named: "applicationDidFinishLaunching", in: delegate),
            "applicationDidFinishLaunching is gone from \(owner)"
        )
        #expect(
            launch.contains("CadenceRemoteNotificationRegistrar.registerIfNeeded()"),
            "the one caller is no longer on the launch path"
        )

        // And the entry point that used to be the second caller is clean in code, while the
        // adaptor that guarantees the delegate runs at all is still there. Deleting a duplicate
        // call is only safe while the survivor is reachable.
        let app = try #require(sources["Cadence/CadenceApp.swift"])
        #expect(
            !app.contains("CadenceRemoteNotificationRegistrar"),
            "CadenceApp is registering for silent push again"
        )
        #expect(
            app.contains("@NSApplicationDelegateAdaptor(CadenceAppDelegate.self)"),
            "the delegate is no longer installed, so nothing registers for silent push at all"
        )
    }

    /// The registrar is also the only thing in the app that asks AppKit to register, so "one
    /// caller" above is one call site all the way down rather than one wrapper over several.
    @Test func onlyTheRegistrarAsksAppKitToRegister() throws {
        let sources = try launchWiringSources()
        let owner = "Cadence/macOS/Services/CadenceAppDelegate.swift"
        let sites = try launchAppKitRegistrationInstrument().sweep(
            sources.keys.sorted(),
            atLeast: 500,
            including: owner,
            read: { sources[$0] ?? "" }
        )
        #expect(sites == [owner], "registerForRemoteNotifications() is spelled in \(sites)")
        #expect(
            CadenceSourceScan.matchCount(
                #"(?<![A-Za-z])registerForRemoteNotifications\s*\("#,
                in: try #require(sources[owner])
            ) == 1,
            "the owner spells registerForRemoteNotifications() more than once"
        )
    }

    /// Cold launch still must not prompt for notification permission — the thing the duplicate
    /// caller was *not*, and the property most easily broken by someone tidying this wiring.
    @Test func coldLaunchStillAsksForNoNotificationPermission() throws {
        let sources = try launchWiringSources()
        let app = try #require(sources["Cadence/CadenceApp.swift"])
        let initializer = try #require(
            launchInitializerBody(in: app),
            "CadenceApp has no init() to read"
        )
        #expect(
            !initializer.contains("requestAuthorization"),
            "cold launch prompts for notification permission again"
        )
        #expect(
            initializer.contains("NotificationManager.shared"),
            "read the wrong body: the initializer no longer touches NotificationManager"
        )
    }
}

// MARK: - Support

private func launchWiringRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Every app-target Swift file, comment- and literal-stripped, read once.
private func launchWiringSources() throws -> [String: String] {
    let root = launchWiringRepositoryRoot().appendingPathComponent("Cadence")
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [:] }
    var sources: [String: String] = [:]
    for element in enumerator {
        guard let name = element as? String, name.hasSuffix(".swift") else { continue }
        let path = "Cadence/\(name)"
        let raw = try String(
            contentsOf: launchWiringRepositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
        sources[path] = CadenceSourceScan.codeOnly(raw)
    }
    return sources
}

/// Fires on a qualified call of the registrar. The negative witness is its **declaration**, which
/// lives in the same file as the one legitimate call — a detector that matched the bare name would
/// report the owner as a caller whether or not it called anything.
private func launchRegistrarCallInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "qualified call of CadenceRemoteNotificationRegistrar.registerIfNeeded",
        fires: "        CadenceRemoteNotificationRegistrar.registerIfNeeded()",
        andNotOn: """
        enum CadenceRemoteNotificationRegistrar {
            @MainActor
            static func registerIfNeeded() {
            }
        }
        """,
        by: { source in
            CadenceSourceScan.matchCount(
                #"CadenceRemoteNotificationRegistrar\.registerIfNeeded\s*\("#,
                in: source
            ) > 0
        }
    )
}

/// Fires on the AppKit call itself. The negative witness is AppKit's **opposite** call,
/// `unregisterForRemoteNotifications()`, which contains the positive one as a substring — so a
/// detector written as a plain `contains` reports the teardown path as a registration site. The
/// delegate callbacks in the same file (`didRegisterForRemoteNotificationsWithDeviceToken`) are
/// excluded for free by case: they capitalise the `R`.
private func launchAppKitRegistrationInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "AppKit registerForRemoteNotifications() call",
        fires: "        application.registerForRemoteNotifications()",
        andNotOn: "        application.unregisterForRemoteNotifications()",
        by: { source in
            CadenceSourceScan.matchCount(
                #"(?<![A-Za-z])registerForRemoteNotifications\s*\("#,
                in: source
            ) > 0
        }
    )
}

/// `CadenceSourceScan.functionBody` anchors on `func <name>(`; an initializer has no `func`.
private func launchInitializerBody(in source: String) -> String? {
    guard let signature = source.range(of: "init() {") else { return nil }
    var depth = 0
    var index = source.index(before: signature.upperBound)
    while index < source.endIndex {
        if source[index] == "{" {
            depth += 1
        } else if source[index] == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[signature.upperBound..<index])
            }
        }
        index = source.index(after: index)
    }
    return nil
}

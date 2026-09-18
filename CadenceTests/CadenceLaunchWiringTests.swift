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
///
/// **T-626 made "one" mean one *per platform*, and that is a strengthening rather than a
/// loosening.** The owner the docs named was `Cadence/macOS/Services/CadenceAppDelegate.swift`,
/// and it was the only launch caller in the repository because there was no
/// `UIApplicationDelegateAdaptor` anywhere in it — so on iOS Cadence never subscribed to CloudKit's
/// silent pushes at all, and a test asserting `callers == [that one file]` read as green precisely
/// because half the app was missing. The assertions below now name **both** owners exactly, require
/// each to be guarded to its own platform, and — the part that keeps this from being two
/// registrations — still require the whole app to contain exactly **one** call site that asks the
/// system to register, shared by a `typealias` rather than copied behind a directive.
@MainActor
struct CadenceLaunchWiringTests {

    /// The whole ticket in one assertion, twice over: one qualified call to the registrar per
    /// platform, each in the file that owns that platform's launch.
    ///
    /// Scanned over comment- and literal-stripped source, which is load-bearing rather than tidy:
    /// `CadenceApp.init()` now carries a tombstone comment *naming* the call it no longer makes,
    /// and a raw-text scan would count that comment as the second caller it exists to forbid.
    @Test func exactlyOneLaunchCallerPerPlatformRegistersForSilentPush() throws {
        let macOwner = "Cadence/macOS/Services/CadenceAppDelegate.swift"
        let iOSOwner = "Cadence/iOS/iOSAppDelegate.swift"
        let sources = try launchWiringSources()
        let callers = try launchRegistrarCallInstrument().sweep(
            sources.keys.sorted(),
            atLeast: 500,
            including: macOwner,
            read: { sources[$0] ?? "" }
        )

        #expect(
            callers == [iOSOwner, macOwner].sorted(),
            "silent-push registration is called from \(callers)"
        )

        // The call site is launch, not some later lifecycle hook that happens to live in the same
        // file — scoped to the function body, because asserting over the whole file passes on any
        // line in it.
        let delegate = try #require(sources[macOwner])
        let launch = try #require(
            CadenceSourceScan.functionBody(named: "applicationDidFinishLaunching", in: delegate),
            "applicationDidFinishLaunching is gone from \(macOwner)"
        )
        #expect(
            launch.contains("CadenceRemoteNotificationRegistrar.registerIfNeeded()"),
            "the macOS caller is no longer on the launch path"
        )

        // Same scoping on iOS, and it cannot use `functionBody(named:)`: every UIKit delegate
        // callback in the file is *named* `application`, so the anchor has to be the part of the
        // signature that tells them apart. Anchoring on the name would read whichever callback
        // happens to be declared first.
        let iOSDelegate = try #require(sources[iOSOwner])
        let iOSLaunch = try #require(
            CadenceSourceScan.declarationBody("didFinishLaunchingWithOptions", in: iOSDelegate),
            "didFinishLaunchingWithOptions is gone from \(iOSOwner)"
        )
        #expect(
            iOSLaunch.contains("CadenceRemoteNotificationRegistrar.registerIfNeeded()"),
            "the iOS caller is no longer on the launch path"
        )

        // Two callers are only safe while no binary holds both, so the platform guard is asserted
        // rather than assumed. Without this the pair above is indistinguishable from T-468's
        // original defect with an extra file.
        #expect(delegate.hasPrefix("#if os(macOS)"), "the macOS delegate is no longer platform-guarded")
        #expect(iOSDelegate.hasPrefix("#if os(iOS)"), "the iOS delegate is no longer platform-guarded")

        // And the entry point that used to be the second caller is clean in code, while both
        // adaptors that guarantee a delegate runs at all are still there. Deleting a duplicate
        // call is only safe while the survivor is reachable — and on iOS the adaptor is the thing
        // that was missing, so its absence is the defect itself, not a tidy-up risk.
        let app = try #require(sources["Cadence/CadenceApp.swift"])
        #expect(
            !app.contains("CadenceRemoteNotificationRegistrar"),
            "CadenceApp is registering for silent push again"
        )
        #expect(
            app.contains("@NSApplicationDelegateAdaptor(CadenceAppDelegate.self)"),
            "the macOS delegate is no longer installed, so nothing registers for silent push there"
        )
        #expect(
            app.contains("@UIApplicationDelegateAdaptor(CadenceIOSAppDelegate.self)"),
            "the iOS delegate is no longer installed, so nothing registers for silent push there"
        )
    }

    /// The registrar is also the only thing in the app that asks *either* platform's application
    /// object to register, so "one caller per platform" above is one call site all the way down
    /// rather than one wrapper over two.
    ///
    /// **This is where the T-626 change could have gone wrong quietly.** The obvious way to give
    /// iOS a registration is a second `#if`-guarded body beside the macOS one — two `shared`
    /// lookups, two guards, two calls — and a sweep that merely counted "the files that ask" would
    /// have gone from one to one, because both halves would live in the same file. So the count
    /// asserted is the **call sites in the whole app**, still exactly one, and the body holding it
    /// is asserted to contain no platform directive at all: the difference between the two
    /// platforms is the `Application` typealias and nothing else.
    @Test func onlyTheRegistrarAsksTheSystemToRegister() throws {
        let sources = try launchWiringSources()
        let owner = "Cadence/Services/CadenceRemoteNotificationRegistrar.swift"
        let sites = try launchSystemRegistrationInstrument().sweep(
            sources.keys.sorted(),
            atLeast: 500,
            including: owner,
            read: { sources[$0] ?? "" }
        )
        #expect(sites == [owner], "registerForRemoteNotifications() is spelled in \(sites)")

        let registrar = try #require(sources[owner])
        #expect(
            CadenceSourceScan.matchCount(
                #"(?<![A-Za-z])registerForRemoteNotifications\s*\("#,
                in: registrar
            ) == 1,
            "the owner spells registerForRemoteNotifications() more than once"
        )

        let body = try #require(
            CadenceSourceScan.functionBody(named: "registerIfNeeded", in: registrar),
            "registerIfNeeded is gone from \(owner)"
        )
        #expect(
            !body.contains("#if"),
            "the one registration has grown a platform branch, so it is two registrations again"
        )
        #expect(
            body.contains("Application.shared"),
            "the shared body no longer goes through the platform typealias"
        )
        #expect(
            registrar.contains("typealias Application = NSApplication"),
            "macOS no longer reaches the shared registration"
        )
        #expect(
            registrar.contains("typealias Application = UIApplication"),
            "iOS no longer reaches the shared registration"
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

/// Fires on the platform registration call itself — the same spelling on `NSApplication` and
/// `UIApplication`, which is why one detector covers both. The negative witness is the frameworks'
/// **opposite** call, `unregisterForRemoteNotifications()`, which contains the positive one as a
/// substring — so a detector written as a plain `contains` reports the teardown path as a
/// registration site. The delegate callbacks in the two delegate files
/// (`didRegisterForRemoteNotificationsWithDeviceToken`) are excluded for free by case: they
/// capitalise the `R`.
private func launchSystemRegistrationInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "platform registerForRemoteNotifications() call",
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

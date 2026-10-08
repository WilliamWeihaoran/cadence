import Foundation
import Testing
#if os(macOS)
import EventKit
#endif
@testable import Cadence

/// **[[T-3031]] — an agent launch and a UI-test launch may not reach the owner's real Calendar.**
///
/// `CadenceEventKitLaunchGate` decides, from the launch environment, that a process is an agent
/// (`scripts/run-macos-app.sh`) or `CadenceUITests` launch; the calendar managers then never read
/// or request authorization, never observe the store, and refuse every write. These tests pin the
/// predicate against literal environments AND against the variables the two launchers really set
/// (read from their source, so a launcher that stops setting them goes red here), drive a disarmed
/// `CalendarManager` through every door, and scan `iOSCalendarManager`, which a macOS test build
/// does not compile.
///
/// Safety of the tests themselves: no test here calls `shared`, reads TCC, prompts, or reaches
/// `defaultWritableCalendar`. Writes are driven only with `EKEvent`s built from a foreign throwaway
/// store, which EventKit refuses, so a mutated-away gate turns `.notAuthorized` into `.saveFailed`
/// rather than into a real write.
@Suite(.serialized)
@MainActor
struct CadenceEventKitLaunchGateTests {

    // MARK: - 1. The predicate

    @Test func eachOfTheThreeLaunchMarkersAloneDisarmsEventKit() {
        #expect(CadenceEventKitLaunchGate.isDisarmed(in: ["CADENCE_LOCAL_STORE_ONLY": "1"]))
        #expect(CadenceEventKitLaunchGate.isDisarmed(in: ["CADENCE_UI_TEST_MODE": "1"]))
        #expect(CadenceEventKitLaunchGate.isDisarmed(in: ["CADENCE_UI_TEST_STORE_ID": "agent-42"]))
    }

    /// The other direction, which is the whole of the shipping behaviour: nothing set, a unit-test
    /// host's XCTest keys, and the near-misses of each marker all leave EventKit armed.
    @Test func aShippingOrUnitTestEnvironmentLeavesEventKitArmed() {
        let armed: [[String: String]] = [
            [:],
            ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration", "XCTestSessionIdentifier": "abc"],
            ["CADENCE_LOCAL_STORE_ONLY": "0"],
            ["CADENCE_UI_TEST_MODE": "0"],
            ["CADENCE_UI_TEST_STORE_ID": ""],
        ]
        for environment in armed {
            #expect(!CadenceEventKitLaunchGate.isDisarmed(in: environment), "\(environment) disarmed EventKit")
        }
        // This very process is a `CadenceTests` host, and the scheme sets none of the three: the
        // gate must not change what the rest of the suite sees.
        #expect(!CadenceEventKitLaunchGate.isDisarmedForThisProcess)
    }

    /// The variables `run-macos-app.sh` actually puts in front of the binary, parsed out of its
    /// launch line rather than restated, so the gate is tied to the launcher and not to a comment.
    @Test func theAgentLauncherEnvironmentDisarmsEventKit() throws {
        let script = try CadenceSourceScan.sourceFile("scripts/run-macos-app.sh")
        let launchLines = script.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && $0.contains("CADENCE_UI_TEST_STORE_ID=")
        }
        #expect(launchLines.count == 1, "expected one launch line in run-macos-app.sh, found \(launchLines.count)")
        let line = try #require(launchLines.first)

        var environment: [String: String] = [:]
        for token in line.split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("CADENCE_") else { continue }
            environment[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        // Non-vacuity: the parser found both variables the header documents.
        #expect(environment["CADENCE_LOCAL_STORE_ONLY"] == "1")
        #expect(environment["CADENCE_UI_TEST_STORE_ID"]?.isEmpty == false)

        #expect(CadenceEventKitLaunchGate.isDisarmed(in: environment))
        // Each half on its own is enough, so losing either one keeps the launch disarmed.
        for key in environment.keys {
            #expect(CadenceEventKitLaunchGate.isDisarmed(in: environment.filter { $0.key == key }), "\(key) alone did not disarm")
        }
    }

    /// Every UI suite that launches the app marks the launch with at least one of the three — the
    /// gate is only as good as the launchers' habit of setting them.
    @Test func everyUITestLaunchCarriesADisarmingMarker() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "CadenceUITests")
        var launchingFiles: [String] = []
        var unmarked: [String] = []
        for path in files {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            guard code.contains("launchEnvironment[") else { continue }
            launchingFiles.append(path)
            let marked = code.contains(#"launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1""#)
                || code.contains(#"launchEnvironment["CADENCE_UI_TEST_MODE"] = "1""#)
                // The store id is set only through the shared helper, so the helper's call is the
                // third marker. Not spelled as the assignment itself: that string here would be
                // counted as a launch site by `CadenceAgentDefaultsIsolationTests`' store-id census.
                || code.contains("isolateStoreAndPreferences(")
            if !marked { unmarked.append(path) }
        }
        #expect(launchingFiles.count >= 9, "found only \(launchingFiles.count) UI files that set a launch environment")
        #expect(unmarked.isEmpty, "UI files launching without an EventKit-disarming marker: \(unmarked.sorted())")
    }

    #if os(macOS)
    // MARK: - 2. A disarmed CalendarManager, door by door

    private static let agentLaunch = ["CADENCE_LOCAL_STORE_ONLY": "1", "CADENCE_UI_TEST_STORE_ID": "agent-42"]

    private func makeManager(environment: [String: String], authorized: Bool) -> CalendarManager {
        CalendarManager(gatedTestStore: EKEventStore(), launchEnvironment: environment, authorizedForTesting: authorized)
    }

    /// `.fullAccess` — the status the owner's Mac answers — still applies as not authorized, and
    /// registers no observer. The armed control proves the same call does authorize and observe,
    /// so the disarmed answer is the gate's and not the seam's.
    @Test func aDisarmedManagerReadsFullAccessAsNotAuthorizedAndNeverObserves() {
        let disarmed = makeManager(environment: Self.agentLaunch, authorized: false)
        disarmed.applyAuthorizationStatusForTesting(.fullAccess)
        #expect(!disarmed.isAuthorized)
        #expect(!disarmed.isObservingStoreChanges)

        disarmed.startObserving()
        #expect(!disarmed.isObservingStoreChanges, "a disarmed manager registered an EKEventStoreChanged observer")

        let armed = makeManager(environment: [:], authorized: false)
        armed.applyAuthorizationStatusForTesting(.fullAccess)
        #expect(armed.isAuthorized)
        #expect(armed.isObservingStoreChanges)
        armed.stopObserving()
        #expect(!armed.isObservingStoreChanges)
    }

    /// The re-derive path never consults TCC on a disarmed launch, and clears a seeded grant.
    @Test func aDisarmedManagerRefreshClearsAuthorizationWithoutAskingTCC() {
        let disarmed = makeManager(environment: ["CADENCE_UI_TEST_MODE": "1"], authorized: true)
        #expect(disarmed.isAuthorized)
        disarmed.refreshAuthorizationState()
        #expect(!disarmed.isAuthorized)
        #expect(!disarmed.isObservingStoreChanges)
        #expect(!disarmed.isDenied)
    }

    @Test func aDisarmedManagerRequestAccessAnswersNoWithoutPrompting() async {
        let disarmed = makeManager(environment: Self.agentLaunch, authorized: true)
        let granted = await disarmed.requestAccess()
        #expect(!granted)
        #expect(!disarmed.isAuthorized)
        #expect(!disarmed.isObservingStoreChanges)
    }

    /// The write sinks refuse on their own: the flag is seeded TRUE past the gate, so the only
    /// thing standing between each call and `store.save` / `store.remove` is the disarm check.
    /// The event comes from a foreign store, so without the gate EventKit answers `.saveFailed`.
    @Test func everyWriteOnADisarmedManagerIsARefusedNoOpEvenPastTheFlag() {
        let disarmed = makeManager(environment: Self.agentLaunch, authorized: true)
        let foreignEvent = EKEvent(eventStore: EKEventStore())
        foreignEvent.title = "Untouched"

        let answers: [CalendarWriteFailure?] = [
            disarmed.updateEvent(foreignEvent, title: "A", startMin: 60, durationMinutes: 30, dateKey: "2026-06-01"),
            disarmed.updateEvent(foreignEvent, title: "B", startDate: Date(), endDate: Date().addingTimeInterval(3600)),
            disarmed.updateEventNotes(foreignEvent, notes: "C"),
            disarmed.convertAllDayEventToTimed(foreignEvent, startMin: 120, dateKey: "2026-06-01"),
            disarmed.deleteEvent(foreignEvent),
            disarmed.deleteEvent(foreignEvent, scope: .futureOccurrences),
        ]
        #expect(answers.count == 6)
        for (index, answer) in answers.enumerated() {
            #expect(answer == .notAuthorized, "write #\(index) answered \(String(describing: answer))")
        }
        #expect(disarmed.lastWriteFailure == .notAuthorized)
    }

    /// The control for the test above: the same calls on an armed, seeded manager do reach
    /// EventKit (which refuses the foreign event), so `.notAuthorized` there is the gate's answer.
    @Test func theSameWritesOnAnArmedSeededManagerReachEventKit() {
        let armed = makeManager(environment: [:], authorized: true)
        let foreignEvent = EKEvent(eventStore: EKEventStore())
        let answer = armed.deleteEvent(foreignEvent)
        #expect(answer != nil)
        #expect(answer != .notAuthorized)
    }
    #endif

    // MARK: - 3. iOSCalendarManager, by source

    /// `Cadence/iOS/` is behind `#if os(iOS)` and is not compiled into this target, so the iOS half
    /// is pinned by reading it: every door is gated, and the request/refresh gates come BEFORE the
    /// first TCC read in their bodies.
    @Test func theIOSCalendarManagerIsGatedAtEveryDoor() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(raw.count > 1_000)
        #expect(code.count == raw.count)
        #expect(code != raw)

        #expect(code.contains("private let isEventKitDisarmed = CadenceEventKitLaunchGate.isDisarmedForThisProcess"))
        #expect(
            CadenceSourceScan.matchCount(#"guard isAuthorized, !isEventKitDisarmed else \{ return \.notAuthorized \}"#, in: code) == 4,
            "not all four iOS writes refuse on a disarmed launch"
        )
        // Non-vacuity for that count: the four writes are the only `.notAuthorized` guards.
        #expect(CadenceSourceScan.matchCount(#"else \{ return \.notAuthorized \}"#, in: code) == 4)

        let observer = try #require(CadenceSourceScan.functionBody(named: "startObserving", in: code))
        #expect(observer.contains("!isEventKitDisarmed"))
        let apply = try #require(CadenceSourceScan.functionBody(named: "applyAuthorizationStatus", in: code))
        #expect(apply.contains("status == .fullAccess, !isEventKitDisarmed"))

        for name in ["requestAccess", "refreshAuthorizationState"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: code), "no \(name) body")
            let gate = try #require(body.range(of: "guard !isEventKitDisarmed"), "\(name) has no disarm guard")
            let tcc = try #require(body.range(of: "EKEventStore.authorizationStatus"), "\(name) never reads TCC")
            #expect(gate.lowerBound < tcc.lowerBound, "\(name) reads TCC before the disarm guard")
        }
    }

    /// The same ordering on the desktop manager, for the one door a test cannot safely drive by
    /// mutation: removing `requestAccess`'s guard would ask the host's real TCC, and may prompt.
    @Test func theDesktopCalendarManagerAsksNoTCCQuestionBeforeItsDisarmGuard() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Services/CalendarManager.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.count == raw.count)
        #expect(code != raw)
        for name in ["requestAccess", "refreshAuthorizationState"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: code), "no \(name) body")
            let gate = try #require(body.range(of: "guard !isEventKitDisarmed"), "\(name) has no disarm guard")
            let tcc = try #require(body.range(of: "EKEventStore.authorizationStatus"), "\(name) never reads TCC")
            #expect(gate.lowerBound < tcc.lowerBound, "\(name) reads TCC before the disarm guard")
        }
        #expect(code.contains("self.isEventKitDisarmed = CadenceEventKitLaunchGate.isDisarmedForThisProcess"))
    }
}

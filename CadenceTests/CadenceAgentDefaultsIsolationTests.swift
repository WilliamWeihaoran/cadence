import Foundation
import Testing
@testable import Cadence

/// **T-735 — the tooling leak that reads as a product bug.**
///
/// `scripts/simulator-claim.sh` gives each agent a private SwiftData store and argues from that
/// store that two agents on one shared simulator cannot merge data. The argument is true for the
/// store and false for `UserDefaults`: `@AppStorage` values and remembered positions live in one
/// device-wide domain that survives reinstall and outlives a claim.
///
/// It cost twenty minutes on 2026-09-03. The compact Calendar tab opened on **August 2026 with
/// Aug 17 selected** on a cold launch against an **empty** private store — the exact shape of a
/// date bug, and in fact another agent's leftover `CadenceCalendarDateMemory` keys.
///
/// The fix is mechanical rather than a paragraph in the script's header, because a header only
/// helps an agent who reads it *before* being misled. These are the four things that have to hold
/// for the mechanism to be real: the name decision, the isolation itself, the launch that asks for
/// it, and the two wirings that make the app honour it.
@MainActor
struct CadenceAgentDefaultsIsolationTests {

    // MARK: - Behavioural: the name decision

    /// A real id becomes a suite, and every shape that would put a preferences file somewhere
    /// unintended becomes `nil` — which lands on `UserDefaults.standard`, i.e. on exactly the
    /// pre-T-735 behaviour rather than on a silently different one.
    @Test func onlyAnIdThatCanSafelyNameAPreferencesFileBecomesASuite() {
        #expect(CadenceDefaults.suiteName(forAgentID: "j4") == "com.haoranwei.Cadence.agent.j4")
        #expect(CadenceDefaults.suiteName(forAgentID: " j4 ") == "com.haoranwei.Cadence.agent.j4")
        #expect(CadenceDefaults.suiteName(forAgentID: "batch-9_a.2") == "com.haoranwei.Cadence.agent.batch-9_a.2")

        #expect(CadenceDefaults.suiteName(forAgentID: nil) == nil)
        #expect(CadenceDefaults.suiteName(forAgentID: "") == nil)
        #expect(CadenceDefaults.suiteName(forAgentID: "   ") == nil)
        #expect(CadenceDefaults.suiteName(forAgentID: "../../etc") == nil, "a traversal names a file outside the container")
        #expect(CadenceDefaults.suiteName(forAgentID: "two words") == nil)
        #expect(CadenceDefaults.suiteName(forAgentID: "a/b") == nil)
    }

    /// The resolution, driven rather than launched. No argument means the shared domain — so the
    /// product is untouched by all of this — and a valid one means a store that is *not* it.
    @Test func anAbsentLaunchArgumentLeavesTheAppOnTheSharedDomain() {
        #expect(CadenceDefaults.resolvedStore(agentID: nil) === UserDefaults.standard)
        #expect(CadenceDefaults.resolvedStore(agentID: "  ") === UserDefaults.standard)

        let name = CadenceDefaults.suiteNamePrefix + "isolation-test-a"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        #expect(CadenceDefaults.suiteName(forAgentID: "isolation-test-a") == name)
        #expect(CadenceDefaults.resolvedStore(agentID: "isolation-test-a") !== UserDefaults.standard)
    }

    /// **The leak itself, reproduced and then not reproduced.**
    ///
    /// `CadenceCalendarDateMemory` is the type the incident was chased through, so it is the one
    /// asserted on. Two agent ids, one device: the position one remembers must be invisible to the
    /// other *and* to the shared domain, which is what "an empty store looks empty" rests on.
    @Test func onAgentsRememberedCalendarPositionIsInvisibleToTheNext() throws {
        let first = try #require(CadenceDefaults.suiteName(forAgentID: "isolation-test-first"))
        let second = try #require(CadenceDefaults.suiteName(forAgentID: "isolation-test-second"))
        // Both ends, so a run that died before its `defer` cannot make the next one green or red
        // for the wrong reason. `removePersistentDomain` empties the domain but does not delete the
        // plist, so the test host's container keeps two empty files under these two fixed names —
        // measured 2026-09-03, `{ }` in both. Fixed names rather than generated ones for exactly
        // that reason: a per-run id would leave one file per run.
        UserDefaults.standard.removePersistentDomain(forName: first)
        UserDefaults.standard.removePersistentDomain(forName: second)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: first)
            UserDefaults.standard.removePersistentDomain(forName: second)
        }

        let sharedBefore = UserDefaults.standard.string(forKey: CadenceCalendarDateMemory.selectionKey)

        let day = try #require(DateFormatters.date(from: "2026-08-17"))
        CadenceCalendarDateMemory(defaults: CadenceDefaults.resolvedStore(agentID: "isolation-test-first"))
            .setSelectedDate(day)

        let firstMemory = CadenceCalendarDateMemory(defaults: CadenceDefaults.resolvedStore(agentID: "isolation-test-first"))
        #expect(firstMemory.storedSelectionKey == "2026-08-17", "the write did not land, so nothing below is evidence")

        let secondMemory = CadenceCalendarDateMemory(defaults: CadenceDefaults.resolvedStore(agentID: "isolation-test-second"))
        #expect(
            secondMemory.storedSelectionKey == nil,
            "the next agent inherits August 2026, which is the twenty minutes this ticket cost"
        )
        #expect(
            UserDefaults.standard.string(forKey: CadenceCalendarDateMemory.selectionKey) == sharedBefore,
            "the private write reached the device-wide domain anyway"
        )
    }

    // MARK: - Source shape: the launch, and the two wirings

    /// The mechanism is worth nothing if the claim script does not ask for it. Scanned rather than
    /// run: a sandboxed test host cannot drive `simctl`.
    @Test func theClaimScriptLaunchesEachAgentIntoItsOwnDefaultsSuite() throws {
        let script = try CadenceSourceScan.sourceFile("scripts/simulator-claim.sh")
        // Non-vacuity: this is the claim script, read whole.
        #expect(script.count > 4_000, "scripts/simulator-claim.sh read as \(script.count) characters")
        #expect(
            script.contains("SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID"),
            "scripts/simulator-claim.sh is not the claim script any more"
        )

        #expect(
            script.contains("${SIMCTL} launch$extra $u $BUNDLE_ID -\(CadenceDefaults.suiteNameArgumentKey) ${(q)ID}"),
            "the launch does not pass the per-agent defaults suite, so only the store is isolated"
        )
    }

    /// Both readers. `@AppStorage` is redirected once, at the scene, and the remembered calendar
    /// position — which is plain storage, so `defaultAppStorage` does not reach it — defaults to
    /// the same store rather than to `.standard`.
    @Test func theAppAndTheCalendarMemoryBothReadThroughTheRedirect() throws {
        let app = try CadenceSourceScan.sourceFile("Cadence/CadenceApp.swift")
        #expect(app.contains("struct CadenceApp: App {"), "Cadence/CadenceApp.swift did not read as itself")
        #expect(
            app.contains(".defaultAppStorage(CadenceDefaults.store)"),
            "every @AppStorage in the app is still resolved against the device-wide domain"
        )

        let memory = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarDateMemory.swift")
        #expect(memory.contains("struct CadenceCalendarDateMemory {"), "the memory file did not read as itself")
        #expect(
            memory.contains("init(defaults: UserDefaults = CadenceDefaults.store) {"),
            "the remembered calendar position still defaults to the shared domain"
        )
    }
}

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

    // MARK: - The two macOS launchers, which had none of this (T-1157)

    /// **The same mechanism, and until 2026-09-12 neither macOS launcher asked for it.**
    ///
    /// `simulator-claim.sh` above is an iOS launcher. On macOS the two launches an agent is told
    /// to make — `scripts/run-macos-app.sh` and every `XCUIApplication` in `CadenceUITests` — set
    /// `CADENCE_LOCAL_STORE_ONLY` and `CADENCE_UI_TEST_STORE_ID` and stopped there. Those isolate
    /// **SwiftData and nothing else**, which is the sentence this file's header already carries
    /// about iOS. A debug build carries bundle id `com.haoranwei.Cadence`, so it gets the
    /// signed-in person's sandbox container, and with no argument `CadenceDefaults.store` *is*
    /// their `Data/Library/Preferences/com.haoranwei.Cadence.plist` — **86 keys, written the same
    /// morning**, measured at `4efd003`.
    @Test func bothMacOSLaunchersAskForAPrivatePreferencesSuite() throws {
        let script = try CadenceSourceScan.sourceFile("scripts/run-macos-app.sh")
        #expect(script.contains("CADENCE_UI_TEST_STORE_ID=\"$ID\""), "run-macos-app.sh did not read as itself")
        #expect(
            script.contains("-\(CadenceDefaults.suiteNameArgumentKey) \"$ID\""),
            "run-macos-app.sh launches the app onto the signed-in person's own defaults domain"
        )

        // Every launch site in the UI target, counted rather than named: a fifth one added later
        // has to route through the helper too, and a count is the only reading that notices.
        let uiSources = [
            "CadenceUITests/CadenceUITests.swift",
            "CadenceUITests/CadenceUITestsLaunchTests.swift",
            "CadenceUITests/CadenceTodayCompositionUITests.swift",
            "CadenceUITests/CadenceSeededSidebarTimingUITests.swift",
        ]
        var constructions = 0
        var isolations = 0
        for path in uiSources {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            constructions += source.components(separatedBy: "XCUIApplication()").count - 1
            isolations += source.components(separatedBy: "isolateStoreAndPreferences(").count - 1
            #expect(
                !source.contains("launchEnvironment[\"CADENCE_UI_TEST_STORE_ID\"]"),
                "\(path) still sets the store id by hand, so its preferences suite is whatever it happens to be"
            )
        }
        #expect(constructions == 4, "the UI target builds \(constructions) apps, not the 4 this reading was measured against")
        #expect(isolations == constructions, "\(constructions) launch sites, \(isolations) of them isolated")

        // The helper lives in the UI-test target, which nothing here can import, so the two
        // literals it has to keep in step with this target are read as text. Both are load-bearing:
        // a drifted key name means the argument is ignored and a drifted character set means an id
        // the app refuses, and each lands the launch back on the shared domain looking correct.
        let helper = try CadenceSourceScan.sourceFile("CadenceUITests/CadenceUITestEnvironment.swift")
        #expect(helper.contains("enum CadenceUITestEnvironment {"), "the UI-test environment file did not read as itself")
        #expect(
            helper.contains("static let suiteNameArgumentKey = \"\(CadenceDefaults.suiteNameArgumentKey)\""),
            "the UI target spells a different launch-argument key, so the argument it passes is ignored"
        )
        #expect(
            helper.contains("CharacterSet.alphanumerics.union(CharacterSet(charactersIn: \"-_.\"))"),
            "the UI target reduces ids against a different character set than CadenceDefaults accepts"
        )
    }

    /// **Why "one line on each side" would have been a green no-op**, and the reason T-1157 was
    /// filed rather than applied blind.
    ///
    /// The proposed fix passed the *store id* as the suite name. `CadenceUITests` builds that id
    /// as `"ui-\(name)-\(UUID().uuidString)"`, and `XCTestCase.name` on macOS is
    /// `-[CadenceUITests testLaunchesToTodayWithSeededSidebarLists]` — square brackets and a
    /// space, all three outside the accepted set. `suiteName(forAgentID:)` answers `nil` for that,
    /// `nil` means the shared domain, and the fallback is silent *by design* because it is the
    /// product's behaviour with no argument at all. The launch would have carried
    /// `-CadenceSuiteName`, looked correct in the source, and deleted the same four keys.
    @Test func theStoreIdTheUITestsBuildIsRefusedUntilItIsReduced() {
        let raw = "ui--[CadenceUITests testLaunchesToTodayWithSeededSidebarLists]-4E5F6A7B"
        #expect(
            CadenceDefaults.suiteName(forAgentID: raw) == nil,
            "the id the UI tests actually build is accepted, so this test is no longer about anything"
        )

        // `CadenceUITestEnvironment.privateSuiteID` lives in the UI-test target, which nothing here
        // can import, so its RULE is restated and its OUTPUT is what gets asserted: every character
        // outside the accepted set becomes `-`.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let reduced = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        #expect(reduced == "ui---CadenceUITests-testLaunchesToTodayWithSeededSidebarLists--4E5F6A7B")
        #expect(
            CadenceDefaults.suiteName(forAgentID: reduced) == CadenceDefaults.suiteNamePrefix + reduced,
            "the reduction does not survive the app's own rule, so the UI launches are still shared"
        )
    }

    /// The half that does not depend on a launch argument being right.
    ///
    /// `CadenceUITestSupport.resetUserDefaults` is what actually *deletes*: four keys, removed from
    /// whatever `CadenceDefaults.store` resolved to. Both non-skipped UI tests request it. So the
    /// question it now asks first is not "was an argument passed" — a string, mistypeable — but
    /// "is this store the shared domain", which is the hazard itself.
    @Test func aRequestedResetRefusesToRunOnTheSharedDomain() throws {
        #expect(
            CadenceUITestSupport.mayResetUserDefaults(store: UserDefaults.standard) == false,
            "a UI-test reset would still delete the signed-in person's four sidebar keys"
        )
        #expect(CadenceDefaults.isPrivateSuite(UserDefaults.standard) == false)

        // Through `withTemporaryDefaults`, which derives the suite name from `#function` — a name
        // minted per run strands one more preference plist in the app's own container every time
        // ([[T-516]]), and that container already holds 7803 of them.
        try withTemporaryDefaults("cadence.tests.reset-guard") { suite in
            #expect(CadenceDefaults.isPrivateSuite(suite))
            #expect(
                CadenceUITestSupport.mayResetUserDefaults(store: suite),
                "the guard refuses a private suite too, which would leave every UI test unseeded"
            )
        }
    }
}

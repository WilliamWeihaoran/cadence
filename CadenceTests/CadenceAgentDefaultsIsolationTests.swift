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
            "CadenceUITests/CadenceTodayRowCrushUITests.swift",
            // The sixth, added with [[T-2074]]/[[T-2075]]: the first launch site in this target
            // that is not macOS. It is here because the comment above says a later one has to
            // route through the helper too — and a list that is never extended turns that
            // sentence into a count over the files somebody remembered.
            "CadenceUITests/CadenceIOSSeededStoreUITests.swift",
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
        #expect(constructions == 6, "the UI target builds \(constructions) apps, not the 6 this reading was measured against")
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

    // MARK: - The backups beside the store, which followed neither (T-1448)

    /// **The store redirect moved the store and left everything beside it behind.**
    ///
    /// `StoreBackupManager` resolved `CadenceStoreSupport.primaryStoreDirectoryURL()` directly, so
    /// on a launch redirected by `CADENCE_UI_TEST_STORE_ID` it managed the signed-in person's
    /// backups while the app had a private store open. T-1448 was filed over the *visible* half —
    /// an agent saw their two real backups listed in Settings → Data Safety. The half measured
    /// while closing it is that the same directory was written: `PersistenceController.init` ran
    /// its preflight against the app-group path unconditionally, so every agent launch copied
    /// ~16 MB of their store into their backups folder and then purged the rest under their
    /// retention policy.
    ///
    /// Driven rather than launched, and driven at the resolution the product actually calls: the
    /// environment is an argument here only because a test process cannot be two launches at once.
    @Test func theBackupsDirectoryFollowsTheStoreTheLaunchActuallyOpens() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1448-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // **The unset case first, because it is the one that reaches the shipping app.** No id in
        // the environment has to keep answering the production path exactly, and "exactly" is
        // asserted against `CadenceStoreSupport` rather than against a literal, so a later change
        // to where the app-group store lives cannot make this pass by drifting with it.
        //
        // **[[T-1850]] made "exactly" mean something on a host with no app group.** This was
        // `try CadenceStoreSupport.primaryStoreDirectoryURL()` on one line, and on a hosted CI
        // runner that `try` throws — `NSCocoaErrorDomain` 513 over `NSPOSIXErrorDomain` 1, from the
        // `createDirectory` inside `sharedStoreDirectoryURL` and **not** from a nil container: the
        // lookup answers `/Users/runner/Library/Group Containers/…` and the directory under it
        // cannot be made, because `.github/ci.entitlements` grants only `get-task-allow` and a
        // hosted runner has no provisioning profile to carry an app group. So the assertion was
        // never reached at all. The claim is *agreement with `CadenceStoreSupport`*, not "a path
        // came back", and it is now driven on every floor: this host's container, an injected
        // stand-in that always resolves, an injected container that is answered and cannot be
        // written — CI's, exactly — and an injected absence. The exact path is still pinned, on
        // every host, by the stand-in.
        for floor in CadenceAppGroupFloor.all(in: temporaryDirectory) {
            expectResolvesLikeTheAppGroupStore(
                { try StoreBackupManager.storeDirectoryURL(in: [:], temporaryDirectory: temporaryDirectory, fileManager: $0) },
                on: floor,
                "an unredirected launch no longer resolves its backups to the app-group store"
            )
            expectResolvesLikeTheAppGroupStore(
                {
                    try StoreBackupManager.storeDirectoryURL(
                        in: ["CADENCE_LOCAL_STORE_ONLY": "1"],
                        temporaryDirectory: temporaryDirectory,
                        fileManager: $0
                    )
                },
                on: floor,
                "CADENCE_LOCAL_STORE_ONLY alone never redirected the store and must not redirect backups"
            )
        }

        // ...and now the redirected one.
        let environment = ["CADENCE_UI_TEST_STORE_ID": "t1448-agent"]
        let redirected = try StoreBackupManager.storeDirectoryURL(
            in: environment,
            temporaryDirectory: temporaryDirectory
        )
        let expected = CadenceUITestStoreDirectory.rootDirectory(in: temporaryDirectory)
            .appendingPathComponent("t1448-agent", isDirectory: true)
        for floor in CadenceAppGroupFloor.all(in: temporaryDirectory) {
            expectDiffersFromTheAppGroupStore(
                redirected,
                on: floor,
                "the redirect resolved to the person's own store directory"
            )
        }
        #expect(redirected == expected, "the backups directory is not beside the store this launch opens")

        // The resolution is only worth something if `listBackups` reads through it, so the claim is
        // finished at the level that renders: a backup planted beside the private store is listed
        // from the resolved directory, and is **not** among what the production directory reports.
        //
        // **Planted under `expected`, never under `redirected`**, and that is a safety property of
        // this test rather than a style choice. `expected` is built from this test's own temporary
        // directory, so it cannot name a real store; `redirected` is the value under test, and a
        // regression that made it answer the app-group path would have this line create a folder
        // inside the signed-in person's real backups directory — writing into exactly the place
        // T-1448 exists to keep an agent out of. Planting in the known-private path leaves the
        // assertion below just as red and leaves their directory untouched. The one call that does
        // touch it, the last `#expect`, only lists it.
        let plantedID = "20260928-000000-startup"
        let plantedURL = expected
            .appendingPathComponent("Cadence Store Backups", isDirectory: true)
            .appendingPathComponent(plantedID, isDirectory: true)
        try FileManager.default.createDirectory(at: plantedURL, withIntermediateDirectories: true)

        let redirectedIDs = StoreBackupManager.listBackups(storeDirectoryURL: redirected).map(\.id)
        #expect(redirectedIDs == [plantedID], "the redirected directory listed \(redirectedIDs)")

        // Over the floors whose app group *exists* — never empty, because the stand-in always does,
        // so this loop cannot quietly become a loop over nothing on a runner. Listing only; the one
        // of these that may be the owner's real directory is the one this test has never written to.
        let resolvable = CadenceAppGroupFloor.resolvable(in: temporaryDirectory)
        #expect(!resolvable.isEmpty, "no floor resolved an app-group store, so the check below is vacuous")
        for floor in resolvable {
            let appGroupStore = try #require(floor.reference.url)
            #expect(
                !StoreBackupManager.listBackups(storeDirectoryURL: appGroupStore).map(\.id).contains(plantedID),
                "[\(floor.name)] the two directories are the same one, so nothing above was isolated"
            )
        }
    }

    /// **The no-argument entry points are the ones the product calls**, so the resolution proved
    /// above has to be the resolution they reach — otherwise this is a tested helper beside an
    /// untouched defect.
    @Test func everyNoArgumentBackupEntryPointResolvesThroughTheRedirect() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        #expect(source.contains("enum StoreBackupManager {"), "PersistenceController.swift did not read as itself")

        let resolver = try #require(
            CadenceSourceScan.declarationBody("private static func defaultStoreDirectoryURL(", in: source),
            "the no-argument entry points no longer share one resolver"
        )
        #expect(
            resolver.contains("storeDirectoryURL(in: ProcessInfo.processInfo.environment)"),
            "defaultStoreDirectoryURL does not ask the environment, so nothing the launch sets reaches it"
        )
        #expect(
            !resolver.contains("CadenceStoreSupport.primaryStoreDirectoryURL()"),
            "defaultStoreDirectoryURL went back to answering the app-group store unconditionally"
        )

        // **[[T-1852]]: the two *listings* now take a second, non-creating resolver — and it has to
        // ask the same redirect.** `unmanagedBackupDirectories()` and `unmanagedStoreDirectories()`
        // want the live store directory only in order to **exclude** it from a read-only list, and
        // reaching it through `defaultStoreDirectoryURL()` meant that asking created the signed-in
        // person's store directory. They are the only two that moved; every destructive entry point
        // still takes the creating form, which is correct — it is about to write there.
        let location = try #require(
            CadenceSourceScan.declarationBody("private static func defaultStoreDirectoryLocation(", in: source),
            "the listings no longer share a non-creating resolver"
        )
        #expect(
            location.contains("storeDirectoryLocation(in: ProcessInfo.processInfo.environment)"),
            "defaultStoreDirectoryLocation does not ask the environment, so the redirect does not reach it"
        )
        #expect(
            !location.contains("CadenceStoreSupport.primaryStoreDirectoryURL"),
            "the non-creating resolver creates the app-group store directory again"
        )

        // Counted rather than named, in both spellings: an entry point added later still has to go
        // through one of the two, and a count is the only reading that notices. The creating form
        // was nine for T-1448 (eight calls and the declaration); [[T-1532]] added a tenth,
        // `unmanagedBackupDirectories()`, and [[T-1680]] an eleventh, `unmanagedStoreDirectories()`
        // — and [[T-1852]] moved exactly those two onto the non-creating form, which is why the
        // first number went back to 9 and the second is 3 (two calls and the declaration). The
        // **sum** is what must not fall: twelve spellings, one resolver each.
        //
        // Over the stripped source, because T-1532 also wrote the name into a doc comment — and a
        // tripwire that a paragraph can trip is one that gets edited until it stops complaining.
        let code = CadenceSourceScan.strippingComments(source)
        let creating = CadenceSourceScan.matchCount("defaultStoreDirectoryURL\\(\\)", in: code)
        let locating = CadenceSourceScan.matchCount("defaultStoreDirectoryLocation\\(\\)", in: code)
        #expect(creating == 9, "\(creating) spellings of defaultStoreDirectoryURL(), not the 9 measured for T-1852")
        #expect(locating == 3, "\(locating) spellings of defaultStoreDirectoryLocation(), not the 3 measured for T-1852")
        #expect(
            creating + locating == 12,
            "\(creating + locating) no-argument store-directory resolutions, not the 12 measured for T-1852"
        )

        // The two that moved are the two listings, named — a count alone cannot tell "the listing
        // stopped creating" from "a destructive entry point quietly stopped creating too".
        for listing in [
            "unmanagedBackupDirectories(liveStoreDirectoryURL: defaultStoreDirectoryLocation())",
            "liveStoreDirectoryURL: defaultStoreDirectoryLocation(),",
        ] {
            #expect(code.contains(listing), "a read-only listing is back on the creating resolver: \(listing)")
        }
    }

    // MARK: - T-1530: the test host's backups follow the test host's store

    /// **The redirect made provable, from inside the process it is about.**
    ///
    /// [[T-1530]] recorded the residue [[T-1448]] left: `storeDirectoryURL(in:)` honoured
    /// `CADENCE_UI_TEST_STORE_ID` and not the separate `isRunningTests` redirect, and a plain
    /// `xcodebuild test` sets no store id — so every no-argument entry point on
    /// `StoreBackupManager` resolved the signed-in person's app-group directory while this test
    /// host had a throwaway store open. That nothing reached it was an *assertion about the suite*,
    /// one `try StoreBackupManager.deleteAllBackups()` away from being false.
    ///
    /// This drives the real no-argument property, in this process, against this process's real
    /// environment — which is the only reading that can tell the guarantee from the coincidence.
    @Test func theTestHostsBackupsAreItsOwnAndNotTheSignedInPersons() throws {
        // This one is about the **real process environment**, so `backupRootURL` cannot be injected
        // into — and does not need to be. Built here from `FileManager.default.temporaryDirectory`
        // — the same default the resolver takes, spelled independently of it. Nothing below is
        // planted under the value under test, so a regression that answered the app-group path
        // leaves this assertion red and their directory untouched. Same rule, same reason, as
        // `…FollowsTheStoreTheLaunchActuallyOpens`.
        let hostRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceTestsHostStore", isDirectory: true)
            .appendingPathComponent("Cadence Store Backups", isDirectory: true)

        // The load-bearing claim, and it is **exact and unconditional on every host**: the
        // no-argument backup root is the test host's own. It names no app group, so it is the same
        // assertion on a Mac with a container and on a runner without one.
        #expect(
            StoreBackupManager.backupRootURL.standardizedFileURL == hostRoot.standardizedFileURL,
            "the no-argument backup root is \(StoreBackupManager.backupRootURL.path)"
        )

        // The corollary, stated per floor because [[T-1850]]: `try CadenceStoreSupport
        // .primaryStoreDirectoryURL()` on the first line of this test threw on CI, where there is no
        // app-group container, and took the assertion above down with it before it ran. A refusal is
        // a value here, and a directory is never equal to one — so "the test host's backups are not
        // the owner's" is decidable on a host that cannot reach the owner's at all.
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1530Floors-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        for floor in CadenceAppGroupFloor.all(in: temporaryDirectory) {
            let appGroupBackupRoot = floor.reference.appending("Cadence Store Backups")
            #expect(
                CadenceAppGroupStoreOutcome.directory(
                    StoreBackupManager.backupRootURL.standardizedFileURL.path
                ) != appGroupBackupRoot,
                "[\(floor.name)] a unit test's backup entry points still resolve the signed-in person's real backups"
            )
        }

        // The path is only half of it: `listBackups()` has to *read* through the resolution, or
        // this is a tested property beside an untouched defect. Planted in the host's own folder
        // and removed again; the owner's directory is only listed.
        let plantedID = "20260929-000000-manual-t1530-\(UUID().uuidString.prefix(8))"
        let plantedURL = hostRoot.appendingPathComponent(plantedID, isDirectory: true)
        try FileManager.default.createDirectory(at: plantedURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plantedURL) }

        #expect(
            StoreBackupManager.listBackups().map(\.id).contains(plantedID),
            "listBackups() does not read the directory the test host's store lives in"
        )
        let resolvable = CadenceAppGroupFloor.resolvable(in: temporaryDirectory)
        #expect(!resolvable.isEmpty, "no floor resolved an app-group store, so the check below is vacuous")
        for floor in resolvable {
            let appGroupStore = try #require(floor.reference.url)
            #expect(
                !StoreBackupManager.listBackups(storeDirectoryURL: appGroupStore).map(\.id).contains(plantedID),
                "[\(floor.name)] the two directories are the same one, so nothing above was isolated"
            )
        }
    }

    /// Both directions, injected — because the half that matters most is the one no test host can
    /// exhibit: **an environment naming neither redirect still resolves exactly the production
    /// path**, which is the shipping app's.
    @Test func theTestHostRedirectIsGuardedInBothDirections() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1530-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // The three readings of "where is this process's app group" — [[T-1850]]. This was one
        // `try CadenceStoreSupport.primaryStoreDirectoryURL()`, which is a *refusal* on a hosted
        // runner with no provisioning profile, so the whole test stopped at this line on CI. The
        // claim below is agreement with `CadenceStoreSupport`, floor by floor, which is decidable
        // on a host that has no app group and still pins the exact path on one that does.
        let floors = CadenceAppGroupFloor.all(in: temporaryDirectory)

        // (1) Nothing named, and the near-misses. Asserted against `CadenceStoreSupport` rather
        //     than a literal so a later move of the app-group store cannot make this pass by
        //     drifting with it.
        let unredirected: [[String: String]] = [
            [:],
            ["CADENCE_LOCAL_STORE_ONLY": "1"],
            ["CADENCE_UI_TEST_MODE": "0"],
            ["CADENCE_UI_TEST_STORE_ID": ""],
            ["XCTestConfigurationFilePathButNotReally": "/tmp/x"],
        ]
        for environment in unredirected {
            #expect(
                CadenceUITestStoreDirectory.redirectedStoreDirectory(
                    in: environment,
                    temporaryDirectory: temporaryDirectory
                ) == nil,
                "\(environment) redirected the shipping app away from its own store"
            )
            for floor in floors {
                expectResolvesLikeTheAppGroupStore(
                    {
                        try StoreBackupManager.storeDirectoryURL(
                            in: environment,
                            temporaryDirectory: temporaryDirectory,
                            fileManager: $0
                        )
                    },
                    on: floor,
                    "\(environment) no longer resolves the app-group backups directory"
                )
            }
        }

        // (2) Each spelling of "this process is a test host", one at a time. `XCTestSessionIdentifier`
        //     is not decoration: a `swift test`-shaped run sets it without the configuration path.
        let testHost = temporaryDirectory
            .appendingPathComponent("CadenceTestsHostStore", isDirectory: true)
        let testHostEnvironments: [[String: String]] = [
            ["XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration"],
            ["XCTestSessionIdentifier": "9E1C-T1530"],
            ["CADENCE_UI_TEST_MODE": "1"],
        ]
        for environment in testHostEnvironments {
            let resolved = try StoreBackupManager.storeDirectoryURL(
                in: environment,
                temporaryDirectory: temporaryDirectory
            )
            #expect(resolved == testHost, "\(environment) resolved \(resolved.path)")
            for floor in floors {
                expectDiffersFromTheAppGroupStore(
                    resolved,
                    on: floor,
                    "\(environment) still resolves the signed-in person's store"
                )
            }
        }

        // (3) A `CadenceUITests` launch sets **both**, and the per-launch private store has to win:
        //     that directory is the one the sweep owns by `.owner` lock and the one
        //     `run-macos-app.sh stop` removes whole. Diverting it into the shared test-host folder
        //     would put two concurrent launches back in one store.
        let uiLaunch = ["CADENCE_UI_TEST_MODE": "1", "CADENCE_UI_TEST_STORE_ID": "t1530-ui"]
        #expect(
            try StoreBackupManager.storeDirectoryURL(
                in: uiLaunch,
                temporaryDirectory: temporaryDirectory
            ) == CadenceUITestStoreDirectory.rootDirectory(in: temporaryDirectory)
                .appendingPathComponent("t1530-ui", isDirectory: true),
            "a UI-test launch was diverted into the shared test-host store"
        )
    }

    /// The store and its backups have to ask **one** resolver, because two copies of the question
    /// is how they came to disagree in the first place.
    @Test func theStoreAndItsBackupsAskOneResolver() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")

        let storeResolver = try #require(
            CadenceSourceScan.declarationBody("private static func resolvedStoreURL(", in: source),
            "PersistenceController.resolvedStoreURL did not read as itself"
        )
        #expect(
            storeResolver.contains("CadenceUITestStoreDirectory.redirectedStoreDirectory()"),
            "the store resolver spells its own redirects again"
        )

        // **[[T-1852]] moved the redirect one level down, on purpose.** `storeDirectoryURL(in:)` is
        // now `storeDirectoryLocation(in:)` plus one `createDirectory`, so the creating and the
        // non-creating answers cannot drift apart — which is this test's own rule applied to the
        // pair it created. Asserted in both halves: the question is asked once, below, and the
        // creating form is the one that delegates to it.
        let backupResolver = try #require(
            CadenceSourceScan.declarationBody("static func storeDirectoryLocation(", in: source),
            "StoreBackupManager.storeDirectoryLocation did not read as itself"
        )
        #expect(
            backupResolver.contains("CadenceUITestStoreDirectory.redirectedStoreDirectory("),
            "the backup resolver is back to asking only about CADENCE_UI_TEST_STORE_ID"
        )
        #expect(
            backupResolver.contains("CadenceStoreSupport.storeDirectoryLocation(fileManager: fileManager)"),
            "the unredirected half creates the app-group store directory merely by being asked"
        )

        let creatingBackupResolver = try #require(
            CadenceSourceScan.declarationBody("static func storeDirectoryURL(", in: source),
            "StoreBackupManager.storeDirectoryURL did not read as itself"
        )
        #expect(
            creatingBackupResolver.contains("try storeDirectoryLocation("),
            "storeDirectoryURL spells the redirect itself again, so the two answers can disagree"
        )
        #expect(
            !creatingBackupResolver.contains("CadenceUITestStoreDirectory.redirectedStoreDirectory("),
            "the redirect question is asked in two places on StoreBackupManager again"
        )

        // The literal is the tell. While the test-host directory name was written out in
        // `PersistenceController.swift`, only the store knew about it. Over the stripped source:
        // the prose above `storeDirectoryURL(in:)` names it, and naming it is the point.
        #expect(
            CadenceSourceScan.matchCount("CadenceTestsHostStore", in: CadenceSourceScan.strippingComments(source)) == 0,
            "the test-host path is spelled in PersistenceController again, so the two can drift apart"
        )
        let directorySource = try CadenceSourceScan.sourceFile(
            "Cadence/Services/CadenceUITestStoreDirectory.swift"
        )
        #expect(
            directorySource.contains("static let testHostDirectoryName = \"CadenceTestsHostStore\""),
            "the one definition of the test-host directory name moved or was renamed"
        )
    }

    /// The write half. `PersistenceController.init` took `primaryStoreDirectoryURL()` and handed it
    /// to `performPendingRestoreIfNeeded` and `createBackupIfStoreExists` — a restore and a ~16 MB
    /// copy, both against the signed-in person's store, on a launch that had opened a private one.
    @Test func theStartupPreflightBacksUpTheStoreThisLaunchOpened() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        let body = CadenceSourceScan.strippingComments(try #require(
            // `"init()"`, not `"init() {"`. `declarationBody` resumes at the end of a prefix whose
            // parentheses are already closed and then takes the **next** `{` — so the longer
            // spelling hands back the body of `if Self.shouldResetStoreOnLaunch {`, four lines that
            // contain none of the four things asserted below and fail every one of them.
            CadenceSourceScan.declarationBody("init()", in: source),
            "PersistenceController.init did not read as itself"
        ))
        #expect(
            body.contains("CadenceUITestStoreDirectory.privateStoreDirectory()"),
            "the startup preflight never asks which store this launch opens"
        )
        #expect(
            body.contains("StoreBackupManager.createBackupIfStoreExists("),
            "the preflight no longer takes a startup backup, so this test is about nothing"
        )

        // The legacy migration is the deliberate exception and stays on the app-group path: it
        // copies into a target with no store items, and a private store directory is always empty,
        // so following the redirect would import the person's real data into the throwaway store.
        #expect(
            body.contains("appGroupDirectoryURL: storeDirectoryURL"),
            "the legacy migration no longer reads as itself"
        )
        let migrationIndex = try #require(body.range(of: "migrateLegacyStoreIfNeeded")?.lowerBound)
        let guardIndex = try #require(body.range(of: "if let privateStoreDirectoryURL {")?.lowerBound)
        #expect(
            guardIndex < migrationIndex,
            "the legacy migration runs before the launch knows whether it has a private store"
        )
    }
}

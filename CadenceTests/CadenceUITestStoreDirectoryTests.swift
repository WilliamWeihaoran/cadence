import Foundation
import Testing
@testable import Cadence

/// **T-1090.** `CadenceUITests` created one private SwiftData store per `XCUIApplication` launch
/// and nothing ever removed it: 71 directories, ~34 MB, when the backlog was first counted.
///
/// The mechanism is `CadenceUITestStoreDirectory`, and the two properties worth executing are the
/// two the ticket set against each other — it must remove the leaked directories, and it must not
/// remove one a concurrent run is using. Both are asserted here against real directories in a
/// scratch root, because both are filesystem behaviour rather than shape.
///
/// The UI target is not touched by the fix and so is not asserted on here. Why the removal lives in
/// the app rather than in a `tearDown` is written on `CadenceUITestStoreDirectory`, and it is a
/// measurement: `CadenceUITests-Runner.app` is sandboxed with a **read-only** exception over `/`,
/// so a test-side `removeItem` in the app's container cannot succeed.
struct CadenceUITestStoreDirectoryTests {

    /// A scratch root of this test's own, so a live run's stores are never in this suite's reach.
    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceUITestStoreDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A launch directory that carries an `.owner` file **nothing holds** — what a finished or
    /// crashed run leaves behind, which is the whole population the sweep exists to collect.
    private static func makeAbandonedStore(_ id: String, in root: URL) throws -> URL {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: directory.appendingPathComponent("default.store"))
        try Data().write(to: CadenceUITestStoreDirectory.ownerFileURL(in: directory))
        return directory
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - The leak, closed

    @Test func aSweepRemovesTheStoresNoLiveProcessOwnsAndSaysSoOnlyAfterTheyAreGone() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try Self.makeAbandonedStore("launch-1", in: root)
        let second = try Self.makeAbandonedStore("ui--[CadenceUITests testX]-2", in: root)
        let current = try Self.makeAbandonedStore("launch-current", in: root)

        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: ["launch-current"])

        #expect(report.removed == ["launch-1", "ui--[CadenceUITests testX]-2"])
        #expect(report.retained.isEmpty)
        #expect(report.failed.isEmpty)
        // The report is checked against the filesystem rather than believed.
        #expect(Self.exists(first) == false)
        #expect(Self.exists(second) == false)
        #expect(Self.exists(current), "the sweep removed the directory this launch is running in")
    }

    /// The hazard T-1090 named: *"a sweeper that deletes an id a **concurrent** run is using would
    /// corrupt a live test's store, which is worse than the leak."*
    ///
    /// `flock` answers it exactly rather than by age. This claims one id — which is what a second
    /// running app is — and then sweeps with nothing excluded at all, so the only thing that can
    /// save the live directory is the lock.
    @Test func aStoreALiveLaunchHoldsIsNotRemovedEvenWhenTheSweepIsNotToldToKeepIt() throws {
        let root = try Self.makeRoot()
        defer {
            CadenceUITestStoreDirectory.releaseOwnership(in: root)
            try? FileManager.default.removeItem(at: root)
        }

        let abandoned = try Self.makeAbandonedStore("launch-abandoned", in: root)
        let claim = CadenceUITestStoreDirectory.claimAndSweep(id: "launch-live", in: root)
        let live = root.appendingPathComponent("launch-live", isDirectory: true)

        // The claim sweeps as well as claims — that is the whole of what a launch does — so the
        // store the previous run abandoned is already gone before the second sweep below runs.
        #expect(claim.removed == ["launch-abandoned"])
        #expect(Self.exists(abandoned) == false)
        #expect(Self.exists(live), "claiming an id did not create its directory")
        #expect(Self.exists(CadenceUITestStoreDirectory.ownerFileURL(in: live)), "no .owner file was written")

        let next = try Self.makeAbandonedStore("launch-abandoned-2", in: root)
        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: [])

        #expect(report.retained == ["launch-live"])
        #expect(report.removed == ["launch-abandoned-2"], "the second sweep found nothing to remove")
        #expect(Self.exists(live), "the sweep removed a store a live launch holds the lock on")
        #expect(Self.exists(next) == false)
    }

    /// A directory from before this mechanism has no `.owner` file, so nothing can be established
    /// about it — and the conservative reading is the one that cannot corrupt a live run.
    ///
    /// This is a real decision and not an accident of the implementation: it means the sweep does
    /// **not** collect a pre-existing backlog. It costs nothing, because the backlog measured by
    /// T-1090 was cleared by hand before this landed, and every directory made from here on
    /// carries the file.
    @Test func aDirectoryWithNoOwnerFileIsRetainedRatherThanGuessedAbout() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("launch-legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: legacy.appendingPathComponent("default.store"))

        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: [])

        #expect(report.retained == ["launch-legacy"])
        #expect(report.removed.isEmpty)
        #expect(Self.exists(legacy))
    }

    /// A removal that did not happen is reported as `failed`, never as `removed`.
    ///
    /// This is the [[T-1066]] rule executed: `run-macos-app.sh stop` printed *"private store
    /// removed"* over a directory that was still on disk, and the fix was to re-`stat`. An
    /// unwritable parent is the cheapest way to make `removeItem` fail for real — the directory and
    /// its `.owner` file are untouched, so the lock is still takeable and the sweep still tries.
    @Test func aRemovalThatFailedIsReportedAsFailedAndNotAsRemoved() throws {
        let root = try Self.makeRoot()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }

        let stubborn = try Self.makeAbandonedStore("launch-stubborn", in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: [])

        #expect(report.failed == ["launch-stubborn"])
        #expect(report.removed.isEmpty)
        #expect(Self.exists(stubborn), "the test's premise is gone: the removal actually worked")
    }

    /// Non-vacuity for the three assertions above: a sweep over a root with nothing in it reports
    /// nothing, so an empty report is evidence of an empty root and not of a sweep that never ran.
    @Test func aSweepOverAnEmptyRootReportsNothing() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: [])

        #expect(report.isEmpty)
        #expect(CadenceUITestStoreDirectory.sweep(
            in: root.appendingPathComponent("never-created", isDirectory: true),
            keeping: []
        ).isEmpty, "a root that does not exist is not an error")
    }

    /// A loose file beside the launch directories is not a store and is not swept.
    @Test func onlyDirectoriesAreSwept() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let stray = root.appendingPathComponent("notes.txt")
        try Data("not a store".utf8).write(to: stray)
        _ = try Self.makeAbandonedStore("launch-1", in: root)

        let report = CadenceUITestStoreDirectory.sweep(in: root, keeping: [])

        #expect(report.removed == ["launch-1"])
        #expect(Self.exists(stray))
    }

    /// A claim that did not get the lock says so, and does not report from its intentions.
    ///
    /// The state is real: a second live process already owns that id, so the launch about to open
    /// the store is a second writer to it — and the moment the first one exits, the directory
    /// becomes sweepable underneath it. `flock` is per open-file-description, so a second
    /// descriptor in this process reproduces it exactly.
    @Test func aClaimThatCouldNotTakeTheLockReportsThatItDidNot() throws {
        let root = try Self.makeRoot()
        let directory = root.appendingPathComponent("launch-contended", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owner = CadenceUITestStoreDirectory.ownerFileURL(in: directory)
        try Data().write(to: owner)

        let held = open(owner.path, O_RDWR)
        #expect(held >= 0)
        #expect(flock(held, LOCK_EX | LOCK_NB) == 0, "the test could not take the lock it is standing in for")
        defer {
            close(held)
            CadenceUITestStoreDirectory.releaseOwnership(in: root)
            try? FileManager.default.removeItem(at: root)
        }

        #expect(CadenceUITestStoreDirectory.claimAndSweep(id: "launch-contended", in: root).claimedOwnership == false)
        // And the ordinary case, so the assertion above is a discrimination and not a constant.
        #expect(CadenceUITestStoreDirectory.claimAndSweep(id: "launch-free", in: root).claimedOwnership)
    }

    // MARK: - Which launches sweep, which only get a private store

    /// Every launch that names an id gets the redirect. `run-macos-app.sh` is the caller that sets
    /// `CADENCE_UI_TEST_STORE_ID` without `CADENCE_UI_TEST_MODE`, and it must keep getting one:
    /// that redirect is what keeps an agent's app off the user's real store.
    @Test func anyLaunchThatNamesAnIdGetsItsOwnStoreDirectory() {
        #expect(CadenceUITestStoreDirectory.directoryID(in: [:]) == nil)
        #expect(CadenceUITestStoreDirectory.directoryID(in: ["CADENCE_UI_TEST_STORE_ID": ""]) == nil)
        #expect(CadenceUITestStoreDirectory.directoryID(
            in: ["CADENCE_UI_TEST_STORE_ID": "agent-7"]
        ) == "agent-7")
        #expect(CadenceUITestStoreDirectory.directoryID(
            in: ["CADENCE_UI_TEST_STORE_ID": "ui-[CadenceUITests testA/testB]-1"]
        ) == "ui-[CadenceUITests testA-testB]-1", "a path separator in the id would escape the root")
    }

    /// **Only `CadenceUITests` sweeps**, and the cost of getting this wrong is on the other
    /// mechanism: `run-macos-app.sh stop` reports from the filesystem since [[T-1066]] and exits 1
    /// with `!! NOTHING REMOVED` when the path is not there. A sweep that collected an agent's
    /// abandoned store would make that refusal fire over a directory something else had cleaned.
    @Test func onlyAUITestLaunchClaimsAndSweeps() {
        #expect(CadenceUITestStoreDirectory.sweepingLaunchID(
            in: ["CADENCE_UI_TEST_STORE_ID": "launch-1", "CADENCE_UI_TEST_MODE": "1"]
        ) == "launch-1")
        #expect(CadenceUITestStoreDirectory.sweepingLaunchID(
            in: ["CADENCE_UI_TEST_STORE_ID": "agent-7", "CADENCE_LOCAL_STORE_ONLY": "1"]
        ) == nil, "run-macos-app.sh's launch swept, and `stop` will report a store it did not remove")
        #expect(CadenceUITestStoreDirectory.sweepingLaunchID(
            in: ["CADENCE_UI_TEST_MODE": "1"]
        ) == nil)
    }

    /// The gate above is one half; this is the other, and it holds even if the gate is bypassed.
    /// A launch that does not claim writes no `.owner` file, and
    /// `aDirectoryWithNoOwnerFileIsRetainedRatherThanGuessedAbout` is what that costs it: nothing
    /// removes it, so an agent's live app cannot be swept out from under it either way.
    @Test func aLaunchThatDoesNotClaimLeavesNoOwnerFileToTake() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let agentRun = root.appendingPathComponent("agent-7", isDirectory: true)
        try FileManager.default.createDirectory(at: agentRun, withIntermediateDirectories: true)

        #expect(Self.exists(CadenceUITestStoreDirectory.ownerFileURL(in: agentRun)) == false)
        #expect(CadenceUITestStoreDirectory.sweep(in: root, keeping: []).retained == ["agent-7"])
        #expect(Self.exists(agentRun))
    }

    // MARK: - The wiring, which no unit test can reach through `init()`

    /// `PersistenceController.init()` is where the claim has to happen, and it happens **after**
    /// the `CADENCE_RESET_STORE` branch — a lock taken on a file that branch then deletes owns
    /// nothing. `init()` cannot be exercised here (it opens a real container off a process-wide
    /// environment variable), so the order is pinned in source.
    @Test func theClaimRunsAtLaunchAndAfterTheStoreReset() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("init()", in: source),
            "PersistenceController.init() was renamed"
        )
        let reset = try #require(body.range(of: "deleteResolvedStoreDirectory()"))
        let claim = try #require(
            body.range(of: "claimUITestStoreDirectoryIfNeeded()"),
            "the launch no longer claims or sweeps its private UI-test store (T-1090)"
        )
        #expect(reset.upperBound < claim.lowerBound, "the claim moved above the reset that deletes it")
    }

    /// One spelling of the directory the stores live in.
    ///
    /// `PersistenceController` used to carry its own `"CadenceUITestStores"` literal beside the one
    /// the sweeper walks; two spellings of one path is how a sweep comes to run over a directory
    /// nothing writes, which is the shape [[T-1066]] was.
    @Test func theStoreRootIsNamedInExactlyOnePlaceUnderCadence() throws {
        var naming: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            if source.contains("\"CadenceUITestStores\"") {
                naming.append((path as NSString).lastPathComponent)
            }
        }
        #expect(naming == ["CadenceUITestStoreDirectory.swift"])
    }
}

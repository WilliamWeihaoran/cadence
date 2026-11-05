import Foundation
import Testing
@testable import Cadence

/// **T-1840 — `Delete Account & Data` also deletes the recovery store and the earlier store
/// folders (owner decision 2026-10-22).**
///
/// [[T-1680]] made those folders visible in Data Safety and had the reset say it left them. The
/// owner then decided the reset takes them, with three constraints this suite holds:
///
/// 1. the recovery store **this launch is running on** is skipped — removing files under an open
///    `ModelContainer` is a different bug;
/// 2. the typed-phrase gate names the recovery store before the button is live (pinned in
///    `CadenceUnmanagedStoreDirectoryTests.theResetCopyNamesTheStoreFoldersItDeletes`);
/// 3. `migrateLegacyStoreIfNeeded` still behaves once the earlier locations are emptied.
///
/// **[[T-8981]] (owner decision 2026-11-04) added the fourth thing the reset takes**: the
/// `Cadence Store Backups` folders beside those earlier store locations. T-1840 deliberately took
/// exact-name store items only, so each of those — a full copy of a Cadence store — survived
/// "delete all my data" and went on being listed in Data Safety. The owner chose to delete them
/// **and** name them in the confirmation first; a silent delete was refused rather than merely not
/// chosen. `theResetDeletesTheBackupsBesideAnEarlierStoreLocationAndTheGateSaysSoFirst` holds both
/// halves in one test on purpose: a test that only checked the deletion would let the app start
/// destroying someone's last recovery copy without telling them.
///
/// Every fixture is under this process's own temporary directory; nothing here passes a default
/// legacy or recovery path, which name the signed-in person's home.
@MainActor
struct CadenceDataResetStoreFolderTests {

    // MARK: - Fixture

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1840-\(UUID().uuidString)", isDirectory: true)
    }

    private func plant(_ names: [String], in directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for name in names {
            try Data(repeating: 0x2A, count: 1024).write(to: directoryURL.appendingPathComponent(name))
        }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private struct Tree {
        let root: URL
        let live: URL
        let liveRecovery: URL
        let legacy: URL
        let legacyBackup: URL
        let legacyStray: URL
        let absentLegacy: URL
    }

    /// The machine's shape: the live store with a `Recovery/` child, one earlier location holding a
    /// store **and** a `Cadence Store Backups` folder and an unrelated file beside it, and one
    /// earlier location that does not exist.
    private func plantTree() throws -> Tree {
        let root = makeRoot()
        let live = root.appendingPathComponent("Group/Cadence", isDirectory: true)
        let liveRecovery = live.appendingPathComponent("Recovery", isDirectory: true)
        let legacy = root.appendingPathComponent("Containers/Application Support/Cadence", isDirectory: true)
        let legacyBackup = legacy
            .appendingPathComponent("Cadence Store Backups/2026-01-01-startup", isDirectory: true)
        let legacyStray = legacy.appendingPathComponent("notes.txt")
        try plant(["default.store", "default.store-wal"], in: live)
        try plant(["recovery.store", "recovery.store-wal"], in: liveRecovery)
        try plant(["default.store", "default.store-wal", "default.store-shm"], in: legacy)
        try plant(["default.store"], in: legacyBackup)
        try Data("keep".utf8).write(to: legacyStray)
        return Tree(
            root: root,
            live: live,
            liveRecovery: liveRecovery,
            legacy: legacy,
            legacyBackup: legacyBackup,
            legacyStray: legacyStray,
            absentLegacy: root.appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)
        )
    }

    private func sweep(_ tree: Tree, runningOnRecoveryStore: Bool) throws -> Int {
        // `live` is also a legacy candidate, as it is on a machine that never moved: the sweep
        // must exclude the open store exactly as the listing does.
        try StoreBackupManager.deleteUnusedStoreFoldersForDataReset(
            liveStoreDirectoryURL: tree.live,
            recoveryStoreDirectories: [tree.liveRecovery],
            legacyStoreDirectories: [tree.legacy, tree.absentLegacy, tree.live],
            runningOnRecoveryStore: runningOnRecoveryStore
        )
    }

    // MARK: - It deletes them

    @Test func theResetEmptiesTheRecoveryStoreAndEveryEarlierStoreLocation() throws {
        let tree = try plantTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let listedBefore = StoreBackupManager.unmanagedStoreDirectories(
            liveStoreDirectoryURL: tree.live,
            recoveryStoreDirectories: [tree.liveRecovery],
            legacyStoreDirectories: [tree.legacy, tree.absentLegacy, tree.live]
        )
        #expect(listedBefore.count == 2, "non-vacuity: the fixture lists \(listedBefore.map(\.url.path))")

        let emptied = try sweep(tree, runningOnRecoveryStore: false)

        // Three directories: the recovery store, the earlier store location, and — since
        // [[T-8981]] — the backups folder beside that earlier location.
        #expect(emptied == 3, "the sweep emptied \(emptied) folders")
        for name in ["recovery.store", "recovery.store-wal"] {
            #expect(!exists(tree.liveRecovery.appendingPathComponent(name)), "the recovery store's \(name) survived the reset")
        }
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            #expect(!exists(tree.legacy.appendingPathComponent(name)), "the earlier store's \(name) survived the reset")
        }
        #expect(
            StoreBackupManager.unmanagedStoreDirectories(
                liveStoreDirectoryURL: tree.live,
                recoveryStoreDirectories: [tree.liveRecovery],
                legacyStoreDirectories: [tree.legacy, tree.absentLegacy, tree.live]
            ).isEmpty,
            "Data Safety would still list a store folder after the reset"
        )

        // The open store is not one of them.
        #expect(exists(tree.live.appendingPathComponent("default.store")), "the reset deleted the store this launch has open")
        #expect(exists(tree.live.appendingPathComponent("default.store-wal")))
        // Store files and backups go; a stray file beside the old store stays, and nothing is
        // created where nothing was. [[T-8981]] reversed the backups half of this assertion — it
        // read "the sweep reached a backups folder" until the owner decided the reset takes them;
        // the test that holds that reversal together with the confirmation copy is below.
        #expect(
            !exists(tree.legacyBackup.appendingPathComponent("default.store")),
            "a full copy of the store survived Delete Account & Data (T-8981)"
        )
        #expect(exists(tree.legacyStray), "the sweep deleted a file that is not a store item or a backup")
        #expect(!exists(tree.absentLegacy), "the sweep created a folder it was only asked about")
    }

    /// **[[T-1840]] (1).** That launch is running on the recovery store.
    @Test func theRecoveryStoreThisLaunchIsRunningOnIsNeverTouched() throws {
        let tree = try plantTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }

        let emptied = try sweep(tree, runningOnRecoveryStore: true)

        // Two: the earlier store location and its backups folder ([[T-8981]]). The skip is of the
        // recovery store only, and the backups beside an earlier location are not conditional on
        // which store this launch is running on.
        #expect(emptied == 2)
        #expect(exists(tree.liveRecovery.appendingPathComponent("recovery.store")), "the reset deleted the store this launch is running on")
        #expect(exists(tree.liveRecovery.appendingPathComponent("recovery.store-wal")))
        // ...and the earlier location still goes, so the skip is narrow.
        #expect(!exists(tree.legacy.appendingPathComponent("default.store")))
    }

    /// Under a test or agent launch only folders inside the process's temporary directory may be
    /// touched — the gate the backup writers already pass ([[T-3045]] (3)). The default legacy
    /// candidates name the signed-in person's home, so this is what makes a mistaken default call
    /// from a test harmless. A refusal does not stop the other folders.
    @Test func aFolderOutsideTheTemporaryDirectoryIsRefusedAndTheRestStillGo() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let allowedRoot = root.appendingPathComponent("Allowed", isDirectory: true)
        let live = allowedRoot.appendingPathComponent("Live/Cadence", isDirectory: true)
        let allowedRecovery = live.appendingPathComponent("Recovery", isDirectory: true)
        let outside = root.appendingPathComponent("Elsewhere/Cadence", isDirectory: true)
        try plant(["default.store"], in: live)
        try plant(["recovery.store"], in: allowedRecovery)
        try plant(["default.store"], in: outside)
        let environment = ProcessInfo.processInfo.environment
        #expect(
            CadenceUITestStoreDirectory.redirectedStoreDirectory(in: environment, temporaryDirectory: allowedRoot) != nil,
            "non-vacuity: this test host is not a redirected launch, so the gate would allow everything"
        )

        #expect(throws: StoreBackupManager.BackupWriteRefusal.self) {
            try StoreBackupManager.deleteUnusedStoreFoldersForDataReset(
                liveStoreDirectoryURL: live,
                recoveryStoreDirectories: [allowedRecovery],
                legacyStoreDirectories: [outside],
                runningOnRecoveryStore: false,
                environment: environment,
                temporaryDirectory: allowedRoot
            )
        }
        #expect(exists(outside.appendingPathComponent("default.store")), "a test launch deleted a folder outside its temporary directory")
        #expect(!exists(allowedRecovery.appendingPathComponent("recovery.store")), "one refused folder stopped the rest of the sweep")
    }

    // MARK: - [[T-8981]]: the backups beside the earlier store locations

    /// **The deletion and the sentence that makes it fair, in one test.**
    ///
    /// [[T-8981]], owner decision 2026-11-04. [[T-1840]] took exact-name store items only, so a
    /// `Cadence Store Backups` folder beside an earlier store location survived the reset — and
    /// each of those is a *full copy of a Cadence store*, so after asking to have their data
    /// deleted the person still had their data on disk and Data Safety went on listing it. The
    /// owner was given three options — delete and say so, leave them, delete silently — and took
    /// the first; the third was **refused**, not merely not chosen, because destroying someone's
    /// last recovery copy without telling them is how a store is lost by a person who thought they
    /// still had it.
    ///
    /// So the two halves are asserted together rather than in two tests. A test that only checked
    /// the deletion would stay green through exactly the regression the owner refused: the app
    /// quietly destroying backups it never named. The gate copy is checked on **both** branches,
    /// because these backups are taken whichever store the launch is running on.
    @Test func theResetDeletesTheBackupsBesideAnEarlierStoreLocationAndTheGateSaysSoFirst() throws {
        let tree = try plantTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        // Backups beside the **live** store as well: those are `deleteAllBackupsForDataReset`'s,
        // and this step must not be a second thing that reaches them.
        let liveBackup = tree.live
            .appendingPathComponent("Cadence Store Backups/2026-02-02-manual", isDirectory: true)
        try plant(["default.store"], in: liveBackup)

        let legacyBackupRoot = tree.legacy
            .appendingPathComponent("Cadence Store Backups", isDirectory: true)
        let listedBefore = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: tree.live,
            legacyStoreDirectories: [tree.legacy, tree.absentLegacy, tree.live]
        )
        #expect(
            listedBefore.map(\.url.standardizedFileURL.path)
                == [legacyBackupRoot.standardizedFileURL.path],
            "non-vacuity: Data Safety lists \(listedBefore.map(\.url.path)) before the reset"
        )
        #expect(listedBefore.first?.backupCount == 1, "non-vacuity: the fixture's backup was not counted")

        // HALF ONE — the confirmation names them before the irreversible button, and says what
        // losing one costs and what a reader can do about it.
        for runningOnRecoveryStore in [false, true] {
            let gate = CadenceUnmanagedStoreCopy.resetGateDeletesThem(
                runningOnRecoveryStore: runningOnRecoveryStore
            )
            #expect(
                gate.contains("Cadence Store Backups"),
                "the gate does not name the backups folders it deletes (runningOnRecoveryStore: \(runningOnRecoveryStore))"
            )
            #expect(
                gate.contains("complete copy of a Cadence store"),
                "the gate names the folders without saying what one of them holds (runningOnRecoveryStore: \(runningOnRecoveryStore))"
            )
            #expect(
                gate.contains("copy it somewhere else before you continue"),
                "the gate warns without saying what a reader can do about it (runningOnRecoveryStore: \(runningOnRecoveryStore))"
            )
        }

        // HALF TWO — and the reset really reaches them.
        let emptied = try sweep(tree, runningOnRecoveryStore: false)

        #expect(emptied == 3, "the sweep emptied \(emptied) folders")
        #expect(
            !exists(tree.legacyBackup),
            "a full copy of the store survived Delete Account & Data (T-8981)"
        )
        #expect(
            StoreBackupManager.unmanagedBackupDirectories(
                liveStoreDirectoryURL: tree.live,
                legacyStoreDirectories: [tree.legacy, tree.absentLegacy, tree.live]
            ).isEmpty,
            "Data Safety would still list a full copy of the store after the reset"
        )
        // Only what the row counted goes: the root folder stays, exactly as an emptied store
        // folder does, and a file that is not a backup is still not this sweep's.
        #expect(exists(legacyBackupRoot), "the sweep removed the folder rather than the backups in it")
        #expect(exists(tree.legacyStray), "the sweep deleted a file that is not a backup")
        // ...and the live store's backups are not this step's to take.
        #expect(
            exists(liveBackup.appendingPathComponent("default.store")),
            "this step reached the live store's own backups, which deleteAllBackupsForDataReset takes"
        )
    }

    /// The per-folder gate covers the backups half too ([[T-3045]] (3), [[T-8981]]).
    ///
    /// `outside` holds **no** store items, only backups, so the refusal this asserts can only have
    /// come from the backups loop — if the gate there were dropped, the store half would still have
    /// nothing to refuse and the test would go red rather than passing for the wrong reason. A
    /// refusal does not stop the folders that pass.
    @Test func aBackupsFolderOutsideTheTemporaryDirectoryIsRefusedAndTheRestStillGo() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let allowedRoot = root.appendingPathComponent("Allowed", isDirectory: true)
        let live = allowedRoot.appendingPathComponent("Live/Cadence", isDirectory: true)
        let allowedLegacy = allowedRoot.appendingPathComponent("Earlier/Cadence", isDirectory: true)
        let allowedBackup = allowedLegacy
            .appendingPathComponent("Cadence Store Backups/2026-01-01-startup", isDirectory: true)
        let outside = root.appendingPathComponent("Elsewhere/Cadence", isDirectory: true)
        let outsideBackup = outside
            .appendingPathComponent("Cadence Store Backups/2026-01-01-startup", isDirectory: true)
        try plant(["default.store"], in: live)
        try plant(["default.store"], in: allowedLegacy)
        try plant(["default.store"], in: allowedBackup)
        try plant(["default.store"], in: outsideBackup)

        let environment = ProcessInfo.processInfo.environment
        #expect(
            CadenceUITestStoreDirectory.redirectedStoreDirectory(in: environment, temporaryDirectory: allowedRoot) != nil,
            "non-vacuity: this test host is not a redirected launch, so the gate would allow everything"
        )
        let listed = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: live,
            legacyStoreDirectories: [allowedLegacy, outside]
        )
        #expect(listed.count == 2, "non-vacuity: the fixture listed \(listed.map(\.url.path))")

        #expect(throws: StoreBackupManager.BackupWriteRefusal.self) {
            try StoreBackupManager.deleteUnusedStoreFoldersForDataReset(
                liveStoreDirectoryURL: live,
                recoveryStoreDirectories: [],
                legacyStoreDirectories: [allowedLegacy, outside],
                runningOnRecoveryStore: false,
                environment: environment,
                temporaryDirectory: allowedRoot
            )
        }
        #expect(
            exists(outsideBackup.appendingPathComponent("default.store")),
            "a test launch deleted backups outside its temporary directory"
        )
        #expect(!exists(allowedBackup), "one refused backups folder stopped the rest of the sweep")
    }

    // MARK: - [[T-1840]] (3): the migration still behaves without them

    /// `migrateLegacyStoreIfNeeded` reads the earlier store locations on every launch whose
    /// app-group store is empty. After the reset empties them it must neither throw nor import
    /// anything — the control first shows the same fixture *would* have migrated.
    @Test func theLegacyMigrationFindsNothingAndThrowsNothingOnceTheEarlierLocationsAreGone() throws {
        let tree = try plantTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }

        let controlGroup = tree.root.appendingPathComponent("ControlGroup/Cadence", isDirectory: true)
        let migratedFrom = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
            appGroupDirectoryURL: controlGroup,
            candidateLegacyDirectories: [tree.liveRecovery, tree.legacy, tree.absentLegacy]
        )
        #expect(
            migratedFrom?.standardizedFileURL.path == tree.legacy.standardizedFileURL.path,
            "non-vacuity: the fixture's earlier location would not have migrated"
        )

        _ = try sweep(tree, runningOnRecoveryStore: false)

        let freshGroup = tree.root.appendingPathComponent("FreshGroup/Cadence", isDirectory: true)
        let afterReset = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
            appGroupDirectoryURL: freshGroup,
            candidateLegacyDirectories: [tree.liveRecovery, tree.legacy, tree.absentLegacy]
        )
        #expect(afterReset == nil, "the migration imported from a location the reset emptied")
        #expect(CadenceStoreSupport.storeItemURLs(in: freshGroup).isEmpty, "the migration wrote store files after the reset")
    }

    // MARK: - The reset reaches the step, and a refusal is reported

    /// The third step runs when both before it fail, and its own failure is reported in the
    /// outcome rather than thrown — the store is already gone by then (T-1313).
    @Test func theStoreFolderStepRunsAfterRefusedBackupStepsAndItsRefusalIsReported() {
        let refusal = CocoaError(.fileWriteNoPermission)
        var storeFoldersRan = false
        let outcome = PrivacyDataResetService.removeStoredBackups(
            deletingBackups: { throw refusal },
            deletingRetainedOriginals: { throw refusal },
            deletingUnusedStoreFolders: { storeFoldersRan = true; return 2 }
        )
        #expect(storeFoldersRan, "a refused backup step skipped the store folders (T-1840)")

        let onlyFoldersRefused = PrivacyDataResetService.removeStoredBackups(
            deletingBackups: { 3 },
            deletingRetainedOriginals: { 0 },
            deletingUnusedStoreFolders: { throw refusal }
        )
        #expect(onlyFoldersRefused.removedBackupCount == 3)
        #expect(
            onlyFoldersRefused.retainedBackupReason == refusal.localizedDescription,
            "a refused store-folder sweep is silent"
        )
        #expect(outcome.retainedBackupReason == refusal.localizedDescription)
    }
}

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

        #expect(emptied == 2, "the sweep emptied \(emptied) folders")
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
        // Only store files go: the backups folder and a stray file beside the old store stay, and
        // nothing is created where nothing was.
        #expect(exists(tree.legacyBackup.appendingPathComponent("default.store")), "the sweep reached a backups folder")
        #expect(exists(tree.legacyStray), "the sweep deleted a file that is not a store item")
        #expect(!exists(tree.absentLegacy), "the sweep created a folder it was only asked about")
    }

    /// **[[T-1840]] (1).** That launch is running on the recovery store.
    @Test func theRecoveryStoreThisLaunchIsRunningOnIsNeverTouched() throws {
        let tree = try plantTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }

        let emptied = try sweep(tree, runningOnRecoveryStore: true)

        #expect(emptied == 1)
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

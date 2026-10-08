import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Two holes in the restore path, both from the `backupaudit` pass, every fixture a temp directory.
///
/// **T-3045 (1).** `quarantinePendingRestore` writes a `FailedRestoreRecord` and clears the pending
/// key; the same launch's startup backup then runs `cleanUpAutomaticBackups`, which exempted only
/// the pending URL — so the backup the failed-restore banner names was ordinary retention fodder.
///
/// **T-3044 (c).** Restore validity was never checked: `isBackupDirectory` is existence only and
/// `verifyStagedRestore` compares sizes, which a zero-byte `default.store` passes. The gate landed
/// here refuses an empty store file; the SQLite-header half is still open (see the gate's comment).
@MainActor
struct CadenceRestoreSafetyGateTests {
    // MARK: - Fixtures

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceRestoreSafetyGateTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedStore(in root: URL, marker: String) throws {
        try Data(marker.utf8).write(to: root.appendingPathComponent("default.store"))
        try Data("\(marker)-wal".utf8).write(to: root.appendingPathComponent("default.store-wal"))
    }

    private func marker(in root: URL) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("default.store")) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func relabel(_ backup: URL, as reason: StoreBackupReason, createdAt: Date) throws {
        let url = backup.appendingPathComponent("manifest.json")
        var manifest = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        manifest["reason"] = reason.rawValue
        manifest["createdAt"] = createdAt.ISO8601Format()
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
    }

    /// Seven pre-restore backups, oldest first. Retention keeps the newest five, so the oldest two
    /// are removable by any sweep that does not exempt them.
    private func sevenPreRestoreBackups(in root: URL) throws -> [URL] {
        var backups: [URL] = []
        for index in 0..<7 {
            try seedStore(in: root, marker: "historical-\(index)")
            backups.append(try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            )))
        }
        for (index, backup) in backups.enumerated() {
            try relabel(backup, as: .preRestore, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
        }
        return backups
    }

    /// Schedule a restore from `backup`, then make it fail in staged verification for a reason
    /// that has nothing to do with the validity gate — the manifest claims a sidecar that is gone.
    private func failARestore(from backup: URL, in root: URL, defaults: UserDefaults) throws {
        try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
        try FileManager.default.removeItem(at: backup.appendingPathComponent("default.store-wal"))
        #expect(throws: (any Error).self) {
            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)
        }
    }

    // MARK: - T-3045 (1): the backup a failed-restore banner names survives retention

    @Test func theSameLaunchsStartupBackupDoesNotPurgeTheBackupTheFailedRestoreBannerNames() throws {
        try withTemporaryDefaults("CadenceTests.restoreSafetyGate") { defaults in
            let root = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let backups = try sevenPreRestoreBackups(in: root)
            let selected = try #require(backups.first)
            try seedStore(in: root, marker: "live")

            try failARestore(from: selected, in: root, defaults: defaults)
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.backupURL.standardizedFileURL == selected.standardizedFileURL)
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)

            // What the launch does next (`PersistenceController`, the `.startup` backup).
            _ = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .startup,
                storeDirectoryURL: root,
                defaults: defaults
            ))

            #expect(
                FileManager.default.fileExists(atPath: selected.path),
                "the startup sweep purged the backup the failed-restore banner names"
            )
            // ...while retention still prunes the unprotected one beside it.
            #expect(!FileManager.default.fileExists(atPath: backups[1].path))
            #expect(backups[2...].allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    @Test func theExemptionLastsExactlyAsLongAsTheFailedRestoreRecord() throws {
        try withTemporaryDefaults("CadenceTests.restoreSafetyGate") { defaults in
            let root = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let backups = try sevenPreRestoreBackups(in: root)
            let selected = try #require(backups.first)
            try seedStore(in: root, marker: "live")
            try failARestore(from: selected, in: root, defaults: defaults)

            let removedWhileRecorded = try StoreBackupManager.cleanUpAutomaticBackups(
                storeDirectoryURL: root,
                defaults: defaults
            )
            #expect(removedWhileRecorded == 1)
            #expect(FileManager.default.fileExists(atPath: selected.path))

            StoreBackupManager.clearFailedRestore(defaults: defaults)
            let removedAfterClearing = try StoreBackupManager.cleanUpAutomaticBackups(
                storeDirectoryURL: root,
                defaults: defaults
            )
            #expect(removedAfterClearing == 1)
            #expect(!FileManager.default.fileExists(atPath: selected.path))
        }
    }

    // MARK: - T-3044 (c): the validity gate

    @Test func aRealSwiftDataStorePassesTheGateAndAnEmptyOrMissingFileDoesNot() throws {
        let root = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realStore = root.appendingPathComponent("real.store")
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: realStore
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: "A row"))
        try context.save()
        #expect(StoreBackupManager.storeFileIsNonEmpty(at: realStore))

        let oneByte = root.appendingPathComponent("one-byte.store")
        try Data([0x53]).write(to: oneByte)
        #expect(StoreBackupManager.storeFileIsNonEmpty(at: oneByte))

        let empty = root.appendingPathComponent("empty.store")
        try Data().write(to: empty)
        #expect(!StoreBackupManager.storeFileIsNonEmpty(at: empty))
        #expect(!StoreBackupManager.storeFileIsNonEmpty(at: root.appendingPathComponent("missing.store")))
        #expect(!StoreBackupManager.storeFileIsNonEmpty(at: root))
    }

    @Test func schedulingARestoreRefusesAZeroByteStoreFile() throws {
        try withTemporaryDefaults("CadenceTests.restoreSafetyGate") { defaults in
            let root = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try seedStore(in: root, marker: "the-backup")
            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            ))
            try Data().write(to: backup.appendingPathComponent("default.store"))

            #expect(throws: CocoaError(.fileReadCorruptFile)) {
                try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
            }
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(!CadenceStoreSupport.restoreIsPending(inStoreDirectory: root))
        }
    }

    /// The backup was valid when the restore was scheduled and was emptied before the next launch
    /// applied it. Size verification passes — the staged copy matches the emptied source exactly —
    /// so only the staged validity gate stands between it and the live store.
    @Test func stagedVerificationRefusesAZeroByteStoreFileBeforeAnythingLiveIsTouched() throws {
        try withTemporaryDefaults("CadenceTests.restoreSafetyGate") { defaults in
            let root = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try seedStore(in: root, marker: "the-backup")
            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            ))
            try seedStore(in: root, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
            try Data().write(to: backup.appendingPathComponent("default.store"))
            let backupsBefore = StoreBackupManager.listBackups(storeDirectoryURL: root).count

            #expect(throws: CocoaError(.fileReadCorruptFile)) {
                try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)
            }

            #expect(marker(in: root) == "what-is-live")
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.retainedOriginalsPath == nil)
            // Refused before the pre-restore safety backup, so no backup was added either.
            #expect(StoreBackupManager.listBackups(storeDirectoryURL: root).count == backupsBefore)
        }
    }

    @Test func aNonEmptyBackupStillRestores() throws {
        try withTemporaryDefaults("CadenceTests.restoreSafetyGate") { defaults in
            let root = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try seedStore(in: root, marker: "the-backup")
            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            ))
            try seedStore(in: root, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)

            #expect(marker(in: root) == "the-backup")
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) == nil)
        }
    }

    // MARK: - T-3045 (2): a retained-originals folder is named on screen

    /// The listing Settings → Data Safety reads answers the folders beside **this launch's** store.
    /// Planted under the test host's own redirected store, which is checked to be inside the
    /// temporary directory before anything is written.
    @Test func theNoArgumentListingNamesARetainedFolderBesideThisLaunchsStore() throws {
        let liveStore = try StoreBackupManager.storeDirectoryLocation(in: ProcessInfo.processInfo.environment)
        try #require(
            CadenceUITestStoreDirectory.isPath(liveStore, inside: FileManager.default.temporaryDirectory),
            "this process's store is not redirected into tmp; refusing to plant anything beside it"
        )
        let retained = liveStore.appendingPathComponent(
            "Cadence Unrestored Store Files 20261007-120000-restoreguard-\(UUID().uuidString)",
            isDirectory: true
        )
        let storeExisted = FileManager.default.fileExists(atPath: liveStore.path)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: retained)
            if !storeExisted { try? FileManager.default.removeItem(at: liveStore) }
        }
        let listed = StoreBackupManager.retainedUnrestoredOriginalDirectories()
            .map(\.standardizedFileURL.path)
        #expect(listed.filter { $0 == retained.standardizedFileURL.path }.count == 1)
    }

    /// The view reads that listing exactly once, renders it through a row that can only reveal,
    /// and nothing in the file can delete a retained folder.
    @Test func theMacDataSafetyScreenListsRetainedFoldersAndCannotDeleteThem() throws {
        let path = "Cadence/macOS/Views/SettingsDataSafetySection.swift"
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        #expect(code.contains("struct SettingsDataSafetySection"), "non-vacuity: wrong file")
        func count(_ needle: String) -> Int { code.components(separatedBy: needle).count - 1 }
        #expect(count("StoreBackupManager.retainedUnrestoredOriginalDirectories()") == 1)
        #expect(count("RetainedUnrestoredOriginalsRow(") == 1)
        #expect(count("ForEach(Array(retainedUnrestoredDirectories.enumerated())") == 1)
        #expect(count("deleteRetainedUnrestoredOriginals") == 0)

        let rowStart = try #require(code.range(of: "private struct RetainedUnrestoredOriginalsRow"))
        let rest = code[rowStart.upperBound...]
        let rowEnd = rest.range(of: "private struct ")?.lowerBound ?? rest.endIndex
        let row = String(rest[..<rowEnd])
        #expect(row.contains("onReveal"), "non-vacuity: the row segment was not found")
        for forbidden in ["removeItem", "destructive", "delete", "Delete"] {
            #expect(!row.contains(forbidden), "the retained-originals row mentions \(forbidden)")
        }
    }

    // MARK: - T-3045 (3): backup writers refuse a non-temporary directory under a test launch

    @Test func theWriteGuardAllowsEverythingInTheShippingAppAndOnlyTmpUnderATestLaunch() {
        let tmp = URL(fileURLWithPath: "/var/folders/xy/T", isDirectory: true)
        let real = URL(fileURLWithPath: "/Users/someone/Library/Group Containers/group.x/Cadence", isDirectory: true)
        let legacy = URL(fileURLWithPath: "/Users/someone/Library/Containers/x/Data/Library/Application Support/Cadence")
        let shipping: [String: String] = [:]
        let unitTests = ["XCTestConfigurationFilePath": "/x.xctestconfiguration"]
        let agentLaunch = ["CADENCE_UI_TEST_STORE_ID": "agent-1"]

        // The shipping app: no redirect, so nothing changes.
        for url in [real, legacy, tmp] {
            #expect(CadenceUITestStoreDirectory.mayWriteBackups(inStoreDirectory: url, environment: shipping, temporaryDirectory: tmp))
        }
        for environment in [unitTests, agentLaunch] {
            #expect(!CadenceUITestStoreDirectory.mayWriteBackups(inStoreDirectory: real, environment: environment, temporaryDirectory: tmp))
            #expect(!CadenceUITestStoreDirectory.mayWriteBackups(inStoreDirectory: legacy, environment: environment, temporaryDirectory: tmp))
            #expect(CadenceUITestStoreDirectory.mayWriteBackups(
                inStoreDirectory: tmp.appendingPathComponent("Fixture.\(UUID().uuidString)"),
                environment: environment, temporaryDirectory: tmp
            ))
            // The `/private` alias of tmp is tmp; a `..` walk out of it is not; neither is a sibling
            // whose name merely starts with tmp's.
            #expect(CadenceUITestStoreDirectory.mayWriteBackups(
                inStoreDirectory: URL(fileURLWithPath: "/private/var/folders/xy/T/Fixture"),
                environment: environment, temporaryDirectory: tmp
            ))
            #expect(!CadenceUITestStoreDirectory.mayWriteBackups(
                inStoreDirectory: URL(fileURLWithPath: "/var/folders/xy/T/../../../Users/someone/Cadence"),
                environment: environment, temporaryDirectory: tmp
            ))
            #expect(!CadenceUITestStoreDirectory.mayWriteBackups(
                inStoreDirectory: URL(fileURLWithPath: "/var/folders/xy/T-other/Cadence"),
                environment: environment, temporaryDirectory: tmp
            ))
        }
    }

    /// Every entry point that writes into, thins or removes a backups directory (or the retained
    /// originals) refuses **before** touching the filesystem. The probe directory does not exist,
    /// so an unguarded call would return quietly (`nil` / `0`) rather than throw.
    @Test func everyBackupWriterRefusesANonTemporaryStoreDirectoryInThisTestProcess() throws {
        #expect(CadenceUITestStoreDirectory.redirectedStoreDirectory() != nil, "non-vacuity: this process is not a redirected launch")
        let probe = URL(fileURLWithPath: "/CadenceRestoreGuardProbe-\(UUID().uuidString)", isDirectory: true)
        let refusal = StoreBackupManager.BackupWriteRefusal(storeDirectoryPath: probe.path)

        #expect(throws: refusal) {
            try StoreBackupManager.createBackupIfStoreExists(reason: .manual, storeDirectoryURL: probe)
        }
        #expect(throws: refusal) {
            try StoreBackupManager.cleanUpAutomaticBackups(storeDirectoryURL: probe)
        }
        #expect(throws: refusal) {
            try StoreBackupManager.deleteAllBackups(storeDirectoryURL: probe)
        }
        #expect(throws: refusal) {
            try StoreBackupManager.deleteRetainedUnrestoredOriginals(storeDirectoryURL: probe)
        }
        #expect(!FileManager.default.fileExists(atPath: probe.path))
    }

    /// And a temp directory still works through the same entry points.
    @Test func theSameWritersStillRunInsideTheTemporaryDirectory() throws {
        let root = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try seedStore(in: root, marker: "live")
        _ = try #require(try StoreBackupManager.createBackupIfStoreExists(reason: .manual, storeDirectoryURL: root))
        #expect(try StoreBackupManager.cleanUpAutomaticBackups(storeDirectoryURL: root) == 0)
        #expect(try StoreBackupManager.deleteRetainedUnrestoredOriginals(storeDirectoryURL: root) == 0)
        #expect(try StoreBackupManager.deleteAllBackups(storeDirectoryURL: root) == 1)
    }
}

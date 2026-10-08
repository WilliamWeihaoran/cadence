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
}

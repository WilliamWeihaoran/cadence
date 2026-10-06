import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexBackupAuditTests {
    @Test func codexRestoringTheOldestRetainedPreRestoreBackupSurvivesSafetyBackupRetention() throws {
        try withTemporaryDefaults("CadenceTests.codexBackupAudit") { defaults in
            let root = try temporaryStore()
            defer { try? FileManager.default.removeItem(at: root) }

            var backups: [URL] = []
            for index in 0..<5 {
                try seedStore(in: root, marker: "historical-\(index)")
                let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                    reason: .manual,
                    storeDirectoryURL: root
                ))
                backups.append(backup)
            }
            for (index, backup) in backups.enumerated() {
                try labelAsPreRestore(backup, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
            }
            let selected = try #require(backups.first)
            let before = StoreBackupManager.listBackups(storeDirectoryURL: root)
            #expect(before.count == 5)
            #expect(before.allSatisfy { $0.reason == StoreBackupReason.preRestore.displayName })
            #expect(before.last?.url == selected, "the fixture must select the oldest retained backup")

            try seedStore(in: root, marker: "live-before-restore")
            try StoreBackupManager.scheduleRestore(from: selected, defaults: defaults, storeDirectoryURL: root)
            do {
                try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)
            } catch {
                Issue.record("Restoring a retained backup was refused: \(error)")
            }
            #expect(try marker(in: root) == "historical-0")
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) == nil)
            let after = StoreBackupManager.listBackups(storeDirectoryURL: root)
            #expect(after.contains { snapshot in
                snapshot.reason == StoreBackupReason.preRestore.displayName
                    && (try? marker(in: snapshot.url)) == "live-before-restore"
            }, "the safety backup must still preserve the displaced live store")
        }
    }

    @Test(arguments: ["{", "{}", ""])
    func codexUnreadableBackupManifestCannotDisableRequiredSidecarValidation(_ manifest: String) throws {
        try withTemporaryDefaults("CadenceTests.codexBackupAudit") { defaults in
            let root = try temporaryStore()
            defer { try? FileManager.default.removeItem(at: root) }
            try seedStore(in: root, marker: "incomplete-backup")
            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            ))
            try FileManager.default.removeItem(at: backup.appendingPathComponent("default.store-wal"))
            try Data(manifest.utf8).write(to: backup.appendingPathComponent("manifest.json"))
            try seedStore(in: root, marker: "good-live-store")

            do {
                try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
            } catch {
                let failure = error as NSError
                #expect(failure.domain == NSCocoaErrorDomain)
                #expect(failure.code == CocoaError.Code.fileReadCorruptFile.rawValue)
                #expect(try marker(in: root) == "good-live-store")
                #expect(try marker(in: root, name: "default.store-wal") == "good-live-store-wal")
                return
            }
            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)
            }
            #expect(try marker(in: root) == "good-live-store")
            #expect(try marker(in: root, name: "default.store-wal") == "good-live-store-wal")
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) != nil)
        }
    }

    @Test func codexAValidBackupStillRestoresAllManifestComponents() throws {
        try withTemporaryDefaults("CadenceTests.codexBackupAudit") { defaults in
            let root = try temporaryStore()
            defer { try? FileManager.default.removeItem(at: root) }
            try seedStore(in: root, marker: "valid-backup")
            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            ))
            try seedStore(in: root, marker: "live")
            try StoreBackupManager.scheduleRestore(from: backup, defaults: defaults, storeDirectoryURL: root)
            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: root, defaults: defaults)

            #expect(try marker(in: root) == "valid-backup")
            #expect(try marker(in: root, name: "default.store-wal") == "valid-backup-wal")
            #expect(try marker(in: root, name: ".default_SUPPORT/asset.bin") == "valid-backup-asset")
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) == nil)
        }
    }

    @Test func codexAutomaticCleanupProtectsOnlyThePendingRestoreSource() throws {
        try withTemporaryDefaults("CadenceTests.codexBackupAudit") { defaults in
            let root = try temporaryStore()
            defer { try? FileManager.default.removeItem(at: root) }
            var backups: [URL] = []
            for index in 0..<7 {
                try seedStore(in: root, marker: "historical-\(index)")
                backups.append(try #require(try StoreBackupManager.createBackupIfStoreExists(
                    reason: .manual, storeDirectoryURL: root
                )))
            }
            for (index, backup) in backups.enumerated() {
                try labelAsPreRestore(backup, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
            }
            let selected = try #require(backups.first)
            try StoreBackupManager.scheduleRestore(from: selected, defaults: defaults, storeDirectoryURL: root)
            let firstRemoval = try StoreBackupManager.cleanUpAutomaticBackups(storeDirectoryURL: root, defaults: defaults)
            #expect(firstRemoval == 1, "the unselected sixth-oldest backup should still be pruned")
            #expect(FileManager.default.fileExists(atPath: selected.path))
            #expect(!FileManager.default.fileExists(atPath: backups[1].path))
            #expect(StoreBackupManager.listBackups(storeDirectoryURL: root).count == 6)

            StoreBackupManager.clearPendingRestore(defaults: defaults, storeDirectoryURL: root)
            let secondRemoval = try StoreBackupManager.cleanUpAutomaticBackups(storeDirectoryURL: root, defaults: defaults)
            #expect(secondRemoval == 1)
            #expect(!FileManager.default.fileExists(atPath: selected.path))
            #expect(StoreBackupManager.listBackups(storeDirectoryURL: root).count == 5)
        }
    }

    private func temporaryStore() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceCodexBackupAudit.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func seedStore(in root: URL, marker: String) throws {
        try Data(marker.utf8).write(to: root.appendingPathComponent("default.store"))
        try Data("\(marker)-wal".utf8).write(to: root.appendingPathComponent("default.store-wal"))
        let assets = root.appendingPathComponent(".default_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("\(marker)-asset".utf8).write(to: assets.appendingPathComponent("asset.bin"))
    }

    private func marker(in root: URL, name: String = "default.store") throws -> String {
        String(decoding: try Data(contentsOf: root.appendingPathComponent(name)), as: UTF8.self)
    }

    private func labelAsPreRestore(_ backup: URL, createdAt: Date) throws {
        let url = backup.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        var manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        manifest["reason"] = StoreBackupReason.preRestore.rawValue
        manifest["createdAt"] = createdAt.ISO8601Format()
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
    }
}

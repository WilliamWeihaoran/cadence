import Foundation
import SwiftData
import Testing
@testable import Cadence

/// What a failed restore is allowed to cost the user: the restore, and nothing else.
///
/// **T-326.** `performPendingRestoreIfNeeded` used to remove the live store items first and copy
/// the backup over them second, clearing the pending flag only after the last copy landed. Every
/// assertion in this file is about the window that opened between those two steps — a full disk, a
/// damaged sidecar, a permission failure, an interrupted copy — where the app was left with no
/// store **and** a pending restore that the next launch would attempt again, forever.
///
/// So a happy-path test is worth almost nothing here and the failures are the subject. Each test
/// injects a real `FileManager` failure at one specific point in the sequence and then asks the two
/// questions that matter: is the store the user already had still there and still openable, and can
/// the next launch get past this.
@MainActor
struct CadenceStoreRestoreTests {
    // MARK: - Fixtures

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceStoreRestoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A store directory shaped like the real one: the store file, a `-wal` sidecar, and the
    /// `.default_SUPPORT` *directory*, which is what makes the size check in `verifyStagedRestore`
    /// exercise its directory branch rather than only the file branch.
    private func seedStoreItems(in directory: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: directory.appendingPathComponent("default.store"))
        try Data("\(marker)-wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))
        let supportURL = directory.appendingPathComponent(".default_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try Data("\(marker)-support".utf8).write(to: supportURL.appendingPathComponent("support.bin"))
    }

    private func removeStoreItems(in directory: URL) throws {
        for item in CadenceStoreSupport.storeItemURLs(in: directory) {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func marker(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("default.store")) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func storeItemNames(in directory: URL) -> Set<String> {
        Set(CadenceStoreSupport.storeItemURLs(in: directory).map(\.lastPathComponent))
    }

    /// Neither working directory may survive a restore, successful or not.
    private func expectNoRestoreScratchLeftBehind(in directory: URL, sourceLocation: SourceLocation = #_sourceLocation) {
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty, "restore scratch left behind: \(leftovers)", sourceLocation: sourceLocation)
    }

    /// Seed a real SwiftData store, so "the live store survived" can be checked by opening it
    /// rather than by comparing bytes we wrote ourselves.
    private func writeRealStore(at storeURL: URL, taskTitle: String) throws {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: taskTitle))
        try context.save()
    }

    private func taskTitles(inStoreAt storeURL: URL) throws -> [String] {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: false,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<AppTask>()).map(\.title).sorted()
    }

    // MARK: - The removal/copy window

    @Test func aCopyThatFailsPartWayThroughStagingLeavesEveryLiveStoreItemWhereItWas() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "the-backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            // Disk full on the second item of the copy: the old code had already deleted the live
            // store by this point in the sequence.
            let interrupting = InterruptingFileManager(
                failCopy: { _, destination in
                    destination.path.contains("restore-staging") && destination.lastPathComponent == "default.store-wal"
                }
            )

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            #expect(marker(in: storeDirectory) == "what-is-live")
            #expect(storeItemNames(in: storeDirectory) == ["default.store", "default.store-wal", ".default_SUPPORT"])
            expectNoRestoreScratchLeftBehind(in: storeDirectory)
        }
    }

    @Test func aFailureDuringTheSwapPutsTheDisplacedStoreBack() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "the-backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            // The one window that cannot be a single rename: several verified items are being moved
            // into the store directory and the second one fails.
            let interrupting = InterruptingFileManager(
                failMove: { source, destination in
                    source.path.contains("restore-staging") && destination.lastPathComponent == "default.store-wal"
                }
            )

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            #expect(marker(in: storeDirectory) == "what-is-live")
            #expect(storeItemNames(in: storeDirectory) == ["default.store", "default.store-wal", ".default_SUPPORT"])
            expectNoRestoreScratchLeftBehind(in: storeDirectory)
        }
    }

    @Test func aBackupMissingSomethingItsManifestClaimsIsRefusedBeforeAnythingIsReplaced() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "the-backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))
            // Damage the backup the way a half-written or partly deleted folder is damaged: the
            // manifest still names the sidecar, the sidecar is gone. `isBackupDirectory` cannot see
            // this — it only looks for the manifest and the store file — so the old code copied
            // what remained over a store it had already deleted and called that a restore.
            try FileManager.default.removeItem(at: backupURL.appendingPathComponent("default.store-wal"))

            try removeStoreItems(in: storeDirectory)
            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    defaults: defaults
                )
            }

            #expect(marker(in: storeDirectory) == "what-is-live")
            #expect(storeItemNames(in: storeDirectory) == ["default.store", "default.store-wal", ".default_SUPPORT"])
            expectNoRestoreScratchLeftBehind(in: storeDirectory)
        }
    }

    @Test func theStoreThatSurvivesAFailedRestoreStillOpensAndStillHasItsOwnRows() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }
            let storeURL = storeDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename)

            try writeRealStore(at: storeURL, taskTitle: "Row from the backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try writeRealStore(at: storeURL, taskTitle: "Row the user has right now")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            let interrupting = InterruptingFileManager(
                failCopy: { _, destination in
                    destination.path.contains("restore-staging") && destination.lastPathComponent == "default.store"
                }
            )

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            // The point of the ticket. Not "a file is present" — the same database, openable, with
            // the user's own row in it.
            #expect(try taskTitles(inStoreAt: storeURL) == ["Row the user has right now"])
        }
    }

    // MARK: - The launch cannot wedge

    @Test func aFailedRestoreIsQuarantinedSoTheNextLaunchDoesNotAttemptItAgain() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "the-backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            let interrupting = InterruptingFileManager(
                failCopy: { _, destination in
                    destination.path.contains("restore-staging") && destination.lastPathComponent == "default.store"
                }
            )
            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            // Off the launch path...
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            // ...but not forgotten, and it says which backup and why.
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.backupPath == backupURL.path)
            #expect(record.backupName == backupURL.lastPathComponent)
            #expect(!record.reason.isEmpty)
            #expect(record.startupMessage.contains(backupURL.lastPathComponent))

            // The next launch: same call, healthy file manager, and it is a no-op rather than a
            // second attempt at the same failing restore.
            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )
            #expect(marker(in: storeDirectory) == "what-is-live")
        }
    }

    @Test func aPendingRestorePointingAtNothingIsQuarantinedRatherThanRetried() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)
            try FileManager.default.removeItem(at: backupURL)

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    defaults: defaults
                )
            }

            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.backupPath == backupURL.path)
            #expect(marker(in: storeDirectory) == "what-is-live")
        }
    }

    @Test func schedulingANewRestoreSupersedesTheRecordOfTheLastFailure() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            let interrupting = InterruptingFileManager(
                failCopy: { _, destination in destination.path.contains("restore-staging") }
            )
            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) != nil)

            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) == nil)
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults)?.path == backupURL.path)
        }
    }

    // MARK: - And it still restores

    @Test func aRestoreThatSucceedsReplacesTheStoreAndClearsThePendingFlag() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedStoreItems(in: storeDirectory, marker: "the-backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try seedStoreItems(in: storeDirectory, marker: "what-is-live")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )

            #expect(marker(in: storeDirectory) == "the-backup")
            #expect(storeItemNames(in: storeDirectory) == ["default.store", "default.store-wal", ".default_SUPPORT"])
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(StoreBackupManager.lastFailedRestore(defaults: defaults) == nil)
            expectNoRestoreScratchLeftBehind(in: storeDirectory)

            // The store it replaced is not gone; it is the pre-restore backup, which is what the
            // banner tells the user to look for.
            let preRestoreBackups = StoreBackupManager.listBackups(storeDirectoryURL: storeDirectory)
                .filter { $0.reason == StoreBackupReason.preRestore.displayName }
            #expect(preRestoreBackups.count == 1)
        }
    }

    @Test func aSucceedingRestoreProducesAStoreTheAppCanOpen() throws {
        try withTemporaryDefaults("CadenceTests.storeRestore") { defaults in
            let storeDirectory = try makeStoreDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }
            let storeURL = storeDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename)

            try writeRealStore(at: storeURL, taskTitle: "Row from the backup")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            try removeStoreItems(in: storeDirectory)
            try writeRealStore(at: storeURL, taskTitle: "Row the user has right now")
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults)

            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )

            #expect(try taskTitles(inStoreAt: storeURL) == ["Row from the backup"])
        }
    }

    // MARK: - The banner

    @Test func aFailedRestoreIsReportedWithoutClaimingSyncIsBroken() {
        // The staged restore leaves the CloudKit store open and syncing, so this issue must not be
        // dressed as a store-level failure the way a recovery store is.
        #expect(CadenceStartupIssueKind.restoreFailed.disablesCloudSync == false)
        #expect(CadenceStartupIssueKind.restoreFailed.losesDataOnQuit == false)

        let issue = CadenceStartupIssue(
            kind: .restoreFailed,
            message: "Cadence could not restore the backup 20260826-090000-manual."
        )
        #expect(issue.bannerDetail.contains(issue.message))
        #expect(issue.bannerDetail.contains("intact"))
        #expect(!issue.bannerTitle.isEmpty)

        let health = CadenceSyncHealth.resolve(startupIssue: issue, account: .available)
        #expect(health.level == .syncing)
    }
}

/// A `FileManager` that fails exactly one file operation and is otherwise the real thing.
///
/// The seam T-326 needs: the defect is a specific ordering, so proving it is fixed means throwing
/// at a specific step and looking at what is left on disk. A read-only destination cannot aim that
/// precisely — it fails the pre-restore backup first, before the sequence under test starts.
private nonisolated final class InterruptingFileManager: FileManager {
    /// Both predicates take source **and** destination. Destination alone is not enough: the
    /// rollback inside `swapStagedRestore` moves the displaced items back to the very paths the
    /// failing move was aiming at, so a destination-only predicate would also sabotage the
    /// recovery it is supposed to be testing.
    private let failCopy: @Sendable (URL, URL) -> Bool
    private let failMove: @Sendable (URL, URL) -> Bool

    init(
        failCopy: @escaping @Sendable (URL, URL) -> Bool = { _, _ in false },
        failMove: @escaping @Sendable (URL, URL) -> Bool = { _, _ in false }
    ) {
        self.failCopy = failCopy
        self.failMove = failMove
        super.init()
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if failCopy(srcURL, dstURL) {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failMove(srcURL, dstURL) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

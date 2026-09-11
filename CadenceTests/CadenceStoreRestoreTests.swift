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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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

    // MARK: - T-1100: a rollback that cannot finish keeps what it moved

    /// Where a failed rollback put the originals it could not replace, if it made one. Asked
    /// through the same enumeration the privacy reset uses, so a rename that hid the folder from
    /// the reset would also fail these.
    private func retainedOriginalsDirectory(in directory: URL) -> URL? {
        StoreBackupManager.retainedUnrestoredOriginalDirectories(in: directory).first
    }

    /// **The defect.** Two faults, not one: the staged `default.store-wal` refuses to move in, and
    /// the displaced `default.store` refuses to move back. Both are the same operation on the same
    /// volume, so whatever refuses the first is available to refuse the second.
    ///
    /// The old catch swallowed the failed move-back with `try?` and then removed the displaced
    /// directory unconditionally, one line later — deleting the user's live store from inside the
    /// code written to protect it. Nothing said so: the throw named the *first* failure, and the
    /// banner went on claiming the existing data was intact.
    @Test func aRollbackThatCannotPutAnOriginalBackKeepsItInsteadOfDeletingIt() throws {
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

            let interrupting = InterruptingFileManager(
                failMove: { source, destination in
                    // The forward swap fails on the second item...
                    (source.path.contains("restore-staging") && destination.lastPathComponent == "default.store-wal")
                        // ...and the compensating move of the live store fails too.
                        || (source.path.contains("restore-previous") && destination.lastPathComponent == "default.store")
                }
            )

            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            // The point of the ticket: the live store file is not in the store directory, and it is
            // not deleted either — it is in the retained folder, byte for byte.
            let retained = try #require(
                retainedOriginalsDirectory(in: storeDirectory),
                "the originals the rollback could not replace were destroyed"
            )
            let retainedStore = retained.appendingPathComponent("default.store")
            #expect(FileManager.default.fileExists(atPath: retainedStore.path))
            #expect(String(data: try Data(contentsOf: retainedStore), encoding: .utf8) == "what-is-live")

            // Everything the rollback *could* put back is back, and nothing of the restore is
            // installed over it.
            #expect(marker(in: storeDirectory) == nil)
            #expect(storeItemNames(in: storeDirectory) == ["default.store-wal", ".default_SUPPORT"])
            // The retained folder is not mistaken for part of the store by any store-item scan.
            expectNoRestoreScratchLeftBehind(in: storeDirectory)

            // And the store as it was is still recoverable from the pre-restore backup.
            #expect(StoreBackupManager.listBackups(storeDirectoryURL: storeDirectory)
                .contains { $0.reason == StoreBackupReason.preRestore.displayName })
        }
    }

    /// The same failure, read from the banner. `.restoreFailed`'s copy says the existing data is
    /// intact and the restore simply did not run; neither sentence is true here, so this record
    /// does not get to use them.
    @Test func aRollbackThatKeptFilesSaysSoInsteadOfClaimingTheStoreIsUntouched() throws {
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

            let interrupting = InterruptingFileManager(
                failMove: { source, destination in
                    (source.path.contains("restore-staging") && destination.lastPathComponent == "default.store-wal")
                        || (source.path.contains("restore-previous") && destination.lastPathComponent == "default.store")
                }
            )
            #expect(throws: (any Error).self) {
                try StoreBackupManager.performPendingRestoreIfNeeded(
                    storeDirectoryURL: storeDirectory,
                    fileManager: interrupting,
                    defaults: defaults
                )
            }

            let retained = try #require(retainedOriginalsDirectory(in: storeDirectory))
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.retainedOriginalsPath == retained.path)
            #expect(record.startupIssueKind == .restoreIncomplete)
            #expect(record.startupMessage.contains(retained.path))
            #expect(!record.startupMessage.contains("kept the data already on this device"))

            let issue = CadenceStartupIssue(kind: record.startupIssueKind, message: record.startupMessage)
            #expect(!issue.bannerDetail.contains("Your existing data is intact"))
            #expect(issue.bannerDetail.contains("Nothing was deleted"))
            // Still not a sync failure: the store that opened is CloudKit-backed either way.
            #expect(CadenceSyncHealth.resolve(startupIssue: issue, account: .available).level == .syncing)
        }
    }

    /// The discriminator. An ordinary swap failure whose rollback *succeeds* keeps none of this
    /// machinery: no retained folder, no changed banner. Without this, retaining unconditionally
    /// would also pass the test above.
    @Test func aRollbackThatSucceedsLeavesNoRetainedFolderAndTheOrdinaryMessage() throws {
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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

            #expect(retainedOriginalsDirectory(in: storeDirectory) == nil)
            #expect(marker(in: storeDirectory) == "what-is-live")
            let record = try #require(StoreBackupManager.lastFailedRestore(defaults: defaults))
            #expect(record.retainedOriginalsPath == nil)
            #expect(record.startupIssueKind == .restoreFailed)
            #expect(record.startupMessage.contains("kept the data already on this device"))
        }
    }

    /// The other half of BR-1: the *next* restore used to delete a displaced directory it found
    /// lying there. A process killed between the two move loops leaves exactly that — the only copy
    /// of the store items it had moved aside — and a later restore reused the path by removing it.
    @Test func aLaterRestoreDoesNotEraseOriginalsAnEarlierSwapLeftBehind() throws {
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

            // What a killed swap leaves behind, under the working name the next swap wants.
            let strandedURL = storeDirectory.appendingPathComponent(".cadence-restore-previous.tmp", isDirectory: true)
            try FileManager.default.createDirectory(at: strandedURL, withIntermediateDirectories: true)
            try Data("from-an-interrupted-swap".utf8)
                .write(to: strandedURL.appendingPathComponent("default.store"))

            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)
            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )

            // The restore still ran...
            #expect(marker(in: storeDirectory) == "the-backup")
            // ...and the stranded originals were moved out of the way rather than deleted.
            let retained = try #require(
                retainedOriginalsDirectory(in: storeDirectory),
                "a later restore destroyed the originals an interrupted swap left behind"
            )
            let strandedStore = retained.appendingPathComponent("default.store")
            #expect(String(data: try Data(contentsOf: strandedStore), encoding: .utf8) == "from-an-interrupted-swap")
            expectNoRestoreScratchLeftBehind(in: storeDirectory)
        }
    }

    /// The privacy reset's half of the same folder: it is store data, and "delete my Cadence data"
    /// has to include it. Exercised on a temporary directory — the real entry point deletes inside
    /// the app's own container, so no test may call that one.
    @Test func aRetainedFolderIsDeletedByTheDataResetRatherThanOutlivingIt() throws {
        let storeDirectory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        try seedStoreItems(in: storeDirectory, marker: "what-is-live")
        let retainedURL = storeDirectory
            .appendingPathComponent("Cadence Unrestored Store Files 20260910-101500", isDirectory: true)
        try FileManager.default.createDirectory(at: retainedURL, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: retainedURL.appendingPathComponent("default.store"))

        #expect(StoreBackupManager.retainedUnrestoredOriginalDirectories(in: storeDirectory) == [retainedURL])
        #expect(try StoreBackupManager.deleteRetainedUnrestoredOriginals(storeDirectoryURL: storeDirectory) == 1)
        #expect(!FileManager.default.fileExists(atPath: retainedURL.path))
        // ...and it took nothing else with it.
        #expect(storeItemNames(in: storeDirectory) == ["default.store", "default.store-wal", ".default_SUPPORT"])
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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

            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)
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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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
            try StoreBackupManager.scheduleRestore(from: backupURL, defaults: defaults, storeDirectoryURL: storeDirectory)

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

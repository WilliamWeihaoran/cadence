import Foundation
import SwiftData
import Testing
@testable import Cadence

/// What a failed **startup backup** is allowed to cost the user: the backup, and nothing else.
///
/// **[[T-3042]].** `PersistenceController.init` ran
/// `_ = try StoreBackupManager.createBackupIfStoreExists(reason: .startup, …)` as the last statement
/// of one big preflight `do`, whose `catch` called `makeRecoveryContainer` and returned. The real
/// store was never opened. So a failure to write *a copy of the database* showed the user an empty
/// app and a banner saying Cadence could not open their data — on every launch, until whatever
/// filesystem condition caused it cleared.
///
/// The precedent was three lines above it: [[T-326]] put `performPendingRestoreIfNeeded` in its own
/// inner `do`/`catch` so "a restore that fails no longer takes the launch down with it", because
/// falling through to a recovery store "used to hide an intact database behind an empty one". A
/// failed backup has the same shape and a weaker claim on aborting the launch — the restore at least
/// touches the store directory, the backup only reads it.
///
/// **Every leg of the startup backup is non-fatal, and that was checked rather than assumed.** All
/// five writes `createBackupIfStoreExists` makes land inside `<store>/Cadence Store Backups`: the
/// backup root's `createDirectory`, each `copyItem` into the `.tmp` staging folder, the manifest
/// `write`, the `moveItem` that renames that staging folder to its final name *within the same
/// backup root*, and `purgeAutomaticBackups`' `removeItem` over old backup folders. There is no
/// staged swap over the store here — that belongs to the restore, one function away — so no leg can
/// leave the store directory in a state where opening it is unsafe.
///
/// The fixture below drives the leg that decided it, and it is the realistic one: `purgeAutomaticBackups`
/// runs **after** the backup has already landed under its final name, so one old backup folder that
/// will not delete makes a *successful* backup report failure.
@MainActor
struct CadenceStartupBackupFailureTests {

    // MARK: - Fixtures

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceStartupBackupFailure.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real SwiftData store, so "the launch still opens the user's own data" can be checked by
    /// opening it and reading a row back rather than by comparing bytes this test wrote itself.
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

    /// Rewrite a backup's manifest so retention reads it as a Before Restore backup taken at a
    /// chosen moment. The same trick `CadenceCodexBackupAuditTests` uses, and for the same reason:
    /// `maxPreRestoreBackups` is a flat count, so six of them makes exactly one removable and the
    /// purge has exactly one thing to fail at.
    private func labelAsPreRestore(_ backup: URL, createdAt: Date) throws {
        let url = backup.appendingPathComponent("manifest.json")
        var manifest = try #require(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        manifest["reason"] = StoreBackupReason.preRestore.rawValue
        manifest["createdAt"] = createdAt.ISO8601Format()
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
    }

    /// Make one old backup folder genuinely un-removable, the way a `uchg` flag or a permissions
    /// fault does on a real machine: a child directory that `removeItem` has to empty and cannot.
    ///
    /// A **real** filesystem refusal rather than a stub `FileManager`, because the claim under test
    /// is about where in the sequence the throw lands — after the new backup has been renamed into
    /// place — and a fake that throws on command can be aimed at a step the real one never reaches.
    private func makeUndeletable(_ directoryURL: URL) throws -> URL {
        let locked = directoryURL.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("pinned".utf8).write(to: locked.appendingPathComponent("pinned.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        return locked
    }

    /// A store directory holding a real store, six Before Restore backups, and the oldest of them
    /// rigged so the retention sweep cannot delete it.
    private func seedStoreWithAnUndeletableOldBackup(
        taskTitle: String
    ) throws -> (root: URL, locked: URL, doomed: URL) {
        let root = try makeStoreDirectory()
        try writeRealStore(at: root.appendingPathComponent("default.store"), taskTitle: taskTitle)

        var backups: [URL] = []
        for _ in 0..<6 {
            backups.append(try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: root
            )))
        }
        for (index, backup) in backups.enumerated() {
            try labelAsPreRestore(backup, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
        }

        let doomed = try #require(backups.first)
        let listed = StoreBackupManager.listBackups(storeDirectoryURL: root)
        #expect(listed.count == 6, "the fixture must hold six Before Restore backups, not \(listed.count)")
        #expect(listed.last?.url == doomed, "the fixture must rig the one backup retention will prune")

        return (root, try makeUndeletable(doomed), doomed)
    }

    private func tearDown(root: URL, locked: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The leg that matters: the backup landed, and then the sweep failed

    /// The realistic case, end to end on a real filesystem: the backup succeeds, the retention sweep
    /// that runs after it throws, and the launch's data is untouched and still openable.
    ///
    /// The three assertions are the ticket: the error is real, the backup it reports as failed is
    /// sitting on disk under its final name, and the store the old code would have hidden behind an
    /// empty recovery container still answers with the user's own row.
    @Test func aStartupBackupThatLandsAndThenFailsItsRetentionSweepLeavesTheStoreIntact() throws {
        try withTemporaryDefaults("CadenceTests.startupBackupFailure") { defaults in
            let fixture = try seedStoreWithAnUndeletableOldBackup(taskTitle: "Written before the backup failed")
            defer { tearDown(root: fixture.root, locked: fixture.locked) }

            var thrown: Error?
            do {
                _ = try StoreBackupManager.createBackupIfStoreExists(
                    reason: .startup,
                    storeDirectoryURL: fixture.root,
                    defaults: defaults
                )
            } catch {
                thrown = error
            }

            let failure = try #require(
                thrown,
                "the fixture stopped failing — the retention sweep deleted a folder it should not have been able to"
            )
            #expect(FileManager.default.fileExists(atPath: fixture.doomed.path))

            // The backup this call reports as failed has already landed under its final name. That
            // is the whole shape of the defect: a *successful* backup emptying the app.
            let after = StoreBackupManager.listBackups(storeDirectoryURL: fixture.root)
            #expect(
                after.contains { $0.reason == StoreBackupReason.startup.displayName },
                "the startup backup never landed, so this is not the post-landing failure under test"
            )

            // And the store the old `catch` would have replaced with an empty recovery container.
            #expect(
                try taskTitles(inStoreAt: fixture.root.appendingPathComponent("default.store"))
                    == ["Written before the backup failed"]
            )

            // What the launch does with that error: open the real store and say what happened.
            let issue = try #require(PersistenceController.preflightStartupIssue(
                failedRestore: nil,
                failedStartupBackup: failure
            ))
            #expect(issue.kind == .backupFailed)
            #expect(issue.kind.disablesCloudSync == false)
            #expect(issue.kind.losesDataOnQuit == false)
            #expect(
                !issue.message.lowercased().contains("recovery store"),
                "a failed backup is reporting itself as a store that could not be opened: \(issue.message)"
            )
        }
    }

    /// Non-vacuity for the fixture above: with nothing rigged, the same call succeeds and prunes.
    @Test func anUnobstructedStartupBackupStillSucceedsAndStillPrunes() throws {
        try withTemporaryDefaults("CadenceTests.startupBackupFailure") { defaults in
            let fixture = try seedStoreWithAnUndeletableOldBackup(taskTitle: "Ordinary launch")
            defer { tearDown(root: fixture.root, locked: fixture.locked) }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixture.locked.path
            )

            _ = try StoreBackupManager.createBackupIfStoreExists(
                reason: .startup,
                storeDirectoryURL: fixture.root,
                defaults: defaults
            )

            #expect(!FileManager.default.fileExists(atPath: fixture.doomed.path))
            #expect(PersistenceController.preflightStartupIssue(
                failedRestore: nil,
                failedStartupBackup: nil
            ) == nil)
            #expect(PersistenceController.preflightVerdict(
                failedRestore: nil,
                failedStartupBackup: nil
            ) == .completed)
        }
    }

    // MARK: - The two sentences, which used to be one

    /// The audit's specific complaint: "your backup could not be written" and "your database could
    /// not be opened" were the same sentence and mean opposite things.
    @Test func theBackupFailureAndTheUnopenableDatabaseNoLongerShareASentence() {
        let cause = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileWriteOutOfSpace.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "There is not enough space on the disk."]
        )

        let backupMessage = PersistenceController.startupBackupFailureMessage(cause)
        let storeMessage = PersistenceController.primaryStoreFailureMessage(cause)

        #expect(backupMessage != storeMessage)
        #expect(backupMessage.contains("There is not enough space on the disk."))
        #expect(backupMessage.lowercased().contains("backup"))
        #expect(
            !backupMessage.lowercased().contains("recovery store"),
            "the backup sentence is back to announcing a recovery store: \(backupMessage)"
        )
        #expect(
            !backupMessage.lowercased().contains("could not be created"),
            "the backup sentence reads as the store-open failure: \(backupMessage)"
        )
        #expect(storeMessage.lowercased().contains("recovery store"))

        // And the banner the user actually reads says the data is fine.
        let issue = CadenceStartupIssue(kind: .backupFailed, message: backupMessage)
        #expect(issue.bannerDetail.contains(backupMessage))
        #expect(issue.bannerDetail.contains("intact"))
        #expect(!issue.bannerTitle.isEmpty)
        #expect(
            CadenceSyncHealth.resolve(
                startupIssue: issue,
                account: .available,
                pushRegistration: .registered
            ).level == .syncing,
            "a failed backup is being reported as a sync failure, which it is not"
        )
    }

    // MARK: - One slot, three claimants

    /// `CadenceStartupIssue` holds **one** issue. `init` keeps [[T-3013]]'s `startupIssue == nil`
    /// guard for the sync message, and this is the ranking between the two preflight failures that
    /// are left: the restore is something the user asked for, the backup is housekeeping.
    @Test func aFailedRestoreOutranksAFailedBackupForTheOneIssueSlot() {
        let record = StoreBackupManager.FailedRestoreRecord(
            backupPath: "/tmp/Cadence Store Backups/20260826-090000-manual",
            backupName: "20260826-090000-manual",
            failedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: "The backup folder is missing."
        )
        let backupFailure = CocoaError(.fileWriteOutOfSpace)

        let both = PersistenceController.preflightStartupIssue(
            failedRestore: record,
            failedStartupBackup: backupFailure
        )
        #expect(both?.kind == .restoreFailed)
        #expect(both?.message == record.startupMessage)

        // Each alone still speaks.
        #expect(PersistenceController.preflightStartupIssue(
            failedRestore: record,
            failedStartupBackup: nil
        )?.kind == .restoreFailed)
        #expect(PersistenceController.preflightStartupIssue(
            failedRestore: nil,
            failedStartupBackup: backupFailure
        )?.kind == .backupFailed)
        #expect(PersistenceController.preflightStartupIssue(
            failedRestore: nil,
            failedStartupBackup: nil
        ) == nil)
    }

    /// The [[T-1366]] ledger keeps the three answers apart, and ranks them the way the banner does
    /// so the two cannot name different failures for the same launch.
    @Test func theLedgerSeparatesARefusedBackupFromARefusedRestoreAndFromACleanPass() {
        let record = StoreBackupManager.FailedRestoreRecord(
            backupPath: "/tmp/b",
            backupName: "b",
            failedAt: Date(timeIntervalSince1970: 1),
            reason: "no"
        )

        #expect(PersistenceController.preflightVerdict(
            failedRestore: nil,
            failedStartupBackup: nil
        ) == .completed)

        let backupOnly = PersistenceController.preflightVerdict(
            failedRestore: nil,
            failedStartupBackup: CocoaError(.fileWriteOutOfSpace)
        )
        #expect(backupOnly.outcome == .refused)
        #expect(backupOnly.note == "startupBackupRefused")

        let restoreOnly = PersistenceController.preflightVerdict(
            failedRestore: record,
            failedStartupBackup: nil
        )
        #expect(restoreOnly.outcome == .refused)
        #expect(restoreOnly.note == "pendingRestoreRefused")

        #expect(PersistenceController.preflightVerdict(
            failedRestore: record,
            failedStartupBackup: CocoaError(.fileWriteOutOfSpace)
        ).note == "pendingRestoreRefused")

        // Vocabulary, never content: a note can carry no path, title or framework prose.
        for note in [backupOnly.note, restoreOnly.note].compactMap(\.self) {
            #expect(!note.contains("/"))
            #expect(!note.contains(" "))
        }
    }

    // MARK: - The shape in `init`, which is the thing that can be undone

    /// Read from `init`'s own body, the way `CadenceStartupRecoveryReasonTests` reads it for the
    /// `try?` that T-1319 removed: the structure is the fix, and restoring the single `do` is the
    /// one edit that silently brings the defect back.
    @Test func theStartupBackupSitsInItsOwnDoCatchThatCannotReachARecoveryStore() throws {
        let body = try initBody()

        // Non-vacuity: this really is the boot sequence.
        #expect(body.contains("makeRecoveryContainer("))
        #expect(body.contains("performPendingRestoreIfNeeded"))

        let backupCall = try #require(
            body.range(of: "reason: .startup"),
            "init no longer takes a startup backup at all"
        )
        let enclosingDo = try #require(
            body.range(of: "do {", options: .backwards, range: body.startIndex..<backupCall.lowerBound),
            "the startup backup is not inside any do block"
        )
        let enclosingRange = try #require(
            CadenceSourceScan.matchedRange(after: enclosingDo.lowerBound, in: body, open: "{", close: "}"),
            "the do block enclosing the startup backup does not balance"
        )
        let enclosing = String(body[enclosingRange])

        #expect(
            enclosing.contains("reason: .startup"),
            """
            the startup backup is back inside the shared preflight `do`, so a backup that fails — \
            including one that SUCCEEDED and whose retention sweep then failed — drops the launch \
            into an empty recovery store again (T-3042)
            """
        )
        // T-326's restore keeps its own block; this did not simply widen that one.
        #expect(
            !enclosing.contains("performPendingRestoreIfNeeded"),
            "the backup and the restore now share one catch, so each is reported as the other"
        )

        let catchBody = try #require(
            CadenceSourceScan.matchedBody(
                after: body.index(after: enclosingRange.upperBound),
                in: body,
                open: "{",
                close: "}"
            ),
            "the startup backup's do block is not followed by a catch"
        )
        #expect(
            catchBody.contains("failedStartupBackup = error"),
            "the startup backup's failure is swallowed rather than recorded"
        )
        #expect(
            !catchBody.contains("makeRecoveryContainer("),
            "a failed backup still opens a recovery store over an intact database (T-3042)"
        )
    }

    /// The other direction, so the fix cannot be over-applied later: the legs that really can leave
    /// the launch with no store directory to open — resolving (and creating) it, and the legacy
    /// migration — are still inside the fatal `do` and still fall through to a recovery container.
    ///
    /// A blanket catch that opened a store the preflight had already damaged would be a worse bug
    /// than the one T-3042 fixed.
    @Test func theLegsThatCanLeaveNoStoreToOpenAreStillFatal() throws {
        let body = try initBody()

        let fatalSentence = try #require(
            body.range(of: "backup/restore preflight failed"),
            "the preflight's recovery sentence is gone, so nothing in the preflight is fatal any more"
        )
        let fatalCatch = try #require(
            body.range(of: "} catch {", options: .backwards, range: body.startIndex..<fatalSentence.lowerBound),
            "the preflight's recovery sentence is no longer reached from a catch"
        )
        let fatalBody = try #require(
            CadenceSourceScan.matchedBody(after: fatalCatch.lowerBound, in: body, open: "{", close: "}")
        )
        #expect(fatalBody.contains("makeRecoveryContainer("))
        #expect(fatalBody.contains("backup/restore preflight failed"))

        // The two legs it still covers.
        #expect(body.contains("try CadenceStoreSupport.primaryStoreDirectoryURL()"))
        #expect(body.contains("try CadenceStoreSupport.migrateLegacyStoreIfNeeded("))

        // Neither has been quietly moved into the startup backup's non-fatal block.
        let backupCall = try #require(body.range(of: "reason: .startup"))
        let enclosingDo = try #require(
            body.range(of: "do {", options: .backwards, range: body.startIndex..<backupCall.lowerBound)
        )
        let enclosing = try #require(
            CadenceSourceScan.matchedBody(after: enclosingDo.lowerBound, in: body, open: "{", close: "}")
        )
        #expect(
            !enclosing.contains("migrateLegacyStoreIfNeeded"),
            "the legacy migration is now non-fatal, so a launch can open a store it half-migrated"
        )
        #expect(
            !enclosing.contains("primaryStoreDirectoryURL"),
            "resolving the store directory is now non-fatal, so a launch can open a directory it never got"
        )
    }

    private func initBody() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        return try #require(
            CadenceSourceScan.declarationBody("init()", in: source),
            "PersistenceController.init is gone or its braces do not balance"
        )
    }
}

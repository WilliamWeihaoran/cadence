import Foundation
import SQLite3
import SwiftData
import Testing
@testable import Cadence

/// Two holes in the backup path, every fixture a temp directory.
///
/// **T-3043.** An archive import in `.restoreOverwritingExistingRows` rewrote every matched row and
/// took no backup first, so a completed overwrite the person regretted had nothing newer to go back
/// to than the last launch's startup backup. `CadenceArchiveImportFlow.confirm()` now takes a
/// `.preImport` backup before it writes, and refuses the import if it cannot.
///
/// **T-3044 (b).** A backup taken from a running app was a raw `copyItem` of `default.store` and
/// then `default.store-wal`; a checkpoint between the two copies moves committed frames into a
/// database file that was already copied and out of a WAL that is not yet copied. `.manual` and
/// `.preImport` backups now read the database as one SQLite snapshot (`VACUUM INTO`).
///
/// `.preservesTheStoredLaunchReports` for the reason `CadenceArchiveImportEntryPointTests` gives:
/// `confirm()` runs `NoteMigrationService`, which writes its report to `UserDefaults.standard`.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadencePreImportBackupTests {

    // MARK: - T-3043: the flow

    /// The backup runs before the import touches a row: the closure sees the store's own title,
    /// and the archive's title lands only afterwards.
    @Test func anOverwriteImportBacksUpBeforeItWritesAnything() throws {
        let fixture = try OverwriteFixture(destination: try CadenceTestStore.container())
        defer { fixture.removeArchive() }

        var titlesSeenByTheBackup: [[String]] = []
        let flow = CadenceArchiveImportFlow(
            reconcileNotifications: { _ in },
            backUpBeforeOverwriting: { container in
                titlesSeenByTheBackup.append(try Self.taskTitles(in: container))
                return URL(fileURLWithPath: "/nonexistent/20261008-120000-pre-import", isDirectory: true)
            }
        )
        flow.preview(.success(fixture.archiveURL), in: fixture.destination)
        flow.mode = .restoreOverwritingExistingRows
        flow.confirm()

        #expect(titlesSeenByTheBackup == [[OverwriteFixture.editedTitle]])
        #expect(try Self.taskTitles(in: fixture.destination) == [OverwriteFixture.archiveTitle])
        let message = try #require(flow.statusMessage)
        #expect(message.contains("replaced"))
        #expect(message.contains("20261008-120000-pre-import"))
    }

    /// A backup that cannot be taken is a refusal: nothing is overwritten, nothing is reconciled,
    /// and the preview is disarmed exactly as a committed one would be.
    @Test func anOverwriteImportWhoseBackupFailsWritesNothing() throws {
        let fixture = try OverwriteFixture(destination: try CadenceTestStore.container())
        defer { fixture.removeArchive() }

        struct BackupRefused: LocalizedError {
            var errorDescription: String? { "disk full" }
        }
        var reconciled = 0
        let flow = CadenceArchiveImportFlow(
            reconcileNotifications: { _ in reconciled += 1 },
            backUpBeforeOverwriting: { _ in throw BackupRefused() }
        )
        flow.preview(.success(fixture.archiveURL), in: fixture.destination)
        flow.mode = .restoreOverwritingExistingRows
        flow.confirm()

        #expect(try Self.taskTitles(in: fixture.destination) == [OverwriteFixture.editedTitle])
        #expect(reconciled == 0)
        let message = try #require(flow.statusMessage)
        #expect(message.hasPrefix("Nothing was imported or replaced"))
        #expect(message.contains("disk full"))
        #expect(!flow.isPreviewing)
    }

    /// Merge mode changes no existing row's values, so it takes no backup (the decision is argued
    /// on `CadenceArchiveImportFlow.backUpBeforeOverwriting`).
    @Test func aMergeImportTakesNoBackup() throws {
        let fixture = try OverwriteFixture(destination: try CadenceTestStore.container())
        defer { fixture.removeArchive() }

        var backups = 0
        let flow = CadenceArchiveImportFlow(
            reconcileNotifications: { _ in },
            backUpBeforeOverwriting: { _ in
                backups += 1
                return nil
            }
        )
        flow.preview(.success(fixture.archiveURL), in: fixture.destination)
        #expect(flow.mode == .mergeKeepingExistingRows)
        flow.confirm()

        #expect(backups == 0)
        #expect(try Self.taskTitles(in: fixture.destination) == [OverwriteFixture.editedTitle])
        #expect(try #require(flow.statusMessage).hasPrefix("Imported"))
    }

    /// The live door, end to end, through a flow built the way both Settings screens build it. The
    /// backup holds the row as it was before the import; the live store holds the archive's copy.
    @Test func theDefaultFlowBacksUpTheOnDiskStoreItIsAboutToOverwrite() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        let destination = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let fixture = try OverwriteFixture(destination: destination)
        defer { fixture.removeArchive() }

        let flow = CadenceArchiveImportFlow(reconcileNotifications: { _ in })
        flow.preview(.success(fixture.archiveURL), in: destination)
        flow.mode = .restoreOverwritingExistingRows
        flow.confirm()

        #expect(try Self.taskTitles(in: destination) == [OverwriteFixture.archiveTitle])
        let backups = StoreBackupManager.listBackups(storeDirectoryURL: directory)
        #expect(backups.map(\.reason) == [StoreBackupReason.preImport.displayName])
        let backup = try #require(backups.first)
        #expect(try Self.taskTitlesInBackup(backup.url) == [OverwriteFixture.editedTitle])
        #expect(try #require(flow.statusMessage).contains(backup.url.lastPathComponent))
    }

    /// The door's non-backup answers: an in-memory store has nothing on disk to copy and is not
    /// refused; a store it cannot locate is refused rather than silently skipped — both a store
    /// under another file name (even with a `default.store` beside it, which is not the store the
    /// import writes) and a `default.store` that is no longer on disk.
    @Test func thePreImportDoorSkipsAnInMemoryStoreAndRefusesOneItCannotLocate() throws {
        #expect(try StoreBackupManager.createPreImportBackup(for: try CadenceTestStore.container()) == nil)

        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let neighbour = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: directory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        )
        let oddlyNamed = try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(
                "CadencePreImportBackupFixture",
                schema: CadenceSchema.schema,
                url: directory.appendingPathComponent("elsewhere.store"),
                cloudKitDatabase: .none
            )
        )
        #expect(throws: StoreBackupManager.PreImportBackupUnavailable.self) {
            try StoreBackupManager.createPreImportBackup(for: oddlyNamed)
        }
        #expect(StoreBackupManager.listBackups(storeDirectoryURL: directory).isEmpty)

        for item in CadenceStoreSupport.storeItemURLs(in: directory) {
            try FileManager.default.removeItem(at: item)
        }
        #expect(throws: StoreBackupManager.PreImportBackupUnavailable.self) {
            try StoreBackupManager.createPreImportBackup(for: neighbour)
        }
        #expect(StoreBackupManager.listBackups(storeDirectoryURL: directory).isEmpty)
    }

    /// One per overwriting import, so they are capped like pre-restore backups; a manual backup is
    /// never swept, however old.
    @Test func theNewestFivePreImportBackupsSurviveASweep() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var snapshots = (0..<7).map { index in
            StoreBackupSnapshot(
                id: "pre-import-\(index)",
                url: URL(fileURLWithPath: "/nonexistent/pre-import-\(index)"),
                createdAt: base.addingTimeInterval(Double(index) * 60),
                reason: StoreBackupReason.preImport.displayName,
                sizeBytes: 1
            )
        }
        snapshots.append(StoreBackupSnapshot(
            id: "manual-old",
            url: URL(fileURLWithPath: "/nonexistent/manual-old"),
            createdAt: base.addingTimeInterval(-86_400 * 400),
            reason: StoreBackupReason.manual.displayName,
            sizeBytes: 1
        ))

        let removed = StoreBackupManager.automaticBackupSnapshotsToRemove(snapshots, now: base)
        #expect(Set(removed.map(\.id)) == ["pre-import-0", "pre-import-1"])
    }

    // MARK: - T-3044 (b): a backup of a live store

    /// The store is open and its rows are in the WAL, not yet in `default.store`. The backup is one
    /// file with no sidecars, and that file alone holds every committed row.
    @Test func aBackupOfALiveStoreIsOneFileHoldingEveryCommittedRow() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        let live = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let context = ModelContext(live)
        for index in 0..<Self.liveRowCount {
            context.insert(AppTask(title: "Live row \(index)"))
        }
        try context.save()

        // Non-vacuity: the database file on its own does not yet hold the rows. Without this the
        // test cannot tell a snapshot from a copy of `default.store`.
        let walURL = directory.appendingPathComponent("default.store-wal")
        #expect(FileManager.default.fileExists(atPath: walURL.path))
        let databaseOnly = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: databaseOnly) }
        try FileManager.default.copyItem(at: storeURL, to: databaseOnly.appendingPathComponent("default.store"))
        #expect(Self.sqliteTaskCount(at: databaseOnly.appendingPathComponent("default.store")) < Self.liveRowCount)

        let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
            reason: .manual,
            storeDirectoryURL: directory
        ))

        let items = try FileManager.default.contentsOfDirectory(atPath: backup.path)
        #expect(items.contains("default.store"))
        #expect(!items.contains("default.store-wal"))
        #expect(!items.contains("default.store-shm"))
        #expect(Self.sqliteTaskCount(at: backup.appendingPathComponent("default.store")) == Self.liveRowCount)
        #expect(try Self.taskTitlesInBackup(backup).count == Self.liveRowCount)
        // Read-only: the snapshot neither checkpointed nor removed the live WAL.
        #expect(FileManager.default.fileExists(atPath: walURL.path))
    }

    /// A store file that is not SQLite has no WAL to straddle, so a manual backup still copies it
    /// and its sidecars byte for byte — which is what every plain-text fixture in the restore suites
    /// relies on.
    @Test func aStoreFileThatIsNotSQLiteIsStillCopiedWithItsSidecars() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("marker".utf8).write(to: directory.appendingPathComponent("default.store"))
        try Data("marker-wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))

        let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
            reason: .manual,
            storeDirectoryURL: directory
        ))
        #expect(try Data(contentsOf: backup.appendingPathComponent("default.store")) == Data("marker".utf8))
        #expect(try Data(contentsOf: backup.appendingPathComponent("default.store-wal")) == Data("marker-wal".utf8))
    }

    /// The startup and pre-restore backups run before the container opens and keep copying every
    /// file as it is; only the two running-app reasons snapshot.
    @Test func onlyTheRunningAppReasonsSnapshotTheDatabase() throws {
        #expect(StoreBackupReason.manual.isTakenFromARunningApp)
        #expect(StoreBackupReason.preImport.isTakenFromARunningApp)
        #expect(!StoreBackupReason.startup.isTakenFromARunningApp)
        #expect(!StoreBackupReason.preRestore.isTakenFromARunningApp)

        try withTemporaryDefaults("CadenceTests.preImportBackup") { defaults in
            let directory = try Self.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let storeURL = directory.appendingPathComponent(CadenceStoreSupport.storeFilename)
            let live = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: true,
                cloudKitDatabase: .none,
                storeURL: storeURL
            )
            let context = ModelContext(live)
            context.insert(AppTask(title: "Startup row"))
            try context.save()

            let backup = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .startup,
                storeDirectoryURL: directory,
                defaults: defaults
            ))
            let items = try FileManager.default.contentsOfDirectory(atPath: backup.path)
            #expect(items.contains("default.store-wal"))
        }
    }

    // MARK: - Fixtures

    private static let liveRowCount = 25

    /// A destination that already holds the archive's task under the archive's id, edited since —
    /// so an overwrite has a matched row to replace and a merge has one to keep.
    private struct OverwriteFixture {
        static let archiveTitle = "Title in the archive"
        static let editedTitle = "Title edited since"

        let destination: ModelContainer
        let archiveURL: URL

        @MainActor
        init(destination: ModelContainer) throws {
            let source = ModelContext(try CadenceTestStore.container())
            source.insert(AppTask(title: Self.archiveTitle))
            try source.save()
            let data = try CadenceDataExportService.exportArchive(in: source).data
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cadence-preimport-fixture-\(UUID().uuidString).json")
            try data.write(to: url)

            try CadenceArchiveImportService.importArchive(data, mode: .mergeKeepingExistingRows, into: destination)
            let context = ModelContext(destination)
            let task = try #require(try context.fetch(FetchDescriptor<AppTask>()).first)
            task.title = Self.editedTitle
            try context.save()

            self.destination = destination
            self.archiveURL = url
        }

        func removeArchive() {
            try? FileManager.default.removeItem(at: archiveURL)
        }
    }

    private static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadencePreImportBackupTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func taskTitles(in container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title).sorted()
    }

    /// Opened from a copy, so the backup folder itself never gains sidecars from being read.
    private static func taskTitlesInBackup(_ backup: URL) throws -> [String] {
        let copy = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: copy) }
        let storeURL = copy.appendingPathComponent(CadenceStoreSupport.storeFilename)
        try FileManager.default.copyItem(at: backup.appendingPathComponent("default.store"), to: storeURL)
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: false,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        return try taskTitles(in: container)
    }

    /// Rows in `ZAPPTASK`, read through SQLite with no sidecars beside the file; a database that
    /// does not have the table yet counts as zero.
    private static func sqliteTaskCount(at url: URL) -> Int {
        var database: OpaquePointer?
        defer { sqlite3_close_v2(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT count(*) FROM ZAPPTASK", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

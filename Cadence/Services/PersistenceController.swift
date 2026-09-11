import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()
    /// The one startup problem this launch hit, if any.
    ///
    /// Structured rather than a bare `String` since T-153: two of the things that can be recorded
    /// here leave the store with `cloudKitDatabase: .none`, and the rest do not touch sync at all.
    /// Every surface that showed this used to have to guess which from the prose.
    private(set) static var startupIssue: CadenceStartupIssue?

    /// Set only when `container` is `nil` — the CloudKit store, the on-disk recovery store, and a
    /// fully in-memory container all failed to open. See `makeRecoveryContainer`'s final catch.
    ///
    /// This used to be a `fatalError`, unconditionally, on a launch already three failures deep.
    /// It is not reachable by anything a user or a synced record can drive — recreating it needs
    /// SwiftData to be unable to construct even an in-memory container, which is not a storage or
    /// network condition, since in-memory needs neither — but "not reachable" is not the same
    /// promise as "cannot happen", and the trap's cost when it does is the worst first impression
    /// the app has: a crash on launch with no explanation and no way to recover anything. This is
    /// the honest alternative: say plainly that nothing could be opened, and try, once, to read
    /// whatever *is* still on disk well enough to export it — see
    /// `attemptRecoveryExport()`.
    private(set) static var terminalFailure: CadenceStartupTerminalFailure?

    /// `nil` exactly when `terminalFailure` is set. `CadenceApp` reads this to decide whether it
    /// can build the normal app shell at all, or has to fall back to
    /// `CadenceTerminalRecoveryView` instead — a `ModelContainer` this app never got is not a
    /// container any view can safely assume, including the two floating panels
    /// (`QuickTaskPanelController`, `TaskNotesPanelController`) that build their own `.modelContainer`
    /// off `PersistenceController.shared.container` outside the app's main window group.
    let container: ModelContainer?

    static let schema = CadenceSchema.schema

    init() {
        if Self.shouldResetStoreOnLaunch {
            Self.deleteResolvedStoreDirectory()
        }

        // After the reset, never before it: the reset removes the whole directory, lock file
        // included, and a claim taken on a file that is then deleted owns nothing (T-1090).
        Self.claimUITestStoreDirectoryIfNeeded()

        if Self.isRunningTests {
            do {
                container = try Self.makeContainer()
                return
            } catch {
                fatalError("Could not create test ModelContainer: \(error.localizedDescription)")
            }
        }

        var failedRestore: StoreBackupManager.FailedRestoreRecord?
        do {
            let storeDirectoryURL = try CadenceStoreSupport.primaryStoreDirectoryURL()
            _ = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
                appGroupDirectoryURL: storeDirectoryURL,
                candidateLegacyDirectories: CadenceStoreSupport.legacyStoreCandidateDirectories(),
                backupHandler: { legacyDirectory in
                    _ = try StoreBackupManager.createBackupIfStoreExists(
                        reason: .preRestore,
                        storeDirectoryURL: legacyDirectory
                    )
                }
            )
            // T-326: a restore that fails no longer takes the launch down with it. The staged
            // restore leaves the existing store untouched when it throws, so the right move is to
            // open that store normally and say what happened — not to fall through to a recovery
            // store, which used to hide an intact database behind an empty one.
            do {
                try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: storeDirectoryURL)
            } catch {
                failedRestore = StoreBackupManager.lastFailedRestore()
            }
            _ = try StoreBackupManager.createBackupIfStoreExists(
                reason: .startup,
                storeDirectoryURL: storeDirectoryURL
            )
        } catch {
            container = Self.makeRecoveryContainer(
                issue: "Cadence opened a recovery store because backup/restore preflight failed: \(error.localizedDescription)"
            )
            return
        }

        if let c = try? PersistenceController.makeContainer() {
            container = c
            if let failedRestore {
                Self.startupIssue = CadenceStartupIssue(
                    kind: failedRestore.startupIssueKind,
                    message: failedRestore.startupMessage
                )
            }
            let startupContext = ModelContext(c)
            Self.performStartupMaintenance(in: startupContext)
            return
        }
        container = Self.makeRecoveryContainer(
            issue: "Cadence opened a recovery store because the CloudKit store could not be created."
        )
    }

    private static func performStartupMaintenance(in context: ModelContext) {
        // Folds any surviving `Pursuit` rows into `Goal`. Self-guarding and idempotent, and
        // manages its own saves because it deletes rows rather than just inserting them.
        PursuitToGoalMigration.runIfNeeded(modelContext: context)

        // **No pass here seeds the default tags, and that is the point (T-528).**
        //
        // The seed's only signal was "no tag carries this slug", and at launch that sentence has
        // two readings the store cannot tell apart: a user who has never had tags, and a user
        // whose tags have not arrived yet — a reinstall, a second device, a restore, the first
        // seconds of any CloudKit launch. Seeding on the second reading inserts an *active* `bug`
        // beside the archived, recoloured `bug` still in flight; `deduplicateTags` then merges the
        // pair and the tag the user archived is back, active, in the seed's colour, on every
        // synced device. On one device with no CloudKit at all it was simpler and just as wrong:
        // rename `bug` to `Defect` in Settings > Tags and the next launch re-seeded `bug` beside
        // it. Measured against the built app on 2026-08-30 — seven tags in, eight tags out.
        //
        // There is no local signal that separates the two readings, so the fix is not a better
        // guard on the insert; it is that a launch does not insert. `TagSupport.seedDefaultTags`
        // is now reached only from the "Add Defaults" controls that already ship on both
        // platforms, where "no tag carries this slug" has one reading because a person just said
        // so. `CadenceFirstLaunchEmptyStoreTests` holds the launch path to it.
        //
        // This also restores the symmetry `DataIntegrityRepairService`'s own doc comment argues
        // for twelve lines from here: every startup pass is now inert against a store that is
        // empty only because sync has not landed.
        let migrationReport = NoteMigrationService.migrateAndRecordFailure(in: context, source: "app-startup", saveChanges: false)
        let syncedNoteTags = TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
        // `removingForkedOccurrences:` is the app supplying the half of T-622's collapse that
        // `DataIntegrityRepairService` cannot spell: it is in `CadenceMCPServer`'s explicit source
        // list and the task-deletion core is not. Omitting it here would leave forked recurring
        // occurrences uncollapsed on the one launch that matters, silently, so
        // `DataIntegrityRepairServiceTests.theAppStartupRepairSuppliesTheForkedOccurrenceRemover`
        // pins that this argument is present.
        let repairReport = DataIntegrityRepairService.repairAndRecordFailure(
            in: context,
            source: "app-startup",
            saveChanges: false,
            removingForkedOccurrences: CadenceForkedOccurrenceRemover.removeAndCancelReminders
        )
        // T-621's store-wide pass, safe here by the same argument the repair above uses: it only
        // ever raises a counter and is a pure function of the counter and the ledger's rows, so a
        // launch that races the first CloudKit import computes a total that is too low and leaves
        // the counter alone. `bank` already heals the subject it writes to; this is for the task
        // nobody opens again, whose stale total an hours-mode `Goal` is still reading.
        let reconciledFocusMinutes = CadenceFocusLedger.reconcile(in: context)
        let changedStore = (migrationReport?.insertedTotal ?? 0) > 0 ||
            syncedNoteTags ||
            reconciledFocusMinutes ||
            repairReport?.changed == true

        guard changedStore, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            startupIssue = CadenceStartupIssue(
                kind: .maintenanceSaveFailed,
                message: "Cadence could not save startup maintenance changes: \(error.localizedDescription)"
            )
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let storeURL = try resolvedStoreURL()
        if shouldUseLocalStoreOnly {
            let localConfig = ModelConfiguration(
                "Cadence",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [localConfig])
        }

        let cloudConfig = ModelConfiguration(
            "Cadence",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")
        )
        return try ModelContainer(for: schema, configurations: [cloudConfig])
    }

    private static func makeRecoveryContainer(issue: String) -> ModelContainer? {
        startupIssue = CadenceStartupIssue(kind: .recoveryStore, message: issue)
        do {
            let recoveryDirectoryURL = try recoveryStoreDirectoryURL()
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let recoveryConfig = ModelConfiguration(
                "Cadence Recovery",
                schema: schema,
                url: recoveryDirectoryURL.appendingPathComponent("recovery.store"),
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [recoveryConfig])
        } catch {
            startupIssue = CadenceStartupIssue(
                kind: .inMemoryStore,
                message: "\(issue) Recovery store creation also failed, so Cadence opened a temporary in-memory store: \(error.localizedDescription)"
            )
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                // Every store this launch could have opened — CloudKit, an on-disk recovery
                // store, a fully in-memory one — has now failed. There is nothing left to fall
                // back to that is still "the app": `container` stays `nil` and `CadenceApp` shows
                // `CadenceTerminalRecoveryView` instead of building a window group around a store
                // that does not exist.
                terminalFailure = CadenceStartupTerminalFailure(
                    message: "\(issue) In-memory store creation also failed: \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    /// A best-effort, read-only, export-only open of whatever store this device actually has —
    /// tried only from `CadenceTerminalRecoveryView`, after `terminalFailure` is already set.
    ///
    /// This is not a fourth attempt at the sequence above. `init` already tried the primary store
    /// **with CloudKit**, a separate on-disk recovery store **without** it, and a fully in-memory
    /// store, and all three failed before this is ever reachable. What none of those three tried
    /// is the thing this does first: the primary store's own file, local-only, read-only. If the
    /// boot failure was CloudKit's — an unreachable network, a bad container entitlement, a
    /// rejected schema push, all common and all outside this app's control — the user's actual
    /// data is sitting on disk untouched, and this is what gets it into an export instead of
    /// behind a launch-time crash. If the primary store's file cannot be read at all, this falls
    /// back to whatever on-disk recovery stores exist from a previous launch.
    ///
    /// Resolving the real URLs, opening a container and building the archive are three different
    /// functions — `recoveryExportCandidateStoreURLs`, `openReadOnlyStore(at:)` and
    /// `recoverFirstExportableStore` below — for the same reason `recoveryStoreDirectoryURL` is
    /// built on the already-pure `recoveryStoreDirectoryCandidates`: a test can hand the search
    /// real, isolated temporary files, or an injected open and export, without ever touching this
    /// device's actual app-group container.
    static func attemptRecoveryExport(fileManager: FileManager = .default) -> RecoveryExportResult {
        let primaryStoreURL = try? CadenceStoreSupport.primaryStoreURL(fileManager: fileManager)
        let primaryStoreDirectoryURL = try? CadenceStoreSupport.primaryStoreDirectoryURL(fileManager: fileManager)
        let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let candidateStoreURLs = recoveryExportCandidateStoreURLs(
            primaryStoreURL: primaryStoreURL,
            recoveryDirectoryCandidates: recoveryStoreDirectoryCandidates(
                primaryStoreDirectoryURL: primaryStoreDirectoryURL,
                applicationSupportDirectoryURL: applicationSupportDirectoryURL,
                temporaryDirectoryURL: fileManager.temporaryDirectory
            )
        )
        return recoverFirstExportableStore(from: candidateStoreURLs)
    }

    /// The ordered list of store files `attemptRecoveryExport` will try: the
    /// primary store first (if one was resolved at all — a `nil` is dropped, not passed through as
    /// a URL that cannot exist), then each recovery directory's `recovery.store`, in the order
    /// `recoveryStoreDirectoryCandidates` already ranks them.
    ///
    /// Pure and independently testable: given the same two inputs, this always returns the same
    /// list, with no filesystem access at all.
    static func recoveryExportCandidateStoreURLs(
        primaryStoreURL: URL?,
        recoveryDirectoryCandidates: [URL]
    ) -> [URL] {
        var candidateStoreURLs: [URL] = []
        if let primaryStoreURL {
            candidateStoreURLs.append(primaryStoreURL)
        }
        candidateStoreURLs.append(contentsOf: recoveryDirectoryCandidates.map {
            $0.appendingPathComponent("recovery.store")
        })
        return candidateStoreURLs
    }

    /// One candidate that opened and then could not be turned into an archive.
    ///
    /// A candidate that did not open at all is **not** one of these: most launches have no recovery
    /// directory, so an absent store is the ordinary case and reporting it as a failure would bury
    /// the one that matters under noise. What this records is the case T-1099 is about — a store
    /// that is really there, really opened, and still gave nothing back.
    nonisolated struct RecoveryExportFailure: Equatable {
        let storeURL: URL
        let reason: String
    }

    /// An archive, the store it came from, and what was tried before it.
    nonisolated struct RecoveryExport: Equatable {
        let storeURL: URL
        let data: Data
        let recordCount: Int
        /// Stores that opened ahead of this one and failed to export. Non-empty means the screen
        /// has to say so: something on this device was reachable and did not make it into the file.
        let precedingFailures: [RecoveryExportFailure]
    }

    /// What one press of the recovery screen's export button found.
    nonisolated enum RecoveryExportResult: Equatable {
        /// No candidate opened at all.
        case noStoreOpened
        /// Every store that opened refused to export, in the order they were tried.
        case everyOpenedStoreFailed([RecoveryExportFailure])
        case exported(RecoveryExport)
    }

    /// Open each candidate in turn and try to build an archive from it, answering the first one
    /// that produces bytes.
    ///
    /// **T-1099 — this used to stop at the first store that *opened*.** Opening and exporting are
    /// two different failures: `CadenceDataExportService.makeArchive` runs twenty-one throwing
    /// fetches after the open, so a store that is intact enough for SwiftData to attach to and
    /// damaged enough to refuse a fetch ended the search — the second candidate was never reached,
    /// and pressing the button again repeated the same candidate order to the same dead end. The
    /// user was on the one screen in the app that exists because everything else already failed,
    /// and got less of their data out than the device was holding.
    ///
    /// `open` and `export` are parameters so the pair can be driven independently in a test:
    /// producing a store that genuinely opens and genuinely fails to export is not something a
    /// fixture can arrange with a file. Their defaults are the real thing, so the shipped path has
    /// no seam in it.
    ///
    /// What it deliberately does not do: merge stores, or prefer the largest archive. The candidate
    /// order is a ranking — the primary store first — and the first one that can answer wins, the
    /// same contract as before for every case that used to work.
    static func recoverFirstExportableStore(
        from candidateStoreURLs: [URL],
        open: (URL) -> ModelContainer? = { PersistenceController.openReadOnlyStore(at: $0) },
        export: (ModelContainer) throws -> CadenceDataExportOutcome = {
            try CadenceDataExportService.exportArchive(in: ModelContext($0))
        }
    ) -> RecoveryExportResult {
        var failures: [RecoveryExportFailure] = []
        for storeURL in candidateStoreURLs {
            guard let container = open(storeURL) else { continue }
            do {
                let outcome = try export(container)
                return .exported(RecoveryExport(
                    storeURL: storeURL,
                    data: outcome.data,
                    recordCount: outcome.recordCount,
                    precedingFailures: failures
                ))
            } catch {
                failures.append(RecoveryExportFailure(storeURL: storeURL, reason: error.localizedDescription))
            }
        }
        return failures.isEmpty ? .noStoreOpened : .everyOpenedStoreFailed(failures)
    }

    /// Opens one store file read-only, with CloudKit switched off. `nil` if it does not open.
    ///
    /// No explicit existence check runs before the open, and that absence is measured rather than
    /// assumed: a `FileManager.fileExists` guard sat here first, a mutation dropped it, and every
    /// test in this file still passed. `allowsSave: false` against a URL with no store there
    /// already refuses instead of creating one — the exact asymmetry
    /// `CadenceSharedStoreWriteGateTests.aWriteCapableOpenCreatesAMissingStoreAndAReadOnlyOpenDoesNot`
    /// measures for T-311 — so a second, redundant check here could only ever restate a guarantee
    /// `allowsSave: false` already gives for free. `allowsSave: false` is spelled explicitly below
    /// rather than left to a shared default, because it is the one line actually standing between
    /// this recovery path and writing into a store it did not create — and a "successful" open of
    /// an empty store it *did* just create would tell someone their data was recovered when
    /// nothing was, the opposite of what this screen exists to be honest about.
    static func openReadOnlyStore(at storeURL: URL) -> ModelContainer? {
        let configuration = ModelConfiguration(
            "Cadence Recovery Export",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [configuration])
    }

    static func recoveryStoreDirectoryCandidates(
        primaryStoreDirectoryURL: URL?,
        applicationSupportDirectoryURL: URL?,
        temporaryDirectoryURL: URL
    ) -> [URL] {
        var seenPaths: Set<String> = []
        return [
            primaryStoreDirectoryURL?.appendingPathComponent("Recovery", isDirectory: true),
            applicationSupportDirectoryURL?
                .appendingPathComponent("Cadence", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true),
            temporaryDirectoryURL
                .appendingPathComponent("Cadence", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true),
        ]
        .compactMap(\.self)
        .filter { candidate in
            seenPaths.insert(candidate.standardizedFileURL.path).inserted
        }
    }

    private static func recoveryStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let primaryStoreDirectoryURL = try? CadenceStoreSupport.primaryStoreDirectoryURL(fileManager: fileManager)
        let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var lastError: Error?

        for candidate in recoveryStoreDirectoryCandidates(
            primaryStoreDirectoryURL: primaryStoreDirectoryURL,
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            temporaryDirectoryURL: fileManager.temporaryDirectory
        ) {
            do {
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
                return candidate
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private static var shouldUseLocalStoreOnly: Bool {
        isRunningTests ||
            ProcessInfo.processInfo.environment["CADENCE_LOCAL_STORE_ONLY"] == "1" ||
            ProcessInfo.processInfo.environment["CADENCE_UI_TEST_MODE"] == "1"
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil ||
            environment["CADENCE_UI_TEST_MODE"] == "1"
    }

    private static var shouldResetStoreOnLaunch: Bool {
        ProcessInfo.processInfo.environment["CADENCE_RESET_STORE"] == "1"
    }

    /// Lock this launch's store directory and remove the ones no live process owns.
    ///
    /// The whole answer to [[T-1090]] is here rather than in `CadenceUITests`, and the reason is
    /// on `CadenceUITestStoreDirectory`: the UI-test runner is sandboxed with a read-only
    /// exception over `/` and cannot delete anything inside the app's container. Which launches
    /// sweep, and why that is narrower than which launches get a private store, is argued there
    /// too.
    private static func claimUITestStoreDirectoryIfNeeded() {
        guard let id = CadenceUITestStoreDirectory.sweepingLaunchID(
            in: ProcessInfo.processInfo.environment
        ) else { return }
        CadenceUITestStoreDirectory.claimAndSweep(id: id, in: CadenceUITestStoreDirectory.rootDirectory())
    }

    private static func resolvedStoreURL() throws -> URL {
        if let safeID = CadenceUITestStoreDirectory.directoryID(in: ProcessInfo.processInfo.environment) {
            let storeDirectoryURL = CadenceUITestStoreDirectory.rootDirectory()
                .appendingPathComponent(safeID, isDirectory: true)
            try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
            return storeDirectoryURL.appendingPathComponent("default.store")
        }

        if isRunningTests {
            let testStoreDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CadenceTestsHostStore", isDirectory: true)
            try FileManager.default.createDirectory(at: testStoreDirectoryURL, withIntermediateDirectories: true)
            return testStoreDirectoryURL.appendingPathComponent("default.store")
        }

        return try CadenceStoreSupport.primaryStoreURL()
    }

    private static func deleteResolvedStoreDirectory() {
        guard let storeURL = try? resolvedStoreURL() else { return }
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}

enum StoreBackupReason: String, Codable {
    case startup
    case manual
    case preRestore = "pre-restore"

    var displayName: String {
        switch self {
        case .startup: return "Startup"
        case .manual: return "Manual"
        case .preRestore: return "Before Restore"
        }
    }
}

struct StoreBackupSnapshot: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date
    let reason: String
    let sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

private struct StoreBackupManifest: Codable {
    let createdAt: Date
    let reason: StoreBackupReason
    let sourceStoreURL: String
    let items: [String]
}

enum StoreBackupManager {
    private static let backupDirectoryName = "Cadence Store Backups"
    private static let manifestName = "manifest.json"
    private static let pendingRestoreDefaultsKey = "cadence.pendingStoreRestoreURL"
    private static let failedRestoreDefaultsKey = "cadence.failedStoreRestore"
    /// Where a restore is assembled before it is allowed to replace anything, and where the store
    /// it replaces waits until the swap has finished. Both are hidden siblings of the store items
    /// inside the store directory, so a rename between them never crosses a volume, and neither
    /// name is in `CadenceStoreSupport.managedStoreItemNames`, so neither is ever mistaken for
    /// part of the store.
    private static let restoreStagingDirectoryName = ".cadence-restore-staging.tmp"
    private static let restoreDisplacedDirectoryName = ".cadence-restore-previous.tmp"
    /// Where originals a rollback could **not** put back are kept (T-1100), and the one directory
    /// in this file nothing ever deletes.
    ///
    /// Deliberately not a `.tmp` sibling of the two above: those two are scratch, and every path
    /// here is entitled to remove scratch. This is the user's own store files, held because the
    /// only other option is destroying them, and the name is what makes "scratch" and "the last
    /// copy of your data" two different things a later restore can tell apart. Visible rather than
    /// dotted, because `FailedRestoreRecord` names the path in a banner and a hidden folder is a
    /// worse answer to "where is my data" than a visible one.
    private static let unrestoredOriginalsDirectoryPrefix = "Cadence Unrestored Store Files"
    private static let denseStartupBackupCount = 5
    private static let dailyStartupRetentionDays = 7
    private static let weeklyStartupRetentionWeeks = 4
    private static let maxPreRestoreBackups = 5

    /// A restore that failed **and** could not be completely undone (T-1100).
    ///
    /// Its own type rather than a `CocoaError`, because the two facts a caller has to act on —
    /// that the store directory is no longer what it was, and where the originals went — cannot be
    /// recovered from a string. `performPendingRestoreIfNeeded` reads `retainedOriginalsPath` off
    /// it to build the record the banner shows; `errorDescription` is what a caller that only
    /// prints `localizedDescription` gets, so it has to carry the same three facts in prose.
    nonisolated struct RestoreRollbackFailure: LocalizedError, Equatable {
        /// The failure that started the rollback.
        let underlyingReason: String
        /// The store items the rollback could not put back, sorted.
        let unrestoredItemNames: [String]
        /// Where those items are now. Never empty, and never deleted by this app.
        let retainedOriginalsPath: String

        var errorDescription: String? {
            let items = unrestoredItemNames.joined(separator: ", ")
            return "\(underlyingReason) Undoing the restore then failed as well: \(items) could not be put back, so \(unrestoredItemNames.count == 1 ? "it was" : "they were") kept in \(retainedOriginalsPath) rather than deleted."
        }
    }

    /// A restore that was scheduled, attempted, and failed — kept instead of the pending key so
    /// the next launch reads it as history rather than as an instruction.
    nonisolated struct FailedRestoreRecord: Codable, Equatable {
        let backupPath: String
        let backupName: String
        let failedAt: Date
        let reason: String
        /// Set **only** when the rollback could not put every displaced original back (T-1100):
        /// the folder those originals were kept in instead. `nil` — the ordinary failed restore —
        /// means the store directory holds exactly what it held before the attempt.
        ///
        /// Optional so a record written before this field existed still decodes: a synthesized
        /// `init(from:)` reads a missing key for an `Optional` as `nil` rather than throwing, and
        /// a launch that threw away its own failure record would be a second defect on top of the
        /// first.
        let retainedOriginalsPath: String?

        init(
            backupPath: String,
            backupName: String,
            failedAt: Date,
            reason: String,
            retainedOriginalsPath: String? = nil
        ) {
            self.backupPath = backupPath
            self.backupName = backupName
            self.failedAt = failedAt
            self.reason = reason
            self.retainedOriginalsPath = retainedOriginalsPath
        }

        var backupURL: URL { URL(fileURLWithPath: backupPath, isDirectory: true) }

        /// What the startup banner says. It has to state the outcome the user cannot see for
        /// themselves — that their existing data is still there — because the visible evidence of
        /// a failed restore is that nothing changed, which is indistinguishable from nothing
        /// having been asked for.
        ///
        /// **T-1100: exactly one of these two sentences is true, and the record is what knows
        /// which.** "It kept the data already on this device" is a claim about the store directory,
        /// and a rollback that could not replace every original it moved aside has not earned it —
        /// the store there is part backup, part original, and the rest is in the retained folder.
        /// The second sentence says that, and says where, because the path is the only thing that
        /// makes those files findable.
        var startupMessage: String {
            guard let retainedOriginalsPath else {
                return "Cadence could not restore the backup \(backupName), so it kept the data already on this device: \(reason) The restore was not applied and will not be retried on its own."
            }
            return "Cadence could not restore the backup \(backupName), and could not put every file it had moved aside back where it found it: \(reason) Nothing was deleted — those files were kept in \(retainedOriginalsPath). The restore will not be retried on its own."
        }

        /// Which banner this record earns. The two differ in what they promise about the store, so
        /// the choice belongs with the fact that decides it rather than at the call site.
        var startupIssueKind: CadenceStartupIssueKind {
            retainedOriginalsPath == nil ? .restoreFailed : .restoreIncomplete
        }
    }

    static var backupRootURL: URL {
        (try? defaultStoreDirectoryURL().appendingPathComponent(backupDirectoryName, isDirectory: true))
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    @discardableResult
    static func createBackupIfStoreExists(reason: StoreBackupReason) throws -> URL? {
        try createBackupIfStoreExists(reason: reason, storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func createBackupIfStoreExists(
        reason: StoreBackupReason,
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL? {
        let sourceItems = existingStoreItems(in: storeDirectoryURL, fileManager: fileManager)
        guard !sourceItems.isEmpty else { return nil }

        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        let now = Date()
        let finalURL = uniqueBackupDirectory(
            for: now,
            reason: reason,
            storeDirectoryURL: storeDirectoryURL,
            fileManager: fileManager
        )
        let temporaryURL = backupRootURL.appendingPathComponent(".\(finalURL.lastPathComponent).tmp", isDirectory: true)

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        var copiedNames: [String] = []
        do {
            for source in sourceItems {
                let destination = temporaryURL.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
                copiedNames.append(source.lastPathComponent)
            }

            let manifest = StoreBackupManifest(
                createdAt: now,
                reason: reason,
                sourceStoreURL: storeDirectoryURL.appendingPathComponent("default.store").path,
                items: copiedNames
            )
            let manifestData = try JSONEncoder.cadenceBackupEncoder.encode(manifest)
            try manifestData.write(to: temporaryURL.appendingPathComponent(manifestName), options: .atomic)

            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            if reason == .startup || reason == .preRestore {
                try purgeAutomaticBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
            }
            return finalURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func listBackups() -> [StoreBackupSnapshot] {
        listBackups(storeDirectoryURL: try? defaultStoreDirectoryURL())
    }

    static func listBackups(storeDirectoryURL: URL?, fileManager: FileManager = .default) -> [StoreBackupSnapshot] {
        guard let storeDirectoryURL else { return [] }
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: backupRootURL,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let manifest = manifest(at: url, fileManager: fileManager)
            let createdAt = manifest?.createdAt
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast
            return StoreBackupSnapshot(
                id: url.lastPathComponent,
                url: url,
                createdAt: createdAt,
                reason: manifest?.reason.displayName ?? "Backup",
                sizeBytes: directorySize(url, fileManager: fileManager)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func cleanUpAutomaticBackups() throws -> Int {
        try cleanUpAutomaticBackups(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func cleanUpAutomaticBackups(storeDirectoryURL: URL, fileManager: FileManager = .default) throws -> Int {
        let removableBackups = automaticBackupSnapshotsToRemove(
            listBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
        )
        for snapshot in removableBackups {
            try fileManager.removeItem(at: snapshot.url)
        }
        return removableBackups.count
    }

    @discardableResult
    static func deleteAllBackups() throws -> Int {
        try deleteAllBackups(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    /// Every folder of originals a failed rollback retained, oldest name first (T-1100).
    static func retainedUnrestoredOriginalDirectories(
        in storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        ((try? fileManager.contentsOfDirectory(atPath: storeDirectoryURL.path)) ?? [])
            .filter { $0.hasPrefix(unrestoredOriginalsDirectoryPrefix) }
            .sorted()
            .map { storeDirectoryURL.appendingPathComponent($0, isDirectory: true) }
    }

    /// Delete them.
    ///
    /// Reached from the privacy reset, and deliberately **not** from `deleteAllBackups`: a user
    /// clearing backups in Settings is managing disk space, and this folder is the last copy of
    /// store files a restore could not put back. A user who asks Cadence to delete *their data* is
    /// asking for it, though — leaving a copy of the store inside the app's own container would be
    /// the reset claiming more than it did, which is the same promise `docs/privacy.html` makes and
    /// T-1101 had to repair for the Keychain.
    @discardableResult
    static func deleteRetainedUnrestoredOriginals() throws -> Int {
        try deleteRetainedUnrestoredOriginals(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func deleteRetainedUnrestoredOriginals(
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let retained = retainedUnrestoredOriginalDirectories(in: storeDirectoryURL, fileManager: fileManager)
        for directoryURL in retained {
            try fileManager.removeItem(at: directoryURL)
        }
        return retained.count
    }

    @discardableResult
    static func deleteAllBackups(storeDirectoryURL: URL) throws -> Int {
        let snapshots = listBackups(storeDirectoryURL: storeDirectoryURL)
        let backupRootURL = backupRootURL(for: storeDirectoryURL)

        if FileManager.default.fileExists(atPath: backupRootURL.path) {
            try FileManager.default.removeItem(at: backupRootURL)
        }

        return snapshots.count
    }

    /// - Parameter storeDirectoryURL: the store this restore is aimed at, `nil` for the real one.
    ///   It is needed because the pending restore is also recorded *beside the store* — see
    ///   `CadenceStoreSupport.restorePendingMarkerName` — so that the widget extension, which does
    ///   not share `UserDefaults.standard`, can see that a restore is about to replace whatever it
    ///   would write (T-311).
    static func scheduleRestore(
        from backupURL: URL,
        defaults: UserDefaults = CadenceDefaults.store,
        storeDirectoryURL: URL? = nil
    ) throws {
        guard isBackupDirectory(backupURL) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // A freshly chosen backup supersedes whatever failed last time; otherwise the record of
        // the old failure would outlive the reason anyone would still care about it.
        defaults.removeObject(forKey: failedRestoreDefaultsKey)
        defaults.set(backupURL.path, forKey: pendingRestoreDefaultsKey)
        setSharedRestorePendingMarker(true, storeDirectoryURL: storeDirectoryURL)
    }

    static func clearPendingRestore(defaults: UserDefaults = CadenceDefaults.store, storeDirectoryURL: URL? = nil) {
        defaults.removeObject(forKey: pendingRestoreDefaultsKey)
        setSharedRestorePendingMarker(false, storeDirectoryURL: storeDirectoryURL)
    }

    /// Keep the app-group marker in step with the pending-restore key. Resolving the store
    /// directory here rather than at each call site keeps the two writes in one place, which is
    /// the only way the marker cannot outlive the thing it stands for.
    private static func setSharedRestorePendingMarker(_ pending: Bool, storeDirectoryURL: URL?) {
        guard let directoryURL = storeDirectoryURL ?? (try? defaultStoreDirectoryURL()) else { return }
        CadenceStoreSupport.setRestorePending(pending, inStoreDirectory: directoryURL)
    }

    static func pendingRestoreURL(defaults: UserDefaults = CadenceDefaults.store) -> URL? {
        guard let storedPath = defaults.string(forKey: pendingRestoreDefaultsKey), !storedPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: storedPath, isDirectory: true)
    }

    /// The restore Cadence tried, failed at, and refused to try again on its own.
    static func lastFailedRestore(defaults: UserDefaults = CadenceDefaults.store) -> FailedRestoreRecord? {
        guard let data = defaults.data(forKey: failedRestoreDefaultsKey) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(FailedRestoreRecord.self, from: data)
    }

    static func clearFailedRestore(defaults: UserDefaults = CadenceDefaults.store) {
        defaults.removeObject(forKey: failedRestoreDefaultsKey)
    }

    static func performPendingRestoreIfNeeded() throws {
        try performPendingRestoreIfNeeded(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    /// Apply the restore the user scheduled on a previous launch, or do nothing.
    ///
    /// **T-326.** This used to remove the live store items *first* and copy the backup over them
    /// second, clearing the pending flag only after the last copy landed. Anything that threw in
    /// between — a full disk, a damaged sidecar inside the backup, a permission failure, an
    /// interrupted copy — left the user with no store **and** the pending restore still set: the
    /// app fell back to a recovery store, and the next launch ran the same failing restore again.
    /// Their data was sitting in the pre-restore backup and nothing told them so.
    ///
    /// The ordering now matches the one backup *creation* has used all along, about 130 lines
    /// above: assemble the whole replacement in a `.tmp` sibling, verify it, and only then swap.
    /// Nothing live is removed until a complete, verified replacement exists, and the swap itself
    /// moves the old items aside rather than deleting them so a failure mid-swap puts them back.
    ///
    /// A restore that fails is **quarantined** rather than left pending, so a launch cannot wedge.
    static func performPendingRestoreIfNeeded(
        storeDirectoryURL: URL,
        fileManager: FileManager = .default,
        defaults: UserDefaults = CadenceDefaults.store
    ) throws {
        guard let backupURL = pendingRestoreURL(defaults: defaults) else {
            // The launch is also where a stale app-group marker gets reconciled against the key it
            // mirrors. Without this, a marker that outlived its restore would refuse every widget
            // write from then on, and only a reinstall would clear it.
            CadenceStoreSupport.setRestorePending(false, inStoreDirectory: storeDirectoryURL)
            return
        }
        guard isBackupDirectory(backupURL, fileManager: fileManager) else {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: "The backup folder is missing, or no longer looks like a Cadence backup.",
                defaults: defaults,
                storeDirectoryURL: storeDirectoryURL
            )
            throw CocoaError(.fileReadNoSuchFile)
        }

        do {
            try applyRestore(from: backupURL, into: storeDirectoryURL, fileManager: fileManager)
        } catch {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: error.localizedDescription,
                // The one thing the banner cannot infer from prose: this failure left files
                // somewhere other than where the user's store lives (T-1100).
                retainedOriginalsPath: (error as? RestoreRollbackFailure)?.retainedOriginalsPath,
                defaults: defaults,
                storeDirectoryURL: storeDirectoryURL
            )
            throw error
        }

        clearFailedRestore(defaults: defaults)
        clearPendingRestore(defaults: defaults, storeDirectoryURL: storeDirectoryURL)
    }

    /// Stage, verify, swap. Every `throw` in here leaves the live store exactly as it was.
    private static func applyRestore(
        from backupURL: URL,
        into storeDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        _ = try createBackupIfStoreExists(
            reason: .preRestore,
            storeDirectoryURL: storeDirectoryURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        let stagingURL = storeDirectoryURL.appendingPathComponent(restoreStagingDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let stagedNames = try stageBackupContents(of: backupURL, into: stagingURL, fileManager: fileManager)
        try verifyStagedRestore(
            at: stagingURL,
            from: backupURL,
            stagedNames: stagedNames,
            fileManager: fileManager
        )
        try swapStagedRestore(
            at: stagingURL,
            names: stagedNames,
            into: storeDirectoryURL,
            fileManager: fileManager
        )
    }

    private static func stageBackupContents(
        of backupURL: URL,
        into stagingURL: URL,
        fileManager: FileManager
    ) throws -> [String] {
        let backupContents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        var stagedNames: [String] = []
        for source in backupContents where source.lastPathComponent != manifestName {
            try fileManager.copyItem(at: source, to: stagingURL.appendingPathComponent(source.lastPathComponent))
            stagedNames.append(source.lastPathComponent)
        }
        return stagedNames
    }

    /// A staged copy only earns the right to replace the live store if it is complete.
    ///
    /// Three things have to hold: the store file itself is present, everything the backup's own
    /// manifest claims is present, and every staged item is byte-for-byte the same size as the
    /// item it was copied from. The last one is the point — a copy that stopped early still leaves
    /// a file at the destination, so an existence check alone would wave a truncated store through
    /// and swap it over a good one.
    private static func verifyStagedRestore(
        at stagingURL: URL,
        from backupURL: URL,
        stagedNames: [String],
        fileManager: FileManager
    ) throws {
        let stagedNameSet = Set(stagedNames)
        guard stagedNameSet.contains(CadenceStoreSupport.storeFilename) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let manifestItems = Set(manifest(at: backupURL, fileManager: fileManager)?.items ?? [])
            .subtracting([manifestName])
        guard manifestItems.isSubset(of: stagedNameSet) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        for name in stagedNames {
            guard let sourceSize = itemSize(of: backupURL.appendingPathComponent(name), fileManager: fileManager),
                  let stagedSize = itemSize(of: stagingURL.appendingPathComponent(name), fileManager: fileManager),
                  sourceSize == stagedSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    /// Move the live items aside, move the verified ones in, and only then drop the old copy.
    ///
    /// Several files have to change together and no single rename covers all of them, so this is
    /// the one window that cannot be made atomic outright. The displaced directory is what closes
    /// it: anything that throws part-way puts every displaced item back where it was.
    ///
    /// **T-1100 — the rollback used to delete the displaced directory whether or not it had
    /// emptied it.** Both compensating operations were `try?`, and the removal beneath them was
    /// unconditional, so a rollback that could not move an original back deleted that original a
    /// line later: the one outcome this whole staged design exists to prevent, reached through the
    /// code written to prevent it. A single filesystem fault is not the case that needs
    /// arguing — the forward move and the compensating move are the same operation on the same
    /// volume, so whatever refused one is available to refuse the other.
    ///
    /// The rule now: **nothing here removes a directory it did not empty.** A rollback that leaves
    /// anything behind retains that folder under `unrestoredOriginalsDirectoryPrefix` and reports
    /// where, and both the removal *and* the move-back stop being swallowed — a removal that fails
    /// makes the move-back onto the same path fail, which is now recorded rather than lost.
    private static func swapStagedRestore(
        at stagingURL: URL,
        names: [String],
        into storeDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let displacedURL = storeDirectoryURL.appendingPathComponent(restoreDisplacedDirectoryName, isDirectory: true)
        // A displaced directory that is already here is not this call's scratch: it is the
        // originals of a swap that never finished — the process killed mid-move, or a rollback
        // that could not complete. Removing it to reuse the path is the same deletion the catch
        // below refuses to make, one launch later. Retaining it first `throw`s if it cannot,
        // before anything live has been touched.
        if fileManager.fileExists(atPath: displacedURL.path) {
            _ = try retainUnrestoredOriginals(at: displacedURL, in: storeDirectoryURL, fileManager: fileManager)
        }
        try fileManager.createDirectory(at: displacedURL, withIntermediateDirectories: true)

        var displacedNames: [String] = []
        var installedNames: [String] = []
        do {
            for item in existingStoreItems(in: storeDirectoryURL, fileManager: fileManager) {
                try fileManager.moveItem(at: item, to: displacedURL.appendingPathComponent(item.lastPathComponent))
                displacedNames.append(item.lastPathComponent)
            }
            for name in names {
                try fileManager.moveItem(
                    at: stagingURL.appendingPathComponent(name),
                    to: storeDirectoryURL.appendingPathComponent(name)
                )
                installedNames.append(name)
            }
        } catch {
            // Only the items this call put there. Anything still sitting in the store directory
            // under a staged name is an original that was never displaced, and deleting that is
            // the very failure this method exists to prevent.
            for name in installedNames {
                try? fileManager.removeItem(at: storeDirectoryURL.appendingPathComponent(name))
            }
            var unrestoredNames: [String] = []
            for name in displacedNames {
                do {
                    try fileManager.moveItem(
                        at: displacedURL.appendingPathComponent(name),
                        to: storeDirectoryURL.appendingPathComponent(name)
                    )
                } catch {
                    unrestoredNames.append(name)
                }
            }
            guard unrestoredNames.isEmpty else {
                // The originals still in there are the only copy of themselves. If even the
                // retaining move fails, the displaced directory keeps its own name and is reported
                // under it — still not deleted, which is the whole promise.
                let retainedURL = (try? retainUnrestoredOriginals(
                    at: displacedURL,
                    in: storeDirectoryURL,
                    fileManager: fileManager
                )) ?? displacedURL
                throw RestoreRollbackFailure(
                    underlyingReason: error.localizedDescription,
                    unrestoredItemNames: unrestoredNames.sorted(),
                    retainedOriginalsPath: retainedURL.path
                )
            }
            // Empty by the loop above, and only then removed.
            try? fileManager.removeItem(at: displacedURL)
            throw error
        }

        try? fileManager.removeItem(at: displacedURL)
    }

    /// Move a folder of originals somewhere no restore will reuse, and answer where it went.
    ///
    /// The timestamped name is the point: two failures a week apart are two folders, not one
    /// overwriting the other, and `-2` suffixes settle the same-second collision the way
    /// `uniqueBackupDirectory` already does for backups. The prefix is not in
    /// `CadenceStoreSupport.managedStoreItemNames`, so no store scan, backup or migration reads
    /// what is inside it as part of the store.
    private static func retainUnrestoredOriginals(
        at displacedURL: URL,
        in storeDirectoryURL: URL,
        now: Date = Date(),
        fileManager: FileManager
    ) throws -> URL {
        let baseName = "\(unrestoredOriginalsDirectoryPrefix) \(DateFormatters.backupFolderTimestamp.string(from: now))"
        var candidate = storeDirectoryURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = storeDirectoryURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.moveItem(at: displacedURL, to: candidate)
        return candidate
    }

    /// Take a failing restore off the launch path without throwing away what it was.
    ///
    /// Clearing alone would stop the loop, and that is what the old code did for a backup folder
    /// that no longer parses — but it also erases the fact that the user asked for a restore, which
    /// is the one thing they need to see afterwards. Quarantining moves the intent out of the key
    /// the launch reads and into a record the startup banner names, so a second attempt is a
    /// decision the user makes rather than something a launch does to itself.
    private static func quarantinePendingRestore(
        backupURL: URL,
        reason: String,
        retainedOriginalsPath: String? = nil,
        defaults: UserDefaults,
        storeDirectoryURL: URL? = nil
    ) {
        let record = FailedRestoreRecord(
            backupPath: backupURL.path,
            backupName: backupURL.lastPathComponent,
            failedAt: Date(),
            reason: reason,
            retainedOriginalsPath: retainedOriginalsPath
        )
        if let data = try? JSONEncoder.cadenceBackupEncoder.encode(record) {
            defaults.set(data, forKey: failedRestoreDefaultsKey)
        }
        clearPendingRestore(defaults: defaults, storeDirectoryURL: storeDirectoryURL)
    }

    /// The size of one backed-up item, whether it is a file or one of the store's sidecar folders.
    private static func itemSize(of url: URL, fileManager: FileManager) -> Int64? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return directorySize(url, fileManager: fileManager)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private static func defaultStoreDirectoryURL() throws -> URL {
        try CadenceStoreSupport.primaryStoreDirectoryURL()
    }

    private static func existingStoreItems(in storeDirectoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        CadenceStoreSupport.storeItemURLs(in: storeDirectoryURL, fileManager: fileManager)
    }

    private static func backupRootURL(for storeDirectoryURL: URL) -> URL {
        storeDirectoryURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    private static func uniqueBackupDirectory(
        for date: Date,
        reason: StoreBackupReason,
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        let baseName = "\(DateFormatters.backupFolderTimestamp.string(from: date))-\(reason.rawValue)"
        var candidate = backupRootURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = backupRootURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func isBackupDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let manifestURL = url.appendingPathComponent(manifestName)
        let storeURL = url.appendingPathComponent(CadenceStoreSupport.storeFilename)
        return fileManager.fileExists(atPath: manifestURL.path)
            && fileManager.fileExists(atPath: storeURL.path)
    }

    private static func manifest(at url: URL, fileManager: FileManager = .default) -> StoreBackupManifest? {
        let manifestURL = url.appendingPathComponent(manifestName)
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(StoreBackupManifest.self, from: data)
    }

    private static func purgeAutomaticBackups(storeDirectoryURL: URL, fileManager: FileManager = .default) throws {
        try cleanUpAutomaticBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
    }

    static func automaticBackupSnapshotsToRemove(
        _ snapshots: [StoreBackupSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [StoreBackupSnapshot] {
        let startupDisplayName = StoreBackupReason.startup.displayName
        let preRestoreDisplayName = StoreBackupReason.preRestore.displayName
        let startupBackups = snapshots
            .filter { $0.reason == startupDisplayName }
            .sorted { $0.createdAt > $1.createdAt }
        let preRestoreBackups = snapshots
            .filter { $0.reason == preRestoreDisplayName }
            .sorted { $0.createdAt > $1.createdAt }

        var keptIDs = retainedStartupBackupIDs(
            startupBackups,
            now: now,
            calendar: calendar
        )
        keptIDs.formUnion(preRestoreBackups.prefix(maxPreRestoreBackups).map(\.id))

        return snapshots.filter { snapshot in
            (snapshot.reason == startupDisplayName || snapshot.reason == preRestoreDisplayName)
                && !keptIDs.contains(snapshot.id)
        }
    }

    private static func retainedStartupBackupIDs(
        _ backups: [StoreBackupSnapshot],
        now: Date,
        calendar inputCalendar: Calendar
    ) -> Set<String> {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let today = calendar.startOfDay(for: now)
        var retained = Set<String>()
        var retainedDayBuckets = Set<String>()
        var retainedWeekBuckets = Set<String>()

        func ageInDays(for date: Date) -> Int? {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day
        }

        func dayBucket(for date: Date) -> String {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        }

        func weekBucket(for date: Date) -> String {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        }

        func rememberBuckets(for snapshot: StoreBackupSnapshot) {
            guard let age = ageInDays(for: snapshot.createdAt), age >= 0 else { return }
            if age < dailyStartupRetentionDays {
                retainedDayBuckets.insert(dayBucket(for: snapshot.createdAt))
            } else if age < dailyStartupRetentionDays + weeklyStartupRetentionWeeks * 7 {
                retainedWeekBuckets.insert(weekBucket(for: snapshot.createdAt))
            }
        }

        for snapshot in backups.prefix(denseStartupBackupCount) {
            retained.insert(snapshot.id)
            rememberBuckets(for: snapshot)
        }

        for snapshot in backups.dropFirst(denseStartupBackupCount) {
            guard let age = ageInDays(for: snapshot.createdAt) else { continue }
            if age < 0 {
                retained.insert(snapshot.id)
            } else if age < dailyStartupRetentionDays {
                let bucket = dayBucket(for: snapshot.createdAt)
                if retainedDayBuckets.insert(bucket).inserted {
                    retained.insert(snapshot.id)
                }
            } else if age < dailyStartupRetentionDays + weeklyStartupRetentionWeeks * 7 {
                let bucket = weekBucket(for: snapshot.createdAt)
                if retainedWeekBuckets.insert(bucket).inserted {
                    retained.insert(snapshot.id)
                }
            }
        }
        return retained
    }

    private static func directorySize(_ url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else {
            return 0
        }

        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                return
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
    }
}

private extension JSONEncoder {
    static var cadenceBackupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var cadenceBackupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()
    /// The one startup problem this launch hit, if any.
    ///
    /// Structured rather than a bare `String` since T-153: two of the three things that can be
    /// recorded here leave the store with `cloudKitDatabase: .none`, and the third does not touch
    /// sync at all. Every surface that showed this used to have to guess which from the prose.
    private(set) static var startupIssue: CadenceStartupIssue?

    let container: ModelContainer

    static let schema = CadenceSchema.schema

    init() {
        if Self.shouldResetStoreOnLaunch {
            Self.deleteResolvedStoreDirectory()
        }

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
                    kind: .restoreFailed,
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

        let migrationReport = NoteMigrationService.migrateAndRecordFailure(in: context, source: "app-startup", saveChanges: false)
        let seededDefaultTags = TagSupport.seedDefaultTags(in: context, saveChanges: false)
        let syncedNoteTags = TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
        let repairReport = DataIntegrityRepairService.repairAndRecordFailure(in: context, source: "app-startup", saveChanges: false)
        let changedStore = (migrationReport?.insertedTotal ?? 0) > 0 ||
            seededDefaultTags ||
            syncedNoteTags ||
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

    private static func makeRecoveryContainer(issue: String) -> ModelContainer {
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
                fatalError("\(issue) In-memory recovery store creation also failed: \(error.localizedDescription)")
            }
        }
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

    private static func resolvedStoreURL() throws -> URL {
        if let uiTestStoreID = ProcessInfo.processInfo.environment["CADENCE_UI_TEST_STORE_ID"],
           !uiTestStoreID.isEmpty {
            let safeID = uiTestStoreID.replacingOccurrences(of: "/", with: "-")
            let storeDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CadenceUITestStores", isDirectory: true)
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
    private static let denseStartupBackupCount = 5
    private static let dailyStartupRetentionDays = 7
    private static let weeklyStartupRetentionWeeks = 4
    private static let maxPreRestoreBackups = 5

    /// A restore that was scheduled, attempted, and failed — kept instead of the pending key so
    /// the next launch reads it as history rather than as an instruction.
    nonisolated struct FailedRestoreRecord: Codable, Equatable {
        let backupPath: String
        let backupName: String
        let failedAt: Date
        let reason: String

        var backupURL: URL { URL(fileURLWithPath: backupPath, isDirectory: true) }

        /// What the startup banner says. It has to state the outcome the user cannot see for
        /// themselves — that their existing data is still there — because the visible evidence of
        /// a failed restore is that nothing changed, which is indistinguishable from nothing
        /// having been asked for.
        var startupMessage: String {
            "Cadence could not restore the backup \(backupName), so it kept the data already on this device: \(reason) The restore was not applied and will not be retried on its own."
        }
    }

    private static let folderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

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

    @discardableResult
    static func deleteAllBackups(storeDirectoryURL: URL) throws -> Int {
        let snapshots = listBackups(storeDirectoryURL: storeDirectoryURL)
        let backupRootURL = backupRootURL(for: storeDirectoryURL)

        if FileManager.default.fileExists(atPath: backupRootURL.path) {
            try FileManager.default.removeItem(at: backupRootURL)
        }

        return snapshots.count
    }

    static func scheduleRestore(from backupURL: URL, defaults: UserDefaults = .standard) throws {
        guard isBackupDirectory(backupURL) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // A freshly chosen backup supersedes whatever failed last time; otherwise the record of
        // the old failure would outlive the reason anyone would still care about it.
        defaults.removeObject(forKey: failedRestoreDefaultsKey)
        defaults.set(backupURL.path, forKey: pendingRestoreDefaultsKey)
    }

    static func clearPendingRestore(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingRestoreDefaultsKey)
    }

    static func pendingRestoreURL(defaults: UserDefaults = .standard) -> URL? {
        guard let storedPath = defaults.string(forKey: pendingRestoreDefaultsKey), !storedPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: storedPath, isDirectory: true)
    }

    /// The restore Cadence tried, failed at, and refused to try again on its own.
    static func lastFailedRestore(defaults: UserDefaults = .standard) -> FailedRestoreRecord? {
        guard let data = defaults.data(forKey: failedRestoreDefaultsKey) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(FailedRestoreRecord.self, from: data)
    }

    static func clearFailedRestore(defaults: UserDefaults = .standard) {
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
        defaults: UserDefaults = .standard
    ) throws {
        guard let backupURL = pendingRestoreURL(defaults: defaults) else { return }
        guard isBackupDirectory(backupURL, fileManager: fileManager) else {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: "The backup folder is missing, or no longer looks like a Cadence backup.",
                defaults: defaults
            )
            throw CocoaError(.fileReadNoSuchFile)
        }

        do {
            try applyRestore(from: backupURL, into: storeDirectoryURL, fileManager: fileManager)
        } catch {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: error.localizedDescription,
                defaults: defaults
            )
            throw error
        }

        clearFailedRestore(defaults: defaults)
        clearPendingRestore(defaults: defaults)
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
    private static func swapStagedRestore(
        at stagingURL: URL,
        names: [String],
        into storeDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let displacedURL = storeDirectoryURL.appendingPathComponent(restoreDisplacedDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: displacedURL.path) {
            try fileManager.removeItem(at: displacedURL)
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
            for name in displacedNames {
                try? fileManager.moveItem(
                    at: displacedURL.appendingPathComponent(name),
                    to: storeDirectoryURL.appendingPathComponent(name)
                )
            }
            try? fileManager.removeItem(at: displacedURL)
            throw error
        }

        try? fileManager.removeItem(at: displacedURL)
    }

    /// Take a failing restore off the launch path without throwing away what it was.
    ///
    /// Clearing alone would stop the loop, and that is what the old code did for a backup folder
    /// that no longer parses — but it also erases the fact that the user asked for a restore, which
    /// is the one thing they need to see afterwards. Quarantining moves the intent out of the key
    /// the launch reads and into a record the startup banner names, so a second attempt is a
    /// decision the user makes rather than something a launch does to itself.
    private static func quarantinePendingRestore(backupURL: URL, reason: String, defaults: UserDefaults) {
        let record = FailedRestoreRecord(
            backupPath: backupURL.path,
            backupName: backupURL.lastPathComponent,
            failedAt: Date(),
            reason: reason
        )
        if let data = try? JSONEncoder.cadenceBackupEncoder.encode(record) {
            defaults.set(data, forKey: failedRestoreDefaultsKey)
        }
        clearPendingRestore(defaults: defaults)
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
        let baseName = "\(folderDateFormatter.string(from: date))-\(reason.rawValue)"
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

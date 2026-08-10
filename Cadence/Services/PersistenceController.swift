import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()
    private(set) static var startupIssue: String?

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
            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: storeDirectoryURL)
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
            startupIssue = "Cadence could not save startup maintenance changes: \(error.localizedDescription)"
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
        startupIssue = issue
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
            startupIssue = "\(issue) Recovery store creation also failed, so Cadence opened a temporary in-memory store: \(error.localizedDescription)"
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
    private static let denseStartupBackupCount = 5
    private static let dailyStartupRetentionDays = 7
    private static let weeklyStartupRetentionWeeks = 4
    private static let maxPreRestoreBackups = 5

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
    static func createBackupIfStoreExists(reason: StoreBackupReason, storeDirectoryURL: URL) throws -> URL? {
        let sourceItems = existingStoreItems(in: storeDirectoryURL)
        guard !sourceItems.isEmpty else { return nil }

        let fileManager = FileManager.default
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        let now = Date()
        let finalURL = uniqueBackupDirectory(for: now, reason: reason, storeDirectoryURL: storeDirectoryURL)
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
                try purgeAutomaticBackups(storeDirectoryURL: storeDirectoryURL)
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

    static func listBackups(storeDirectoryURL: URL?) -> [StoreBackupSnapshot] {
        guard let storeDirectoryURL else { return [] }
        let fileManager = FileManager.default
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
            let manifest = manifest(at: url)
            let createdAt = manifest?.createdAt
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast
            return StoreBackupSnapshot(
                id: url.lastPathComponent,
                url: url,
                createdAt: createdAt,
                reason: manifest?.reason.displayName ?? "Backup",
                sizeBytes: directorySize(url)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func cleanUpAutomaticBackups() throws -> Int {
        try cleanUpAutomaticBackups(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func cleanUpAutomaticBackups(storeDirectoryURL: URL) throws -> Int {
        let removableBackups = automaticBackupSnapshotsToRemove(listBackups(storeDirectoryURL: storeDirectoryURL))
        for snapshot in removableBackups {
            try FileManager.default.removeItem(at: snapshot.url)
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

    static func scheduleRestore(from backupURL: URL) throws {
        guard isBackupDirectory(backupURL) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        UserDefaults.standard.set(backupURL.path, forKey: pendingRestoreDefaultsKey)
    }

    static func clearPendingRestore() {
        UserDefaults.standard.removeObject(forKey: pendingRestoreDefaultsKey)
    }

    static func pendingRestoreURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: pendingRestoreDefaultsKey), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func performPendingRestoreIfNeeded() throws {
        try performPendingRestoreIfNeeded(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    static func performPendingRestoreIfNeeded(storeDirectoryURL: URL) throws {
        guard let backupURL = pendingRestoreURL() else { return }
        guard isBackupDirectory(backupURL) else {
            clearPendingRestore()
            throw CocoaError(.fileReadNoSuchFile)
        }

        _ = try createBackupIfStoreExists(reason: .preRestore, storeDirectoryURL: storeDirectoryURL)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        for item in existingStoreItems(in: storeDirectoryURL) {
            try fileManager.removeItem(at: item)
        }

        let backupContents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for source in backupContents where source.lastPathComponent != manifestName {
            let destination = storeDirectoryURL.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        clearPendingRestore()
    }

    private static func defaultStoreDirectoryURL() throws -> URL {
        try CadenceStoreSupport.primaryStoreDirectoryURL()
    }

    private static func existingStoreItems(in storeDirectoryURL: URL) -> [URL] {
        CadenceStoreSupport.storeItemURLs(in: storeDirectoryURL)
    }

    private static func backupRootURL(for storeDirectoryURL: URL) -> URL {
        storeDirectoryURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    private static func uniqueBackupDirectory(for date: Date, reason: StoreBackupReason, storeDirectoryURL: URL) -> URL {
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        let baseName = "\(folderDateFormatter.string(from: date))-\(reason.rawValue)"
        var candidate = backupRootURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = backupRootURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func isBackupDirectory(_ url: URL) -> Bool {
        let manifestURL = url.appendingPathComponent(manifestName)
        let storeURL = url.appendingPathComponent("default.store")
        return FileManager.default.fileExists(atPath: manifestURL.path)
            && FileManager.default.fileExists(atPath: storeURL.path)
    }

    private static func manifest(at url: URL) -> StoreBackupManifest? {
        let manifestURL = url.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(StoreBackupManifest.self, from: data)
    }

    private static func purgeAutomaticBackups(storeDirectoryURL: URL) throws {
        try cleanUpAutomaticBackups(storeDirectoryURL: storeDirectoryURL)
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

    private static func directorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
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

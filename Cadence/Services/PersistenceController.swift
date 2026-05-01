import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    static let schema = CadenceSchema.schema

    init() {
        do {
            try StoreBackupManager.performPendingRestoreIfNeeded()
            try StoreBackupManager.createBackupIfStoreExists(reason: .startup)
        } catch {
            fatalError("Cadence refused to open the store because the safety backup/restore preflight failed: \(error.localizedDescription)")
        }

        if let c = try? PersistenceController.makeContainer() {
            container = c
            let startupContext = ModelContext(c)
            NoteMigrationService.migrateAndRecordFailure(in: startupContext, source: "app-startup")
            TagSupport.seedDefaultTags(in: startupContext)
            TagSupport.syncAllNoteTagsFromMarkdown(in: startupContext)
            DataIntegrityRepairService.repairAndRecordFailure(in: startupContext, source: "app-startup")
            return
        }
        fatalError("Could not create CloudKit ModelContainer. Refusing to reopen the production store in a different mode.")
    }

    private static func makeContainer() throws -> ModelContainer {
        if ProcessInfo.processInfo.environment["CADENCE_LOCAL_STORE_ONLY"] == "1" {
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [localConfig])
        }

        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")
        )
        return try ModelContainer(for: schema, configurations: [cloudConfig])
    }

    private static func deleteStoreFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if let files = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.contains(".store") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        for name in ["default.store-wal", "default.store-shm"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }
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
    private static let maxAutomaticBackups = 80

    private static let copiedStoreItemNames = [
        "default.store",
        "default.store-wal",
        "default.store-shm",
        ".default_SUPPORT",
        "default_ckAssets",
    ]

    private static let folderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var backupRootURL: URL {
        applicationSupportURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    @discardableResult
    static func createBackupIfStoreExists(reason: StoreBackupReason) throws -> URL? {
        let sourceItems = existingStoreItems()
        guard !sourceItems.isEmpty else { return nil }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        let now = Date()
        let finalURL = uniqueBackupDirectory(for: now, reason: reason)
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
                sourceStoreURL: applicationSupportURL.appendingPathComponent("default.store").path,
                items: copiedNames
            )
            let manifestData = try JSONEncoder.cadenceBackupEncoder.encode(manifest)
            try manifestData.write(to: temporaryURL.appendingPathComponent(manifestName), options: .atomic)

            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            if reason == .startup {
                try purgeOldStartupBackups()
            }
            return finalURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func listBackups() -> [StoreBackupSnapshot] {
        let fileManager = FileManager.default
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
        guard let backupURL = pendingRestoreURL() else { return }
        guard isBackupDirectory(backupURL) else {
            clearPendingRestore()
            throw CocoaError(.fileReadNoSuchFile)
        }

        _ = try createBackupIfStoreExists(reason: .preRestore)

        let fileManager = FileManager.default
        for item in existingStoreItems() {
            try fileManager.removeItem(at: item)
        }

        let backupContents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for source in backupContents where source.lastPathComponent != manifestName {
            let destination = applicationSupportURL.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        clearPendingRestore()
    }

    private static func existingStoreItems() -> [URL] {
        copiedStoreItemNames
            .map { applicationSupportURL.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func uniqueBackupDirectory(for date: Date, reason: StoreBackupReason) -> URL {
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

    private static func purgeOldStartupBackups() throws {
        let startupBackups = listBackups().filter { snapshot in
            manifest(at: snapshot.url)?.reason == .startup
        }
        guard startupBackups.count > maxAutomaticBackups else { return }
        for snapshot in startupBackups.dropFirst(maxAutomaticBackups) {
            try FileManager.default.removeItem(at: snapshot.url)
        }
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

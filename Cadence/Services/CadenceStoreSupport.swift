import Foundation
import SwiftData

enum CadenceStoreSupport {
    nonisolated static let appGroupIdentifier = "group.com.haoranwei.Cadence"
    nonisolated static let appContainerIdentifier = "com.haoranwei.Cadence"
    nonisolated static let storeFilename = "default.store"
    nonisolated static let managedStoreItemNames = [
        storeFilename,
        "default.store-wal",
        "default.store-shm",
        ".default_SUPPORT",
        "default_ckAssets",
    ]

    nonisolated static func appGroupStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        guard let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return baseURL.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    nonisolated static func appGroupStoreURL(fileManager: FileManager = .default) throws -> URL {
        try appGroupStoreDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(storeFilename)
    }

    nonisolated static func legacyStoreCandidateDirectories(
        homeDirectoryURL: URL = userHomeDirectory
    ) -> [URL] {
        [
            homeDirectoryURL
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(appContainerIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Application Support", isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/Application Support", isDirectory: true),
        ]
    }

    nonisolated static func makeSharedContainer(
        allowsSave: Bool,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none,
        storeURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? appGroupStoreURL(fileManager: fileManager)
        let configuration = ModelConfiguration(
            "Cadence",
            schema: CadenceSchema.schema,
            url: resolvedStoreURL,
            allowsSave: allowsSave,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    @discardableResult
    nonisolated static func migrateLegacyStoreIfNeeded(
        appGroupDirectoryURL: URL,
        candidateLegacyDirectories: [URL] = legacyStoreCandidateDirectories(),
        fileManager: FileManager = .default,
        backupHandler: ((URL) throws -> Void)? = nil
    ) throws -> URL? {
        guard !hasManagedStoreItems(in: appGroupDirectoryURL, fileManager: fileManager) else {
            return nil
        }

        guard let legacyDirectoryURL = candidateLegacyDirectories.first(where: {
            hasManagedStoreItems(in: $0, fileManager: fileManager)
        }) else {
            return nil
        }

        try backupHandler?(legacyDirectoryURL)
        try fileManager.createDirectory(at: appGroupDirectoryURL, withIntermediateDirectories: true)

        for name in managedStoreItemNames {
            let sourceURL = legacyDirectoryURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = appGroupDirectoryURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return legacyDirectoryURL
    }

    nonisolated static func storeItemURLs(in directoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        managedStoreItemNames
            .map { directoryURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    nonisolated static func hasManagedStoreItems(in directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        !storeItemURLs(in: directoryURL, fileManager: fileManager).isEmpty
    }

    private nonisolated static var userHomeDirectory: URL {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }
}

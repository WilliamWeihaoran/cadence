import Foundation
import SwiftData

nonisolated enum CadenceStoreSupport {
    nonisolated static let appContainerIdentifier = "com.haoranwei.Cadence"
    nonisolated static let appGroupIdentifier = "group.com.haoranwei.Cadence"
    nonisolated static let storeDirectoryName = "Cadence"
    nonisolated static let storeFilename = "default.store"
    nonisolated static let managedStoreItemNames = [
        storeFilename,
        "default.store-wal",
        "default.store-shm",
        ".default_SUPPORT",
        "default_ckAssets",
    ]

    nonisolated static func primaryStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try sharedStoreDirectoryURL(fileManager: fileManager)
    }

    nonisolated static func sharedStoreDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        let baseURL: URL
        if let containerURL {
            baseURL = containerURL
        } else if let groupContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            baseURL = groupContainerURL
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        let storeDirectoryURL = baseURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        return storeDirectoryURL
    }

    nonisolated static func primaryStoreURL(fileManager: FileManager = .default) throws -> URL {
        try primaryStoreDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(storeFilename)
    }

    nonisolated static func makePrimaryContainer(
        allowsSave: Bool,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none,
        storeURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? primaryStoreURL(fileManager: fileManager)
        let configuration = ModelConfiguration(
            "Cadence",
            schema: CadenceSchema.schema,
            url: resolvedStoreURL,
            allowsSave: allowsSave,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    nonisolated static func legacyStoreCandidateDirectories(
        homeDirectoryURL: URL = userHomeDirectory
    ) -> [URL] {
        var seenPaths: Set<String> = []
        return [
            homeDirectoryURL
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(appContainerIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
                .appendingPathComponent(storeDirectoryName, isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(storeDirectoryName, isDirectory: true),
        ]
        .filter { candidate in
            seenPaths.insert(candidate.standardizedFileURL.path).inserted
        }
    }

    @discardableResult
    nonisolated static func migrateLegacyStoreIfNeeded(
        appGroupDirectoryURL: URL,
        candidateLegacyDirectories: [URL],
        fileManager: FileManager = .default,
        backupHandler: ((URL) throws -> Void)? = nil
    ) throws -> URL? {
        try fileManager.createDirectory(at: appGroupDirectoryURL, withIntermediateDirectories: true)
        guard storeItemURLs(in: appGroupDirectoryURL, fileManager: fileManager).isEmpty else {
            return nil
        }

        for legacyDirectory in candidateLegacyDirectories {
            let legacyItems = storeItemURLs(in: legacyDirectory, fileManager: fileManager)
            guard !legacyItems.isEmpty else { continue }

            try backupHandler?(legacyDirectory)

            do {
                for sourceURL in legacyItems {
                    let destinationURL = appGroupDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
                return legacyDirectory
            } catch {
                for sourceURL in legacyItems {
                    let destinationURL = appGroupDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw error
            }
        }

        return nil
    }

    nonisolated static func storeItemURLs(in directoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        managedStoreItemNames
            .map { directoryURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// macOS is the one platform where the process home and the *user's* home differ: under the App
    /// Sandbox `NSHomeDirectory()` is the container, and only `homeDirectoryForCurrentUser` reaches
    /// `~`. Everywhere else the container **is** the home.
    ///
    /// Spelled as macOS-or-not rather than by listing platforms. It used to read
    /// `#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)`, and this app builds two of those
    /// six names — so three of the four listed compiled to nothing, while implying targets that do
    /// not exist. This way a platform added later is right by default rather than by remembering
    /// to name it here.
    private nonisolated static var userHomeDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }
}

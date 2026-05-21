import Foundation
import SwiftData

enum CadenceStoreSupport {
    nonisolated static let appContainerIdentifier = "com.haoranwei.Cadence"
    nonisolated static let storeFilename = "default.store"
    nonisolated static let managedStoreItemNames = [
        storeFilename,
        "default.store-wal",
        "default.store-shm",
        ".default_SUPPORT",
        "default_ckAssets",
    ]

    nonisolated static func primaryStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return baseURL.appendingPathComponent("Cadence", isDirectory: true)
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

    nonisolated static func storeItemURLs(in directoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        managedStoreItemNames
            .map { directoryURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
}

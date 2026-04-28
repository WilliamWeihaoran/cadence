import Foundation
import SwiftData

enum CadenceModelContainerFactory {
    static let storeURLEnvironmentKey = "CADENCE_MCP_STORE_URL"
    static let appContainerIdentifier = "com.haoranwei.Cadence"

    static func makeReadOnlyContainer() throws -> ModelContainer {
        let storeURL = try resolvedStoreURL()
        let configuration = ModelConfiguration(
            "Cadence",
            schema: CadenceSchema.schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: CadenceSchema.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    static func resolvedStoreURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment[storeURLEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let overrideURL = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: overrideURL.path) else {
                throw CadenceReadError.storeNotFound([overrideURL.path])
            }
            return overrideURL
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let appContainerURL = home
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(appContainerIdentifier)
            .appendingPathComponent("Data/Library/Application Support/default.store")
        if FileManager.default.fileExists(atPath: appContainerURL.path) {
            return appContainerURL
        }

        let unsandboxedURL = home
            .appendingPathComponent("Library/Application Support/default.store")
        if FileManager.default.fileExists(atPath: unsandboxedURL.path) {
            return unsandboxedURL
        }

        throw CadenceReadError.storeNotFound([
            appContainerURL.path,
            unsandboxedURL.path,
        ])
    }
}

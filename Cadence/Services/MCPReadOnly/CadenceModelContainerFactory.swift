import Foundation
import SwiftData

enum CadenceModelContainerFactory {
    static let storeURLEnvironmentKey = "CADENCE_MCP_STORE_URL"
    static let createStoreIfMissingEnvironmentKey = "CADENCE_MCP_CREATE_STORE_IF_MISSING"
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

    static func makeReadWriteContainer() throws -> ModelContainer {
        let storeURL = try resolvedStoreURL()
        let configuration = ModelConfiguration(
            "Cadence",
            schema: CadenceSchema.schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
        let context = ModelContext(container)
        NoteMigrationService.migrateAndRecordFailure(in: context, source: "mcp-container")
        DataIntegrityRepairService.repairAndRecordFailure(in: context, source: "mcp-container")
        return container
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
            if FileManager.default.fileExists(atPath: overrideURL.path) || shouldCreateMissingOverrideStore {
                return overrideURL
            } else {
                throw CadenceReadError.storeNotFound([overrideURL.path])
            }
        }

        let home = userHomeDirectory
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

    static func refreshMarkerURL() throws -> URL {
        try resolvedStoreURL()
            .deletingLastPathComponent()
            .appendingPathComponent(".cadence-mcp-refresh")
    }

    static func auditLogURL() throws -> URL {
        try resolvedStoreURL()
            .deletingLastPathComponent()
            .appendingPathComponent("mcp-audit.log")
    }

    static func notifyExternalWrite() {
        guard let markerURL = try? refreshMarkerURL() else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = Data(timestamp.utf8)
        if FileManager.default.fileExists(atPath: markerURL.path),
           let handle = try? FileHandle(forWritingTo: markerURL) {
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: markerURL.path, contents: data)
        }
    }

    private static var userHomeDirectory: URL {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    private static var shouldCreateMissingOverrideStore: Bool {
        let raw = ProcessInfo.processInfo.environment[createStoreIfMissingEnvironmentKey] ?? ""
        return ["1", "true", "yes"].contains(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

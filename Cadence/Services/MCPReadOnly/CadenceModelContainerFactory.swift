import Foundation
import SwiftData

enum CadenceModelContainerFactory {
    static let storeURLEnvironmentKey = "CADENCE_MCP_STORE_URL"
    static let createStoreIfMissingEnvironmentKey = "CADENCE_MCP_CREATE_STORE_IF_MISSING"
    static let enableWritesEnvironmentKey = "CADENCE_MCP_ENABLE_WRITES"
    private static let inMemoryContainerCreationQueue = DispatchQueue(
        label: "com.haoranwei.Cadence.inMemoryModelContainerCreation"
    )

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
        TagSupport.seedDefaultTags(in: context)
        TagSupport.syncAllNoteTagsFromMarkdown(in: context)
        DataIntegrityRepairService.repairAndRecordFailure(in: context, source: "mcp-container")
        return container
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try inMemoryContainerCreationQueue.sync {
            let configuration = ModelConfiguration(
                schema: CadenceSchema.schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
        }
    }

    static var writesEnabled: Bool {
        environmentFlag(enableWritesEnvironmentKey)
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

        return try CadenceStoreSupport.primaryStoreURL()
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

    private static var shouldCreateMissingOverrideStore: Bool {
        environmentFlag(createStoreIfMissingEnvironmentKey)
    }

    private static func environmentFlag(_ key: String) -> Bool {
        let raw = ProcessInfo.processInfo.environment[key] ?? ""
        return ["1", "true", "yes"].contains(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

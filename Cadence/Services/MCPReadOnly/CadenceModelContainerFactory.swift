import Foundation
import SwiftData

nonisolated enum CadenceModelContainerFactory {
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

    /// Where this process's writes announce themselves. The *location* is the marker's own
    /// business (`CadenceStoreSupport.externalWriteMarkerURL`); what this type knows that the
    /// store-support layer does not is `CADENCE_MCP_STORE_URL`, so a run pointed at a temp store
    /// posts beside that store and not beside the user's real one.
    static func refreshMarkerURL() throws -> URL {
        CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: try resolvedStoreURL())
    }

    static func auditLogURL() throws -> URL {
        try resolvedStoreURL()
            .deletingLastPathComponent()
            .appendingPathComponent("mcp-audit.log")
    }

    /// The MCP server's half of the out-of-process write contract: save, then say so. The app
    /// picks the marker up and reconciles notifications for the write — see
    /// `CadenceStoreSupport.postExternalWrite`, which is the same call the widget extension's App
    /// Intents make.
    static func notifyExternalWrite() {
        guard let storeURL = try? resolvedStoreURL() else { return }
        CadenceStoreSupport.postExternalWrite(besideStoreAt: storeURL)
    }

    private static var shouldCreateMissingOverrideStore: Bool {
        environmentFlag(createStoreIfMissingEnvironmentKey)
    }

    private static func environmentFlag(_ key: String) -> Bool {
        let raw = ProcessInfo.processInfo.environment[key] ?? ""
        return ["1", "true", "yes"].contains(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

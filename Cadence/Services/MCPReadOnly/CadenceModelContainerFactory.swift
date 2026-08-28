import Foundation
import SwiftData

/// The read-write startup sequence, spelled once.
///
/// **T-309: this ran three times over one store on a single `CadenceMCPServer` launch.**
/// `makeReadWriteContainer()` did all four steps, then `CadenceReadService.init` re-ran the note
/// migration, then `CadenceWriteService.init` re-ran all four *and* built a private
/// `CadenceReadService` that re-ran the note migration a fourth time — all before a single tool
/// call had arrived. Mostly wasted work, but each extra pass is another window in which a second
/// process mutates the store the running app has open, and the arrangement was only ever safe
/// while every one of the four operations stayed perfectly idempotent, which nothing enforced.
///
/// The fix is deliberately **not** a guard inside these functions. It is that the sequence lives
/// here, the one caller that owns startup runs it, and every other entry point is *told* it has
/// already run — `CadenceReadService(performsMigrations:)` and
/// `CadenceWriteService(preparesStore:)`. An automatic skip would be cached state with no way to
/// invalidate it; a flag is readable at the call site, which is where the mistake was.
///
/// `executedStartupStepCount` on the two services exists so a test can state the count instead of
/// the prose.
nonisolated enum CadenceMCPStorePreparation {
    /// How many distinct operations `prepare(in:source:)` performs. The services report what they
    /// executed against this rather than against a literal.
    static let stepCount = 4

    /// Note migration, tag seeding, tag sync, integrity repair — in that order. The order is not
    /// cosmetic: `syncAllNoteTagsFromMarkdown` resolves tags `seedDefaultTags` may have just
    /// created, and the repair pass runs last so it sees the migrated shape.
    @discardableResult
    static func prepare(in context: ModelContext, source: String) -> Int {
        NoteMigrationService.migrateAndRecordFailure(in: context, source: source)
        TagSupport.seedDefaultTags(in: context)
        TagSupport.syncAllNoteTagsFromMarkdown(in: context)
        DataIntegrityRepairService.repairAndRecordFailure(in: context, source: source)
        return stepCount
    }

    /// The note migration alone. `CadenceReadService` runs this and nothing else when it is asked
    /// to migrate: a read of a store nobody has migrated still has to see canonical notes, but a
    /// read has no business seeding tags or repairing relationships.
    @discardableResult
    static func migrateNotes(in context: ModelContext, source: String) -> Int {
        NoteMigrationService.migrateAndRecordFailure(in: context, source: source)
        return 1
    }
}

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
        CadenceMCPStorePreparation.prepare(in: context, source: "mcp-container")
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

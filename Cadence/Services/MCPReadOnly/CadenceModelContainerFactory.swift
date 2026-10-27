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
///
/// **T-3018: the store the two container factories below open is the owner's CloudKit-MIRRORED
/// one, and they open it with `cloudKitDatabase: .none`.** `makeReadOnlyContainer()` and
/// `makeReadWriteContainer()` both resolve `CadenceStoreSupport.primaryStoreURL()` — the same file
/// the running app has open with `.private("iCloud.com.haoranwei.Cadence")`
/// (in `PersistenceController.makeContainer()`) — so the read-write one is one store open under
/// two different configurations. Mirroring off does not by itself keep a write from the owner's
/// other devices: a `cloudKitDatabase: .none` store still records the persistent history a CloudKit
/// export reads (measured by `widgetmirror` in `58c648fe`, [[T-3108]]); what is left is latency,
/// which is unmeasured. `CADENCE_MCP_ENABLE_WRITES` gates the write container and
/// `CADENCE_MCP_STORE_URL` redirects both, which is why every repository script that sets the
/// first pins the second before it — `CadenceTests/CadenceMCPWriteFenceTests` is what keeps that
/// true. Whether an out-of-process writer should mirror, refuse, or keep running the repair in
/// `prepare` was an owner decision about the sync contract; the owner ruled KEEP on 2026-10-26
/// (T-3018): mirroring stays off and the repair stays.
nonisolated enum CadenceMCPStorePreparation {
    /// How many distinct operations `prepare(in:source:)` performs. The services report what they
    /// executed against this rather than against a literal.
    static let stepCount = 3

    /// Note migration, tag sync, integrity repair — in that order, the repair pass last so it sees
    /// the migrated shape.
    ///
    /// **The tag seed used to be the second of four, and T-528 removed it.** This runs on the MCP
    /// server's own launch against the user's real store, from a second process, with no user in
    /// front of it — so it read "no tag carries this slug" exactly as wrongly as the app's launch
    /// did, and re-seeded a renamed default through the back door of a store the app had already
    /// stopped touching. Nothing downstream needs it: `TagSupport.resolveTags` mints a tag by name
    /// when a write asks for one, so an MCP write that names a tag works against a store with no
    /// tags in it at all. Seeding is a user action now, and this process has no user.
    ///
    /// **The repair step was left (T-3018), and since [[T-7511]] it no longer deletes.**
    /// `DataIntegrityRepairService.repairAndRecordFailure` would delete duplicate `Context`,
    /// `Area`, `Project` and `Note` rows and saves — the same "this process has no user" that
    /// removed the seed, applied to a pass that *removes* rows rather than adding one. The owner
    /// ruled KEEP on 2026-10-26 (T-3018), so it still runs, with its merges deferred: the app's
    /// launch merges duplicates behind [[T-6482]]'s import gate, which this process cannot arm.
    @discardableResult
    static func prepare(in context: ModelContext, source: String) -> Int {
        NoteMigrationService.migrateAndRecordFailure(in: context, source: source)
        TagSupport.syncAllNoteTagsFromMarkdown(in: context)
        // No `removingForkedOccurrences:`, and that is an answer rather than an omission (T-622).
        // Removing a task means severing every inverse that names it and cancelling its reminders,
        // and this target compiles neither the one spelling of the first nor a notification centre
        // to do the second. A fork it leaves alone is collapsed by the app's next startup repair;
        // a fork this process half-removed would not be.
        // [[T-7511]]: `.deferDuplicateMerges`, never the `.mergeDuplicates` default. This
        // container opens `cloudKitDatabase: .none`, so nothing imports into *it* — but it is the
        // same file on disk the app mirrors into, and the app process can be importing a child of
        // the very duplicate this one would delete. [[T-6482]]'s gate is a property of the opening
        // process, and this process has no import event to wait for, so there is no gate to arm:
        // it never merges. The app's own launch does, behind the import gate, so a duplicate is
        // still merged — by the one process that can tell when it is safe. The repair itself stays
        // ([[T-3018]]): the stored-title pass still runs here.
        DataIntegrityRepairService.repairAndRecordFailure(
            in: context,
            source: source,
            deleting: .deferDuplicateMerges
        )
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

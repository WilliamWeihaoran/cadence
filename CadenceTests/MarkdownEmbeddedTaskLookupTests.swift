import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-349: a task deleted elsewhere stayed interactive inside an already-open note editor.
///
/// Four editors — `NotePanel`, `NoteEditorPane`, `ListNotesSupportViews` and iOS's
/// `iOSMarkdownEditingSurface` — cache a just-created embedded task in `recentEmbeddedTasks` so the
/// card is live before the `@Query` catches up. The cache had no expiry, so once the live query
/// stopped returning a deleted task the lookup fell through to the cache and handed back a row the
/// store no longer held: the card kept toggling, renaming, opening and hovering against it.
///
/// `MarkdownEmbeddedTaskLookup.resolve` is the fix — the cache serves creation latency only, and a
/// cache hit is re-verified against the store. This file tests the **helper**, not the four private
/// SwiftUI methods, plus a scan that those four call it.
@MainActor
struct MarkdownEmbeddedTaskLookupTests {

    private func embedContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @discardableResult
    private func seedTask(_ title: String, in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: title)
        context.insert(task)
        try context.save()
        return task
    }

    // MARK: - The live query wins, and does not pay for the store

    /// A live-query hit never consults the store. Pinned by asking for a task the store has never
    /// heard of: if `resolve` verified unconditionally it would answer `nil` here.
    @Test func theLiveQueryAnswersWithoutConsultingTheStore() throws {
        let context = try embedContext()
        let detached = AppTask(title: "Never inserted")
        var cache: [UUID: AppTask] = [:]

        let resolved = MarkdownEmbeddedTaskLookup.resolve(
            id: detached.id,
            liveTasks: [detached],
            cache: &cache,
            in: context
        )

        #expect(resolved?.id == detached.id)
        #expect(cache.isEmpty)
    }

    // MARK: - The cache serves creation latency

    /// The case the cache exists for: the task is in the store, the `@Query` has not produced it
    /// yet, and the card must still be live.
    @Test func aCachedTaskTheStoreStillHoldsResolvesAndStaysCached() throws {
        let context = try embedContext()
        let task = try seedTask("Just created", in: context)
        var cache: [UUID: AppTask] = [task.id: task]

        let resolved = MarkdownEmbeddedTaskLookup.resolve(
            id: task.id,
            liveTasks: [],
            cache: &cache,
            in: context
        )

        #expect(resolved?.id == task.id)
        #expect(cache[task.id] != nil, "the creation-latency cache was evicted for a task that exists")
    }

    // MARK: - The bug

    /// The defect, stated directly: delete the task elsewhere and the cached fallback must stop
    /// answering. Before the fix this returned the cached object and the card stayed interactive.
    @Test func aCachedTaskDeletedElsewhereResolvesToNilAndIsEvicted() throws {
        let context = try embedContext()
        let task = try seedTask("Deleted elsewhere", in: context)
        let id = task.id
        var cache: [UUID: AppTask] = [id: task]

        // Deleted the way any other surface would delete it.
        #expect(CadenceTaskMutationSupport.delete(task, modelContext: context))

        let resolved = MarkdownEmbeddedTaskLookup.resolve(
            id: id,
            liveTasks: [],
            cache: &cache,
            in: context
        )

        #expect(resolved == nil, "a deleted task still resolved from the creation-latency cache (T-349)")
        #expect(cache[id] == nil, "the verified-missing task was left in the cache")
    }

    /// Eviction is not a one-shot: a second lookup is still missing, and now answers from the empty
    /// cache without another fetch.
    @Test func aSecondLookupAfterEvictionIsStillMissing() throws {
        let context = try embedContext()
        let task = try seedTask("Deleted elsewhere", in: context)
        let id = task.id
        var cache: [UUID: AppTask] = [id: task]
        #expect(CadenceTaskMutationSupport.delete(task, modelContext: context))

        _ = MarkdownEmbeddedTaskLookup.resolve(id: id, liveTasks: [], cache: &cache, in: context)
        let again = MarkdownEmbeddedTaskLookup.resolve(id: id, liveTasks: [], cache: &cache, in: context)

        #expect(again == nil)
    }

    /// An id neither side has ever seen. `nil`, and no cache entry invented for it.
    @Test func anUnknownEmbeddedIdResolvesToNil() throws {
        let context = try embedContext()
        try seedTask("Unrelated", in: context)
        var cache: [UUID: AppTask] = [:]

        #expect(MarkdownEmbeddedTaskLookup.resolve(id: UUID(), liveTasks: [], cache: &cache, in: context) == nil)
        #expect(cache.isEmpty)
    }

    /// The other tasks in the cache are not collateral. Only the id that was asked about and proved
    /// missing is dropped.
    @Test func evictionTouchesOnlyTheVerifiedMissingEntry() throws {
        let context = try embedContext()
        let doomed = try seedTask("Doomed", in: context)
        let survivor = try seedTask("Survivor", in: context)
        let doomedID = doomed.id
        var cache: [UUID: AppTask] = [doomedID: doomed, survivor.id: survivor]
        #expect(CadenceTaskMutationSupport.delete(doomed, modelContext: context))

        _ = MarkdownEmbeddedTaskLookup.resolve(id: doomedID, liveTasks: [], cache: &cache, in: context)

        #expect(cache[doomedID] == nil)
        #expect(cache[survivor.id]?.id == survivor.id)
    }

    // MARK: - The store question itself

    /// `storeHoldsTask` answers three ways, and the third is the point: `nil` is "could not read",
    /// which is not the same fact as "no such task". Same distinction
    /// `HabitNotificationReconcileSupport.reconcileInput` draws.
    @Test func storeHoldsTaskSeparatesPresenceFromAbsence() throws {
        let context = try embedContext()
        let task = try seedTask("Present", in: context)

        #expect(MarkdownEmbeddedTaskLookup.storeHoldsTask(id: task.id, in: context) == true)
        #expect(MarkdownEmbeddedTaskLookup.storeHoldsTask(id: UUID(), in: context) == false)

        let id = task.id
        #expect(CadenceTaskMutationSupport.delete(task, modelContext: context))
        #expect(MarkdownEmbeddedTaskLookup.storeHoldsTask(id: id, in: context) == false)
    }

    // MARK: - Shape: the four editors route through it

    private static let embeddingEditors = [
        "Cadence/macOS/Views/NotePanel.swift",
        "Cadence/macOS/Views/NoteEditorPane.swift",
        "Cadence/macOS/Views/ListNotesSupportViews.swift",
        "Cadence/iOS/iOSMarkdownEditingSurface.swift"
    ]

    /// The unguarded fallback the ticket is about: `?? recentEmbeddedTasks[id]`, in any spacing.
    private static let unverifiedCacheFallback = #"\?\?\s*recentEmbeddedTasks\["#

    @Test func theFourEmbeddingEditorsReVerifyTheirCreationLatencyCache() throws {
        var filesRead = 0

        for path in Self.embeddingEditors {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper changed the length")

            // Positive, and the non-vacuity check: the file still keeps a cache, and now resolves
            // through the shared helper rather than falling back to it blind.
            #expect(
                stripped.contains("recentEmbeddedTasks["),
                "\(path) no longer caches newly embedded tasks at all"
            )
            #expect(
                stripped.contains("MarkdownEmbeddedTaskLookup.resolve("),
                "\(path) resolves embedded tasks without re-verifying the cache (T-349)"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.unverifiedCacheFallback, in: stripped) == 0,
                "\(path) still falls back to the cache unverified (T-349)"
            )

            filesRead += 1
        }

        #expect(filesRead == 4, "the scan read \(filesRead) of 4 embedding editors")
    }

    /// The missing-card behaviour has to stay: the markdown reference remains and the card renders
    /// as missing, so a deleted embed is visible rather than erased from the note text.
    @Test func aMissingEmbedStillRendersAsACardRatherThanVanishing() throws {
        let reference = MarkdownTaskEmbedReference(id: UUID(), title: "Gone", range: NSRange(location: 0, length: 4))
        let info = MarkdownTaskEmbedRenderInfo.missing(reference: reference)

        #expect(info.id == reference.id)
        #expect(!info.title.isEmpty)
    }

    /// The needles match what they hunt and miss what they must not, and the reader reaches real
    /// files.
    @Test func theEmbeddedTaskLookupScanNeedlesAndReaderAreNotVacuous() throws {
        #expect(
            CadenceSourceScan.matchCount(Self.unverifiedCacheFallback, in: "allTasks.first(where: { $0.id == id }) ?? recentEmbeddedTasks[id]") == 1
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unverifiedCacheFallback, in: "recentEmbeddedTasks[task.id] = task") == 0
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unverifiedCacheFallback, in: "cache: &recentEmbeddedTasks,") == 0
        )

        // The reader really does return the repository's own text.
        let helper = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownTaskEmbedSupport.swift")
        )
        #expect(
            helper.contains("nonisolated enum MarkdownEmbeddedTaskLookup"),
            "the scan did not read the file that declares the lookup helper"
        )
        #expect(helper.contains("descriptor.fetchLimit = 1"))
    }
}

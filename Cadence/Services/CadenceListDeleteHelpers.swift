import Foundation
import SwiftData

/// The recursive delete cascades for `Context`, `Area` and `Project`.
///
/// **Cross-platform, and moved here to become so.** This file was `#if os(macOS)` under
/// `macOS/Services/` and imported nothing platform-specific, which left iOS with no way to delete
/// a list or a context at all — the `RemindersManager` / `PrivacyDataResetService` /
/// `TrackingDeleteHelpers` shape for the fourth time. The name carries the `Cadence` prefix so the
/// two-line tombstone left at the old path cannot collide with it on `.stringsdata`.
///
/// **Do not re-implement any of this per platform.** Deleting an area is recursive: it takes its
/// tasks, its list notes, its links, its legacy documents *and its nested projects*, and a context
/// takes every area and project beneath it along with their goals, habits and completions. A
/// hand-rolled second copy is how rows get orphaned — `Area.tasks` and `Project.tasks` *nullify*
/// rather than cascade, so a delete that skips the task sweep does not remove the tasks, it cuts
/// them loose into Inbox with no container.
/// The task sweep a list cascade runs before it deletes anything else, as a value.
///
/// Named at file scope rather than nested so the tests that hand in a refusing one do not have to
/// spell `(Set<UUID>) -> Bool` and hope it still means the same thing. See
/// `ModelContext.sweep(_:)` for why it is injectable at all.
typealias CadenceListTaskSweep = (Set<UUID>) -> Bool

extension ModelContext {
    // Each cascade below deletes its list *and* its tasks. `cascadeDeleteTasks(withIDs:)` returns
    // false when it could not read the store, and in that case the tasks are still there — so
    // deleting the list anyway would not cascade to them (`Area.tasks`/`Project.tasks` nullify
    // rather than cascade); it would cut them loose into Inbox with no container. Aborting the
    // whole cascade leaves the user's data exactly as it was, which is the only outcome they can
    // recover from.
    //
    // **None of these commit, and the `Bool` is not advisory (T-291).** A `false` return means the
    // context is holding a partial cascade, so the caller must roll it back rather than save over
    // it. Every caller goes through `CadencePendingChangePersistence.commitCascade`, which is the
    // one place that pairing is written; `CadenceListCascadeRollbackTests` pins that no surface
    // calls one of these and saves anyway.
    @discardableResult
    func deleteContext(_ context: Context, sweepTasks: CadenceListTaskSweep? = nil) -> Bool {
        let areas = Array(context.areas ?? [])
        let contextProjects = Array(context.projects ?? [])
        let pursuits = Array(context.pursuits ?? [])
        let contextTasks = Array(context.tasks ?? [])
        let goals = Array(context.goals ?? [])
        let habits = Array(context.habits ?? [])
        let areaProjects = areas.flatMap { Array($0.projects ?? []) }
        let projects = uniqueProjects(from: areaProjects + contextProjects)
        let goalLinks = uniqueGoalListLinks(from:
            goals.flatMap { Array($0.listLinks ?? []) } +
            areas.flatMap { Array($0.goalLinks ?? []) } +
            projects.flatMap { Array($0.goalLinks ?? []) }
        )

        let tasks = uniqueTasks(from:
            areas.flatMap { Array($0.tasks ?? []) } +
            projects.flatMap { Array($0.tasks ?? []) } +
            contextTasks +
            goals.flatMap { Array($0.tasks ?? []) }
        )
        let notes = uniqueNotes(from:
            areas.flatMap { Array($0.notes ?? []) } +
            projects.flatMap { Array($0.notes ?? []) }
        )
        .filter { $0.kind == .list }
        let documents = uniqueDocuments(from:
            areas.flatMap { Array($0.documents ?? []) } +
            projects.flatMap { Array($0.documents ?? []) }
        )
        let deletedNoteIDs = Set(notes.map(\.id))
        // Read while the rows are still live, and before the task sweep below deletes them
        // (T-620). This is the candidate set: the assets this cascade's own markdown pointed at.
        // Notes, legacy documents and task notes are the three markdown-bearing fields a list
        // cascade takes, which is the same triple `CadenceListDeletionSummary` counts from.
        let doomedMarkdown = notes.map(\.content) + documents.map(\.content) + tasks.map(\.notes)
        let links = uniqueLinks(from:
            areas.flatMap { Array($0.links ?? []) } +
            projects.flatMap { Array($0.links ?? []) }
        )
        let completions = uniqueHabitCompletions(from: habits.flatMap { Array($0.completions ?? []) })

        guard sweep(sweepTasks)(Set(tasks.map(\.id))) else { return false }
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: doomedMarkdown,
            excludingNoteIDs: deletedNoteIDs
        )
        delete(links)
        delete(completions)
        delete(goalLinks)
        delete(goals)
        delete(habits)
        delete(pursuits)
        delete(projects)
        delete(areas)
        delete(context)

        // cascadeDeleteTasks(withIDs:) already cancels task notifications above; habits deleted via
        // this context cascade need the same cheap direct cancellation for their reminders.
        let habitIDs = habits.map(\.id)
        if !habitIDs.isEmpty {
            Task { await NotificationManager.shared.cancel(habitIDs: habitIDs) }
        }
        return true
    }

    @discardableResult
    func deleteProject(_ project: Project, sweepTasks: CadenceListTaskSweep? = nil) -> Bool {
        let tasks = Array(project.tasks ?? [])
        let notes = uniqueNotes(from: Array(project.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(project.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        // Read before the task sweep deletes the tasks. See `deleteContext` above.
        let doomedMarkdown = notes.map(\.content) + documents.map(\.content) + tasks.map(\.notes)
        // The goal links go **after** the guard (T-291). They used to go before it, so a failed
        // task read returned `false` having already severed every link from this project to the
        // goals it contributes to — the project survived, its tasks survived, and a goal quietly
        // lost the list feeding its percentage.
        guard sweep(sweepTasks)(Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
        delete(uniqueGoalListLinks(from: Array(project.goalLinks ?? [])))
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: doomedMarkdown,
            excludingNoteIDs: deletedNoteIDs
        )
        delete(uniqueLinks(from: Array(project.links ?? [])))
        delete(project)
        return true
    }

    @discardableResult
    func deleteArea(_ area: Area, sweepTasks: CadenceListTaskSweep? = nil) -> Bool {
        let tasks = Array(area.tasks ?? [])
        let projects = uniqueProjects(from: Array(area.projects ?? []))
        let notes = uniqueNotes(from: Array(area.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(area.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        // This area's own markdown only; each nested project supplies its own candidate set from
        // the recursive `deleteProject` call below.
        let doomedMarkdown = notes.map(\.content) + documents.map(\.content) + tasks.map(\.notes)
        // After the guard, and after the nested projects, for the reason `deleteProject` gives:
        // both of those can still return `false`, and an area that failed to delete must not have
        // dropped its goal links on the way out.
        guard sweep(sweepTasks)(Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
        for project in projects {
            guard deleteProject(project, sweepTasks: sweepTasks) else { return false }
        }
        delete(uniqueGoalListLinks(from: Array(area.goalLinks ?? [])))
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: doomedMarkdown,
            excludingNoteIDs: deletedNoteIDs
        )
        delete(uniqueLinks(from: Array(area.links ?? [])))
        delete(area)
        return true
    }

    /// Resolves the task sweep: the real one, unless a test handed in a refusing stand-in.
    ///
    /// **Why the seam exists.** The failure every `guard` above is written against is a store read
    /// that cannot be performed, and that cannot be provoked out of an in-memory container — the
    /// same reason `CadencePendingChangePersistence` takes its `commit` as a parameter. Without a
    /// seam the abort paths are unreachable from a test, and T-291 is precisely a bug that lived
    /// on an unreachable abort path: the goal links were deleted before the `guard`, so a failure
    /// returned `false` having already severed them, and nothing could see it.
    ///
    /// A stand-in is faithful because the real sweep's contract is "returns `false` having changed
    /// nothing" — `{ _ in false }` is exactly that. No production call site passes one.
    private func sweep(_ override: CadenceListTaskSweep?) -> CadenceListTaskSweep {
        override ?? { self.cascadeDeleteTasks(withIDs: $0) }
    }

    /// The one seam this file has, and the only reason it is not entirely platform-free.
    ///
    /// `CadenceTaskMutationSupport.deleteTasks(withIDs:…)` is the task-deletion core both platforms
    /// already share. macOS wraps it as `ModelContext.deleteTasks(withIDs:)` purely to supply two
    /// AppKit-shaped hooks — the singleton hover/completion/subtask-entry teardown, and the focus
    /// session a disposed bundle invalidates — and those singletons do not exist on iOS. Calling the
    /// shared core directly on both platforms would silently drop that teardown on macOS; calling
    /// the macOS wrapper unconditionally does not compile on iOS. So: same core, macOS keeps its
    /// hooks.
    ///
    /// Returns `false` — having changed nothing — when the store could not be read, which is what
    /// every caller above aborts its whole cascade on.
    ///
    /// **`commitsImmediately: false` is what makes the abort mean anything (T-291).** The shared
    /// core used to `try? modelContext.save()` part-way through, so a cascade that failed *after*
    /// the task sweep had already committed the tasks as deleted: the list came back on rollback
    /// and its tasks did not. Deferred, the whole cascade is one pending change, and the caller's
    /// `CadencePendingChangePersistence.commitCascade` either commits all of it or rolls all of it
    /// back. Nothing here commits; the surface that asked for the delete does.
    private func cascadeDeleteTasks(withIDs taskIDs: Set<UUID>) -> Bool {
        #if os(macOS)
        return deleteTasks(withIDs: taskIDs, commitsImmediately: false)
        #else
        return CadenceTaskMutationSupport.deleteTasks(
            withIDs: taskIDs,
            modelContext: self,
            commitsImmediately: false
        )
        #endif
    }

    private func delete<T: PersistentModel>(_ models: [T]) {
        for model in models {
            delete(model)
        }
    }

    private func uniqueTasks(from tasks: [AppTask]) -> [AppTask] {
        dedupe(tasks, by: \AppTask.id)
    }

    private func uniqueProjects(from projects: [Project]) -> [Project] {
        dedupe(projects, by: \Project.id)
    }

    private func uniqueNotes(from notes: [Note]) -> [Note] {
        dedupe(notes, by: \Note.id)
    }

    private func uniqueDocuments(from documents: [Document]) -> [Document] {
        dedupe(documents, by: \Document.id)
    }

    private func uniqueLinks(from links: [SavedLink]) -> [SavedLink] {
        dedupe(links, by: \SavedLink.id)
    }

    private func uniqueHabitCompletions(from completions: [HabitCompletion]) -> [HabitCompletion] {
        dedupe(completions, by: \HabitCompletion.id)
    }

    private func uniqueGoalListLinks(from links: [GoalListLink]) -> [GoalListLink] {
        dedupe(links, by: \GoalListLink.id)
    }

    /// Reclaims the image assets **this delete's own markdown** referenced and nothing surviving
    /// still does.
    ///
    /// **"Referenced" means every markdown-bearing field, not `Note.content` (T-411).** The
    /// markdown editor is one component bound to several fields, and a paste into a *task's* notes
    /// creates a real `MarkdownImageAsset` the same way a paste into a note does. Scanning notes
    /// alone made that asset unreferenced by definition, so the next `deleteNote` or list cascade
    /// took its `.externalStorage` bytes while the task kept a reference that no longer resolved.
    /// `CadenceMarkdownSourceInventory` owns the field list and the rule for extending it.
    ///
    /// **`referencedByDeletedMarkdown` is the candidate set, and it is what stops this being a
    /// global garbage collection (T-620).** It used to fetch every `MarkdownImageAsset` in the
    /// store and delete every one the *surviving* markdown did not mention — so an asset whose
    /// owning row had not arrived from CloudKit yet was, by definition, unreferenced, and any
    /// unrelated note or list delete took its `.externalStorage` bytes. The note then imported
    /// holding a `cadence-image://` reference that will never resolve again. Nothing self-heals;
    /// the bytes are gone.
    ///
    /// **This is `DataIntegrityRepairService`'s reasoning, applied to the same model type from the
    /// other side.** That service refuses to collect an orphaned `MarkdownImageAsset` because
    /// *"an unowned row is indistinguishable from one whose owner has not arrived"* — the asset has
    /// no relationship to `Note` or `AppTask`, so CloudKit has nothing to order the two records by.
    /// Repair declining to collect the row while delete collected it was the same store answering
    /// one question two ways. Delete now agrees with repair: an asset nobody has ever referenced is
    /// **not this delete's business**, and the only assets at stake are the ones the rows being
    /// deleted actually pointed at.
    ///
    /// It is also the definition both confirmations already promise. `CadenceNoteDeletionSummary`
    /// and `CadenceListDeletionSummary` compute `images` as *the doomed rows' references, minus
    /// what survives* and deliberately exclude pre-existing orphans (T-423) — so before this the
    /// counts on the confirmation sheet were a strict subset of what the button did.
    ///
    /// The residual, stated rather than hidden: an asset the deleted markdown referenced **and** an
    /// unimported row also references is still collected. That needs ownership the schema does not
    /// have, and is not this fix. The cost of the new bias is a leak — an asset referenced by
    /// nothing is never reclaimed here — which is the direction this whole area errs in
    /// (`CadenceMarkdownSourceInventory`: *keep, not collect*).
    ///
    /// - Parameter referencedByDeletedMarkdown: every markdown body this delete is removing —
    ///   note contents, task notes, legacy document contents. Read these **before** the rows are
    ///   deleted; a deleted-but-unsaved model is not a body worth trusting.
    func deleteUnreferencedMarkdownImageAssets(
        referencedByDeletedMarkdown doomedMarkdown: [String],
        excludingNoteIDs: Set<UUID> = []
    ) {
        let candidateIDs = doomedMarkdown.reduce(into: Set<UUID>()) { result, text in
            result.formUnion(MarkdownImageAssetService.referencedIDs(in: text))
        }
        guard !candidateIDs.isEmpty else { return }
        guard let assets = try? fetch(FetchDescriptor<MarkdownImageAsset>()) else { return }
        let candidates = assets.filter { candidateIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }
        // These fetches decide which images are still *referenced*, so `?? []` on a failed read did
        // not mean "collect nothing" — it meant "nothing in this store references any image", and
        // every asset the user had ever pasted into any note was deleted while the notes kept
        // their now-dangling references. One failed read during a single project delete could
        // take out the entire image library, unrecoverably. A failure must skip the collection;
        // deferring garbage until the next delete costs nothing. The inventory answers `nil` for
        // exactly that case, and it answers `nil` if *any* field it reads is unreadable.
        guard let remainingMarkdown = CadenceMarkdownSourceInventory.liveMarkdownTexts(
            in: self,
            excludingNoteIDs: excludingNoteIDs
        ) else { return }
        let unreferenced = MarkdownImageAssetService.unreferencedAssets(
            allAssets: candidates,
            markdownTexts: remainingMarkdown
        )
        delete(unreferenced)
    }

    private func dedupe<T>(_ models: [T], by id: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0[keyPath: id]).inserted }
    }
}

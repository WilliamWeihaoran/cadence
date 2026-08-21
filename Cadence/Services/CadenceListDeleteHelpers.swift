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
extension ModelContext {
    // Each cascade below deletes its list *and* its tasks. `cascadeDeleteTasks(withIDs:)` returns
    // false when it could not read the store, and in that case the tasks are still there — so
    // deleting the list anyway would not cascade to them (`Area.tasks`/`Project.tasks` nullify
    // rather than cascade); it would cut them loose into Inbox with no container. Aborting the
    // whole cascade leaves the user's data exactly as it was, which is the only outcome they can
    // recover from.
    @discardableResult
    func deleteContext(_ context: Context) -> Bool {
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
        let links = uniqueLinks(from:
            areas.flatMap { Array($0.links ?? []) } +
            projects.flatMap { Array($0.links ?? []) }
        )
        let completions = uniqueHabitCompletions(from: habits.flatMap { Array($0.completions ?? []) })

        guard cascadeDeleteTasks(withIDs: Set(tasks.map(\.id))) else { return false }
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: deletedNoteIDs)
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
    func deleteProject(_ project: Project) -> Bool {
        let tasks = Array(project.tasks ?? [])
        let notes = uniqueNotes(from: Array(project.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(project.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        delete(uniqueGoalListLinks(from: Array(project.goalLinks ?? [])))
        guard cascadeDeleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: deletedNoteIDs)
        delete(uniqueLinks(from: Array(project.links ?? [])))
        delete(project)
        return true
    }

    @discardableResult
    func deleteArea(_ area: Area) -> Bool {
        let tasks = Array(area.tasks ?? [])
        let projects = uniqueProjects(from: Array(area.projects ?? []))
        let notes = uniqueNotes(from: Array(area.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(area.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        delete(uniqueGoalListLinks(from: Array(area.goalLinks ?? [])))
        guard cascadeDeleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
        for project in projects {
            guard deleteProject(project) else { return false }
        }
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: deletedNoteIDs)
        delete(uniqueLinks(from: Array(area.links ?? [])))
        delete(area)
        return true
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
    private func cascadeDeleteTasks(withIDs taskIDs: Set<UUID>) -> Bool {
        #if os(macOS)
        return deleteTasks(withIDs: taskIDs)
        #else
        return CadenceTaskMutationSupport.deleteTasks(withIDs: taskIDs, modelContext: self)
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

    func deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: Set<UUID> = []) {
        guard let assets = try? fetch(FetchDescriptor<MarkdownImageAsset>()), !assets.isEmpty else { return }
        // This fetch decides which images are still *referenced*, so `?? []` on a failed read did
        // not mean "collect nothing" — it meant "nothing in this store references any image", and
        // every asset the user had ever pasted into any note was deleted while the notes kept
        // their now-dangling references. One failed read during a single project delete could
        // take out the entire image library, unrecoverably. A failure must skip the collection;
        // deferring garbage until the next delete costs nothing.
        guard let allNotes = try? fetch(FetchDescriptor<Note>()) else { return }
        let remainingMarkdown = allNotes
            .filter { !excludingNoteIDs.contains($0.id) }
            .map(\.content)
        let unreferenced = MarkdownImageAssetService.unreferencedAssets(
            allAssets: assets,
            markdownTexts: remainingMarkdown
        )
        delete(unreferenced)
    }

    private func dedupe<T>(_ models: [T], by id: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0[keyPath: id]).inserted }
    }
}

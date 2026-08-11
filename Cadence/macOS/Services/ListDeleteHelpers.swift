#if os(macOS)
import Foundation
import SwiftData

extension ModelContext {
    // Each cascade below deletes its list *and* its tasks. `deleteTasks(withIDs:)` returns false
    // when it could not read the store, and in that case the tasks are still there — so deleting
    // the list anyway would not cascade to them (`Area.tasks`/`Project.tasks` nullify rather than
    // cascade); it would cut them loose into Inbox with no container. Aborting the whole cascade
    // leaves the user's data exactly as it was, which is the only outcome they can recover from.
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

        guard deleteTasks(withIDs: Set(tasks.map(\.id))) else { return false }
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

        // deleteTasks(withIDs:) already cancels task notifications above; habits deleted via this
        // context cascade need the same cheap direct cancellation for their reminder notifications.
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
        guard deleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
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
        guard deleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id))) else { return false }
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
#endif

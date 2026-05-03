#if os(macOS)
import Foundation
import SwiftData

extension ModelContext {
    func deleteContext(_ context: Context) {
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

        deleteTasks(withIDs: Set(tasks.map(\.id)))
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
    }

    func deleteProject(_ project: Project) {
        let tasks = Array(project.tasks ?? [])
        let notes = uniqueNotes(from: Array(project.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(project.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        delete(uniqueGoalListLinks(from: Array(project.goalLinks ?? [])))
        deleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id)))
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: deletedNoteIDs)
        delete(uniqueLinks(from: Array(project.links ?? [])))
        delete(project)
    }

    func deleteArea(_ area: Area) {
        let tasks = Array(area.tasks ?? [])
        let projects = uniqueProjects(from: Array(area.projects ?? []))
        let notes = uniqueNotes(from: Array(area.notes ?? [])).filter { $0.kind == .list }
        let documents = uniqueDocuments(from: Array(area.documents ?? []))
        let deletedNoteIDs = Set(notes.map(\.id))
        delete(uniqueGoalListLinks(from: Array(area.goalLinks ?? [])))
        deleteTasks(withIDs: Set(uniqueTasks(from: tasks).map(\.id)))
        for project in projects {
            deleteProject(project)
        }
        delete(notes)
        delete(documents)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: deletedNoteIDs)
        delete(uniqueLinks(from: Array(area.links ?? [])))
        delete(area)
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
        let remainingMarkdown = ((try? fetch(FetchDescriptor<Note>())) ?? [])
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

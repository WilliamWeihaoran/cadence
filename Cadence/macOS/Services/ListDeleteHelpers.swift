#if os(macOS)
import Foundation
import SwiftData

extension ModelContext {
    func deleteContext(_ context: Context) {
        let areas = Array(context.areas ?? [])
        let contextProjects = Array(context.projects ?? [])
        let contextTasks = Array(context.tasks ?? [])
        let goals = Array(context.goals ?? [])
        let habits = Array(context.habits ?? [])

        let areaProjects = areas.flatMap { Array($0.projects ?? []) }
        let projects = uniqueProjects(from: areaProjects + contextProjects)
        let tasks = uniqueTasks(from:
            areas.flatMap { Array($0.tasks ?? []) } +
            projects.flatMap { Array($0.tasks ?? []) } +
            contextTasks +
            goals.flatMap { Array($0.tasks ?? []) }
        )
        let subtasks = uniqueSubtasks(from: tasks.flatMap { Array($0.subtasks ?? []) })
        let documents = uniqueDocuments(from:
            areas.flatMap { Array($0.documents ?? []) } +
            projects.flatMap { Array($0.documents ?? []) }
        )
        let notes = uniqueNotes(from:
            areas.flatMap { Array($0.notes ?? []) } +
            projects.flatMap { Array($0.notes ?? []) }
        )
        .filter { $0.kind == .list }
        let links = uniqueLinks(from:
            areas.flatMap { Array($0.links ?? []) } +
            projects.flatMap { Array($0.links ?? []) }
        )
        let completions = uniqueHabitCompletions(from: habits.flatMap { Array($0.completions ?? []) })

        delete(subtasks)
        delete(tasks)
        delete(documents)
        delete(notes)
        delete(links)
        delete(completions)
        delete(goals)
        delete(habits)
        delete(projects)
        delete(areas)
        delete(context)
    }

    func deleteProject(_ project: Project) {
        let tasks = Array(project.tasks ?? [])
        delete(uniqueSubtasks(from: tasks.flatMap { Array($0.subtasks ?? []) }))
        delete(uniqueTasks(from: tasks))
        delete(uniqueDocuments(from: Array(project.documents ?? [])))
        delete(uniqueNotes(from: Array(project.notes ?? [])).filter { $0.kind == .list })
        delete(uniqueLinks(from: Array(project.links ?? [])))
        delete(project)
    }

    func deleteArea(_ area: Area) {
        let tasks = Array(area.tasks ?? [])
        let projects = uniqueProjects(from: Array(area.projects ?? []))
        delete(uniqueSubtasks(from: tasks.flatMap { Array($0.subtasks ?? []) }))
        delete(uniqueTasks(from: tasks))
        for project in projects {
            deleteProject(project)
        }
        delete(uniqueDocuments(from: Array(area.documents ?? [])))
        delete(uniqueNotes(from: Array(area.notes ?? [])).filter { $0.kind == .list })
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

    private func uniqueSubtasks(from subtasks: [Subtask]) -> [Subtask] {
        dedupe(subtasks, by: \Subtask.id)
    }

    private func uniqueProjects(from projects: [Project]) -> [Project] {
        dedupe(projects, by: \Project.id)
    }

    private func uniqueDocuments(from documents: [Document]) -> [Document] {
        dedupe(documents, by: \Document.id)
    }

    private func uniqueNotes(from notes: [Note]) -> [Note] {
        dedupe(notes, by: \Note.id)
    }

    private func uniqueLinks(from links: [SavedLink]) -> [SavedLink] {
        dedupe(links, by: \SavedLink.id)
    }

    private func uniqueHabitCompletions(from completions: [HabitCompletion]) -> [HabitCompletion] {
        dedupe(completions, by: \HabitCompletion.id)
    }

    private func dedupe<T>(_ models: [T], by id: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0[keyPath: id]).inserted }
    }
}
#endif

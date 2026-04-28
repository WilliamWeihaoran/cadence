#if os(macOS)
import SwiftData

extension ModelContext {
    func deleteContext(_ context: Context) {
        let areas = context.areas ?? []
        let projects = context.projects ?? []
        let areaProjectIDs = Set(areas.flatMap { $0.projects ?? [] }.map(\.id))
        let areaTaskIDs = Set(areas.flatMap { $0.tasks ?? [] }.map(\.id))
        let projectTaskIDs = Set(projects.flatMap { $0.tasks ?? [] }.map(\.id))
        let contextTaskIDs = Set((context.tasks ?? []).map(\.id))

        for area in areas {
            deleteArea(area)
        }

        for project in projects where !areaProjectIDs.contains(project.id) {
            deleteProject(project)
        }

        for task in context.tasks ?? [] where !areaTaskIDs.contains(task.id) && !projectTaskIDs.contains(task.id) {
            delete(task)
        }

        for goal in context.goals ?? [] {
            for task in goal.tasks ?? [] where !areaTaskIDs.contains(task.id) && !projectTaskIDs.contains(task.id) && !contextTaskIDs.contains(task.id) {
                delete(task)
            }
            delete(goal)
        }

        for habit in context.habits ?? [] {
            for completion in habit.completions ?? [] { delete(completion) }
            delete(habit)
        }

        delete(context)
    }

    func deleteProject(_ project: Project) {
        for task in project.tasks ?? [] { delete(task) }
        for document in project.documents ?? [] { delete(document) }
        for link in project.links ?? [] { delete(link) }
        delete(project)
    }

    func deleteArea(_ area: Area) {
        for task in area.tasks ?? [] { delete(task) }
        for project in area.projects ?? [] { deleteProject(project) }
        for document in area.documents ?? [] { delete(document) }
        for link in area.links ?? [] { delete(link) }
        delete(area)
    }
}
#endif

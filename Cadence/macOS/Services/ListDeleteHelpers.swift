#if os(macOS)
import SwiftData

extension ModelContext {
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

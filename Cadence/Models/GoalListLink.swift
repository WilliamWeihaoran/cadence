import SwiftData
import Foundation

@Model final class GoalListLink {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var goal: Goal? = nil
    var area: Area? = nil
    var project: Project? = nil

    init(goal: Goal? = nil, area: Area? = nil, project: Project? = nil) {
        self.goal = goal
        self.area = area
        self.project = project
    }

    var title: String {
        area?.name ?? project?.name ?? "Missing List"
    }

    var icon: String {
        area?.icon ?? project?.icon ?? "questionmark.folder"
    }

    var colorHex: String {
        area?.colorHex ?? project?.colorHex ?? "#6b7a99"
    }

    var context: Context? {
        area?.context ?? project?.context
    }

    var tasks: [AppTask] {
        area?.tasks ?? project?.tasks ?? []
    }

    func pointsTo(area candidate: Area) -> Bool {
        area?.id == candidate.id
    }

    func pointsTo(project candidate: Project) -> Bool {
        project?.id == candidate.id
    }
}

import SwiftData
import Foundation

/// Top-level life/work domain. Contains areas, projects, goals, habits.
@Model final class Context {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#4a9eff"
    var icon: String = "square.stack.fill"
    var order: Int = 0
    var isArchived: Bool = false

    @Relationship(inverse: \Area.context) var areas: [Area]? = nil
    @Relationship(inverse: \Project.context) var projects: [Project]? = nil
    @Relationship(inverse: \AppTask.context) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Goal.context) var goals: [Goal]? = nil
    @Relationship(inverse: \Habit.context) var habits: [Habit]? = nil

    init(name: String, colorHex: String = "#4a9eff", icon: String = "square.stack.fill") {
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }
}

import SwiftData
import Foundation

@Model final class HabitCompletion {
    var id: UUID = UUID()
    var date: String = ""   // YYYY-MM-DD
    var count: Int = 1
    var createdAt: Date = Date()

    var habit: Habit? = nil

    init(date: String, habit: Habit? = nil) {
        self.date = date
        self.habit = habit
    }
}

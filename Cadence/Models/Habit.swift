import SwiftData
import Foundation

@Model final class Habit {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = "star.fill"
    var colorHex: String = "#4a9eff"
    var frequencyType: HabitFrequency = .daily
    /// JSON [Int]: daysOfWeek=[0-6], timesPerWeek=[n], monthly=[dayOfMonth], daily=[]
    var frequencyDaysRaw: String = "[]"
    var targetCount: Int = 1
    var order: Int = 0
    var createdAt: Date = Date()

    var context: Context? = nil
    @Relationship(inverse: \HabitCompletion.habit) var completions: [HabitCompletion]? = nil

    var frequencyDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: Data(frequencyDaysRaw.utf8))) ?? [] }
        set { frequencyDaysRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var currentStreak: Int {
        let dates = Set((completions ?? []).map { $0.date })
        let cal = Calendar.current
        var date = cal.startOfDay(for: Date())
        let todayStr = DateFormatters.dateKey(from: date)
        let yesterdayStr = DateFormatters.dateKey(from: cal.date(byAdding: .day, value: -1, to: date)!)
        guard dates.contains(todayStr) || dates.contains(yesterdayStr) else { return 0 }
        if !dates.contains(todayStr) { date = cal.date(byAdding: .day, value: -1, to: date)! }
        var streak = 0
        while dates.contains(DateFormatters.dateKey(from: date)) {
            streak += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }

    init(title: String, context: Context? = nil) {
        self.title = title
        self.context = context
    }
}

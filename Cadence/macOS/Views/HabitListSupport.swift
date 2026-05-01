#if os(macOS)
import SwiftUI

enum HabitListFilter: CaseIterable {
    case today
    case completed
    case streaking
    case all

    var label: String {
        switch self {
        case .today: return "Due Today"
        case .completed: return "Completed Today"
        case .streaking: return "Streaking"
        case .all: return "All"
        }
    }

    func matches(_ habit: Habit) -> Bool {
        switch self {
        case .today:
            return habit.isDueToday
        case .completed:
            return habit.isDone(on: DateFormatters.todayKey())
        case .streaking:
            return habit.currentStreak >= 3
        case .all:
            return true
        }
    }
}

struct HabitGoalGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let colorHex: String
    let habits: [Habit]
}
#endif

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

    /// `todayKey` is the page's observed day ([[T-5012]]), not the clock read here: the page's
    /// day observer is what re-runs this at midnight, so the key has to come from it.
    func matches(_ habit: Habit, todayKey: String) -> Bool {
        switch self {
        case .today:
            return habit.isDue(onDayKey: todayKey)
        case .completed:
            return habit.isDone(on: todayKey)
        case .streaking:
            return habit.currentStreak >= 3
        case .all:
            return true
        }
    }

    /// Whether this selection can hide a habit that exists.
    ///
    /// The default is `.today`, which is the narrowest of the four: a habit set to Mon/Wed/Fri is
    /// filtered out on a Tuesday. Without this the page called that "No habits yet".
    var narrowsResults: Bool { self != .all }
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

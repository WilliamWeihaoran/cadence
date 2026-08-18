import Foundation

enum CadenceCalendarViewMode: String, CaseIterable, Hashable {
    case week = "Week"
    case twoWeeks = "2 Weeks"
    case month = "Month"

    static let pickerCases: [CadenceCalendarViewMode] = [.week, .month]

    var daysCount: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 1
        }
    }
}

enum CadenceCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"
}

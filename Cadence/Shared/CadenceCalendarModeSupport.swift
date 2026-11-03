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

    /// The mode's one glyph ([[T-10221]]): the iOS Calendar toolbar's Week/Month pills and the
    /// Settings > Navigation "Calendar view" choices both read it. Settings drew `calendar` on
    /// Week and Month alike, so its two rows wore one glyph and Week's was not the toolbar's.
    var systemImage: String {
        switch self {
        case .week, .twoWeeks: return "rectangle.split.3x1"
        case .month: return "calendar"
        }
    }
}

enum CadenceCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"

    /// Board's one glyph ([[T-10221]]): the iOS Calendar toolbar's Board pill drew
    /// `rectangle.grid.2x2` while the Settings "Calendar style" choice drew `square.grid.2x2`.
    /// Timeline has no constant: the toolbar names it by its Week/Month modes, not a pill.
    static let boardSystemImage = "rectangle.grid.2x2"
}

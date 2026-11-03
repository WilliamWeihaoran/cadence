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

/// The Calendar page's one three-way choice, Week / Month / Board ([[T-7074]]).
///
/// Two stored keys carry it -- `CadenceCalendarPresentation` and `CadenceCalendarViewMode` -- and
/// the iOS toolbar's mode control has always written them as one control: Board sets the
/// presentation and leaves the mode alone, Week and Month set the timeline plus the mode. Settings
/// > Navigation drew the same two keys as two rows, "Calendar view: Week / Month" and "Calendar
/// style: Timeline / Board", so with Board on the page Settings still read "Calendar view: Week"
/// beside a style row the page never names. Both surfaces now read and write this one value.
enum CadenceCalendarPageView: Hashable, CaseIterable {
    case week
    case month
    case board

    /// The choice the two stored keys spell. `nil` only for `.twoWeeks`, which no picker offers
    /// and only an older build's persisted value can hold -- so neither surface claims it is Week.
    init?(presentation: CadenceCalendarPresentation, viewMode: CadenceCalendarViewMode) {
        if presentation == .board {
            self = .board
            return
        }
        switch viewMode {
        case .week: self = .week
        case .month: self = .month
        case .twoWeeks: return nil
        }
    }

    var title: String {
        switch self {
        case .week: return CadenceCalendarViewMode.week.rawValue
        case .month: return CadenceCalendarViewMode.month.rawValue
        case .board: return CadenceCalendarPresentation.board.rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .week: return CadenceCalendarViewMode.week.systemImage
        case .month: return CadenceCalendarViewMode.month.systemImage
        case .board: return CadenceCalendarPresentation.boardSystemImage
        }
    }

    /// What a Settings "Calendar view" row reads for the stored pair, on both platforms
    /// ([[T-8737]]). A `.twoWeeks` an older build persisted reads as itself rather than as Week,
    /// the way the toolbar lights no pill for it.
    static func settingsTitle(
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode
    ) -> String {
        CadenceCalendarPageView(presentation: presentation, viewMode: viewMode)?.title ?? viewMode.rawValue
    }

    /// Board keeps the line it had as a "Calendar style": it is the one choice whose name does not
    /// say what it draws. Week and Month do.
    var settingsSubtitle: String? {
        self == .board ? "Columns per day, with overdue and unscheduled rails." : nil
    }

    /// The write the toolbar makes. Board keeps the stored mode, so leaving Board returns to the
    /// timeline range the reader had.
    func apply(
        presentation: inout CadenceCalendarPresentation,
        viewMode: inout CadenceCalendarViewMode
    ) {
        switch self {
        case .week:
            presentation = .timeline
            viewMode = .week
        case .month:
            presentation = .timeline
            viewMode = .month
        case .board:
            presentation = .board
        }
    }
}

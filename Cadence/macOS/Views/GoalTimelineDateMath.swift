#if os(macOS)
import CoreGraphics
import Foundation

enum TimeScale: String, CaseIterable {
    case twoWeeks = "2W"
    case month = "M"
    case quarter = "Q"
    case year = "Y"
    case fiveYears = "5Y"

    var dayWidth: CGFloat {
        switch self {
        case .twoWeeks: return 48
        case .month: return 26
        case .quarter: return 12
        case .year: return 3.5
        case .fiveYears: return 1.5
        }
    }

    var renderDays: Int {
        switch self {
        case .twoWeeks: return 120
        case .month: return 180
        case .quarter: return 365
        case .year: return 730
        case .fiveYears: return 1825
        }
    }

    var leadDays: Int {
        switch self {
        case .twoWeeks: return 14
        case .month: return 30
        case .quarter: return 60
        case .year: return 90
        case .fiveYears: return 180
        }
    }
}

enum GoalTimelineDateMath {
    static func renderStartDate(
        scale: TimeScale,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: -scale.leadDays, to: today) ?? today
    }

    static func renderEndDate(
        startDate: Date,
        scale: TimeScale,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.date(byAdding: .day, value: scale.renderDays, to: startDate)
    }

    static func shiftedRange(
        start: Date,
        end: Date,
        dayOffset: Int,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard let shiftedStart = calendar.date(byAdding: .day, value: dayOffset, to: start),
              let shiftedEnd = calendar.date(byAdding: .day, value: dayOffset, to: end) else {
            return nil
        }
        return (shiftedStart, shiftedEnd)
    }
}
#endif

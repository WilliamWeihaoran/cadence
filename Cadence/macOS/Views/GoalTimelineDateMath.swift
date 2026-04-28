#if os(macOS)
import CoreGraphics
import Foundation

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

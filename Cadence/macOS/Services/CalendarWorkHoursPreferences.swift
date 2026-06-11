#if os(macOS)
import CoreGraphics
import Foundation

enum CalendarWorkHoursPreferences {
    struct WorkHoursRange: Equatable {
        let startMinute: Int
        let endMinute: Int
    }

    struct HighlightFrame: Equatable {
        let y: CGFloat
        let height: CGFloat
    }

    static let startMinuteKey = "calendar.workHours.startMinute.v1"
    static let endMinuteKey = "calendar.workHours.endMinute.v1"
    static let defaultStartMinute = 9 * 60
    static let defaultEndMinute = 17 * 60

    static let selectableStartMinutes = stride(from: 0, through: 23 * 60 + 30, by: 30).map { $0 }
    static let selectableEndMinutes = stride(from: 30, through: 24 * 60, by: 30).map { $0 }

    static func normalizedStartMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 23 * 60 + 30)
    }

    static func normalizedEndMinute(_ minute: Int, startMinute: Int) -> Int {
        let safeStart = normalizedStartMinute(startMinute)
        return min(max(minute, safeStart + 30), 24 * 60)
    }

    static func normalizedRange(startMinute: Int, endMinute: Int) -> WorkHoursRange {
        let start = normalizedStartMinute(startMinute)
        return WorkHoursRange(
            startMinute: start,
            endMinute: normalizedEndMinute(endMinute, startMinute: start)
        )
    }

    static func rangeByUpdatingStart(
        _ startMinute: Int,
        currentEndMinute: Int
    ) -> WorkHoursRange {
        normalizedRange(startMinute: startMinute, endMinute: currentEndMinute)
    }

    static func rangeByUpdatingEnd(
        _ endMinute: Int,
        currentStartMinute: Int
    ) -> WorkHoursRange {
        normalizedRange(startMinute: currentStartMinute, endMinute: endMinute)
    }

    static func visibleMinuteRange(
        startMinute: Int,
        endMinute: Int,
        timelineStartHour: Int,
        timelineEndHour: Int
    ) -> ClosedRange<Int>? {
        let timelineStart = max(0, timelineStartHour * 60)
        let timelineEnd = min(24 * 60, timelineEndHour * 60)
        let range = normalizedRange(startMinute: startMinute, endMinute: endMinute)
        let visibleStart = max(range.startMinute, timelineStart)
        let visibleEnd = min(range.endMinute, timelineEnd)

        guard visibleEnd > visibleStart else { return nil }
        return visibleStart...visibleEnd
    }

    static func highlightFrame(
        startMinute: Int,
        endMinute: Int,
        timelineStartHour: Int,
        timelineEndHour: Int,
        hourHeight: CGFloat
    ) -> HighlightFrame? {
        guard let visibleRange = visibleMinuteRange(
            startMinute: startMinute,
            endMinute: endMinute,
            timelineStartHour: timelineStartHour,
            timelineEndHour: timelineEndHour
        ) else {
            return nil
        }

        let y = CGFloat(visibleRange.lowerBound - timelineStartHour * 60) * hourHeight / 60
        let height = CGFloat(visibleRange.upperBound - visibleRange.lowerBound) * hourHeight / 60
        guard height > 0 else { return nil }
        return HighlightFrame(y: y, height: height)
    }

    static func shouldShowHighlight(on date: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDateInWeekend(date)
    }

    static func displayLabel(startMinute: Int, endMinute: Int) -> String {
        let range = normalizedRange(startMinute: startMinute, endMinute: endMinute)
        return TimeFormatters.timeRange(
            startMin: range.startMinute,
            endMin: range.endMinute
        )
    }
}
#endif

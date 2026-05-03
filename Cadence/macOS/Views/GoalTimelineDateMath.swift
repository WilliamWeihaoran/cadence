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

enum GoalTimelineResizeEdge {
    case leading
    case trailing
}

struct GoalTimelineBarFrame: Equatable {
    let x: CGFloat
    let width: CGFloat
}

struct GoalTimelineMonthMarker: Equatable {
    let date: Date
    let label: String
    let x: CGFloat
}

enum GoalTimelineDateMath {
    static let roadmapScales: [TimeScale] = [.month, .quarter, .year, .fiveYears]

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

    static func dayOffset(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    static func xPosition(
        for date: Date,
        rangeStart: Date,
        dayWidth: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        CGFloat(dayOffset(from: rangeStart, to: date, calendar: calendar)) * dayWidth
    }

    static func dayDelta(for translation: CGFloat, dayWidth: CGFloat) -> Int {
        guard dayWidth > 0 else { return 0 }
        return Int((translation / dayWidth).rounded())
    }

    static func barFrame(
        start: Date,
        end: Date,
        rangeStart: Date,
        dayWidth: CGFloat,
        calendar: Calendar = .current
    ) -> GoalTimelineBarFrame {
        let normalizedStart = calendar.startOfDay(for: min(start, end))
        let normalizedEnd = calendar.startOfDay(for: max(start, end))
        let startOffset = dayOffset(from: rangeStart, to: normalizedStart, calendar: calendar)
        let endOffset = dayOffset(from: rangeStart, to: normalizedEnd, calendar: calendar)
        return GoalTimelineBarFrame(
            x: CGFloat(startOffset) * dayWidth,
            width: max(dayWidth, CGFloat(endOffset - startOffset + 1) * dayWidth)
        )
    }

    static func barFrame(
        startKey: String,
        endKey: String,
        rangeStart: Date,
        dayWidth: CGFloat,
        calendar: Calendar = .current
    ) -> GoalTimelineBarFrame? {
        guard let start = DateFormatters.date(from: startKey),
              let end = DateFormatters.date(from: endKey) else {
            return nil
        }
        return barFrame(start: start, end: end, rangeStart: rangeStart, dayWidth: dayWidth, calendar: calendar)
    }

    static func movedRange(
        start: Date,
        end: Date,
        dayDelta: Int,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard let shiftedStart = calendar.date(byAdding: .day, value: dayDelta, to: start),
              let shiftedEnd = calendar.date(byAdding: .day, value: dayDelta, to: end) else {
            return nil
        }
        return (calendar.startOfDay(for: shiftedStart), calendar.startOfDay(for: shiftedEnd))
    }

    static func resizedRange(
        start: Date,
        end: Date,
        edge: GoalTimelineResizeEdge,
        dayDelta: Int,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        let normalizedStart = calendar.startOfDay(for: min(start, end))
        let normalizedEnd = calendar.startOfDay(for: max(start, end))

        switch edge {
        case .leading:
            guard let proposedStart = calendar.date(byAdding: .day, value: dayDelta, to: normalizedStart) else {
                return nil
            }
            return (min(calendar.startOfDay(for: proposedStart), normalizedEnd), normalizedEnd)
        case .trailing:
            guard let proposedEnd = calendar.date(byAdding: .day, value: dayDelta, to: normalizedEnd) else {
                return nil
            }
            return (normalizedStart, max(calendar.startOfDay(for: proposedEnd), normalizedStart))
        }
    }

    static func monthMarkers(
        rangeStart: Date,
        rangeEnd: Date,
        dayWidth: CGFloat,
        calendar: Calendar = .current
    ) -> [GoalTimelineMonthMarker] {
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        guard start <= end else { return [] }

        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = 1
        guard var month = calendar.date(from: components) else { return [] }
        if month < start, let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) {
            month = nextMonth
        }

        var markers: [GoalTimelineMonthMarker] = []
        while month <= end {
            markers.append(
                GoalTimelineMonthMarker(
                    date: month,
                    label: DateFormatters.monthAbbrev.string(from: month),
                    x: xPosition(for: month, rangeStart: start, dayWidth: dayWidth, calendar: calendar)
                )
            )
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = nextMonth
        }
        return markers
    }
}
#endif

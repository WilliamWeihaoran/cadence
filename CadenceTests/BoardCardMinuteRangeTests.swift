import Foundation
import Testing
@testable import Cadence

/// [[T-17021]]: the iOS Board event card's minutes on one day column are wall-clock readings, so
/// on a DST transition day its label says the clock times the timeline draws — not start plus
/// elapsed, which was an hour short on spring-forward and an hour long on fall-back.
///
/// `iOSCalendarBoardEventItem` is iOS-only and invisible to this macOS-built target; its init
/// reads its minutes from `CadenceScheduleSupport.boardCardMinuteRange` and nothing else, so the
/// rule is tested here.
@Suite("Board card minutes on a day column")
struct BoardCardMinuteRangeTests {
    private static func newYork(_ month: Int, _ day: Int, _ hour: Int, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    @Test("A DST-day card reads its event's wall-clock ends, as the grid does")
    func aTransitionDayCardReadsTheWallClockEnds() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        // (month, day, start hour, end hour): spring forward, fall back, and an ordinary day.
        for (month, day, startHour, endHour) in [(3, 8, 1, 4), (11, 1, 0, 3), (6, 11, 1, 4)] {
            let start = try Self.newYork(month, day, startHour, calendar)
            let end = try Self.newYork(month, day, endHour, calendar)
            let range = try #require(
                CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: start, calendar: calendar)
            )
            #expect(range.start == startHour * 60)
            #expect(range.end == endHour * 60, "\(month)/\(day) labelled to \(range.end)")
            // The grid's own reading of the same event, minus its 15-minute floor.
            #expect(range.end == CadenceScheduleSupport.minuteRange(from: start, to: end, on: start, calendar: calendar).end)
            // The elapsed length differs from the label's span exactly on the transition days.
            let elapsed = Int(end.timeIntervalSince(start) / 60)
            #expect((range.end - range.start == elapsed) == (month == 6))
        }
    }

    @Test("An overnight event is clipped to each column and absent from the days it does not touch")
    func anOvernightEventIsClippedPerColumn() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let start = try Self.newYork(6, 11, 22, calendar)
        let end = try #require(calendar.date(byAdding: .hour, value: 4, to: start))
        let firstDay = calendar.startOfDay(for: start)
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let thirdDay = try #require(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let dayBefore = try #require(calendar.date(byAdding: .day, value: -1, to: firstDay))

        let first = try #require(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: firstDay, calendar: calendar))
        #expect(first.start == 22 * 60 && first.end == 24 * 60)
        let second = try #require(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: secondDay, calendar: calendar))
        #expect(second.start == 0 && second.end == 2 * 60)
        #expect(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: thirdDay, calendar: calendar) == nil)
        #expect(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: dayBefore, calendar: calendar) == nil)

        // An event ending exactly at midnight does not leak a sliver into the next column.
        let toMidnight = try #require(calendar.date(byAdding: .hour, value: 2, to: start))
        #expect(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: toMidnight, on: secondDay, calendar: calendar) == nil)
    }

    @Test("A very short event keeps the card's 5-minute floor")
    func aShortEventKeepsTheFloor() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let start = try Self.newYork(6, 11, 9, calendar)
        let end = start.addingTimeInterval(60)
        let range = try #require(CadenceScheduleSupport.boardCardMinuteRange(from: start, to: end, on: start, calendar: calendar))
        #expect(range.start == 9 * 60 && range.end == 9 * 60 + 5)
    }
}

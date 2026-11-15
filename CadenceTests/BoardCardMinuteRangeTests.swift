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

/// [[T-17871]] / [[T-17872]]: a short timed event is labelled with its true end on both iOS
/// calendar surfaces, as the Mac's board card and timeline block already are.
///
/// The Board card fed `boardCardMinuteRange` an end floored at start + 30, so a 15-minute event
/// read as 30; the timeline block printed and spoke `minuteRange`, whose end is floored at
/// start + 15 for geometry, so a 5-minute event read as 15. Both callers are iOS-only, so the rules
/// are the two shared helpers they call, and the source checks below pin that they call them.
@Suite("Short events keep their true end on iOS labels")
struct ShortEventLabelEndTests {
    private static func nineAM(_ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 9)))
    }

    @Test("A 15-minute event's board card ends at 9:15, a 0-minute or endless one at 9:05")
    func theBoardCardKeepsAShortEventsTrueEnd() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let start = try Self.nineAM(calendar)
        func card(_ end: Date?) throws -> (start: Int, end: Int) {
            let floored = CadenceScheduleSupport.boardCardEventEnd(start: start, end: end)
            return try #require(
                CadenceScheduleSupport.boardCardMinuteRange(from: start, to: floored, on: start, calendar: calendar)
            )
        }
        let quarter = try card(start.addingTimeInterval(15 * 60))
        #expect(quarter.start == 9 * 60 && quarter.end == 9 * 60 + 15, "a 15-minute card labelled to \(quarter.end)")
        let ten = try card(start.addingTimeInterval(10 * 60))
        #expect(ten.end == 9 * 60 + 10, "a 10-minute card labelled to \(ten.end)")
        // A zero-length event and one with no end are floored, and still intersect their day.
        #expect(try card(start).end == 9 * 60 + 5)
        #expect(try card(nil).end == 9 * 60 + 5)
        // A long event is untouched.
        #expect(try card(start.addingTimeInterval(90 * 60)).end == 10 * 60 + 30)
    }

    @Test("A 5- and 10-minute timeline block labels its true end, a 0-minute one the 5-minute floor")
    func theTimelineLabelKeepsAShortEventsTrueEnd() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/New_York")
        let start = try Self.nineAM(calendar)
        for minutes in [5, 10] {
            let end = start.addingTimeInterval(TimeInterval(minutes * 60))
            let label = CadenceScheduleSupport.timelineEventLabelRange(from: start, to: end, on: start, calendar: calendar)
            #expect(label.start == 9 * 60 && label.end == 9 * 60 + minutes, "a \(minutes)-minute block labelled to \(label.end)")
            // The geometry keeps its 15-minute floor; only the label moved.
            #expect(CadenceScheduleSupport.minuteRange(from: start, to: end, on: start, calendar: calendar).end == 9 * 60 + 15)
        }
        let zero = CadenceScheduleSupport.timelineEventLabelRange(from: start, to: start, on: start, calendar: calendar)
        #expect(zero.start == 9 * 60 && zero.end == 9 * 60 + 5)
        // A short event at the end of the day stops at midnight, as the Mac's block does.
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23, minute: 58)))
        #expect(CadenceScheduleSupport.timelineEventLabelRange(from: late, to: late, on: late, calendar: calendar).end == 24 * 60)
    }

    @Test("The iOS card and timeline block read the two helpers")
    func theIOSCallersReadTheHelpers() throws {
        let cards = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        #expect(cards.contains("CadenceScheduleSupport.boardCardEventEnd(start: eventStart, end: event.endDate)"))
        #expect(!cards.contains("30 * 60"), "the Board card floors a real end at 30 minutes again")

        let support = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarEventSupport.swift"))
        let labelRange = try #require(CadenceSourceScan.functionBody(named: "labelMinuteRange", in: support))
        #expect(labelRange.contains("CadenceScheduleSupport.timelineEventLabelRange("))

        let grid = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: grid)
        )
        #expect(column.contains("let label = iOSCalendarEventSupport.labelMinuteRange(for: event, on: date)"))
        #expect(column.contains("iOSCalendarEventBlock(event: event, startMin: label.start, endMin: label.end,"))
    }
}

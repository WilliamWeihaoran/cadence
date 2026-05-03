import CoreGraphics
import Foundation
import Testing
@testable import Cadence

@MainActor
struct GoalTimelineDateMathTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    @Test func convertsDatesToTimelineXPositions() {
        let rangeStart = date("2026-03-01")
        let target = date("2026-03-06")

        let x = GoalTimelineDateMath.xPosition(
            for: target,
            rangeStart: rangeStart,
            dayWidth: 12,
            calendar: calendar
        )

        #expect(x == 60)
    }

    @Test func createsInclusiveBarFrames() {
        let rangeStart = date("2026-03-01")

        let frame = GoalTimelineDateMath.barFrame(
            start: date("2026-03-03"),
            end: date("2026-03-05"),
            rangeStart: rangeStart,
            dayWidth: 10,
            calendar: calendar
        )

        #expect(frame.x == 20)
        #expect(frame.width == 30)
    }

    @Test func generatesMonthMarkersInsideVisibleRange() {
        let markers = GoalTimelineDateMath.monthMarkers(
            rangeStart: date("2026-02-15"),
            rangeEnd: date("2026-05-05"),
            dayWidth: 10,
            calendar: calendar
        )

        #expect(markers.map(\.label) == ["Mar", "Apr", "May"])
        #expect(markers.first?.x == CGFloat(14 * 10))
    }

    @Test func movingRangeShiftsStartAndEndTogether() throws {
        let moved = try #require(
            GoalTimelineDateMath.movedRange(
                start: date("2026-03-03"),
                end: date("2026-03-05"),
                dayDelta: 4,
                calendar: calendar
            )
        )

        #expect(DateFormatters.dateKey(from: moved.start) == "2026-03-07")
        #expect(DateFormatters.dateKey(from: moved.end) == "2026-03-09")
    }

    @Test func resizingRangeClampsToValidDates() throws {
        let leading = try #require(
            GoalTimelineDateMath.resizedRange(
                start: date("2026-03-10"),
                end: date("2026-03-15"),
                edge: .leading,
                dayDelta: 10,
                calendar: calendar
            )
        )
        let trailing = try #require(
            GoalTimelineDateMath.resizedRange(
                start: date("2026-03-10"),
                end: date("2026-03-15"),
                edge: .trailing,
                dayDelta: -10,
                calendar: calendar
            )
        )

        #expect(DateFormatters.dateKey(from: leading.start) == "2026-03-15")
        #expect(DateFormatters.dateKey(from: leading.end) == "2026-03-15")
        #expect(DateFormatters.dateKey(from: trailing.start) == "2026-03-10")
        #expect(DateFormatters.dateKey(from: trailing.end) == "2026-03-10")
    }

    @Test func missingDateKeysDoNotProduceBarFrames() {
        let frame = GoalTimelineDateMath.barFrame(
            startKey: "",
            endKey: "2026-03-05",
            rangeStart: date("2026-03-01"),
            dayWidth: 10,
            calendar: calendar
        )

        #expect(frame == nil)
    }

    private func date(_ key: String) -> Date {
        DateFormatters.date(from: key) ?? Date()
    }
}

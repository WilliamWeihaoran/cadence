import Foundation
import Testing
@testable import Cadence

/// [[T-18582]]: the Today and Calendar widgets turn the day on a second timeline entry dated at the
/// next start of day, built for that day from the same rows, rather than on a reload WidgetKit may
/// defer. The providers are not in the test target; the support they call is.
@MainActor
struct CadenceWidgetDayTurnTimelineTests {
    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func instant(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func task(_ title: String, due: String = "", scheduled: String = "") -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = due
        task.scheduledDate = scheduled
        return task
    }

    @Test func aTimelineCarriesTodayNowAndTheNextDayAtItsStart() {
        let calendar = Self.calendar("America/New_York")
        let now = Self.instant(2026, 11, 20, 23, 30, in: calendar)
        let days = CadenceWidgetDayTurnTimeline.entryDays(now: now, calendar: calendar)

        #expect(days.count == 2)
        #expect(days.first?.date == now)
        #expect(days.first?.day == Self.instant(2026, 11, 20, 0, 0, in: calendar))
        let midnight = Self.instant(2026, 11, 21, 0, 0, in: calendar)
        #expect(days.last?.date == midnight)
        #expect(days.last?.day == midnight)
    }

    /// Both DST turns in New York: a 23-hour and a 25-hour day still put the second entry at the
    /// next local midnight, not 24 hours on.
    @Test func theNextEntryLandsOnMidnightAcrossBothDaylightSavingTurns() {
        let calendar = Self.calendar("America/New_York")
        for (day, nextDay) in [((2026, 3, 8), (2026, 3, 9)), ((2026, 11, 1), (2026, 11, 2))] {
            let now = Self.instant(day.0, day.1, day.2, 22, 0, in: calendar)
            let next = CadenceWidgetDayTurnTimeline.entryDays(now: now, calendar: calendar).last?.date
            let midnight = Self.instant(nextDay.0, nextDay.1, nextDay.2, 0, 0, in: calendar)
            #expect(next == midnight, "\(day)")
            #expect(calendar.dateComponents([.hour, .minute], from: midnight) == DateComponents(hour: 0, minute: 0))
        }
    }

    @Test func theTodayTilesSecondEntryIsBuiltForTheNextDaysKey() {
        let calendar = Self.calendar("America/New_York")
        let now = Self.instant(2026, 11, 20, 23, 30, in: calendar)
        let dueToday = Self.task("due today", due: "2026-11-20")
        let dueTomorrow = Self.task("due tomorrow", due: "2026-11-21")

        let entries = CadenceTodayWidgetSupport.daySnapshots(
            from: [dueToday, dueTomorrow],
            limit: 8,
            now: now,
            calendar: calendar
        )

        #expect(entries.count == 2)
        let today = entries[0].snapshot
        #expect(today.dateKey == "2026-11-20")
        #expect(today.dueTodayCount == 1)
        #expect(today.overdueCount == 0)
        #expect(today.tasks.map(\.title) == ["due today"])

        let tomorrow = entries[1].snapshot
        #expect(entries[1].date == Self.instant(2026, 11, 21, 0, 0, in: calendar))
        #expect(tomorrow.dateKey == "2026-11-21")
        // Yesterday's due-today task is overdue on the turned tile, and tomorrow's is due today.
        #expect(tomorrow.dueTodayCount == 1)
        #expect(tomorrow.overdueCount == 1)
        #expect(tomorrow.totalCount == 2)
        #expect(tomorrow.tasks.map(\.title) == ["due today", "due tomorrow"])
    }

    /// [[T-18617]]: the strip is walked in the calendar the caller states, so this runs in every
    /// zone of `CadenceTestTimeZones` -- in one that is not the host's, a strip walked in
    /// `Calendar.current` keys its first cell a day early.
    @Test(arguments: CadenceTestTimeZones.identifiers)
    func theCalendarTilesSecondEntryStartsItsStripOnTheNextDay(_ zone: String) throws {
        let calendar = try CadenceTestTimeZones.calendar(zone)
        let now = Self.instant(2026, 11, 20, 23, 30, in: calendar)
        let dueToday = Self.task("due today", due: "2026-11-20")

        let entries = CadenceCalendarWidgetSupport.daySnapshots(
            from: [dueToday],
            dayCount: 14,
            now: now,
            calendar: calendar
        )

        #expect(entries.count == 2)
        #expect(entries[0].date == now)
        let today = entries[0].snapshot
        #expect(today.date == Self.instant(2026, 11, 20, 0, 0, in: calendar))
        #expect(today.days.first?.dateKey == "2026-11-20")
        #expect(today.days.first?.weekdayLabel == "FRI")
        #expect(today.days.first?.dayNumberLabel == "20")
        #expect(today.days.first?.isToday == true)
        #expect(today.days.first?.dueCount == 1)
        #expect(today.overdueCount == 0)

        let midnight = Self.instant(2026, 11, 21, 0, 0, in: calendar)
        #expect(entries[1].date == midnight)
        let turned = entries[1].snapshot
        #expect(turned.date == midnight)
        #expect(turned.days.count == 14)
        #expect(turned.days.first?.dateKey == "2026-11-21")
        #expect(turned.days.first?.weekdayLabel == "SAT")
        #expect(turned.days.first?.dayNumberLabel == "21")
        #expect(turned.days.first?.isToday == true)
        #expect(turned.days.last?.dateKey == "2026-12-04")
        #expect(turned.days.contains { $0.dateKey == "2026-11-20" } == false)
        #expect(turned.overdueCount == 1)
    }
}

#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-18863]] — the Mac Today timeline opened at the last session's scroll hour.**
///
/// `SchedulePanelStateSupport.restoreScrollHour` returned the remembered scroll hour whenever
/// it was at or past the canvas's first hour (0), so a scroll to 9 PM one evening opened the next
/// morning at 9 PM, with the 9 AM meeting and the now-line out of view above. The iPad's Today
/// timeline opens one hour above the day's first timed item, else at the current hour less one,
/// through `CadenceScheduleSupport.initialTimelineHour`; the Mac now asks the same function.
@MainActor
struct MacTodayTimelineOpeningHourTests {
    private static func at(hour: Int, minute: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: hour, minute: minute)))
    }

    /// A 9:00 event and a 10:00 task at 08:30: one hour above the earlier, which is the iPad's 8.
    @Test func theFirstTimedItemDecidesTheOpeningHour() throws {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let first = SchedulePanelStateSupport.firstTimedMinute(taskStartMinutes: [600], eventStartMinutes: [540])
        #expect(first == 540)
        let mac = SchedulePanelStateSupport.openingHour(
            firstTimedMinute: first,
            now: try Self.at(hour: 8, minute: 30, in: calendar),
            calendar: calendar
        )
        #expect(mac == 8)
        #expect(mac == CadenceScheduleSupport.initialTimelineHour(firstTimedMinute: first, showsToday: true, calendar: calendar))
    }

    /// Nothing timed at 08:30 opens at 7, the current hour less one -- the iPad's second rung.
    @Test func anEmptyTodayOpensAnHourBeforeNow() throws {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let now = try Self.at(hour: 8, minute: 30, in: calendar)
        #expect(SchedulePanelStateSupport.firstTimedMinute(taskStartMinutes: [], eventStartMinutes: []) == nil)
        let mac = SchedulePanelStateSupport.openingHour(firstTimedMinute: nil, now: now, calendar: calendar)
        #expect(mac == 7)
        #expect(mac == CadenceScheduleSupport.initialTimelineHour(showsToday: true, now: now, calendar: calendar))
    }

    /// The remembered hour is no longer an input, and the panel hands the restore today's blocks.
    @Test func thePanelOpensFromTodaysItemsNotTheRememberedHour() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let panel = try read("Cadence/macOS/Views/SchedulePanel.swift")
        let data = try read("Cadence/macOS/Views/SchedulePanelDataSupport.swift")
        let state = try read("Cadence/macOS/Views/SchedulePanelStateSupport.swift")
        #expect(panel.contains("taskStartMinutes: scheduledTasks.map(\\.scheduledStartMin)"))
        #expect(panel.contains("eventStartMinutes: externalEventItems.map(\\.startMin)"))
        #expect(panel.contains("rememberedScrollHour: rememberedScrollHour") == false)
        #expect(data.contains("restoreScrollHour(\n            firstTimedMinute: firstTimedMinute"))
        #expect(state.contains("CadenceScheduleSupport.initialTimelineHour("))
        #expect(state.contains("rememberedScrollHour") == false)
        // [[T-18869]]: nor is it still written. The key, its scroll observer and the T-1498
        // rationing that threaded the write are gone, so the panel names none of them.
        #expect(panel.contains("rememberedScrollHour") == false)
        #expect(panel.contains("onScrollGeometryChange") == false)
        #expect(panel.contains("SchedulePanelDataSupport.restoreScroll("))
    }
}
#endif

#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// An authorised calendar source whose day holds all-day events and nothing timed — the day
/// [[T-7982]] is about. The real `CalendarManager` is unauthorised on the test host and would
/// answer `[]` for both halves, so a test against it could not tell "dropped" from "never read".
private final class AllDayOnlyEventDaySource: CalendarEventDaySource {
    var isAuthorized: Bool = true
    var storeVersion: Int = 0
    var allDayTitles: [String] = ["Thanksgiving"]
    private let store = EKEventStore()

    func fetchEvents(for date: Date) -> [EKEvent] { [] }

    func fetchAllDayEvents(for date: Date) -> [EKEvent] {
        let dayStart = Calendar.current.startOfDay(for: date)
        return allDayTitles.map { title in
            let event = EKEvent(eventStore: store)
            event.title = title
            event.isAllDay = true
            event.startDate = dayStart
            event.endDate = dayStart.addingTimeInterval(86_400)
            return event
        }
    }
}

/// **T-7982 — Mac Today's Timeline pane never showed the day's all-day events.**
///
/// `SchedulePanelDataSupport.externalEventItems` reads the timed half only, and the pane had no
/// band above its ladder, so a holiday was on no part of Mac Today. The pane now reads the
/// Calendar day header's `CalendarEventDayCache.allDayEvents` door, draws a band when the day has
/// one, and the export lists them as "All day". Counts and relations only.
@MainActor
struct MacTodayTimelineAllDayBandTests {
    private static let day: Date =
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26))
            ?? Date(timeIntervalSince1970: 0)

    @Test("A day whose only event is all-day puts it in the pane's data, and not in the timed half")
    func anAllDayOnlyDayReachesThePane() {
        let source = AllDayOnlyEventDaySource()
        let cache = CalendarEventDayCache()

        let timed = SchedulePanelDataSupport.externalEventItems(
            calendarManager: source, date: Self.day, cache: cache
        )
        let allDay = SchedulePanelDataSupport.allDayEvents(
            calendarManager: source, date: Self.day, cache: cache
        )

        // The control: the timed read the pane always had sees nothing on this day.
        #expect(timed.isEmpty)
        #expect(allDay.count == 1)
        #expect(allDay.first?.title == "Thanksgiving")
    }

    @Test("An unauthorised source gives the band nothing, so it is not drawn")
    func anUnauthorisedSourceDrawsNoBand() {
        let source = AllDayOnlyEventDaySource()
        source.isAuthorized = false
        let allDay = SchedulePanelDataSupport.allDayEvents(
            calendarManager: source, date: Self.day, cache: CalendarEventDayCache()
        )
        #expect(allDay.isEmpty)
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: allDay.count) == 0)
    }

    @Test("The band costs nothing on an ordinary day and stops growing at its chip limit")
    func theBandHeightIsZeroThenCapped() {
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: 0) == 0)
        let one = SchedulePanelAllDayBandLayout.height(eventCount: 1)
        let three = SchedulePanelAllDayBandLayout.height(eventCount: SchedulePanelAllDayBandLayout.visibleChipLimit)
        let many = SchedulePanelAllDayBandLayout.height(eventCount: 9)
        #expect(one > 0)
        #expect(three > one)
        #expect(many == three)
    }

    @Test("The export lists an all-day event as All day, ahead of the timed ones")
    func theExportListsAllDayEventsFirst() throws {
        // The zone the host is pinned to, stated (CadenceTimeZoneIndependenceTests' rule).
        let start = try CadenceTestTimeZones.calendar(CadenceTestTimeZones.pinnedIdentifier)
            .startOfDay(for: Self.day)
        let store = EKEventStore()
        let timedEvent = EKEvent(eventStore: store)
        timedEvent.title = "Dinner"
        timedEvent.startDate = start.addingTimeInterval(18 * 3600)
        timedEvent.endDate = start.addingTimeInterval(20 * 3600)
        let timed = CalendarEventItem.timedSegments(from: [timedEvent], for: Self.day)
        try #require(timed.count == 1)

        let lines = SchedulePanelDataSupport.exportEventLines(
            allDayTitles: ["Thanksgiving"],
            timedEvents: timed
        )

        #expect(lines.count == 2)
        #expect(lines.first == "- All day • Thanksgiving")
        #expect(lines.last?.hasSuffix("• Dinner") == true)
        #expect(SchedulePanelDataSupport.exportEventLines(allDayTitles: [], timedEvents: []).isEmpty)
    }

    /// The data above is only worth anything if the pane draws it and the export reads it.
    @Test("SchedulePanel draws the band from the all-day read and exports through the shared lines")
    func schedulePanelUsesTheAllDayRead() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanel.swift")
        )
        #expect(code.components(separatedBy: "SchedulePanelDataSupport.allDayEvents(").count - 1 == 1)
        #expect(code.components(separatedBy: "SchedulePanelAllDayBand(events:").count - 1 == 1)
        #expect(code.components(separatedBy: "SchedulePanelDataSupport.exportEventLines(").count - 1 == 1)
    }
}
#endif

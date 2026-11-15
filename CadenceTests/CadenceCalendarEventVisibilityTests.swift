import EventKit
import Foundation
import Testing
@testable import Cadence

/// Pins [[T-18007]]: a declined invitation is hidden and an organizer-cancelled event is drawn as
/// cancelled, by one rule both calendar managers read. Decided over plain values, so no
/// `EKEventStore` is opened.
struct CadenceCalendarEventVisibilityTests {
    private typealias Attendee = CadenceCalendarEventVisibility.Attendee

    // MARK: - (a) declined is hidden

    @Test func anInvitationTheCurrentUserDeclinedIsHidden() {
        let attendees = [
            Attendee(isCurrentUser: false, status: .accepted),
            Attendee(isCurrentUser: true, status: .declined),
        ]
        #expect(CadenceCalendarEventVisibility.isShown(attendees: attendees) == false)
    }

    @Test func anInvitationTheCurrentUserAcceptedOrHasNotAnsweredIsShown() {
        for status: EKParticipantStatus in [.accepted, .tentative, .pending, .unknown, .delegated, .completed, .inProcess] {
            let attendees = [Attendee(isCurrentUser: true, status: status)]
            #expect(CadenceCalendarEventVisibility.isShown(attendees: attendees), "status \(status.rawValue)")
        }
    }

    @Test func anotherAttendeeDecliningDoesNotHideTheEvent() {
        let attendees = [
            Attendee(isCurrentUser: false, status: .declined),
            Attendee(isCurrentUser: true, status: .accepted),
        ]
        #expect(CadenceCalendarEventVisibility.isShown(attendees: attendees))
    }

    /// No attendees (a personal event) or no attendee marked as the current user (some CalDAV
    /// servers): there is no declined answer to read, so the event stays.
    @Test func anEventWithNoCurrentUserAttendeeIsShown() {
        #expect(CadenceCalendarEventVisibility.isShown(attendees: []))
        #expect(CadenceCalendarEventVisibility.isShown(attendees: [Attendee(isCurrentUser: false, status: .declined)]))
    }

    // MARK: - (b) cancelled is drawn as cancelled

    @Test func onlyACanceledStatusIsDrawnAsCancelled() {
        #expect(CadenceCalendarEventVisibility.isCancelled(status: .canceled))
        for status: EKEventStatus in [.none, .confirmed, .tentative] {
            #expect(CadenceCalendarEventVisibility.isCancelled(status: status) == false, "status \(status.rawValue)")
        }
    }

    @Test func aCancelledBlockIsDimmedButStillVisible() {
        #expect(CadenceCalendarEventVisibility.cancelledOpacity > 0)
        #expect(CadenceCalendarEventVisibility.cancelledOpacity < 1)
    }

    @Test func aCancelledEventSaysSoAndAnOrdinaryOneDoesNot() {
        #expect(
            CadenceCalendarDayAccessibility.timedEventLabel(title: "Standup", timeRange: "9:00 – 9:30 AM", isCancelled: true)
                == "Standup, 9:00 – 9:30 AM, canceled"
        )
        #expect(
            CadenceCalendarDayAccessibility.timedEventLabel(title: "Standup", timeRange: "9:00 – 9:30 AM", isCancelled: false)
                == "Standup, 9:00 – 9:30 AM"
        )
    }

    // MARK: - One rule, both platforms

    /// Every fetch both managers hand to a surface goes through the shared filter: the Mac day
    /// fetches and search window, and the iOS day fetch and search window.
    @Test func bothManagersFilterEveryDayFetchAndSearchWindow() throws {
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Services/CalendarManager.swift"))
        let ios = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift"))
        let filter = #"CadenceCalendarEventVisibility\.shown\(store\.events\(matching: predicate\)\)"#
        // fetchEvents, fetchAllDayEvents, windowEvents (which searchEvents reads).
        #expect(CadenceSourceScan.matchCount(filter, in: mac) == 3)
        // fetchEvents, searchEvents.
        #expect(CadenceSourceScan.matchCount(filter, in: ios) == 2)
    }
}

import EventKit
import Foundation
import Testing
@testable import Cadence

/// Pins the one calendar-event search filter both platforms now share (T-132).
///
/// The bug: `CalendarManager.searchEvents` (macOS) and `iOSCalendarManager.searchEvents` (iOS) had
/// the same name and the same default arguments and disagreed twice — macOS dropped every all-day
/// event and matched with `localizedLowercase.contains`, iOS kept them and matched with
/// `CadenceSearchMatcher`. Neither manager can be tested directly (both need an authorized
/// EventKit store, which the test machine deliberately does not have), so the shared decision they
/// both delegate to is what gets pinned here.
struct CadenceCalendarEventSearchSupportTests {

    /// One store for the whole test, not one per event. Swift Testing makes a fresh instance per
    /// test function, so this still isolates them from each other — but a suite that stands up a
    /// hundred `EKEventStore`s in parallel is asking EventKit for trouble it does not need.
    private let store = EKEventStore()

    private func event(
        title: String,
        notes: String? = nil,
        start: Date,
        durationMinutes: Int = 60,
        isAllDay: Bool = false
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return event
    }

    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - The regression

    /// macOS filtered `!$0.isAllDay` here, so Cmd+K could not find an all-day event at all — and
    /// because the one caller that resolves a picked result back to an `EKEvent` goes through this
    /// same function, it could not have opened one either.
    @Test func anAllDayEventIsFoundByItsTitle() {
        let birthday = event(title: "Marta's Birthday", start: now.addingTimeInterval(86_400), isAllDay: true)
        let standup = event(title: "Standup", start: now.addingTimeInterval(3_600))

        let results = CadenceCalendarEventSearchSupport.results(
            from: [birthday, standup],
            query: "birthday",
            now: now
        )

        #expect(results.count == 1)
        #expect(results.first?.title == "Marta's Birthday")
        #expect(results.first?.isAllDay == true)
    }

    @Test func allDayEventsAreNotExcludedFromAnEmptyQueryEither() {
        let allDay = event(title: "Conference", start: now.addingTimeInterval(86_400), isAllDay: true)
        let timed = event(title: "Standup", start: now.addingTimeInterval(3_600))

        let results = CadenceCalendarEventSearchSupport.results(from: [allDay, timed], query: "", now: now)

        #expect(results.map { $0.title ?? "" } == ["Standup", "Conference"])
    }

    // MARK: - Which matcher won

    /// The macOS side used a single `localizedLowercase.contains` over each field, which cannot
    /// match a two-word query whose words are not adjacent in the title. `CadenceSearchMatcher`
    /// scores per token, so it can — this is the behavioural difference between the two matchers,
    /// not just a difference in ranking.
    @Test func multiTokenQueriesMatchWordsThatAreNotAdjacent() {
        let event = event(title: "Team Weekly Standup", start: now.addingTimeInterval(3_600))

        #expect(CadenceCalendarEventSearchSupport.matches(query: "team standup", event: event))
        // The rule the old macOS body would have applied, spelled out so the contrast is explicit.
        #expect(!"team weekly standup".contains("team standup"))
    }

    @Test func punctuationAndDiacriticsDoNotBlockAMatch() {
        let event = event(title: "Réunion: Q3 Planning", start: now.addingTimeInterval(3_600))
        #expect(CadenceCalendarEventSearchSupport.matches(query: "reunion q3", event: event))
    }

    @Test func aQueryMatchingNothingReturnsNothing() {
        let event = event(title: "Standup", start: now.addingTimeInterval(3_600))
        #expect(CadenceCalendarEventSearchSupport.results(from: [event], query: "dentist", now: now).isEmpty)
    }

    // MARK: - Searched fields

    /// Title first: `CadenceSearchMatcher` weights the first field as the title, so the order is
    /// part of the contract rather than an accident of how the array was written.
    @Test func titleNotesAndCalendarNameAreAllSearchedInThatOrder() {
        let event = event(title: "Standup", notes: "bring the roadmap", start: now.addingTimeInterval(3_600))

        #expect(CadenceCalendarEventSearchSupport.searchFields(for: event) == ["Standup", "bring the roadmap", ""])
        #expect(CadenceCalendarEventSearchSupport.matches(query: "roadmap", event: event))
    }

    // MARK: - The empty-query window

    @Test func anEmptyQueryDropsEventsThatHaveAlreadyEnded() {
        let past = event(title: "Yesterday", start: now.addingTimeInterval(-86_400))
        let running = event(title: "Running", start: now.addingTimeInterval(-600), durationMinutes: 60)
        let future = event(title: "Later", start: now.addingTimeInterval(3_600))

        let results = CadenceCalendarEventSearchSupport.results(from: [past, running, future], query: "", now: now)

        // An event that is happening *right now* has not ended and is still upcoming.
        #expect(results.map { $0.title ?? "" } == ["Running", "Later"])
    }

    /// A non-empty query deliberately reaches back over the whole window — the past 60 days are
    /// searchable, they are just not listed unprompted.
    @Test func anExplicitQueryStillFindsPastEvents() {
        let past = event(title: "Retro", start: now.addingTimeInterval(-86_400))
        #expect(CadenceCalendarEventSearchSupport.results(from: [past], query: "retro", now: now).count == 1)
    }

    @Test func whitespaceOnlyQueriesAreTreatedAsEmpty() {
        let past = event(title: "Retro", start: now.addingTimeInterval(-86_400))
        #expect(CadenceCalendarEventSearchSupport.results(from: [past], query: "   ", now: now).isEmpty)
    }

    // MARK: - Ordering

    /// macOS sorted on `startDate` alone, leaving same-minute ties undefined. All-day events all
    /// start at midnight, so the tie is the common case among the results this fix newly admits.
    @Test func eventsStartingAtTheSameInstantAreOrderedByTitle() throws {
        let start = now.addingTimeInterval(86_400)
        let zulu = event(title: "Zulu", start: start)
        let alpha = event(title: "alpha", start: start)
        let mike = event(title: "Mike", start: start)

        // The tie itself is EventKit's to hand back, and these are timed events precisely so it
        // has no all-day normalization to do. Stated as requirements so that an environment which
        // stops returning what was set fails *saying so*, rather than as an ordering mismatch that
        // reads like a comparator bug.
        try #require(zulu.startDate == alpha.startDate)
        try #require(alpha.startDate == mike.startDate)
        try #require([zulu, alpha, mike].map(\.title) == ["Zulu", "alpha", "Mike"])

        let forward = CadenceCalendarEventSearchSupport.results(from: [zulu, alpha, mike], query: "", now: now)
        let reversed = CadenceCalendarEventSearchSupport.results(from: [mike, alpha, zulu], query: "", now: now)

        #expect(forward.map { $0.title ?? "" } == ["alpha", "Mike", "Zulu"])
        // Total, so input order cannot change the answer.
        #expect(reversed.map { $0.title ?? "" } == forward.map { $0.title ?? "" })
    }

    @Test func earlierEventsComeFirst() {
        let late = event(title: "Late", start: now.addingTimeInterval(7_200))
        let early = event(title: "Early", start: now.addingTimeInterval(3_600))
        let results = CadenceCalendarEventSearchSupport.results(from: [late, early], query: "", now: now)
        #expect(results.map { $0.title ?? "" } == ["Early", "Late"])
    }
}

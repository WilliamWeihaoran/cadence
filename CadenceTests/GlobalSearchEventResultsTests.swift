import EventKit
import Foundation
import Testing
@testable import Cadence

/// Pins which calendar events Cmd+K's **Events** section shows (T-149).
///
/// The bug: `eventResults` truncated with `events.prefix(12)` and *then* called `rankedResults`,
/// so it ranked the twelve chronologically-earliest matches rather than the twelve best. Every
/// other section in `GlobalSearchIndexSupport` ranks first and prefixes second; this one did not,
/// and the difference is invisible until more than twelve events match — at which point the exact
/// title you typed can be absent from a list of twelve.
@MainActor
struct GlobalSearchEventResultsTests {

    /// One store for the whole test — see `CadenceCalendarEventSearchSupportTests` for why.
    private let store = EKEventStore()

    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func event(title: String, start: Date) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3_600)
        return event
    }

    /// Thirteen events whose titles all *match* the query but only one of which matches it well,
    /// with the exact match last in chronological order. `searchEvents` hands `eventResults` its
    /// input already filtered and sorted by start date, so this is the shape the real caller
    /// produces — the padding events are what a busy month of "Design review — <team>" looks like.
    private func crowdedWindow() -> (events: [EKEvent], exactTitle: String) {
        let exactTitle = "Roadmap"
        var events: [EKEvent] = (0..<12).map { index in
            event(
                title: "Roadmap sync with the platform team \(index)",
                start: now.addingTimeInterval(TimeInterval(3_600 * (index + 1)))
            )
        }
        events.append(event(title: exactTitle, start: now.addingTimeInterval(3_600 * 20)))
        return (events, exactTitle)
    }

    // MARK: - The regression

    @Test func theBestMatchSurvivesEvenWhenTwelveWeakerOnesComeFirstInTime() {
        let (events, exactTitle) = crowdedWindow()

        let results = GlobalSearchIndexSupport.eventResults(from: events, query: "roadmap")

        // What the old body did: keep the twelve earliest, then rank those.
        let truncatedFirst = GlobalSearchIndexSupport.rankedResults(
            events.prefix(12).map { GlobalSearchIndexSupport.eventResult(for: $0) },
            query: "roadmap"
        )
        #expect(!truncatedFirst.contains { $0.title == exactTitle })

        #expect(results.first?.title == exactTitle)
    }

    @Test func theSectionStillCapsAtTwelveResultsForAQuery() {
        let (events, _) = crowdedWindow()
        #expect(GlobalSearchIndexSupport.eventResults(from: events, query: "roadmap").count == 12)
    }

    /// Ranking is by match score, not by start date — the point of the section is to answer the
    /// query, and the subtitle carries the date for the reader.
    @Test func anExactTitleMatchOutranksAnEarlierPartialOne() {
        let partial = event(title: "Retro prep", start: now.addingTimeInterval(3_600))
        let exact = event(title: "Retro", start: now.addingTimeInterval(86_400))

        let results = GlobalSearchIndexSupport.eventResults(from: [partial, exact], query: "retro")

        #expect(results.map(\.title) == ["Retro", "Retro prep"])
    }

    // MARK: - The empty-query branch, which is deliberately not the same

    /// With no query, `searchEvents` has already answered "what is coming up" in start-date order,
    /// so the first six are the answer and stay in that order. Ranking here would be actively
    /// wrong rather than merely redundant: an empty query scores every item equally and
    /// `CadenceSearchMatcher.rank` breaks the tie on title, which would list six events picked
    /// alphabetically out of a 365-day window.
    @Test func anEmptyQueryKeepsTheSoonestSixInChronologicalOrder() {
        // Titles deliberately counter-sorted against time, so an alphabetical answer and a
        // chronological one cannot be confused for each other.
        let titles = ["Zulu", "Yankee", "Xray", "Whiskey", "Victor", "Uniform", "Tango", "Sierra"]
        let events: [EKEvent] = titles.enumerated().map { index, title in
            event(title: title, start: now.addingTimeInterval(TimeInterval(3_600 * (index + 1))))
        }

        let results = GlobalSearchIndexSupport.eventResults(from: events, query: "")

        #expect(results.map(\.title) == Array(titles.prefix(6)))
    }

    @Test func aWhitespaceOnlyQueryTakesTheEmptyBranch() {
        let events: [EKEvent] = (0..<8).map { index in
            event(title: "Event \(index)", start: now.addingTimeInterval(TimeInterval(3_600 * (index + 1))))
        }

        #expect(GlobalSearchIndexSupport.eventResults(from: events, query: "   ").count == 6)
    }

    // MARK: - Row content

    @Test func anAllDayEventSaysAllDayRatherThanMidnightToMidnight() {
        let allDay = event(title: "Conference", start: now.addingTimeInterval(86_400))
        allDay.isAllDay = true

        let result = GlobalSearchIndexSupport.eventResult(for: allDay)

        #expect(result.subtitle.contains("All day"))
        #expect(!result.subtitle.contains("12:00 AM – 12:00 AM"))
    }

    @Test func aResultCarriesTheEventDestinationItResolvesThrough() {
        let standup = event(title: "Standup", start: now.addingTimeInterval(3_600))
        let result = GlobalSearchIndexSupport.eventResult(for: standup)

        guard case .event(let identifier) = result.destination else {
            Issue.record("expected an event destination")
            return
        }

        // The identifier a picked row hands to `CadenceCalendarEventSearchSupport.event(from:)`.
        #expect(CadenceEventNoteSupport.matches(standup, identifier: identifier))
    }
}

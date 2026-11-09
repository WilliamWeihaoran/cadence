import EventKit
import Foundation
import Testing
#if os(iOS)
import SwiftUI
#endif
@testable import Cadence

/// [[T-14622]]: a searching Events section breaks a score tie on TIME -- upcoming soonest first,
/// then past most-recent first -- before title, with occurrence identity as the last leg, through
/// the one comparator Cmd+K and iOS Search both rank with
/// (`CadenceCalendarEventSearchSupport.rankMatches`).
///
/// Every occurrence of a recurring series scores and titles alike, so the old order fell to the
/// identity leg, whose `#occurrence=<yyyy-MM-dd>` suffix sorts from the start of the 60-days-back
/// window: the fixture's identities ascend with the date on purpose, which is exactly the order
/// the old ranker produced.
enum EventSearchTimeRankFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400

    /// One standup series (two weeks back, two days back, tomorrow, the day after) and a second,
    /// same-titled series between its two upcoming occurrences -- the "1:1" case.
    struct Occurrence {
        let label: String
        let offsetDays: Double
        let identity: String
    }

    static let occurrences: [Occurrence] = [
        .init(label: "A-14d", offsetDays: -14, identity: "a#occurrence=2027-01-01:540"),
        .init(label: "A-2d", offsetDays: -2, identity: "a#occurrence=2027-01-13:540"),
        .init(label: "A+1d", offsetDays: 1, identity: "a#occurrence=2027-01-16:540"),
        .init(label: "A+2d", offsetDays: 2, identity: "a#occurrence=2027-01-17:540"),
        .init(label: "B+1.5d", offsetDays: 1.5, identity: "b#occurrence=2027-01-16:1260")
    ]

    /// Next-upcoming first, past ones last and most recent first, the second series interleaved
    /// by date rather than listed after the first.
    static let expected = ["A+1d", "B+1.5d", "A+2d", "A-2d", "A-14d"]

    static func event(in store: EKEventStore, offsetDays: Double, title: String = "Standup") -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = now.addingTimeInterval(offsetDays * day)
        event.endDate = event.startDate.addingTimeInterval(1_800)
        return event
    }
}

struct CadenceEventSearchTimeRankTests {
    private typealias Key = CadenceCalendarEventSearchSupport.SearchRankKey
    private let store = EKEventStore()
    private let now = EventSearchTimeRankFixture.now

    private func key(
        score: Int = 10,
        upcoming: Bool,
        start offsetDays: Double,
        title: String = "Standup",
        identity: String = "x"
    ) -> Key {
        Key(
            score: score,
            isUpcoming: upcoming,
            start: now.addingTimeInterval(offsetDays * EventSearchTimeRankFixture.day),
            title: title,
            identity: identity
        )
    }

    /// The shared ranker on the ticket's fixture: three occurrences of one series around now plus
    /// a same-titled second series, all one score, come out next-upcoming first.
    @Test func aRecurringSeriesRanksItsNextOccurrenceFirstAndPastOnesMostRecentFirst() {
        let fixture = EventSearchTimeRankFixture.occurrences
        let matches = fixture.map { occurrence in
            (occurrence: occurrence, event: EventSearchTimeRankFixture.event(in: store, offsetDays: occurrence.offsetDays))
        }
        // Handed over in identity (= old ranked) order, so an identity-only answer is the input.
        let ranked = CadenceCalendarEventSearchSupport.rankMatches(
            matches,
            now: now,
            event: { $0.event },
            score: { _ in 10 },
            title: { _ in "Standup" },
            identity: { $0.occurrence.identity }
        )
        #expect(ranked.map(\.occurrence.label) == EventSearchTimeRankFixture.expected)

        // Non-vacuity: the old leg order (score, title, identity) gives the oldest first.
        let old = CadenceSearchMatcher.rank(
            matches, score: { _ in 10 }, title: { _ in "Standup" }, identity: { $0.occurrence.identity }
        )
        #expect(old.first?.occurrence.label == "A-14d")
    }

    @Test func scoreStillDecidesBeforeTime() {
        let pastExact = key(score: 50, upcoming: false, start: -10)
        let upcomingPartial = key(score: 10, upcoming: true, start: 1)
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(pastExact, upcomingPartial))
        #expect(!CadenceCalendarEventSearchSupport.isRankedBefore(upcomingPartial, pastExact))
    }

    @Test func upcomingBeatsPastAndEachSideRunsAwayFromNow() {
        let soon = key(upcoming: true, start: 1)
        let later = key(upcoming: true, start: 3)
        let recent = key(upcoming: false, start: -1)
        let older = key(upcoming: false, start: -5)
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(soon, later))
        #expect(!CadenceCalendarEventSearchSupport.isRankedBefore(later, soon))
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(later, recent))
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(recent, older))
        #expect(!CadenceCalendarEventSearchSupport.isRankedBefore(older, recent))
    }

    /// A still-running occurrence is upcoming (`isUpcoming` reads the end), and comes before
    /// tomorrow's.
    @Test func anOccurrenceInProgressIsUpcomingAndFirst() {
        let inProgress = EventSearchTimeRankFixture.event(in: store, offsetDays: 0)
        inProgress.startDate = now.addingTimeInterval(-600)
        inProgress.endDate = now.addingTimeInterval(600)
        let tomorrow = EventSearchTimeRankFixture.event(in: store, offsetDays: 1)
        let yesterday = EventSearchTimeRankFixture.event(in: store, offsetDays: -1)
        let ranked = CadenceCalendarEventSearchSupport.rankMatches(
            [yesterday, tomorrow, inProgress],
            now: now,
            event: { $0 },
            score: { _ in 1 },
            title: { _ in "Standup" },
            identity: { $0 === yesterday ? "a" : $0 === tomorrow ? "b" : "c" }
        )
        #expect(ranked.map { $0 === inProgress ? "now" : $0 === tomorrow ? "tomorrow" : "yesterday" }
            == ["now", "tomorrow", "yesterday"])
    }

    /// Title, then identity, only once score and time tie: the order stays total.
    @Test func titleThenIdentityBreakATimeTie() {
        let alpha = key(upcoming: true, start: 1, title: "alpha", identity: "z")
        let beta = key(upcoming: true, start: 1, title: "Beta", identity: "a")
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(alpha, beta))
        let first = key(upcoming: true, start: 1, identity: "a")
        let second = key(upcoming: true, start: 1, identity: "b")
        #expect(CadenceCalendarEventSearchSupport.isRankedBefore(first, second))
        #expect(!CadenceCalendarEventSearchSupport.isRankedBefore(second, first))
        #expect(!CadenceCalendarEventSearchSupport.isRankedBefore(first, first))
    }
}

#if os(macOS)
/// Cmd+K's ranker on the fixture: `GlobalSearchIndexSupport.eventResults` for a title query.
@MainActor
struct CadenceEventSearchTimeRankMacTests {
    private let store = EKEventStore()

    @Test func cmdKListsARecurringSeriesFromItsNextOccurrence() {
        let now = EventSearchTimeRankFixture.now
        let labelled = EventSearchTimeRankFixture.occurrences.map { occurrence in
            (label: occurrence.label, event: EventSearchTimeRankFixture.event(in: store, offsetDays: occurrence.offsetDays))
        }
        let idToLabel = Dictionary(uniqueKeysWithValues: labelled.map {
            (GlobalSearchIndexSupport.eventResult(for: $0.event, relativeTo: now).id, $0.label)
        })
        let results = GlobalSearchIndexSupport.eventResults(from: labelled.map(\.event), query: "standup", relativeTo: now)
        #expect(results.count == labelled.count)
        #expect(results.map { idToLabel[$0.id] ?? "?" } == EventSearchTimeRankFixture.expected)
    }
}
#endif

#if os(iOS)
/// iOS Search's ranker on the fixture: `iOSSearchIndexSupport.rankedEventResults`.
@MainActor
struct CadenceEventSearchTimeRankIOSTests {
    private let store = EKEventStore()

    @Test func iOSSearchListsARecurringSeriesFromItsNextOccurrence() {
        let now = EventSearchTimeRankFixture.now
        let matches = EventSearchTimeRankFixture.occurrences.map { occurrence in
            let event = EventSearchTimeRankFixture.event(in: store, offsetDays: occurrence.offsetDays)
            let row = iOSSearchResult(
                id: CadenceSearchIdentity.event(occurrence.identity),
                destination: .event(event),
                title: "Standup",
                subtitle: occurrence.label,
                detail: "",
                icon: CadenceSearchEventGlyph.systemImage,
                color: .blue,
                score: 10
            )
            return (event: event, row: row)
        }
        let ranked = iOSSearchIndexSupport.rankedEventResults(matches, now: now)
        #expect(ranked.map(\.subtitle) == EventSearchTimeRankFixture.expected)
        // Non-vacuity: the generic funnel it replaced lists the oldest first.
        #expect(iOSSearchIndexSupport.rankedResults(matches.map(\.row)).first?.subtitle == "A-14d")
    }
}
#endif

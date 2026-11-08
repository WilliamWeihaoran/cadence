// macOS only: `GlobalSearchIndexSupport` is the Cmd+K palette and is behind `#if os(macOS)`.
#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// [[T-12801]]: Cmd+K ranks a matched row by the fields it MATCHED on, as iOS Search does.
///
/// The palette gated tasks and notes on their whole shared field lists and then re-scored them on
/// the two lines the row draws, so every row found through its notes or body scored no match,
/// sank together, and read A to Z. iOS Search ranks the same rows by the gate's own score
/// (`iOSSearchIndexSupport.rankedResults` over `CadenceSearchMatcher.matchScore`). Each fixture
/// below is two rows that only the hidden field finds, chosen so that the score order is the
/// REVERSE of the alphabetical order -- the defect's order -- and each test first asserts that the
/// two scores really differ, so it cannot pass on a tie.
@MainActor
struct CadenceGlobalSearchMatchedFieldRankingTests {

    /// One query word, deep in one body and first in the other. `CadenceSearchMatcher` scores a
    /// word-prefix hit by how early it sits, so the earlier hit is the better match.
    private static let query = "dentist"
    private static let deepBody = "one two three four five six seven eight nine ten eleven dentist"
    private static let shallowBody = "dentist"

    @Test func aTaskFoundThroughItsNotesRanksByThatMatchRatherThanByTitle() {
        let alpha = AppTask(title: "Alpha errand")
        alpha.notes = Self.deepBody
        let beta = AppTask(title: "Beta errand")
        beta.notes = Self.shallowBody

        let alphaScore = CadenceTaskSearchSupport.matchScore(query: Self.query, task: alpha)
        let betaScore = CadenceTaskSearchSupport.matchScore(query: Self.query, task: beta)
        #expect(alphaScore != nil && betaScore != nil)
        #expect((betaScore ?? 0) > (alphaScore ?? 0))

        let palette = GlobalSearchIndexSupport.taskResults(tasks: [alpha, beta], query: Self.query)
        #expect(palette.map(\.title) == ["Beta errand", "Alpha errand"])
    }

    @Test func aNoteFoundThroughItsBodyRanksByThatMatchRatherThanByTitle() {
        let alpha = Note(kind: .permanent, title: "Alpha page", content: Self.deepBody)
        let beta = Note(kind: .permanent, title: "Beta page", content: Self.shallowBody)

        let fields: (Note) -> [String] = { [$0.title, $0.content] }
        let alphaScore = CadenceSearchMatcher.matchScore(query: Self.query, fields: fields(alpha))
        let betaScore = CadenceSearchMatcher.matchScore(query: Self.query, fields: fields(beta))
        #expect(alphaScore != nil && betaScore != nil)
        #expect((betaScore ?? 0) > (alphaScore ?? 0))

        let palette = GlobalSearchIndexSupport.noteResults(notes: [alpha, beta], query: Self.query, taskTitles: [:])
        #expect(palette.map(\.title) == ["Beta page", "Alpha page"])
    }

    /// [[T-12803]]: the Events section, the one [[T-12801]] left on the drawn row. Two events that
    /// only their notes find; the palette must rank them by the shared ranking fields iOS Search
    /// scores (`CadenceCalendarEventSearchSupport.rankingFields`), not A to Z.
    @Test func anEventFoundThroughItsNotesRanksByThatMatchRatherThanByTitle() {
        let store = EKEventStore()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ title: String, notes: String) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.notes = notes
            event.startDate = start
            event.endDate = start.addingTimeInterval(3_600)
            return event
        }
        let alpha = event("Alpha sync", notes: Self.deepBody)
        let beta = event("Beta sync", notes: Self.shallowBody)

        let score: (EKEvent) -> Int? = {
            CadenceSearchMatcher.matchScore(
                query: Self.query,
                fields: CadenceCalendarEventSearchSupport.rankingFields(
                    for: $0, dayTimeLine: GlobalSearchIndexSupport.eventDayTimeLine(for: $0, relativeTo: start)
                )
            )
        }
        #expect(score(alpha) != nil && score(beta) != nil)
        #expect((score(beta) ?? 0) > (score(alpha) ?? 0))

        let palette = GlobalSearchIndexSupport.eventResults(from: [alpha, beta], query: Self.query, relativeTo: start)
        #expect(palette.map(\.title) == ["Beta sync", "Alpha sync"])
    }
}
#endif

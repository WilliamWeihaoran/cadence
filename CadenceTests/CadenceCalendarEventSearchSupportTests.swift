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

    // MARK: - Resolving a picked result (T-149)

    /// The divergence: `macOSRootCommandActionSupport` resolved a Cmd+K event result by calling
    /// `searchEvents(matching: "")` and scanning the answer. That is the `isUpcoming` branch, so a
    /// finished event — which an explicit query *does* return, per the test above — was findable
    /// and not openable. Both halves are asserted together here so the contradiction is the test.
    @MainActor @Test func aPastEventCanBeResolvedEvenThoughAnEmptyQueryHidesIt() throws {
        let retro = event(title: "Retro", start: now.addingTimeInterval(-86_400))
        let upcoming = event(title: "Standup", start: now.addingTimeInterval(3_600))
        let window = [retro, upcoming]
        let retroID = CadenceEventNoteSupport.identifier(for: retro)

        // What the old resolve path saw.
        let asSearched = CadenceCalendarEventSearchSupport.results(from: window, query: "", now: now)
        try #require(!asSearched.contains { CadenceEventNoteSupport.matches($0, identifier: retroID) })

        let resolved = CadenceCalendarEventSearchSupport.event(from: window, identifier: retroID)
        #expect(resolved === retro)
    }

    @MainActor @Test func resolvingPicksTheOneEventNamedAndNotSimplyTheFirst() {
        let first = event(title: "Standup", start: now.addingTimeInterval(3_600))
        let second = event(title: "Retro", start: now.addingTimeInterval(7_200))

        let resolved = CadenceCalendarEventSearchSupport.event(
            from: [first, second],
            identifier: CadenceEventNoteSupport.identifier(for: second)
        )

        #expect(resolved === second)
    }

    /// An empty identifier is not "match whatever comes first" — `matches` compares strings, and a
    /// fallback identifier is never empty, but the guard says so rather than relying on that.
    @MainActor @Test func anEmptyIdentifierResolvesToNothing() {
        let standup = event(title: "Standup", start: now.addingTimeInterval(3_600))
        #expect(CadenceCalendarEventSearchSupport.event(from: [standup], identifier: "") == nil)
    }

    @MainActor @Test func anUnknownIdentifierResolvesToNothing() {
        let standup = event(title: "Standup", start: now.addingTimeInterval(3_600))
        #expect(CadenceCalendarEventSearchSupport.event(from: [standup], identifier: "not-an-event") == nil)
    }

    // MARK: - The third spelling of the identity rule (T-438)

    /// `iOSBoardCards` was the copy T-403 did not reach. It spelled
    /// `event.eventIdentifier ?? event.calendarItemIdentifier` and, when that came back empty, fell
    /// through to `"\(dateKey)-\(event.hash)"`.
    ///
    /// Two things were wrong with it, and this pins the second because the first is unarrangeable:
    /// `??` only catches a **nil** event identifier, never an empty one, and `EKEvent.hash` is
    /// `NSObject`'s — derived from the instance's address, so it is a property of the *object* and
    /// not of the event. Two reads of one meeting are two objects.
    @Test func anObjectHashIsNotAnEventIdentity() {
        let one = event(title: "Standup", start: now.addingTimeInterval(3_600))
        let other = event(title: "Standup", start: now.addingTimeInterval(3_600))

        #expect(one.hash != other.hash,
                "EKEvent.hash was content-derived after all, which this assertion assumed it is not")
        #expect(CadenceEventNoteSupport.rawIdentifier(for: one)
                != CadenceEventNoteSupport.rawIdentifier(for: other),
                "two separate events collapsed onto one identity")
    }

    /// Why the `event.hash` branch was reachable-but-never-right: the shared rule already answers
    /// for every shape the board can hand it, and never with an empty string. There is nothing left
    /// for a fallback of last resort to do.
    @Test func theSharedIdentityRuleAnswersForEveryEventShapeTheBoardSees() {
        let shapes = [
            event(title: "Standup", start: now.addingTimeInterval(3_600)),
            event(title: "Conference", start: now.addingTimeInterval(86_400), isAllDay: true),
            event(title: "", start: now.addingTimeInterval(7_200)),
            EKEvent(eventStore: store)
        ]

        for (index, subject) in shapes.enumerated() {
            let identity = CadenceEventNoteSupport.rawIdentifier(for: subject)
            #expect(!identity.isEmpty, "shape \(index) has no identity, so a fallback is still needed")
        }
    }

    /// The rule is stable for one object across repeated reads, which the `hash` fallback also was
    /// **within** a launch — the difference is that this one is derived from the event.
    @Test func theSharedIdentityRuleIsStableForOneEvent() {
        let standup = event(title: "Standup", start: now.addingTimeInterval(3_600))
        let first = CadenceEventNoteSupport.rawIdentifier(for: standup)
        #expect(first == CadenceEventNoteSupport.rawIdentifier(for: standup))
        #expect(first == standup.calendarItemIdentifier,
                "an unsaved event has no eventIdentifier, so the rule should land on the item one")
    }

    /// A **source scan**: `iOSBoardCards.swift` is under `Cadence/iOS/`, behind `#if os(iOS)`, and
    /// this target builds for macOS — so `iOSCalendarBoardEventItem` cannot be constructed here.
    /// What is checkable is that the board card reads the rule above instead of re-typing it.
    @Test func theBoardCardReadsTheSharedIdentityRuleRatherThanRespellingIt() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSBoardCards.swift")
        #expect(raw.count > 400, "the board cards read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct iOSCalendarBoardEventItem"), "the board event item moved")

        #expect(source.contains("let eventIdentifier = CadenceEventNoteSupport.rawIdentifier(for: event)"),
                "the board card does not read the shared identity rule")
        #expect(CadenceSourceScan.matchCount(#"event\.hash"#, in: source) == 0,
                "the board card still keys an identity off an object hash (T-438)")
        #expect(CadenceSourceScan.matchCount(#"eventIdentifier\s*\?\?"#, in: source) == 0,
                "the board card still spells its own identity fallback")
        #expect(CadenceSourceScan.matchCount(#"calendarItemIdentifier"#, in: source) == 0,
                "the board card still reaches for EventKit's identifiers directly")
    }

    /// Without this the three `== 0` assertions above are true of any text at all.
    @Test func theBoardCardScanNeedlesAreNotVacuous() {
        #expect(CadenceSourceScan.matchCount(#"event\.hash"#, in: ##"let id = "\(dateKey)-\(event.hash)""##) == 1)
        #expect(CadenceSourceScan.matchCount(#"event\.hash"#, in: "eventHashes.count") == 0)
        #expect(CadenceSourceScan.matchCount(#"eventIdentifier\s*\?\?"#,
                                             in: "event.eventIdentifier ?? event.calendarItemIdentifier") == 1)
        #expect(CadenceSourceScan.matchCount(#"eventIdentifier\s*\?\?"#,
                                             in: "let eventIdentifier = CadenceEventNoteSupport.rawIdentifier(for: event)") == 0)
        #expect(CadenceSourceScan.matchCount(#"calendarItemIdentifier"#, in: "event.calendarItemIdentifier") == 1)
        #expect(CadenceSourceScan.matchCount(#"calendarItemIdentifier"#, in: "event.eventIdentifier") == 0)
    }
}

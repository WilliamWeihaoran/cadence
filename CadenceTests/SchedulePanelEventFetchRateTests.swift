#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// A calendar source that **is** authorised, returns events, and counts what was asked of it.
///
/// This exists because the real thing cannot answer the question. `CalendarManager.fetchEvents(for:)`
/// opens with `guard isAuthorized else { return [] }`, and the test host is not calendar-authorised,
/// so against the shipping object a fetch-count assertion reads zero whether the cache works,
/// whether the caller bypasses it, or whether the reading is simply unreachable. That is the
/// failure mode T-1499 was filed refusing to reproduce: a disqualifying column that never
/// disqualifies is indistinguishable from one that cannot reach the reading.
///
/// It conforms to `CalendarEventDaySource` — the seam added for this ticket — which is the *whole*
/// of what `CalendarEventDayCache` touches, so a fake that satisfies it cannot be satisfying less
/// than the cache actually uses.
private final class CountingEventDaySource: CalendarEventDaySource {
    var isAuthorized: Bool = true
    var storeVersion: Int = 0
    /// How many events each fetch answers with. Changed mid-test to prove a refetch really went
    /// back to the source rather than replaying a cached answer.
    var eventsPerFetch: Int = 3

    private(set) var timedFetchCount = 0
    private(set) var allDayFetchCount = 0

    private let store = EKEventStore()

    func fetchEvents(for date: Date) -> [EKEvent] {
        timedFetchCount += 1
        return makeEvents(on: date, allDay: false)
    }

    func fetchAllDayEvents(for date: Date) -> [EKEvent] {
        allDayFetchCount += 1
        return makeEvents(on: date, allDay: true)
    }

    private func makeEvents(on date: Date, allDay: Bool) -> [EKEvent] {
        let dayStart = Calendar.current.startOfDay(for: date)
        return (0..<eventsPerFetch).map { index in
            let event = EKEvent(eventStore: store)
            event.title = "Event \(index)"
            event.isAllDay = allDay
            // 09:00, 10:00, 11:00 … one hour each, so every one clips to a distinct segment.
            event.startDate = dayStart.addingTimeInterval(TimeInterval((9 + index) * 3600))
            event.endDate = dayStart.addingTimeInterval(TimeInterval((10 + index) * 3600))
            return event
        }
    }
}

/// **T-1499 — Today's timeline queried `EKEventStore` once per render; now it queries once.**
///
/// Found by census out of T-1498's two-host diff, not by a timer. Today's timeline and the calendar
/// page draw the *same* `TimelineDayCanvas`; the calendar page's host has always read its events
/// through `CalendarEventDayCache`, and `SchedulePanel` called `CalendarManager.fetchEvents(for:)`
/// straight through — an `NSPredicate` and an `EKEventStore.events(matching:)` per body evaluation,
/// with no memoisation of any kind. T-1498 made that cost once per *gesture* rather than once per
/// frame, so this was never a scroll-rate defect by the time it was fixed. It was one store query
/// per *render* of a panel that re-renders on every task change, every store refresh and every zoom
/// step.
///
/// **The seam is the deliverable as much as the cache line is.** Option (a) of the three the ticket
/// named: `CalendarEventDaySource` is the four members `CalendarEventDayCache` reads off
/// `CalendarManager`, and nothing else. Option (b) — an authorised host — was not taken, because
/// granting the test host calendar access makes the numbers below depend on the machine's own
/// calendar contents, which is the opposite of a bound.
///
/// **Every count here has a control that must come out differently**, because the reading these
/// tests are worth anything against is the one where the source is never consulted at all. The
/// unauthorised control is not a hypothetical: it is character for character what the real
/// `CalendarManager` does on this host.
///
/// **Counts and relations only, never a duration.** CI runs Xcode 26 and this Mac 27
/// (T-1279/T-1296).
@MainActor
struct SchedulePanelEventFetchRateTests {

    /// 2026-06-11, fixed. The `TestAction` pins `TZ=UTC` (T-1116).
    private static func day(_ dayOfMonth: Int = 11) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: dayOfMonth))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// One render of `SchedulePanel.externalEventItems`, through the shipping call.
    private func render(
        _ source: CountingEventDaySource,
        cache: CalendarEventDayCache,
        day: Date
    ) -> [CalendarEventItem] {
        SchedulePanelDataSupport.externalEventItems(
            calendarManager: source,
            date: day,
            cache: cache
        )
    }

    /// The expression `SchedulePanelDataSupport.externalEventItems` **held before this ticket**,
    /// written out verbatim. Nothing here models the old decision; it *is* the old line, so the
    /// before and after numbers come out of one source through two code paths that differ in
    /// exactly the thing that changed.
    private func renderUncached(_ source: CountingEventDaySource, day: Date) -> [CalendarEventItem] {
        CalendarEventItem.timedSegments(from: source.fetchEvents(for: day), for: day)
    }

    // MARK: - The denominator, first

    /// **What makes every number below mean anything.** One render of the shipping path against an
    /// authorised source fetches once and draws three events; the identical render against the same
    /// source with `isAuthorized` false fetches **zero** times and draws nothing.
    ///
    /// The second line is not a hypothetical control — it is exactly what the real
    /// `CalendarManager` does on this test host, and therefore exactly what a fetch-count assertion
    /// written against the shipping object would have read no matter what the code did. The two
    /// numbers must differ or nothing in this file is measuring the cache.
    @Test("The counted source is the one being consulted, and an unauthorised one reads zero")
    func theSourceIsActuallyConsulted() {
        let source = CountingEventDaySource()
        let items = render(source, cache: CalendarEventDayCache(), day: Self.day())

        #expect(source.timedFetchCount == 1,
                "the authorised source was fetched \(source.timedFetchCount) times, not once")
        #expect(items.count == 3,
                "the authorised source drew \(items.count) items, not the 3 events it returned")

        let unauthorised = CountingEventDaySource()
        unauthorised.isAuthorized = false
        let nothing = render(unauthorised, cache: CalendarEventDayCache(), day: Self.day())

        #expect(unauthorised.timedFetchCount == 0,
                """
                the unauthorised source was fetched \(unauthorised.timedFetchCount) times. At any \
                number other than 0 the control is not the vacuous reading it is here to name.
                """)
        #expect(nothing.isEmpty)
        #expect(source.timedFetchCount != unauthorised.timedFetchCount,
                "both readings came out \(source.timedFetchCount); this file measures nothing")
    }

    // MARK: - The measurement the fix is answering

    /// **The before number.** Twelve renders of the pre-T-1499 expression are twelve
    /// `EKEventStore.events(matching:)` queries — one per body evaluation, which is the defect
    /// stated as a count.
    @Test("Uncached, one render is one store query")
    func theUncachedPanelQueriedOncePerRender() {
        let source = CountingEventDaySource()
        let day = Self.day()

        for _ in 0..<12 { _ = renderUncached(source, day: day) }

        #expect(source.timedFetchCount == 12,
                "12 renders made \(source.timedFetchCount) queries")
    }

    /// **The after number, and the bound.** The same twelve renders through the shipping path,
    /// holding the cache the way `SchedulePanel` holds it: **one** query, and every render still
    /// draws all three events, so the saving was not bought by drawing less.
    @Test("Cached, twelve renders of one day are one store query")
    func theCachedPanelQueriesOncePerDay() {
        let source = CountingEventDaySource()
        let cache = CalendarEventDayCache()
        let day = Self.day()

        var drawn: [Int] = []
        for _ in 0..<12 { drawn.append(render(source, cache: cache, day: day).count) }

        #expect(source.timedFetchCount == 1,
                "12 renders made \(source.timedFetchCount) queries, not 1")
        #expect(drawn == Array(repeating: 3, count: 12),
                "the renders drew \(drawn); a cache that drops events is not a cache")
        #expect(source.timedFetchCount < drawn.count)
    }

    /// The difference between a bound and a coincidence: five times the renders is five times the
    /// old number and leaves the new one at one. Nothing about the fix is tuned to 12.
    @Test("The query count does not follow the render count")
    func theQueryCountDoesNotFollowTheRenderCount() {
        let day = Self.day()

        let coarseUncached = CountingEventDaySource()
        for _ in 0..<12 { _ = renderUncached(coarseUncached, day: day) }
        let fineUncached = CountingEventDaySource()
        for _ in 0..<60 { _ = renderUncached(fineUncached, day: day) }

        #expect(coarseUncached.timedFetchCount == 12)
        #expect(fineUncached.timedFetchCount == 60)

        let coarse = CountingEventDaySource()
        let coarseCache = CalendarEventDayCache()
        for _ in 0..<12 { _ = render(coarse, cache: coarseCache, day: day) }
        let fine = CountingEventDaySource()
        let fineCache = CalendarEventDayCache()
        for _ in 0..<60 { _ = render(fine, cache: fineCache, day: day) }

        #expect(coarse.timedFetchCount == fine.timedFetchCount,
                "12 renders cost \(coarse.timedFetchCount) and 60 cost \(fine.timedFetchCount)")
        #expect(fine.timedFetchCount == 1)
    }

    // MARK: - What the cache must never swallow

    /// A store change refetches, and the refetch is a **real** one: the source is told to answer
    /// with five events instead of three, and the render after the bump draws five. Without that
    /// second half the count alone could not tell a refetch from a replayed answer.
    ///
    /// This is the half that makes the panel's `let _ = calendarManager.storeVersion` still load
    /// bearing — it is both the SwiftUI subscription and the cache's invalidation.
    @Test("A store change refetches, and the refetched answer is the new one")
    func aStoreChangeIsNotServedFromTheCache() {
        let source = CountingEventDaySource()
        let cache = CalendarEventDayCache()
        let day = Self.day()

        for _ in 0..<5 { _ = render(source, cache: cache, day: day) }
        #expect(source.timedFetchCount == 1)

        source.eventsPerFetch = 5
        let stale = render(source, cache: cache, day: day)
        #expect(source.timedFetchCount == 1,
                "the cache went back to the store without the store changing")
        #expect(stale.count == 3, "the control: with no bump the answer is still the cached one")

        source.storeVersion += 1
        let fresh = render(source, cache: cache, day: day)

        #expect(source.timedFetchCount == 2,
                "a store change made \(source.timedFetchCount) total queries, not 2")
        #expect(fresh.count == 5,
                "the refetch drew \(fresh.count) events; it replayed the cached answer")
    }

    /// A different day is a different key. The panel draws one day, but it outlives midnight, and a
    /// cache keyed on nothing would pin yesterday's events on today's canvas forever.
    @Test("A second day is a second query, not the first day's answer")
    func adifferentDayIsADifferentKey() {
        let source = CountingEventDaySource()
        let cache = CalendarEventDayCache()

        for _ in 0..<4 { _ = render(source, cache: cache, day: Self.day(11)) }
        #expect(source.timedFetchCount == 1)

        let tomorrow = render(source, cache: cache, day: Self.day(12))

        #expect(source.timedFetchCount == 2,
                "two days cost \(source.timedFetchCount) queries, not 2")
        #expect(tomorrow.map(\.dateKey) == Array(repeating: "2026-06-12", count: 3),
                "the second day drew \(tomorrow.map(\.dateKey))")

        // …and it did not evict the first, so alternating days is still two queries and not four.
        _ = render(source, cache: cache, day: Self.day(11))
        _ = render(source, cache: cache, day: Self.day(12))
        #expect(source.timedFetchCount == 2,
                "alternating two days cost \(source.timedFetchCount) queries")
    }

    // MARK: - Neither host of the canvas may lose the cache again

    /// Both halves, because this defect was a *missing* indirection and a missing indirection leaves
    /// no trace. The panel's route through the cache is pinned here, and so is the calendar page's —
    /// the control host is only a control for as long as it stays cached.
    @Test("Both hosts of the timeline canvas read their events through the day cache")
    func bothHostsOfTheCanvasReadThroughTheCache() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let support = try read("Cadence/macOS/Views/SchedulePanelDataSupport.swift")
        #expect(support.isEmpty == false, "the reader read nothing, so nothing below is a reading")
        #expect(support.contains("cache.timedEvents("),
                "Today's timeline no longer goes through the day cache")
        #expect(support.contains("calendarManager.fetchEvents(") == false,
                "Today's timeline queries the store directly again")

        // Non-vacuity for the line above: the host must actually own a cache, or the parameter is
        // being handed a fresh one per render and the memo never survives a body evaluation.
        let panel = try read("Cadence/macOS/Views/SchedulePanel.swift")
        #expect(panel.contains("@State private var eventCache = CalendarEventDayCache()"))
        #expect(panel.contains("cache: eventCache"))
        #expect(panel.contains("calendarManager.storeVersion"),
                "the subscription that is also the cache's invalidation is gone")

        let page = try read("Cadence/macOS/Views/CalendarPageView.swift")
        #expect(page.contains("@State private var calendarEventDayCache = CalendarEventDayCache()"),
                "the control host lost its cache, so it is no longer a control")
    }

    /// The seam is narrow on purpose, and staying narrow is the claim. A `CalendarEventDaySource`
    /// that grew write methods would be a fake that can lie about saving events, which is not what
    /// a read-through cache needs to be testable.
    @Test("The seam names only what the day cache reads")
    func theSeamStaysNarrow() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/macOS/Views/CalendarTimelineSupport.swift")

        #expect(source.contains("protocol CalendarEventDaySource"))
        #expect(source.contains("extension CalendarManager: CalendarEventDaySource"),
                "the shipping manager no longer satisfies the seam a test substitutes for")

        // The protocol's own body, not the file's: the four members and nothing else. A seam that
        // restates `CalendarManager` teaches a fake to lie about everything, writes included.
        let opener = "protocol CalendarEventDaySource: AnyObject {"
        let afterOpener = try #require(source.range(of: opener)).upperBound
        let closer = try #require(source.range(of: "\n}", range: afterOpener..<source.endIndex))
        let body = String(source[afterOpener..<closer.lowerBound])

        let declared = body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        #expect(declared == [
            "var isAuthorized: Bool { get }",
            "var storeVersion: Int { get }",
            "func fetchEvents(for date: Date) -> [EKEvent]",
            "func fetchAllDayEvents(for date: Date) -> [EKEvent]"
        ], "the seam now declares \(declared)")
    }
}
#endif

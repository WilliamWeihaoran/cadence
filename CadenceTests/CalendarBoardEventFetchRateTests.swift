#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// A calendar source that **is** authorised, answers with events, and counts both halves of what
/// was asked of it.
///
/// The same reason T-1499's `CountingEventDaySource` exists, one surface over.
/// `CalendarManager.fetchEvents(for:)` and `fetchAllDayEvents(for:)` both open with
/// `guard isAuthorized else { return [] }`, and the test host is not calendar-authorised — so
/// against the shipping object every count in this file reads zero whether the cache works, whether
/// the caller bypasses it, or whether the reading is simply unreachable. A count with no control is
/// the shape this repo keeps finding, and it is what the denominator test below refuses to be.
///
/// It counts the two fetches separately because the board's defect was *two* queries per column,
/// not one: the all-day half is a second `NSPredicate` and a second `EKEventStore.events(matching:)`
/// that no test of the timeline's single timed fetch would have covered.
private final class CountingBoardEventDaySource: CalendarEventDaySource {
    var isAuthorized: Bool = true
    var storeVersion: Int = 0
    /// How many events each half answers with. Different numbers on purpose, so a drawn item can be
    /// attributed to the half it came from. Changed mid-test to prove a refetch really went back to
    /// the source rather than replaying a cached answer.
    var timedEventsPerFetch: Int = 3
    var allDayEventsPerFetch: Int = 2

    private(set) var timedFetchCount = 0
    private(set) var allDayFetchCount = 0

    var totalFetchCount: Int { timedFetchCount + allDayFetchCount }

    private let store = EKEventStore()

    func fetchEvents(for date: Date) -> [EKEvent] {
        timedFetchCount += 1
        return makeEvents(on: date, count: timedEventsPerFetch, allDay: false)
    }

    func fetchAllDayEvents(for date: Date) -> [EKEvent] {
        allDayFetchCount += 1
        return makeEvents(on: date, count: allDayEventsPerFetch, allDay: true)
    }

    private func makeEvents(on date: Date, count: Int, allDay: Bool) -> [EKEvent] {
        let dayStart = Calendar.current.startOfDay(for: date)
        return (0..<count).map { index in
            let event = EKEvent(eventStore: store)
            event.title = "\(allDay ? "All-day" : "Timed") \(index)"
            event.isAllDay = allDay
            // 09:00, 10:00, 11:00 … one hour each, so every timed one clips to a distinct segment.
            event.startDate = dayStart.addingTimeInterval(TimeInterval((9 + index) * 3600))
            event.endDate = dayStart.addingTimeInterval(TimeInterval((10 + index) * 3600))
            return event
        }
    }
}

/// **T-1570 — the Calendar Board queried `EKEventStore` twice per realized day column per render;
/// now it queries twice per *day*, once.**
///
/// Found by census while T-1499 was being closed, by reading the call sites of
/// `CalendarEventItem.timedSegments` — not by a timer, and **deliberately not a lag report**. The
/// owner reports the Calendar page as smooth and T-1501 named it the smooth control; nothing here
/// claims the owner will feel this. The defect stated honestly is a query count:
/// `CalendarPageBoardView.calendarDisplayItems(for:)` ran `fetchAllDayEvents(for:)` and
/// `fetchEvents(for:)` back to back with no memoisation, from inside `ForEach(0..<renderDays)` with
/// `renderDays == 420`, on a surface that re-renders on every task change, every store refresh and
/// every rail toggle.
///
/// **The seam was already there.** T-1499 introduced `CalendarEventDaySource` — four members, an
/// empty conformance on `CalendarManager` — so closing this took a support function that takes it,
/// and the page handing the board the `CalendarEventDayCache` the month grid and the timeline
/// viewport already had.
///
/// **Every count here has a control that must come out differently**, because the reading these
/// tests would otherwise be worth nothing against is the one where the source is never consulted at
/// all. The unauthorised control is not a hypothetical: it is character for character what the real
/// `CalendarManager` does on this host.
///
/// **Counts and relations only, never a duration.** CI runs Xcode 26 and this Mac 27
/// (T-1279/T-1296).
@MainActor
struct CalendarBoardEventFetchRateTests {

    /// 2026-06-11 and the days after it, fixed. The `TestAction` pins `TZ=UTC` (T-1116).
    private static func day(_ dayOfMonth: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: dayOfMonth))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// The days a realized `LazyHStack` of board columns holds at once — the ticket's own "six to
    /// ten". Nothing is tuned to it: `theQueryCountDoesNotFollowTheRenderCount` re-reads the same
    /// relation at four times the renders.
    private static func realizedColumns(_ count: Int = 8) -> [Date] {
        (0..<count).map { day(11 + $0) }
    }

    /// One column of the shipping board, through the call `calendarDisplayItems(for:)` now makes.
    private func column(
        _ source: CountingBoardEventDaySource,
        cache: CalendarEventDayCache,
        day: Date
    ) -> [CalendarBoardEventDisplayItem] {
        CalendarPageBoardDataSupport.calendarDisplayItems(
            for: day,
            calendarManager: source,
            cache: cache
        )
    }

    /// The expression `CalendarPageBoardView.calendarDisplayItems(for:)` **held before this
    /// ticket**, written out verbatim. Nothing here models the old decision; it *is* the old body,
    /// minus the `storeVersion` read that was only ever a SwiftUI subscription — so the before and
    /// after numbers come out of one source through two code paths that differ in exactly the thing
    /// that changed.
    private func columnUncached(
        _ source: CountingBoardEventDaySource,
        day: Date
    ) -> [CalendarBoardEventDisplayItem] {
        guard source.isAuthorized else { return [] }
        let calendar = Calendar.current
        let allDay = source.fetchAllDayEvents(for: day).map {
            CalendarBoardEventDisplayItem(allDay: $0, date: day, calendar: calendar)
        }
        let timed = CalendarEventItem
            .timedSegments(from: source.fetchEvents(for: day), for: day, calendar: calendar)
            .map(CalendarBoardEventDisplayItem.init(timed:))
        return (allDay + timed).sorted { $0.sortKey < $1.sortKey }
    }

    // MARK: - The denominator, first

    /// **What makes every number below mean anything.** One column through the shipping path
    /// against an authorised source fetches twice — once per half — and draws all five events; the
    /// identical column against the same source with `isAuthorized` false fetches **zero** times and
    /// draws nothing.
    ///
    /// The second reading is not a hypothetical control. It is exactly what the real
    /// `CalendarManager` does on this test host, and therefore exactly what a fetch-count assertion
    /// written against the shipping object would have read no matter what the code did. The two
    /// numbers must differ or nothing in this file is measuring the cache.
    @Test("The counted source is the one the board consults, and an unauthorised one reads zero")
    func theBoardsCountedSourceIsActuallyConsulted() {
        let source = CountingBoardEventDaySource()
        let items = column(source, cache: CalendarEventDayCache(), day: Self.day(11))

        #expect(source.timedFetchCount == 1,
                "the authorised source was asked for timed events \(source.timedFetchCount) times, not once")
        #expect(source.allDayFetchCount == 1,
                "the authorised source was asked for all-day events \(source.allDayFetchCount) times, not once")
        #expect(items.count == 5,
                "the authorised source drew \(items.count) items, not the 2 all-day + 3 timed it returned")
        #expect(items.filter(\.isAllDay).count == 2,
                "the all-day half drew \(items.filter(\.isAllDay).count) items")

        let unauthorised = CountingBoardEventDaySource()
        unauthorised.isAuthorized = false
        let nothing = column(unauthorised, cache: CalendarEventDayCache(), day: Self.day(11))

        #expect(unauthorised.totalFetchCount == 0,
                """
                the unauthorised source was fetched \(unauthorised.totalFetchCount) times. At any \
                number other than 0 the control is not the vacuous reading it is here to name.
                """)
        #expect(nothing.isEmpty)
        #expect(source.totalFetchCount != unauthorised.totalFetchCount,
                "both readings came out \(source.totalFetchCount); this file measures nothing")
        #expect(items.count != nothing.count,
                "both readings drew \(items.count) items; this file measures nothing")
    }

    // MARK: - The measurement the fix is answering

    /// **The before number.** Six renders of a board holding eight realized columns, through the
    /// pre-T-1570 expression, are **ninety-six** `EKEventStore` queries — two per column per render,
    /// which is the defect stated as a count.
    @Test("Uncached, one render of eight columns is sixteen store queries")
    func theUncachedBoardQueriedTwicePerColumnPerRender() {
        let source = CountingBoardEventDaySource()
        let days = Self.realizedColumns()

        for day in days { _ = columnUncached(source, day: day) }
        #expect(source.totalFetchCount == 16,
                "one render of 8 columns made \(source.totalFetchCount) queries, not 16")

        for _ in 0..<5 {
            for day in days { _ = columnUncached(source, day: day) }
        }
        #expect(source.totalFetchCount == 96,
                "6 renders of 8 columns made \(source.totalFetchCount) queries, not 96")
        #expect(source.timedFetchCount == 48)
        #expect(source.allDayFetchCount == 48)
    }

    /// **The after number, and the bound.** The same six renders of the same eight columns through
    /// the shipping path, holding the cache the way `CalendarPageView` holds it: **sixteen**
    /// queries, all of them on the first render, and every render still draws all five events per
    /// column — so the saving was not bought by drawing less.
    @Test("Cached, six renders of eight columns are sixteen store queries, all on the first")
    func theCachedBoardQueriesTwicePerDay() {
        let source = CountingBoardEventDaySource()
        let cache = CalendarEventDayCache()
        let days = Self.realizedColumns()

        var drawnPerRender: [Int] = []
        for _ in 0..<6 {
            var drawn = 0
            for day in days { drawn += column(source, cache: cache, day: day).count }
            drawnPerRender.append(drawn)
        }

        #expect(source.totalFetchCount == 16,
                "6 renders of 8 columns made \(source.totalFetchCount) queries, not 16")
        #expect(source.timedFetchCount == 8)
        #expect(source.allDayFetchCount == 8)
        #expect(drawnPerRender == Array(repeating: 40, count: 6),
                "the renders drew \(drawnPerRender); a cache that drops events is not a cache")
        #expect(source.totalFetchCount < drawnPerRender.reduce(0, +))
    }

    /// The difference between a bound and a coincidence: four times the renders is four times the
    /// old number and leaves the new one where it was. Nothing about the fix is tuned to six
    /// renders or to eight columns.
    @Test("The board's query count follows the days it draws, not the times it renders")
    func theBoardsQueryCountDoesNotFollowTheRenderCount() {
        let days = Self.realizedColumns()

        let coarseUncached = CountingBoardEventDaySource()
        for _ in 0..<6 { for day in days { _ = columnUncached(coarseUncached, day: day) } }
        let fineUncached = CountingBoardEventDaySource()
        for _ in 0..<24 { for day in days { _ = columnUncached(fineUncached, day: day) } }

        #expect(coarseUncached.totalFetchCount == 96)
        #expect(fineUncached.totalFetchCount == 384,
                "24 renders uncached made \(fineUncached.totalFetchCount) queries")

        let coarse = CountingBoardEventDaySource()
        let coarseCache = CalendarEventDayCache()
        for _ in 0..<6 { for day in days { _ = column(coarse, cache: coarseCache, day: day) } }
        let fine = CountingBoardEventDaySource()
        let fineCache = CalendarEventDayCache()
        for _ in 0..<24 { for day in days { _ = column(fine, cache: fineCache, day: day) } }

        #expect(coarse.totalFetchCount == fine.totalFetchCount,
                "6 renders cost \(coarse.totalFetchCount) and 24 cost \(fine.totalFetchCount)")
        #expect(fine.totalFetchCount == 16)
        #expect(fineUncached.totalFetchCount > fine.totalFetchCount,
                "the two branches read the same number; one of them is not the branch it claims")
    }

    /// Scrolling the board is what adds queries, and it adds exactly two per newly realized day —
    /// the relation the fix actually makes. Scrolling *back* over days already drawn adds none,
    /// which is the half a per-render memo could not give.
    @Test("A newly scrolled-in column costs two queries; scrolling back costs none")
    func anotherColumnIsAnotherTwoQueries() {
        let source = CountingBoardEventDaySource()
        let cache = CalendarEventDayCache()
        let first = Self.realizedColumns()

        for day in first { _ = column(source, cache: cache, day: day) }
        #expect(source.totalFetchCount == 16)

        let scrolledIn = Self.day(19)
        let fresh = column(source, cache: cache, day: scrolledIn)
        #expect(source.totalFetchCount == 18,
                "one new column cost \(source.totalFetchCount - 16) queries, not 2")
        #expect(fresh.map(\.dateKey) == Array(repeating: "2026-06-19", count: 5),
                "the new column drew \(fresh.map(\.dateKey))")

        for day in first { _ = column(source, cache: cache, day: day) }
        _ = column(source, cache: cache, day: scrolledIn)
        #expect(source.totalFetchCount == 18,
                "scrolling back over drawn days cost \(source.totalFetchCount - 18) further queries")
    }

    // MARK: - What the cache must never swallow

    /// A store change refetches **both halves**, and the refetch is a real one: the source is told
    /// to answer with different numbers, and the column after the bump draws them. Without that
    /// second half the count alone could not tell a refetch from a replayed answer.
    ///
    /// This is what keeps the board's `let _ = calendarManager.storeVersion` load bearing — it is
    /// both the SwiftUI subscription and the cache's invalidation.
    @Test("A store change refetches both halves, and the refetched answer is the new one")
    func aStoreChangeIsNotServedToTheBoardFromTheCache() {
        let source = CountingBoardEventDaySource()
        let cache = CalendarEventDayCache()
        let day = Self.day(11)

        for _ in 0..<5 { _ = column(source, cache: cache, day: day) }
        #expect(source.totalFetchCount == 2)

        source.timedEventsPerFetch = 4
        source.allDayEventsPerFetch = 3
        let stale = column(source, cache: cache, day: day)
        #expect(source.totalFetchCount == 2,
                "the cache went back to the store without the store changing")
        #expect(stale.count == 5, "the control: with no bump the answer is still the cached one")
        #expect(stale.filter(\.isAllDay).count == 2)

        source.storeVersion += 1
        let refreshed = column(source, cache: cache, day: day)

        #expect(source.totalFetchCount == 4,
                "a store change made \(source.totalFetchCount) total queries, not 4")
        #expect(source.timedFetchCount == 2)
        #expect(source.allDayFetchCount == 2)
        #expect(refreshed.count == 7,
                "the refetch drew \(refreshed.count) items, not 4 timed + 3 all-day; it replayed the cached answer")
        #expect(refreshed.count != stale.count,
                "the answer did not move across the bump, so the count alone proves nothing")
        #expect(refreshed.filter(\.isAllDay).count == 3,
                "the all-day half replayed its cached answer through the bump")
    }

    /// A different day is a different key, in both halves. The board draws 420 of them and the
    /// column identity is the whole of what distinguishes one from the next; a cache keyed on
    /// nothing would pin one day's events on every column.
    @Test("Each day column is its own key in both halves of the cache")
    func eachBoardColumnIsItsOwnCacheKey() {
        let source = CountingBoardEventDaySource()
        let cache = CalendarEventDayCache()

        for _ in 0..<4 { _ = column(source, cache: cache, day: Self.day(11)) }
        #expect(source.totalFetchCount == 2)

        let tomorrow = column(source, cache: cache, day: Self.day(12))
        #expect(source.totalFetchCount == 4,
                "two days cost \(source.totalFetchCount) queries, not 4")
        #expect(Set(tomorrow.map(\.dateKey)) == ["2026-06-12"],
                "the second day drew \(Set(tomorrow.map(\.dateKey)))")

        // …and it did not evict the first, so alternating days is still four queries and not eight.
        _ = column(source, cache: cache, day: Self.day(11))
        _ = column(source, cache: cache, day: Self.day(12))
        #expect(source.totalFetchCount == 4,
                "alternating two days cost \(source.totalFetchCount) queries")
    }

    // MARK: - No presentation on the calendar page may lose the cache again

    /// Both halves, because this defect was a *missing* indirection and a missing indirection leaves
    /// no trace. The board's route through the cache is pinned here, and so is the fact that the
    /// page owns one cache and hands the same one to all three of its presentations — a board given
    /// a fresh cache per render would satisfy the first assertion and memoise nothing.
    @Test("The board reads its events through the page's day cache")
    func theBoardReadsThroughTheDayCache() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let board = try read("Cadence/macOS/Views/CalendarPageBoardSupportViews.swift")
        #expect(board.isEmpty == false, "the reader read nothing, so nothing below is a reading")
        #expect(board.contains("cache.timedEvents("),
                "the board no longer reads timed events through the day cache")
        #expect(board.contains("cache.allDayEvents("),
                "the board no longer reads all-day events through the day cache")
        #expect(board.contains("calendarManager.fetchEvents(") == false,
                "the board queries the store for timed events directly again")
        #expect(board.contains("calendarManager.fetchAllDayEvents(") == false,
                "the board queries the store for all-day events directly again")
        #expect(board.contains("calendarManager.storeVersion"),
                "the subscription that is also the cache's invalidation is gone")
        #expect(board.contains("let eventCache: CalendarEventDayCache"),
                "the board makes its own cache instead of being handed the page's")

        let page = try read("Cadence/macOS/Views/CalendarPageView.swift")
        #expect(page.contains("@State private var calendarEventDayCache = CalendarEventDayCache()"),
                "the page no longer owns the cache its presentations share")
        #expect(page.contains("eventCache: calendarEventDayCache"),
                "the page no longer hands its cache down")
        // One cache, not one per presentation: the board, the month grid and the timeline viewport
        // are handed the same object, which is why switching presentations reuses warm days.
        #expect(page.components(separatedBy: "CalendarEventDayCache()").count - 1 == 1,
                "the page builds more than one day cache")
    }
}
#endif

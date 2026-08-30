import Foundation
import Testing

@testable import Cadence

/// `CadenceCalendarDateMemory` — the calendar's remembered anchor and selection.
///
/// The point of the type is that these two values are storage and not observed state (T-152: an
/// `@AppStorage` write on every column of a horizontal fling cost a dropped frame each). What is
/// pinnable here is everything that has to survive that move: the key names, the normalisation, the
/// round trip, and the no-op write that keeps a fling from touching defaults at all.
@Suite("Calendar date memory")
struct CalendarDateMemoryTests {

    /// The device's own calendar, deliberately. `DateFormatters.ymd` formats in the device time
    /// zone, so a fixture calendar pinned to UTC disagrees with it by a day either side of
    /// midnight — and the type under test is exactly the round trip between the two.
    private let calendar = Calendar.current

    private func date(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key))
    }

    /// The suite name used to be a fresh `UUID()` per call, cleaned up by a
    /// `removePersistentDomain(forName: defaults.description)` that named no suite which has ever
    /// existed. Between them this file stranded a preference plist per test per run in the app's
    /// own container (T-516) — `removePersistentDomain` empties a domain and never deletes the
    /// file behind it. `withTemporaryDefaults` names the suite after the calling test, so the
    /// footprint is one file per test rather than one per test per run.

    /// A user's saved position lives behind these exact strings. Renaming one loses where they
    /// were, and nothing about the app would look broken afterwards.
    @Test
    func theDefaultsKeysAreTheOnesTheAppAlreadyShipped() {
        #expect(CadenceCalendarDateMemory.anchorKey == "ios.calendar.anchorDateKey")
        #expect(CadenceCalendarDateMemory.selectionKey == "ios.calendar.selectedDateKey")
    }

    @Test
    func aStoredDayIsNormalisedToTheStartOfItsDay() throws {
        let noon = try #require(calendar.date(bySettingHour: 13, minute: 45, second: 0, of: date("2026-08-19")))
        #expect(CadenceCalendarDateMemory.storageKey(for: noon, calendar: calendar) == "2026-08-19")
    }

    @Test
    func aDayRoundTripsThroughStorage() throws {
        for key in ["2026-01-01", "2026-08-19", "2026-12-31"] {
            let stored = CadenceCalendarDateMemory.storageKey(for: try date(key), calendar: calendar)
            let restored = CadenceCalendarDateMemory.date(fromStored: stored, calendar: calendar)
            #expect(restored == calendar.startOfDay(for: try date(key)))
        }
    }

    /// The `calendar` parameter is honoured, and this is the assertion that says so on **any**
    /// host. Pacific/Honolulu is UTC−10 and Pacific/Kiritimati is UTC+14, so midnight on the 19th
    /// in one and midnight on the 20th in the other are **the same instant** — 2026-08-19T10:00Z.
    /// An implementation that snaps in the caller's calendar and then spells the result in the
    /// device's own time zone therefore returns the same key for both, whatever that device's zone
    /// is, and cannot satisfy the two expectations below at once.
    ///
    /// Every call site passes `Calendar.current` today, so this pins an API promise rather than a
    /// shipping bug — but the promise is the reason the parameter is there (T-302).
    @Test
    func theStoredKeyNamesTheDayTheGivenCalendarIsOn() throws {
        let honolulu = try fixedZoneCalendar("Pacific/Honolulu")
        let kiritimati = try fixedZoneCalendar("Pacific/Kiritimati")
        // 2026-08-19 12:00 in Honolulu; 2026-08-20 12:00 in Kiritimati. One instant, two days.
        let instant = try #require(
            utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 22))
        )

        #expect(CadenceCalendarDateMemory.storageKey(for: instant, calendar: honolulu) == "2026-08-19")
        #expect(CadenceCalendarDateMemory.storageKey(for: instant, calendar: kiritimati) == "2026-08-20")
        // The premise, stated so it cannot rot: those two midnights really are one instant.
        let honoluluMidnight = try startOfDay("2026-08-19", in: honolulu)
        let kiritimatiMidnight = try startOfDay("2026-08-20", in: kiritimati)
        #expect(honoluluMidnight == kiritimatiMidnight)
    }

    /// The parse side of the same promise. A key read back in a calendar has to land on midnight
    /// **in that calendar's zone**, or the round trip through this type loses a day for any device
    /// whose zone straddles the stored day's midnight.
    @Test
    func aStoredKeyIsReadBackAtMidnightInTheGivenCalendarsZone() throws {
        let honolulu = try fixedZoneCalendar("Pacific/Honolulu")
        let kiritimati = try fixedZoneCalendar("Pacific/Kiritimati")

        let honoluluMidnight = try startOfDay("2026-08-19", in: honolulu)
        let kiritimatiMidnight = try startOfDay("2026-08-20", in: kiritimati)

        #expect(CadenceCalendarDateMemory.date(fromStored: "2026-08-19", calendar: honolulu) == honoluluMidnight)
        #expect(CadenceCalendarDateMemory.date(fromStored: "2026-08-20", calendar: kiritimati) == kiritimatiMidnight)
    }

    /// A key naming a month that does not exist is not a rolled-over date, it is nothing
    /// remembered. The calendar-aware parse is component arithmetic and `month: 13` rolls into the
    /// next January on its own, so the validation has to happen before it.
    @Test
    func anImpossibleStoredKeyReadsBackAsNothingRemembered() throws {
        let honolulu = try fixedZoneCalendar("Pacific/Honolulu")

        #expect(CadenceCalendarDateMemory.date(fromStored: "2026-13-01", calendar: honolulu) == nil)
        #expect(CadenceCalendarDateMemory.date(fromStored: "2026-02-30", calendar: honolulu) == nil)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// A Gregorian calendar in a named zone that has never observed daylight saving, so the
    /// offsets quoted above hold for every date in these tests.
    private func fixedZoneCalendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private func startOfDay(_ key: String, in calendar: Calendar) throws -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(
            year: parts.first,
            month: parts.dropFirst().first,
            day: parts.dropFirst(2).first
        )
        return try #require(calendar.date(from: components))
    }

    /// "Nothing remembered" has three spellings and all three have to mean the same thing, because
    /// the caller's fallback is the real today and its alternative is landing on a date it invented.
    @Test
    func nothingRememberedReadsBackAsNil() {
        #expect(CadenceCalendarDateMemory.date(fromStored: nil, calendar: calendar) == nil)
        #expect(CadenceCalendarDateMemory.date(fromStored: "", calendar: calendar) == nil)
        #expect(CadenceCalendarDateMemory.date(fromStored: "not-a-date", calendar: calendar) == nil)
    }

    /// The write that a fling does not do. A scroll recrosses the same boundary constantly — the
    /// settle oscillates over it and the rubber band at either end reports the same day again — so
    /// the unchanged case is the common one, not the edge one.
    @Test
    func rewritingTheSameDayIsNotAWrite() throws {
        let day = try date("2026-08-19")
        #expect(CadenceCalendarDateMemory.valueToStore(for: day, stored: "2026-08-19", calendar: calendar) == nil)
        #expect(CadenceCalendarDateMemory.valueToStore(for: day, stored: nil, calendar: calendar) == "2026-08-19")
        #expect(CadenceCalendarDateMemory.valueToStore(for: day, stored: "", calendar: calendar) == "2026-08-19")
        #expect(
            CadenceCalendarDateMemory.valueToStore(for: day, stored: "2026-08-18", calendar: calendar)
                == "2026-08-19"
        )
    }

    @Test
    func theAnchorAndTheSelectionAreStoredSeparately() throws {
        try withTemporaryDefaults("CadenceTests.calendarDateMemory") { defaults in
            let memory = CadenceCalendarDateMemory(defaults: defaults)
            // Hoisted out of the `#expect`s below: a `try` inside a macro argument is checked in
            // the expansion buffer, which does not inherit a *closure*'s inferred `throws`.
            let anchor = try date("2026-08-19")
            let selection = try date("2026-09-02")

            #expect(memory.anchorDate(calendar: calendar) == nil)
            #expect(memory.selectedDate(calendar: calendar) == nil)

            memory.setAnchorDate(anchor, calendar: calendar)
            memory.setSelectedDate(selection, calendar: calendar)

            #expect(memory.anchorDate(calendar: calendar) == calendar.startOfDay(for: anchor))
            #expect(memory.selectedDate(calendar: calendar) == calendar.startOfDay(for: selection))
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-08-19")
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-09-02")
        }
    }

    /// A position written by the shipped `@AppStorage` build has to still be there after the move.
    /// The keys and the `yyyy-MM-dd` spelling are unchanged, so it is; this is what says so.
    @Test
    func aPositionWrittenByTheOldAppStorageBuildIsStillRestored() throws {
        try withTemporaryDefaults("CadenceTests.calendarDateMemory") { defaults in
            defaults.set("2026-03-04", forKey: "ios.calendar.anchorDateKey")
            defaults.set("2026-03-06", forKey: "ios.calendar.selectedDateKey")

            let anchor = try date("2026-03-04")
            let selection = try date("2026-03-06")
            let memory = CadenceCalendarDateMemory(defaults: defaults)
            #expect(memory.anchorDate(calendar: calendar) == calendar.startOfDay(for: anchor))
            #expect(memory.selectedDate(calendar: calendar) == calendar.startOfDay(for: selection))
        }
    }
}

/// **T-405.** The restore ordering `iOSCalendarView` used to spell inline.
///
/// [[T-369]] is entirely an ordering claim — *a dated calendar link outranks where the calendar was
/// left* — and it was verified on iOS by an simulator build and nothing else, because `CadenceTests`
/// cannot see `Cadence/iOS/`. `CadenceCalendarDateMemory.restoredPosition` is that decision lifted
/// out of the view, so it can be called here; the view is a thin caller and is pinned as one below.
@Suite("Calendar restore ordering")
struct CalendarRestoredPositionTests {

    private let calendar = Calendar.current

    private func day(_ key: String) throws -> Date {
        calendar.startOfDay(for: try #require(DateFormatters.date(from: key, in: calendar)))
    }

    private func restored(
        fallback: String = "2026-08-29",
        selection: String? = nil,
        anchor: String? = nil,
        link: String? = nil
    ) throws -> CadenceCalendarRestoredPosition {
        CadenceCalendarDateMemory.restoredPosition(
            fallback: try day(fallback),
            storedSelection: selection,
            storedAnchor: anchor,
            deepLinkDateKey: link,
            calendar: calendar
        )
    }

    /// Nothing remembered and no link: the page's own default, both days.
    @Test func afreshInstallOpensOnTheCallersFallbackDay() throws {
        let position = try restored()
        #expect(position.selectedDate == (try day("2026-08-29")))
        #expect(position.anchorDate == position.selectedDate)
    }

    @Test func theRememberedPositionIsRestoredWhenNoLinkNamesADay() throws {
        let position = try restored(selection: "2026-03-06", anchor: "2026-03-02")
        #expect(position.selectedDate == (try day("2026-03-06")))
        #expect(position.anchorDate == (try day("2026-03-02")))
    }

    /// A remembered selection with no anchor beside it leads with the selected day rather than
    /// with the fallback — otherwise a restore would open the remembered day off-screen.
    @Test func arememberedSelectionWithNoAnchorLeadsWithItself() throws {
        let position = try restored(selection: "2026-03-06")
        #expect(position.anchorDate == (try day("2026-03-06")))
    }

    /// **The whole of T-369.** The link wins over the remembered position — and it is the case the
    /// iOS build could only compile-check.
    @Test func adatedLinkOutranksTheRememberedPosition() throws {
        let position = try restored(selection: "2026-03-06", anchor: "2026-03-02", link: "2026-07-04")
        #expect(position.selectedDate == (try day("2026-07-04")))
    }

    /// And it takes the anchor with it. Applying only the selection would open the linked day
    /// scrolled out of the grid's leading column, which is the same complaint T-369 started from.
    @Test func adatedLinkMovesTheAnchorAndNotOnlyTheSelection() throws {
        let position = try restored(selection: "2026-03-06", anchor: "2026-03-02", link: "2026-07-04")
        #expect(position.anchorDate == (try day("2026-07-04")))
        #expect(position.anchorDate == position.selectedDate)
    }

    /// The link wins from a fresh install too — there is nothing remembered for it to outrank, and
    /// falling back to today would be the pre-T-369 behaviour with extra steps.
    @Test func adatedLinkAlsoWinsWhenNothingIsRemembered() throws {
        let position = try restored(link: "2026-07-04")
        #expect(position.selectedDate == (try day("2026-07-04")))
        #expect(position.anchorDate == (try day("2026-07-04")))
    }

    /// A garbage link is not a day, so it outranks nothing. `DateComponents(month: 13)` *rolls
    /// over* rather than failing, which is why `date(fromStored:)` normalises first — a link
    /// reading `2026-13-01` must not silently mean January 2027.
    @Test func anunparseableLinkLeavesTheRememberedPositionAlone() throws {
        for junk in ["", "tomorrow", "2026-13-01", "26-03-06"] {
            let position = try restored(selection: "2026-03-06", anchor: "2026-03-02", link: junk)
            #expect(position.selectedDate == (try day("2026-03-06")), "\(junk) was read as a day")
            #expect(position.anchorDate == (try day("2026-03-02")), "\(junk) moved the anchor")
        }
    }

    /// `2026-3-6` is **not** in the list above, and finding that out is why this test exists.
    /// `DateFormatters.normalizedDateKey` parses with the `ymd` formatter, which is lenient about
    /// single-digit months and days, and then only insists on a four-digit *year* — so an
    /// unpadded key is a real day and normalises to the padded spelling. The first draft of the
    /// junk list assumed the opposite and went red on the anchor.
    ///
    /// It matters beyond the test: `CadenceDeepLink.calendarDateKey` hands this whatever the URL
    /// carried, so `cadence://calendar/2026-3-6` opens on 6 March rather than being ignored.
    @Test func anunpaddedLinkIsARealDayAndNotGarbage() throws {
        let position = try restored(selection: "2026-03-06", anchor: "2026-03-02", link: "2026-3-6")
        #expect(position.selectedDate == (try day("2026-03-06")))
        #expect(position.anchorDate == (try day("2026-03-06")), "the unpadded link did not move the anchor")
        #expect(DateFormatters.normalizedDateKey("2026-3-6") == "2026-03-06")
        #expect(DateFormatters.normalizedDateKey("26-03-06") == nil, "a two-digit year is still rejected")
    }

    /// Garbage in the *stored* keys falls back the same way, rather than landing on a day nobody
    /// picked. A downgrade or a hand-edited plist is where these come from.
    @Test func garbageInTheStoredKeysFallsBackRatherThanInventingADay() throws {
        let position = try restored(selection: "2026-13-01", anchor: "nonsense")
        #expect(position.selectedDate == (try day("2026-08-29")))
        #expect(position.anchorDate == (try day("2026-08-29")))
    }

    /// The raw accessors `restoredPosition` is fed from read the same two keys the parsed ones do.
    /// Without this the pure decision above could be pinned perfectly while the caller handed it
    /// the wrong strings.
    @Test func therawStoredAccessorsReadTheSameKeysTheParsedOnesDo() throws {
        try withTemporaryDefaults("CadenceTests.calendarRestoredPosition") { defaults in
            let memory = CadenceCalendarDateMemory(defaults: defaults)

            #expect(memory.storedSelectionKey == nil)
            #expect(memory.storedAnchorKey == nil)

            memory.setSelectedDate(try day("2026-03-06"), calendar: calendar)
            memory.setAnchorDate(try day("2026-03-02"), calendar: calendar)

            #expect(memory.storedSelectionKey == "2026-03-06")
            #expect(memory.storedAnchorKey == "2026-03-02")
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == memory.storedSelectionKey)
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == memory.storedAnchorKey)
        }
    }

    /// And the view is a thin caller of it. A source scan, because `Cadence/iOS/iOSCalendarView.swift`
    /// is behind `#if os(iOS)` and this target builds for macOS — so this is the half of T-405 that
    /// stays a scan, and the eight tests above are the half that is now behaviour.
    @Test func theIOSCalendarPageDefersTheOrderingRatherThanRespellingIt() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarView.swift")
        #expect(raw.count > 400, "iOSCalendarView.swift read as \(raw.count) characters")
        let page = CadenceSourceScan.strippingComments(raw)
        #expect(page != raw, "the comment stripper removed nothing")
        #expect(page.count == raw.count, "the stripper changed the length")
        #expect(page.contains("struct iOSCalendarView: View"), "the scan read the wrong file")

        let restore = try #require(
            CadenceSourceScan.functionBody(named: "restorePersistedCalendarDates", in: page),
            "iOSCalendarView has no restorePersistedCalendarDates()"
        )
        #expect(restore.contains("CadenceCalendarDateMemory.restoredPosition("),
                "the page still spells the restore ordering inline (T-405)")
        #expect(restore.contains("selectedDate = restored.selectedDate"))
        #expect(restore.contains("anchorDate = restored.anchorDate"))
        // The inline ordering, gone: no branch on the remembered days and no second applier call
        // left inside the restore for a later edit to reorder.
        #expect(CadenceSourceScan.matchCount(#"dateMemory\.selectedDate\("#, in: restore) == 0)
        #expect(CadenceSourceScan.matchCount(#"dateMemory\.anchorDate\("#, in: restore) == 0)
        #expect(CadenceSourceScan.matchCount(#"applyCalendarDeepLinkDate\(\)"#, in: restore) == 0)

        // The warm path — a link arriving while the page already stands — is still there, and reads
        // the same one definition of "the day this link names".
        #expect(page.contains("applyCalendarDeepLinkDate()"), "the warm deep-link path went away")
        let apply = try #require(
            CadenceSourceScan.functionBody(named: "applyCalendarDeepLinkDate", in: page),
            "iOSCalendarView has no applyCalendarDeepLinkDate()"
        )
        #expect(apply.contains("CadenceCalendarDateMemory.date("),
                "the warm path parses the link its own way (T-405)")
    }

    /// The scan's needles, and its reader. Without these the `== 0` assertions above hold of any
    /// text at all.
    @Test func therestoreScanNeedlesAreNotVacuous() {
        #expect(CadenceSourceScan.matchCount(#"dateMemory\.selectedDate\("#,
                                             in: "if let x = dateMemory.selectedDate(calendar: calendar) {") == 1)
        #expect(CadenceSourceScan.matchCount(#"dateMemory\.selectedDate\("#,
                                             in: "storedSelection: dateMemory.storedSelectionKey,") == 0)
        #expect(CadenceSourceScan.matchCount(#"applyCalendarDeepLinkDate\(\)"#,
                                             in: "applyCalendarDeepLinkDate()") == 1)
        #expect(CadenceSourceScan.matchCount(#"applyCalendarDeepLinkDate\(\)"#,
                                             in: "perform: applyCalendarDeepLinkDate") == 0)
    }
}

/// `CadenceCalendarDateMemoryWriter` — the coalescing half.
///
/// The whole of T-152 is that a horizontal fling used to write user defaults once per column
/// crossed and dropped a frame each time. These pin the two halves of "once per settle instead":
/// a run of positions collapses to one write of the *last* one, and nothing is lost when the settle
/// never comes.
@Suite("Calendar date memory writer")
struct CalendarDateMemoryWriterTests {

    /// Counts what actually reaches the store, because "how many writes" *is* the behaviour under
    /// test. Asserting only the final value passes just as happily when every one of forty columns
    /// wrote, which is the bug.
    private final class CountingDefaults: UserDefaults, @unchecked Sendable {
        private(set) var writes = 0

        override func set(_ value: Any?, forKey defaultName: String) {
            writes += 1
            super.set(value, forKey: defaultName)
        }
    }

    /// A stand-in for the settle wait that the test opens by hand.
    ///
    /// Replaces the wall clock, so "not written yet" and "written" are two states this test moves
    /// between rather than two instants it waits for. The previous shape slept 400ms against a 60ms
    /// quiet period, which is only sound if the writer's scheduled `Task` gets a thread inside those
    /// 400ms — under three parallel builds it did not, and the test failed after 43 seconds having
    /// found nothing wrong (T-176). A longer interval would only move that threshold.
    private actor SleepGate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func open() {
            isOpen = true
            waiter?.resume()
            waiter = nil
        }
    }

    /// The device's own calendar, deliberately. `DateFormatters.ymd` formats in the device time
    /// zone, so a fixture calendar pinned to UTC disagrees with it by a day either side of
    /// midnight — and the type under test is exactly the round trip between the two.
    private let calendar = Calendar.current

    private func date(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key))
    }

    /// Handed to `withTemporaryDefaults(_:test:opening:_:)` rather than called: choosing the suite
    /// name is the helper's job, and choosing it here is the whole of T-516. Each of the three
    /// tests below used to mint a `UUID()` and strand another plist in the app's container.
    private func countingDefaults(_ suite: String) -> CountingDefaults? {
        CountingDefaults(suiteName: suite)
    }

    @MainActor
    @Test
    func aRunOfPositionsCollapsesToOneWriteOfTheLastOne() async throws {
        try await withTemporaryDefaults(
            "CadenceTests.calendarDateMemoryWriter",
            opening: countingDefaults
        ) { defaults in
            let gate = SleepGate()
            let writer = CadenceCalendarDateMemoryWriter(
                memory: CadenceCalendarDateMemory(defaults: defaults),
                quietPeriod: .milliseconds(60),
                sleep: { _ in await gate.wait() }
            )

            // Thirty columns of fling. None of these may reach the store while the next is still coming.
            for day in 1...30 {
                writer.remember(
                    anchor: try date(String(format: "2026-09-%02d", day)),
                    selection: try date("2026-08-19"),
                    calendar: calendar
                )
            }
            #expect(defaults.writes == 0)

            await gate.open()
            await writer.awaitScheduledWrite()
            // Two: the anchor and the selection, once each.
            #expect(defaults.writes == 2)
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-09-30")
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-08-19")
        }
    }

    @MainActor
    @Test
    func flushWritesImmediatelyAndCancelsWhatWasPending() async throws {
        try await withTemporaryDefaults(
            "CadenceTests.calendarDateMemoryWriter",
            opening: countingDefaults
        ) { defaults in
            let gate = SleepGate()
            let writer = CadenceCalendarDateMemoryWriter(
                memory: CadenceCalendarDateMemory(defaults: defaults),
                quietPeriod: .milliseconds(60),
                sleep: { _ in await gate.wait() }
            )

            writer.remember(anchor: try date("2026-09-01"), selection: try date("2026-09-01"), calendar: calendar)
            writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)

            // The page going away must not wait out a quiet period it will never see the end of — this
            // reads the store well inside the 60ms one.
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-10-05")
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-10-06")

            // And the write it cancelled must not land afterwards and undo it. Opening the gate and
            // then awaiting that very task is what makes this an assertion rather than a hope: the
            // cancelled task has demonstrably run to completion before the store is read.
            await gate.open()
            await writer.awaitScheduledWrite()
            #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-10-05")
            #expect(defaults.writes == 2)
        }
    }

    /// Re-recording a position the store already holds is not a write. Settling oscillates across a
    /// column boundary, so this is the common case rather than the odd one.
    @MainActor
    @Test
    func rememberingWhereItAlreadyIsTouchesNothing() throws {
        try withTemporaryDefaults(
            "CadenceTests.calendarDateMemoryWriter",
            opening: countingDefaults
        ) { defaults in
            let writer = CadenceCalendarDateMemoryWriter(
                memory: CadenceCalendarDateMemory(defaults: defaults),
                quietPeriod: .milliseconds(10)
            )

            writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)
            #expect(defaults.writes == 2)

            writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)
            #expect(defaults.writes == 2)
        }
    }
}

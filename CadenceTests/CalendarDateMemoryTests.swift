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

    private func freshDefaults(_ name: String = UUID().uuidString) throws -> UserDefaults {
        try #require(UserDefaults(suiteName: name))
    }

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
        let defaults = try freshDefaults()
        let memory = CadenceCalendarDateMemory(defaults: defaults)

        #expect(memory.anchorDate(calendar: calendar) == nil)
        #expect(memory.selectedDate(calendar: calendar) == nil)

        memory.setAnchorDate(try date("2026-08-19"), calendar: calendar)
        memory.setSelectedDate(try date("2026-09-02"), calendar: calendar)

        #expect(memory.anchorDate(calendar: calendar) == calendar.startOfDay(for: try date("2026-08-19")))
        #expect(memory.selectedDate(calendar: calendar) == calendar.startOfDay(for: try date("2026-09-02")))
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-08-19")
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-09-02")

        defaults.removePersistentDomain(forName: defaults.description)
    }

    /// A position written by the shipped `@AppStorage` build has to still be there after the move.
    /// The keys and the `yyyy-MM-dd` spelling are unchanged, so it is; this is what says so.
    @Test
    func aPositionWrittenByTheOldAppStorageBuildIsStillRestored() throws {
        let suite = UUID().uuidString
        let defaults = try freshDefaults(suite)
        defaults.set("2026-03-04", forKey: "ios.calendar.anchorDateKey")
        defaults.set("2026-03-06", forKey: "ios.calendar.selectedDateKey")

        let memory = CadenceCalendarDateMemory(defaults: defaults)
        #expect(memory.anchorDate(calendar: calendar) == calendar.startOfDay(for: try date("2026-03-04")))
        #expect(memory.selectedDate(calendar: calendar) == calendar.startOfDay(for: try date("2026-03-06")))

        defaults.removePersistentDomain(forName: suite)
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

    /// The device's own calendar, deliberately. `DateFormatters.ymd` formats in the device time
    /// zone, so a fixture calendar pinned to UTC disagrees with it by a day either side of
    /// midnight — and the type under test is exactly the round trip between the two.
    private let calendar = Calendar.current

    private func date(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key))
    }

    private func countingDefaults(_ suite: String) throws -> CountingDefaults {
        try #require(CountingDefaults(suiteName: suite))
    }

    @MainActor
    @Test
    func aRunOfPositionsCollapsesToOneWriteOfTheLastOne() async throws {
        let suite = UUID().uuidString
        let defaults = try countingDefaults(suite)
        let writer = CadenceCalendarDateMemoryWriter(
            memory: CadenceCalendarDateMemory(defaults: defaults),
            quietPeriod: .milliseconds(60)
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

        try await Task.sleep(for: .milliseconds(400))
        // Two: the anchor and the selection, once each.
        #expect(defaults.writes == 2)
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-09-30")
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-08-19")

        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    @Test
    func flushWritesImmediatelyAndCancelsWhatWasPending() async throws {
        let suite = UUID().uuidString
        let defaults = try countingDefaults(suite)
        let writer = CadenceCalendarDateMemoryWriter(
            memory: CadenceCalendarDateMemory(defaults: defaults),
            quietPeriod: .milliseconds(60)
        )

        writer.remember(anchor: try date("2026-09-01"), selection: try date("2026-09-01"), calendar: calendar)
        writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)

        // The page going away must not wait out a quiet period it will never see the end of — this
        // reads the store well inside the 60ms one.
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-10-05")
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.selectionKey) == "2026-10-06")

        // And the write it cancelled must not land afterwards and undo it.
        try await Task.sleep(for: .milliseconds(400))
        #expect(defaults.string(forKey: CadenceCalendarDateMemory.anchorKey) == "2026-10-05")
        #expect(defaults.writes == 2)

        defaults.removePersistentDomain(forName: suite)
    }

    /// Re-recording a position the store already holds is not a write. Settling oscillates across a
    /// column boundary, so this is the common case rather than the odd one.
    @MainActor
    @Test
    func rememberingWhereItAlreadyIsTouchesNothing() throws {
        let suite = UUID().uuidString
        let defaults = try countingDefaults(suite)
        let writer = CadenceCalendarDateMemoryWriter(
            memory: CadenceCalendarDateMemory(defaults: defaults),
            quietPeriod: .milliseconds(10)
        )

        writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)
        #expect(defaults.writes == 2)

        writer.flush(anchor: try date("2026-10-05"), selection: try date("2026-10-06"), calendar: calendar)
        #expect(defaults.writes == 2)

        defaults.removePersistentDomain(forName: suite)
    }
}

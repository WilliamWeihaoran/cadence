import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1366 step two: which population is expensive, and the bound the answer left behind.**
///
/// [[T-1366]]'s first measurement took one fixture of 300 `AppTask` rows and reported what a
/// generation cost. That is a number, not an answer: it said the Calendar widget's fetch
/// materialised the whole table and Today's a filtered superset, and it did not say whether the
/// rows the fetch handed over and the derivation then threw away were where the time went. Until
/// that was separated, any optimisation was a guess, and this ticket's whole shape is that the
/// order is not negotiable.
///
/// So this sweeps three populations against each other, holding the other two still:
/// - **qualifying** — open work carrying at least one date. Every term in both widgets' derivation
///   reads only these, so this is the irreducible population.
/// - **settled ballast** — done/cancelled rows, carrying dates. Today's predicate drops them in the
///   store; Calendar's fetch used to have no predicate, so it materialised every one and
///   `openTasks` discarded them in memory.
/// - **undated ballast** — open rows carrying no date at all. Same story, second reason, and the
///   worse of the two: these survive `openTasks` and are then walked again by every day in the
///   strip.
///
/// **What it measured** (medians of 7, Apple M3 Pro / Mac15,6, 11 cores, 18 GB, macOS 27.0,
/// Xcode 27.0 (27A266a), disk-backed fixtures in a temporary directory — never the app group and
/// never the owner's store), with qualifying held at 120 and the ballast varied:
///
///     ballast          Today total    Calendar BEFORE (fetch/derive)   Calendar AFTER
///     none               8.49ms          9.98ms  (  4.25 /   3.84)        9.38ms
///     1,000 settled      8.17ms         42.54ms  ( 34.92 /   4.84)        9.37ms
///     5,000 settled     10.01ms        173.86ms  (156.43 /   9.17)        9.60ms
///     10,000 settled     9.79ms        337.37ms  (307.68 /  14.51)        9.90ms
///     1,000 undated      8.35ms         68.12ms  ( 37.42 /  28.70)        9.16ms
///     5,000 undated      8.88ms        303.02ms  (152.90 / 137.61)        9.71ms
///     10,000 undated     9.49ms        579.40ms  (309.68 / 261.25)       10.68ms
///
/// Today was flat across every one of those and its `rowsFetched` never left 120; Calendar grew by
/// two orders of magnitude on rows that could not appear in its answer, and the undated half grew
/// faster than the settled half because those survive `openTasks` and are then walked again by
/// every day in the strip. **That named the population, and the optimisation followed it and
/// nothing else**: Calendar fetches through `CadenceTodayWidgetSupport.datedOpenTaskFetchDescriptor()`,
/// and the last column is the same sweep afterwards — flat in the size of the table, 34x at 10,000
/// settled rows and 54x at 10,000 undated ones.
///
/// **The irreducible population was measured too and deliberately left alone.** With no ballast at
/// all, 10,000 qualifying rows cost Calendar 688.47ms before and 699.18ms after — unchanged, which
/// is the point: the predicate admits every one of them. 394ms of that is the derivation, which
/// filters the open population twice per drawn day, and that is [[T-1437]] and is not this ticket.
///
/// **The bound is a count, not a duration.** `rowsFetched` is already in the instrument; what is
/// asserted below is that neither widget's fetch materialises a row its answer cannot use, over a
/// store that demonstrably holds such rows. No test here asserts a time, for the
/// [[T-1279]]/[[T-1296]] reason.
@MainActor
@Suite(.serialized)
struct CadenceWidgetPopulationSweepTests {
    nonisolated static let repetitions = 7
    nonisolated static let baselineQualifying = 120

    /// **The cohorts, as two literals, because widening them is how the table above is
    /// reproduced.** Put `5_000` and `10_000` back into both arrays and rerun; that is the whole
    /// interface, and it is deliberately not an environment variable — measured 2026-09-27 against
    /// this repository, exporting one in the shell does not reach the `CadenceTests` host any more
    /// than it reaches the UI-test runner (`CadenceUITestEnvironment` has the same finding for the
    /// same reason), and the marker-file channel that one falls back to would put a file inside
    /// `~/Library/Containers/com.haoranwei.Cadence/Data/`, which is the one directory a test here
    /// may not reach for.
    ///
    /// They run small by default because what runs unconditionally is the **bound**, and a bound
    /// does not need a big store to hold: the ballast cohorts below already contain rows the
    /// fetch must not materialise, and one such row is as decisive as ten thousand.
    nonisolated static let ballastSizes = [1_000]
    nonisolated static let qualifyingSizes = [1_000]

    // MARK: - The bound

    /// **Neither widget's fetch materialises a row its answer cannot use.**
    ///
    /// This is the number [[T-1366]]'s optimisation is accountable to, and it is a count rather
    /// than a duration so it means the same thing on a different machine on a different day.
    /// Calendar's fetch carried no predicate, so before the change the second reading below was
    /// `1_120` where the qualifying population was `120` — the ballast, fetched in full, to be
    /// discarded in memory.
    ///
    /// The non-vacuity is the whole test: the same store, read through a bare
    /// `FetchDescriptor<AppTask>()`, really does hand back every ballast row. Without that leg a
    /// green run here would be equally consistent with a fixture that had no ballast in it.
    @Test func neitherWidgetsFetchMaterialisesARowItsAnswerCannotUse() throws {
        try withTemporaryDefaults("CadenceTests.widgetSweep") { defaults in
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)
            var lines: [String] = []

            func run(_ label: String, qualifying: Int, undated: Int, settled: Int) throws {
                let store = try SweepStore(qualifying: qualifying, undated: undated, settled: settled)
                defer { store.tearDown() }
                let readings = try measure(store: store, defaults: defaults)

                #expect(
                    readings.today.rows == qualifying,
                    "\(label): Today's fetch materialised \(readings.today.rows) rows for \(qualifying) qualifying"
                )
                #expect(
                    readings.calendar.rows == qualifying,
                    "\(label): Calendar's fetch materialised \(readings.calendar.rows) rows for \(qualifying) qualifying"
                )
                // Non-vacuity: the ballast is really in the store, and an unfiltered fetch really
                // would have carried it.
                let wholeTable = try store.wholeTableRowCount()
                #expect(wholeTable == store.totalRows)
                #expect(
                    wholeTable == qualifying + undated + settled,
                    "\(label): the fixture did not hold the ballast this cohort is about"
                )

                lines.append(
                    label.padding(toLength: 30, withPad: " ", startingAt: 0)
                    + " table=\(store.totalRows)"
                    + " | today \(readings.today.described)"
                    + " | calendar \(readings.calendar.described)"
                )
            }

            try run("ballast=none", qualifying: Self.baselineQualifying, undated: 0, settled: 0)
            for settled in Self.ballastSizes {
                try run("settled-ballast=\(settled)", qualifying: Self.baselineQualifying, undated: 0, settled: settled)
            }
            for undated in Self.ballastSizes {
                try run("undated-ballast=\(undated)", qualifying: Self.baselineQualifying, undated: undated, settled: 0)
            }
            for qualifying in Self.qualifyingSizes {
                try run("qualifying=\(qualifying)", qualifying: qualifying, undated: 0, settled: 0)
            }

            print("""
                T-1366 population sweep (median of \(Self.repetitions), disk-backed fixtures)
                  cores=\(ProcessInfo.processInfo.processorCount) \
                ram=\(ProcessInfo.processInfo.physicalMemory / 1_048_576)MB
                \(lines.joined(separator: "\n"))
                """)
        }
    }

    // MARK: - The equivalence oracle

    /// **The cheaper fetch draws the snapshot the whole-table fetch drew** — every field of it,
    /// over a store built to make the discarded rows as loud as they can be.
    ///
    /// The ballast here is not inert filler: the settled rows carry dates *inside the strip the
    /// widget draws*, and one of them is overdue, so a fetch that kept them and a derivation that
    /// forgot to filter them would produce visibly different day counts and a different overdue
    /// badge rather than the same numbers by luck. The undated rows are open, which is the half
    /// `openTasks` does **not** remove.
    ///
    /// Both legs run through the pure `snapshot(from:today:dayCount:)`, which is untouched, so what
    /// is compared is the fetch and only the fetch.
    @Test func theFilteredFetchDrawsTheSnapshotTheWholeTableFetchDrew() throws {
        let store = try SweepStore(qualifying: 60, undated: 40, settled: 50)
        defer { store.tearDown() }

        // The shipping path first, because **the day it resolved is the day the other two legs
        // are replayed against**. Re-deriving one here would read the ambient calendar and the
        // wall clock a second time — a zone dependency `CadenceTimeZoneIndependenceTests` refuses
        // outright, and a midnight straddle between two reads that would make this test flake once
        // a year rather than fail. `CadenceCalendarWidgetSnapshot.date` *is* that day.
        let produced = try CadenceCalendarWidgetSupport.snapshot(
            modelContext: ModelContext(try store.openReadOnlyContainer()),
            dayCount: 14
        )
        let today = produced.date

        let context = ModelContext(try store.openReadOnlyContainer())
        let everyRow = try context.fetch(FetchDescriptor<AppTask>())
        let filteredRows = try context.fetch(CadenceTodayWidgetSupport.datedOpenTaskFetchDescriptor())

        // The rows really are different sets, so the comparison below is about something.
        #expect(everyRow.count == store.totalRows)
        #expect(filteredRows.count == 60)
        #expect(filteredRows.count < everyRow.count)

        let fromWholeTable = CadenceCalendarWidgetSupport.snapshot(from: everyRow, today: today, dayCount: 14)
        let fromFiltered = CadenceCalendarWidgetSupport.snapshot(from: filteredRows, today: today, dayCount: 14)
        #expect(fromFiltered == fromWholeTable, "the filtered fetch changed the snapshot")
        #expect(produced == fromWholeTable)

        // Non-vacuity for all three: the snapshot has work in it, and the ballast would have been
        // visible had it leaked through — a day strip with counts, and an overdue badge.
        #expect(produced.state == .ready)
        #expect(produced.days.reduce(0) { $0 + $1.totalCount } > 0)
        #expect(produced.overdueCount > 0)
        #expect(produced.upcomingTitle != nil)
    }

    // MARK: - Measurement

    private nonisolated func measure(
        store: SweepStore,
        defaults: UserDefaults
    ) throws -> (today: Reading, calendar: Reading) {
        var today = Reading()
        var calendar = Reading()

        for _ in 0..<Self.repetitions {
            let todayProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.todayWidgetKind,
                userDefaults: defaults
            )
            let todayContainer = try store.openReadOnlyContainer()
            todayProbe.finished(.containerOpen)
            let todaySnapshot = try CadenceTodayWidgetSupport.snapshot(
                modelContext: ModelContext(todayContainer),
                todayKey: store.todayKey,
                limit: 3,
                probe: todayProbe
            )
            today.add(try #require(todayProbe.recordGeneration(
                outcome: todaySnapshot.state == .empty ? .empty : .ready,
                renderedCount: todaySnapshot.tasks.count,
                sourceSnapshotAt: todaySnapshot.date
            )))

            let calendarProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.calendarWidgetKind,
                userDefaults: defaults
            )
            let calendarContainer = try store.openReadOnlyContainer()
            calendarProbe.finished(.containerOpen)
            let calendarSnapshot = try CadenceCalendarWidgetSupport.snapshot(
                modelContext: ModelContext(calendarContainer),
                dayCount: 14,
                probe: calendarProbe
            )
            calendar.add(try #require(calendarProbe.recordGeneration(
                outcome: calendarSnapshot.state == .empty ? .empty : .ready,
                renderedCount: calendarSnapshot.days.count,
                sourceSnapshotAt: calendarSnapshot.date
            )))
        }
        return (today, calendar)
    }

    /// The medians of one cohort. **`rows` is read from the record rather than counted here**, so
    /// the number the assertions bound is the one the shipping instrument writes.
    struct Reading {
        private(set) var containerOpen: [TimeInterval] = []
        private(set) var fetch: [TimeInterval] = []
        private(set) var derive: [TimeInterval] = []
        private(set) var total: [TimeInterval] = []
        private(set) var rows: Int = -1
        private(set) var footprint: Int = 0

        mutating func add(_ record: CadenceWidgetGenerationRecord) {
            containerOpen.append(record.stageDurations[.containerOpen] ?? 0)
            fetch.append(record.stageDurations[.fetch] ?? 0)
            derive.append(record.stageDurations[.derive] ?? 0)
            total.append(record.totalDuration)
            rows = record.rowsFetched ?? rows
            footprint = max(footprint, record.footprintBytes ?? 0)
        }

        var described: String {
            "rows=\(rows) open=\(Self.ms(containerOpen)) fetch=\(Self.ms(fetch)) "
            + "derive=\(Self.ms(derive)) total=\(Self.ms(total)) "
            + "spread=[\(Self.ms([total.min() ?? 0]))..\(Self.ms([total.max() ?? 0]))] "
            + "rss=\(footprint / 1_048_576)MB"
        }

        private static func ms(_ samples: [TimeInterval]) -> String {
            guard !samples.isEmpty else { return "-" }
            let sorted = samples.sorted()
            return String(format: "%.2fms", sorted[sorted.count / 2] * 1_000)
        }
    }

    // MARK: - Fixtures

    /// A store on disk, built from three populations named separately so a sweep can hold two of
    /// them still. Disk rather than memory because a container open is one of the costs
    /// [[T-1329]] never paid for, and an in-memory store does not open one.
    struct SweepStore {
        let directory: URL
        let storeURL: URL
        let todayKey: String
        let totalRows: Int

        init(qualifying: Int, undated: Int, settled: Int) throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cadence-widget-sweep-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("fixture.store")
            let calendar = Calendar.current
            let now = Date()
            todayKey = DateFormatters.dateKey(from: now, calendar: calendar)
            totalRows = qualifying + undated + settled

            func key(dayOffset: Int) -> String {
                DateFormatters.dateKey(
                    from: calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now,
                    calendar: calendar
                )
            }
            // Dates spread over the strip the Calendar widget draws, plus a tail of overdue work,
            // so no cohort is a store where every date term short-circuits on the same key.
            let dateKeys = (-7...13).map(key(dayOffset:))

            let container = try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "CadenceWidgetSweepFixture",
                    schema: CadenceSchema.schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
            let context = ModelContext(container)

            for index in 0..<qualifying {
                let task = AppTask(title: "Qualifying \(index)")
                if index.isMultiple(of: 2) {
                    task.dueDate = dateKeys[index % dateKeys.count]
                } else {
                    task.scheduledDate = dateKeys[index % dateKeys.count]
                }
                context.insert(task)
            }
            for index in 0..<undated {
                context.insert(AppTask(title: "Undated \(index)"))
            }
            // Settled rows carry dates *inside the drawn strip*, including overdue ones, so a
            // fetch that kept them is visible in the day counts rather than harmless.
            for index in 0..<settled {
                let task = AppTask(title: "Settled \(index)")
                task.dueDate = dateKeys[index % dateKeys.count]
                task.scheduledDate = dateKeys[(index + 3) % dateKeys.count]
                task.status = index.isMultiple(of: 2) ? .done : .cancelled
                context.insert(task)
            }
            try context.save()
        }

        /// The same read-only, CloudKit-free open the four providers make, against the fixture.
        func openReadOnlyContainer() throws -> ModelContainer {
            try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none,
                storeURL: storeURL
            )
        }

        /// What a predicate-free fetch would have materialised — the pre-[[T-1366]] Calendar path,
        /// kept here as the non-vacuity leg rather than as a number written down twice.
        func wholeTableRowCount() throws -> Int {
            try ModelContext(openReadOnlyContainer()).fetchCount(FetchDescriptor<AppTask>())
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

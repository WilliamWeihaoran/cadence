import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-359: two devices can each create a `HabitCompletion` for one habit on one day.
///
/// Their `id`s differ, so both rows survive CloudKit merge, and `completionCountsByDate()` used to
/// **add** them — one real check-in satisfying a `targetCount` of 2, or a `.timesPerWeek` target
/// reached with half the check-ins it names.
///
/// **The collapse rule is `max`, not `sum`, and this suite is where that is said out loud.** Every
/// check-in the app writes goes through `CadenceHabitCompletionStore.toggle`, and it is binary: an
/// unchecked day gets exactly one row at the default `count` of 1, and a checked day's second tap
/// *deletes*. Nothing increments an existing row, so a second row for one habit-day is never a
/// second deliberate increment — it is the same check-in recorded twice. `sum` prices a fiction
/// (two increments the product cannot produce) at the cost of mis-scoring the real case; `max`
/// reads the duplicate as what it is, and leaves a genuine multi-count day alone because that day
/// lives in one row's `count`.
@MainActor
struct CadenceHabitCompletionDuplicateTests {

    // MARK: - Helpers

    private static func gregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    /// Writes a row the way a *device* does, not the way the app does: straight into the store,
    /// bypassing the shared toggle. That is the only way to reproduce the state CloudKit produces.
    @discardableResult
    private static func syncedRow(
        _ habit: Habit,
        on dateKey: String,
        count: Int = 1,
        createdAt: Date = Date(timeIntervalSince1970: 1_770_000_000),
        context: ModelContext
    ) -> HabitCompletion {
        let completion = HabitCompletion(date: dateKey, habit: habit)
        completion.count = count
        completion.createdAt = createdAt
        context.insert(completion)
        habit.completions = (habit.completions ?? []) + [completion]
        return completion
    }

    // MARK: - The collapse rule

    /// The decision, stated as an assertion: 1 + 1 is **1**, and 3 + 1 is **3**.
    @Test func twoRowsForOneHabitDayCollapseToTheLargestNotTheirSum() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Meditate")
        habit.frequencyType = .daily
        context.insert(habit)

        // Two devices, one check-in each, one day. Neither knows about the other's row.
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        // A day whose rows disagree about how much it was worth.
        Self.syncedRow(habit, on: "2026-03-10", count: 3, context: context)
        Self.syncedRow(habit, on: "2026-03-10", count: 1, context: context)
        try context.save()

        let counts = habit.completionCountsByDate()
        #expect(counts["2026-03-09"] == 1, "the duplicate was added rather than collapsed")
        #expect(counts["2026-03-10"] == 3, "the day reports something other than its largest row")
    }

    /// The defect itself. `targetCount = 2` means two check-ins in a day; two devices each
    /// recording one check-in is one check-in, not two.
    @Test func aTargetCountHabitIsNotSatisfiedByDuplicatesOfOneCheckIn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Self.gregorian()

        let habit = Habit(title: "Drink water 2x")
        habit.frequencyType = .daily
        habit.targetCount = 2
        context.insert(habit)

        // Mar 8, 9 and 10: one real check-in per day, recorded twice each.
        for dayOfMonth in 8...10 {
            let key = String(format: "2026-03-%02d", dayOfMonth)
            Self.syncedRow(habit, on: key, context: context)
            Self.syncedRow(habit, on: key, context: context)
        }
        try context.save()

        #expect(habit.completionCountsByDate()["2026-03-09"] == 1)
        // Mar 10 is "today" and is forgiven; Mar 9 is not, and it was never worth 2.
        #expect(
            habit.currentStreak(asOf: Self.day(2026, 3, 10, calendar: calendar), calendar: calendar) == 0,
            "a three-day streak was built out of duplicates of one check-in a day"
        )
    }

    /// The other half of the decision: `max` must not shrink a day that genuinely was worth more.
    /// A real multi-count day carries its quantity in one row's `count`, and `max` over one row is
    /// that row.
    @Test func aGenuineMultiCountDayStillReadsItsFullCount() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Self.gregorian()

        let habit = Habit(title: "Drink water 3x")
        habit.frequencyType = .daily
        habit.targetCount = 3
        context.insert(habit)

        Self.syncedRow(habit, on: "2026-03-08", count: 3, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: 3, context: context)
        Self.syncedRow(habit, on: "2026-03-10", count: 1, context: context)
        try context.save()

        let counts = habit.completionCountsByDate()
        #expect(counts["2026-03-08"] == 3)
        #expect(counts["2026-03-09"] == 3)
        #expect(counts["2026-03-10"] == 1)
        #expect(
            habit.currentStreak(asOf: Self.day(2026, 3, 10, calendar: calendar), calendar: calendar) == 2,
            "the collapse shrank a day that really was worth three"
        )
    }

    /// `.timesPerWeek` reads the same dictionary a week at a time, so the duplicate reached the
    /// weekly target too. 2026-03-02 is a Monday, so Mon/Tue/Wed are all inside one ISO week.
    @Test func aTimesPerWeekTargetIsNotReachedByDuplicatesOfOneCheckIn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Self.gregorian()

        let habit = Habit(title: "Run 3x per week")
        habit.frequencyType = .timesPerWeek
        habit.targetCount = 3
        context.insert(habit)

        for key in ["2026-03-02", "2026-03-03"] {
            Self.syncedRow(habit, on: key, context: context)
            Self.syncedRow(habit, on: key, context: context)
        }
        try context.save()

        // Two real runs out of three. `isDue` for `.timesPerWeek` asks whether the week still owes
        // check-ins, excluding the day being asked about; summing the four rows answered "no".
        #expect(
            habit.isDue(on: Self.day(2026, 3, 4, calendar: calendar), calendar: calendar),
            "the week read as satisfied on two runs recorded twice each"
        )
    }

    /// `Habit.completionCountsByDate()` and `HabitCompletion.collapsedCount(of:)` are two spellings
    /// of one rule. Pinned equal so a change to either is a red test rather than a drift.
    @Test func theDayCountAHabitReportsIsTheCollapsedCountOfItsRows() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Stretch")
        context.insert(habit)
        Self.syncedRow(habit, on: "2026-03-09", count: 2, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: 5, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: -4, context: context)
        Self.syncedRow(habit, on: "2026-03-10", count: 1, context: context)
        try context.save()

        let counts = habit.completionCountsByDate()
        for key in ["2026-03-09", "2026-03-10"] {
            let rows = (habit.completions ?? []).filter { $0.date == key }
            #expect(counts[key] == HabitCompletion.collapsedCount(of: rows), "the two rules disagree about \(key)")
        }
        #expect(counts["2026-03-09"] == 5, "a negative row was allowed to move the day's count")
    }

    // MARK: - The repair

    @Test func theRepairCollapsesADuplicatedHabitDayToOneRow() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Meditate")
        context.insert(habit)
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        Self.syncedRow(habit, on: "2026-03-10", context: context)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")

        #expect(report.duplicateHabitCompletionsRemoved == 1)
        #expect(report.changed, "the report does not report the removal it made")

        #expect((habit.completions ?? []).count == 2, "the deleted row is still on the relationship")
        #expect(habit.completionCountsByDate() == ["2026-03-09": 1, "2026-03-10": 1])

        // A second context on the same container: the repair saved, it did not merely mutate.
        let stored = try ModelContext(container).fetch(FetchDescriptor<HabitCompletion>())
        #expect(stored.count == 2)
        #expect(Set(stored.map(\.date)) == ["2026-03-09", "2026-03-10"])
    }

    /// The survivor carries the day's collapsed count, distinct days are untouched, and a second
    /// habit that happens to share the date is a different habit-day.
    @Test func theRepairKeepsTheLargestRowAndLeavesDistinctDaysAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Drink water 3x")
        habit.targetCount = 3
        let other = Habit(title: "Stretch")
        context.insert(habit)
        context.insert(other)

        Self.syncedRow(habit, on: "2026-03-09", count: 1, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: 3, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: 2, context: context)
        Self.syncedRow(habit, on: "2026-03-10", count: 1, context: context)
        Self.syncedRow(other, on: "2026-03-09", count: 1, context: context)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.duplicateHabitCompletionsRemoved == 2)

        let survivors = (habit.completions ?? []).filter { $0.date == "2026-03-09" }
        #expect(survivors.count == 1)
        #expect(survivors.first?.count == 3, "the survivor does not carry the day's collapsed count")
        #expect((habit.completions ?? []).count == 2)
        #expect((other.completions ?? []).count == 1, "another habit's day was collapsed into this one")
    }

    /// Repair runs on every device against its own copy of the same rows. If two devices chose
    /// different survivors they would each delete the other's keeper, so the ordering has to be
    /// total and independent of fetch order.
    @Test func theRepairSurvivorDoesNotDependOnFetchOrder() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Meditate")
        context.insert(habit)
        // Same count, same createdAt: only the id can break the tie.
        let rows = (0..<4).map { _ in Self.syncedRow(habit, on: "2026-03-09", context: context) }
        try context.save()

        let chosen = try #require(HabitCompletion.canonicalRow(among: rows))
        #expect(HabitCompletion.canonicalRow(among: rows.reversed())?.id == chosen.id)
        #expect(HabitCompletion.canonicalRow(among: rows.shuffled())?.id == chosen.id)
        #expect(chosen.id.uuidString == rows.map(\.id.uuidString).min())
        #expect(HabitCompletion.canonicalRow(among: [HabitCompletion]()) == nil)
    }

    // MARK: - The one writer

    @Test func theSharedToggleWritesOneRowAndClearsEveryRowForTheDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Meditate")
        context.insert(habit)
        try context.save()

        #expect(try CadenceHabitCompletionStore.toggle(habit, on: "2026-03-09", modelContext: context))
        #expect((habit.completions ?? []).count == 1, "a check-in wrote something other than one row")
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitCompletion>()).count == 1)

        #expect(try CadenceHabitCompletionStore.toggle(habit, on: "2026-03-09", modelContext: context) == false)
        #expect((habit.completions ?? []).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitCompletion>()).isEmpty)

        // A day another device has already duplicated: unchecking has to take every row, or the
        // habit still reads as done immediately after the user cleared it.
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        Self.syncedRow(habit, on: "2026-03-09", context: context)
        try context.save()

        #expect(try CadenceHabitCompletionStore.toggle(habit, on: "2026-03-09", modelContext: context) == false)
        #expect(habit.isDone(on: "2026-03-09") == false)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitCompletion>()).isEmpty)
    }

    // MARK: - Every call site goes through it

    /// The [[T-374]] half. Four files used to open-code this toggle, and the property that matters
    /// is not "the shared helper exists" but "nothing else writes a check-in" — which is a claim
    /// about files this target does not compile (`Cadence/iOS/` is behind `#if os(iOS)`), so it is
    /// a scan.
    @Test func onlyTheHabitCompletionStoreConstructsAHabitCompletion() throws {
        let root = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence")
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not enumerate \(root.path)"
        )

        var scanned: Set<String> = []
        var constructing: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let raw = try String(contentsOf: url, encoding: .utf8)
            scanned.insert(url.lastPathComponent)
            let stripped = CadenceSourceScan.strippingComments(raw)
            if CadenceSourceScan.matchCount(#"(?<![A-Za-z0-9_])HabitCompletion\("#, in: stripped) > 0 {
                constructing.insert(url.lastPathComponent)
            }
        }

        // Non-vacuity: an empty read, a wrong root, or an enumerator that never descended would
        // otherwise pass this test by finding nothing anywhere.
        #expect(scanned.count > 150, "the scan read only \(scanned.count) Swift files under Cadence/")
        for reached in [
            "Habit.swift",                          // Models/
            "CadenceHabitCompletionStore.swift",    // Services/
            "CadenceFocusPlanningSupport.swift",    // Shared/
            "HabitsView.swift",                     // macOS/Views/
            "iOSFeatureViews.swift",                // iOS/
            // T-359 named this as a fourth toggle site and it is not one:
            // `markHabitCompletion` writes the widget's optimistic override into `UserDefaults`
            // and never touches a row. Listed here so the scan is on record as having read it.
            "CadenceWidgetIntents.swift",
            "CadenceWidgetRefreshCenter.swift"
        ] {
            #expect(scanned.contains(reached), "the scan never reached \(reached)")
        }

        #expect(constructing == ["CadenceHabitCompletionStore.swift"])
    }

    /// The positive half: each surface that used to own a copy now names the shared store. Without
    /// this, deleting a habit toggle entirely would leave the test above green.
    @Test func everyHabitToggleCallSiteNamesTheSharedStore() throws {
        for (path, function) in [
            ("Cadence/macOS/Views/HabitsView.swift", "toggleHabit"),
            ("Cadence/iOS/iOSFeatureViews.swift", "toggle"),
            ("Cadence/Services/CadenceWidgetIntents.swift", "toggleHabitCompletionResult")
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "the comment stripper removed nothing from \(path)")
            #expect(stripped.count == raw.count, "the stripper changed the length of \(path)")

            let body = try #require(
                CadenceSourceScan.functionBody(named: function, in: stripped),
                "could not find \(function)() in \(path)"
            )
            #expect(
                body.contains("CadenceHabitCompletionStore.toggle("),
                "\(function)() in \(path) no longer goes through the shared store"
            )
        }

        // The retired copy is gone rather than merely unused.
        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceFocusPlanningSupport.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"enum CadenceHabitSupport"#, in: shared) == 0)
    }

    /// The needle matches the constructor it hunts and misses the names it sits beside — otherwise
    /// the `== ["CadenceHabitCompletionStore.swift"]` above is a claim about a pattern that never
    /// matches anything.
    @Test func theHabitCompletionNeedleMatchesTheConstructorAndNotItsNeighbours() {
        let needle = #"(?<![A-Za-z0-9_])HabitCompletion\("#
        #expect(CadenceSourceScan.matchCount(needle, in: "HabitCompletion(date: key, habit: habit)") == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: "let c = HabitCompletion(date: k)") == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: "markHabitCompletion(id, isDoneToday: true)") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "recentHabitCompletionStates()") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "HabitCompletionState(timestamp: t)") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "FetchDescriptor<HabitCompletion>()") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "deleteAll(HabitCompletion.self, in: c)") == 0)
    }

    // MARK: - T-391, the split day, and why nothing repairs it

    /// **The premise, checked mechanically rather than remembered.** `max` only reads a day lower
    /// than `sum` would when that day's quantity was *split* across rows — 2 + 1 for a target of
    /// 3. Nothing in the app can produce that split, and this is the assertion that says so: the
    /// initializer has no `count` parameter, so every construction gets the model default of `1`,
    /// and the only assignment to a row's `count` anywhere under `Cadence/` is the one in
    /// `CadenceHabitCompletionStore.collapseDuplicates`, which writes `collapsedCount` — a `max`
    /// over rows that are all already `1`, so it cannot raise anything either.
    ///
    /// If this test goes red, T-391 has stopped being hypothetical and the decision below has to
    /// be revisited.
    @Test func nothingUnderCadenceEverWritesAHabitDayQuantityAboveOne() throws {
        let model = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Models/HabitCompletion.swift")
        )
        #expect(model.count > 400, "HabitCompletion.swift read as \(model.count) characters")
        #expect(CadenceSourceScan.matchCount(#"init\("#, in: model) == 1, "a second initializer appeared")
        #expect(CadenceSourceScan.matchCount(#"init\(date: String, habit: Habit\? = nil\)"#, in: model) == 1)
        #expect(CadenceSourceScan.matchCount(#"count: Int"#, in: model) == 1, "count is a stored property and not also a parameter")
        #expect(HabitCompletion(date: "2026-03-09").count == 1, "the model default is no longer 1")

        let root = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence")
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not enumerate \(root.path)"
        )

        var scanned: Set<String> = []
        var assigning: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let raw = try String(contentsOf: url, encoding: .utf8)
            scanned.insert(url.lastPathComponent)
            let stripped = CadenceSourceScan.strippingComments(raw)
            if CadenceSourceScan.matchCount(Self.countAssignmentNeedle, in: stripped) > 0 {
                assigning.insert(url.lastPathComponent)
            }
        }

        // Non-vacuity: the same shape the constructor scan above uses.
        #expect(scanned.count > 150, "the scan read only \(scanned.count) Swift files under Cadence/")
        for reached in ["Habit.swift", "HabitCompletion.swift", "CadenceHabitCompletionStore.swift", "DataIntegrityRepairService.swift"] {
            #expect(scanned.contains(reached), "the scan never reached \(reached)")
        }

        #expect(assigning == ["CadenceHabitCompletionStore.swift"])
        let store = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceHabitCompletionStore.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(#"survivor\.count = collapsed"#, in: store) == 1,
            "the one write to a row's count is no longer the collapsed (max) value"
        )
    }

    /// The needle matches an assignment to some row's `count` and misses the two `self.count =`
    /// lines in view initializers it sits beside — otherwise the set comparison above is a claim
    /// about a pattern that never matches anything.
    @Test func theCountAssignmentNeedleMatchesRowWritesAndNotInitializerSelfAssignment() {
        let needle = Self.countAssignmentNeedle
        #expect(CadenceSourceScan.matchCount(needle, in: "survivor.count = collapsed") == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: "        completion.count = 3") == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: "self.count = count") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "if rows.count == 1 { return }") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "let n = habit.completions?.count ?? 0") == 0)
        #expect(CadenceSourceScan.matchCount(needle, in: "count: habits.count,") == 0)
    }

    /// **The limit, stated as behaviour: a split habit-day reads low, and startup repair makes
    /// that permanent.**
    ///
    /// The decision on [[T-391]] is to document rather than repair, and this is the documentation
    /// that executes. There is no rule that can fold `[2, 1]` back to 3 without also folding
    /// `[1, 1]` to 2, which is exactly the [[T-359]] bug — `HabitCompletion` carries no provenance
    /// that separates "one day's quantity written across two rows" from "one check-in synced
    /// twice", so a repair here would have to guess. The place that *does* know is an importer,
    /// which sees a whole archive's rows for a day at once.
    ///
    /// So this is the warning for whoever builds [[T-274]]'s archive import: **fold split rows
    /// into one row's `count` before inserting them.** `performStartupMaintenance` runs repair the
    /// instant the container opens, and the collapse deletes the smaller rows — so an import that
    /// writes a split day loses the remainder before anyone can look at it, and the day reads low
    /// forever rather than only until the next repair.
    @Test func aSplitHabitDayReadsLowAndTheStartupRepairMakesThatPermanent() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let habit = Habit(title: "Drink water 3x")
        habit.targetCount = 3
        context.insert(habit)
        // What an importer or a legacy store could hold and the app cannot write: one day's
        // quantity of 3, split across two rows.
        Self.syncedRow(habit, on: "2026-03-09", count: 2, context: context)
        Self.syncedRow(habit, on: "2026-03-09", count: 1, context: context)
        try context.save()

        let calendar = Self.gregorian()
        #expect(habit.completionCountsByDate()["2026-03-09"] == 2, "max, not the 3 sum would report")
        // The visible consequence: a target of 3 that the rows add up to is not credited.
        #expect(
            habit.currentStreak(asOf: Self.day(2026, 3, 9, calendar: calendar), calendar: calendar) == 0,
            "a split day was credited against targetCount"
        )

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.duplicateHabitCompletionsRemoved == 1)

        // The remainder is gone from the store, not merely ignored by the read.
        let stored = try ModelContext(container).fetch(FetchDescriptor<HabitCompletion>())
        #expect(stored.count == 1)
        #expect(stored.first?.count == 2, "repair kept the larger row and dropped the remainder")
        #expect(habit.completionCountsByDate()["2026-03-09"] == 2)
    }

    /// The needle for "something assigns a row's `count`", shared by the scan and its self-test.
    private static let countAssignmentNeedle = #"(?<![A-Za-z0-9_.])(?!self\b)[A-Za-z_][A-Za-z0-9_]*\.count\s*=(?!=)"#
}

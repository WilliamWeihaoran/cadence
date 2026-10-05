import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1366, the widget half: a generation that finished and one that could not now leave different
/// marks, and both of them leave numbers.**
///
/// Before this there was no durable duration, memory or last-success instrument anywhere on the
/// widget path. All four providers catch an open or fetch failure and return their
/// `unavailableSnapshot()`, which is the right thing to draw and says nothing afterwards — so a
/// widget that is successfully showing hours-old data and a refresh that was requested and arrived
/// late are the same observation from outside the process. `.after(date)` is the only thing the
/// providers recorded, and it is a *request* for a timeline opportunity rather than evidence one
/// was granted.
///
/// **Everything here runs against a disk-backed store in a temporary directory.** Never the app
/// group, never `~/Library/Containers/com.haoranwei.Cadence/Data`: the numbers below are about a
/// fixture, and the owner's 264-row store is not a fixture. Disk rather than memory because
/// container opening is one of the four costs [[T-1329]] did not pay for, and an in-memory store
/// does not open one.
@MainActor
struct CadenceWidgetCostInstrumentTests {

    // MARK: - Opt-in, and what silence means

    /// **The instrument writes nothing until someone asks for it, and a reader with nothing to read
    /// refuses rather than reporting zeroes.**
    ///
    /// The second half is the one with teeth. `.silent(.instrumentDisabled)` and a record of all
    /// zeroes are the same bytes to a careless reader, and a test that only checked "no crash"
    /// would be green against an instrument that had quietly stopped recording — which is the shape
    /// [[T-1161]] sat in for thirteen days.
    @Test func theLedgerIsSilentUntilItIsOptedInAndRecordsOnceItIs() throws {
        try withTemporaryDefaults("CadenceTests.widgetCost") { defaults in
            let kind = CadenceWidgetRefreshCenter.todayWidgetKind

            #expect(CadenceWidgetGenerationLedger.isEnabled(userDefaults: defaults) == false)
            let offProbe = probe(kind: kind, defaults: defaults)
            offProbe.finished(.containerOpen)
            offProbe.finished(.fetch, rows: 12)
            #expect(
                offProbe.recordGeneration(outcome: .ready, renderedCount: 3, sourceSnapshotAt: Date()) == nil,
                "a probe wrote a record while the instrument was off"
            )
            #expect(
                CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).silence == .instrumentDisabled
            )

            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)
            #expect(
                CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).silence == .nothingRecorded,
                "the instrument is on and has recorded nothing, which is a third answer and not a zeroed record"
            )

            let onProbe = probe(kind: kind, defaults: defaults)
            onProbe.finished(.containerOpen)
            onProbe.finished(.fetch, rows: 12)
            onProbe.finished(.derive)
            let written = try #require(
                onProbe.recordGeneration(outcome: .ready, renderedCount: 3, sourceSnapshotAt: Date(timeIntervalSince1970: 5_000)),
                "the probe recorded nothing with the instrument on"
            )

            // Non-vacuity for the reader: it really can come back with something, so the two
            // silences above are the ledger's answer and not a reader that always says nothing.
            let read = try #require(
                CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).record,
                "the ledger refused to read back the record it had just written"
            )
            // Field-wise rather than `read == written`: a `Date` that has been through
            // `timeIntervalSince1970` and back is the same instant to within a rounding bit and not
            // necessarily the same `Double`, and pinning bit-equality of a timestamp would make
            // this a test about floating point.
            #expect(read.outcome == written.outcome)
            #expect(read.stageDurations == written.stageDurations)
            #expect(read.totalDuration == written.totalDuration)
            #expect(abs(read.generatedAt.timeIntervalSince(written.generatedAt)) < 0.001)
            #expect(read.rowsFetched == 12)
            #expect(read.renderedCount == 3)
            #expect(read.measuredStages == [.containerOpen, .fetch, .derive])
            #expect(read.sourceSnapshotAt?.timeIntervalSince1970 == 5_000)
        }
    }

    /// **"Nothing to draw" and "could not read the store" are stored in different slots.**
    ///
    /// This is the audit's silent pair, made separable. Both render the same chrome and both used
    /// to leave the same nothing behind; a last-success timestamp beside a last-refusal timestamp
    /// is what turns "the widget looks stale" into either "it was asked and refused" or "it was
    /// never asked".
    @Test func aRefusalIsKeptApartFromAResultWithNothingInIt() throws {
        try withTemporaryDefaults("CadenceTests.widgetCost") { defaults in
            let kind = CadenceWidgetRefreshCenter.calendarWidgetKind
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)

            let emptyProbe = probe(kind: kind, defaults: defaults)
            emptyProbe.finished(.containerOpen)
            emptyProbe.finished(.fetch, rows: 0)
            emptyProbe.finished(.derive)
            _ = emptyProbe.recordGeneration(
                outcome: .empty,
                renderedCount: 0,
                sourceSnapshotAt: Date(timeIntervalSince1970: 1_000)
            )

            let refusalProbe = probe(kind: kind, defaults: defaults)
            _ = refusalProbe.recordRefusal(CocoaError(.fileReadNoSuchFile))

            let success = try #require(CadenceWidgetGenerationLedger.lastSuccess(kind: kind, userDefaults: defaults).record)
            let refusal = try #require(CadenceWidgetGenerationLedger.lastRefusal(kind: kind, userDefaults: defaults).record)
            let latest = try #require(CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).record)

            #expect(success.outcome == .empty)
            #expect(success.refusalReason == nil)
            #expect(success.sourceSnapshotAt?.timeIntervalSince1970 == 1_000)
            #expect(refusal.outcome == .refused)
            #expect(refusal.sourceSnapshotAt == nil, "a refusal has no source snapshot to be stale from")
            let refusalReason = try #require(refusal.refusalReason)
            #expect(refusalReason.contains(CocoaError.errorDomain))
            #expect(latest.outcome == .refused, "the most recent generation is the refusal")

            // The other widget's slots are untouched: a refusal on one kind must not read as one
            // on another, which is what a single shared slot would have produced.
            #expect(
                CadenceWidgetGenerationLedger.lastRefusal(
                    kind: CadenceWidgetRefreshCenter.todayWidgetKind,
                    userDefaults: defaults
                ).silence == .nothingRecorded
            )
        }
    }

    /// **A successful generation that measured no stage is not a record.**
    ///
    /// The instrument refuses to write it, and the reader would refuse to believe it: an empty
    /// stage map decodes to nothing rather than to a generation that cost zero seconds. A *refusal*
    /// is allowed to have measured no stage — the container open can throw before the first mark —
    /// and must then carry the reason it refused, which is the only thing it has to say.
    @Test func anInstrumentThatMeasuredNothingRefusesToReportACleanSweep() throws {
        try withTemporaryDefaults("CadenceTests.widgetCost") { defaults in
            let kind = CadenceWidgetRefreshCenter.habitWidgetKind
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)

            let blind = probe(kind: kind, defaults: defaults)
            #expect(
                blind.recordGeneration(outcome: .ready, renderedCount: 4, sourceSnapshotAt: Date()) == nil,
                "a generation that timed no stage at all was written as a successful record"
            )
            #expect(CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).silence == .nothingRecorded)

            // The same probe, refusing before it ever marked a stage: that one is recorded.
            let refused = try #require(
                blind.recordRefusal(CocoaError(.fileReadCorruptFile)),
                "a container open that threw before the first mark left nothing behind"
            )
            #expect(refused.measuredStages.isEmpty)
            #expect(refused.refusalReason?.isEmpty == false)

            // And the storage side enforces the same rule, so a payload that has lost its stages
            // cannot come back as a zero-cost success.
            var ruined: [String: Any] = [
                "kind": kind,
                "outcome": CadenceWidgetGenerationOutcome.ready.rawValue,
                "stages": [String: Any](),
                "total": 0.25,
                "rendered": 2,
                "generatedAt": Date().timeIntervalSince1970,
            ]
            defaults.set(ruined, forKey: CadenceWidgetGenerationLedger.lastGenerationKeyPrefix + kind)
            #expect(
                CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).silence == .recordUnreadable
            )

            // Non-vacuity for that decode: the same payload *with* a stage in it reads back fine,
            // so the refusal above is the emptiness and not a reader that rejects everything.
            ruined["stages"] = [CadenceWidgetStage.fetch.rawValue: 0.25]
            defaults.set(ruined, forKey: CadenceWidgetGenerationLedger.lastGenerationKeyPrefix + kind)
            #expect(CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).record != nil)
        }
    }

    /// The refusal reason is built from an error's type, domain and code, so it **cannot** carry a
    /// task title, a note body or a file path even when the error it came from does.
    @Test func theRefusalReasonCannotCarryUserText() {
        let leaky = NSError(
            domain: "CadenceFixtureDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Could not read /Users/someone/Notes/Quarterly salary review.md"]
        )
        let reason = CadenceWidgetGenerationLedger.refusalReason(for: leaky)

        #expect(reason.contains("CadenceFixtureDomain"))
        #expect(reason.contains("42"))
        #expect(!reason.contains("salary"))
        #expect(!reason.contains("/Users/"))
        // Non-vacuity: the text really is in the error this was built from.
        #expect(leaky.localizedDescription.contains("salary"))
    }

    // MARK: - The measurement

    /// **Measured, on disk: both widgets now hand the store the same predicate, and neither one
    /// materialises the rest of the table.**
    ///
    /// The audit corrected the premise that Today fetches every task — it fetches a filtered
    /// superset — and noted that Calendar's fetch was the broad one. That was true when this test
    /// was written and it is the thing [[T-1366]]'s step-two sweep priced: holding the qualifying
    /// population still and adding rows the derivation cannot read, Calendar's generation grew with
    /// them and Today's did not. So Calendar fetches through
    /// `CadenceTodayWidgetSupport.datedOpenTaskFetchDescriptor()` now, and the assertion below
    /// moved with it: the number that used to be the whole table is the qualifying population.
    /// `CadenceWidgetPopulationSweepTests` holds the cohorts and the equivalence oracle.
    ///
    /// **No time threshold is asserted and none should be.** A duration here is a fact about this
    /// machine on this day; what is bounded is the *shape* — every stage measured, nothing claiming
    /// to have cost less than nothing, and the parts never summing past the whole.
    @Test func neitherWidgetsFetchMaterialisesMoreThanTheDatedOpenPopulation() throws {
        let fixture = try DiskFixture()
        defer { fixture.tearDown() }

        try withTemporaryDefaults("CadenceTests.widgetCost") { defaults in
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)

            let todayProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.todayWidgetKind,
                userDefaults: defaults
            )
            let todayContainer = try fixture.openReadOnlyContainer()
            todayProbe.finished(.containerOpen)
            let todaySnapshot = try CadenceTodayWidgetSupport.snapshot(
                modelContext: ModelContext(todayContainer),
                todayKey: fixture.todayKey,
                limit: 3,
                probe: todayProbe
            )
            let today = try #require(
                todayProbe.recordGeneration(
                    outcome: todaySnapshot.state == .empty ? .empty : .ready,
                    renderedCount: todaySnapshot.tasks.count,
                    sourceSnapshotAt: todaySnapshot.date
                ),
                "the Today probe recorded nothing"
            )

            let calendarProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.calendarWidgetKind,
                userDefaults: defaults
            )
            let calendarContainer = try fixture.openReadOnlyContainer()
            calendarProbe.finished(.containerOpen)
            let calendarSnapshot = try CadenceCalendarWidgetSupport.snapshot(
                modelContext: ModelContext(calendarContainer),
                dayCount: 14,
                probe: calendarProbe
            )
            let calendar = try #require(
                calendarProbe.recordGeneration(
                    outcome: calendarSnapshot.state == .empty ? .empty : .ready,
                    renderedCount: calendarSnapshot.days.count,
                    sourceSnapshotAt: calendarSnapshot.date
                ),
                "the Calendar probe recorded nothing"
            )

            // The counts, against the fixture's own arithmetic rather than a literal.
            let todayRows = try #require(today.rowsFetched, "the Today probe counted no rows at all")
            let calendarRows = try #require(calendar.rowsFetched, "the Calendar probe counted no rows at all")
            #expect(todayRows == DiskFixture.openDatedTaskCount)
            #expect(calendarRows == DiskFixture.openDatedTaskCount)
            #expect(todayRows > todaySnapshot.tasks.count)

            // Non-vacuity, and it is the whole point of the two numbers above: the fixture holds
            // 180 rows of the two kinds the predicate must drop, and the same store read through a
            // bare `FetchDescriptor<AppTask>()` really does hand back all 300 — so `120` is the
            // predicate doing work and not a store where every task happens to qualify.
            let wholeTable = try ModelContext(fixture.openReadOnlyContainer())
                .fetchCount(FetchDescriptor<AppTask>())
            #expect(wholeTable == DiskFixture.totalTaskCount)
            #expect(wholeTable > todayRows)
            #expect(DiskFixture.totalTaskCount >= 300)
            #expect(DiskFixture.settledTaskCount > 0)
            #expect(DiskFixture.openUndatedTaskCount > 0)
            #expect(DiskFixture.totalTaskCount > DiskFixture.openDatedTaskCount)

            // The shape of every duration, bounded rather than pinned.
            for record in [today, calendar] {
                #expect(record.measuredStages == [.containerOpen, .fetch, .derive], "\(record.kind)")
                #expect(record.totalDuration.isFinite && record.totalDuration >= 0, "\(record.kind)")
                #expect(
                    record.accountedDuration <= record.totalDuration + 0.000_001,
                    "\(record.kind) attributed \(record.accountedDuration)s of stages to a \(record.totalDuration)s generation"
                )
                #expect(record.footprintBytes.map { $0 > 0 } ?? true, "a footprint of zero is not a reading")
                #expect(record.renderedCount >= 0)
            }

            // The footprint reader is a Darwin `task_info` call, not a toolchain answer: a live
            // process has a physical footprint. If this ever fails it is the platform, which is
            // worth a red run, and the bound is deliberately loose.
            let footprint = try #require(
                CadenceProcessFootprint.currentBytes(),
                "the kernel would not report this process's footprint"
            )
            #expect(footprint > 1_000_000)

            print("""
                T-1366 widget measurement (disk-backed fixture, \(DiskFixture.totalTaskCount) AppTask rows, \
                \(DiskFixture.openDatedTaskCount) of them open and dated)
                  today:    rows=\(todayRows) rendered=\(today.renderedCount) \
                total=\(today.totalDuration)s stages=\(Self.described(today.stageDurations))
                  calendar: rows=\(calendarRows) rendered=\(calendar.renderedCount) \
                total=\(calendar.totalDuration)s stages=\(Self.described(calendar.stageDurations))
                  footprint=\(footprint) bytes
                """)
        }
    }

    /// **T-1403: all four widget kinds separate the store fetch from the in-memory derivation, and
    /// a caller that passes no probe still records absence rather than zero.**
    ///
    /// Habit and Milestone were instrumented at the provider only — their support types were
    /// outside [[T-1366]]'s file ownership — so their records carried a container open and a total
    /// and said nothing about the fanout that is the reason to look at them. Milestone's is the one
    /// that matters: `snapshot(from:now:limit:)` walks contributions and habit momentum through
    /// sub-goals, linked lists, tasks and habits for every goal in the pool, and that walk is now
    /// this record's `derive` stage.
    ///
    /// **The second half is the guard on the first.** `probe:` defaults to `nil`, and a record
    /// written without one must come back with `fetch` and `derive` *absent* from `measuredStages`
    /// and `rowsFetched == nil` — never `0`. That is the distinction `NoteMigrationReport.noteTableScanned`
    /// exists to make: a zero in an `Int` reads identically whether the number was measured or
    /// never taken. Both halves are in one test so neither can be satisfied by an instrument that
    /// had stopped recording, or by one that records a zero for everything.
    ///
    /// No duration is asserted, for the [[T-1279]]/[[T-1296]] reason. What is bounded is shape.
    @Test func habitAndMilestoneNowSplitFetchFromDeriveAndAbsentIsStillNotZero() throws {
        let fixture = try DiskFixture()
        defer { fixture.tearDown() }

        try withTemporaryDefaults("CadenceTests.widgetCost") { defaults in
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)

            let habitProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.habitWidgetKind,
                userDefaults: defaults
            )
            let habitContainer = try fixture.openReadOnlyContainer()
            habitProbe.finished(.containerOpen)
            let habitSnapshot = try CadenceHabitWidgetSupport.snapshot(
                modelContext: ModelContext(habitContainer),
                limit: 8,
                probe: habitProbe
            )
            let habit = try #require(
                habitProbe.recordGeneration(
                    outcome: habitSnapshot.state == .empty ? .empty : .ready,
                    renderedCount: habitSnapshot.habits.count,
                    sourceSnapshotAt: habitSnapshot.date
                ),
                "the Habit probe recorded nothing"
            )

            let milestoneProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.milestoneWidgetKind,
                userDefaults: defaults
            )
            let milestoneContainer = try fixture.openReadOnlyContainer()
            milestoneProbe.finished(.containerOpen)
            let milestoneSnapshot = try CadenceMilestoneWidgetSupport.snapshot(
                modelContext: ModelContext(milestoneContainer),
                limit: 5,
                probe: milestoneProbe
            )
            let milestone = try #require(
                milestoneProbe.recordGeneration(
                    outcome: milestoneSnapshot.state == .empty ? .empty : .ready,
                    renderedCount: milestoneSnapshot.visibleGoals.count,
                    sourceSnapshotAt: milestoneSnapshot.date
                ),
                "the Milestone probe recorded nothing"
            )

            for record in [habit, milestone] {
                #expect(
                    record.measuredStages == [.containerOpen, .fetch, .derive],
                    "\(record.kind) measured \(record.measuredStages.map(\.rawValue).sorted())"
                )
                #expect(record.totalDuration.isFinite && record.totalDuration >= 0, "\(record.kind)")
                #expect(
                    record.accountedDuration <= record.totalDuration + 0.000_001,
                    "\(record.kind) attributed \(record.accountedDuration)s of stages to a \(record.totalDuration)s generation"
                )
                #expect(record.stageDurations.values.allSatisfy { $0.isFinite && $0 >= 0 }, "\(record.kind)")
                #expect(record.footprintBytes.map { $0 > 0 } ?? true, "a footprint of zero is not a reading")
            }

            // The counts, against the fixture's own arithmetic. The row count is the whole table
            // each support type fetches, not the prefix its widget draws.
            #expect(try #require(habit.rowsFetched) == DiskFixture.habitCount)
            #expect(try #require(milestone.rowsFetched) == DiskFixture.goalCount)
            #expect(milestone.renderedCount < DiskFixture.goalCount, "the fixture's pool is not bigger than the list")
            #expect(habit.renderedCount <= DiskFixture.habitCount)

            // **Absent is not zero.** The same two support calls with no probe, recorded by a probe
            // that only closed the container open: the two stages are missing rather than zeroed,
            // and the row count is `nil` rather than `0` — over a fixture that demonstrably has
            // rows in it, so the `nil` is the instrument's silence and not the store's emptiness.
            let blindProbe = CadenceWidgetGenerationProbe(
                kind: CadenceWidgetRefreshCenter.habitWidgetKind,
                userDefaults: defaults
            )
            let blindContainer = try fixture.openReadOnlyContainer()
            blindProbe.finished(.containerOpen)
            let blindSnapshot = try CadenceHabitWidgetSupport.snapshot(
                modelContext: ModelContext(blindContainer),
                limit: 8
            )
            let blind = try #require(
                blindProbe.recordGeneration(
                    outcome: blindSnapshot.state == .empty ? .empty : .ready,
                    renderedCount: blindSnapshot.habits.count,
                    sourceSnapshotAt: blindSnapshot.date
                ),
                "the un-probed generation recorded nothing"
            )
            #expect(blind.measuredStages == [.containerOpen])
            #expect(blind.rowsFetched == nil, "an unmeasured fetch recorded a row count of zero")
            #expect(blind.stageDurations[.fetch] == nil)
            #expect(blind.stageDurations[.derive] == nil)
            // Non-vacuity for that `nil`: the same store, read through a probe, really does count
            // rows — so the absence above is the missing probe and not an empty table.
            #expect(DiskFixture.habitCount > 0)
            #expect(blindSnapshot.habits.count == habitSnapshot.habits.count)

            print("""
                T-1403 widget measurement (disk-backed fixture, \(DiskFixture.habitCount) Habit \
                + \(DiskFixture.goalCount) Goal rows)
                  habit:     rows=\(habit.rowsFetched as Int?) rendered=\(habit.renderedCount) \
                total=\(habit.totalDuration)s stages=\(Self.described(habit.stageDurations))
                  milestone: rows=\(milestone.rowsFetched as Int?) rendered=\(milestone.renderedCount) \
                total=\(milestone.totalDuration)s stages=\(Self.described(milestone.stageDurations))
                """)
        }
    }

    /// **The ledger keeps a slot for every kind the bundle ships *and* for the two it used to.**
    ///
    /// Until [[T-2078]] these were the same four, and this test said so. The bundle now ships two:
    /// `CadenceHabitCheckInWidget` and `CadenceMilestoneMomentumWidget` were retired with the
    /// habits and goals surfaces. `instrumentedKinds` was deliberately **not** cut to match, and
    /// the reason is the second half below rather than inertia — it is the list
    /// `clearStoredState` sweeps, so dropping the two retired kinds would strand whatever rows an
    /// *older build* of this app wrote under them in the app group, where the privacy reset could
    /// never reach them again. The ledger's list is "has ever written here"; the bundle's is
    /// "ships today".
    ///
    /// Both halves are read rather than written down twice: the shipping set comes out of
    /// `CadenceWidgetsBundle.swift`, so putting a widget back without a ledger slot fails here.
    @Test func theLedgerKeepsASlotForEveryWidgetKindTheBundleShipsAndEveryKindItRetired() throws {
        let bundle = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("CadenceWidgets/CadenceWidgetsBundle.swift")
        )

        // What the bundle body registers, which is what WidgetKit ships.
        #expect(bundle.contains("CadenceTodayTasksWidget()"))
        #expect(bundle.contains("CadenceCalendarSnapshotWidget()"))
        #expect(!bundle.contains("CadenceHabitCheckInWidget()"))
        #expect(!bundle.contains("CadenceMilestoneMomentumWidget()"))
        // Exactly two registrations, so a third added without a ledger slot is not silent.
        #expect(bundle.components(separatedBy: "Widget()").count - 1 == 2)

        // Every shipping kind has a slot.
        #expect(CadenceWidgetGenerationLedger.instrumentedKinds.contains(CadenceWidgetRefreshCenter.todayWidgetKind))
        #expect(CadenceWidgetGenerationLedger.instrumentedKinds.contains(CadenceWidgetRefreshCenter.calendarWidgetKind))

        // And so does every retired one, because the reset has to be able to erase their rows.
        for retired in [CadenceWidgetRefreshCenter.habitWidgetKind, CadenceWidgetRefreshCenter.milestoneWidgetKind] {
            #expect(CadenceWidgetGenerationLedger.instrumentedKinds.contains(retired))
        }
        #expect(Set(CadenceWidgetGenerationLedger.instrumentedKinds).count == 4)
    }

    /// The claim above, driven rather than asserted from a list: a row an older build wrote under a
    /// **retired** kind is still erased by `clearStoredState`.
    ///
    /// The control is the shipping kind written in the same breath — if both readings came back
    /// `.silent` because the instrument was off, the first `#expect` would already have failed, so
    /// the retired row's disappearance is an erasure and not an empty denominator.
    @Test func clearingTheLedgerErasesRowsARetiredWidgetKindWrote() throws {
        try withTemporaryDefaults("cadence.widget.cost.retired") { defaults in
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)

            for kind in [CadenceWidgetRefreshCenter.habitWidgetKind, CadenceWidgetRefreshCenter.todayWidgetKind] {
                let written = probe(kind: kind, defaults: defaults)
                // A generation that measured no stage is deliberately not a record, so the stages
                // have to be closed here or the fixture writes nothing and the erasure is vacuous.
                written.finished(.containerOpen)
                written.finished(.fetch, rows: 4)
                written.finished(.derive)
                written.recordGeneration(
                    outcome: .ready,
                    renderedCount: 3,
                    sourceSnapshotAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            }

            // Both rows are really there before the reset runs.
            for kind in [CadenceWidgetRefreshCenter.habitWidgetKind, CadenceWidgetRefreshCenter.todayWidgetKind] {
                guard case .recorded = CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults) else {
                    Issue.record("no row recorded for \(kind), so the erasure below would be vacuous")
                    return
                }
            }

            CadenceWidgetGenerationLedger.clearStoredState(userDefaults: defaults)

            for kind in [CadenceWidgetRefreshCenter.habitWidgetKind, CadenceWidgetRefreshCenter.todayWidgetKind] {
                #expect(
                    CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults)
                        == .silent(.nothingRecorded),
                    "a row written under \(kind) survived the reset"
                )
            }
        }
    }

    // MARK: - Fixtures

    private func probe(kind: String, defaults: UserDefaults) -> CadenceWidgetGenerationProbe {
        CadenceWidgetGenerationProbe(kind: kind, userDefaults: defaults)
    }

    private static func described(_ stages: [CadenceWidgetStage: TimeInterval]) -> String {
        stages
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)s" }
            .joined(separator: " ")
    }

    /// A store **on disk, in a temporary directory**, so a container open is a real one.
    ///
    /// Three populations, because the claim being measured is about which of them a fetch has to
    /// materialise: open work carrying a date, open work carrying none, and settled work.
    private struct DiskFixture {
        static let openDatedTaskCount = 120
        static let openUndatedTaskCount = 100
        static let settledTaskCount = 80
        static var totalTaskCount: Int { openDatedTaskCount + openUndatedTaskCount + settledTaskCount }
        /// T-1403's two populations. Habit's fetch and Milestone's carry no predicate — unlike
        /// the two `AppTask` readers above, and unmeasured, which is why they were left alone —
        /// so these are the whole tables their probes count, and both are deliberately larger than
        /// the prefix their widgets draw (8 and 5), which is what `rowsFetched > renderedCount`
        /// is a claim about.
        static let habitCount = 24
        static let goalCount = 18

        let directory: URL
        let storeURL: URL
        let todayKey: String

        init() throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cadence-widget-cost-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("fixture.store")
            todayKey = DateFormatters.dateKey(from: Date(), calendar: .current)

            let container = try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "CadenceWidgetCostFixture",
                    schema: CadenceSchema.schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
            let context = ModelContext(container)
            let yesterday = DateFormatters.dateKey(
                from: Date().addingTimeInterval(-86_400),
                calendar: .current
            )

            for index in 0..<Self.openDatedTaskCount {
                let task = AppTask(title: "Dated \(index)")
                if index.isMultiple(of: 3) {
                    task.dueDate = todayKey
                } else if index.isMultiple(of: 3) == false && index.isMultiple(of: 2) {
                    task.dueDate = yesterday
                } else {
                    task.scheduledDate = todayKey
                }
                context.insert(task)
            }
            for index in 0..<Self.openUndatedTaskCount {
                context.insert(AppTask(title: "Undated \(index)"))
            }
            for index in 0..<Self.settledTaskCount {
                let task = AppTask(title: "Settled \(index)")
                task.dueDate = todayKey
                task.status = index.isMultiple(of: 2) ? .done : .cancelled
                context.insert(task)
            }
            // T-1403. Daily habits so every row is due today and the Habit widget's derive pass
            // has the whole table to filter rather than an empty result it can short-circuit.
            for index in 0..<Self.habitCount {
                let habit = Habit(title: "Habit \(index)")
                habit.frequencyType = .daily
                context.insert(habit)
            }
            // Goals in two layers, because Milestone's derive is a *traversal*: a flat pool would
            // time the ranking and not the recursion through `subGoals` that is the fanout R59
            // points at.
            var parents: [Goal] = []
            for index in 0..<Self.goalCount {
                let goal = Goal(title: "Goal \(index)")
                if index.isMultiple(of: 3), let parent = parents.last {
                    goal.parentGoal = parent
                } else {
                    parents.append(goal)
                }
                context.insert(goal)
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

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

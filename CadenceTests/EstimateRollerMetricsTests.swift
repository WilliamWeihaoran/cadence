import Foundation
import Testing
@testable import Cadence

/// The estimate roller's rules, pinned once for both platforms.
///
/// There used to be two estimate pickers: macOS's roller and an iOS panel of preset chips over two
/// typed number fields. iPad and iPhone now open the roller, so these tests are what stands in for
/// the macOS screenshots this project cannot take from an agent shell — and, since the two
/// platform branches take `isTouch` as an argument rather than reading `#if os`, they also pin the
/// touch behaviour from the macOS-only test target.
@MainActor
struct EstimateRollerMetricsTests {

    // MARK: - Columns

    @Test
    func columnsSplitATotalIntoHoursAndMinutes() {
        let split = EstimateRollerMetrics.columns(forTotal: 90)
        #expect(split.hours == 1)
        #expect(split.minutes == 30)
    }

    /// The minutes column carries multiples of five, so an off-step value has to land somewhere.
    /// It floors: the focus timer logs "Actual" minutes that are rarely multiples of five, and
    /// rounding up would show a duration longer than the one that was actually recorded.
    @Test
    func offStepMinutesFloorRatherThanRound() {
        #expect(EstimateRollerMetrics.columns(forTotal: 7).minutes == 5)
        #expect(EstimateRollerMetrics.columns(forTotal: 9).minutes == 5)
        #expect(EstimateRollerMetrics.columns(forTotal: 64).minutes == 0)
        #expect(EstimateRollerMetrics.columns(forTotal: 64).hours == 1)
    }

    @Test
    func columnsClampToTheRollersRange() {
        let overLong = EstimateRollerMetrics.columns(forTotal: 5000)
        #expect(overLong.hours == 24)
        #expect(overLong.minutes == 0)

        let negative = EstimateRollerMetrics.columns(forTotal: -30)
        #expect(negative.hours == 0)
        #expect(negative.minutes == 0)
    }

    @Test
    func everyColumnValueIsOneTheColumnsActuallyCarry() {
        for total in stride(from: 0, through: 1500, by: 7) {
            let split = EstimateRollerMetrics.columns(forTotal: total)
            #expect(EstimateRollerMetrics.hourValues.contains(split.hours))
            #expect(EstimateRollerMetrics.minuteValues.contains(split.minutes))
        }
    }

    // MARK: - Total

    @Test
    func totalAddsTheTwoColumns() {
        #expect(EstimateRollerMetrics.total(hours: 2, minutes: 15) == 135)
        #expect(EstimateRollerMetrics.total(hours: 0, minutes: 0) == 0)
    }

    @Test
    func totalCannotExceedTwentyFourHours() {
        #expect(EstimateRollerMetrics.total(hours: 24, minutes: 55) == EstimateRollerMetrics.maxMinutes)
        #expect(EstimateRollerMetrics.maxMinutes == 1440)
    }

    /// Seeding then reading back must be stable for any value the roller can express, or opening
    /// the picker twice would walk the estimate down five minutes a visit.
    @Test
    func seedingAnOnStepValueRoundTrips() {
        for total in stride(from: 0, through: EstimateRollerMetrics.maxMinutes, by: 5) {
            let split = EstimateRollerMetrics.columns(forTotal: total)
            #expect(EstimateRollerMetrics.total(hours: split.hours, minutes: split.minutes) == total)
        }
    }

    // MARK: - Stepping

    @Test
    func steppingMovesOneRow() {
        #expect(EstimateRollerMetrics.stepped(from: 30, in: EstimateRollerMetrics.minuteValues, by: 1) == 35)
        #expect(EstimateRollerMetrics.stepped(from: 30, in: EstimateRollerMetrics.minuteValues, by: -1) == 25)
    }

    /// A wheel that wraps from 24h back to 0h loses the value you overshot; this one stops.
    @Test
    func steppingStopsAtTheEndsRatherThanWrapping() {
        #expect(EstimateRollerMetrics.stepped(from: 55, in: EstimateRollerMetrics.minuteValues, by: 1) == 55)
        #expect(EstimateRollerMetrics.stepped(from: 0, in: EstimateRollerMetrics.minuteValues, by: -1) == 0)
        #expect(EstimateRollerMetrics.stepped(from: 24, in: EstimateRollerMetrics.hourValues, by: 1) == 24)
    }

    @Test
    func steppingFromAValueTheColumnDoesNotCarryFallsToItsFirstRow() {
        #expect(EstimateRollerMetrics.stepped(from: 7, in: EstimateRollerMetrics.minuteValues, by: 1) == 0)
    }

    // MARK: - Presets

    /// The presets are the one-tap path the roller alone does not give — the reason the iOS chip
    /// row could be dropped without losing anything. They must stay, and stay reachable.
    @Test
    func presetsSurviveAndAreValuesTheColumnsCanHold() {
        #expect(EstimateRollerMetrics.presets.isEmpty == false)
        for preset in EstimateRollerMetrics.presets {
            let split = EstimateRollerMetrics.columns(forTotal: preset)
            #expect(EstimateRollerMetrics.total(hours: split.hours, minutes: split.minutes) == preset)
        }
    }

    // MARK: - Touch targets

    /// A roller built for a pointer needs 44pt rows on a finger — but only where a finger actually
    /// taps. The columns are scrolled, not tapped row by row, so their density is unchanged.
    @Test
    func rollerRowsKeepTheirDensityOnBothPlatforms() {
        #expect(EstimateRollerMetrics.rowHeight == 26)
    }

    @Test
    func tappableControlsReachTheTouchMinimumOnTouch() {
        #expect(EstimateRollerMetrics.hitHeight(plateHeight: 24, isTouch: true) == 44)
        #expect(EstimateRollerMetrics.hitHeight(plateHeight: 26, isTouch: true) == 44)
    }

    /// The plate is never grown to get there — a pointer keeps the compact control it had.
    @Test
    func aPointerLeavesTheControlTheSizeItIsDrawn() {
        #expect(EstimateRollerMetrics.hitHeight(plateHeight: 24, isTouch: false) == 24)
        #expect(EstimateRollerMetrics.hitHeight(plateHeight: 26, isTouch: false) == 26)
    }

    @Test
    func anAlreadyLargeControlIsNotShrunkToTheMinimum() {
        #expect(EstimateRollerMetrics.hitHeight(plateHeight: 60, isTouch: true) == 60)
    }

    /// The clamp exists to tame trackpad momentum. On touch the content tracks the finger, so the
    /// same clamp would spring a deliberate drag back — it has to be looser there, not equal.
    @Test
    func aFingerMayCarryTheRollerFurtherThanATrackpadFlick() {
        #expect(EstimateRollerMetrics.maxRowsPerGesture(isTouch: false) == 3)
        #expect(EstimateRollerMetrics.maxRowsPerGesture(isTouch: true) > EstimateRollerMetrics.maxRowsPerGesture(isTouch: false))
    }

    @Test
    func theRunningPlatformPicksTheRightBranch() {
        #if os(macOS)
        #expect(EstimateRollerMetrics.isTouchInput == false)
        #else
        #expect(EstimateRollerMetrics.isTouchInput)
        #endif
    }
}

/// **T-1431 — the first owner-reported defect in this ledger, as a count.**
///
/// The owner rolled the macOS estimate popover and reported that it "lags a ton and does not have
/// any smooth animation". Two defects sat behind that one sentence and only the second was visible
/// from source alone.
///
/// **What is asserted here is a COUNT, and deliberately not a duration.** CI runs Xcode 26 and the
/// machine this was written on runs 27.0; T-1279/T-1296 are the standing record of what pinning one
/// toolchain's timing answer costs. "It feels smooth" is not a bound a test can hold. *"One roll is
/// one write, however many rows it crosses"* is.
///
/// **What was NOT the cause, so nobody re-measures it.** `opacity(for:)` calls
/// `values.firstIndex(of:)` twice per row per render, which is O(n) inside an O(n) body — and the
/// two columns are `Array(0...24)` and `stride(from: 0, through: 55, by: 5)`, i.e. **25 and 12
/// rows**. That is ~1,250 integer comparisons per render and cannot be felt. It is untouched.
@MainActor
struct EstimateRollerCommitRateTests {

    /// The panel reduced to the one thing this ticket is about: what the centred row reports, what
    /// the gate says about it, and how many writes reach the value behind the panel.
    ///
    /// `isGated == false` replays the behaviour the owner hit, so the before and after numbers come
    /// out of the same transcript rather than out of two different descriptions of one.
    private struct Roller {
        var gate = EstimateRollerCommitGate()
        var isGated = true
        /// What the two columns currently add up to.
        private(set) var centred = 0
        /// The value the caller's binding holds — `task.estimatedMinutes` in the macOS inspector.
        private(set) var stored = 0
        /// Every write that reached it, in order.
        private(set) var writes: [Int] = []

        /// `scrollPosition(id:anchor:.center)` reporting a new centred row.
        mutating func rowCentred(_ value: Int) {
            centred = value
            guard isGated else {
                commit()
                return
            }
            guard gate.noteValueChanged() else { return }
            commit()
        }

        /// `onScrollPhaseChange` reporting `ScrollPhase.isScrolling`.
        mutating func scrollPhase(_ column: EstimateRollerCommitGate.Column, isScrolling: Bool) {
            guard isGated else { return }
            guard gate.noteScrollPhaseChanged(column, isScrolling: isScrolling) else { return }
            commit()
        }

        /// ↑/↓, a preset, Clear, Done — and the panel's `onDisappear` flush.
        mutating func commit(force: Bool = false) {
            gate.noteWritePerformed()
            guard stored != centred else { return }
            stored = centred
            writes.append(centred)
        }
    }

    /// One fling over ten rows, as the two columns report it.
    private func fling(
        _ roller: inout Roller,
        column: EstimateRollerCommitGate.Column = .hours,
        rows: [Int],
        reportLandingAfterTheSettle: Bool = false
    ) {
        roller.scrollPhase(column, isScrolling: true)
        let tracked = reportLandingAfterTheSettle ? Array(rows.dropLast()) : rows
        for row in tracked { roller.rowCentred(row) }
        roller.scrollPhase(column, isScrolling: false)
        if reportLandingAfterTheSettle, let landed = rows.last { roller.rowCentred(landed) }
    }

    // MARK: - The measurement the fix is answering

    /// **The before number.** Ungated, the transcript below writes once per row the centre band
    /// crossed — and on the macOS inspector each of those is `task.estimatedMinutes`, so each one
    /// invalidates every view observing that task.
    @Test("Ungated, one roll writes once per row it crosses")
    func theUngatedRollerWritesOncePerRowCrossed() {
        var roller = Roller()
        roller.isGated = false
        let crossed = Array(1...10).map { $0 * 60 }

        fling(&roller, rows: crossed)

        #expect(roller.writes.count == crossed.count)
        #expect(roller.writes == crossed)
    }

    /// **The after number, and the bound.** The same ten rows, gated: one write, and it is the row
    /// the gesture landed on.
    @Test("One settled roll is one write, however many rows it crossed")
    func aGatedRollWritesOnceHoweverManyRowsItCrosses() {
        var roller = Roller()
        let crossed = Array(1...10).map { $0 * 60 }

        fling(&roller, rows: crossed)

        #expect(roller.writes.count == 1)
        #expect(roller.writes == [600])
        #expect(roller.stored == 600)
    }

    /// And the bound does not drift with the length of the gesture: twice the rows is still one
    /// write, which is the difference between a bound and a coincidence.
    @Test("Twice the rows is still one write")
    func theWriteCountDoesNotFollowTheRowCount() {
        var short = Roller()
        fling(&short, rows: Array(1...5).map { $0 * 5 })

        var long = Roller()
        fling(&long, rows: Array(1...11).map { $0 * 5 })

        #expect(short.writes.count == 1)
        #expect(long.writes.count == 1)
        #expect(long.stored == 55)
    }

    /// If the landed row is reported *after* the settle rather than before it, the deferral has
    /// already been redeemed and the late report writes on its own. Two writes, not ten — and the
    /// stored value is still the row the user landed on, which is the half that matters.
    @Test("A landing reported after the settle still lands, and still does not write per row")
    func aLandingReportedAfterTheSettleStillWritesTheLandedRow() {
        var roller = Roller()
        let crossed = Array(1...10).map { $0 * 60 }

        fling(&roller, rows: crossed, reportLandingAfterTheSettle: true)

        #expect(roller.writes.count <= 2)
        #expect(roller.stored == 600)
        #expect(roller.writes.last == 600)
    }

    // MARK: - What the deferral must never swallow

    /// The constraint the ticket put in writing: the roller must still write when the user stops.
    /// Nothing is moving here, so there is nothing to defer and the write is immediate.
    @Test("A change with no column moving writes immediately")
    func aChangeOutsideAGestureWritesAtOnce() {
        var roller = Roller()

        roller.rowCentred(45)

        #expect(roller.writes == [45])
        #expect(roller.gate.isWriteOwed == false)
    }

    /// ↑/↓, a preset, Clear and Done do not consult the gate at all — they call `commit(force:)`,
    /// which writes even mid-gesture and clears whatever was owed.
    @Test("Keyboard, presets, Clear and Done write through the gate rather than behind it")
    func aForcedCommitWritesMidGestureAndClearsTheDebt() {
        var roller = Roller()
        roller.scrollPhase(.minutes, isScrolling: true)
        roller.rowCentred(20)
        #expect(roller.writes.isEmpty, "a mid-gesture report wrote")
        #expect(roller.gate.isWriteOwed)

        roller.commit(force: true)

        #expect(roller.writes == [20])
        #expect(roller.gate.isWriteOwed == false, "the settle would write a second time")

        // And the settle that follows does not write again, because nothing is owed.
        roller.scrollPhase(.minutes, isScrolling: false)
        #expect(roller.writes == [20])
    }

    /// A panel dismissed by a click outside it while a column is still decelerating never gets its
    /// settle. The debt is readable, which is what lets `onDisappear` redeem it.
    @Test("A write owed when the panel goes away is still readable, so onDisappear can flush it")
    func anOwedWriteSurvivesForTheDisappearFlush() {
        var roller = Roller()
        roller.scrollPhase(.hours, isScrolling: true)
        roller.rowCentred(120)

        #expect(roller.writes.isEmpty)
        #expect(roller.gate.isWriteOwed, "nothing would tell onDisappear a write is outstanding")

        roller.commit(force: true)
        #expect(roller.stored == 120)
    }

    /// Both columns share one gate, because the value is `hours * 60 + minutes`: writing it while
    /// the *other* column is still moving is the same mid-gesture write from the other side.
    @Test("The write waits for both columns, not just the one that changed")
    func aStillMovingSecondColumnHoldsTheWrite() {
        var roller = Roller()
        roller.scrollPhase(.hours, isScrolling: true)
        roller.scrollPhase(.minutes, isScrolling: true)
        roller.rowCentred(90)

        roller.scrollPhase(.hours, isScrolling: false)
        #expect(roller.writes.isEmpty, "the write went out while the minutes column was still moving")

        roller.scrollPhase(.minutes, isScrolling: false)
        #expect(roller.writes == [90])
    }

    /// A settle with nothing owed is not a write. Otherwise merely touching the roller and putting
    /// it back would commit, and the panel's own no-op guard would be the only thing left holding
    /// the line.
    @Test("A settle owing nothing writes nothing")
    func aSettleWithNothingOwedIsSilent() {
        var roller = Roller()
        roller.scrollPhase(.hours, isScrolling: true)
        roller.scrollPhase(.hours, isScrolling: false)

        #expect(roller.writes.isEmpty)
        #expect(roller.gate.isRolling == false)
    }

    // MARK: - The second defect: the scroll path had no animation at all

    /// `withAnimation` appeared exactly **once** in this 718-line file, at `step(_:in:selection:)`
    /// — the ↑/↓ path. The scroll path had none, so the opacity ramp (1 / 0.55 / 0.3) and the tint
    /// switched between discrete states in a single frame as the centre band crossed a row. Both
    /// paths now ease, off one duration rather than two literals that can drift apart.
    @Test("The scroll path animates, off the same duration the keyboard path uses")
    func theRowTransitionIsAnimatedOnBothPaths() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/Shared/Components/EstimatePickerControl.swift")

        #expect(source.contains(".animation("),
                "the scroll path has no animation, so the ramp still snaps")
        #expect(source.contains("value: selection"),
                "the animation is not keyed on the row becoming the chosen one")
        #expect(source.contains(".onScrollPhaseChange"),
                "the panel no longer hears the settle, so the deferral cannot be redeemed")

        // Non-vacuity, and the reason the constant exists: the 0.12 the keyboard path carried as a
        // literal is now the one number both paths read.
        #expect(EstimateRollerMetrics.rowTransitionDuration == 0.12)
        #expect(!source.contains("duration: 0.12"),
                "the literal came back beside the constant, so the two paths can drift apart")
        let readings = source.components(separatedBy: "EstimateRollerMetrics.rowTransitionDuration").count - 1
        #expect(readings >= 2, "only one path reads the shared duration, which is not shared")
    }

    /// The ruled-out hypothesis, kept as arithmetic so it is not re-opened. Two columns of 25 and
    /// 12 rows is not a quadratic anybody can feel.
    @Test("The ramp the lag was first blamed on is 25 and 12 rows, not a long list")
    func theOpacityRampRunsOverTwoVeryShortColumns() {
        #expect(EstimateRollerMetrics.hourValues.count == 25)
        #expect(EstimateRollerMetrics.minuteValues.count == 12)
        let comparisons = EstimateRollerMetrics.hourValues.count * EstimateRollerMetrics.hourValues.count * 2
            + EstimateRollerMetrics.minuteValues.count * EstimateRollerMetrics.minuteValues.count * 2
        #expect(comparisons < 2_000)
    }
}

/// T-76: the macOS status editor in `TaskEmbedFieldEditorPopover` stopped iterating
/// `TaskStatus.allCases` and now renders `CadenceTaskInspectorSupport.StatusAction`, the same
/// model the iOS inspector uses.
@MainActor
struct TaskEmbedStatusEditorTests {

    /// The boundary that makes the deletion safe. `Start` is the **only** control on macOS that
    /// can write `.inProgress`; the four-option list it replaced was the other one. If this action
    /// ever disappears, a task already in that state has no way out but completion.
    @Test
    func startIsStillReachableAsTheSoleMacOSWriterOfInProgress() {
        let actions = CadenceTaskInspectorSupport.StatusAction.allCases
        #expect(actions.contains(.inProgress))
        #expect(CadenceTaskInspectorSupport.StatusAction.inProgress.target(from: .todo) == .inProgress)
    }

    /// The two values a status control must **not** offer, because the embed card's own checkbox
    /// already owns them. That is what shrank the list from four rows to two.
    @Test
    func completionIsLeftToTheCheckbox() {
        let offered = Set(CadenceTaskInspectorSupport.StatusAction.allCases.map(\.status))
        #expect(offered.contains(.todo) == false)
        #expect(offered.contains(.done) == false)
        #expect(offered.count < TaskStatus.allCases.count)
    }
}

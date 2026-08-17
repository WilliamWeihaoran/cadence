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

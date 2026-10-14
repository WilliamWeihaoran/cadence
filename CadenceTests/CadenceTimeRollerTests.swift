import Foundation
import Testing
@testable import Cadence

/// The hour/minute/meridiem roller's arithmetic ([[T-3169]], for [[T-3171]]'s shared panel).
///
/// **These are the lines a screenshot cannot check.** The roller itself is a SwiftUI body and the
/// test target is macOS-built, so what is pinned here is the half that can be wrong silently: the
/// 12-hour face, where `12 AM` is hour 0 and `12 PM` is hour 12 — the one pair a naive
/// `hour + meridiem * 12` gets wrong in *both* directions — and the floor-not-round rule that stops
/// merely opening the control from moving a stored time.
@Suite("Time roller model")
@MainActor
struct CadenceTimeRollerModelTests {

    // MARK: Round trip

    /// Every minute the roller can express survives being split into three columns and put back.
    ///
    /// Over the whole day rather than a handful of samples: the two readings that break are
    /// midnight and noon, and a sampled test is exactly the one that would miss them.
    @Test("Every expressible minute round-trips on both clock faces")
    func everyExpressibleMinuteRoundTrips() {
        for usesTwentyFourHourClock in [false, true] {
            for minuteOfDay in stride(from: 0, to: 24 * 60, by: CadenceTimeRollerModel.minuteStep) {
                let parts = CadenceTimeRollerModel.components(
                    fromMinutes: minuteOfDay,
                    usesTwentyFourHourClock: usesTwentyFourHourClock
                )
                let rebuilt = CadenceTimeRollerModel.minutes(
                    hour: parts.hour,
                    minute: parts.minute,
                    meridiem: parts.meridiem,
                    usesTwentyFourHourClock: usesTwentyFourHourClock
                )
                #expect(
                    rebuilt == minuteOfDay,
                    "\(minuteOfDay) rebuilt as \(rebuilt) on a \(usesTwentyFourHourClock ? "24" : "12")-hour face"
                )
            }
        }
    }

    /// Midnight and noon, named rather than left to the sweep above, because they are the whole
    /// reason the mapping is not `hour + meridiem * 12`.
    @Test("Twelve AM is midnight and twelve PM is noon")
    func twelveReadsAsMidnightAndNoon() {
        #expect(
            CadenceTimeRollerModel.minutes(
                hour: 12,
                minute: 0,
                meridiem: CadenceTimeRollerModel.amValue,
                usesTwentyFourHourClock: false
            ) == 0
        )
        #expect(
            CadenceTimeRollerModel.minutes(
                hour: 12,
                minute: 0,
                meridiem: CadenceTimeRollerModel.pmValue,
                usesTwentyFourHourClock: false
            ) == 12 * 60
        )

        let midnight = CadenceTimeRollerModel.components(fromMinutes: 0, usesTwentyFourHourClock: false)
        #expect(midnight.hour == 12)
        #expect(midnight.meridiem == CadenceTimeRollerModel.amValue)

        let noon = CadenceTimeRollerModel.components(fromMinutes: 12 * 60, usesTwentyFourHourClock: false)
        #expect(noon.hour == 12)
        #expect(noon.meridiem == CadenceTimeRollerModel.pmValue)
    }

    /// One minute before midnight is the other end of the same arithmetic, and it is a PM hour 11
    /// rather than an hour 23 the 12-hour column does not carry.
    @Test("The last minute of the day lands in the twelve-hour column's range")
    func lastMinuteOfDayStaysInRange() {
        let parts = CadenceTimeRollerModel.components(fromMinutes: 23 * 60 + 55, usesTwentyFourHourClock: false)
        #expect(parts.hour == 11)
        #expect(parts.minute == 55)
        #expect(parts.meridiem == CadenceTimeRollerModel.pmValue)
        #expect(CadenceTimeRollerModel.hourValues(usesTwentyFourHourClock: false).contains(parts.hour))
    }

    // MARK: Seeding does not move a stored time

    /// An off-step stored minute opens on the step **below** it, never above.
    ///
    /// Opening a control must not be able to push an appointment later. `EstimateRollerMetrics`
    /// floors for the same reason; this is that rule restated where the consequence is a time
    /// rather than a duration.
    @Test("An off-step minute is floored, never rounded up")
    func offStepMinutesAreFloored() {
        for offset in 1..<CadenceTimeRollerModel.minuteStep {
            let stored = 16 * 60 + offset
            let parts = CadenceTimeRollerModel.components(fromMinutes: stored, usesTwentyFourHourClock: true)
            #expect(parts.hour == 16)
            #expect(parts.minute == 0, "4:0\(offset) PM opened on :\(parts.minute)")
        }
    }

    /// Out-of-range input is held inside the day rather than wrapping into another one.
    @Test("Minutes outside the day are clamped into it")
    func outOfRangeMinutesClamp() {
        let below = CadenceTimeRollerModel.components(fromMinutes: -90, usesTwentyFourHourClock: true)
        #expect(below.hour == 0)
        #expect(below.minute == 0)

        let above = CadenceTimeRollerModel.components(fromMinutes: 25 * 60, usesTwentyFourHourClock: true)
        #expect(above.hour == 23)
    }

    // MARK: Columns

    /// The two faces carry different hour columns, and neither carries a value the other's
    /// arithmetic would mis-read.
    @Test("Hour columns match their clock face")
    func hourColumnsMatchTheClockFace() {
        #expect(CadenceTimeRollerModel.hourValues(usesTwentyFourHourClock: false) == Array(1...12))
        #expect(CadenceTimeRollerModel.hourValues(usesTwentyFourHourClock: true) == Array(0...23))
    }

    /// The minute column is the finer pointer grid, not the 15-minute grid a tap on a timeline
    /// lands on — see the constant's own note.
    @Test("The minute column steps by the pointer grid and spans one hour")
    func minuteColumnStepsByThePointerGrid() {
        #expect(CadenceTimeRollerModel.minuteStep == CadenceScheduleSupport.pointerTimeGridMinutes)
        #expect(CadenceTimeRollerModel.minuteValues.first == 0)
        #expect(CadenceTimeRollerModel.minuteValues.last == 60 - CadenceTimeRollerModel.minuteStep)
        #expect(CadenceTimeRollerModel.minuteValues.allSatisfy { $0 % CadenceTimeRollerModel.minuteStep == 0 })
    }

    /// Hours are zero-padded on a 24-hour face and bare on a 12-hour one, which is how the two
    /// faces are told apart at a glance in a column with no other chrome.
    @Test("Column labels read as a clock")
    func columnLabelsReadAsAClock() {
        #expect(CadenceTimeRollerModel.hourLabel(9, usesTwentyFourHourClock: true) == "09")
        #expect(CadenceTimeRollerModel.hourLabel(9, usesTwentyFourHourClock: false) == "9")
        #expect(CadenceTimeRollerModel.minuteLabel(5) == "05")
        #expect(CadenceTimeRollerModel.meridiemLabel(CadenceTimeRollerModel.amValue) == "AM")
        #expect(CadenceTimeRollerModel.meridiemLabel(CadenceTimeRollerModel.pmValue) == "PM")
    }
}

/// The roller **column** is one component now, not two ([[T-3169]]).
///
/// `EstimatePickerControl` carried a private `EstimateRollerColumn` and a private
/// `EstimateRollerScrollBehavior`; the schedule panel needed the same wheel for hours and minutes,
/// and a second hand-rolled copy is the outcome this repository's shared-component rule exists to
/// prevent. These are source-text checks because what is being asserted is *that there is one
/// implementation*, which no runtime value can report.
@Suite("Roller column extraction")
@MainActor
struct CadenceRollerColumnExtractionTests {

    private func source(_ relativePath: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("The estimate picker no longer declares a roller column of its own")
    func estimatePickerDeclaresNoColumn() {
        let estimate = source("Cadence/Shared/Components/EstimatePickerControl.swift")
        #expect(!estimate.isEmpty)
        #expect(!estimate.contains("private struct EstimateRollerColumn"))
        #expect(!estimate.contains("private struct EstimateRollerScrollBehavior"))
        #expect(estimate.contains("CadenceRollerColumn("))
    }

    @Test("The time roller reuses the shared column rather than declaring a wheel")
    func timeRollerReusesTheSharedColumn() {
        let roller = source("Cadence/Shared/Components/CadenceTimeRoller.swift")
        #expect(!roller.isEmpty)
        #expect(roller.contains("CadenceRollerColumn("))
        // A fresh wheel would need its own scroll view and its own target behaviour. Neither
        // appears here, which is the whole claim.
        #expect(!roller.contains("ScrollView(.vertical)"))
        #expect(!roller.contains("ScrollTargetBehavior"))
    }

    /// The geometry did not move. It stayed in `EstimateRollerMetrics`, where
    /// `EstimatePickerLargeTextLayoutTests` already pins it, and the shared column reads it through
    /// a typealias — so there is one row height in the app, not two.
    @Test("One roller geometry, read under a neutral name")
    func oneRollerGeometryUnderANeutralName() {
        let column = source("Cadence/Shared/Components/CadenceRollerColumn.swift")
        #expect(column.contains("typealias CadenceRollerMetrics = EstimateRollerMetrics"))
        #expect(CadenceRollerMetrics.rowHeight == EstimateRollerMetrics.rowHeight)
        #expect(CadenceRollerMetrics.rowTransitionDuration == EstimateRollerMetrics.rowTransitionDuration)
    }
}

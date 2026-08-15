import Foundation
import Testing
@testable import Cadence

/// The iOS habit editor renders `HabitFrequency.allCases` as a four-way segmented control, roughly
/// 80pt per segment. That control used to truncate silently, so this enum carried a second,
/// shortened `compactLabel` spelling purely to fit it. `iOSSegmentedChoice` now wraps to a second
/// line and scales down before dropping characters, so the frequencies are back to one name each
/// and these assertions guard the property the bug was actually about: whatever the four are
/// called, a reader has to be able to tell them apart.
@MainActor
struct HabitFrequencyLabelTests {

    @Test func everyFrequencyHasANameAndNoTwoShareIt() {
        let labels = HabitFrequency.allCases.map(\.label)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }

    @Test func theFullLabelIsUnchanged() {
        #expect(HabitFrequency.daily.label == "Daily")
        #expect(HabitFrequency.daysOfWeek.label == "Days of Week")
        #expect(HabitFrequency.timesPerWeek.label == "Times per Week")
        #expect(HabitFrequency.monthly.label == "Monthly")
    }
}

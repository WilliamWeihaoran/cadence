import Foundation
import Testing
@testable import Cadence

/// The iOS habit editor renders `HabitFrequency.allCases` as a four-way segmented control roughly
/// 80pt wide per segment. `label` does not survive that: "Days of Week" and "Times per Week" both
/// truncate, and "Days of W…" / "Times per…" are neither readable nor distinguishable from each
/// other. `compactLabel` is the spelling that fits; these assertions are what stop it drifting back
/// into something that does not.
@MainActor
struct HabitFrequencyLabelTests {

    /// The measured budget. 13pt semibold averages well under 8pt per character, so a segment holds
    /// comfortably more than eight characters; the ceiling here is deliberately tighter than the
    /// real one so a future edit has to think before crossing it.
    private let compactCharacterBudget = 9

    @Test func everyCompactLabelFitsASegmentOfTheFourWayControl() {
        for frequency in HabitFrequency.allCases {
            #expect(frequency.compactLabel.count <= compactCharacterBudget)
        }
    }

    /// The bug was two options that read the same once truncated, so distinctness is the property
    /// that actually matters — not any particular wording.
    @Test func compactLabelsAreDistinctFromEachOther() {
        let labels = HabitFrequency.allCases.map(\.compactLabel)
        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    /// `label` is still the full name and is what surfaces with room for a sentence use; the
    /// compact spelling is an addition, not a replacement. Two of the four are short enough that
    /// both spellings agree.
    @Test func theFullLabelIsUnchanged() {
        #expect(HabitFrequency.daily.label == "Daily")
        #expect(HabitFrequency.daysOfWeek.label == "Days of Week")
        #expect(HabitFrequency.timesPerWeek.label == "Times per Week")
        #expect(HabitFrequency.monthly.label == "Monthly")

        #expect(HabitFrequency.daily.compactLabel == HabitFrequency.daily.label)
        #expect(HabitFrequency.monthly.compactLabel == HabitFrequency.monthly.label)
    }
}

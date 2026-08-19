import Foundation
import Testing
@testable import Cadence

/// `SidebarCountLabel` and `iOSSidebarCountLabel` were 24 lines that were character-for-character
/// identical once the names were normalised, and the single difference between them was the font
/// size: 11 on macOS against 12 on iOS. One component draws both sidebars now
/// (`CadenceSidebarCountLabel`), and the figure it draws with lives here.
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so pinning the view is not on offer.
/// Pinning the number and the clamp rule is, and that is where the fork was.
struct CadenceSidebarCountMetricsTests {
    /// 12 wins. The count is the only number in the column and has to stay legible beside a 13–14pt
    /// label; the point macOS was saving bought nothing, because the label truncates against
    /// `badgeLeadingGap` either way and a fixed-size count never takes a name's width from it.
    @Test func theSidebarCountIsTwelvePointOnBothPlatforms() {
        #expect(CadenceSidebarCountMetrics.fontSize == 12)
    }

    /// A count is a bare number until it would start costing the name beside it.
    @Test func aCountUnderTheThresholdIsJustItsDigits() {
        for value in [1, 7, 42, 998, 999] {
            let count = CadenceSidebarCount(value: value, emphasis: .neutral)
            #expect(CadenceSidebarCountMetrics.displayText(for: count) == "\(value)")
        }
    }

    /// Above it, the count clamps rather than widens: a four-digit tally in a 188–200pt column
    /// would eat the list name it belongs to, and "how many over a thousand" is not actionable.
    @Test func aCountOverTheThresholdClampsInsteadOfWidening() {
        for value in [1000, 4_321, Int.max] {
            let count = CadenceSidebarCount(value: value, emphasis: .neutral)
            #expect(CadenceSidebarCountMetrics.displayText(for: count) == "999+")
        }
    }

    /// Emphasis is a colour, never a different string — the urgent count reads as the same number
    /// it would in neutral, in red.
    @Test func emphasisDoesNotChangeTheText() {
        for value in [3, 1_500] {
            let neutral = CadenceSidebarCount(value: value, emphasis: .neutral)
            let urgent = CadenceSidebarCount(value: value, emphasis: .urgent)

            #expect(
                CadenceSidebarCountMetrics.displayText(for: neutral)
                    == CadenceSidebarCountMetrics.displayText(for: urgent)
            )
        }
    }

    /// The threshold and the clamped string are one decision, so the label can never read "999+"
    /// for a count of 1000 while the rule says something else.
    @Test func theClampStringIsBuiltFromTheThreshold() {
        let atThreshold = CadenceSidebarCount(value: CadenceSidebarCountMetrics.overflowThreshold, emphasis: .neutral)
        let overThreshold = CadenceSidebarCount(value: CadenceSidebarCountMetrics.overflowThreshold + 1, emphasis: .neutral)

        #expect(CadenceSidebarCountMetrics.displayText(for: atThreshold) == "\(CadenceSidebarCountMetrics.overflowThreshold)")
        #expect(CadenceSidebarCountMetrics.displayText(for: overThreshold) == "\(CadenceSidebarCountMetrics.overflowThreshold)+")
    }
}

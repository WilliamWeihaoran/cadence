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

/// The rest of the sidebar's figures, which went through the same consolidation the count did.
///
/// The two columns had each been deciding for themselves and had drifted in five dimensions nobody
/// chose: 15pt glyphs against 13, 13pt labels against 14, 10pt of icon-to-label against 9, a 14pt
/// list colour bar against 16, and a 10pt due-date caption against 11. The user asked for one
/// sidebar, so these live in `CadenceSidebarMetrics` and both files read them.
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so — exactly as above — what is pinned
/// is the value type, not the views.
struct CadenceSidebarMetricsTests {
    private let desktop = CadenceSidebarMetrics.metrics(for: .desktop)
    private let tablet = CadenceSidebarMetrics.metrics(for: .tablet)

    /// **Row height is the only figure allowed to differ, and it must.** 32pt is right under a
    /// pointer; a finger needs 44, and a nav row is the most-tapped control in the iPad shell.
    /// Flattening this would read as a tidy-up and be an ergonomic regression.
    @Test func rowHeightIsTheOnlyFigureThatDiffersBySurface() {
        #expect(desktop.rowHeight == CadenceSidebarMetrics.pointerRowHeight)
        #expect(tablet.rowHeight == CadenceSidebarMetrics.touchRowHeight)
        #expect(desktop.rowHeight != tablet.rowHeight)

        // Everything else is the same object with that one field changed. Rebuilding the desktop
        // struct out of the tablet's other nineteen figures and expecting equality is what makes a
        // *new* divergence fail here, rather than only the figures someone remembered to assert.
        #expect(
            desktop
                == CadenceSidebarRowMetrics(
                    rowHeight: desktop.rowHeight,
                    cornerRadius: tablet.cornerRadius,
                    rowSpacing: tablet.rowSpacing,
                    horizontalPadding: tablet.horizontalPadding,
                    iconSlotWidth: tablet.iconSlotWidth,
                    iconSize: tablet.iconSize,
                    iconLabelSpacing: tablet.iconLabelSpacing,
                    labelFontSize: tablet.labelFontSize,
                    badgeLeadingGap: tablet.badgeLeadingGap,
                    secondaryIconOpacity: tablet.secondaryIconOpacity,
                    groupSpacing: tablet.groupSpacing,
                    sectionSpacing: tablet.sectionSpacing,
                    listColorBarWidth: tablet.listColorBarWidth,
                    listColorBarHeight: tablet.listColorBarHeight,
                    listColorBarLeadingInset: tablet.listColorBarLeadingInset,
                    listLabelFontSize: tablet.listLabelFontSize,
                    listDueDateIconSize: tablet.listDueDateIconSize,
                    listDueDateFontSize: tablet.listDueDateFontSize,
                    listDueDateSpacing: tablet.listDueDateSpacing,
                    listTrailingItemSpacing: tablet.listTrailingItemSpacing
                )
        )
    }

    /// The five figures that were actually forked, named individually so a regression says which
    /// one came back rather than only that the structs differ.
    @Test func theFiveDriftedFiguresLandedOnTheMacOSSpelling() {
        #expect(desktop.iconSize == 15)
        #expect(desktop.labelFontSize == 13)
        #expect(desktop.iconLabelSpacing == 10)
        #expect(desktop.listColorBarHeight == 14)
        #expect(desktop.listDueDateFontSize == 10)
    }

    /// The macOS enum is the shared type's spelling, not a second set of numbers.
    @Test func theMacOSMetricsEnumForwardsToTheSharedFigures() {
        #expect(SidebarMetrics.rowHeight == desktop.rowHeight)
        #expect(SidebarMetrics.iconSize == desktop.iconSize)
        #expect(SidebarMetrics.labelFontSize == desktop.labelFontSize)
        #expect(SidebarMetrics.iconLabelSpacing == desktop.iconLabelSpacing)
        #expect(SidebarMetrics.rowCornerRadius == desktop.cornerRadius)
        #expect(SidebarMetrics.listColorBarHeight == desktop.listColorBarHeight)
        #expect(SidebarMetrics.listDueDateFontSize == desktop.listDueDateFontSize)
        #expect(SidebarMetrics.badgeLeadingGap == desktop.badgeLeadingGap)
        #expect(SidebarMetrics.groupSpacing == desktop.groupSpacing)
        #expect(SidebarMetrics.secondaryIconOpacity == desktop.secondaryIconOpacity)
    }
}

/// The glyph tint, which both columns now draw.
///
/// The iPad drew every glyph in `Theme.dim` on the argument that macOS only keeps its hues because
/// Settings → Sidebar has a colour picker there. The preference is a plain string, so the rule for
/// reading it is shared and the picker's absence on iPad stops being a reason to look different.
struct CadenceSidebarTintTests {
    @Test func anUnsetPreferenceGivesEveryDestinationItsOwnDefault() {
        for destination in CadenceFeatureDestination.allCases {
            #expect(CadenceSidebarTint.hex(for: destination, overridesRaw: "") == destination.defaultColorHex)
        }
    }

    @Test func anOverrideWinsForItsDestinationAndOnlyThatOne() {
        let raw = "today:#112233,calendar:#445566"

        #expect(CadenceSidebarTint.hex(for: .today, overridesRaw: raw) == "#112233")
        #expect(CadenceSidebarTint.hex(for: .calendar, overridesRaw: raw) == "#445566")
        #expect(CadenceSidebarTint.hex(for: .habits, overridesRaw: raw) == CadenceFeatureDestination.habits.defaultColorHex)
    }

    /// Garbage in the preference must not take a row's colour away, and an entry for a destination
    /// the sidebar no longer offers a handle for — `inbox`, since the merge — is simply ignored.
    @Test func unparseableEntriesAreDroppedRatherThanBlankingARow() {
        let raw = "nonsense,inbox:#000000,today:#112233,malformed:"

        #expect(CadenceSidebarTint.overrides(from: raw)[.today] == "#112233")
        #expect(CadenceSidebarTint.hex(for: .allTasks, overridesRaw: raw) == CadenceFeatureDestination.allTasks.defaultColorHex)
    }

    /// The macOS enum reads the same map, keyed through its own raw values. The two enums share raw
    /// values by construction, and this is what would fail if one were renamed.
    @Test func theMacOSColourMapAgreesWithTheSharedOne() {
        let raw = "today:#112233,focus:#445566"
        let macMap = SidebarStaticDestination.colorHexMap(from: raw)

        #expect(macMap[.today] == "#112233")
        #expect(macMap[.focus] == "#445566")
        #expect(SidebarStaticDestination.today.resolvedColorHex(from: raw) == "#112233")
        #expect(
            SidebarStaticDestination.habits.resolvedColorHex(from: raw)
                == CadenceFeatureDestination.habits.defaultColorHex
        )
    }
}

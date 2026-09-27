import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **T-1410: the two presented pickers that converted, and the two that did not.**
///
/// T-1398 pinned five presented pickers to `.fixed` to stop a live regression — their labels were
/// already scaling while their frames were literals, so at `accessibility5` a `+` glyph resolved to
/// ~38pt inside a 40pt box. Pinning stopped the bleeding and converted nothing: a reader with
/// Larger Text on still got a scaled sheet that opened an unscaled picker.
///
/// These suites are what "converted properly" means as arithmetic. Every height in them is derived
/// from the lines it has to hold rather than from a constant, every assertion walks all twelve
/// `DynamicTypeSize` cases, and the literals each claim rests on are read back out of the file they
/// are asserted against — so a panel whose geometry goes back to a number fails here rather than
/// quietly measuring numbers it no longer draws.
///
/// **Nothing here asserts that the scaling environment propagates across a `.popover`.** T-1398
/// measured that it does, on Xcode 27 / iOS 26.5 only; CI runs Xcode 26, and T-1279/T-1296 are the
/// record of what pinning a toolchain's answer costs. The panels state their own scaling instead,
/// which is a property of the source and is what these suites read.
struct CadenceChoicePopoverLargeTextLayoutTests {

    private let everySize = DynamicTypeSize.allCases
    private let path = "Cadence/Shared/Components/CadenceChoicePicker.swift"

    // MARK: - The shape this panel converted to is the shape it already had

    /// The cap is still a cap, and the panel still falls back to a scroll rather than growing past
    /// it.
    ///
    /// This is the per-panel decision, and it is the reason `maxHeight` is the one literal left in
    /// a converted panel: `ViewThatFits` takes the unscrolled stack while it fits under the cap and
    /// the `ScrollView` when it does not, so the cap is a *scroll threshold*. A cap that grew with
    /// the reader's text size would put the popover off the screen instead of scrolling it, which
    /// is the one change that would make an accessibility size worse than the pin it replaced.
    @Test("The converted choice popover is intrinsically sized and scrolls past a cap")
    func theChoicePopoverStillTakesItsHeightFromItsContentAndScrollsPastTheCap() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)

        #expect(source.contains("ViewThatFits(in: .vertical)"),
                "the panel stopped sizing itself from its content")
        #expect(source.contains("ScrollView { content }"),
                "the panel stopped scrolling, so its cap became a clip")
        #expect(source.contains(".frame(maxHeight: maxHeight)"),
                "the cap stopped being a maximum")
        #expect(source.contains(".cadenceScaledTypography()"),
                "the panel no longer declares itself converted")
        #expect(!source.contains(".cadenceFixedTypography()"),
                "the panel declares both answers, so it states none")

        // And the height cap really is a constant rather than a second growing figure.
        #expect(CadenceChoicePopoverMetrics.maxHeight == 380)
        #expect(CadenceChoicePopoverMetrics.containerMaxHeight == 340)
    }

    /// Shrinking text back down to fit is what the reader asked not to happen, so the panel gets a
    /// second line instead of a `minimumScaleFactor`.
    @Test("The choice popover gains a line rather than shrinking its text")
    func theChoiceRowTakesASecondLineInsteadOfAScaleFactor() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)
        #expect(!source.contains("minimumScaleFactor"),
                "the panel shrinks its text to fit, which defeats the setting it is following")

        for size in everySize {
            let limit = CadenceChoicePopoverMetrics.titleLineLimit(at: size, scaling: .enabled)
            let expected = CadenceTypeScale.isAccessibilitySize(size) ? 2 : 1
            #expect(limit == expected, "line limit is \(limit) at \(size)")
            #expect(CadenceChoicePopoverMetrics.titleLineLimit(at: size, scaling: .fixed) == 1,
                    "an unconverted reading of this panel changed shape at \(size)")
        }
    }

    // MARK: - Every box holds the text in it, at every size

    /// The assertion the radius and metric sweeps cannot make: the row reserves what it draws.
    @Test("The choice row reserves room for every line it is allowed, at all twelve sizes")
    func theChoiceRowNeverReservesLessThanItsTitleNeeds() {
        #expect(everySize.count == 12, "a shorter walk would prove less than it claims")

        for size in everySize {
            for scaling in CadenceTypographyScaling.allCases {
                let reserved = CadenceChoicePopoverMetrics.rowMinHeight(at: size, scaling: scaling)
                let needed = CadenceChoicePopoverMetrics.rowTextHeight(at: size, scaling: scaling)
                #expect(reserved >= needed,
                        "the row reserves \(reserved) for \(needed) of text at \(size)/\(scaling)")

                // And it never drops below the platform's touch target, which is the other reason
                // the number exists.
                let touch = CadenceSettingsRowMetrics.rowHeight(at: size, scaling: scaling)
                #expect(reserved >= touch,
                        "the row fell under its touch floor at \(size)/\(scaling)")

                // The glyph slot holds the glyph drawn in it, or the leading column clips.
                let slot = CadenceChoicePopoverMetrics.glyphSlot(at: size, scaling: scaling)
                let glyph = CadenceTypeScale.size(
                    .rowTitle,
                    base: CadenceChoicePopoverMetrics.glyphSize,
                    at: size,
                    scaling: scaling
                )
                #expect(slot >= glyph, "the glyph slot clips at \(size)/\(scaling)")
            }
        }
    }

    /// **The "font grew, box did not" case, priced against the box this panel used to carry.**
    ///
    /// The row was `minHeight: CadenceSettingsRowMetrics.rowHeight` — a flat 44 on iOS, 34 on
    /// macOS — around a title at a fixed 14. The box this prices is that row **as it draws at the
    /// default text size**, which is the honest frozen number on either platform, and the question
    /// is what the title does to it once it can move. From one step above the default onward the
    /// text no longer fits inside it, and from `accessibility1` onward it needs a second line as
    /// well — which is exactly the clipping T-1364's brief says `iOSCalendarMetricsTests` and the
    /// radius sweeps stay green through.
    @Test("A row frozen at its old floor could not hold its own title once it scales")
    func theOldRowFloorOverflowsAtAccessibilitySizes() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)
        // Non-vacuity: these are the numbers the assertions below are about.
        #expect(source.contains("static let titleSize: CGFloat = 14"))
        #expect(source.contains("static let rowVerticalPadding: CGFloat = 9"))
        #expect(source.contains("minHeight: CadenceChoicePopoverMetrics.rowMinHeight("),
                "the row stopped reading the derived floor")

        let frozenFloor = CadenceChoicePopoverMetrics.rowMinHeight(at: .large, scaling: .enabled)

        var overflowingSizes: [DynamicTypeSize] = []
        for size in everySize {
            let needed = CadenceChoicePopoverMetrics.rowTextHeight(at: size, scaling: .enabled)
            if needed > frozenFloor { overflowingSizes.append(size) }

            // The pinned reading of the same row, at the same size, never moves at all.
            let pinned = CadenceChoicePopoverMetrics.rowTextHeight(at: size, scaling: .fixed)
            let atDefault = CadenceChoicePopoverMetrics.rowTextHeight(at: .large, scaling: .enabled)
            #expect(pinned == atDefault, "the unconverted row moved at \(size)")
        }

        #expect(overflowingSizes.contains(.accessibility5))
        #expect(overflowingSizes.count >= 2,
                "only one size overflowed, so the derived floor is cosmetic")
        #expect(!overflowingSizes.contains(.large),
                "the default size must be unaffected or this was never a refactor")

        // And the derived floor covers every one of them.
        for size in overflowingSizes {
            let reserved = CadenceChoicePopoverMetrics.rowMinHeight(at: size, scaling: .enabled)
            #expect(reserved > frozenFloor, "the derived floor did not grow at \(size)")
        }
    }

    // MARK: - The panel stays a panel

    /// Additive, monotonic, a no-op at the default size, and still narrow enough for the narrowest
    /// iPhone.
    ///
    /// 375pt is an iPhone SE / 13 mini in portrait, which is the narrowest screen this app runs on;
    /// the margin asserted is deliberately generous because a `.popover` is inset from the screen
    /// by an amount only UIKit knows. What is being pinned is that the panel grows by tens of
    /// points rather than by a multiplier — a proportional 230 would be 717pt at `accessibility5`.
    @Test("The panel widens by what its title gained and stays inside the narrowest iPhone")
    func theChoicePanelWidthGrowsAdditivelyAndStaysOnScreen() {
        let narrowestPhoneWidth: CGFloat = 375

        #expect(CadenceChoicePopoverMetrics.width(CadenceChoicePopoverMetrics.width, at: .large, scaling: .enabled)
            == CadenceChoicePopoverMetrics.width)

        var previous: CGFloat = 0
        for size in everySize {
            let generic = CadenceChoicePopoverMetrics.width(
                CadenceChoicePopoverMetrics.width, at: size, scaling: .enabled
            )
            let container = CadenceChoicePopoverMetrics.width(
                CadenceChoicePopoverMetrics.containerWidth, at: size, scaling: .enabled
            )
            #expect(generic >= previous, "the panel narrowed at \(size)")
            previous = generic
            #expect(container > generic, "the grouped picker stopped being the wider of the two")
            #expect(container < narrowestPhoneWidth,
                    "the panel is \(container) wide at \(size), which is off a 375pt screen")

            #expect(CadenceChoicePopoverMetrics.width(
                CadenceChoicePopoverMetrics.width, at: size, scaling: .fixed
            ) == CadenceChoicePopoverMetrics.width, "the unconverted panel moved at \(size)")
        }

        let gain: CGFloat = CadenceTypeScale.growth(
            .rowTitle,
            base: CadenceChoicePopoverMetrics.titleSize,
            at: .accessibility5,
            scaling: .enabled
        )
        let widest: CGFloat = CadenceChoicePopoverMetrics.width(
            CadenceChoicePopoverMetrics.width, at: .accessibility5, scaling: .enabled
        )
        #expect(widest == CadenceChoicePopoverMetrics.width + gain)
        // Proportional growth is what is being rejected, and it is strictly worse here.
        let proportional: CGFloat = CadenceChoicePopoverMetrics.width
            * CadenceTypeScale.multiplier(.rowTitle, at: .accessibility5, scaling: .enabled)
        #expect(widest < proportional)
        #expect(proportional > narrowestPhoneWidth)
    }
}

/// The duration editor, which converted to a different shape than the choice popover did.
struct EstimatePickerLargeTextLayoutTests {

    private let everySize = DynamicTypeSize.allCases
    private let path = "Cadence/Shared/Components/EstimatePickerControl.swift"

    /// **Why this panel is intrinsically sized instead of becoming a capped scroll.**
    ///
    /// Its two roller columns are themselves vertical `ScrollView`s. Wrapping the panel in another
    /// one — which is what `CadenceFittedPopover` does, correctly, for a list of rows — would nest
    /// a vertical scroll inside a vertical scroll over the control the reader is dragging. So the
    /// height is bounded the other way: each roller row grows and the column shows **fewer** of
    /// them, and the whole panel's height is derived block by block so a unit test can ask whether
    /// it still fits on a phone.
    @Test("The duration editor bounds its height by showing fewer rows, not by scrolling")
    func theRollerShowsFewerRowsRatherThanGrowingItsViewport() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)
        #expect(source.contains(".cadenceScaledTypography()"),
                "the panel no longer declares itself converted")
        #expect(!source.contains(".cadenceFixedTypography()"),
                "the panel declares both answers, so it states none")
        #expect(!source.contains("minimumScaleFactor"),
                "the panel shrinks its text to fit, which defeats the setting it is following")
        #expect(source.contains("static let visibleRows: CGFloat = 5"))

        #expect(EstimateRollerMetrics.visibleRows(at: .large, scaling: .enabled) == 5)
        #expect(EstimateRollerMetrics.visibleRows(at: .xxxLarge, scaling: .enabled) == 5)
        #expect(EstimateRollerMetrics.visibleRows(at: .accessibility1, scaling: .enabled) == 3)
        #expect(EstimateRollerMetrics.visibleRows(at: .accessibility5, scaling: .enabled) == 3)
        // Three is the floor: a wheel that shows no neighbours is a label.
        for size in everySize {
            let rows = EstimateRollerMetrics.visibleRows(at: size, scaling: .enabled)
            #expect(rows >= 3, "the wheel shows \(rows) values at \(size), so it stopped being a wheel")
            #expect(EstimateRollerMetrics.visibleRows(at: size, scaling: .fixed) == 5)
        }

        // The point of the trade: rows roughly double and the viewport does not.
        let base: CGFloat = EstimateRollerMetrics.viewportHeight(at: .large, scaling: .enabled)
        let largest: CGFloat = EstimateRollerMetrics.viewportHeight(at: .accessibility5, scaling: .enabled)
        let rowAtLarge: CGFloat = EstimateRollerMetrics.rowHeight(at: .large, scaling: .enabled)
        let rowAtLargest: CGFloat = EstimateRollerMetrics.rowHeight(at: .accessibility5, scaling: .enabled)
        #expect(rowAtLargest > rowAtLarge * 1.8)
        #expect(largest > base, "the viewport stopped following the type at all")
        #expect(largest < base * 1.5, "the viewport grew like the rows did, so nothing was traded")
    }

    /// Every plate in the panel holds the label on it, at every size — and the ones that are tapped
    /// still reach the platform's touch target.
    @Test("Every plate in the duration editor holds its own label at all twelve sizes")
    func theEstimatePlatesHoldTheirLabels() {
        #expect(everySize.count == 12)

        for size in everySize {
            for scaling in CadenceTypographyScaling.allCases {
                let rollerRow = EstimateRollerMetrics.rowHeight(at: size, scaling: scaling)
                let rollerLine = CadenceTypeScale.lineHeight(
                    .controlLabel, base: EstimateRollerMetrics.rowLabelSize, at: size, scaling: scaling
                )
                #expect(rollerRow >= rollerLine,
                        "a roller row is \(rollerRow) around \(rollerLine) of value at \(size)/\(scaling)")

                let preset = EstimateRollerMetrics.presetPlateHeight(at: size, scaling: scaling)
                let presetLine = CadenceTypeScale.lineHeight(
                    .metadata, base: EstimateRollerMetrics.presetLabelSize, at: size, scaling: scaling
                )
                #expect(preset >= presetLine,
                        "a preset plate is \(preset) around \(presetLine) of label at \(size)/\(scaling)")

                let footer = EstimateRollerMetrics.footerPlateHeight(at: size, scaling: scaling)
                let footerLine = CadenceTypeScale.lineHeight(
                    .metadata, base: EstimateRollerMetrics.footerLabelSize, at: size, scaling: scaling
                )
                #expect(footer >= footerLine,
                        "a footer plate is \(footer) around \(footerLine) of label at \(size)/\(scaling)")

                // The tapped controls still reach 44pt under a finger, which is the whole reason
                // `hitHeight` exists and is the figure a growing plate could have quietly absorbed.
                #expect(EstimateRollerMetrics.hitHeight(plateHeight: preset, isTouch: true)
                    >= EstimateRollerMetrics.touchTargetHeight)
                #expect(EstimateRollerMetrics.hitHeight(plateHeight: footer, isTouch: true)
                    >= EstimateRollerMetrics.touchTargetHeight)
            }
        }
    }

    /// **The "font grew, box did not" case for this panel**, against the two plate heights it
    /// carried as literals before T-1410.
    @Test("The duration editor's old literal plates could not hold their labels once they scale")
    func theOldEstimatePlatesOverflowAtAccessibilitySizes() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)
        // Non-vacuity: the two numbers below are the ones the panel drew, read back out of it.
        #expect(source.contains("static let presetPlateHeight: CGFloat = 24"))
        #expect(source.contains("static let footerPlateHeight: CGFloat = 26"))
        #expect(source.contains("static let rowHeight: CGFloat = 26"))

        let frozenPreset = EstimateRollerMetrics.presetPlateHeight
        let frozenRollerRow = EstimateRollerMetrics.rowHeight

        var presetOverflows: [DynamicTypeSize] = []
        var rollerOverflows: [DynamicTypeSize] = []
        for size in everySize {
            let presetLine = CadenceTypeScale.lineHeight(
                .metadata, base: EstimateRollerMetrics.presetLabelSize, at: size, scaling: .enabled
            )
            if presetLine > frozenPreset { presetOverflows.append(size) }

            let rollerLine = CadenceTypeScale.lineHeight(
                .controlLabel, base: EstimateRollerMetrics.rowLabelSize, at: size, scaling: .enabled
            )
            if rollerLine > frozenRollerRow { rollerOverflows.append(size) }
        }

        #expect(presetOverflows.contains(.accessibility5))
        #expect(rollerOverflows.contains(.accessibility5))
        #expect(presetOverflows.count >= 2)
        #expect(rollerOverflows.count >= 2)
        #expect(!presetOverflows.contains(.large))
        #expect(!rollerOverflows.contains(.large))
    }

    /// The presets reflow rather than truncate, and the header stacks rather than colliding.
    @Test("The presets reflow and the header stacks once the type is an accessibility size")
    func theEstimatePanelReflowsRatherThanShrinking() {
        #expect(EstimateRollerMetrics.presets.count == 5)

        for size in everySize {
            let columns = EstimateRollerMetrics.presetColumns(at: size, scaling: .enabled)
            let rows = EstimateRollerMetrics.presetRows(at: size, scaling: .enabled)
            #expect(columns >= 2, "one column of presets is a list, not a preset row")
            #expect(columns * rows >= EstimateRollerMetrics.presets.count,
                    "the grid has no room for every preset at \(size)")

            // The unconverted reading is the row it always was.
            #expect(EstimateRollerMetrics.presetColumns(at: size, scaling: .fixed) == 5)
            #expect(EstimateRollerMetrics.presetRows(at: size, scaling: .fixed) == 1)
            #expect(EstimateRollerMetrics.headerIsStacked(at: size, scaling: .fixed) == false)

            let stacked = EstimateRollerMetrics.headerIsStacked(at: size, scaling: .enabled)
            #expect(stacked == CadenceTypeScale.isAccessibilitySize(size),
                    "the header stacks at the wrong point (\(size))")
        }

        #expect(EstimateRollerMetrics.presetColumns(at: .xxxLarge, scaling: .enabled) == 5)
        #expect(EstimateRollerMetrics.presetColumns(at: .accessibility1, scaling: .enabled) == 2)
        #expect(EstimateRollerMetrics.presetRows(at: .accessibility1, scaling: .enabled) == 3)
    }

    /// And the whole panel still fits on a phone at the largest text size, which is the question a
    /// screenshot would have been used for.
    ///
    /// 667pt is an iPhone SE in portrait, the shortest screen this app runs on. The panel is an
    /// anchored popover, so it is inset from that by an amount only UIKit knows — the margin
    /// asserted is therefore generous, and what is being pinned is that the panel's height is a
    /// derived sum rather than a constant, and that the sum lands nearer 500 than 1,000.
    @Test("The duration editor still fits a phone at every text size")
    func theEstimatePanelHeightStaysInsideAPhone() {
        let shortestPhoneHeight: CGFloat = 667

        let atDefault: CGFloat = EstimateRollerMetrics.panelHeight(at: .large, scaling: .enabled)
        #expect(atDefault > 0)
        for size in everySize {
            #expect(EstimateRollerMetrics.panelHeight(at: size, scaling: .fixed) == atDefault,
                    "an unconverted reading of the panel moved at \(size)")
        }

        var previous: CGFloat = 0
        for size in everySize {
            let height = EstimateRollerMetrics.panelHeight(at: size, scaling: .enabled)
            #expect(height >= previous, "the panel got shorter at \(size)")
            previous = height
            #expect(height < shortestPhoneHeight * 0.8,
                    "the panel is \(height) tall at \(size), which does not leave a popover room")
        }

        let largest: CGFloat = EstimateRollerMetrics.panelHeight(at: .accessibility5, scaling: .enabled)
        #expect(largest > atDefault, "the panel does not follow the reader at all")
        #expect(largest < atDefault * 2.5,
                "the panel grew like a multiplier, which is the growth rule being rejected")
    }
}

/// **Why the month grid stays pinned, as arithmetic rather than as appetite.**
///
/// `CadenceQuickDatePopover` was the cheap half of T-1398's rule: nothing it draws reads the
/// scaling environment, so the pin closed no regression and only stated the rule for the day a
/// shared component in there is converted. T-1410 asked whether it could be converted with the
/// other two, and the answer is no — not because of an unconverted dependency, but because a month
/// is seven columns wide and that is not a layout decision.
struct CadenceQuickDateGridScaleTests {

    private let path = "Cadence/Shared/Components/CadenceDatePicker.swift"

    /// The grid is still the literal grid this is an argument about.
    @Test("The month grid still draws the seven fixed cells this pricing is about")
    func theMonthGridIsStillSevenLiteralColumns() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read(path)

        #expect(source.contains("GridItem(.flexible(), spacing: 2), count: 7)"),
                "the month grid stopped being seven flexible columns")
        #expect(source.contains(".frame(width: 34, height: 34)"),
                "the day cell stopped being a 34pt square")
        #expect(source.contains(".font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))"),
                "the day numeral stopped being a fixed 12")
        #expect(source.contains(".cadenceFixedTypography()"),
                "the panel stopped declaring that it does not scale")
        #expect(!source.contains(".cadenceScaledTypography()"),
                "the month grid opted itself in without its geometry moving")
    }

    /// **Seven columns is what a month is, and seven grown cells do not fit a phone.**
    ///
    /// The day cell is a 34pt circle around a 12pt numeral — 19.6pt of ring and gutter for a 14.4pt
    /// line box. Growing it the way every other box in T-1364/T-1410 grows (additively, by what the
    /// text gained) makes it 59pt at `accessibility5`, and the widest column the narrowest iPhone
    /// can offer a seven-column grid inside this panel's own padding is under 50.
    ///
    /// The only arrangement that keeps seven columns is a cell derived from the line box alone —
    /// which is the same as saying *delete the ring*, since a line box of 44.4 in a cell of 44.4
    /// leaves nothing around the numeral. That is a different control, not a scaled one, so it is a
    /// redesign rather than a conversion and this panel honestly does not scale.
    @Test("Seven day cells grown by this app's own rule do not fit the narrowest iPhone")
    func aGrownMonthGridIsWiderThanAPhone() {
        // From the file, and asserted to still be there by the test above.
        let cellSide: CGFloat = 34
        let numeralSize: CGFloat = 12
        let columns: CGFloat = 7
        let columnSpacing: CGFloat = 2
        let gridHorizontalPadding: CGFloat = 8
        let narrowestPhoneWidth: CGFloat = 375

        let availableWidth: CGFloat = narrowestPhoneWidth
            - gridHorizontalPadding * 2
            - columnSpacing * (columns - 1)
        let availableColumn: CGFloat = availableWidth / columns

        // The app's own growth rule, applied to the cell.
        let grownCell: CGFloat = CadenceTypeScale.height(
            cellSide, holding: .metadata, textBase: numeralSize, at: .accessibility5, scaling: .enabled
        )
        #expect(grownCell > availableColumn,
                "a \(grownCell)pt cell fits a \(availableColumn)pt column, so the pin needs re-arguing")

        // And the one thing that would fit is the cell with its ring removed.
        let numeralLine: CGFloat = CadenceTypeScale.lineHeight(
            .metadata, base: numeralSize, at: .accessibility5, scaling: .enabled
        )
        #expect(numeralLine < availableColumn, "even a bare line box does not fit, so say so instead")
        let ringToday: CGFloat = cellSide - numeralSize * CadenceTypeScale.lineHeightRatio
        #expect(ringToday > 0, "the drawn cell has no ring, so there is nothing being given up")
        // Keeping the ring the cell is actually drawn with, around a numeral that has grown, is
        // the thing that does not fit. So "convert it" means "delete the ring", which is a
        // different control rather than a scaled one.
        let grownNumeralInTodaysRing: CGFloat = numeralLine + ringToday
        #expect(grownNumeralInTodaysRing > availableColumn,
                "today's ring around a grown numeral fits after all, so the pin needs re-arguing")

        // The default size is untouched either way, which is what makes the pin free.
        #expect(CadenceTypeScale.height(
            cellSide, holding: .metadata, textBase: numeralSize, at: .large, scaling: .enabled
        ) == cellSide)
        for size in DynamicTypeSize.allCases {
            #expect(CadenceTypeScale.height(
                cellSide, holding: .metadata, textBase: numeralSize, at: size, scaling: .fixed
            ) == cellSide, "the pinned cell moved at \(size)")
        }
    }
}

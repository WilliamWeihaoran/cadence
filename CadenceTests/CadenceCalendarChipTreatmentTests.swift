import Foundation
import SwiftUI
import Testing

#if canImport(AppKit)
import AppKit
#endif

@testable import Cadence

/// **T-3160, the chip half: which of the two calendar treatments each chip wears.**
///
/// `CadenceCalendarEventStyle` holds two families — `plate*` (the bright luminance-solved fill
/// with `Theme.onColor` ink) and `rail*` (Apple Calendar's dark tinted plate with the title in the
/// calendar's own hue) — and T-3160 swapped who wears which: a **task** takes `plate`, an **event**
/// takes `rail`. The contrast work itself is pinned by `CadenceContrastFloorTests`; what was
/// unguarded until this file is the **assignment**, which is exactly the half of a paint swap that
/// can land for four chips out of five and look finished.
///
/// Five chips are in scope here: macOS `MonthEventChip` / `MonthTaskChip` in the month grid,
/// macOS `AllDayEventChip` / `AllDayTaskChip` in the all-day lane, and iOS `iOSCalendarMiniChip`,
/// which is the one chip that serves both and therefore branches. The timed canvases are T-3161's
/// and the Calendar Board's tint-wash cards are deliberately out of the swap.
///
/// **The negative is the point.** "An event chip draws no rail" is not something any existing test
/// could witness, because a rail that was never added looks identical to a rail that was dropped
/// on purpose. It was dropped on purpose — see `noChipInEitherFileDrawsTheRailItself` for the
/// measurement — so the fact is asserted rather than left as an absence.
@Suite("Calendar chip treatments (T-3160)")
struct CadenceCalendarChipTreatmentTests {

    private static let macOSChips = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
    private static let iOSChips = "Cadence/iOS/iOSCalendarMonthViews.swift"

    /// EventKit hands back whatever the account stored, so this is not the palette: it is the
    /// palette's bright end, a raw white calendar, and the degenerate corners a user-chosen
    /// `colorHex` can reach. Same sweep `CadenceContrastFloorTests` uses, deliberately — a chip
    /// that only holds on the colours someone remembered is the defect both files exist to stop.
    private static let hues = ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000", "#0000ff", "#000000"]

    // MARK: - What the two treatments do at chip size

    /// The swap is only visible if the two chip plates stay apart, so this measures the gap rather
    /// than trusting that two functions with different names return different colours.
    ///
    /// The targets are hue-independent, but the colours that come back are not: `solvedBrightness`
    /// bisects brightness in `0...1` and a deep hue can run out before it reaches the target. The
    /// gap is therefore measured on the **resolved fills**, not on `plateLuminance` against
    /// `railFillLuminance` — which is the measurement `CadenceContrastFloorTests` already makes and
    /// which cannot see this.
    ///
    /// **One hue falls short of the 15-or-so L\* the rest hold, and it is named rather than
    /// averaged away.** A primary `#0000ff` cannot reach the plate treatment's *active* target of
    /// Y = 0.124: at 0.9 of its saturation and full brightness it tops out at Y = 0.0815, so the
    /// bisection returns brightness 1 and the active plate is the same colour as the rest plate.
    /// The gap to the rail plate narrows from 16.9 L\* to 9.3 there. That is still nine times the
    /// just-noticeable step, so the two treatments remain plainly different — but it is a property
    /// of the plate solve that predates this ticket, and a second hue joining it should be read as
    /// news.
    @Test func theEventChipPlateIsTheDarkerOfTheTwoAtEveryHue() {
        var measured = 0
        var narrow: [String] = []
        for hex in Self.hues {
            let swatch = Color(hex: hex)
            for active in [false, true] {
                measured += 1
                let rail = Theme.relativeLuminance(of: CadenceCalendarEventStyle.railChipFill(for: swatch, isActive: active))
                let plate = Theme.relativeLuminance(of: CadenceCalendarEventStyle.plateChipFill(for: swatch, isActive: active))
                #expect(
                    rail < plate,
                    "\(hex) (active: \(active)): the chip plates have crossed, rail \(t3160Rounded(rail)) against plate \(t3160Rounded(plate))"
                )

                let gap = t3160LStar(plate) - t3160LStar(rail)
                if gap <= 15 { narrow.append("\(hex) (active: \(active))") }
                #expect(
                    gap > 9,
                    "\(hex) (active: \(active)): the two chip plates are \(t3160Rounded(gap)) L* apart, which is a state-step not a treatment"
                )
            }
        }
        #expect(measured == 14, "non-vacuity: seven hues in two states, \(measured) measured")
        #expect(
            narrow == ["#0000ff (active: false)", "#0000ff (active: true)"],
            "the set of hues whose plate cannot reach its own target changed: \(narrow)"
        )
    }

    /// Both chip treatments still clear AA at chip size, measured on the fill the ink actually
    /// lands on.
    ///
    /// This is not a duplicate of `CadenceContrastFloorTests`' tier sweep: that one measures the
    /// *block* fills. A chip reads `plateChipFill` / `railChipFill`, which take `isActive` and have
    /// no selected state, and nothing was asserting that the chip-sized solve lands where the
    /// block-sized one does.
    @Test func everyChipTierClearsItsFloorOnItsOwnChipPlate() {
        var measured = 0
        for hex in Self.hues {
            let swatch = Color(hex: hex)
            for active in [false, true] {
                let rail = CadenceCalendarEventStyle.railChipFill(for: swatch, isActive: active)
                let plate = CadenceCalendarEventStyle.plateChipFill(for: swatch, isActive: active)

                // The event chip: title and time range in the hue, recurrence-tier glyph on iOS.
                measured += 3
                #expect(
                    t3160Ratio(CadenceCalendarEventStyle.railTitleColor(for: swatch, isActive: active), on: rail) >= 4.5,
                    "\(hex) (active: \(active)): the event chip title fell under AA on its own plate"
                )
                #expect(
                    t3160Ratio(CadenceCalendarEventStyle.railSecondaryLabelColor(for: swatch, isActive: active), on: rail) >= 4.5,
                    "\(hex) (active: \(active)): the event chip time range fell under AA on its own plate"
                )
                #expect(
                    t3160Ratio(CadenceCalendarEventStyle.railTertiaryLabelColor(for: swatch, isActive: active), on: rail) >= 3,
                    "\(hex) (active: \(active)): the event chip glyph fell under the 3:1 non-text bar"
                )

                // The task chip: `Theme.onColor` ink, and the tertiary tier the completion glyph
                // falls back to when a task has no deadline to colour it.
                measured += 2
                #expect(
                    t3160Ratio(CadenceCalendarEventStyle.platePrimaryLabelColor, on: plate) >= 4.5,
                    "\(hex) (active: \(active)): the task chip title fell under AA on its own plate"
                )
                #expect(
                    t3160Ratio(CadenceCalendarEventStyle.plateTertiaryLabelColor(isActive: active), on: plate) >= 3,
                    "\(hex) (active: \(active)): the task chip's neutral completion glyph fell under the 3:1 non-text bar"
                )
            }
        }
        #expect(measured == 70, "non-vacuity: seven hues, two states, five tiers, \(measured) measured")
    }

    /// **Why neither solved chip plate carries `Theme.subtleWash` any more, measured rather than
    /// asserted in a comment.**
    ///
    /// Both event chips used to composite a 3.5% white wash over the fill. Under the old plate
    /// treatment that was nearly free — the fill sat at Y = 0.098 and white ink has nowhere to
    /// fall to. Under the rail treatment the plate is solved to Y = 0.030 and the title is a
    /// *colour*, solved to `railTitleContrastTarget` against exactly that number, so the wash is
    /// spending contrast the solve already allocated. The margin above 4.5 exists to survive a
    /// `colorHex` rounding to 8 bits per channel, not to survive a second fill.
    ///
    /// The loss is asserted as a *direction and a size*, not a table: the washed ratio must fall
    /// below the declared target at every hue, and the bright end of the gamut — which is what the
    /// palettes actually ship — must give up most of the 0.6 the target was carrying.
    ///
    /// **The cost is hue-dependent, and the deep hues are the ones that lose least**, which is the
    /// opposite of the intuition. A 3.5% white wash lifts a plate by a fixed amount in *sRGB*, and
    /// how much luminance that buys depends on where on the transfer curve the plate sits: a plate
    /// built from `#ffc857` or a white calendar goes 0.030 → 0.039 and the title falls to about
    /// 4.59:1, while `#0000ff`'s much lower-coded plate goes 0.030 → 0.034 and it falls only to
    /// 4.88:1. Every hue loses, none of them for free, and the worst case is the common one.
    @Test func aWhiteWashOverTheEventChipPlateSpendsTheTitlesRoundingMargin() {
        let target = CadenceCalendarEventStyle.railTitleContrastTarget
        var measured = 0
        var worst = 0.0
        for hex in Self.hues {
            let swatch = Color(hex: hex)
            let plate = CadenceCalendarEventStyle.railChipFill(for: swatch)
            let title = CadenceCalendarEventStyle.railTitleColor(for: swatch)

            let unwashed = t3160Ratio(title, on: plate)
            let washed = t3160Ratio(title, on: Theme.subtleWash, over: plate)
            measured += 1
            worst = max(worst, unwashed - washed)

            #expect(
                unwashed >= target - 0.05,
                "\(hex): the unwashed title no longer lands on its \(target):1 target, at \(t3160Rounded(unwashed)):1"
            )
            #expect(
                washed < target,
                "\(hex): the wash is free here, which means the plate is no longer solved"
            )
            #expect(
                unwashed - washed > 0.2,
                "\(hex): the wash cost only \(t3160Rounded(unwashed - washed)) of contrast; re-measure before letting it back in"
            )
        }
        #expect(measured == 7, "non-vacuity: \(measured) hues measured")
        #expect(
            worst > 0.4,
            "the worst hue now loses only \(t3160Rounded(worst)) of the title's margin to the wash, against the 0.52 measured"
        )

        // And the wash is still a real white, so the numbers above cannot come from a token that
        // was quietly emptied.
        #expect(Theme.relativeLuminance(of: Theme.subtleWash) > 0, "Theme.subtleWash stopped being a wash")
    }

    // MARK: - Which chip reads which family

    /// The assignment itself: each chip names one family and **not** the other.
    ///
    /// Scoped to each chip's own declaration body rather than to the file, because all five of
    /// these live two screens apart and a file-wide `contains` is satisfied by the neighbour. Read
    /// through `codeOnly`, so the prose explaining the swap — which necessarily names both
    /// families — cannot stand in for a call.
    @Test func eachChipNamesExactlyOneOfTheTwoTreatments() throws {
        let macOS = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.macOSChips))

        let chips: [(declaration: String, wears: [String], refuses: [String])] = [
            (
                "struct MonthEventChip: View",
                ["CadenceCalendarEventStyle.railChipFill(for:",
                 "CadenceCalendarEventStyle.railTitleColor(for:",
                 "CadenceCalendarEventStyle.railSecondaryLabelColor(for:",
                 "CadenceCalendarEventStyle.railColor(for:"],
                ["plateChipFill", "platePrimaryLabelColor", "plateSecondaryLabelColor", "Theme.subtleWash"]
            ),
            (
                "struct MonthTaskChip: View",
                ["CadenceCalendarEventStyle.plateChipFill(for:",
                 "CadenceCalendarEventStyle.platePrimaryLabelColor",
                 "CadenceCalendarEventStyle.plateSecondaryLabelColor(",
                 "CadenceCalendarEventStyle.plateTertiaryLabelColor("],
                ["railChipFill", "railTitleColor", "railColor", "Theme.subtleWash"]
            ),
            (
                "struct AllDayEventChip: View",
                ["CadenceCalendarEventStyle.railChipFill(for:",
                 "CadenceCalendarEventStyle.railTitleColor(for:",
                 "CadenceCalendarEventStyle.railColor(for:"],
                ["plateChipFill", "platePrimaryLabelColor", "Theme.subtleWash"]
            ),
            (
                "struct AllDayTaskChip: View",
                ["CadenceCalendarEventStyle.plateChipFill(",
                 "CadenceCalendarEventStyle.platePrimaryLabelColor",
                 "CadenceCalendarEventStyle.plateTertiaryLabelColor("],
                ["railChipFill", "railTitleColor", "railColor", "Theme.subtleWash"]
            )
        ]

        for chip in chips {
            let body = try #require(
                CadenceSourceScan.declarationBody(chip.declaration, in: macOS),
                "\(chip.declaration) is gone from \(Self.macOSChips)"
            )
            #expect(body.count > 200, "non-vacuity: \(chip.declaration) read back \(body.count) characters")
            for needle in chip.wears {
                #expect(body.contains(needle), "\(chip.declaration) no longer draws \(needle)")
            }
            for needle in chip.refuses {
                #expect(!body.contains(needle), "\(chip.declaration) is wearing the other treatment's \(needle)")
            }
        }
    }

    /// iOS's chip is the one that serves both, so the assignment lives in its branches rather than
    /// in which symbols it mentions. The flag has to be read in the right direction: before
    /// T-3160 it was `isEventPlate` and an event wore the plate, and the whole failure mode of a
    /// half-landed swap is a branch left pointing the old way under a new name.
    @Test func theIOSMiniChipBranchesTheRightWayRound() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.iOSChips))
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSCalendarMiniChip: View", in: source),
            "iOSCalendarMiniChip is gone from \(Self.iOSChips)"
        )
        #expect(body.count > 400, "non-vacuity: the mini chip read back \(body.count) characters")

        // The retired spelling, named so a rename cannot quietly restore the old meaning.
        #expect(
            !body.contains("isEventPlate"),
            "the mini chip still calls its flag isEventPlate, which now says the opposite of what it does"
        )
        #expect(body.contains("var isEvent = false"))

        // Dense, because the three branches are each wrapped across lines by the formatter and
        // adjacency is the claim: *this* flag selects *that* family.
        let dense = body.filter { !$0.isWhitespace }
        for pair in [
            "isEvent?CadenceCalendarEventStyle.railChipFill(for:color):CadenceCalendarEventStyle.plateChipFill(for:color)",
            "isEvent?CadenceCalendarEventStyle.railTitleColor(for:color):CadenceCalendarEventStyle.platePrimaryLabelColor",
            "isEvent?CadenceCalendarEventStyle.railTertiaryLabelColor(for:color):CadenceCalendarEventStyle.plateTertiaryLabelColor()",
            "isEvent?CadenceCalendarEventStyle.railColor(for:color):color"
        ] {
            #expect(dense.contains(pair), "the mini chip no longer branches as \(pair)")
        }

        // The call site that opts in. One event list in this grid, and it is the event list.
        #expect(
            CadenceSourceScan.matchCount(#"isEvent: true"#, in: source) == 1,
            "the mini chip's event branch is reached \(CadenceSourceScan.matchCount(#"isEvent: true"#, in: source)) times, expected once"
        )
    }

    /// **The negative, which nothing else in the tree can witness.**
    ///
    /// A rail is right on a timeline block and wrong at chip size, and both of these files were
    /// asked separately. `CadenceCalendarEventStyle.railWidth` is 3pt. A month chip is
    /// `CalendarMonthCellLayout.chipHeight` — 15pt — clipped to `CalendarVisualStyle.chipRadius`,
    /// which is 6: the two corners take 12 of those 15 points of the leading edge, so a 3pt bar
    /// survives as a 3x3 nub. The all-day chip was measured on its own rather than assumed to
    /// match: a 10pt line plus 2pt of padding top and bottom is about 16pt at the same radius,
    /// which leaves roughly 4pt of straight edge — longer, and just as unreadable as the identity
    /// marker a rail is meant to be. iOS's mini chip is about 17pt at `Theme.radiusControl` and
    /// lands in the same place.
    ///
    /// Apple reaches the same conclusion in its own month grid, where an event is a tinted chip or
    /// a dot and the rail appears only on the day and week canvases. So the rail treatment arrives
    /// at chip size as **colour**, and this test is what stops that reading as an oversight — or,
    /// in the other direction, stops someone adding a rail here because the timeline has one.
    @Test func noChipInEitherFileDrawsTheRailItself() throws {
        // The geometry the verdict rests on, read from the constants rather than remembered.
        #expect(CadenceCalendarEventStyle.railWidth == 3)
        #expect(CalendarMonthCellLayout.chipHeight == 15)
        #expect(CalendarVisualStyle.chipRadius == 6)
        // The straight part of the leading edge — everything the two corners do not take — is
        // 15 - 2*6 = 3pt, which is exactly `railWidth`. A rail as long as it is wide is a nub.
        let straightEdge = CalendarMonthCellLayout.chipHeight - (CalendarVisualStyle.chipRadius * 2)
        #expect(
            straightEdge <= CadenceCalendarEventStyle.railWidth,
            """
            the month chip now has \(straightEdge)pt of straight leading edge against a \
            \(CadenceCalendarEventStyle.railWidth)pt rail; re-ask the question this test answers
            """
        )

        for path in [Self.macOSChips, Self.iOSChips] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceCalendarEventStyle"), "non-vacuity: \(path) reads no calendar style at all")
            #expect(
                CadenceSourceScan.matchCount(#"railWidth"#, in: code) == 0,
                "\(path) draws a rail at chip size; see this test for why that renders as a nub"
            )
            #expect(
                CadenceSourceScan.matchCount(#"railBorderOpacity"#, in: code) == 0,
                "\(path) uses the rail's own quiet border ladder, which is quiet because a rail is marking the edge for it"
            )
        }
    }

    /// No chip is left calling a name that does not say which treatment it means.
    ///
    /// The seven unprefixed legacy spellings (`fill`, `chipFill`, `primaryLabelColor`, …) forward
    /// to the `plate` family and exist only so that call sites outside this swap keep compiling.
    /// A chip that still reads one is ambiguous about which treatment it intends, which is the
    /// state this ticket is removing — and on macOS that includes the `CalendarEventVisualStyle`
    /// forwarder, whose own file is leased and carries no `rail*` members at all.
    @Test func noChipReadsATreatmentThroughItsLegacySpelling() throws {
        for path in [Self.macOSChips, Self.iOSChips] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            for legacy in [
                #"CadenceCalendarEventStyle\.chipFill\("#,
                #"CadenceCalendarEventStyle\.fill\("#,
                #"CadenceCalendarEventStyle\.primaryLabelColor"#,
                #"CadenceCalendarEventStyle\.secondaryLabelColor\("#,
                #"CadenceCalendarEventStyle\.tertiaryLabelColor\("#,
                #"CalendarEventVisualStyle\.chipFill\("#,
                #"CalendarEventVisualStyle\.primaryLabelColor"#
            ] {
                #expect(
                    CadenceSourceScan.matchCount(legacy, in: code) == 0,
                    "\(path) still reads \(legacy), which does not say which treatment it means"
                )
            }
        }

        // The forwarders are still live — this test bans them *here*, it does not claim they are
        // gone, and a reader who deletes them on the strength of it would break the leased file.
        #expect(CadenceCalendarEventStyle.primaryLabelColor == CadenceCalendarEventStyle.platePrimaryLabelColor)
        #expect(
            Theme.relativeLuminance(of: CadenceCalendarEventStyle.chipFill(for: Color(hex: "#4a9eff")))
                == Theme.relativeLuminance(of: CadenceCalendarEventStyle.plateChipFill(for: Color(hex: "#4a9eff")))
        )
    }

    /// The affordances that did **not** move with the paint.
    ///
    /// The owner's instruction was a paint swap: a task keeps its completion state and an event
    /// keeps its recurrence glyph. Both chips still draw what they drew, which is what makes the
    /// two readable apart even where the plates are closest — and it is worth pinning, because a
    /// swap that also moved the circle would look tidy and be wrong.
    @Test func theSwapMovedPaintAndNotTheAffordances() throws {
        // `strippingComments` rather than `codeOnly` here, and the difference is load-bearing:
        // `codeOnly` blanks string literals too, and every affordance below *is* a string literal —
        // an SF Symbol name. Read through `codeOnly` this test passes vacuously on an empty file.
        let macOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macOSChips))
        #expect(
            CadenceSourceScan.codeOnly(macOS).range(of: "checkmark.circle.fill") == nil,
            "non-vacuity: codeOnly no longer blanks SF Symbol names, so this reader can go back to it"
        )

        for declaration in ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: macOS))
            #expect(body.contains("checkmark.circle.fill"), "\(declaration) lost its completion state")
            #expect(body.contains("xmark.circle.fill"), "\(declaration) lost its cancelled state")
            #expect(
                body.contains("CalendarChipDueMarker"),
                "\(declaration) lost the deadline marker its grid position cannot state"
            )
        }

        for declaration in ["struct MonthEventChip: View", "struct AllDayEventChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: macOS))
            #expect(
                !body.contains("circle.fill"),
                "\(declaration) grew a completion glyph, which belongs to the task and not to the plate"
            )
        }

        // `Theme.dim` is a grey solved against `Theme.bg`; on a solved plate it is the one tint on
        // these chips with no contrast budget at all, so the neutral completion glyph now falls
        // back to the plate's own tertiary tier. The urgency tints and `Theme.green` stayed, which
        // is why this is a ban on one token rather than on colour.
        //
        // Scoped to the four chips rather than to the file: the day-number label and the item
        // count above them draw `Theme.dim` on `Theme.bg`, where it is exactly right, and a
        // file-wide ban would be a claim about the wrong views.
        for declaration in [
            "struct MonthTaskChip: View",
            "struct AllDayTaskChip: View",
            "struct MonthEventChip: View",
            "struct AllDayEventChip: View"
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: macOS))
            #expect(
                CadenceSourceScan.matchCount(#"Theme\.dim"#, in: body) == 0,
                "\(declaration) is reading Theme.dim on a solved plate"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.dim"#, in: macOS) > 0,
            "non-vacuity: Theme.dim is gone from the file entirely, so the scoped zeros say nothing"
        )
        #expect(macOS.contains("Theme.green"), "non-vacuity: the done glyph's tint went with it")
    }
}

// MARK: - Contrast arithmetic

/// WCAG contrast of `foreground` over `background`, optionally with `background` first flattened
/// onto `base` — which is how a wash laid over a plate is measured.
private func t3160Ratio(_ foreground: Color, on background: Color, over base: Color? = nil) -> Double {
    let flatBackground = base.map { t3160Composited(background, over: $0) } ?? background
    let flatForeground = t3160Composited(foreground, over: flatBackground)
    let lighter = max(Theme.relativeLuminance(of: flatForeground), Theme.relativeLuminance(of: flatBackground))
    let darker = min(Theme.relativeLuminance(of: flatForeground), Theme.relativeLuminance(of: flatBackground))
    return (lighter + 0.05) / (darker + 0.05)
}

private func t3160Composited(_ color: Color, over base: Color) -> Color {
    let top = t3160Components(color)
    let under = t3160Components(base)
    return Color(
        .sRGB,
        red: (top.red * top.alpha) + (under.red * (1 - top.alpha)),
        green: (top.green * top.alpha) + (under.green * (1 - top.alpha)),
        blue: (top.blue * top.alpha) + (under.blue * (1 - top.alpha)),
        opacity: 1
    )
}

private func t3160Components(_ color: Color) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), Double(srgb.alphaComponent))
}

/// CIE L* of a WCAG relative luminance. Linear light says nothing about whether a reader can see a
/// step; L* is roughly perceptually uniform, with a just-noticeable difference of about 1.
private func t3160LStar(_ luminance: Double) -> Double {
    luminance > 0.008856 ? 116 * pow(luminance, 1.0 / 3.0) - 16 : 903.3 * luminance
}

private func t3160Rounded(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

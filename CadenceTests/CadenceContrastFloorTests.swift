import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-853: the WCAG floors, computed from `Theme` rather than remembered about it.
///
/// **Every number in this suite is arithmetic over a live token.** There is no table of measured
/// ratios anywhere below, because a table is exactly the thing that goes quietly stale: the audit
/// that produced this ticket recorded six accent ratios that were all correct arithmetic over the
/// wrong pair, and nothing in the repo could tell. A ratio recomputed from `Theme.dim` and
/// `Theme.surfaceHighlight` on every run cannot drift from the tokens; a ratio typed into a doc
/// comment can, and did.
///
/// **Cadence is dark-only.** `Theme.preferredColorScheme` is a hardcoded `.dark`, so the six
/// surface stops below are not half the population — they are all of it. That is asserted here
/// rather than assumed, because the whole sweep is scoped to them.
///
/// Three floors are in play and they are not interchangeable:
///
/// - **4.5:1** — WCAG AA for normal-size text. Cadence draws body copy at 11–15pt, under the 18pt
///   (or 14pt bold) threshold where the large-text exemption starts, so every text stop in the
///   ramp is normal-size text everywhere it appears.
/// - **3:1** — large text, and the non-text contrast floor for UI components.
/// - **no floor** — hairlines, wells and dividers, which carry no information a reader has to
///   resolve. `borderSubtle` through `rule` live here on purpose and this suite says so out loud.
@MainActor
struct CadenceContrastFloorTests {

    // MARK: - The arithmetic itself

    /// A ratio function that agreed with three known answers is worth more than one that agreed
    /// with the app's own numbers, which is circular. `#767676` on white is the canonical WCAG
    /// boundary grey: it is the darkest grey that still clears 4.5:1 on white, so a formula with a
    /// transposed sRGB→linear constant lands visibly off it.
    @Test func theContrastArithmeticAgreesWithWCAGOnPairsWhoseAnswerIsKnown() {
        #expect(abs(t853Ratio(.black, on: .white) - 21) < 0.0001)
        #expect(abs(t853Ratio(.white, on: .white) - 1) < 0.0001)
        #expect(abs(t853Ratio(Color(hex: "#767676"), on: .white) - 4.54) < 0.01)

        // Alpha is composited, not ignored: 50% white over black is a mid grey, not white.
        let halfWhite = t853Ratio(Color.white.opacity(0.5), on: .black)
        let opaqueWhite = t853Ratio(.white, on: .black)
        #expect(halfWhite > 1)
        #expect(halfWhite < opaqueWhite - 10, "an alpha foreground was measured as if it were opaque")

        #expect(Theme.preferredColorScheme == .dark, "non-vacuity: this suite sweeps a dark-only app")
    }

    // MARK: - The body-text ramp

    /// The sweep below claims to cover *the* text ramp. This is the claim that it does.
    ///
    /// `Theme`'s text stops are declared as a contiguous run between `bg`'s surface block and the
    /// `Extended neutral ramp` MARK, and the sweep hardcodes four names. A fifth stop added to that
    /// run — the exact edit that would slip an unmeasured text colour into the app — turns this
    /// red until it is added to `t853BodyTextRamp` and measured with the rest.
    @Test func theBodyTextRampIsExactlyTheFourStopsThisSuiteSweeps() throws {
        let source = try t853ThemeSource()
        let pattern = #"static let (\w+) = Color\(hex:"#

        // Self-check the needle against literal fixtures before trusting it on the tree.
        #expect(CadenceSourceScan.captures(pattern, in: ##"    static let dim = Color(hex: "#878791")"##).map(\.text) == ["dim"])
        #expect(CadenceSourceScan.captures(pattern, in: ##"    static var dim: Color { accents.dim }"##).isEmpty)

        let all = CadenceSourceScan.captures(pattern, in: source).map(\.text)
        #expect(all.count > 10, "non-vacuity: Theme.swift read as \(all.count) hex-declared tokens")

        let start = try #require(all.firstIndex(of: "text"))
        let end = try #require(all.firstIndex(of: "surfaceRecessed"))
        #expect(start < end, "the text ramp no longer precedes the extended neutral ramp")

        #expect(
            Array(all[start..<end]) == t853BodyTextRamp.map(\.name),
            "Theme's text ramp is \(Array(all[start..<end])) but this suite sweeps \(t853BodyTextRamp.map(\.name))"
        )
    }

    /// **The deliverable.** Every stop a reader is expected to read words in, against every surface
    /// those words can land on.
    ///
    /// T-847 measured `dim` at 4.12 / 3.84 / 3.59 / 3.40 against the four main stops — under the
    /// floor on all four, and worse than that on the two extended stops the audit did not look at.
    /// It is the reason this suite exists and the first thing it caught.
    @Test func everyBodyTextStopClearsFourAndAHalfToOneOnEverySurfaceStop() {
        #expect(t853BodyTextRamp.count == 4, "non-vacuity: the text ramp is still four stops")
        #expect(t853Surfaces.count == 6, "non-vacuity: the surface ramp is still six stops")

        for surface in t853Surfaces {
            #expect(
                t853Luminance(surface.color) < 0.02,
                "non-vacuity: Theme.\(surface.name) is no longer a near-black surface"
            )
        }

        for stop in t853BodyTextRamp {
            for surface in t853Surfaces {
                let ratio = t853Ratio(stop.color, on: surface.color)
                #expect(
                    ratio >= 4.5,
                    "Theme.\(stop.name) reads at \(t853Rounded(ratio)):1 on Theme.\(surface.name), under the 4.5:1 floor for normal text"
                )
            }
        }
    }

    /// A ramp is four stops only if they are four *different* stops. Raising `dim` to clear the
    /// floor is one edit away from raising it onto `subdued`, at which point the app has three text
    /// colours and a spare — so the separation is pinned in the same breath as the floor.
    @Test func theBodyTextRampStaysOrderedAndVisiblySeparated() {
        let onBackground = t853BodyTextRamp.map { (name: $0.name, ratio: t853Ratio($0.color, on: Theme.bg)) }
        #expect(onBackground.first?.name == "text")
        #expect(onBackground.last?.name == "dim")

        for (brighter, dimmer) in zip(onBackground, onBackground.dropFirst()) {
            #expect(
                brighter.ratio > dimmer.ratio,
                "Theme.\(brighter.name) is no brighter than Theme.\(dimmer.name) on Theme.bg"
            )
            #expect(
                brighter.ratio - dimmer.ratio > 0.5,
                "Theme.\(brighter.name) and Theme.\(dimmer.name) are \(t853Rounded(brighter.ratio - dimmer.ratio)) apart on Theme.bg — too close to read as two stops"
            )
        }
    }

    /// The other half of the split. `borderSubtle` through `rule` are hairlines, not text, and the
    /// 4.5:1 floor does not apply to them — which is only an honest position while none of them is
    /// bright enough to be mistaken for a text stop and pressed into service as one.
    @Test func theStructuralNeutralsAreOrderedAndStayWellClearOfTheTextRamp() {
        let structural = t853StructuralNeutrals
        #expect(structural.count == 4, "non-vacuity: the structural ramp is still four stops")

        let luminances = structural.map { t853Luminance($0.color) }
        for (lower, upper) in zip(luminances, luminances.dropFirst()) {
            #expect(upper > lower, "the structural ramp is no longer monotonic")
        }

        let dimmestText = t853BodyTextRamp.map { t853Ratio($0.color, on: Theme.bg) }.min() ?? 0
        for stop in structural {
            let ratio = t853Ratio(stop.color, on: Theme.bg)
            #expect(
                ratio < 3,
                "Theme.\(stop.name) reads at \(t853Rounded(ratio)):1 on Theme.bg — bright enough to be mistaken for a text stop, so it needs to be measured as one"
            )
            #expect(ratio < dimmestText, "Theme.\(stop.name) outranks the dimmest text stop")
        }
    }

    // MARK: - The marker highlight

    /// T-848 measured highlighted markdown text at 1.48:1 and called it unreadable. The arithmetic
    /// was right and the pair was wrong: `Theme.markerHighlightAccent` (the raw pen hue) is never
    /// drawn opaque behind `markerHighlightText` — the editor used to fill the highlight rect at a
    /// fraction of alpha over a near-black text view, so what a reader actually saw was
    /// `markerHighlightText` on that composite, around 7:1, not 1.48:1. T-856 found the alpha was
    /// therefore load-bearing for legibility and lived nowhere Theme-adjacent — a second drawer
    /// (`MarkdownTaskEmbedDrawingSupport`) already reused the raw accent for an unrelated chip
    /// tint, and a third one reaching for "the fill" and painting it opaque would have shipped
    /// unreadable text with nothing going red.
    ///
    /// **So the composite is what `Theme` now offers as `markerHighlightFill`.** The alpha moved
    /// into `Theme.swift`'s own `markerHighlightFillAlpha` and is baked into `markerHighlightFill`
    /// at declaration, pre-flattened to an opaque colour — `MarkdownEditorLayoutManager` paints it
    /// with a bare `.setFill()`, no alpha of its own left to drift. This test therefore measures
    /// `Theme.markerHighlightText` directly against `Theme.markerHighlightFill`, with no alpha
    /// parameter to read out of the drawing code, because there no longer is one there to read.
    @Test func theMarkerHighlightFillIsPreCompositedAndStaysLegibleWithItsText() throws {
        // The fill is opaque by construction now — not a wash a caller still has to attenuate.
        let fillComponents = t853Components(Theme.markerHighlightFill)
        #expect(fillComponents.a == 1, "Theme.markerHighlightFill is no longer fully opaque")

        // And it is not simply the raw accent re-exported under a new name — compositing actually
        // happened. Rather than remember the alpha (the exact trap this ticket is about — a copy
        // of `0.38` sitting in this file would drift from `Theme`'s exactly the way the drawing
        // code's copy used to), this checks the invariant every alpha blend must satisfy: each
        // channel of the result lies between the same channel of the two colours it was mixed
        // from, and — because `Theme.bg` is near-black and the accent is a saturated yellow, not
        // equal on any channel — strictly between rather than at either end.
        let accentComponents = t853Components(Theme.markerHighlightAccent)
        let bgComponents = t853Components(Theme.bg)
        for (channel, fill, accent, bg) in [
            ("red", fillComponents.r, accentComponents.r, bgComponents.r),
            ("green", fillComponents.g, accentComponents.g, bgComponents.g),
            ("blue", fillComponents.b, accentComponents.b, bgComponents.b),
        ] {
            let lower = min(accent, bg), upper = max(accent, bg)
            #expect(
                fill > lower && fill < upper,
                "Theme.markerHighlightFill's \(channel) channel (\(fill)) is not strictly between the accent's (\(accent)) and Theme.bg's (\(bg)) — not a genuine partial blend of the two"
            )
        }

        let painted = t853Ratio(Theme.markerHighlightText, on: Theme.markerHighlightFill)
        #expect(
            painted >= 4.5,
            "highlighted markdown text reads at \(t853Rounded(painted)):1 against Theme.markerHighlightFill"
        )

        // And the pen still reads as a pen: the fill has to lift off the page it is drawn on.
        let lift = t853Ratio(Theme.markerHighlightFill, on: Theme.bg)
        #expect(lift > 1.5, "the highlight fill no longer separates from Theme.bg")

        // The surface underneath the editor is still the text view's own background: the composite
        // was baked assuming `Theme.bg`, and this is what would silently invalidate that.
        let editor = try t853Source("Cadence/macOS/Editor/MarkdownEditorView.swift")
        let backgrounds = CadenceSourceScan.captures(#"textView\.backgroundColor = Theme\.(\w+)"#, in: editor).map(\.text)
        #expect(backgrounds == ["nsBg"], "the markdown text view now draws on \(backgrounds), not Theme.nsBg")
    }

    /// The drawing code reads the pre-composited swatch and nothing else: no `.withAlphaComponent`
    /// reintroduced beside it, which would double up on top of the alpha now baked into
    /// `Theme.markerHighlightFill` and quietly wash the highlight out again.
    @Test func theLayoutManagerPaintsTheCompositeWithNoAlphaOfItsOwn() throws {
        let drawing = try t853Source("Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift")
        #expect(
            CadenceSourceScan.matchCount(#"highlightFillColor\.setFill\(\)"#, in: drawing) == 1,
            "expected exactly one bare `highlightFillColor.setFill()`"
        )
        #expect(
            CadenceSourceScan.matchCount(#"highlightFillColor\.withAlphaComponent"#, in: drawing) == 0,
            "the layout manager re-applies its own alpha on top of the pre-composited fill"
        )
    }

    /// The one other reader of the marker-highlight hue (`MarkdownTaskEmbedDrawingSupport`'s
    /// scheduled/priority chips) reads the raw accent, not the text-legible composite — reading
    /// `highlightFillColor` there would silently wash the chip tint out toward `Theme.bg`.
    @Test func theTaskEmbedChipsReadTheRawAccentNotTheComposite() throws {
        let drawing = try t853Source("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift")
        #expect(
            CadenceSourceScan.matchCount(#"\bhighlightFillColor\b"#, in: drawing) == 0,
            "MarkdownTaskEmbedDrawingSupport now reads the pre-composited fill for a non-text-background use"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\bhighlightAccentColor\b"#, in: drawing) == 2,
            "expected exactly the two known chip/priority call sites"
        )
    }

    // MARK: - White on a saturated fill

    /// T-848's six "accent palette" ratios, correctly attributed. They are not the accents failing
    /// as foregrounds — `everyHueIsLightEnoughToReadOnTheAppBackground` already holds every hue
    /// above 4.5:1 on `Theme.bg`, and it passes. They are `Theme.onColor`, which is plain white,
    /// measured on an accent **fill**: a filled calendar block, a selected day cell, an accent
    /// button.
    ///
    /// That failure is real and it is recorded rather than fixed, because fixing it is not an
    /// accent-palette change — see T-855. Both halves are asserted:
    ///
    /// - white on the fill is under the floor for **every** hue in **every** set, so a palette
    ///   edit that fixed one comes back here and says so;
    /// - `Theme.bg` as the ink clears the floor on every one of them, which is the evidence for
    ///   T-855's proposal and stays true independently of what white does.
    @Test func whiteOnAnAccentFillFailsEveryHueWhileDarkInkClearsThemAll() {
        var measured = 0
        for palette in CadenceAccentPalette.all {
            for hex in palette.swatchHexes {
                let fill = Color(hex: hex)
                measured += 1

                let white = t853Ratio(Theme.onColor, on: fill)
                #expect(
                    white < 4.5,
                    "\(palette.id) \(hex) now carries Theme.onColor at \(t853Rounded(white)):1 — T-855's exception list is stale, update it"
                )

                let ink = t853Ratio(Theme.bg, on: fill)
                #expect(
                    ink >= 4.5,
                    "\(palette.id) \(hex) reads at \(t853Rounded(ink)):1 under Theme.bg ink — T-855's proposal no longer covers it"
                )
                #expect(ink > white, "\(palette.id) \(hex) is now better served by white than by dark ink")
            }
        }
        #expect(measured == 18, "non-vacuity: three sets of six, \(measured) measured")
        #expect(t853Ratio(Theme.onColor, on: Theme.bg) > 15, "non-vacuity: Theme.onColor is still near-white")
    }

    // MARK: - T-855: the ink is a function of the fill

    /// `Theme.relativeLuminance(of:)` is the app's own copy of the arithmetic this suite already
    /// trusts, so the two are checked against each other before anything is built on top of it.
    ///
    /// A second implementation is not duplication here, it is the point: the suite's copy is
    /// deliberately written from the WCAG text and the app's is written against SwiftUI's
    /// `Color.Resolved`, and a transposed constant or a linear-vs-gamma mix-up in either shows up
    /// as a disagreement rather than as two files agreeing on the same mistake.
    @Test func themeRelativeLuminanceAgreesWithThisSuitesOwnWCAGArithmetic() {
        var compared = 0
        for hex in ["#000000", "#ffffff", "#767676", "#09090b", "#4a9eff", "#ffc857", "#6366f1"] {
            let color = Color(hex: hex)
            compared += 1
            #expect(
                abs(Theme.relativeLuminance(of: color) - t853Luminance(color)) < 0.000_01,
                "Theme.relativeLuminance disagrees with WCAG on \(hex): \(Theme.relativeLuminance(of: color)) vs \(t853Luminance(color))"
            )
        }
        #expect(compared == 7, "non-vacuity: \(compared) colours compared")

        // A wash has no luminance until it is told what it is under, and `Theme` says `bg`.
        let wash = Color.white.opacity(0.5)
        #expect(
            abs(Theme.relativeLuminance(of: wash) - t853Luminance(t853Composited(wash, over: Theme.bg))) < 0.000_01,
            "an alpha colour was measured as if it were opaque"
        )
        #expect(Theme.relativeLuminance(of: wash) < Theme.relativeLuminance(of: .white))
    }

    /// **`Theme.onColorCrossoverLuminance` is solved, not tuned** — the sentence in T-855 that said
    /// "the threshold is the only tunable, and it is the part to look at" is answered by there not
    /// being one to tune.
    ///
    /// Recomputed here from `Theme.bg` by this suite's own arithmetic rather than copied from
    /// `Theme`, and then checked behaviourally: at a fill of exactly that luminance the two inks
    /// read the *same* ratio, which is what "crossover" has to mean for the comparison in
    /// `onColor(for:)` to be the right one. A threshold nudged to a rounder number fails both arms.
    @Test func theOnColorCrossoverIsSolvedFromTheAppBackgroundRatherThanTuned() {
        let solved = (1.05 * (t853Luminance(Theme.bg) + 0.05)).squareRoot() - 0.05
        #expect(
            abs(Theme.onColorCrossoverLuminance - solved) < 0.000_001,
            "Theme.onColorCrossoverLuminance is \(Theme.onColorCrossoverLuminance), but solving 1.05/(Y+0.05) = (Y+0.05)/(L(bg)+0.05) gives \(solved)"
        )

        let crossoverFill = t853Grey(luminance: Theme.onColorCrossoverLuminance)
        let white = t853Ratio(Theme.onColor, on: crossoverFill)
        let ink = t853Ratio(Theme.bg, on: crossoverFill)
        #expect(
            abs(white - ink) < 0.001,
            "at the crossover white reads \(t853Rounded(white)):1 and Theme.bg reads \(t853Rounded(ink)):1 — not a crossover"
        )

        // The worst case the whole scheme can produce. Over the 3:1 floor for large text and for
        // non-text UI components, and just under the 4.5:1 one — which is the honest cost of
        // keeping every accent hue exactly where the user chose it.
        #expect(white > 3, "the crossover ratio \(t853Rounded(white)):1 no longer clears the 3:1 non-text floor")
        #expect(white < 4.5, "non-vacuity: the crossover is still the pinch point, not a comfortable pair")
    }

    /// **The deliverable for T-855.** `onColor(for:)` returns the better of the two inks at *every*
    /// fill luminance, and the ratio it delivers never drops below the crossover ratio.
    ///
    /// Swept over greys rather than over the palette, on purpose: a sweep over the eighteen
    /// accents would pass for a function that returned `Theme.bg` unconditionally, because all
    /// eighteen sit above the crossover. The greys walk both sides of it, so the white arm is
    /// exercised too — and the hues afterwards check that the decision is luminance-driven rather
    /// than accidentally right on a neutral.
    @Test func onColorForPicksTheBetterInkAtEveryFillLuminance() {
        let floor = 1.05 / (Theme.onColorCrossoverLuminance + 0.05)
        var sawWhite = 0, sawInk = 0

        var fills: [Color] = (0...200).map { t853Grey(luminance: Double($0) / 200) }
        fills += ["#001133", "#6366f1", "#4a9eff", "#ffc857", "#3d0000", "#00391f", "#e879f9"].map { Color(hex: $0) }

        for fill in fills {
            let chosen = Theme.onColor(for: fill)
            let other = chosen == Theme.bg ? Theme.onColor : Theme.bg
            if chosen == Theme.bg { sawInk += 1 } else { sawWhite += 1 }

            let chosenRatio = t853Ratio(chosen, on: fill)
            #expect(
                chosenRatio >= t853Ratio(other, on: fill) - 0.000_001,
                "Theme.onColor(for:) picked the worse ink on a fill at luminance \(t853Rounded(Theme.relativeLuminance(of: fill)))"
            )
            #expect(
                chosenRatio >= floor - 0.000_001,
                "Theme.onColor(for:) delivered \(t853Rounded(chosenRatio)):1, under the \(t853Rounded(floor)):1 the crossover guarantees"
            )
        }

        #expect(sawWhite > 20, "non-vacuity: the white arm was taken \(sawWhite) times")
        #expect(sawInk > 20, "non-vacuity: the dark-ink arm was taken \(sawInk) times")
    }

    /// Every colour the app *offers* as a fill, under the ink `onColor(for:)` chooses for it.
    ///
    /// Wider than `whiteOnAnAccentFillFailsEveryHueWhileDarkInkClearsThemAll`'s eighteen accents,
    /// because an accent is not the only thing that ends up as a solid plate with a glyph on it:
    /// a list, goal, habit or context `colorHex` fills the focus button and the habit widget cell,
    /// a kanban section colour fills its header, and a tag colour fills its chip.
    ///
    /// **One of them cannot reach 4.5:1 with either ink, and it is named rather than rounded away.**
    /// `#6366f1` in `CadenceColorPalette.colors` sits at luminance 0.1851, three ten-thousandths
    /// under the crossover, so its best available pair is 4.47:1. It is left where it is
    /// deliberately: it is a *stored user value*, and `CadenceColorPalette.offered(_:from:)` would
    /// then append a user's saved `#6366f1` as a thirteenth swatch beside its replacement — the
    /// T-245 shape. A 0.7% shortfall on one swatch does not buy that. See T-1056.
    ///
    /// **T-1089 settled that as the verdict and left the exemption by *name*, on purpose.** The
    /// property version of it — "exempt any fill inside the dead band" — reads better and is worse:
    /// it would silently exempt the *next* swatch added into the band, which is the one case this
    /// test exists to catch. `theTwoInkSchemeHasOneDeadBandAndExactlyOneOfferedFillSitsInIt` is
    /// where the band itself is measured, and it is that test, not this one, that would go red if a
    /// second unservable hue were offered.
    @Test func everyFillTheAppOffersClearsAAUnderTheInkOnColorForChooses() {
        let exempt = "#6366f1"
        var offered: Set<String> = []
        for palette in CadenceAccentPalette.all { offered.formUnion(palette.swatchHexes) }
        offered.formUnion(CadenceColorPalette.colors)
        offered.formUnion(CadenceColorPalette.sectionColors)
        offered.formUnion(CadenceColorPalette.destinationTints)
        offered.formUnion(TagSupport.colorOptions)
        offered.formUnion(TagSupport.defaultTags.map(\.colorHex))
        offered.insert(TaskSectionDefaults.defaultColorHex)

        #expect(offered.count > 30, "non-vacuity: \(offered.count) distinct offered fills")
        #expect(offered.contains { $0.caseInsensitiveCompare(exempt) == .orderedSame }, "the exempt swatch is no longer offered — drop the exemption")

        let crossoverRatio = 1.05 / (Theme.onColorCrossoverLuminance + 0.05)
        for hex in offered.sorted() {
            let fill = Color(hex: hex)
            let ratio = t853Ratio(Theme.onColor(for: fill), on: fill)
            let required = hex.caseInsensitiveCompare(exempt) == .orderedSame ? crossoverRatio : 4.5
            #expect(
                ratio >= required - 0.000_001,
                "\(hex) carries its chosen ink at \(t853Rounded(ratio)):1, under \(t853Rounded(required)):1"
            )
        }
    }

    /// **The band a two-ink scheme cannot serve at all, and the census of what sits in it (T-1089).**
    ///
    /// `onColor(for:)` chooses between exactly two inks, so a fill's best available contrast is
    /// `max(white, bg)` — and that maximum has a minimum. White fails 4.5:1 above
    /// `1.05/4.5 − 0.05`; `bg` fails 4.5:1 below `4.5·(L(bg)+0.05) − 0.05`. Between those two
    /// numbers **neither ink clears AA**, and no threshold, rounding or call-site fix can change
    /// that: the crossover is *solved* from `bg` rather than tuned, and 4.46:1 at the crossover is
    /// the arithmetic best the scheme can do at the worst fill luminance.
    ///
    /// So `#6366f1`'s shortfall is not a defect in a swatch, it is one swatch standing in a window
    /// **0.0042 of luminance wide** — about 2% of the value — that the scheme was always going to
    /// have. This is the honest form of the exemption: the shortfall is bounded, it is bounded by
    /// the scheme rather than by a choice, and exactly one of the app's thirty-odd offered fills is
    /// in it. Adding a second is what would need a decision, and that is what this test refuses.
    ///
    /// **The two ways out and what they cost, since this test is where the numbers are.** Nudging
    /// the hex needs one step of green — `#6365f1` clears at 4.5043:1 — a change no eye can see;
    /// its whole cost is that every user who ever picked indigo keeps `#6366f1` in
    /// `Area.colorHex`/`Project.colorHex`, and `offered(_:from:)` then draws it as a thirteenth
    /// swatch beside a twin, on every synced device, forever. And 4.5043 is a 0.1% margin: the
    /// upper edge below **moves with `bg`**, so the nudge is not even durable. Closing the band
    /// instead means darkening `bg` past `L ≤ 0.00185` — roughly `#09090b` → `#060607` — which
    /// drags the whole neutral ramp to fix one swatch. Both are larger than 0.033 of a ratio.
    @Test func theTwoInkSchemeHasOneDeadBandAndExactlyOneOfferedFillSitsInIt() {
        // White is a constant, so its edge is one too. `bg`'s edge is not: it follows the ramp,
        // which is the same reason `onColorCrossoverLuminance` is solved rather than stored.
        let whiteFails = 1.05 / 4.5 - 0.05
        let inkFails = 4.5 * (Theme.relativeLuminance(of: Theme.bg) + 0.05) - 0.05
        #expect(whiteFails < inkFails, "the band has closed — every fill now clears AA with one ink, so drop the exemption")
        #expect(abs((inkFails - whiteFails) - 0.004_159) < 0.000_01, "the band is \(inkFails - whiteFails) wide, not 0.0042")
        #expect(
            whiteFails < Theme.onColorCrossoverLuminance && Theme.onColorCrossoverLuminance < inkFails,
            "non-vacuity: the crossover is not inside the band the crossover defines"
        )

        var offered: Set<String> = []
        for palette in CadenceAccentPalette.all { offered.formUnion(palette.swatchHexes) }
        offered.formUnion(CadenceColorPalette.colors)
        offered.formUnion(CadenceColorPalette.sectionColors)
        offered.formUnion(CadenceColorPalette.destinationTints)
        offered.formUnion(TagSupport.colorOptions)
        offered.formUnion(TagSupport.defaultTags.map(\.colorHex))
        offered.insert(TaskSectionDefaults.defaultColorHex)
        #expect(offered.count > 30, "non-vacuity: \(offered.count) distinct offered fills")

        let inBand = offered.filter { hex in
            let luminance = Theme.relativeLuminance(of: Color(hex: hex))
            return luminance > whiteFails && luminance < inkFails
        }
        #expect(
            inBand.map { $0.lowercased() }.sorted() == ["#6366f1"],
            """
            the fills no ink can carry to 4.5:1 are \(inBand.sorted()). One of them is T-1089's,             argued and kept; a second is a new decision, not a rounding error — and the palette             has \(String(format: "%.4f", inkFails - whiteFails)) of luminance to avoid, not a point
            """
        )
    }

    /// The three fills the app *solves* rather than takes raw stay under the crossover, which is
    /// what entitles `CadenceCalendarEventStyle.primaryLabelColor` and the two month chips to keep
    /// reaching for the bare `Theme.onColor` constant.
    ///
    /// Without this, "white unconditionally" is a claim about a number in another file that
    /// nothing connects to the ink: raise `fillLuminance`'s selected stop past the crossover and
    /// event titles quietly become the worst-contrast text in the app, with every accent test in
    /// this file still green.
    @Test func theSolvedCalendarFillsStayBelowTheCrossoverSoTheirWhiteInkIsRight() {
        var measured = 0
        // Includes the two brightest hues the palettes ship, which is where a luminance solve is
        // most likely to be overrun, plus a raw white calendar.
        for hex in ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000"] {
            for (selected, active) in [(false, false), (false, true), (true, false)] {
                measured += 1
                let fill = CadenceCalendarEventStyle.fill(for: Color(hex: hex), isSelected: selected, isActive: active)
                #expect(
                    Theme.relativeLuminance(of: fill) < Theme.onColorCrossoverLuminance,
                    "a solved event fill for \(hex) (selected: \(selected), active: \(active)) is past the crossover, so its label must stop being unconditional white"
                )
                #expect(Theme.onColor(for: fill) == Theme.onColor)
                #expect(t853Ratio(CadenceCalendarEventStyle.primaryLabelColor, on: fill) >= 4.5)
            }
        }
        #expect(measured == 15, "non-vacuity: five hues in three states, \(measured) measured")

        // The same guard on the luminance targets themselves, independent of any hue.
        for target in [
            CadenceCalendarEventStyle.fillLuminance(),
            CadenceCalendarEventStyle.fillLuminance(isActive: true),
            CadenceCalendarEventStyle.fillLuminance(isSelected: true),
        ] {
            #expect(target < Theme.onColorCrossoverLuminance, "the \(target) fill target is past the crossover")
        }
    }

    /// What is still allowed to say `Theme.onColor` without asking which fill it lands on.
    ///
    /// The migration is only durable if the *next* accent-filled button is caught, and the whole
    /// failure mode of T-855 was that a constant looked like an answer. So the residue is
    /// enumerated: five files, each with a stated reason, and a sixth goes red here.
    @Test func theOnlyBareThemeOnColorLeftInTheProductTreeIsSolvedOrBrandLocked() throws {
        let instrument = try CadenceScanInstrument(
            "Theme.onColor read as a constant rather than asked for a fill",
            fires: """
            Text(title)
                .foregroundStyle(Theme.onColor)
                .background(Theme.blue)
            """,
            // The nearest look-alikes, all of which must be left alone: the fixed call, and the
            // secondary/border tiers, whose names begin with the same eight characters.
            andNotOn: """
            Text(title)
                .foregroundStyle(Theme.onColor(for: tint))
                .background(tint)
                .overlay(Capsule().strokeBorder(Theme.onColorBorder))
                .shadow(color: Theme.onColorSecondary, radius: 1)
            """,
            by: { CadenceSourceScan.matchCount(#"Theme\.onColor(?![A-Za-z(])"#, in: CadenceSourceScan.codeOnly($0)) > 0 }
        )

        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/Shared/Theme.swift",
            read: { try CadenceSourceScan.sourceFile($0) }
        )

        // Sorted, and `sweep` sorts by path: `Shared` precedes `macOS` because `S` precedes `m`.
        #expect(hits == [
            // The solved event fill itself, which is why it is solved.
            "Cadence/Shared/CadenceCalendarEventStyle.swift",
            // The fill is `CalendarEventVisualStyle.chipFill`, solved under the crossover.
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
            // Sign in with Apple: a brand-locked black fill with a mandated white label.
            "Cadence/macOS/Views/SettingsSectionViews.swift",
            // A white *wash* laid over a block, not ink read against one.
            "Cadence/macOS/Views/TimelineEventBlock.swift",
            "Cadence/macOS/Views/TimelineHoverVisuals.swift",
        ], "the set of files still reading Theme.onColor as a constant changed: \(hits)")
    }
}

/// An opaque grey whose WCAG relative luminance is `luminance`, by inverting the sRGB transfer
/// function. Greys are what a luminance sweep needs: for any target there is exactly one, so the
/// sweep walks luminance itself rather than a hue that happens to pass through it.
private func t853Grey(luminance: Double) -> Color {
    let clamped = min(max(luminance, 0), 1)
    let channel = clamped <= 0.003_130_8 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    return Color(.sRGB, red: channel, green: channel, blue: channel, opacity: 1)
}

// MARK: - Tokens under test

private let t853BodyTextRamp: [(name: String, color: Color)] = [
    ("text", Theme.text),
    ("muted", Theme.muted),
    ("subdued", Theme.subdued),
    ("dim", Theme.dim),
]

/// Every stop a body-text colour can be drawn on, brightest last. The four the audit used plus the
/// two extended stops it did not: `surfaceHover` and `surfaceHighlight` are lighter than
/// `surfaceElevated`, so a token that only clears the floor on the audited four still fails in a
/// hovered row.
private let t853Surfaces: [(name: String, color: Color)] = [
    ("bg", Theme.bg),
    ("surfaceRecessed", Theme.surfaceRecessed),
    ("surface", Theme.surface),
    ("surfaceHover", Theme.surfaceHover),
    ("surfaceElevated", Theme.surfaceElevated),
    ("surfaceHighlight", Theme.surfaceHighlight),
]

private let t853StructuralNeutrals: [(name: String, color: Color)] = [
    ("borderSubtle", Theme.borderSubtle),
    ("border", Theme.border),
    ("borderStrong", Theme.borderStrong),
    ("rule", Theme.rule),
]

// MARK: - WCAG arithmetic

private func t853Components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent)
}

/// WCAG 2.x relative luminance of an **already-flattened** colour.
///
/// Alpha is not consulted here on purpose: `Theme` spells several of its jobs as a wash, and a
/// wash has no luminance until it is told what it is painted on. `t853Ratio` flattens through
/// `t853Composited` before calling this, so an alpha value reaching this function opaque-by-default
/// is a caller bug rather than a silent approximation.
private func t853Luminance(_ color: Color) -> Double {
    let (r, g, b, _) = t853Components(color)
    let linear = [r, g, b].map { channel in
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
}

/// `foreground` on `background`, with `over` naming what `background` itself is painted on when it
/// is a wash rather than an opaque stop.
///
/// Both operands are flattened before they are measured, innermost first: the background onto
/// `over`, then the foreground onto that. A pair where either side carries alpha has no single
/// ratio until it is told what is underneath.
private func t853Ratio(_ foreground: Color, on background: Color, over base: Color? = nil) -> Double {
    let flatBackground = base.map { t853Composited(background, over: $0) } ?? background
    let flatForeground = t853Composited(foreground, over: flatBackground)
    let lighter = max(t853Luminance(flatForeground), t853Luminance(flatBackground))
    let darker = min(t853Luminance(flatForeground), t853Luminance(flatBackground))
    return (lighter + 0.05) / (darker + 0.05)
}

/// `color` flattened onto `base`, as an opaque `Color`.
private func t853Composited(_ color: Color, over base: Color) -> Color {
    let top = t853Components(color)
    let under = t853Components(base)
    return Color(
        .sRGB,
        red: top.r * top.a + under.r * (1 - top.a),
        green: top.g * top.a + under.g * (1 - top.a),
        blue: top.b * top.a + under.b * (1 - top.a),
        opacity: 1
    )
}

private func t853Rounded(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

// MARK: - Source reading

private func t853ThemeSource() throws -> String {
    try t853Source("Cadence/Shared/Theme.swift")
}

/// Comments blanked to spaces of equal length, so offsets still point where they did and a
/// declaration quoted inside a doc comment is not counted as a declared token.
private func t853Source(_ path: String) throws -> String {
    let raw = try CadenceSourceScan.sourceFile(path)
    #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
    let stripped = CadenceSourceScan.strippingComments(raw)
    #expect(stripped.count == raw.count, "\(path): the stripper changed the length")
    #expect(stripped != raw, "\(path): nothing was stripped, so the stripper is not running")
    return stripped
}

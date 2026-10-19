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

    /// The three **plate** fills the app *solves* rather than takes raw stay under the crossover,
    /// which is what entitles `CadenceCalendarEventStyle.platePrimaryLabelColor` and the two month
    /// chips to keep reaching for the bare `Theme.onColor` constant.
    ///
    /// Without this, "white unconditionally" is a claim about a number in another file that
    /// nothing connects to the ink: raise `plateLuminance`'s selected stop past the crossover and
    /// plate titles quietly become the worst-contrast text in the app, with every accent test in
    /// this file still green.
    ///
    /// T-3160 moved this treatment from events to tasks and gave it `plate*` names. The legacy
    /// unprefixed spellings are still live for un-renamed call sites, so this also pins that the
    /// two spellings are the *same* solve rather than two that happen to agree today.
    @Test func theSolvedCalendarFillsStayBelowTheCrossoverSoTheirWhiteInkIsRight() {
        var measured = 0
        // Includes the two brightest hues the palettes ship, which is where a luminance solve is
        // most likely to be overrun, plus a raw white calendar.
        for hex in ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000"] {
            for (selected, active) in [(false, false), (false, true), (true, false)] {
                measured += 1
                let swatch = Color(hex: hex)
                let fill = CadenceCalendarEventStyle.plateFill(for: swatch, isSelected: selected, isActive: active)
                #expect(
                    Theme.relativeLuminance(of: fill) < Theme.onColorCrossoverLuminance,
                    "a solved plate fill for \(hex) (selected: \(selected), active: \(active)) is past the crossover, so its label must stop being unconditional white"
                )
                #expect(Theme.onColor(for: fill) == Theme.onColor)
                #expect(t853Ratio(CadenceCalendarEventStyle.platePrimaryLabelColor, on: fill) >= 4.5)

                // The legacy spelling is the same solve, not a second one.
                let legacy = CadenceCalendarEventStyle.fill(for: swatch, isSelected: selected, isActive: active)
                #expect(
                    abs(Theme.relativeLuminance(of: legacy) - Theme.relativeLuminance(of: fill)) < 0.0005,
                    "fill(for:) and plateFill(for:) have drifted apart at \(hex)"
                )
            }
        }
        #expect(measured == 15, "non-vacuity: five hues in three states, \(measured) measured")
        #expect(CadenceCalendarEventStyle.primaryLabelColor == CadenceCalendarEventStyle.platePrimaryLabelColor)
        #expect(CadenceCalendarEventStyle.fillSaturationScale == CadenceCalendarEventStyle.plateSaturationScale)

        // The same guard on the luminance targets themselves, independent of any hue.
        for target in [
            CadenceCalendarEventStyle.plateLuminance(),
            CadenceCalendarEventStyle.plateLuminance(isActive: true),
            CadenceCalendarEventStyle.plateLuminance(isSelected: true),
        ] {
            #expect(target < Theme.onColorCrossoverLuminance, "the \(target) plate target is past the crossover")
            #expect(
                CadenceCalendarEventStyle.fillLuminance(
                    isSelected: target == CadenceCalendarEventStyle.plateLuminance(isSelected: true),
                    isActive: target == CadenceCalendarEventStyle.plateLuminance(isActive: true)
                ) == target,
                "fillLuminance stopped forwarding to plateLuminance at \(target)"
            )
        }
    }

    /// The **plate** treatment's secondary tier — the time range and calendar name — measured
    /// rather than remembered, and with the one case that does not clear AA named out loud.
    ///
    /// At rest the tier is `Theme.onColorSecondary`, a 0.75 wash of white, and 0.098 was chosen as
    /// the rest fill precisely so that it clears 4.5:1 there. It does — for every hue whose own
    /// luminance is at or above the fill it is solved into. A hue *darker* than its own plate, a
    /// near-black `#3d0000` being the example that exists, composites a more saturated colour
    /// through the wash and lands at 4.46:1: short of AA by 0.04, and short of it before T-3160
    /// too. This is recorded, not silently swept, because the fix is a `Theme` token change and
    /// this ticket is a paint swap. The active and selected states are unaffected: both lift the
    /// tier to full `Theme.onColor`, which is why the ladder exists.
    @Test func thePlateSecondaryTierClearsAAExceptOnAHueDarkerThanItsOwnPlate() {
        var measured = 0
        var exempted: [String] = []
        for hex in ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000"] {
            let swatch = Color(hex: hex)
            let restFill = CadenceCalendarEventStyle.plateFill(for: swatch)
            let restRatio = t853Ratio(CadenceCalendarEventStyle.plateSecondaryLabelColor(), on: restFill)
            measured += 1
            if Theme.relativeLuminance(of: swatch) >= CadenceCalendarEventStyle.plateLuminance() {
                #expect(
                    restRatio >= 4.5,
                    "\(hex) is lighter than its own plate and still misses AA at \(t853Rounded(restRatio)):1"
                )
            } else {
                exempted.append(hex)
                #expect(
                    restRatio >= 4.4,
                    "\(hex) fell further than the recorded 4.46:1 shortfall, to \(t853Rounded(restRatio)):1"
                )
            }

            for (selected, active) in [(false, true), (true, false)] {
                measured += 1
                let fill = CadenceCalendarEventStyle.plateFill(for: swatch, isSelected: selected, isActive: active)
                let tier = CadenceCalendarEventStyle.plateSecondaryLabelColor(isSelected: selected, isActive: active)
                #expect(tier == CadenceCalendarEventStyle.platePrimaryLabelColor)
                #expect(t853Ratio(tier, on: fill) >= 4.5)
            }
        }
        #expect(measured == 15, "non-vacuity: five hues in three states, \(measured) measured")
        #expect(
            exempted == ["#3d0000"],
            "the set of hues darker than their own plate changed: \(exempted)"
        )
    }

    /// T-3160's **rail** treatment: Apple Calendar's look, where the title is in the calendar's own
    /// hue instead of in white.
    ///
    /// This is the assertion that treatment is *solvable*, not merely implemented. A title in the
    /// hue has a far tighter budget than `Theme.onColor` did — white is Y = 1 and nothing in the
    /// gamut can be asked for more — so every tier here is solved to a stated ratio against the
    /// plate it actually lands on, and this measures the ratio that came back rather than checking
    /// that a function exists.
    ///
    /// Each tier is solved, not clamped, which is why the measured ratio should land *on* its
    /// declared target for every hue including the degenerate ones: a pure-black calendar has no
    /// chroma to spend and resolves to a grey of the right luminance, a pure-blue one cannot reach
    /// the target with its chroma intact and is desaturated to exactly the point where it does.
    /// Both are in the sweep because both are reachable through a user-chosen `colorHex`.
    @Test func everyRailTreatmentTierLandsOnItsDeclaredRatioAgainstItsOwnPlate() {
        let tiers: [(name: String, target: Double, floor: Double, color: (Color, Bool, Bool) -> Color)] = [
            ("title", CadenceCalendarEventStyle.railTitleContrastTarget, 4.5, {
                CadenceCalendarEventStyle.railTitleColor(for: $0, isSelected: $1, isActive: $2)
            }),
            ("secondary", CadenceCalendarEventStyle.railSecondaryContrastTarget, 4.5, {
                CadenceCalendarEventStyle.railSecondaryLabelColor(for: $0, isSelected: $1, isActive: $2)
            }),
            ("tertiary", CadenceCalendarEventStyle.railTertiaryContrastTarget, 3, {
                CadenceCalendarEventStyle.railTertiaryLabelColor(for: $0, isSelected: $1, isActive: $2)
            }),
        ]

        var measured = 0
        for hex in t853CalendarHues {
            let swatch = Color(hex: hex)
            for (selected, active) in [(false, false), (false, true), (true, false)] {
                let plate = CadenceCalendarEventStyle.railFill(for: swatch, isSelected: selected, isActive: active)
                for tier in tiers {
                    measured += 1
                    let ratio = t853Ratio(tier.color(swatch, selected, active), on: plate)
                    #expect(
                        ratio >= tier.floor,
                        "the rail \(tier.name) for \(hex) (selected: \(selected), active: \(active)) reads \(t853Rounded(ratio)):1, under its \(tier.floor):1 floor"
                    )
                    #expect(
                        abs(ratio - tier.target) < 0.08,
                        "the rail \(tier.name) for \(hex) (selected: \(selected), active: \(active)) reads \(t853Rounded(ratio)):1 but is solved to \(tier.target):1 — the solve is being clamped, not met"
                    )
                }
            }
        }
        #expect(measured == 63, "non-vacuity: seven hues, three states, three tiers; \(measured) measured")

        // The targets themselves carry the floors, independent of any hue: a later edit that drops
        // `railSecondaryContrastTarget` to 4.2 is red here even if no sweep hue happens to notice.
        #expect(CadenceCalendarEventStyle.railTitleContrastTarget >= 4.5)
        #expect(CadenceCalendarEventStyle.railSecondaryContrastTarget >= 4.5)
        #expect(CadenceCalendarEventStyle.railTertiaryContrastTarget >= 3)
        #expect(CadenceCalendarEventStyle.railTitleContrastTarget > CadenceCalendarEventStyle.railSecondaryContrastTarget)
        #expect(CadenceCalendarEventStyle.railSecondaryContrastTarget > CadenceCalendarEventStyle.railTertiaryContrastTarget)
    }

    /// **[[T-3168]], second lever, as bounded by [[T-3230]]: the rail carries the CALENDAR'S OWN
    /// chroma, up to a ceiling, and clears the 3:1 non-text floor.**
    ///
    /// This replaces `theRailIsTheTitlesColourAndClearsTheNonTextFloorByConstruction`, whose first
    /// claim — rail *is* title — is the one the device photograph overturned. With a deep red, a
    /// pure blue and a pale olive on screen, the deep red was still the loudest block and none of
    /// the three read as Apple Calendar, because the hue was spread evenly over rail, title, rim
    /// and plate rather than concentrated in three points of rail. Three claims now, and the third
    /// was an empty set before:
    ///
    /// 1. **The colour lives in the rail.** The rail carries strictly more OKLab chroma than both
    ///    the title solved over the plate and the plate itself. Stated as a comparison rather than
    ///    as a threshold, because "more colourful than its own text and its own fill" is the
    ///    property; an absolute number would pass on a near-grey calendar for the wrong reason.
    ///    Zero-saturation calendars are exempted from the strict half and checked for equality
    ///    instead — `#000000` and `#ffffff` have no chroma for anything to carry.
    /// 2. **The floor still holds**, against `Theme.bg` and not against the plate — the plate is
    ///    the same hue and cannot separate from it by chroma.
    /// 3. **The CEILING binds, on exactly `#3d0000` and `#0000ff`, and the floor binds on
    ///    nothing.** T-3168 made `railMinimumLuminance` live for one lever — a primary blue tops
    ///    out at Y 0.0756 with its chroma intact and gave saturation up to reach 0.120. T-3230's
    ///    `railChromaCeiling` now takes that saturation first, and taking chroma off at full
    ///    brightness raises luminance, so the floor is satisfied before it is consulted. Both sets
    ///    are asserted by name. A hue joining or leaving the ceiling's set is news about which
    ///    calendars are louder than the loudest one Cadence ships; the floor's set becoming
    ///    non-empty is news that the ceiling stopped covering it.
    @Test func theRailCarriesTheCalendarsOwnChromaAndClearsTheNonTextFloor() {
        var measured = 0
        var flooredHues: [String] = []
        var ceilingHues: [String] = []
        for hex in t853CalendarHues {
            measured += 1
            let swatch = Color(hex: hex)
            let rail = CadenceCalendarEventStyle.railColor(for: swatch)
            let title = CadenceCalendarEventStyle.railTitleColor(for: swatch)
            let plate = CadenceCalendarEventStyle.railFill(for: swatch)

            if t853Saturation(swatch) > 0.01 {
                #expect(
                    t853Chroma(rail) > t853Chroma(title),
                    "the rail for \(hex) carries \(t853Rounded(t853Chroma(rail))) chroma, no more than its own title's \(t853Rounded(t853Chroma(title))) — the colour has stopped living in the rail"
                )
                #expect(
                    t853Chroma(rail) > t853Chroma(plate),
                    "the rail for \(hex) carries \(t853Rounded(t853Chroma(rail))) chroma, no more than the plate behind it at \(t853Rounded(t853Chroma(plate)))"
                )
            } else {
                #expect(t853Chroma(rail) < 0.001, "a calendar with no saturation got a coloured rail")
            }

            let ratio = t853Ratio(rail, on: Theme.bg)
            #expect(
                ratio >= 3,
                "the rail for \(hex) reads \(t853Rounded(ratio)):1 on bg, under the 3:1 non-text floor"
            )
            let railLuminance = Theme.relativeLuminance(of: rail)
            #expect(
                railLuminance >= CadenceCalendarEventStyle.railMinimumLuminance - 0.001,
                "the rail for \(hex) is under its own luminance floor"
            )
            if t853Saturation(swatch) > 0.01 {
                #expect(t853Hue(rail) == t853Hue(swatch), "the rail for \(hex) is no longer that hue")
            }
            if abs(railLuminance - CadenceCalendarEventStyle.railMinimumLuminance) < 0.002 {
                flooredHues.append(hex)
            }
            if t853Chroma(t3230UncappedRail(swatch)) > CadenceCalendarEventStyle.railChromaCeiling {
                ceilingHues.append(hex)
            }
        }
        #expect(measured == 7, "non-vacuity: \(measured) hues measured")
        #expect(
            flooredHues == [],
            "the luminance floor binds on \(flooredHues). Under T-3230's chroma ceiling it should bind on nothing: the ceiling cuts saturation first and that raises luminance, so a hue arriving here means railChromaCeiling went up or railMinimumLuminance did"
        )
        #expect(
            ceilingHues == ["#3d0000", "#0000ff"],
            "railChromaCeiling binds on \(ceilingHues) rather than on the two fully-saturated EventKit hues. Fewer means the ceiling rose above a colour that was louder than anything Cadence ships; more means it dropped onto one that is not"
        )
        // The arithmetic that makes the floor carried rather than live, asserted rather than left
        // in prose. A primary blue at its own chroma cannot reach the floor on brightness alone —
        // that part is unchanged and is why T-3168 could make the floor bind...
        #expect(
            CadenceCalendarEventStyle.relativeLuminance(hue: 2.0 / 3.0, saturation: 1, brightness: 1)
                < CadenceCalendarEventStyle.railMinimumLuminance
        )
        // ...but it never gets there now, because the ceiling has already walked it toward white.
        #expect(
            Theme.relativeLuminance(of: CadenceCalendarEventStyle.railColor(for: Color(hex: "#0000ff")))
                > CadenceCalendarEventStyle.railMinimumLuminance * 1.8
        )
    }

    /// **[[T-3230]]: the rail's chroma ceiling is derived from the palettes, and the assertion is
    /// that derivation rather than the number.**
    ///
    /// T-3168's second lever gave a saturation-1.0 calendar the gamut corner — `#3d0000` and
    /// `#ff0000` both rendered **(255, 0, 0)**, OKLab chroma 0.2577 — and on a near-black canvas
    /// that stayed the first thing the eye landed on even after the block's body had gone quiet.
    /// The ceiling's defining property is **"no louder than the loudest rail Cadence already
    /// ships"**, so it is bounded from below by the eighteen shipped accents and from above by
    /// the fact that it has to actually bite the primary. Both ends are measured here:
    ///
    /// 1. **It launders nothing Cadence offers.** Every accent in every palette comes back from
    ///    `railColor` byte-identical in luminance *and* chroma. This is the assertion that makes
    ///    the constant's lower bound live — drop it under `#4ecb71`'s 0.2030 and this goes red.
    /// 2. **It binds on the primary it was written for**, cutting (255, 0, 0) to (255, 85, 85).
    ///    Raise it to 0.26 and this goes red, which is the upper bound.
    /// 3. **It does not take the pale event's edge away**, which is the trap T-3230 recorded
    ///    option (c) — a luminance ceiling — falling into. `#ede7d3`'s rail carries chroma 0.029,
    ///    a twentieth of the ceiling, and comes back at Y 0.943 untouched.
    @Test func theRailIsHeldToItsChromaCeilingAndStillClearsTheNonTextFloor() {
        var measured = 0
        for palette in CadenceAccentPalette.all {
            for hex in palette.swatchHexes {
                measured += 1
                let swatch = Color(hex: hex)
                let rail = CadenceCalendarEventStyle.railColor(for: swatch)
                #expect(
                    t853Chroma(rail) <= CadenceCalendarEventStyle.railChromaCeiling,
                    "\(palette.id) \(hex)'s rail carries \(t853Rounded(t853Chroma(rail))) chroma, over the ceiling"
                )
                #expect(
                    abs(t853Chroma(rail) - t853Chroma(t3230UncappedRail(swatch))) < 1e-9,
                    "\(palette.id) \(hex)'s rail lost chroma to the ceiling — \(t853Rounded(t853Chroma(rail))) against the \(t853Rounded(t853Chroma(t3230UncappedRail(swatch)))) its own colour carries. The ceiling is under a shipped accent and is now laundering an ordinary calendar"
                )
            }
        }
        #expect(measured == 18, "non-vacuity: three palettes of six, \(measured) measured")

        // The upper bound: it has to bite the hue it was written for, and land where recorded.
        let red = CadenceCalendarEventStyle.railColor(for: Color(hex: "#3d0000"))
        #expect(t853Chroma(t3230UncappedRail(Color(hex: "#3d0000"))) > 0.25)
        #expect(abs(t853Chroma(red) - CadenceCalendarEventStyle.railChromaCeiling) < 0.001)
        #expect(abs(t853Components(red).r - 1) < 1e-9)
        #expect(abs(t853Components(red).g - 85.0 / 255) < 1.0 / 255)
        #expect(abs(t853Components(red).g - t853Components(red).b) < 1e-9)

        // Option (c)'s trap, asserted so a later luminance cap cannot be slipped in beside this.
        let pale = CadenceCalendarEventStyle.railColor(for: Color(hex: "#ede7d3"))
        #expect(t853Chroma(pale) < CadenceCalendarEventStyle.railChromaCeiling / 5)
        #expect(
            Theme.relativeLuminance(of: pale) > 0.9,
            "the pale event's rail reads Y \(t853Rounded(Theme.relativeLuminance(of: pale))) — it has lost the edge T-3168's second lever gave it"
        )
    }

    /// **Agent `calfixture`'s secondary finding, carried through a second change that could make
    /// it worse** ([[T-3168]]).
    ///
    /// `calfixture` reported that a `#0000ff` EVENT plate and an ordinary `#4a9eff` TASK plate had
    /// become close in hue and weight and were being told apart by the rail and the glyph rather
    /// than by the plate. This lever makes both plates *less* separable still — the ceiling drops
    /// to 0.12, so the event plate loses more than half its remaining chroma — so the pair is
    /// measured here rather than argued about.
    ///
    /// **It survives, and this time the rail is doing the work explicitly rather than by luck.**
    /// The first lever's answer was that the rail got three times brighter; that is no longer
    /// true, and the honest number is that `#0000ff`'s rail went the other way — from the title's
    /// Y 0.358 back down to the floor at Y 0.120. What it bought is chroma: 0.150 to **0.269**,
    /// nearly double, and chroma is the axis a task plate has nothing on this scale to answer
    /// with. A task block has no rail at all, so the separator remains, and it is now a
    /// colourfulness difference rather than a brightness one — which is the right axis, since the
    /// plate gap is already a brightness one.
    ///
    /// The plate gap is asserted too, because it is the separator that must not quietly erode:
    /// nothing here touches `railFillLuminance` or `plateLuminance`, and the test fails if a later
    /// change does.
    @Test func theBluestEventAndAnOrdinaryBlueTaskStaySeparableAfterTheColourMovesToTheRail() {
        let eventHue = Color(hex: "#0000ff")
        let taskHue = Color(hex: "#4a9eff")

        let eventPlate = Theme.relativeLuminance(of: CadenceCalendarEventStyle.railFill(for: eventHue))
        let taskPlate = Theme.relativeLuminance(of: CadenceCalendarEventStyle.plateFill(for: taskHue))
        #expect(
            taskPlate > eventPlate * 2,
            "the task plate (Y \(t853Rounded(taskPlate))) is no longer clearly lighter than the event plate (Y \(t853Rounded(eventPlate)))"
        )

        // The rail is the second separator. It is still brighter than the task plate beside it —
        // a task has no rail, so a rail that reads is the thing saying "this is an event" — and it
        // is the floor, not the title solve, that guarantees that now.
        let rail = CadenceCalendarEventStyle.railColor(for: eventHue)
        let railLuminance = Theme.relativeLuminance(of: rail)
        #expect(
            railLuminance > taskPlate,
            "the #0000ff rail (Y \(t853Rounded(railLuminance))) is dimmer than the task plate beside it (Y \(t853Rounded(taskPlate)))"
        )
        // The axis the separation actually lives on after this lever. A task plate is solved for
        // luminance with 0.90 of its own saturation and has no chroma ceiling, so this is not a
        // free comparison — it is the claim that three points of rail out-colour a whole plate.
        #expect(
            t853Chroma(rail) > t853Chroma(CadenceCalendarEventStyle.plateFill(for: taskHue)) * 2,
            "the #0000ff rail carries \(t853Rounded(t853Chroma(rail))) chroma against the task plate's \(t853Rounded(t853Chroma(CadenceCalendarEventStyle.plateFill(for: taskHue)))) — the rail has stopped being the louder marker"
        )
        // ...and it bought that chroma by giving up luminance, which is exactly the trade the
        // floor exists to bound. It may sit ON the floor; it may not sit under it.
        #expect(
            railLuminance >= CadenceCalendarEventStyle.railMinimumLuminance - 0.001,
            "the #0000ff rail fell through the 3:1 non-text floor"
        )
    }

    /// **The rail does not move with the state ladder, and the title does** ([[T-3168]]).
    ///
    /// The rail answers "which calendar is this"; an identity marker that changes colour on hover
    /// is a different calendar. `railColor` takes no `isSelected`/`isActive` and reads nothing
    /// that does, and this is the measurement of that rather than a reading of the signature.
    ///
    /// **The second claim moved with the second lever, and the new one is the honest one.** While
    /// the rail was the title's own colour it was necessarily dimmer than the title in hover and
    /// selection, and the test said so. It is not any more: the rail is solved from the calendar
    /// rather than from the plate, so a *light* calendar's rail is brighter than any of its title
    /// stops and a *deep* one's is darker. Asserting an ordering would therefore be asserting
    /// which calendars exist. What is asserted instead is the thing the change is about — the rail
    /// is never the title's colour for a calendar that has a colour, because the two are now
    /// solved by different rules on purpose — plus the ladder the title still climbs.
    @Test func theRailStaysOneColourWhileItsTitleClimbsTheStateLadder() {
        var measured = 0
        var brighterThanEveryTitleStop: [String] = []
        for hex in t853CalendarHues {
            let swatch = Color(hex: hex)
            let rail = CadenceCalendarEventStyle.railColor(for: swatch)
            let rest = Theme.relativeLuminance(of: CadenceCalendarEventStyle.railTitleColor(for: swatch))
            let active = Theme.relativeLuminance(
                of: CadenceCalendarEventStyle.railTitleColor(for: swatch, isActive: true)
            )
            let selected = Theme.relativeLuminance(
                of: CadenceCalendarEventStyle.railTitleColor(for: swatch, isSelected: true)
            )
            let railLuminance = Theme.relativeLuminance(of: rail)

            #expect(active > rest + 0.02, "the active title for \(hex) did not climb above rest")
            #expect(selected > active + 0.02, "the selected title for \(hex) did not climb above active")

            if t853Saturation(swatch) > 0.01 {
                #expect(
                    rail != CadenceCalendarEventStyle.railTitleColor(for: swatch),
                    "the rail for \(hex) is its rest title again — lever 1 has come back and the colour has left the rail"
                )
            }
            // Whatever the ordering, the rail is one colour: it is read from the calendar and the
            // state ladder is not an input to it. Measured by asking for it three times in three
            // states' worth of surrounding context and getting the same answer.
            #expect(
                Theme.relativeLuminance(of: CadenceCalendarEventStyle.railColor(for: swatch)) == railLuminance,
                "the rail for \(hex) is not a pure function of its calendar colour"
            )
            if railLuminance > selected { brighterThanEveryTitleStop.append(hex) }
            measured += 1
        }
        #expect(measured == 7, "non-vacuity: \(measured) hues measured")
        // Named rather than left to be rediscovered: these are the calendars whose rail outshines
        // their own text at every state, and they are exactly the light ones. A deep hue appearing
        // here would mean the rail had stopped being solved from the calendar.
        #expect(
            brighterThanEveryTitleStop == ["#ffc857", "#4fd6e0", "#ffffff", "#000000"],
            "the set of calendars whose rail is brighter than every title stop changed: \(brighterThanEveryTitleStop)"
        )
    }

    /// Both ladders, measured in L* rather than in raw luminance, because raw luminance is not
    /// perceptually uniform and 0.030 → 0.044 looks nothing like 0.098 → 0.124 does.
    ///
    /// Two claims: each ladder's three stops are ordered and separated by several times the ~1 L*
    /// just-noticeable step, and the rail treatment's plate is *strictly darker* than the plate
    /// treatment's at every state. The second is what keeps the two treatments distinguishable now
    /// that functional affordances are the only other thing telling a task from an event — collapse
    /// the two fills together and the swap has produced one treatment, not two.
    @Test func bothCalendarPlateLaddersStayOrderedAndTheRailPlateStaysTheDarkerOne() {
        let plateLadder = [
            CadenceCalendarEventStyle.plateLuminance(),
            CadenceCalendarEventStyle.plateLuminance(isActive: true),
            CadenceCalendarEventStyle.plateLuminance(isSelected: true),
        ]
        let railLadder = [
            CadenceCalendarEventStyle.railFillLuminance(),
            CadenceCalendarEventStyle.railFillLuminance(isActive: true),
            CadenceCalendarEventStyle.railFillLuminance(isSelected: true),
        ]

        for (name, ladder) in [("plate", plateLadder), ("rail", railLadder)] {
            let steps = zip(ladder.dropFirst(), ladder).map { t853LStar($0) - t853LStar($1) }
            #expect(steps.count == 2, "non-vacuity: \(name) has \(steps.count) steps")
            for step in steps {
                #expect(step > 3, "the \(name) ladder has a \(t853Rounded(step)) L* step, near the ~1 L* JND")
                #expect(step < 12, "the \(name) ladder has a \(t853Rounded(step)) L* step, which is a jump not a state")
            }
        }

        for (rail, plate) in zip(railLadder, plateLadder) {
            #expect(plate - rail > 0.04, "the two plates have converged: \(rail) against \(plate)")
            #expect(t853LStar(plate) - t853LStar(rail) > 10, "the two plates are within one state-step of each other")
        }

        // And the rail plate is still a plate, not the background: it has to say where the block
        // ends even though the rail is what announces it.
        for luminance in railLadder {
            #expect(luminance > Theme.relativeLuminance(of: Theme.bg) * 5)
            #expect(luminance < Theme.onColorCrossoverLuminance)
        }
    }

    // MARK: - T-3168: the chroma ceiling

    /// The arithmetic the ceiling rests on, checked against answers that do not come from this app.
    ///
    /// Same discipline as `theContrastArithmeticAgreesWithWCAGOnPairsWhoseAnswerIsKnown` above: a
    /// chroma function that agrees with Cadence's own numbers has proved nothing. OKLab's defining
    /// landmarks are public — white is lightness 1, black is 0, every neutral has chroma exactly 0,
    /// and sRGB's primary blue is the most chromatic thing the gamut holds at about 0.313.
    @Test func theOKLabArithmeticAgreesWithKnownAnswers() {
        #expect(abs(CadenceOKLab.lightness(red: 1, green: 1, blue: 1) - 1) < 0.0005)
        #expect(abs(CadenceOKLab.lightness(red: 0, green: 0, blue: 0)) < 0.0005)
        #expect(abs(CadenceOKLab.chroma(red: 0, green: 0, blue: 1) - 0.3132) < 0.002)

        // Every neutral is colourless, which is the property the ceiling's bisection walks toward.
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(
                CadenceOKLab.chroma(red: step, green: step, blue: step) < 0.0005,
                "a grey at \(step) measured as carrying chroma"
            )
        }

        // Chroma orders the way the eye does: a primary blue is more colourful than a mid blue,
        // which is more colourful than a grey. Without this the ceiling could be monotonic in the
        // wrong direction and every assertion below would still pass.
        let primary = t853Chroma(Color(hex: "#0000ff"))
        let mid = t853Chroma(Color(hex: "#4a9eff"))
        let grey = t853Chroma(Color(hex: "#6b7a99"))
        #expect(primary > mid)
        #expect(mid > grey)

        // `neutralLightness` is a closed form (`cbrt`) standing in for the general path. If the
        // identity it rests on is ever wrong, the ceiling is computed against the wrong anchor.
        for luminance in [0.030, 0.044, 0.060, 0.098, 0.5] {
            let neutral = t853Grey(luminance: luminance)
            let parts = t853Components(neutral)
            #expect(
                abs(CadenceOKLab.neutralLightness(relativeLuminance: luminance)
                    - CadenceOKLab.lightness(red: parts.r, green: parts.g, blue: parts.b)) < 0.002,
                "neutralLightness disagrees with the general path at Y = \(luminance)"
            )
        }
    }

    /// **The guarantee that makes the ceiling free.** T-3168's whole argument is that a chroma
    /// ceiling applied *at constant luminance* costs no contrast, because every ratio in
    /// `CadenceCalendarEventStyle` is `(L1 + 0.05) / (L2 + 0.05)` over two luminances and nothing
    /// else — so a plate that keeps its Y keeps every tier solved against it, to the digit.
    ///
    /// That is only true if the plate really does keep its Y. The ceiling's bisection re-solves
    /// brightness at every step precisely so it does, and this is the measurement of it: the
    /// delivered fill's relative luminance must still *be* `railFillLuminance`, at every hue
    /// including the ones the ceiling pulls hardest. If it drifts, every derived label target in
    /// `everyRailTreatmentTierLandsOnItsDeclaredRatioAgainstItsOwnPlate` is aiming at a plate that
    /// is not there.
    @Test func everyRailPlateHoldsItsChromaCeilingWithoutMovingItsLuminance() {
        var measured = 0
        for hex in t853CalendarHues {
            let swatch = Color(hex: hex)
            for (selected, active) in [(false, false), (false, true), (true, false)] {
                measured += 1
                let plate = CadenceCalendarEventStyle.railFill(for: swatch, isSelected: selected, isActive: active)
                let ceiling = CadenceCalendarEventStyle.railPlateChromaCeiling(isSelected: selected, isActive: active)
                let declared = CadenceCalendarEventStyle.railFillLuminance(isSelected: selected, isActive: active)

                #expect(
                    t853Chroma(plate) <= ceiling + 0.002,
                    "the rail plate for \(hex) (selected: \(selected), active: \(active)) carries chroma \(t853Rounded(t853Chroma(plate))), over its \(t853Rounded(ceiling)) ceiling"
                )
                #expect(
                    abs(t853Luminance(plate) - declared) < 0.0015,
                    "the rail plate for \(hex) (selected: \(selected), active: \(active)) came back at Y = \(t853Luminance(plate)) rather than its declared \(declared) — the chroma cap moved the luminance, so every tier solved against this plate is now aimed at the wrong number"
                )
            }
        }
        #expect(measured == 21, "non-vacuity: seven hues, three states; \(measured) measured")

        // The ceiling is derived from the ladder rather than typed beside it, so it cannot be left
        // behind when the ladder moves.
        for (selected, active) in [(false, false), (false, true), (true, false)] {
            let expected = CadenceCalendarEventStyle.railPlateChromaRatio
                * CadenceOKLab.neutralLightness(
                    relativeLuminance: CadenceCalendarEventStyle.railFillLuminance(isSelected: selected, isActive: active)
                )
            #expect(
                abs(CadenceCalendarEventStyle.railPlateChromaCeiling(isSelected: selected, isActive: active) - expected) < 1e-9,
                "the chroma ceiling stopped being derived from railFillLuminance"
            )
        }
        #expect(
            CadenceCalendarEventStyle.railPlateChromaCeiling()
                < CadenceCalendarEventStyle.railPlateChromaCeiling(isActive: true),
            "the ceiling no longer rises with the plate it belongs to"
        )
    }

    /// **The ceiling now launders EVERY calendar colour the palettes offer, and that inversion is
    /// the whole of [[T-3168]]'s second lever.**
    ///
    /// This replaces `theChromaCeilingBindsOnlyOnHuesOutsideTheOrdinaryBand`, which asserted the
    /// opposite: that the ceiling touched two of seven sweep hues and one of eighteen accents, and
    /// that a third appearing in either list was news. That was the right assertion while the
    /// plate was where the calendar's colour lived. It is not any more — `railColor` carries the
    /// hue now — and a ceiling only a pathological colour ever reaches leaves every ordinary
    /// calendar exactly as the device photograph showed it: a filled card whose whole body carries
    /// hue.
    ///
    /// **So the claim flips, and it is the bound the constant is derived from.** "The fill is a
    /// near-neutral wash" must be a property of the treatment rather than of which hue the account
    /// picked, so the ceiling must bind on the *least* colourful swatch any shipped palette
    /// offers. All eighteen are held, and five of the seven sweep hues; the two it misses are
    /// `#ffffff` and `#000000`, which have no chroma to take. An accent escaping is news in the
    /// other direction: it means the ceiling drifted up past a palette.
    ///
    /// The derivation is asserted too, because a ratio that merely *happens* to clear every accent
    /// today is one new palette away from not doing so.
    @Test func theChromaCeilingLaundersEveryCalendarColourThePalettesOffer() {
        func clipped(_ hexes: [String]) -> [String] {
            hexes.filter { hex in
                let swatch = Color(hex: hex)
                let source = t853Saturation(swatch) * CadenceCalendarEventStyle.railPlateSaturationScale
                return [(false, false), (false, true), (true, false)].contains { selected, active in
                    let plate = CadenceCalendarEventStyle.railFill(for: swatch, isSelected: selected, isActive: active)
                    return t853Saturation(plate) < source - 0.01
                }
            }
        }

        #expect(
            clipped(t853CalendarHues) == ["#ffc857", "#4fd6e0", "#4a9eff", "#3d0000", "#0000ff"],
            "the set of sweep hues the chroma ceiling binds on changed: \(clipped(t853CalendarHues))"
        )

        var offered: [String] = []
        for palette in CadenceAccentPalette.all { offered.append(contentsOf: palette.swatchHexes) }
        #expect(offered.count == 18, "non-vacuity: \(offered.count) accent swatches swept")
        #expect(
            clipped(offered).count == 18,
            "the ceiling no longer launders every shipped accent — these escaped it: \(Set(offered).subtracting(clipped(offered)).sorted())"
        )

        // The bound the ratio is derived from, measured rather than restated: the least colourful
        // plate any palette can produce, and the ratio that just reaches it. 0.12 must sit under
        // that, or at least one shipped calendar keeps a full-bodied hue.
        let leastColourfulAccentPlate = offered
            .map { t853Chroma(CadenceCalendarEventStyle.railFill(for: Color(hex: $0))) }
            .min() ?? 0
        #expect(leastColourfulAccentPlate > 0, "non-vacuity: no accent plate was measured")
        let anchor = CadenceOKLab.neutralLightness(
            relativeLuminance: CadenceCalendarEventStyle.railFillLuminance()
        )
        let bound = offered
            .map { t853UncappedRailPlateChroma(Color(hex: $0)) / anchor }
            .min() ?? 0
        #expect(
            CadenceCalendarEventStyle.railPlateChromaRatio < bound,
            "railPlateChromaRatio \(CadenceCalendarEventStyle.railPlateChromaRatio) is at or above the \(t853Rounded(bound)) at which the least colourful shipped accent escapes the ceiling"
        )
        #expect(
            CadenceCalendarEventStyle.railPlateChromaRatio > 0.048,
            "railPlateChromaRatio is under the floor at which a vivid plate stops being twice as colourful as the pale #ede7d3 control's own plate"
        )

        // Whatever chroma it gives up, the plate is still that calendar's hue — the cap walks
        // saturation toward grey at a fixed hue, it does not rotate anything, and it does not
        // reach grey.
        for hex in ["#3d0000", "#0000ff", "#4a9eff"] {
            let swatch = Color(hex: hex)
            let plate = CadenceCalendarEventStyle.railFill(for: swatch)
            #expect(t853Hue(plate) == t853Hue(swatch), "the capped plate for \(hex) is no longer that hue")
            #expect(t853Saturation(plate) > 0.05, "the capped plate for \(hex) was laundered to a grey")
            #expect(
                t853Chroma(plate) > t853Chroma(CadenceCalendarEventStyle.railFill(for: Color(hex: "#ede7d3"))) * 2,
                "the capped plate for \(hex) is no more colourful than the pale control's own plate"
            )
        }
    }

    /// **The inversion T-3168 was filed about, measured in the axis that inverted.**
    ///
    /// `bothCalendarPlateLaddersStayOrderedAndTheRailPlateStaysTheDarkerOne` above pins the
    /// *lightness* half, and the lightness half was never in doubt: the rail plate has always been
    /// four times darker. What the owner could see is that it was not therefore *quieter*, because
    /// the eye reads chroma as loudness (Helmholtz–Kohlrausch) and the luminance solve left chroma
    /// completely unbounded — `#0000ff`'s rail plate measured 0.234 against a mid blue's 0.064.
    ///
    /// Two claims, and the second is the one that could not be made before the ceiling existed:
    ///
    /// 1. **Per hue**, the rail plate is quieter than the plate plate on *both* axes.
    /// 2. **Across hues**, the loudest rail plate any calendar colour can produce — which is now
    ///    the ceiling, by construction — is still less colourful than the plate plate of an
    ///    ordinary mid blue. No calendar colour can make an event the loudest block on the canvas.
    ///
    /// Claim 2 fails on the pre-T-3168 solve by a factor of three, which is what the ticket is.
    @Test func noCalendarHueMakesTheEventPlateLouderThanAnOrdinaryTaskPlate() {
        let ordinary = Color(hex: "#4a9eff")
        var measured = 0

        for hex in t853CalendarHues {
            let swatch = Color(hex: hex)
            for (selected, active) in [(false, false), (false, true), (true, false)] {
                measured += 1
                let railPlate = CadenceCalendarEventStyle.railFill(for: swatch, isSelected: selected, isActive: active)
                let platePlate = CadenceCalendarEventStyle.plateFill(for: swatch, isSelected: selected, isActive: active)

                #expect(
                    t853LStar(t853Luminance(railPlate)) < t853LStar(t853Luminance(platePlate)),
                    "the rail plate for \(hex) is no longer the darker of the two"
                )
                #expect(
                    t853Chroma(railPlate) <= t853Chroma(platePlate) + 0.0005,
                    "the rail plate for \(hex) (selected: \(selected), active: \(active)) is MORE colourful than the plate plate of the same hue, at \(t853Rounded(t853Chroma(railPlate))) against \(t853Rounded(t853Chroma(platePlate)))"
                )

                // Claim 2. The reference is a literal mid blue rather than `Theme.blueHex` because
                // the accent palette is selectable and this bound must not move with it.
                let loudestPossible = CadenceCalendarEventStyle.railPlateChromaCeiling(isSelected: selected, isActive: active)
                let ordinaryTask = t853Chroma(
                    CadenceCalendarEventStyle.plateFill(for: ordinary, isSelected: selected, isActive: active)
                )
                #expect(
                    loudestPossible < ordinaryTask,
                    "the loudest event plate reachable (\(t853Rounded(loudestPossible))) is at or above an ordinary blue task plate (\(t853Rounded(ordinaryTask))) — the hierarchy T-3160 built is inverted again"
                )
                #expect(
                    t853Chroma(railPlate) <= loudestPossible + 0.002,
                    "non-vacuity: \(hex) is not actually held by the bound claim 2 rests on"
                )
            }
        }
        #expect(measured == 21, "non-vacuity: seven hues, three states; \(measured) measured")

        // The two the owner can see, named so a regression reads as news rather than as a number.
        for hex in ["#3d0000", "#0000ff"] {
            let plate = CadenceCalendarEventStyle.railFill(for: Color(hex: hex))
            let ordinaryEvent = t853Chroma(CadenceCalendarEventStyle.railFill(for: ordinary))
            #expect(
                t853Chroma(plate) < ordinaryEvent * 1.3,
                "\(hex)'s event plate reads \(t853Rounded(t853Chroma(plate))) against an ordinary blue event's \(t853Rounded(ordinaryEvent)) — it is back to being the loudest block on the canvas, which is T-3168"
            )
        }
    }

    /// What is still allowed to say `Theme.onColor` without asking which fill it lands on.
    ///
    /// The migration is only durable if the *next* accent-filled button is caught, and the whole
    /// failure mode of T-855 was that a constant looked like an answer. So the residue is
    /// enumerated: **three** files, each with a stated reason, and a fourth goes red here.
    ///
    /// **It was five until T-3160, and the two that left are the list working rather than the list
    /// rotting.** The calendar's event and task treatments swapped places, and both departures are
    /// a surface moving *onto* a solved colour: `CalendarPageMonthSupportViews.swift`'s task chips
    /// now read `platePrimaryLabelColor`, which is the same white asked for by name against a fill
    /// solved to admit it, and `TimelineEventBlock.swift` dropped the white accent wash it drew
    /// across the top of every event block — over the rail treatment's plate at Y = 0.030-0.060
    /// that wash composites brighter than the rail itself, so it had become a second, colourless
    /// accent marker competing with the one that names the calendar. Entries are expected to leave
    /// this list. Nothing may be added back to keep one on it.
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
        //
        // **Recomputed from the working tree on 2026-10-13 by agent `calrail`**, at the moment its
        // half of T-3160 was committed, rather than copied from a sibling's report: three agents
        // held dirty files that move this answer, so the only honest reading is the one taken off
        // the tree by the sweep above. An agent landing a fourth must re-run this test, not trust
        // this list.
        #expect(hits == [
            // The plate treatment's own primary tier. `platePrimaryLabelColor` is unconditionally
            // `Theme.onColor` *because* the fill under it is solved to a luminance that admits it,
            // which is the whole point of solving the fill.
            "Cadence/Shared/CadenceCalendarEventStyle.swift",
            // Sign in with Apple: a brand-locked black fill with a mandated white label.
            "Cadence/macOS/Views/SettingsSectionViews.swift",
            // The neutral rest edge of a timeline block: a white *wash* over a block, not ink read
            // against one. `borderColor`'s `idleTintOpacity` is how the rail treatment declines it
            // (T-3160) without this helper having to pick a side.
            "Cadence/macOS/Views/TimelineHoverVisuals.swift",
        ], "the set of files still reading Theme.onColor as a constant changed: \(hits)")
    }
}

/// The hues a calendar colour sweep has to cover. EventKit hands back whatever the account stored,
/// so this is not the palette: it is the palette's bright end, a raw white calendar, and the two
/// degenerate corners a user-chosen `colorHex` can reach — a near-black red and a primary blue,
/// which are where a luminance solve either runs out of chroma or runs out of headroom.
private let t853CalendarHues = ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000", "#0000ff", "#000000"]

/// CIE L* of a WCAG relative luminance. Luminance is linear light and 0.03 → 0.044 says nothing
/// about whether a reader can see the step; L* is roughly perceptually uniform, with a
/// just-noticeable difference of about 1.
private func t853LStar(_ luminance: Double) -> Double {
    luminance > 0.008856 ? 116 * pow(luminance, 1.0 / 3.0) - 16 : 903.3 * luminance
}

/// OKLab chroma of a colour: how much colour it carries, independent of how light it is. The axis
/// WCAG relative luminance cannot see, and the one T-3168's ceiling is stated in.
private func t853Chroma(_ color: Color) -> Double {
    let parts = t853Components(color)
    return CadenceOKLab.chroma(red: parts.r, green: parts.g, blue: parts.b)
}

private func t853Hue(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return (Double(hue) * 1000).rounded() / 1000
}

private func t853Saturation(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Double(saturation)
}

/// The OKLab chroma a rail plate would carry **if there were no ceiling at all** — the pre-T-3168
/// solve, rebuilt here out of the one piece of `CadenceCalendarEventStyle` that is not private
/// (`relativeLuminance(hue:saturation:brightness:)`) plus a bisection of its own.
///
/// It exists so the ceiling's upper bound can be *derived* in the assertion rather than copied out
/// of the doc comment it is justified in. Deliberately the harness's arithmetic and not the code
/// under test's: a bound measured with the capped solve would be the capped number, and would
/// agree with anything.
private func t853UncappedRailPlateChroma(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    let scaled = Double(saturation) * CadenceCalendarEventStyle.railPlateSaturationScale
    let target = CadenceCalendarEventStyle.railFillLuminance()
    var low = 0.0
    var high = 1.0
    for _ in 0..<20 {
        let mid = (low + high) / 2
        if CadenceCalendarEventStyle.relativeLuminance(hue: Double(hue), saturation: scaled, brightness: mid) < target {
            low = mid
        } else {
            high = mid
        }
    }
    return t853Chroma(Color(hue: Double(hue), saturation: scaled, brightness: high))
}

/// The rail as `railColor` would return it with [[T-3230]]'s chroma ceiling removed: the
/// calendar's own hue and saturation at full brightness, which is where T-3168's second lever put
/// it.
///
/// `railMinimumLuminance` is deliberately left out. It is a floor on *luminance* and it reaches it
/// by taking saturation off, so including it could only lower the chroma this returns — and every
/// call site here uses this as an **upper bound** on the chroma the calendar's own colour carries.
/// Leaving it out therefore makes each assertion strictly harder to pass, never easier, and keeps
/// the reference arithmetic to one line.
private func t3230UncappedRail(_ color: Color) -> Color {
    Color(hue: t853RawHue(color), saturation: t853Saturation(color), brightness: 1)
}

/// `t853Hue` without its three-decimal rounding. That rounding is right for the equality checks it
/// was written for and wrong here: a hue nudged by 5e-4 reconstructs a visibly different colour,
/// and this helper's whole job is to reconstruct one exactly.
private func t853RawHue(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Double(hue)
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

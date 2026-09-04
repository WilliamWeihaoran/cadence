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
    /// is right and the pair is wrong: `markerHighlightFill` is **never drawn opaque**. The editor
    /// fills the highlight rect at a fraction of alpha over a near-black text view, so what a
    /// reader actually sees is `markerHighlightText` on that composite — around 7:1, not 1.48:1.
    ///
    /// Which makes the alpha load-bearing rather than cosmetic, and that is what this pins. The
    /// fraction is **read out of the drawing code** and fed into the arithmetic, so raising it
    /// toward opaque — the one edit that would make the audit's number the real one — recomputes
    /// the ratio here and fails. A remembered `0.38` would not have caught it.
    @Test func theMarkerHighlightIsMeasuredAtTheAlphaTheEditorActuallyDrawsIt() throws {
        let drawing = try t853Source("Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift")
        let alphaPattern = #"highlightFillColor\.withAlphaComponent\(([0-9.]+)\)"#

        #expect(
            CadenceSourceScan.captures(alphaPattern, in: "MarkdownStylist.highlightFillColor.withAlphaComponent(0.5).setFill()").map(\.text) == ["0.5"],
            "self-check: the alpha needle no longer reads an alpha"
        )
        #expect(
            CadenceSourceScan.captures(alphaPattern, in: "MarkdownStylist.highlightBorderColor.withAlphaComponent(0.62).setStroke()").isEmpty,
            "self-check: the alpha needle reads the border stroke as the fill"
        )

        let alphas = CadenceSourceScan.captures(alphaPattern, in: drawing).map(\.text)
        #expect(alphas.count == 1, "expected one highlight fill, found \(alphas.count)")
        let alphaText = try #require(alphas.first)
        let alpha = try #require(Double(alphaText))
        #expect(alpha > 0 && alpha <= 1)

        // The surface underneath is the text view's own background, also read rather than assumed.
        let editor = try t853Source("Cadence/macOS/Editor/MarkdownEditorView.swift")
        let backgrounds = CadenceSourceScan.captures(#"textView\.backgroundColor = Theme\.(\w+)"#, in: editor).map(\.text)
        #expect(backgrounds == ["nsBg"], "the markdown text view now draws on \(backgrounds), not Theme.nsBg")

        let painted = t853Ratio(
            Theme.markerHighlightText,
            on: Theme.markerHighlightFill.opacity(alpha),
            over: Theme.bg
        )
        #expect(
            painted >= 4.5,
            "highlighted markdown text reads at \(t853Rounded(painted)):1 as drawn (fill at \(alpha) over Theme.bg)"
        )

        // And the pen still reads as a pen: the fill has to lift off the page it is drawn on.
        let lift = t853Ratio(Theme.markerHighlightFill.opacity(alpha), on: Theme.bg)
        #expect(lift > 1.5, "the highlight fill no longer separates from Theme.bg")
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

import SwiftUI

/// Small-caps "eyebrow" section label (e.g. STATUS, COLOR, UNASSIGNED) used above
/// filter groups, form fields, and card headers. Consolidates several near-identical
/// one-off label styles into a single consistent size/weight/kerning.
///
/// **It comes in two sizes, and that is a tier rather than drift.** A popover group heading or an
/// inspector well label is legitimately smaller than a page's eyebrow, and T-284 kept that
/// distinction rather than flattening it — flattening would have been a size decision dressed as a
/// refactor. What T-284 removed is the *four kernings* the smaller tier had accumulated across six
/// hand-rolled spellings (0.45, 0.54, 0.6, 0.7 and, twice, none at all). Letterspacing is now
/// derived from the size by one ratio, so the two tiers are one decision and a third size could
/// only ever be added on purpose.
struct SectionEyebrowLabel: View {

    /// Which of the two eyebrow tiers a label belongs to.
    ///
    /// `nonisolated` members throughout, matching the static `fontSize` below — but **not for the
    /// same reason, and this tier's annotation is not load-bearing today (T-477).** The static has
    /// to carry it: `CadenceTaskGroupHeadingMetrics` is a `nonisolated struct`, this target defaults
    /// declarations to `@MainActor` (`SWIFT_APPROACHABLE_CONCURRENCY`), and a nonisolated static
    /// cannot initialise from a main-actor-isolated one. `Size`'s members are read by
    /// `SidebarMetrics`, `TaskInspectorFieldRowMetrics`, the notes list's group header and this
    /// view's own `body`, every one of which is main-actor already — dropping `nonisolated` from
    /// these three still builds, measured, so it stays for the tier to be reachable from the same
    /// readers the bare `fontSize` is, not because something breaks without it.
    ///
    /// The wording this replaces justified the annotation by CadenceEyebrowMetrics' readers — a
    /// type that has never existed in this repo, left behind when T-284's conversion renamed the
    /// prose out from under itself. It is deliberately not written in backticks here: it is not a
    /// symbol. `theEyebrowDocOnlyNamesMetricsTypesThatExist` is what stops a rationale in this file
    /// naming a type again that a reader cannot go and check.
    enum Size {
        /// Page and section eyebrows — the default, and what 19 macOS files already draw.
        case standard
        /// Popover group headings and inspector well labels, deliberately one point smaller.
        case compact

        nonisolated var fontSize: CGFloat {
            switch self {
            case .standard: SectionEyebrowLabel.fontSize
            case .compact: SectionEyebrowLabel.compactFontSize
            }
        }

        nonisolated var kerning: CGFloat { fontSize * SectionEyebrowLabel.kerningRatio }

        nonisolated var font: Font { .system(size: fontSize, weight: .semibold) }
    }

    /// The app's one eyebrow size. Exposed because things drawn *beside* an eyebrow have to agree
    /// with it — `CadenceBoardColumnHeaderMetrics.labelSize` and
    /// `CadenceTaskGroupHeadingMetrics.countSize` are both this number, and both were a
    /// hand-typed 10 or 11 before somebody noticed which one they were meant to match.
    /// `nonisolated` because `CadenceTaskGroupHeadingMetrics` is, and a nonisolated value type
    /// cannot read a main-actor-isolated static. A literal, so there is nothing to initialise from.
    nonisolated static let fontSize: CGFloat = 10

    /// The sub-label tier. One point smaller, and only that — every other property of an eyebrow is
    /// shared.
    nonisolated static let compactFontSize: CGFloat = 9

    /// Letterspacing as a fraction of the font size, so the two tiers cannot drift apart.
    ///
    /// `0.08` reproduces the standard tier's long-standing `0.8` at 10pt exactly, and gives the
    /// compact tier `0.72` — which is what the six hand-rolled 9pt labels were each guessing at,
    /// one of them with a comment computing "~0.05em at 9pt" and another "~0.06em at 9pt". A ratio
    /// is the reason there is nothing left to guess.
    ///
    /// **Why the ratio and not the majority (T-284, the judgement the conversion never recorded).**
    /// Counting the six hand-rolled spellings gives the wrong answer: 0.6 appeared twice and 0.54
    /// twice, so a vote elects ~0.057em — a number nobody chose, arrived at by two independent
    /// guesses each landing near it. Tracking is optical, and optical tracking scales with the
    /// type: the same *visual* letterspacing at 9pt as the 19 correct 10pt sites is 0.08 × 9, and
    /// nothing else is. So the minority spelling is the correct one and the plurality is the
    /// accident — which is also why the two sites that carried *no* tracking were the plainest
    /// defects rather than a third opinion: an uppercase run set solid is the condition an eyebrow
    /// style exists to prevent, not a tighter setting of it.
    ///
    /// Derived rather than switched, and `theCompactKerningIsDerivedRatherThanASecondLiteral`
    /// pins that: a per-case literal satisfies every value assertion in this repo while putting the
    /// two tiers back on two independently editable numbers, which is the whole defect.
    nonisolated static let kerningRatio: CGFloat = 0.08

    let text: String
    var size: Size = .standard
    var tint: Color = Theme.dim

    /// **The eyebrow is the component that forced T-1364's migration boundary to be an environment
    /// value.** Sixty-odd files draw one, across surfaces whose heights are still literals, so
    /// converting it "for the composer" would have meant a second eyebrow — and a second eyebrow is
    /// the exact defect T-284 spent this file's doc comment removing. `cadenceUppercaseLabel`
    /// reads `\.cadenceTypographyScaling` instead: inside a converted workflow it grows, everywhere
    /// else it is the same 10 or 9 points it has always been, and there is still one of it.
    ///
    /// **The heading trait is the eyebrow's, not the shared modifier's (T-2035).** Every eyebrow
    /// names the section, group or well beneath it, so VoiceOver's heading navigation should stop
    /// on it. `cadenceUppercaseLabel` also draws the two calendar weekday rails — `Mon` labels a
    /// day column, it is not a heading — and the board column header, whose title is decided by
    /// that component, so the trait is added here rather than in the modifier.
    /// `CadenceEyebrowAccessibilityTests` reads it off a real tree, and its absence on a weekday rail.
    var body: some View {
        Text(text.uppercased())
            .cadenceUppercaseLabel(reading: text, size: size.fontSize, kerning: size.kerning)
            .foregroundStyle(tint)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CadenceUppercaseLabelType: ViewModifier {
    let reading: String
    let size: CGFloat
    let kerning: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    func body(content: Content) -> some View {
        let multiplier = CadenceTypeScale.multiplier(.sectionLabel, at: dynamicTypeSize, scaling: scaling)
        return content
            .font(.system(size: size * multiplier, weight: CadenceTypographyRole.sectionLabel.weight))
            .kerning(kerning * multiplier)
            .accessibilityLabel(Text(verbatim: reading))
    }
}

extension View {
    /// The app's uppercase kerned label — the eyebrow, the board column header, and the two
    /// calendar weekday rails — as one modifier rather than four spellings of it.
    ///
    /// **It takes both figures because tracking is optical (T-1364, extending T-496).** T-496 put
    /// the four sites on one size and one tracking *ratio*; each still set its own `.font` and its
    /// own `.kerning`, which was fine while both were constants and is not once the size can move.
    /// An eyebrow set at 33pt with 0.8pt of tracking is an eyebrow set solid, which is the
    /// condition this style exists to prevent. So the two are applied together, by the same
    /// multiplier, and a site cannot scale one without the other.
    ///
    /// Each site still passes **its own** constants — `CadenceBoardColumnHeaderMetrics.labelSize`
    /// and `.labelKerning`, `CadenceCalendarWeekdayHeaderMetrics`' pair, the eyebrow's `Size` —
    /// so this consolidates the *drawing* and changes nothing about where the numbers are decided.
    /// `CadenceUppercaseLabelTrackingTests` still reads those declarations and still requires each
    /// to name `SectionEyebrowLabel.kerningRatio`.
    ///
    /// **`reading:` is the words, in natural case, and it is required (T-2022).** The glyphs are
    /// uppercased for the eye; assistive tech gets `Edit Area`, not `EDIT AREA` — an all-caps run
    /// is what a screen reader is likeliest to spell out letter by letter, and `MON` is not a word.
    /// It is a required argument rather than a default so no fifth site can draw an uppercase
    /// label and forget what it says. What T-2022 measured, so nobody re-files it: on macOS a
    /// SwiftUI `Text` publishes its string as the static text's **AXValue**, with no label, kerned
    /// or not — `Text("Plain Words")` and `SectionEyebrowLabel` read identically in
    /// `CadenceEyebrowAccessibilityTests`. The ticket's "empty label" was XCUITest's `.label`
    /// reading a field macOS static text never fills; `.kerning` dropped nothing. And on macOS an
    /// `.accessibilityLabel` on a `Text` lands in that same AXValue, which is where this one goes.
    func cadenceUppercaseLabel(reading: String, size: CGFloat, kerning: CGFloat) -> some View {
        modifier(CadenceUppercaseLabelType(reading: reading, size: size, kerning: kerning))
    }
}

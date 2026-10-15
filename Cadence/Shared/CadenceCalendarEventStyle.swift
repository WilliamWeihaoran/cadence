import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The two ways a calendar block is painted, on **both** platforms.
///
/// This used to exist twice. macOS had a luminance-solved fill (`CalendarEventVisualStyle`) with a
/// documented contrast budget; iOS had a hand-tuned `saturation * 0.55, brightness * 0.6` rule —
/// which is precisely the double-hit rule macOS abandoned, and which rendered an orange calendar
/// brown and a green one olive. Two implementations of "what colour is this block" is one too many,
/// so the solve lives here and both platforms read it.
///
/// There are now **two treatments**, and they are named for what they look like rather than for who
/// wears them, because who wears them has already changed once:
///
/// - **`plate*`** — a solved opaque fill in the calendar/list hue with `Theme.onColor` content and
///   no rail. This is the original Cadence event look.
/// - **`rail*`** — Apple Calendar's look: a leading vertical rail at near-full chroma, a much
///   darker tinted plate, and the **title in the hue** rather than in white.
///
/// ## Who wears which, and why that is not in the names (T-3160)
///
/// Until T-3160 the file documented a rule it no longer follows, and the reasoning is kept here as
/// history because it was sound for the arrangement it described:
///
/// > *An event must not read as a task. A task block is a neutral surface wearing a wash of its
/// > list colour plus a leading colour strip and a completion circle; an event has none of those,
/// > so the plate* is *the affordance. A day of raw iCal hues would shout louder than the tasks
/// > beside it, which is backwards for the half of the schedule you cannot edit.*
///
/// The owner's instruction inverts the assignment: an **event** now takes the `rail` treatment and
/// a **task** takes the `plate` treatment. The argument above survives as the reason the two
/// treatments must stay *distinguishable*; it is no longer the reason either one is assigned where
/// it is. Functional affordances did not move with the paint — a task keeps its completion circle,
/// an event keeps its recurrence glyph — so the block still says which it is even where the two
/// plates are closest.
///
/// Because the assignment has moved once it can move again, so no symbol here is called
/// `eventFill` or `taskTitleColor`. A call site reads `railFill(for:)` / `plateFill(for:)` and the
/// *view* says which object it is painting.
///
/// ## What both treatments share
///
/// 1. Saturation is the whole of "which calendar is this", so it is left nearly (plate) or
///    entirely (rail plate) intact. What gets pulled is *luminance*, solved to a fixed target
///    rather than clamped by a brightness ceiling — solving for luminance is what makes the result
///    hue-neutral, since a yellow and a blue at the same `brightness` are nowhere near the same
///    lightness.
/// 2. Every content tier is solved against the plate it actually lands on, so the state ladder
///    cannot quietly push a label under AA.
///
/// ## Why luminance alone was not enough for the rail plate (T-3168)
///
/// Point 1 above is half true, and T-3168 is the half it missed. Solving to a luminance target
/// does make the result hue-neutral *in lightness*. It does nothing at all about **chroma**, and
/// the two are not the same axis: relative luminance is weighted `0.2126 R / 0.7152 G / 0.0722 B`,
/// so a blue has to spend nearly the whole gamut to reach the Y a green reaches with almost no
/// colour at all. Measured on the T-3160 hue sweep, the rail plate at rest came out at OKLab
/// chroma 0.039 for a cyan, 0.064 for a mid blue — and **0.134 for `#3d0000`, 0.234 for
/// `#0000ff`**. One luminance, a six-fold spread of colourfulness.
///
/// That spread is not cosmetic, because the eye does not read luminance. The
/// **Helmholtz–Kohlrausch effect** is the documented result that a more saturated sample is judged
/// *brighter* than a less saturated one at the same luminance, with the brightness-to-luminance
/// ratio rising as chroma rises. WCAG 2.x does not model it, and neither does APCA; both are
/// luminance-only. So the two deep hues above sat at Y = 0.030, four times darker than the task
/// plate at Y = 0.098 *by measurement*, and read as the loudest blocks on the canvas — the exact
/// hierarchy T-3160's darker plate existed to create, inverted.
///
/// The fix is `railPlateChromaCeiling`: a ceiling on the rail plate's OKLab chroma, applied **at
/// constant luminance** by walking saturation down and re-solving brightness. Holding Y exactly is
/// what makes it free — every contrast ratio in this file is `(L1 + 0.05) / (L2 + 0.05)` over two
/// luminances, so a plate that keeps its Y keeps every ratio solved against it, to the last digit.
/// The ceiling touches the **plate only**. `railColor` is untouched, because the rail is the
/// identity marker and laundering it is the one thing this treatment cannot afford.
///
/// The unprefixed legacy spellings (`fill`, `fillLuminance`, `primaryLabelColor`, …) are the
/// `plate` treatment under its historical name and are kept live for call sites that have not been
/// renamed; they forward and add nothing.
enum CadenceCalendarEventStyle {

    // MARK: - Plate treatment

    /// Fraction of the calendar's own saturation the plate fill keeps.
    ///
    /// Deliberately near 1: this is the component that says *which* calendar, and pulling it back
    /// is exactly what produced the brown/olive fills. The 10% it does give up is what keeps a
    /// fully-saturated primary from reading as raw paint next to its neighbours.
    static let plateSaturationScale: Double = 0.90

    /// Relative luminance (WCAG Y) the plate fill is solved to, per interaction state.
    ///
    /// Rest sits at 0.098 because that is where the *secondary* label clears AA: `Theme.onColor`
    /// lands at 7.09:1 and `Theme.onColorSecondary` — the small time range and calendar name — at
    /// 4.64:1, for the lightest calendar colour worth planning for. Anywhere brighter and that line
    /// drops under 4.5:1; hue is bought with saturation above, not with luminance here.
    ///
    /// One hue misses: a calendar *darker than its own plate* — a near-black `#3d0000` is the one
    /// that exists — pushes a more saturated colour through the 0.75 wash and lands the rest-state
    /// secondary at **4.46:1**, 0.04 short of AA, and did so before T-3160 too. It is measured and
    /// named by `thePlateSecondaryTierClearsAAExceptOnAHueDarkerThanItsOwnPlate` rather than left
    /// to be rediscovered; the fix is a `Theme.onColorSecondary` change, which is a palette
    /// decision and not a paint swap's to make.
    ///
    /// The ladder is 4.4 L* then 3.8 L* wide — several times the ~1 L* just-noticeable step, so
    /// rest / active / selected stay legibly separate — and `Theme.onColor` never falls below
    /// 5.25:1 even at the top. `isActive` is hover on macOS and press/selection on iOS.
    static func plateLuminance(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.150 }
        if isActive { return 0.124 }
        return 0.098
    }

    /// Plate fill for a timeline block.
    static func plateFill(for tintColor: Color, isSelected: Bool = false, isActive: Bool = false) -> Color {
        solvedFill(
            for: tintColor,
            saturationScale: plateSaturationScale,
            luminance: plateLuminance(isSelected: isSelected, isActive: isActive)
        )
    }

    /// Plate fill for a month-grid or all-day chip. The same solve as `plateFill(for:)` — a chip and
    /// a block are the same object at two sizes, and they used to drift apart because the chip
    /// composited the raw colour over the cell instead of being solved for its own luminance.
    static func plateChipFill(for tintColor: Color, isActive: Bool = false) -> Color {
        solvedFill(
            for: tintColor,
            saturationScale: plateSaturationScale,
            luminance: plateLuminance(isActive: isActive)
        )
    }

    /// Primary content on a plate fill. Unconditionally `Theme.onColor` — the fill is solved so
    /// that this always holds, which is the point of solving it.
    static let platePrimaryLabelColor = Theme.onColor

    /// Secondary content on a plate fill: the time range, the calendar name.
    ///
    /// Rises to the primary tier while the block is active or selected. At rest 0.75 alpha clears
    /// 4.5:1, but the active and selected fills are brighter by design, and a fixed 0.75 would sink
    /// to 3.57:1 there. Lifting the label instead of holding the fill down is what lets the state
    /// ladder exist at all.
    static func plateSecondaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        isSelected || isActive ? Theme.onColor : Theme.onColorSecondary
    }

    /// Tertiary content on a plate fill: incidental glyphs. Lifted one tier for the same reason as
    /// `plateSecondaryLabelColor`; as a glyph rather than text it only owes the 3:1 non-text bar,
    /// which it holds in every state.
    static func plateTertiaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        isSelected || isActive ? Theme.onColorSecondary : Theme.onColorTertiary
    }

    // MARK: Plate treatment, legacy spellings

    static var fillSaturationScale: Double { plateSaturationScale }

    static func fillLuminance(isSelected: Bool = false, isActive: Bool = false) -> Double {
        plateLuminance(isSelected: isSelected, isActive: isActive)
    }

    static func fill(for calendarColor: Color, isSelected: Bool = false, isActive: Bool = false) -> Color {
        plateFill(for: calendarColor, isSelected: isSelected, isActive: isActive)
    }

    static func chipFill(for calendarColor: Color, isActive: Bool = false) -> Color {
        plateChipFill(for: calendarColor, isActive: isActive)
    }

    static var primaryLabelColor: Color { platePrimaryLabelColor }

    static func secondaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        plateSecondaryLabelColor(isSelected: isSelected, isActive: isActive)
    }

    static func tertiaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        plateTertiaryLabelColor(isSelected: isSelected, isActive: isActive)
    }

    // MARK: - Rail treatment

    /// Fraction of the calendar's own saturation the **rail** keeps.
    ///
    /// Near-full, because in Apple Calendar the rail is the one element that is allowed to read as
    /// raw paint: it is the identity marker, and everything else on the block has been pulled down
    /// so that it can be. The 4% it gives up only takes the hard edge off a 100%-saturation primary.
    static let railSaturationScale: Double = 0.96

    /// Floor the rail's relative luminance is lifted to when its own hue cannot reach it.
    ///
    /// The rail is a non-text UI component, so it owes WCAG's **3:1**, and it owes it against the
    /// app background rather than against its own plate — the plate is the same hue and cannot
    /// separate from it by chroma. `Theme.bg` sits at Y = 0.0028, so 3:1 needs Y >= 0.1083; 0.120
    /// lands at **3.22:1** with margin for a rounded `colorHex`.
    ///
    /// Most calendar colours clear this on their own at full brightness — a mid blue such as
    /// `#4a9eff` reaches Y = 0.32 — so the floor is inert for everything the palettes ship. It
    /// binds only on the deep end of the gamut: a primary `#0000ff` maxes out at Y = 0.075 with its
    /// chroma intact, and is desaturated to s = 0.75 to reach the floor. That is the honest
    /// trade — a rail nobody can see is worse than a rail that is 25% less blue — and it is spelled
    /// as a floor rather than a target so that it never *removes* chroma it did not have to.
    static let railMinimumLuminance: Double = 0.120

    /// Width of the leading rail, in points. One number, because a rail that is 3pt on one platform
    /// and 4pt on the other is the drift this file exists to prevent.
    static let railWidth: CGFloat = 3

    /// Saturation the rail treatment's **plate** keeps: all of it.
    ///
    /// Unlike the plate treatment, which can afford to shade saturation back because its fill is
    /// bright enough to carry hue on luminance alone, this plate lives at Y = 0.03–0.06. Down
    /// there chroma is the *only* thing separating it from black, so none of it is given away.
    static let railPlateSaturationScale: Double = 1.00

    /// Relative luminance (WCAG Y) the rail treatment's tinted plate is solved to, per state.
    ///
    /// Much darker than `plateLuminance`, and that is the whole point: a title drawn **in the hue**
    /// has a far tighter budget than `Theme.onColor` did, and every point of plate luminance is
    /// paid for twice over in how washed-out the title has to become to clear 4.5:1 above it.
    ///
    /// The ladder is **4.9 L* then 4.5 L*** wide (L* 20.0 / 25.0 / 29.4), which is slightly wider
    /// than the plate treatment's 4.4 / 3.8 and many times the ~1 L* just-noticeable step, so rest
    /// / active / selected stay legibly apart. Against `Theme.bg` the plate reads 1.52:1 at rest
    /// and 2.08:1 selected — deliberately quiet, because here the rail is what announces the block
    /// and the plate only has to say where it ends. `isActive` is hover on macOS, press/selection
    /// on iOS.
    static func railFillLuminance(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.060 }
        if isActive { return 0.044 }
        return 0.030
    }

    /// Contrast ratio the rail treatment's **title** is solved to against its own plate.
    ///
    /// 5.1:1 rather than a bare 4.5:1. The margin is not decoration: the solve runs over a
    /// `colorHex` that has already been rounded to 8 bits per channel and then through
    /// `Color(hue:saturation:brightness:)`, and a title sitting exactly on the floor would be one
    /// rounding step from failing it. The margin costs about 4 L* of extra lightness at the rest
    /// plate (L* 62.5 at a bare 4.5:1, L* 66.4 at 5.1:1), which is the price of not shipping a
    /// title whose AA depends on how a hex rounded.
    static let railTitleContrastTarget: Double = 5.1

    /// Contrast ratio the rail treatment's **secondary** tier — time range, location — is solved to.
    ///
    /// **This tier is narrow and that is a real cost, stated rather than hidden.** `Theme.onColor`
    /// over `Theme.onColorSecondary` gives the plate treatment roughly 13 L* to dim into. Here the
    /// title is itself in the hue, so it is already close to the floor, and everything between the
    /// title and 4.5:1 is all the room there is: 4.6 vs 5.1 is **3.2 L*** at the rest plate and
    /// 3.4 L* at the selected one, three or four just-noticeable steps. It reads as a dimmer line of the same colour, not as a different
    /// weight of ink. Buying more would mean either pushing the title brighter (more washed-out
    /// hue, which is the thing this treatment exists to avoid) or dropping the secondary under AA,
    /// and neither is worth 3 L*.
    static let railSecondaryContrastTarget: Double = 4.6

    /// Contrast ratio the rail treatment's **tertiary** tier — incidental glyphs such as the
    /// recurrence marker — is solved to. As a glyph rather than text it owes the 3:1 non-text bar,
    /// not 4.5:1, which is where the rest of the ladder's room comes from: at 3.2:1 it sits about
    /// 11 L* below the secondary line, so the glyph tier is the one that is genuinely separable.
    static let railTertiaryContrastTarget: Double = 3.2

    /// Greatest OKLab chroma the rail treatment's **plate** may carry, as a fraction of that
    /// plate's own perceptual lightness.
    ///
    /// Stated as a ratio rather than as three chroma numbers so it cannot drift from the ladder it
    /// belongs to: `railPlateChromaCeiling` multiplies this by `CadenceOKLab.neutralLightness` of
    /// the plate's luminance, so moving `railFillLuminance` moves the ceiling with it — the same
    /// discipline `railLabelColor` already uses to derive each label tier from its own plate.
    ///
    /// ## Why 0.25, with both ends of the window measured
    ///
    /// The number is not free. It is squeezed from both sides, and the admissible window turns out
    /// to be narrow enough that picking the middle of it is nearly the whole decision.
    ///
    /// **From below — do not launder an ordinary calendar.** Across Cadence's three shipped accent
    /// palettes, eighteen colours, the rail plate's chroma against this same anchor runs 0.126
    /// (the `#4fd6e0` teal) to 0.281 (the `#ff5a5f` red), and every non-red accent tops out at
    /// 0.230. So anything under about **0.231** starts removing chroma from blues, greens and
    /// purples that were never the problem, which is the thing a ceiling must not do.
    ///
    /// **From above — the hierarchy has to survive.** The loudest plate any calendar colour can
    /// now produce *is* the ceiling, by construction. For an event to stay quieter than a task,
    /// that worst case has to stay under the plate treatment's chroma for an ordinary mid blue —
    /// `#4a9eff`, which is also `Theme.blueHex`. That bound is 0.289 at rest, 0.278 active and
    /// **0.270** selected, and the tightest one is the one that counts.
    ///
    /// The window is therefore roughly **[0.231, 0.270]**, and 0.25 is its middle. Inside it
    /// exactly one of the eighteen accents is touched — the `#ff5a5f` red, which is also where the
    /// dark-UI literature puts the worst halation on a dark surface — and on the T-3160 sweep it
    /// binds on exactly the two hues T-3168 was filed about: `#3d0000` measures 0.432 here and
    /// `#0000ff` measures 0.752, three times the band every ordinary hue lives in.
    ///
    /// ## What it costs
    ///
    /// A vivid calendar's plate gives up chroma. `#0000ff`'s rest plate goes from (0, 0, 173) at
    /// chroma 0.234 — a saturated royal blue, and the loudest block on the canvas — to (44, 44, 88)
    /// at 0.078, a quiet navy. `#3d0000`'s goes from (105, 0, 0) at 0.134 to (84, 32, 32) at the
    /// same 0.078. Both land within 1.22x of an ordinary blue event plate, against 3.66x before.
    ///
    /// The identity that chroma was carrying is not lost, because the plate was never where it
    /// lived: the rail still keeps 0.96 of the calendar's chroma at full brightness and is not
    /// touched by any of this, and the title is still drawn **in the hue**, solved to
    /// `railTitleContrastTarget` against a plate whose luminance has not moved a digit.
    ///
    /// It is spelled as a ceiling, not a target, for the same reason `railMinimumLuminance` is
    /// spelled as a floor: it must never remove chroma it did not have to.
    static let railPlateChromaRatio: Double = 0.25

    /// The rail plate's chroma ceiling at a given state, derived from that state's own luminance.
    static func railPlateChromaCeiling(isSelected: Bool = false, isActive: Bool = false) -> Double {
        railPlateChromaRatio * CadenceOKLab.neutralLightness(
            relativeLuminance: railFillLuminance(isSelected: isSelected, isActive: isActive)
        )
    }

    /// The leading rail: the calendar's hue at near-full chroma, lifted to full brightness, and
    /// desaturated only if that still leaves it under `railMinimumLuminance`.
    ///
    /// **Stateless on purpose.** The rail is the answer to "which calendar is this", and an
    /// identity marker that changes colour on hover is a different calendar. The state ladder is
    /// carried by the plate and the labels below it.
    static func railColor(for calendarColor: Color) -> Color {
        let source = hsb(of: calendarColor)
        let saturation = source.saturation * railSaturationScale
        if relativeLuminance(hue: source.hue, saturation: saturation, brightness: 1) >= railMinimumLuminance {
            return Color(hue: source.hue, saturation: saturation, brightness: 1)
        }
        return desaturatedTint(hue: source.hue, ceiling: saturation, luminance: railMinimumLuminance)
    }

    /// The dark tinted plate behind a rail-treated block.
    static func railFill(for calendarColor: Color, isSelected: Bool = false, isActive: Bool = false) -> Color {
        cappedFill(
            for: calendarColor,
            luminance: railFillLuminance(isSelected: isSelected, isActive: isActive),
            chromaCeiling: railPlateChromaCeiling(isSelected: isSelected, isActive: isActive)
        )
    }

    /// The rail treatment's plate at chip size. Same solve, same reason as `plateChipFill`.
    static func railChipFill(for calendarColor: Color, isActive: Bool = false) -> Color {
        cappedFill(
            for: calendarColor,
            luminance: railFillLuminance(isActive: isActive),
            chromaCeiling: railPlateChromaCeiling(isActive: isActive)
        )
    }

    /// The title, **in the calendar's own hue**, lightened until it clears
    /// `railTitleContrastTarget` against the plate it is drawn on.
    ///
    /// The target luminance is *derived* from the plate rather than tabulated —
    /// `ratio * (plate + 0.05) - 0.05` is the WCAG definition rearranged — so moving
    /// `railFillLuminance` moves this with it and the pair cannot drift apart. At the three plate
    /// stops the title lands at Y = 0.358 / 0.429 / 0.511.
    static func railTitleColor(for calendarColor: Color, isSelected: Bool = false, isActive: Bool = false) -> Color {
        railLabelColor(
            for: calendarColor,
            ratio: railTitleContrastTarget,
            isSelected: isSelected,
            isActive: isActive
        )
    }

    /// Time range and location on a rail-treated block. See `railSecondaryContrastTarget` for how
    /// little room this tier has and why.
    static func railSecondaryLabelColor(
        for calendarColor: Color,
        isSelected: Bool = false,
        isActive: Bool = false
    ) -> Color {
        railLabelColor(
            for: calendarColor,
            ratio: railSecondaryContrastTarget,
            isSelected: isSelected,
            isActive: isActive
        )
    }

    /// Incidental glyphs on a rail-treated block — the recurrence marker is the one that matters,
    /// and it stays with the event through the swap.
    static func railTertiaryLabelColor(
        for calendarColor: Color,
        isSelected: Bool = false,
        isActive: Bool = false
    ) -> Color {
        railLabelColor(
            for: calendarColor,
            ratio: railTertiaryContrastTarget,
            isSelected: isSelected,
            isActive: isActive
        )
    }

    /// Hairline of the rail's colour drawn around the tinted plate, so a block on a busy canvas has
    /// an edge without a second fill. Quiet at rest because the rail already marks the leading edge.
    static func railBorderOpacity(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.52 }
        if isActive { return 0.38 }
        return 0.24
    }

    private static func railLabelColor(
        for calendarColor: Color,
        ratio: Double,
        isSelected: Bool,
        isActive: Bool
    ) -> Color {
        let plate = railFillLuminance(isSelected: isSelected, isActive: isActive)
        return solvedTint(
            for: calendarColor,
            saturationScale: 1.0,
            luminance: (ratio * (plate + 0.05)) - 0.05
        )
    }

    // MARK: - Opacity ladders

    static func blockAccentOpacity(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.48 }
        if isActive { return 0.34 }
        return 0.18
    }

    /// Hairline of the calendar's *raw* colour drawn on the solved fill, so the edge reads as a
    /// lit rim of the same hue.
    static func chipBorderOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.60 : 0.45
    }

    static func surfaceOpacity(isActive: Bool) -> Double {
        isActive ? 0.92 : 0.82
    }

    static func tintOpacity(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.24 }
        if isActive { return 0.18 }
        return 0.12
    }

    static func borderOpacity(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.46 }
        if isActive { return 0.34 }
        return 0.22
    }

    static func chipTintOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.18 : 0.11
    }

    // MARK: - Luminance solve

    /// Keeps the hue, scales the saturation, and picks the brightness whose sRGB relative luminance
    /// is `target`. Used for the fills, which are always darker than their source.
    private static func solvedFill(
        for calendarColor: Color,
        saturationScale: Double,
        luminance target: Double
    ) -> Color {
        let source = hsb(of: calendarColor)
        return Color(
            hue: source.hue,
            saturation: source.saturation * saturationScale,
            brightness: solvedBrightness(
                hue: source.hue,
                saturation: source.saturation * saturationScale,
                luminance: target
            )
        )
    }

    /// `solvedFill`, then held to a **chroma ceiling at that same luminance**.
    ///
    /// Two knobs again, in a fixed order, and the order is what makes this safe. Brightness solves
    /// for the luminance target first, exactly as `solvedFill` does. If the result is already
    /// inside the ceiling — which it is for every ordinary calendar hue — nothing else happens and
    /// no chroma is removed. Only when it is outside does saturation walk down, and every step of
    /// that walk **re-solves brightness for the same target**, so the colour that comes back has
    /// the luminance it was asked for whatever its chroma ended up being.
    ///
    /// That invariant is the whole argument for doing it this way. Every contrast guarantee in
    /// this file is `(L1 + 0.05) / (L2 + 0.05)` over two relative luminances and nothing else — so
    /// a plate that keeps its Y keeps every ratio solved against it unchanged, to the digit. The
    /// ceiling therefore buys a quieter plate for exactly zero contrast.
    ///
    /// Chroma falls monotonically as saturation falls at fixed luminance — the colour is walking
    /// toward the grey of that luminance, which has no chroma at all — so a bisection converges,
    /// and `low` is returned because `low` is the end of the bracket known to be *under* the
    /// ceiling.
    ///
    /// That choice is correctness-by-construction rather than a visible difference, and T-3168's
    /// mutation run says so out loud: returning `high` instead **survived**, and is a measured
    /// no-op. After 20 steps the two ends of the bracket are 9.5e-7 apart in saturation and 3.3e-7
    /// apart in chroma — for `#0000ff`'s rest plate both ends round to the *same* 8-bit colour,
    /// (44, 44, 88). Nothing a screen can show and nothing an assertion should pretend to see; the
    /// tolerance that would catch it is four orders of magnitude inside float noise. `low` is
    /// still the right end to return, because it is the one the ceiling's definition guarantees.
    ///
    /// **What it costs, since `solvedBrightness` claims a month grid runs it once per chip.** The
    /// common path is one extra brightness solve plus one OKLab conversion — the early return.
    /// Only a hue that is actually over the ceiling pays for the nested search, and that search is
    /// a bisection whose every step contains a brightness bisection, so it is roughly twenty times
    /// the old cost for those hues alone. It is still only plain arithmetic with no allocation,
    /// and the hues it binds on are the rare ones, which is the trade this is worth making.
    private static func cappedFill(
        for calendarColor: Color,
        luminance target: Double,
        chromaCeiling ceiling: Double
    ) -> Color {
        let source = hsb(of: calendarColor)
        let saturation = source.saturation * railPlateSaturationScale
        if chroma(hue: source.hue, saturation: saturation, luminance: target) <= ceiling {
            return Color(
                hue: source.hue,
                saturation: saturation,
                brightness: solvedBrightness(hue: source.hue, saturation: saturation, luminance: target)
            )
        }

        var low = 0.0
        var high = saturation
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if chroma(hue: source.hue, saturation: mid, luminance: target) > ceiling {
                high = mid
            } else {
                low = mid
            }
        }
        return Color(
            hue: source.hue,
            saturation: low,
            brightness: solvedBrightness(hue: source.hue, saturation: low, luminance: target)
        )
    }

    /// OKLab chroma of this hue and saturation once brightness has been solved to `target`.
    private static func chroma(hue: Double, saturation: Double, luminance target: Double) -> Double {
        let components = rgbComponents(
            hue: hue,
            saturation: saturation,
            brightness: solvedBrightness(hue: hue, saturation: saturation, luminance: target)
        )
        return CadenceOKLab.chroma(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }

    /// Keeps the hue and solves for `target` with whichever knob can reach it — used for the label
    /// tiers, which are usually *lighter* than their source and therefore not always reachable by
    /// brightness alone.
    ///
    /// At a fixed hue and saturation, luminance rises with brightness, so brightness is the first
    /// choice: it leaves chroma exactly where the calendar put it. But a saturated deep hue runs
    /// out — fully-saturated blue tops out at Y = 0.072 even at brightness 1, nowhere near the
    /// Y = 0.36+ a title needs above its plate. At that point the only remaining direction is
    /// *down* in saturation at full brightness, where luminance rises monotonically as the colour
    /// walks toward white. That second branch is what turns a navy calendar into a light-blue
    /// title instead of an unreadable one, and it is entered only when the first branch cannot
    /// reach the target — so a hue with chroma to spare keeps all of it.
    private static func solvedTint(
        for calendarColor: Color,
        saturationScale: Double,
        luminance target: Double
    ) -> Color {
        let source = hsb(of: calendarColor)
        let saturation = source.saturation * saturationScale
        if relativeLuminance(hue: source.hue, saturation: saturation, brightness: 1) >= target {
            return Color(
                hue: source.hue,
                saturation: saturation,
                brightness: solvedBrightness(hue: source.hue, saturation: saturation, luminance: target)
            )
        }
        return desaturatedTint(hue: source.hue, ceiling: saturation, luminance: target)
    }

    /// Brightness whose luminance is `target` at this hue and saturation.
    ///
    /// Luminance is monotonic in brightness at fixed hue/saturation, so a bisection converges
    /// without inverting the sRGB transfer curve. 20 steps resolve brightness far finer than one
    /// 8-bit code point, and the whole solve is plain arithmetic — no allocation per step, which
    /// matters because a month grid runs this once per chip. `high` is returned rather than the
    /// midpoint because `high` is the end of the bracket that is known to be *at or above* the
    /// target, and every caller is spending the result against a contrast floor.
    private static func solvedBrightness(hue: Double, saturation: Double, luminance target: Double) -> Double {
        var low = 0.0
        var high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if relativeLuminance(hue: hue, saturation: saturation, brightness: mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return high
    }

    /// The **most saturated** colour at this hue and full brightness whose luminance still reaches
    /// `target`. Luminance falls as saturation rises here, so the bracket runs the other way:
    /// `low` is the whiter end and is the one known to clear the target.
    private static func desaturatedTint(hue: Double, ceiling: Double, luminance target: Double) -> Color {
        var low = 0.0
        var high = max(ceiling, 0)
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if relativeLuminance(hue: hue, saturation: mid, brightness: 1) < target {
                high = mid
            } else {
                low = mid
            }
        }
        return Color(hue: hue, saturation: low, brightness: 1)
    }

    private static func hsb(of color: Color) -> (hue: Double, saturation: Double, brightness: Double) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        #if canImport(AppKit)
        let source = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #elseif canImport(UIKit)
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif
        return (Double(hue), Double(saturation), Double(brightness))
    }

    static func relativeLuminance(hue: Double, saturation: Double, brightness: Double) -> Double {
        let components = rgbComponents(hue: hue, saturation: saturation, brightness: brightness)
        return (0.2126 * linearized(components.red))
            + (0.7152 * linearized(components.green))
            + (0.0722 * linearized(components.blue))
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func rgbComponents(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let index = Int(sector) % 6
        let fraction = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - (saturation * fraction))
        let rising = brightness * (1 - (saturation * (1 - fraction)))
        switch index {
        case 0: return (brightness, rising, low)
        case 1: return (falling, brightness, low)
        case 2: return (low, brightness, rising)
        case 3: return (low, falling, brightness)
        case 4: return (rising, low, brightness)
        default: return (brightness, low, falling)
        }
    }
}

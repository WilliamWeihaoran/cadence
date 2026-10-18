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
/// - **`rail*`** — Apple Calendar's look: a leading vertical rail at the calendar's own chroma, a
///   much darker tinted plate, and the **title in the hue** rather than in white.
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
/// The ceiling touches the **plate only**.
///
/// ## Where the colour ended up living, and why the plate is not it
///
/// The paragraph above used to end *"`railColor` is untouched, because the rail is the identity
/// marker and laundering it is the one thing this treatment cannot afford."* Both halves of that
/// sentence are now the other way round, and the device photograph is what turned them over:
/// **the plate is laundered hard and the rail is not laundered at all.** The ceiling sits at 0.12
/// rather than 0.25, so it binds on every colour any palette ships, and `railColor` returns the
/// calendar's own hue and saturation rather than the title's solved tint. The identity the rail
/// was protected to carry is exactly what it now carries, in three points of width, with a
/// near-neutral wash behind it — which is the distribution the owner's Apple Calendar target has
/// and the one Cadence did not. The reasoning for each number is on the two symbols themselves.
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
    /// ## It was 0.25, and 0.25 was answering a different question ([[T-3168]])
    ///
    /// T-3168 set this to 0.25 with a window measured from both ends, and the lower end of that
    /// window was the rule **"do not launder an ordinary calendar"**: across Cadence's three
    /// palettes the least colourful accent's plate measures 0.0391, so anything under about 0.231
    /// starts taking chroma off blues, greens and purples that were never the problem.
    ///
    /// That rule was right *while the plate was where the calendar's colour lived*. It is no
    /// longer, and the two halves of this ticket are one change: `railColor` now carries the
    /// calendar's own chroma, so the plate does not have to, and a plate that keeps hue is not
    /// preserving identity — it is competing with the rail for it. The owner's target says so in
    /// as many words: *"Apple's events are a near-neutral wash with a saturated left rail and
    /// coloured text; the colour lives in the rail. Ours are filled cards whose whole body carries
    /// hue."* **So the old lower bound is not relaxed here, it is inverted: laundering an ordinary
    /// calendar's plate is now the thing this constant is for.**
    ///
    /// ## Why 0.12, with both ends of the new window measured
    ///
    /// **From above, and this end is derived rather than judged.** "The fill is a near-neutral
    /// wash" has to be a property of the *treatment*, not of which hue the account happened to
    /// pick — a ceiling that only a pathological colour ever reaches leaves every ordinary
    /// calendar exactly as the owner photographed it. So the ceiling must bind on the **least**
    /// colourful swatch any shipped palette offers. That is `#4fd6e0`, whose uncapped rest plate
    /// measures **0.0391**; against this anchor (`cbrt(0.030)` = 0.3107) it puts the bound at
    /// **0.1258**. At 0.12 the ceiling binds on **all eighteen** accents and on five of the seven
    /// sweep hues — the two it misses are `#ffffff` and `#000000`, which have no chroma to take.
    /// At 0.20 it binds on eight of eighteen; at 0.25 on one.
    ///
    /// **From below — the plates must not collapse into one grey.** The pale `#ede7d3` control is
    /// the fixture's "already quiet" calendar and its plate carries chroma **0.0075**, below every
    /// ceiling considered here and therefore never touched by one. A ceiling that pulled a vivid
    /// calendar under about twice that would make a deep red's plate no more coloured than a
    /// cream one's, which is the "two calendars now look the same" failure T-3168 was watched for.
    /// That puts the floor at a ceiling of 0.015, i.e. a ratio of **0.048**.
    ///
    /// The window is therefore **[0.048, 0.126]**, and **0.12 is deliberately at the top of it
    /// rather than in the middle** — the same reason this is spelled as a ceiling and not as a
    /// target. It must never remove chroma it did not have to, so the right value is the largest
    /// one at which the property still holds, with the remaining 0.006 left as margin for a
    /// `colorHex` that has already been rounded to 8 bits. Rendered side by side at 0.25 / 0.18 /
    /// 0.12 / 0.08 the step that stops the body reading as a coloured card is the one into 0.12;
    /// 0.08 is past it and flattens a green and a teal into the same slate.
    ///
    /// ## What it costs, measured
    ///
    /// Every plate above the ceiling lands on **chroma 0.0373** at rest (0.0423 active, 0.0469
    /// selected). `#3d0000`'s rest plate goes from (84, 32, 32) to **(67, 42, 42)**, `#0000ff`'s
    /// from (44, 44, 88) to **(47, 47, 67)**, and an ordinary `#4a9eff` — untouched at 0.25 —
    /// from (23, 49, 80) to **(35, 50, 67)**. The pale control stays exactly (50, 48, 44), which
    /// is the measurement that says this ceiling still only ever removes, never adds.
    ///
    /// **And it still costs no contrast, for the same arithmetic as before:** the cap re-solves
    /// brightness at every step of its saturation walk, so Y is held at 0.030 / 0.044 / 0.060 to
    /// the bisection's precision, and every ratio in this file is `(L1 + 0.05) / (L2 + 0.05)` over
    /// two luminances and nothing else. Re-measured rather than assumed: across the 63 tier
    /// measurements the largest ratio that moved at all moved by **1.2e-05**, which is four orders
    /// of magnitude inside one 8-bit code point. All 63 still land on 5.1 / 4.6 / 3.2 to four
    /// decimal places.
    static let railPlateChromaRatio: Double = 0.12

    /// The rail plate's chroma ceiling at a given state, derived from that state's own luminance.
    static func railPlateChromaCeiling(isSelected: Bool = false, isActive: Bool = false) -> Double {
        railPlateChromaRatio * CadenceOKLab.neutralLightness(
            relativeLuminance: railFillLuminance(isSelected: isSelected, isActive: isActive)
        )
    }

    /// The leading rail: **the calendar's own colour, at all the chroma it can carry**
    /// ([[T-3168]]).
    ///
    /// ## This is the second half of one change, and it reverses the first half
    ///
    /// T-3168's first lever made the rail adopt `railTitleColor(for:)` — the title's *solved*
    /// colour, lightened and desaturated to clear 5.1:1 over the plate. It was read off an Apple
    /// Calendar screenshot in which a block's rail and its title looked like one colour, and it
    /// answered a real complaint: the rail was the loudest element in the frame.
    ///
    /// **It was then looked at on a device, which had never happened, and the picture disagreed.**
    /// With a deep red, a pure blue and a pale olive side by side, the deep red was still the
    /// loudest thing on screen; the pale one nearly vanished; and none of the three read as Apple
    /// Calendar. The reading that explains all three at once is that *the structure was already
    /// Apple's and the distribution of colour was not*: Apple puts the hue in three points of rail
    /// and leaves the body a near-neutral wash, while Cadence spread a middling amount of hue over
    /// the rail, the title, the rim **and** the whole plate — so no part of the block was neutral
    /// and the plate, being the largest, was what the eye read.
    ///
    /// So the hue goes back into the rail and comes out of the plate, in one change:
    /// `railPlateChromaRatio` drops from 0.25 to 0.12 and this function stops laundering itself.
    /// Neither half works alone — a saturated rail over a hued plate is the block that was
    /// photographed as too loud, and a neutral plate under a washed rail is a block with no
    /// calendar identity anywhere.
    ///
    /// ## What it returns
    ///
    /// The calendar's **own hue and saturation**, at the brightness that carries the most chroma —
    /// full brightness — and lifted to `railMinimumLuminance` only when that is not enough to
    /// clear the 3:1 non-text bar against `Theme.bg`.
    ///
    /// Saturation is taken whole rather than at the 0.96 the pre-T-3168 rail used. That 4% existed
    /// to stop a fully-saturated primary reading as raw paint beside its neighbours, and the
    /// neighbours have changed: the plate it sits on now carries a third of the chroma it did, so
    /// the rail is the one place the calendar's colour appears at strength and that is the point
    /// of it. The haircut was worth ΔC = 0.0018 on `#3d0000` — well inside a just-noticeable
    /// difference — against the cost of the rail not quite being the colour the account chose.
    ///
    /// ## The floor is live again, and that is the measurement to keep
    ///
    /// Under the title-coloured rail `railMinimumLuminance` was inert by arithmetic: a rest title
    /// solves to Y 0.358, three times the 0.120 floor, at every hue. It binds again now, on
    /// exactly one of the seven sweep hues — `#0000ff`, which maxes out at Y 0.0756 with its
    /// chroma intact and is desaturated to s = 0.75 to reach the floor. That is the honest trade
    /// the floor was written for and it is back to doing its job rather than being carried.
    ///
    /// ## Two consequences, stated rather than discovered later
    ///
    /// 1. **The rail is no longer the same colour as the title, and for a light calendar it is
    ///    brighter than the title.** `#ede7d3` goes from a dull (166, 161, 147) at Y 0.358 to
    ///    (255, 249, 227) at Y 0.943 — which is the direct answer to "the pale event nearly
    ///    vanishes", since nothing else on that block clears 2:1 against the canvas. A
    ///    zero-saturation calendar (`#000000`, `#ffffff`) therefore gets a white rail, as it did
    ///    before T-3168.
    /// 2. **Still stateless, and that pin is unchanged.** The rail answers "which calendar is
    ///    this", and an identity marker that changes colour on hover is a different calendar. It
    ///    takes no `isSelected`/`isActive` and reads nothing that does, so it cannot acquire a
    ///    state ladder by someone adding a defaulted argument upstream.
    ///
    /// The rim drawn around the block reads this same function at `railBorderOpacity`, so a rail
    /// that gained chroma and lost luminance makes the rim *quieter*, not louder: `#3d0000`'s rest
    /// rim composites to **(112, 32, 32)** against the **(125, 53, 53)** that was sampled off the
    /// device before this change — a measurement, not a model: that pixel was read out of
    /// `scratchpad/raillever/before-04.png` and the simple sRGB composite reproduces it exactly.
    static func railColor(for calendarColor: Color) -> Color {
        let source = hsb(of: calendarColor)
        guard relativeLuminance(hue: source.hue, saturation: source.saturation, brightness: 1)
            < railMinimumLuminance
        else {
            return Color(hue: source.hue, saturation: source.saturation, brightness: 1)
        }
        return desaturatedTint(
            hue: source.hue,
            ceiling: source.saturation,
            luminance: railMinimumLuminance
        )
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
    /// inside the ceiling — which, since the ratio moved to 0.12, is true only of a calendar that
    /// is already near-neutral — nothing else happens and no chroma is removed. Only when it is
    /// outside does saturation walk down, and every step of
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
    /// **What it costs, since `solvedBrightness` claims a month grid runs it once per chip, and
    /// the bill went up.** The early return is one extra brightness solve plus one OKLab
    /// conversion; the nested search is a bisection whose every step contains a brightness
    /// bisection, so it is roughly twenty times the early return. At the old 0.25 that search ran
    /// for two sweep hues and one of eighteen accents and the early return covered everything
    /// else. At 0.12 the search is the **common** path: it runs for every colour any palette
    /// ships. It is still plain arithmetic with no allocation per step — about four hundred
    /// floating-point evaluations per chip — and a month grid is the worst case worth naming if
    /// one ever shows up in a trace. If it does, the fix is a cache keyed on (hue, saturation,
    /// state), not a looser ceiling.
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

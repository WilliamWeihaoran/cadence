import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// How a calendar event is painted, on **both** platforms.
///
/// This used to exist twice. macOS had a luminance-solved fill (`CalendarEventVisualStyle`) with a
/// documented contrast budget; iOS had a hand-tuned `saturation * 0.55, brightness * 0.6` rule —
/// which is precisely the double-hit rule macOS abandoned, and which rendered an orange calendar
/// brown and a green one olive. Two implementations of "what colour is this event" is one too many,
/// so the solve lives here and both platforms read it.
///
/// The rule separates the two jobs the naive version conflates:
///
/// 1. An event must not read as a task. A task block is a neutral surface wearing a wash of its
///    list colour plus a leading colour strip and a completion circle; an event has none of those,
///    so the plate *is* the affordance. A day of raw iCal hues would shout louder than the tasks
///    beside it, which is backwards for the half of the schedule you cannot edit.
/// 2. It must still be recognisably *that* hue. Saturation is the whole of "which calendar is
///    this", so it is left nearly intact. What gets pulled down is *luminance*, solved to a fixed
///    target rather than clamped by a brightness ceiling — solving for luminance is what makes the
///    result hue-neutral, since a yellow and a blue at the same `brightness` are nowhere near the
///    same lightness.
enum CadenceCalendarEventStyle {

    // MARK: - Fill

    /// Fraction of the calendar's own saturation the fill keeps.
    ///
    /// Deliberately near 1: this is the component that says *which* calendar, and pulling it back
    /// is exactly what produced the brown/olive fills. The 10% it does give up is what keeps a
    /// fully-saturated primary from reading as raw paint next to a task card.
    static let fillSaturationScale: Double = 0.90

    /// Relative luminance (WCAG Y) the fill is solved to, per interaction state.
    ///
    /// Rest sits at 0.098 because that is where the *secondary* label clears AA: `Theme.onColor`
    /// lands at 7.09:1 and `Theme.onColorSecondary` — the small time range and calendar name — at
    /// 4.64:1, for the lightest calendar colour worth planning for. Anywhere brighter and that line
    /// drops under 4.5:1; hue is bought with saturation above, not with luminance here.
    ///
    /// The ladder is 4.4 L* then 3.8 L* wide — several times the ~1 L* just-noticeable step, so
    /// rest / active / selected stay legibly separate — and `Theme.onColor` never falls below
    /// 5.25:1 even at the top. `isActive` is hover on macOS and press/selection on iOS.
    static func fillLuminance(isSelected: Bool = false, isActive: Bool = false) -> Double {
        if isSelected { return 0.150 }
        if isActive { return 0.124 }
        return 0.098
    }

    /// Fill for a timeline event block.
    static func fill(for calendarColor: Color, isSelected: Bool = false, isActive: Bool = false) -> Color {
        solvedFill(for: calendarColor, luminance: fillLuminance(isSelected: isSelected, isActive: isActive))
    }

    /// Fill for a month-grid or all-day event chip. The same solve as `fill(for:)` — a chip and a
    /// block are the same object at two sizes, and they used to drift apart because the chip
    /// composited the raw colour over the cell instead of being solved for its own luminance.
    static func chipFill(for calendarColor: Color, isActive: Bool = false) -> Color {
        solvedFill(for: calendarColor, luminance: fillLuminance(isActive: isActive))
    }

    // MARK: - Content on the fill

    /// Primary content on an event fill. Unconditionally `Theme.onColor` — the fill is solved so
    /// that this always holds, which is the point of solving it.
    static let primaryLabelColor = Theme.onColor

    /// Secondary content on an event fill: the time range, the calendar name.
    ///
    /// Rises to the primary tier while the block is active or selected. At rest 0.75 alpha clears
    /// 4.5:1, but the active and selected fills are brighter by design, and a fixed 0.75 would sink
    /// to 3.57:1 there. Lifting the label instead of holding the fill down is what lets the state
    /// ladder exist at all.
    static func secondaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        isSelected || isActive ? Theme.onColor : Theme.onColorSecondary
    }

    /// Tertiary content on an event fill: incidental glyphs such as the recurrence marker. Lifted
    /// one tier for the same reason as `secondaryLabelColor`; as a glyph rather than text it only
    /// owes the 3:1 non-text bar, which it holds in every state.
    static func tertiaryLabelColor(isSelected: Bool = false, isActive: Bool = false) -> Color {
        isSelected || isActive ? Theme.onColorSecondary : Theme.onColorTertiary
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

    /// Keeps the calendar's hue, scales its saturation by `fillSaturationScale`, and picks the
    /// brightness whose sRGB relative luminance is `target`.
    private static func solvedFill(for calendarColor: Color, luminance target: Double) -> Color {
        let source = hsb(of: calendarColor)
        let scaledSaturation = source.saturation * fillSaturationScale
        // Luminance is monotonic in brightness at fixed hue/saturation, so a bisection converges
        // without inverting the sRGB transfer curve. 16 steps resolve brightness far finer than
        // one 8-bit code point, and the whole solve is plain arithmetic — no allocation per step,
        // which matters because a month grid runs this once per chip.
        var low = 0.0
        var high = 1.0
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if relativeLuminance(hue: source.hue, saturation: scaledSaturation, brightness: mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return Color(hue: source.hue, saturation: scaledSaturation, brightness: (low + high) / 2)
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

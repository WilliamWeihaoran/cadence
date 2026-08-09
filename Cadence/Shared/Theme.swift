import SwiftUI

/// Cadence's single fixed dark palette. Previously the app supported 7 selectable themes
/// (light and dark) via `ThemeManager`; that system has been removed in favor of one fixed,
/// non-adaptive palette shared by macOS and iOS/iPadOS.
struct Theme {
    // Near-black neutral. The previous stops sat around hue 225 at ~19% saturation, so the
    // blue cast compounded on every elevated surface and the chrome ended up carrying more
    // color than the content. These sit at ~4% saturation so the accents do that job instead.
    static let bg = Color(hex: "#09090b")
    static let surface = Color(hex: "#131316")
    static let surfaceElevated = Color(hex: "#1a1a1e")
    static let borderSubtle = Color(hex: "#26262b")

    static let text = Color(hex: "#ededef")
    static let muted = Color(hex: "#a1a1aa")
    /// Supporting text one stop below `muted`: the label half of a label/value pair, and captions
    /// that annotate the thing above them rather than say anything on their own. It exists because
    /// `muted` and `dim` are two stops too far apart to express "quieter than secondary, but still
    /// ordinary reading text" — `dim` is reserved for genuinely de-emphasized or disabled content
    /// and lands 9pt captions near 0.42 effective white on `bg`, which is too faint to read on a
    /// device. Sits between the two, nearer `muted`.
    static let subdued = Color(hex: "#95959e")
    static let dim = Color(hex: "#71717a")

    // MARK: - Extended neutral ramp
    // Stops that sit *between* (or just below) the four surface values above. They exist for
    // jobs the four-stop ramp cannot express — a recessed well below `bg`, a hover lift between
    // `surface` and `surfaceElevated`, and borders that must stay visible when drawn at partial
    // alpha. Introduced so the AppKit markdown editor could stop carrying its own private hex
    // literals; they follow the same ~4% saturation near-black ramp as the stops above.

    /// Recessed well one step *below* `bg` (unchecked checkbox interiors, inset wells).
    static let surfaceRecessed = Color(hex: "#0d0d0f")
    /// Hover lift for a surface whose resting fill is `surface`.
    static let surfaceHover = Color(hex: "#17171a")
    /// Hover/selection highlight behind content nested inside an already-elevated surface.
    static let surfaceHighlight = Color(hex: "#1f1f23")
    /// One step above `borderSubtle`, for hairlines that are drawn at partial alpha and would
    /// otherwise disappear.
    static let border = Color(hex: "#2e2e34")
    /// Emphasized border: hovered cards, table delimiters, code fences.
    static let borderStrong = Color(hex: "#3f3f46")
    /// Standalone horizontal rules, which carry no other affordance to lean on.
    static let rule = Color(hex: "#52525b")

    // MARK: - Marker highlight
    // The `==highlight==` marker pen in the markdown editors. Semantic, not palette — it has to
    // read as a physical highlighter, so it deliberately keeps its warm hue through the neutral
    // repaint rather than resolving to `amber`.

    static let markerHighlightFill = Color(hex: "#f6c343")
    static let markerHighlightBorder = Color(hex: "#ffd66b")
    static let markerHighlightText = Color(hex: "#fff4c2")

    /// Single source of truth for the accent hex — also used where a *string* color is
    /// required (model `colorHex` fallbacks) so the literal is not duplicated.
    static let blueHex = "#4a9eff"

    static let blue = Color(hex: blueHex)
    static let blueLight = lightened(blueHex)

    static let red = Color(hex: "#ff6b6b")

    static let green = Color(hex: "#4ecb71")
    static let greenLight = lightened("#4ecb71")

    static let amber = Color(hex: "#ffa94d")
    static let amberLight = lightened("#ffa94d")

    static let purple = Color(hex: "#a78bfa")

    /// The palette is fixed dark; there is no light variant or user selection anymore.
    static let preferredColorScheme: ColorScheme = .dark

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high:   return red
        case .medium: return amber
        case .low:    return blue
        case .none:   return dim
        }
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .done:       return green
        case .cancelled:  return dim
        case .inProgress: return blue
        case .todo:       return muted
        }
    }

    /// Fill for a completed completion-circle (task rows, kanban cards, timeline blocks, task
    /// inspector). When checked, every priority converges to this same green + a white
    /// checkmark — priority stops being shown once a task is done.
    static let doneFill = green

    // MARK: - Foreground on colored fills
    // For content drawn ON TOP of a saturated fill (calendar event blocks, a selected day
    // cell, an accent-filled button) the foreground is deliberately near-white rather than
    // `text` — it has to hold up against an arbitrary user-chosen hue, not against `bg`.
    // These replace scattered `.white` / `.white.opacity(...)` literals so the tiers are
    // named and consistent instead of each call site inventing its own alpha.

    /// Primary content on a colored fill: titles, button labels.
    static let onColor = Color.white
    /// Secondary content on a colored fill: time ranges, subtitles, calendar names.
    static let onColorSecondary = Color.white.opacity(0.75)
    /// Tertiary content on a colored fill: incidental glyphs.
    static let onColorTertiary = Color.white.opacity(0.6)

    /// Hairline outline drawn ON a colored fill, where `borderSubtle` would read as a dark
    /// gap instead of an edge (task-count bubbles on a selected day cell, hatching over a
    /// completed timeline block).
    static let onColorBorder = Color.white.opacity(0.14)
    /// Emphasized variant of `onColorBorder` for selected/active colored fills.
    static let onColorBorderStrong = Color.white.opacity(0.32)

    /// Resting grab handle drawn on a colored timeline block (resize affordances on task,
    /// event, and bundle blocks). Deliberately faint until the block is hovered/selected.
    static let onColorHandle = Color.white.opacity(0.16)
    /// `onColorHandle` while the block is hovered, selected, or actively being resized.
    static let onColorHandleActive = Color.white.opacity(0.42)

    /// Brand-mandated fill for the "Sign in with Apple" button. Not a palette color — Apple's
    /// Sign in with Apple guidelines only permit black / white / outline treatments, so this
    /// deliberately sits outside the neutral ramp and must not be re-tinted with the palette.
    static let appleSignInFill = Color.black

    // MARK: - Overlays
    // Washes and scrims expressed as white/black alpha. Previously hand-tuned per call site
    // against the old blue-tinted background; centralized so a palette change moves them all.

    /// Full-screen dimming behind a modal, sheet, or command palette.
    static let scrim = Color.black.opacity(0.34)
    /// Selected-state wash on top of a colored surface (e.g. today's cell in the month grid).
    static let selectionWash = Color.white.opacity(0.18)
    /// Barely-there lift used to separate a nested region from the surface beneath it.
    static let subtleWash = Color.white.opacity(0.035)

    // MARK: - Shadow presets
    // Named to replace one-off `Color.black.opacity(...)` shadow values scattered across
    // surfaces. Radius/offset stay call-site-specific since elevation depth genuinely varies;
    // these only centralize the color/opacity for jobs that are doing the same kind of lift.

    /// Hairline shadow for small chips/pills (calendar day-cell chips, all-day banner chips).
    static let chipShadow = Color.black.opacity(0.06)
    /// Shadow for an edge-attached floating panel with no dimming scrim behind it
    /// (e.g. Today's right-hand timeline sidebar).
    static let sidePanelShadow = Color.black.opacity(0.18)
    /// Shadow for centered modal cards, popovers, toasts, and overlay shells presented
    /// above a dimming scrim.
    static let overlayCardShadow = Color.black.opacity(0.3)
    /// Soft lift for in-flow content cards that replaces a hard border with gentle elevation.
    /// Paired with `radiusCard`. NOTE: task rows/kanban cards moved back to a flat,
    /// divider-separated style per the current design spec — this token is now only for
    /// surfaces that are still deliberately card-shaped (e.g. stat tiles, popovers).
    static let cardElevationShadow = Color.black.opacity(0.22)

    // MARK: - Corner radius scale
    // A shared radius scale so card-like surfaces read as one family instead of each
    // picking its own value (previously scattered 8/10/12/14/16 with no clear pattern).

    /// Small in-card controls: icon badges, compact buttons, inline pickers.
    static let radiusControl: CGFloat = 10
    /// Standard content cards: stat tiles, list rows that are still card-shaped, kanban cards.
    static let radiusCard: CGFloat = 18
    /// Large surfaces: page headers, sheets, popovers, modal shells.
    static let radiusPanel: CGFloat = 22

    // MARK: - Derived variants
    // The design spec defines only the base hues above; the lightened accent variants (still
    // referenced by existing call sites for hover/pressed/emphasis states) are derived here by
    // blending a fixed fraction toward white, rather than hand-picking arbitrary hex
    // values with no spec to match against.

    private static func lightened(_ hex: String, by amount: Double = 0.3) -> Color {
        blended(hex, toward: (1, 1, 1), amount: amount)
    }

    private static func blended(_ hex: String, toward target: (r: Double, g: Double, b: Double), amount: Double) -> Color {
        let c = hexComponents(hex)
        return Color(
            .sRGB,
            red: c.r + (target.r - c.r) * amount,
            green: c.g + (target.g - c.g) * amount,
            blue: c.b + (target.b - c.b) * amount,
            opacity: 1
        )
    }

    private static func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        return (
            Double((int >> 16) & 0xFF) / 255,
            Double((int >> 8) & 0xFF) / 255,
            Double(int & 0xFF) / 255
        )
    }
}

#if canImport(AppKit)
import AppKit

// MARK: - AppKit bridges
//
// The markdown editor is AppKit (NSTextView + a custom NSLayoutManager doing its own drawing),
// so it cannot read SwiftUI `Color`. It used to carry its own hand-tuned `NSColor(hex:)` literals,
// which silently drifted from the palette above whenever the palette changed. These bridges
// resolve the *same* `Color` constants declared in this file into concrete sRGB `NSColor`s, so a
// palette value is still defined in exactly one place and the two can never diverge.
extension Theme {
    /// Resolves a palette `Color` into a concrete sRGB `NSColor` suitable for AppKit drawing
    /// (`setFill()`, `setStroke()`, `backgroundColor`, `withAlphaComponent(_:)`, PDF rendering).
    private static func nsColor(_ color: Color) -> NSColor {
        let resolved = NSColor(color)
        return resolved.usingColorSpace(.sRGB) ?? resolved
    }

    static let nsBg = nsColor(bg)
    static let nsSurface = nsColor(surface)
    static let nsSurfaceElevated = nsColor(surfaceElevated)
    static let nsBorderSubtle = nsColor(borderSubtle)

    static let nsSurfaceRecessed = nsColor(surfaceRecessed)
    static let nsSurfaceHover = nsColor(surfaceHover)
    static let nsSurfaceHighlight = nsColor(surfaceHighlight)
    static let nsBorder = nsColor(border)
    static let nsBorderStrong = nsColor(borderStrong)
    static let nsRule = nsColor(rule)

    static let nsMarkerHighlightFill = nsColor(markerHighlightFill)
    static let nsMarkerHighlightBorder = nsColor(markerHighlightBorder)
    static let nsMarkerHighlightText = nsColor(markerHighlightText)

    static let nsText = nsColor(text)
    static let nsMuted = nsColor(muted)
    static let nsDim = nsColor(dim)

    static let nsBlue = nsColor(blue)
    static let nsRed = nsColor(red)
    static let nsGreen = nsColor(green)
}
#endif

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

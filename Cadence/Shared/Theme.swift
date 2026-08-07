import SwiftUI

/// Cadence's single fixed dark palette. Previously the app supported 7 selectable themes
/// (light and dark) via `ThemeManager`; that system has been removed in favor of one fixed,
/// non-adaptive palette shared by macOS and iOS/iPadOS.
struct Theme {
    static let bg = Color(hex: "#0f1117")
    static let surface = Color(hex: "#1a1d27")
    static let surfaceElevated = Color(hex: "#1f2235")
    static let borderSubtle = Color(hex: "#252a3d")

    static let text = Color(hex: "#e2e8f0")
    static let muted = Color(hex: "#c4d4e8")
    static let dim = Color(hex: "#6b7a99")

    static let blue = Color(hex: "#4a9eff")
    static let blueLight = lightened("#4a9eff")
    static let blueDark = darkened("#4a9eff")

    static let red = Color(hex: "#ff6b6b")
    static let redLight = lightened("#ff6b6b")

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
    // The design spec defines only the base hues above; light/dark accent variants (still
    // referenced by existing call sites for hover/pressed/emphasis states) are derived here by
    // blending a fixed fraction toward white/black, rather than hand-picking arbitrary hex
    // values with no spec to match against.

    private static func lightened(_ hex: String, by amount: Double = 0.3) -> Color {
        blended(hex, toward: (1, 1, 1), amount: amount)
    }

    private static func darkened(_ hex: String, by amount: Double = 0.35) -> Color {
        blended(hex, toward: (0, 0, 0), amount: amount)
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

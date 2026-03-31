import SwiftUI
import Observation

struct ThemeColors {
    let bg: Color
    let surface: Color
    let surfaceElevated: Color
    let borderSubtle: Color

    let text: Color
    let muted: Color
    let dim: Color

    let blue: Color
    let blueLight: Color
    let blueDark: Color

    let red: Color
    let redLight: Color

    let green: Color
    let greenLight: Color

    let amber: Color
    let amberLight: Color

    let purple: Color
}

enum ThemeOption: String, CaseIterable, Identifiable {
    case midnight
    case graphite
    case ember
    case ocean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .ember: return "Ember"
        case .ocean: return "Ocean"
        }
    }

    var subtitle: String {
        switch self {
        case .midnight: return "Cool navy with crisp electric accents"
        case .graphite: return "Muted charcoal with steel-blue highlights"
        case .ember: return "Dark wine tones with warm copper energy"
        case .ocean: return "Deep teal surfaces with arctic blue accents"
        }
    }

    var previewColors: [Color] {
        let palette = colors
        return [palette.bg, palette.surface, palette.blue, palette.amber]
    }

    var colors: ThemeColors {
        switch self {
        case .midnight:
            return ThemeColors(
                bg: Color(hex: "#0f1117"),
                surface: Color(hex: "#1a1d27"),
                surfaceElevated: Color(hex: "#1f2235"),
                borderSubtle: Color(hex: "#252a3d"),
                text: Color(hex: "#e2e8f0"),
                muted: Color(hex: "#c4d4e8"),
                dim: Color(hex: "#6b7a99"),
                blue: Color(hex: "#4a9eff"),
                blueLight: Color(hex: "#6ab4ff"),
                blueDark: Color(hex: "#1a6bc4"),
                red: Color(hex: "#ff6b6b"),
                redLight: Color(hex: "#ff8e8e"),
                green: Color(hex: "#4ecb71"),
                greenLight: Color(hex: "#6ddb8a"),
                amber: Color(hex: "#ffa94d"),
                amberLight: Color(hex: "#ffbf6b"),
                purple: Color(hex: "#a78bfa")
            )
        case .graphite:
            return ThemeColors(
                bg: Color(hex: "#101214"),
                surface: Color(hex: "#191d20"),
                surfaceElevated: Color(hex: "#20252a"),
                borderSubtle: Color(hex: "#2d343b"),
                text: Color(hex: "#e7edf3"),
                muted: Color(hex: "#c0ccd9"),
                dim: Color(hex: "#7c8a98"),
                blue: Color(hex: "#5da2ff"),
                blueLight: Color(hex: "#85bbff"),
                blueDark: Color(hex: "#2f73cd"),
                red: Color(hex: "#ff7a7a"),
                redLight: Color(hex: "#ff9f9f"),
                green: Color(hex: "#5ac88d"),
                greenLight: Color(hex: "#7fdaad"),
                amber: Color(hex: "#e6a85d"),
                amberLight: Color(hex: "#f2bf82"),
                purple: Color(hex: "#9e8cff")
            )
        case .ember:
            return ThemeColors(
                bg: Color(hex: "#140f12"),
                surface: Color(hex: "#20171c"),
                surfaceElevated: Color(hex: "#281d24"),
                borderSubtle: Color(hex: "#3a2932"),
                text: Color(hex: "#f1e5ea"),
                muted: Color(hex: "#d7c2cb"),
                dim: Color(hex: "#9b7f8b"),
                blue: Color(hex: "#7ab0ff"),
                blueLight: Color(hex: "#9ec8ff"),
                blueDark: Color(hex: "#4176cc"),
                red: Color(hex: "#ff7e88"),
                redLight: Color(hex: "#ffa4ab"),
                green: Color(hex: "#62c58b"),
                greenLight: Color(hex: "#88d8a7"),
                amber: Color(hex: "#ffb15c"),
                amberLight: Color(hex: "#ffc784"),
                purple: Color(hex: "#c293ff")
            )
        case .ocean:
            return ThemeColors(
                bg: Color(hex: "#0c1316"),
                surface: Color(hex: "#132026"),
                surfaceElevated: Color(hex: "#18303a"),
                borderSubtle: Color(hex: "#22414f"),
                text: Color(hex: "#dff2f5"),
                muted: Color(hex: "#bdd6dd"),
                dim: Color(hex: "#6f8f98"),
                blue: Color(hex: "#4db8ff"),
                blueLight: Color(hex: "#79ccff"),
                blueDark: Color(hex: "#197fc1"),
                red: Color(hex: "#ff7d72"),
                redLight: Color(hex: "#ff9d95"),
                green: Color(hex: "#4fd1a1"),
                greenLight: Color(hex: "#72dfb7"),
                amber: Color(hex: "#ffbc57"),
                amberLight: Color(hex: "#ffd07f"),
                purple: Color(hex: "#8fa8ff")
            )
        }
    }
}

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private let storageKey = "selectedTheme"
    var selectedTheme: ThemeOption {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: storageKey)
        }
    }

    var palette: ThemeColors { selectedTheme.colors }

    private init() {
        if
            let rawValue = UserDefaults.standard.string(forKey: storageKey),
            let restored = ThemeOption(rawValue: rawValue)
        {
            selectedTheme = restored
        } else {
            selectedTheme = .midnight
        }
    }
}

struct Theme {
    private static var palette: ThemeColors { ThemeManager.shared.palette }

    static var bg: Color { palette.bg }
    static var surface: Color { palette.surface }
    static var surfaceElevated: Color { palette.surfaceElevated }
    static var borderSubtle: Color { palette.borderSubtle }

    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static var dim: Color { palette.dim }

    static var blue: Color { palette.blue }
    static var blueLight: Color { palette.blueLight }
    static var blueDark: Color { palette.blueDark }

    static var red: Color { palette.red }
    static var redLight: Color { palette.redLight }

    static var green: Color { palette.green }
    static var greenLight: Color { palette.greenLight }

    static var amber: Color { palette.amber }
    static var amberLight: Color { palette.amberLight }

    static var purple: Color { palette.purple }

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

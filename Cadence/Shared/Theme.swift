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
    case daylight
    case sage
    case aurora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .ember: return "Ember"
        case .ocean: return "Ocean"
        case .daylight: return "Daylight"
        case .sage: return "Sage"
        case .aurora: return "Aurora"
        }
    }

    var subtitle: String {
        switch self {
        case .midnight: return "Ink surfaces with cyan and violet accents"
        case .graphite: return "Soft charcoal with cobalt and moss accents"
        case .ember: return "Warm graphite with copper and rose accents"
        case .ocean: return "Deep teal with aqua and sea-glass accents"
        case .daylight: return "Clean light surfaces with crisp blue actions"
        case .sage: return "Calm light greens with teal and clay accents"
        case .aurora: return "Night violet with mint and electric blue accents"
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
                bg: Color(hex: "#0b1020"),
                surface: Color(hex: "#141a2c"),
                surfaceElevated: Color(hex: "#1b2440"),
                borderSubtle: Color(hex: "#2b3656"),
                text: Color(hex: "#edf4ff"),
                muted: Color(hex: "#b8c8df"),
                dim: Color(hex: "#7384a3"),
                blue: Color(hex: "#55b7ff"),
                blueLight: Color(hex: "#84ceff"),
                blueDark: Color(hex: "#247fd0"),
                red: Color(hex: "#ff6f8f"),
                redLight: Color(hex: "#ff9ab2"),
                green: Color(hex: "#67d8a2"),
                greenLight: Color(hex: "#91e8bd"),
                amber: Color(hex: "#f8b85e"),
                amberLight: Color(hex: "#ffd17f"),
                purple: Color(hex: "#b59cff")
            )
        case .graphite:
            return ThemeColors(
                bg: Color(hex: "#111315"),
                surface: Color(hex: "#1b1f22"),
                surfaceElevated: Color(hex: "#242a2f"),
                borderSubtle: Color(hex: "#333b42"),
                text: Color(hex: "#eef2f4"),
                muted: Color(hex: "#c3cbd2"),
                dim: Color(hex: "#818b94"),
                blue: Color(hex: "#6aa7ff"),
                blueLight: Color(hex: "#94c2ff"),
                blueDark: Color(hex: "#3d75c5"),
                red: Color(hex: "#ff7d86"),
                redLight: Color(hex: "#ffa0a7"),
                green: Color(hex: "#8ac36f"),
                greenLight: Color(hex: "#abd98f"),
                amber: Color(hex: "#e9b15f"),
                amberLight: Color(hex: "#f4c985"),
                purple: Color(hex: "#b49bff")
            )
        case .ember:
            return ThemeColors(
                bg: Color(hex: "#17110f"),
                surface: Color(hex: "#241a17"),
                surfaceElevated: Color(hex: "#30221d"),
                borderSubtle: Color(hex: "#473129"),
                text: Color(hex: "#f6ebe5"),
                muted: Color(hex: "#dfc8bb"),
                dim: Color(hex: "#aa8877"),
                blue: Color(hex: "#ff9a62"),
                blueLight: Color(hex: "#ffbd8b"),
                blueDark: Color(hex: "#c76231"),
                red: Color(hex: "#ff6f7d"),
                redLight: Color(hex: "#ff9aa3"),
                green: Color(hex: "#74c69d"),
                greenLight: Color(hex: "#9addba"),
                amber: Color(hex: "#f4c45f"),
                amberLight: Color(hex: "#ffdc87"),
                purple: Color(hex: "#d498ff")
            )
        case .ocean:
            return ThemeColors(
                bg: Color(hex: "#071417"),
                surface: Color(hex: "#102428"),
                surfaceElevated: Color(hex: "#17333a"),
                borderSubtle: Color(hex: "#28535d"),
                text: Color(hex: "#e3fbf8"),
                muted: Color(hex: "#b9dad7"),
                dim: Color(hex: "#719794"),
                blue: Color(hex: "#36c7df"),
                blueLight: Color(hex: "#72deec"),
                blueDark: Color(hex: "#168396"),
                red: Color(hex: "#ff8276"),
                redLight: Color(hex: "#ffa69d"),
                green: Color(hex: "#62d8a7"),
                greenLight: Color(hex: "#8ae8c0"),
                amber: Color(hex: "#ffc25c"),
                amberLight: Color(hex: "#ffd98b"),
                purple: Color(hex: "#8fb5ff")
            )
        case .daylight:
            return ThemeColors(
                bg: Color(hex: "#f6f8fb"),
                surface: Color(hex: "#ffffff"),
                surfaceElevated: Color(hex: "#eef3f8"),
                borderSubtle: Color(hex: "#d9e2ec"),
                text: Color(hex: "#16202a"),
                muted: Color(hex: "#4d5d6f"),
                dim: Color(hex: "#7c8a99"),
                blue: Color(hex: "#256fdb"),
                blueLight: Color(hex: "#5b9df0"),
                blueDark: Color(hex: "#174f9f"),
                red: Color(hex: "#d64545"),
                redLight: Color(hex: "#f17777"),
                green: Color(hex: "#238b63"),
                greenLight: Color(hex: "#5fbf95"),
                amber: Color(hex: "#c77918"),
                amberLight: Color(hex: "#eba64a"),
                purple: Color(hex: "#7655d9")
            )
        case .sage:
            return ThemeColors(
                bg: Color(hex: "#f3f6ef"),
                surface: Color(hex: "#fbfcf8"),
                surfaceElevated: Color(hex: "#e8efe3"),
                borderSubtle: Color(hex: "#d1dcc9"),
                text: Color(hex: "#1b261f"),
                muted: Color(hex: "#50614f"),
                dim: Color(hex: "#7a8a77"),
                blue: Color(hex: "#2c8c83"),
                blueLight: Color(hex: "#62b9ad"),
                blueDark: Color(hex: "#17665f"),
                red: Color(hex: "#c65252"),
                redLight: Color(hex: "#e78383"),
                green: Color(hex: "#4f9a57"),
                greenLight: Color(hex: "#7fbd85"),
                amber: Color(hex: "#bd7f3a"),
                amberLight: Color(hex: "#d9a76d"),
                purple: Color(hex: "#8269c9")
            )
        case .aurora:
            return ThemeColors(
                bg: Color(hex: "#100d1c"),
                surface: Color(hex: "#1b162b"),
                surfaceElevated: Color(hex: "#26203d"),
                borderSubtle: Color(hex: "#3b315c"),
                text: Color(hex: "#f0ecff"),
                muted: Color(hex: "#cec5ed"),
                dim: Color(hex: "#8c80ae"),
                blue: Color(hex: "#7c9cff"),
                blueLight: Color(hex: "#a7bcff"),
                blueDark: Color(hex: "#4f67c7"),
                red: Color(hex: "#ff6fa0"),
                redLight: Color(hex: "#ff9cc0"),
                green: Color(hex: "#76e0bd"),
                greenLight: Color(hex: "#9bf0d3"),
                amber: Color(hex: "#f4c86a"),
                amberLight: Color(hex: "#ffdc91"),
                purple: Color(hex: "#c08cff")
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

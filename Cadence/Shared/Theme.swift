import SwiftUI

struct Theme {
    // Backgrounds
    static let bg = Color(hex: "#0f1117")
    static let surface = Color(hex: "#1a1d27")
    static let surfaceElevated = Color(hex: "#1f2235")
    static let borderSubtle = Color(hex: "#252a3d")

    // Text
    static let text = Color(hex: "#e2e8f0")
    static let muted = Color(hex: "#c4d4e8")
    static let dim = Color(hex: "#6b7a99")

    // Accents
    static let blue = Color(hex: "#4a9eff")
    static let blueLight = Color(hex: "#6ab4ff")
    static let blueDark = Color(hex: "#1a6bc4")

    static let red = Color(hex: "#ff6b6b")
    static let redLight = Color(hex: "#ff8e8e")

    static let green = Color(hex: "#4ecb71")
    static let greenLight = Color(hex: "#6ddb8a")

    static let amber = Color(hex: "#ffa94d")
    static let amberLight = Color(hex: "#ffbf6b")

    static let purple = Color(hex: "#a78bfa")

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
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

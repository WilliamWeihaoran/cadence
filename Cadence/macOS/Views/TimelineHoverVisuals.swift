#if os(macOS)
import SwiftUI

enum TimelineHoverVisuals {
    static func hoverFill(tint: Color, isHovered: Bool, opacity: Double = 0.07) -> Color {
        isHovered ? tint.opacity(opacity) : Color.clear
    }

    static func borderColor(
        tint: Color,
        isSelected: Bool,
        isHovered: Bool,
        selectedOpacity: Double,
        hoverOpacity: Double,
        idleOpacity: Double = 0.06
    ) -> Color {
        if isSelected { return tint.opacity(selectedOpacity) }
        if isHovered { return tint.opacity(hoverOpacity) }
        return .white.opacity(idleOpacity)
    }

    static func shadowColor(isActive: Bool) -> Color {
        isActive ? CalendarVisualStyle.selectedCardShadow : CalendarVisualStyle.cardShadow
    }

    static func shadowRadius(isActive: Bool, active: CGFloat = 11, idle: CGFloat = 7) -> CGFloat {
        isActive ? active : idle
    }

    static func shadowY(isActive: Bool, active: CGFloat = 4, idle: CGFloat = 2) -> CGFloat {
        isActive ? active : idle
    }
}
#endif

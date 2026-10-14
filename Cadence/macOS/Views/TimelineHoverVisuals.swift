#if os(macOS)
import SwiftUI

enum TimelineHoverVisuals {
    static func hoverFill(tint: Color, isHovered: Bool, opacity: Double = 0.07) -> Color {
        isHovered ? tint.opacity(opacity) : Color.clear
    }

    /// The edge of a timeline block, lit by its own tint while the pointer is on it or it is
    /// selected, and by a neutral white wash at rest.
    ///
    /// **`idleTintOpacity` is the one exception, and it is additive** (T-3160). The rail treatment
    /// the event block now wears is solved to a plate at Y = 0.030-0.060, roughly a third as bright
    /// as the plate this white rest edge was picked against; at the opacity that treatment's own
    /// ladder asks for, a white rim there composites brighter than the rail itself and reads as a
    /// grey outline drawn round a coloured block. When it is set, the rest edge is the block's own
    /// `tint` at that opacity instead — which is what
    /// `CadenceCalendarEventStyle.railBorderOpacity` has always said it meant. Left `nil`, every
    /// existing caller keeps the white wash byte for byte.
    static func borderColor(
        tint: Color,
        isSelected: Bool,
        isHovered: Bool,
        selectedOpacity: Double,
        hoverOpacity: Double,
        idleOpacity: Double = 0.06,
        idleTintOpacity: Double? = nil
    ) -> Color {
        if isSelected { return tint.opacity(selectedOpacity) }
        if isHovered { return tint.opacity(hoverOpacity) }
        if let idleTintOpacity { return tint.opacity(idleTintOpacity) }
        return Theme.onColor.opacity(idleOpacity)
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

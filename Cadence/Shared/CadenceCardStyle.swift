import SwiftUI

/// Shared "elevated card" treatment: soft shadow instead of a hard border, on the
/// shared radius scale. Replaces the common `.background(...).clipShape(...).overlay(
/// RoundedRectangle...strokeBorder(Theme.borderSubtle))` pattern that previously made
/// every card read as a flat bordered rectangle with no depth.
struct CadenceCardStyle: ViewModifier {
    var background: Color = Theme.surface
    var cornerRadius: CGFloat = Theme.radiusCard
    var shadowRadius: CGFloat = 14
    var shadowY: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.cardElevationShadow, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func cadenceCard(
        background: Color = Theme.surface,
        cornerRadius: CGFloat = Theme.radiusCard,
        shadowRadius: CGFloat = 14,
        shadowY: CGFloat = 6
    ) -> some View {
        modifier(CadenceCardStyle(
            background: background,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }
}

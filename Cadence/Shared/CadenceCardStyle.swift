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

/// The one chrome for a card raised over a scrim across the whole Mac window ([[T-10041]]): the
/// delete confirmation, the Shift+T / Shift+D date panel, Cmd+K and the New Task panel (and the
/// quick-capture panel's success card, which takes the New Task panel's place in the same panel).
///
/// They drew four: 22 / full hairline / 28-16 shadow, 22 / hairline at 0.4 / 24-14, 22 / 0.4 /
/// 36-20, and a literal 16 continuous / 0.95 / 34-18. Owner decision 2026-11-02: one shape at
/// `Theme.radiusPanel`, one hairline and one shadow. The background stays the caller's -- the New
/// Task panel's comes from `CreateTaskSheet` -- and so does `glow`: the New Task panel keeps its
/// blue one because it is the one card that takes input, and the success card its green.
struct CadenceOverlayCardStyle: ViewModifier {
    static let cornerRadius: CGFloat = Theme.radiusPanel
    static let hairlineOpacity: Double = 0.4
    static let shadowRadius: CGFloat = 28
    static let shadowY: CGFloat = 16
    static let glowRadius: CGFloat = 18

    var glow: Color?

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(Self.hairlineOpacity), lineWidth: 1)
            }
            .shadow(color: Theme.overlayCardShadow, radius: Self.shadowRadius, x: 0, y: Self.shadowY)
            .shadow(color: glow ?? .clear, radius: Self.glowRadius, x: 0, y: 0)
    }
}

extension View {
    /// See `CadenceOverlayCardStyle`. Apply after the card's own background.
    func cadenceOverlayCard(glow: Color? = nil) -> some View {
        modifier(CadenceOverlayCardStyle(glow: glow))
    }
}

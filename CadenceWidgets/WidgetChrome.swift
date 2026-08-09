import SwiftUI
import WidgetKit

struct CadenceWidgetScale {
    let outerPadding: CGFloat
    let sectionSpacing: CGFloat
    let compactSectionSpacing: CGFloat
    let panelPadding: CGFloat
    let cardPadding: CGFloat
    let compactCardPadding: CGFloat
    let titleSize: CGFloat
    let countSize: CGFloat
    let badgeFontSize: CGFloat
    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat
    let metricTitleSize: CGFloat
    let metricValueSize: CGFloat
    let stateTitleSize: CGFloat
    let bodyFontSize: CGFloat
    let captionFontSize: CGFloat
    let controlFontSize: CGFloat
    let panelCornerRadius: CGFloat
    let cardCornerRadius: CGFloat
    let elevationRadius: CGFloat
    let elevationY: CGFloat

    static func forFamily(_ family: WidgetFamily) -> CadenceWidgetScale {
        switch family {
        case .systemSmall:
            return CadenceWidgetScale(
                outerPadding: 12,
                sectionSpacing: 9,
                compactSectionSpacing: 7,
                panelPadding: 10,
                cardPadding: 11,
                compactCardPadding: 10,
                titleSize: 15,
                countSize: 20,
                badgeFontSize: 8.5,
                badgeHorizontalPadding: 6,
                badgeVerticalPadding: 3,
                metricTitleSize: 9,
                metricValueSize: 16,
                stateTitleSize: 12,
                bodyFontSize: 10,
                captionFontSize: 9,
                controlFontSize: 10,
                panelCornerRadius: 16,
                cardCornerRadius: 15,
                elevationRadius: 5,
                elevationY: 2
            )
        case .systemMedium:
            return CadenceWidgetScale(
                outerPadding: 12,
                sectionSpacing: 10,
                compactSectionSpacing: 8,
                panelPadding: 10,
                cardPadding: 11,
                compactCardPadding: 10,
                titleSize: 16,
                countSize: 21,
                badgeFontSize: 8.5,
                badgeHorizontalPadding: 6,
                badgeVerticalPadding: 3,
                metricTitleSize: 9,
                metricValueSize: 16,
                stateTitleSize: 12,
                bodyFontSize: 10,
                captionFontSize: 9,
                controlFontSize: 10,
                panelCornerRadius: 17,
                cardCornerRadius: 16,
                elevationRadius: 6,
                elevationY: 2
            )
        case .systemLarge:
            return CadenceWidgetScale(
                outerPadding: 14,
                sectionSpacing: 11,
                compactSectionSpacing: 8,
                panelPadding: 11,
                cardPadding: 12,
                compactCardPadding: 10,
                titleSize: 17,
                countSize: 22,
                badgeFontSize: 9,
                badgeHorizontalPadding: 6,
                badgeVerticalPadding: 3,
                metricTitleSize: 9,
                metricValueSize: 17,
                stateTitleSize: 13,
                bodyFontSize: 10.5,
                captionFontSize: 9.5,
                controlFontSize: 10.5,
                panelCornerRadius: 18,
                cardCornerRadius: 17,
                elevationRadius: 7,
                elevationY: 3
            )
        default:
            return CadenceWidgetScale(
                outerPadding: 16,
                sectionSpacing: 12,
                compactSectionSpacing: 9,
                panelPadding: 12,
                cardPadding: 13,
                compactCardPadding: 11,
                titleSize: 17,
                countSize: 23,
                badgeFontSize: 9,
                badgeHorizontalPadding: 6,
                badgeVerticalPadding: 3,
                metricTitleSize: 9,
                metricValueSize: 18,
                stateTitleSize: 13,
                bodyFontSize: 10.5,
                captionFontSize: 9.5,
                controlFontSize: 10.5,
                panelCornerRadius: 18,
                cardCornerRadius: 18,
                elevationRadius: 8,
                elevationY: 3
            )
        }
    }
}

/// Shared elevation shadow for widget cards/panels — soft depth instead of a flat fill,
/// matching the app-wide move away from hard-bordered cards. Kept as a plain `.shadow`
/// (not a background-affecting modifier) so it never changes a view's layout footprint,
/// which matters inside WidgetKit's fixed, non-scrolling family sizes.
extension View {
    func cadenceWidgetElevation(_ scale: CadenceWidgetScale) -> some View {
        shadow(color: Theme.cardElevationShadow, radius: scale.elevationRadius, x: 0, y: scale.elevationY)
    }
}

/// Which corner of the container gradient carries the heavy end of the accent wash. Today and
/// Calendar both key off `Theme.blue`, so they are told apart by anchoring rather than by two
/// different blues: Today's wash arrives with the header at the top-leading corner and fades out
/// downward, while Calendar's pools at the bottom-trailing corner, where the neutral ramp is
/// already at its lightest — which is what makes Calendar read as the deeper blue of the two.
enum CadenceWidgetAccentAnchor {
    case topLeading
    case bottomTrailing
}

/// Widget surfaces resolve their colors from `Theme` like every in-app surface does. They used to
/// carry their own hand-tuned `Color(red:...)` literals, which drifted into near-duplicate reds,
/// blues, greens, and ambers that no longer matched anything in the app; the widget target now
/// compiles `Theme.swift` directly so there is one palette instead of two.
///
/// The container background is the neutral `bg → surface` page ramp with a low-alpha wash of the
/// widget's own accent laid over it, so the four stay tellable apart on a crowded home screen
/// without reintroducing four private background hues. One helper takes the accent rather than four
/// near-copies taking four gradients.
///
/// The wash is deliberately asymmetric — heavy against the darker neutral stop, light against the
/// lighter one. That is not a taste call: it keeps the composited result at or below the luminance
/// of `Theme.surfaceElevated`, the opaque card fill that sits on top of it. Holding that ceiling
/// buys two things at once. Cards still read as lifted above the background rather than sunk into
/// it, and text drawn straight onto the container is never on a worse footing than the same text
/// drawn on a card — which is the footing 9pt captions already ship on, so the tint costs no
/// contrast that the design was not already spending.
extension View {
    func cadenceWidgetBackground(
        accent: Color,
        anchor: CadenceWidgetAccentAnchor = .topLeading
    ) -> some View {
        let heavy = accent.opacity(0.08)
        let light = accent.opacity(0.04)
        return containerBackground(for: .widget) {
            LinearGradient(
                colors: [Theme.bg, Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                LinearGradient(
                    colors: anchor == .topLeading ? [heavy, light] : [light, heavy],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct CadenceWidgetBadge: View {
    let text: String
    let tint: Color
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        Text(text)
            .font(.system(size: scale.badgeFontSize, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, scale.badgeHorizontalPadding)
            .padding(.vertical, scale.badgeVerticalPadding)
            .background(tint.opacity(0.20))
            .clipShape(Capsule())
    }
}

struct CadenceWidgetMetricCard: View {
    let title: String
    let value: String
    var valueTint: Color = Theme.text
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.metricTitleSize, weight: .semibold))
                .foregroundStyle(Theme.subdued)
            Text(value)
                .font(.system(size: scale.metricValueSize, weight: .black, design: .rounded))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(scale.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
        .cadenceWidgetElevation(scale)
    }
}

struct CadenceWidgetFooterLink: View {
    let label: String
    let url: URL
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        Link(destination: url) {
            Text(label)
                .font(.system(size: scale.controlFontSize, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, scale.panelPadding)
                .padding(.vertical, max(scale.panelPadding - 4, 5))
                .background(Theme.surfaceHighlight)
                .clipShape(Capsule())
                .cadenceWidgetElevation(scale)
        }
    }
}

struct CadenceWidgetStateCard: View {
    let title: String
    let message: String?
    let actionLabel: String
    let actionURL: URL
    var alignment: HorizontalAlignment = .leading
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        VStack(alignment: alignment, spacing: scale.compactSectionSpacing) {
            Text(title)
                .font(.system(size: scale.stateTitleSize, weight: .semibold))
                .foregroundStyle(Theme.text)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: scale.bodyFontSize, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)
            }

            Link(destination: actionURL) {
                Text(actionLabel)
                    .font(.system(size: scale.controlFontSize, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: alignment == .leading ? .topLeading : .center
        )
    }
}

struct CadenceWidgetPanel<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        content
            .padding(scale.panelPadding)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
            .cadenceWidgetElevation(scale)
    }
}

struct WidgetHeaderBadge: Identifiable {
    let id = UUID()
    let text: String
    let tint: Color
}

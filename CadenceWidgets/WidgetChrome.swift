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
                panelCornerRadius: 15,
                cardCornerRadius: 14
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
                panelCornerRadius: 15,
                cardCornerRadius: 15
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
                panelCornerRadius: 16,
                cardCornerRadius: 16
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
                panelCornerRadius: 16,
                cardCornerRadius: 17
            )
        }
    }
}

extension View {
    func cadenceWidgetBackground(_ colors: [Color]) -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
    }
}

struct CadenceWidgetMetricCard: View {
    let title: String
    let value: String
    var valueTint: Color = .white
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let scale = CadenceWidgetScale.forFamily(widgetFamily)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.metricTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: scale.metricValueSize, weight: .black, design: .rounded))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(scale.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, scale.panelPadding)
                .padding(.vertical, max(scale.panelPadding - 4, 5))
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
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
                .foregroundStyle(.white)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: scale.bodyFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)
            }

            Link(destination: actionURL) {
                Text(actionLabel)
                    .font(.system(size: scale.controlFontSize, weight: .semibold))
                    .foregroundStyle(.white)
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
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
    }
}

struct WidgetHeaderBadge: Identifiable {
    let id = UUID()
    let text: String
    let tint: Color
}

#if os(iOS)
import SwiftData
import SwiftUI

struct iOSFeatureListPane<Content: View>: View {
    let eyebrow: String
    let title: String
    let count: Int
    let emptyTitle: String
    let emptySubtitle: String
    let emptyIcon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: eyebrow, title: title, count: count)
            Divider().background(Theme.borderSubtle)

            if count == 0 {
                iOSEmptyPanel(systemImage: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        content()
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 300, idealWidth: 360)
        .background(Theme.surface)
    }
}

struct iOSCompactPageHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var color: Color = Theme.blue

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: isCompact ? 15 : 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: isCompact ? 32 : 36, height: isCompact ? 32 : 36)
                    .background(color.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: isCompact ? 9 : 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isCompact ? 9 : 10, style: .continuous)
                            .strokeBorder(color.opacity(0.20), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: isCompact ? 26 : 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct iOSCompactPanelCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.52), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func iOSCompactPanelCard() -> some View {
        modifier(iOSCompactPanelCardModifier())
    }
}

struct iOSFeatureSummaryRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let icon: String
    let color: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? "No context" : subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? color.opacity(0.12) : Theme.surfaceElevated.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.26) : Theme.borderSubtle.opacity(0.35), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct iOSFeatureTaskSummaryRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        iOSFeatureSummaryRow(
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            isSelected: isSelected
        )
    }
}

struct iOSFeatureIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceElevated.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.6), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct iOSCalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let taskCount: Int
    var minHeight: CGFloat = 58
    let action: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .semibold))
                    .foregroundStyle(isCurrentMonth ? Theme.text : Theme.dim.opacity(0.42))

                HStack(spacing: 3) {
                    ForEach(0..<min(taskCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? .white : Theme.blue)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(isSelected ? Theme.blue : isToday ? Theme.blue.opacity(0.12) : Theme.surfaceElevated.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isToday || isSelected ? Theme.blue.opacity(0.5) : Theme.borderSubtle.opacity(0.28), lineWidth: 1)
            }
            .opacity(isCurrentMonth ? 1 : 0.58)
        }
        .buttonStyle(.plain)
    }
}

struct iOSFeatureHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct iOSMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

struct iOSFeatureSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)
            VStack(spacing: 8) {
                content()
            }
        }
    }
}

struct iOSFeatureEmptyDetail: View {
    let systemImage: String
    let title: String

    var body: some View {
        iOSEmptyPanel(
            systemImage: systemImage,
            title: title,
            subtitle: "Select an item from the list."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

private struct iOSMacPlaceholderPanel: View {
    let eyebrow: String
    let title: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: eyebrow, title: title)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.72))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

#if os(macOS)
import SwiftUI

struct CommitmentPageHeader<Accessory: View, Controls: View>: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = CadenceDesktopMetrics.pageTitleSize
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: CadenceDesktopMetrics.secondaryTextSize))
                        .foregroundStyle(Theme.dim)
                }

                Spacer(minLength: 20)

                accessory
            }

            controls
        }
        .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
        .padding(.top, CadenceDesktopMetrics.pageHeaderTopPadding)
        .padding(.bottom, CadenceDesktopMetrics.pageHeaderBottomPadding)
        .background(Theme.surface)
    }
}

struct CommitmentIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32
    var iconSize: CGFloat = 13
    var cornerRadius: CGFloat? = nil
    var fillOpacity: Double = 0.14

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(fillOpacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? min(12, size * 0.28)))
    }
}

struct CommitmentSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: CadenceDesktopMetrics.regularControlHeight)
        .background(Theme.surfaceElevated.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: CadenceDesktopMetrics.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceDesktopMetrics.controlCornerRadius, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CommitmentFilterBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var minWidth: CGFloat = 52
    var spacing: CGFloat = 6
    var tint: Color = Theme.blue
    let label: (Item) -> String

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                CadencePillButton(
                    title: label(item),
                    isSelected: selection == item,
                    minWidth: minWidth,
                    tint: tint
                ) {
                    selection = item
                }
            }
        }
        .padding(3)
        .background(Theme.surfaceElevated.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }
}

struct CommitmentGroupHeader: View {
    let title: String
    let icon: String
    let color: Color
    let trailingText: String
    var trailingTint: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

            Spacer()

            Text(trailingText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(trailingTint ?? Theme.text.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

/// Shared small metadata chip used across kanban cards, goal/habit detail rows,
/// planning cards, and timeline bundle inspectors. Prefer this over a local
/// one-off chip struct so tint/padding/shape stay consistent app-wide.
struct CommitmentMetaChip: View {
    let label: String
    let color: Color
    var systemImage: String? = nil
    /// Filled/high-contrast treatment for a chip that should read as the primary metric (e.g. a time range).
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? Theme.bg : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(prominent ? color : color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct CommitmentInlineEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct CommitmentEmptyDetail: View {
    let icon: String
    let title: String
    let subtitle: String
    var background: Color = Theme.surface

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.dim)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }
}
#endif

#if os(macOS)
import SwiftUI

struct CommitmentPageHeader<Accessory: View, Controls: View>: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = 28
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 20)

                accessory
            }

            controls
        }
        .padding(20)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
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
        .padding(4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle, lineWidth: 1))
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

struct CommitmentMetaChip: View {
    let label: String
    let color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
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

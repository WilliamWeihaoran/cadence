import SwiftUI

struct CadenceSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
    }
}

struct CadenceSettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}

struct CadenceSettingsStatusBadge: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Theme.green : Theme.dim)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Theme.green : Theme.dim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((isActive ? Theme.green : Theme.dim).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct CadenceSettingsHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.trailingContent = trailingContent()
    }

    var body: some View {
        CadenceSettingsCard {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                trailingContent
            }
        }
    }
}

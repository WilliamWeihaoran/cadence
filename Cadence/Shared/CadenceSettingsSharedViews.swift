import SwiftUI

struct CadenceSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
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
    let icon: String
    let tint: Color
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.trailingContent = trailingContent()
    }

    var body: some View {
        CadenceSettingsCard {
            // Single-line row now that the description is gone, so the glyph, title,
            // and badge center against each other instead of hanging from the top.
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 0)
                trailingContent
            }
        }
    }
}

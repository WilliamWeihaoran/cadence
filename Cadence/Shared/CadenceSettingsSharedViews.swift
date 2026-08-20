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

#if os(macOS)
/// The Settings detail column's category header: a `.page`-role `DesktopPageHeader` inside the
/// shared settings card.
///
/// macOS-only, like its one caller `SettingsDetailHeader` — iOS has `iOSSettingsPageHeader`, which
/// is the same wrapper over `iOSPageHeader`, and reached this shape first.
///
/// It used to draw its own rounded square at 42/17 and set its title `.semibold` at 18pt while the
/// other three macOS headers were bold at 22 — a header whose identity tile outweighed its own
/// name, and a fourth glyph ratio. The card supplies the padding, hence `padded: false`.
struct CadenceSettingsHeader<TrailingContent: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        tint: Color,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.tint = tint
        self.trailingContent = trailingContent()
    }

    var body: some View {
        CadenceSettingsCard {
            DesktopPageHeader(
                role: .page,
                title: title,
                tint: tint,
                padded: false,
                background: nil
            ) {
                trailingContent
            }
        }
    }
}
#endif

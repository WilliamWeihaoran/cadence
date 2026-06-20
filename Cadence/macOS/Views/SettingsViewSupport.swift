#if os(macOS)
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case navigation
    case sidebar
    case templates
    case contexts
    case lists
    case tags
    case calendar
    case ai
    case dataSafety
    case account

    var id: String { rawValue }

    var sharedKind: CadenceSettingsCategoryKind {
        switch self {
        case .appearance: return .appearance
        case .navigation: return .navigation
        case .sidebar: return .sidebar
        case .templates: return .templates
        case .contexts: return .contexts
        case .lists: return .lists
        case .tags: return .tags
        case .calendar: return .calendar
        case .ai: return .ai
        case .dataSafety: return .dataSafety
        case .account: return .account
        }
    }

    var title: String {
        sharedKind.title
    }

    var subtitle: String {
        sharedKind.subtitle
    }

    var detailDescription: String {
        sharedKind.detailDescription
    }

    var icon: String {
        sharedKind.icon
    }

    var tint: Color {
        sharedKind.tint
    }
}

private struct SettingsCategoryGroup: Identifiable {
    let title: String
    let categories: [SettingsCategory]

    var id: String { title }

    static let all: [SettingsCategoryGroup] = [
        SettingsCategoryGroup(
            title: "Interface",
            categories: [.appearance, .navigation, .sidebar]
        ),
        SettingsCategoryGroup(
            title: "Organization",
            categories: [.contexts, .lists, .tags, .templates]
        ),
        SettingsCategoryGroup(
            title: "Connections",
            categories: [.calendar, .ai]
        ),
        SettingsCategoryGroup(
            title: "Account & Safety",
            categories: [.account, .dataSafety]
        )
    ]
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        CadenceSettingsCard {
            content
        }
    }
}

struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        CadenceSettingsSectionLabel(text: text)
    }
}

struct SettingsStatusBadge: View {
    let title: String
    let isActive: Bool

    var body: some View {
        CadenceSettingsStatusBadge(title: title, isActive: isActive)
    }
}

struct SettingsRail: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Preferences, organization, integrations, and safety.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SettingsCategoryGroup.all) { group in
                        SettingsRailGroup(
                            group: group,
                            selectedCategory: $selectedCategory
                        )
                    }
                }
                .padding(.bottom, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }
}

private struct SettingsRailGroup: View {
    let group: SettingsCategoryGroup
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.dim.opacity(0.78))
                .tracking(1.1)
                .padding(.horizontal, 12)

            VStack(spacing: 6) {
                ForEach(group.categories) { category in
                    SettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
        }
    }
}

private struct SettingsRailButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.tint.opacity(isSelected ? 0.22 : 0.14))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: category.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(category.tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.92))
                    Text(category.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
    }
}

struct SettingsDetailHeader<TrailingContent: View>: View {
    let category: SettingsCategory
    @ViewBuilder let trailingContent: TrailingContent

    init(category: SettingsCategory, @ViewBuilder trailingContent: () -> TrailingContent) {
        self.category = category
        self.trailingContent = trailingContent()
    }

    var body: some View {
        CadenceSettingsHeader(
            title: category.title,
            subtitle: category.detailDescription,
            icon: category.icon,
            tint: category.tint
        ) {
            trailingContent
        }
    }
}
#endif

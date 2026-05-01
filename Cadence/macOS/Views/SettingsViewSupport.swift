#if os(macOS)
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case navigation
    case sidebar
    case contexts
    case lists
    case tags
    case calendar
    case ai
    case dataSafety
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .account: return "Account"
        case .dataSafety: return "Data Safety"
        case .navigation: return "Navigation"
        case .sidebar: return "Sidebar"
        case .contexts: return "Contexts"
        case .tags: return "Tags"
        case .lists: return "Lists"
        case .ai: return "AI"
        case .calendar: return "Calendar"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "Theme and visual tone."
        case .account:
            return "Apple identity status."
        case .dataSafety:
            return "Backups and restores."
        case .navigation:
            return "Default list behavior."
        case .sidebar:
            return "Tabs, order, and visibility."
        case .contexts:
            return "Active and archived contexts."
        case .tags:
            return "Task and note labels."
        case .lists:
            return "Completed and archived lists."
        case .ai:
            return "OpenAI key and model."
        case .calendar:
            return "Access and linked calendars."
        }
    }

    var detailDescription: String {
        switch self {
        case .appearance:
            return "Choose the palette Cadence uses across the app."
        case .account:
            return "Use Sign in with Apple for your Cadence identity. The app still works when signed out."
        case .dataSafety:
            return "Create backups, review restore points, and stage a restore for the next launch."
        case .navigation:
            return "Choose the first page Cadence opens for lists without a saved page."
        case .sidebar:
            return "Arrange the main sidebar tabs and decide which ones stay visible."
        case .contexts:
            return "Manage the top-level groups that organize your areas, projects, tasks, and habits."
        case .tags:
            return "Create, edit, archive, and restore the tags used by tasks and notes."
        case .lists:
            return "Review lists that are no longer active and decide what to restore or remove."
        case .ai:
            return "Store your OpenAI API key in Keychain and choose the model for AI actions."
        case .calendar:
            return "Connect Apple Calendar and choose which calendar each area or project uses."
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .account: return "person.crop.circle.fill"
        case .dataSafety: return "externaldrive.fill.badge.timemachine"
        case .navigation: return "rectangle.stack.fill"
        case .sidebar: return "sidebar.left"
        case .contexts: return "square.stack.3d.up.fill"
        case .tags: return "tag.fill"
        case .lists: return "archivebox.fill"
        case .ai: return "sparkles"
        case .calendar: return "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return Theme.blue
        case .account: return Theme.green
        case .dataSafety: return Theme.amber
        case .navigation: return Theme.green
        case .sidebar: return Theme.amber
        case .contexts: return Theme.red
        case .tags: return Theme.green
        case .lists: return Theme.amber
        case .ai: return Theme.blue
        case .calendar: return Theme.purple
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
    }
}

struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}

struct SettingsStatusBadge: View {
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

struct SettingsRail: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Preferences, organization, integrations, and safety.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(SettingsCategory.allCases) { category in
                    SettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }
}

private struct SettingsRailButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.tint.opacity(isSelected ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: category.icon)
                            .font(.system(size: 14, weight: .semibold))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? category.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
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
        SettingsCard {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(category.tint.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(category.tint)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(category.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(category.detailDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                trailingContent
            }
        }
    }
}
#endif

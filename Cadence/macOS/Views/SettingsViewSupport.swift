#if os(macOS)
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case account
    case navigation
    case sidebar
    case contexts
    case lists
    case ai
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .account: return "Account"
        case .navigation: return "Navigation"
        case .sidebar: return "Sidebar"
        case .contexts: return "Contexts"
        case .lists: return "Lists"
        case .ai: return "AI"
        case .calendar: return "Calendar"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "Themes and overall visual mood."
        case .account:
            return "Apple account identity."
        case .navigation:
            return "How lists open and behave by default."
        case .sidebar:
            return "Choose which static destinations stay visible."
        case .contexts:
            return "Add, edit, archive, and reorder contexts."
        case .lists:
            return "Completed and archived areas and projects."
        case .ai:
            return "Bring your own OpenAI key for local AI actions."
        case .calendar:
            return "Apple Calendar access and linked calendars."
        }
    }

    var detailDescription: String {
        switch self {
        case .appearance:
            return "Pick the dark palette that best fits your workspace. Changes apply across the app immediately."
        case .account:
            return "Connect an Apple account for local identity. Cadence still works signed out."
        case .navigation:
            return "Choose which page new lists open on by default. Once you visit a specific list, Cadence still remembers that list's most recently opened page."
        case .sidebar:
            return "Choose which tabs appear in the sidebar. Hidden tabs are still accessible by re-enabling them here."
        case .contexts:
            return "Add, edit, archive, and drag to reorder contexts. Archived contexts are hidden from the sidebar but not deleted."
        case .lists:
            return "Completed and archived lists live here so you can restore, reopen, or permanently delete them."
        case .ai:
            return "Use your own OpenAI API key for note summaries and task extraction. Cadence stores the key in Keychain."
        case .calendar:
            return "Scheduled tasks sync to Apple Calendar when their area or project has a linked calendar."
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .account: return "person.crop.circle.fill"
        case .navigation: return "rectangle.stack.fill"
        case .sidebar: return "sidebar.left"
        case .contexts: return "square.stack.3d.up.fill"
        case .lists: return "archivebox.fill"
        case .ai: return "sparkles"
        case .calendar: return "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return Theme.blue
        case .account: return Theme.green
        case .navigation: return Theme.green
        case .sidebar: return Theme.amber
        case .contexts: return Theme.red
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
                Text("Tune the app without digging through one giant page.")
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

#if os(iOS)
import SwiftUI

enum iOSSettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case sync
    case calendar
    case organization
    case tags
    case templates
    case lists
    case ai
    case data
    case coverage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .sync: return "Sync"
        case .calendar: return "Calendar"
        case .organization: return "Organization"
        case .tags: return "Tags"
        case .templates: return "Templates"
        case .lists: return "Lists"
        case .ai: return "AI"
        case .data: return "Local Data"
        case .coverage: return "Coverage"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "Themes."
        case .sync: return "iCloud status."
        case .calendar: return "Apple Calendar."
        case .organization: return "Contexts and groups."
        case .tags: return "Task and note tags."
        case .templates: return "Note templates."
        case .lists: return "List lifecycle."
        case .ai: return "OpenAI key."
        case .data: return "Counts and storage."
        case .coverage: return "Mobile feature surface."
        case .about: return "Version and bundle."
        }
    }

    var detailDescription: String {
        switch self {
        case .appearance:
            return "Choose the same Cadence color themes available on Mac."
        case .sync:
            return "Check whether this device can use iCloud and CloudKit for Cadence sync."
        case .calendar:
            return "Connect Apple Calendar and choose which calendars are visible or linked to lists."
        case .organization:
            return "Manage the top-level contexts shared by areas, projects, tasks, and habits."
        case .tags:
            return "Create, archive, restore, and seed tags shared by tasks and notes."
        case .templates:
            return "Customize the note templates used by Today, lists, meetings, and permanent notes."
        case .lists:
            return "Review completed and archived areas or projects and return them to active work."
        case .ai:
            return "Store your OpenAI API key in Keychain and choose the model for AI note actions."
        case .data:
            return "Review the local workspace counts currently visible on this device."
        case .coverage:
            return "Track which companion app workflows are currently implemented on iPhone and iPad."
        case .about:
            return "Review the installed app version and bundle details for TestFlight diagnostics."
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .sync: return "icloud.fill"
        case .calendar: return "calendar"
        case .organization: return "square.stack.3d.up.fill"
        case .tags: return "tag.fill"
        case .templates: return "doc.text.fill"
        case .lists: return "archivebox.fill"
        case .ai: return "sparkles"
        case .data: return "chart.bar.doc.horizontal.fill"
        case .coverage: return "iphone.and.arrow.forward"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return Theme.purple
        case .sync: return Theme.blue
        case .calendar: return Theme.purple
        case .organization: return Theme.red
        case .tags: return Theme.amber
        case .templates: return Theme.purple
        case .lists: return Theme.green
        case .ai: return Theme.blue
        case .data: return Theme.green
        case .coverage: return Theme.purple
        case .about: return Theme.amber
        }
    }
}

enum iOSMobileCapability {
    static let readyCapabilities = [
        "Today planning",
        "All Tasks",
        "Inbox capture",
        "Theme selection",
        "Apple Calendar access and list links",
        "Create/edit/archive contexts",
        "Create/edit/archive lists",
        "Create/archive/restore tags",
        "Customize note templates",
        "Restore completed/archived lists",
        "AI key/model settings",
        "Search",
        "Markdown notes",
        "List Kanban",
        "List planning",
        "List saved links",
        "Completed task review",
        "Calendar timeline",
        "Focus timer",
        "Pursuits",
        "Milestones",
        "Habits"
    ]
}

struct iOSSettingsRail: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Preferences, organization, sync, and TestFlight diagnostics.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(iOSSettingsCategory.allCases) { category in
                    iOSSettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
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

struct iOSSettingsCurrentCategoryPill: View {
    let category: iOSSettingsCategory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(category.tint)
                .frame(width: 28, height: 28)
                .background(category.tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(category.subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(category.tint.opacity(0.22), lineWidth: 1)
        }
    }
}

struct iOSSettingsCategoryStrip: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(iOSSettingsCategory.allCases) { category in
                    iOSSettingsCategoryStripButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private struct iOSSettingsCategoryStripButton: View {
    let category: iOSSettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? category.tint : Theme.dim)
                    .frame(width: 24, height: 24)
                    .background(isSelected ? category.tint.opacity(0.14) : Theme.surfaceElevated.opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(category.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(isSelected ? category.tint.opacity(0.12) : Theme.surfaceElevated.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? category.tint.opacity(0.28) : Theme.borderSubtle.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
    }
}

private struct iOSSettingsRailButton: View {
    let category: iOSSettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct iOSSettingsCompactCategoryPicker: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(iOSSettingsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(selectedCategory == category ? Theme.text : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? category.tint.opacity(0.22) : Theme.surface)
                        )
                        .overlay {
                            Capsule()
                                .stroke(selectedCategory == category ? category.tint.opacity(0.36) : Theme.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct iOSAppearanceSettingsSection: View {
    let selectedTheme: ThemeOption
    let onSelectTheme: (ThemeOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Theme")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                ForEach(ThemeOption.allCases) { option in
                    iOSThemeOptionCard(
                        option: option,
                        isSelected: selectedTheme == option,
                        action: { onSelectTheme(option) }
                    )
                }
            }
        }
    }
}

private struct iOSThemeOptionCard: View {
    let option: ThemeOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(Array(option.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color)
                            .frame(height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                            }
                    }
                }

                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(option.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.68) : Theme.borderSubtle.opacity(0.6), lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct iOSSettingsEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct iOSSettingsMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(13)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

struct iOSSettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }
}

struct iOSSettingsCapabilityRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.text)
            Spacer()
            Label(isReady ? "Ready" : "Later",
                  systemImage: isReady ? "checkmark.circle.fill" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isReady ? Theme.green : Theme.dim)
        }
        .padding(.vertical, 10)
    }
}
#endif

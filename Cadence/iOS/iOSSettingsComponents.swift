#if os(iOS)
import SwiftUI

enum iOSSettingsCategory: String, CaseIterable, Identifiable {
    case navigation
    case sync
    case data
    case calendar
    case notifications
    case organization
    case lists
    case tags
    case templates
    case ai
    case coverage
    case about

    var id: String { rawValue }

    var sharedKind: CadenceSettingsCategoryKind {
        switch self {
        case .navigation: return .navigation
        case .sync: return .sync
        case .data: return .dataSafety
        case .calendar: return .calendar
        case .notifications: return .notifications
        case .organization: return .contexts
        case .lists: return .lists
        case .tags: return .tags
        case .templates: return .templates
        case .ai: return .ai
        case .coverage: return .coverage
        case .about: return .about
        }
    }

    var title: String {
        sharedKind.title
    }

    var subtitle: String {
        sharedKind.subtitle
    }

    var icon: String {
        sharedKind.icon
    }

    var tint: Color {
        sharedKind.tint
    }
}

private struct iOSSettingsCategoryGroup: Identifiable {
    let title: String
    let categories: [iOSSettingsCategory]

    var id: String { title }

    static let all: [iOSSettingsCategoryGroup] = [
        iOSSettingsCategoryGroup(
            title: "Interface",
            categories: [.navigation]
        ),
        iOSSettingsCategoryGroup(
            title: "Organization",
            categories: [.organization, .lists, .tags, .templates]
        ),
        iOSSettingsCategoryGroup(
            title: "Connections",
            categories: [.calendar, .notifications, .sync, .ai]
        ),
        iOSSettingsCategoryGroup(
            title: "Mobile",
            categories: [.data, .coverage, .about]
        )
    ]
}

enum iOSMobileCapabilityStatus: String, CaseIterable, Identifiable {
    case ready
    case partial
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .partial: return "Partial"
        case .later: return "Later"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .partial: return "wrench.and.screwdriver.fill"
        case .later: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: return Theme.green
        case .partial: return Theme.amber
        case .later: return Theme.dim
        }
    }
}

struct iOSMobileCapability: Identifiable, Hashable {
    let title: String
    let detail: String
    let status: iOSMobileCapabilityStatus

    var id: String { title }

    static let all: [iOSMobileCapability] = [
        iOSMobileCapability(title: "Today planning", detail: "Capture, sort, complete, notes, samples, and timeline inspector.", status: .ready),
        iOSMobileCapability(title: "All Tasks", detail: "Review active/completed work, edit tasks, and use shared task presentation.", status: .ready),
        iOSMobileCapability(title: "Inbox capture", detail: "Quick add, triage, completion, and scheduling basics.", status: .ready),
        iOSMobileCapability(title: "Lists", detail: "Areas/projects, list detail, planning, Kanban, links, and lifecycle restore.", status: .ready),
        iOSMobileCapability(title: "Search", detail: "Find tasks, notes, and feature destinations from mobile.", status: .ready),
        iOSMobileCapability(title: "Markdown notes", detail: "Live rendering, raw edit, preview, formatting, images, references, tables, and templates.", status: .ready),
        iOSMobileCapability(title: "Settings", detail: "Theme, navigation defaults, calendar, tags, templates, sync, AI, data, and about.", status: .ready),
        iOSMobileCapability(title: "Focus timer", detail: "Mobile focus surface exists, but still needs deeper desktop parity testing.", status: .partial),
        iOSMobileCapability(title: "Calendar", detail: "Timeline/month/board, quick create, event editing, and empty-slot creation exist; drag/resize parity remains.", status: .partial),
        iOSMobileCapability(title: "Goals", detail: "Create/edit top-level goals with nested milestones and habits; desktop timeline parity still needs polish.", status: .partial),
        iOSMobileCapability(title: "Habits", detail: "Create/edit and toggle habits; deeper analytics and Mac polish remain.", status: .partial),
        iOSMobileCapability(title: "CloudKit sync", detail: "Uses the shared container, but needs manual device/relaunch verification before TestFlight.", status: .partial),
        iOSMobileCapability(title: "App Store metadata", detail: "Icons and public support/privacy links are present; screenshots and final review notes remain.", status: .partial),
        iOSMobileCapability(title: "Desktop editor parity", detail: "The AppKit editor cannot be reused directly; mobile now shares markdown behavior through SwiftUI/UIKit surfaces.", status: .partial),
        iOSMobileCapability(title: "Global desktop commands", detail: "Global hotkeys, hover affordances, and macOS command surfaces are intentionally desktop-only.", status: .later)
    ]

    static func count(for status: iOSMobileCapabilityStatus) -> Int {
        all.filter { $0.status == status }.count
    }

    static func items(for status: iOSMobileCapabilityStatus) -> [iOSMobileCapability] {
        all.filter { $0.status == status }
    }
}

struct iOSSettingsRail: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Preferences and workspace controls.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(iOSSettingsCategoryGroup.all) { group in
                        iOSSettingsRailGroup(
                            group: group,
                            selectedCategory: $selectedCategory
                        )
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.72))
    }
}

private struct iOSSettingsRailGroup: View {
    let group: iOSSettingsCategoryGroup
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.dim.opacity(0.78))
                .tracking(1.1)
                .padding(.horizontal, 10)

            VStack(spacing: 6) {
                ForEach(group.categories) { category in
                    iOSSettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

private struct iOSSettingsRailButton: View {
    let category: iOSSettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                        .lineLimit(1)
                    Text(category.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.72), cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
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
    let capability: iOSMobileCapability

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: capability.status.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(capability.status.color)
                .frame(width: 28, height: 28)
                .background(capability.status.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(capability.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(capability.status.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(capability.status.color)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(capability.status.color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// MARK: - Soft-elevation card shell

/// Local stand-in for the shared `CadenceSettingsCard` (`Shared/CadenceSettingsSharedViews.swift`).
/// The shared component keeps its original hard-border treatment because other surfaces
/// (macOS settings, `iOSCalendarSettingsSection`, `iPadInboxView`) still rely on it as-is.
/// Settings surfaces in this file's scope use this instead so they can pick up the shared
/// `.cadenceCard` soft-elevation styling (bigger radius, shadow instead of a hairline border).
struct iOSSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 14, shadowY: 6)
    }
}

/// Local stand-in for the shared `CadenceSettingsHeader`, same layout, riding on
/// `iOSSettingsCard`'s soft-elevation styling instead of the shared hard-border card.
struct iOSSettingsPageHeader<TrailingContent: View>: View {
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
        iOSSettingsCard {
            // Single-line row now that the description is gone, so the glyph, title,
            // and badge center against each other instead of hanging from the top.
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
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
#endif

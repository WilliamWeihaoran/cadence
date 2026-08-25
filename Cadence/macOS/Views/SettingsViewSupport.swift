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
    case reminders
    case sync
    case notifications
    case ai
    case dataSafety
    case account
    case about

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
        case .reminders: return .reminders
        case .sync: return .sync
        case .notifications: return .notifications
        case .ai: return .ai
        case .dataSafety: return .dataSafety
        case .account: return .account
        case .about: return .about
        }
    }

    var title: String {
        sharedKind.title
    }

    var icon: String {
        sharedKind.icon
    }

    var tint: Color {
        sharedKind.tint
    }
}

/// The rail's grouping, and the reason it is `internal` rather than `private`.
///
/// It was `private`, so the only way a test could state "every category is filed in a group" was to
/// read this file as text and search inside the `static let all` literal for a case name — which
/// pins the *spelling* of one case and cannot see a category that is simply missing. Dropping a
/// case from a group here made a whole settings pane unreachable on macOS with every test green
/// (`docs/TODO.md` T-161). `SettingsCategoryReachTests` asserts over the value now; do not make
/// this `private` again without giving the rail some other way to be read.
struct SettingsCategoryGroup: Identifiable {
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
            // `.sync` sits with Calendar and Reminders — the system services the app talks to —
            // rather than next to `.account` under "Account & Safety", even though its shared
            // title reads "Account & Sync". `.account` is Sign in with Apple, macOS-only and
            // titled "Account"; the two filed adjacently would read as one setting listed twice.
            // Mobile files `.sync` beside `.calendar`/`.reminders` in its "System" group for the
            // same reason, so this is the same shape rather than a second opinion.
            categories: [.calendar, .reminders, .sync, .notifications, .ai]
        ),
        SettingsCategoryGroup(
            title: "Account & Safety",
            categories: [.account, .dataSafety]
        ),
        // Its own group of one rather than filed under "Account & Safety": which build is
        // running is not a safety control, and a row reading "About" beside "Data Safety"
        // reads as one more thing that might delete something.
        SettingsCategoryGroup(
            title: "App",
            categories: [.about]
        )
    ]
}

/// Sizing for the settings category rail. The rail is the same kind of object as the
/// main sidebar — a narrow column of destinations — so it borrows `SidebarMetrics`
/// rather than restating its own row padding, glyph slot, and radius. Deriving them
/// keeps the two columns from drifting apart, and keeps every row here on one pair of
/// left edges: glyphs at `horizontalInset + rowHorizontalPadding`, labels one
/// `iconSlotWidth + iconLabelSpacing` further in.
enum SettingsRailMetrics {
    // MARK: Column

    static let columnWidth: CGFloat = 248
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 22
    static let titleFontSize: CGFloat = 24
    static let titleBottomSpacing: CGFloat = 18

    // MARK: Rows

    static let rowHorizontalPadding: CGFloat = SidebarMetrics.listRowHorizontalPadding
    static let rowVerticalPadding: CGFloat = SidebarMetrics.listRowVerticalPadding
    static let rowCornerRadius: CGFloat = SidebarMetrics.listRowCornerRadius
    static let rowSpacing: CGFloat = SidebarMetrics.listRowSpacing
    static let iconSlotWidth: CGFloat = SidebarMetrics.iconSlotWidth
    static let iconLabelSpacing: CGFloat = SidebarMetrics.iconLabelSpacing
    static let labelFontSize: CGFloat = SidebarMetrics.listLabelFontSize
    static let trailingGap: CGFloat = SidebarMetrics.listTrailingGap
    /// Between the sidebar's list glyph (12) and its nav glyph (15): these rows are
    /// destinations, but there are fourteen of them, so they stay under the nav weight.
    static let iconSize: CGFloat = 14

    // MARK: Group headers

    static let groupHeaderFontSize: CGFloat = SidebarMetrics.contextHeaderFontSize
    static let groupHeaderKerning: CGFloat = SidebarMetrics.contextHeaderKerning
    static let groupHeaderBottomSpacing: CGFloat = SidebarMetrics.contextHeaderBottomSpacing
    static let groupSpacing: CGFloat = SidebarMetrics.contextSectionBottomSpacing
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

// `SettingsStatusBadge` used to sit here, wrapping a shared `CadenceSettingsStatusBadge`. Both are
// deleted (T-20). Its nine callers were all the same call site — `SettingsView.detailHeader` — and
// every one of them put a pill in the category header repeating the value of the first row on the
// screen below it: "Connected" over a Calendar card whose first line says Connected, "Key saved"
// over an AI card whose first line says Key saved. iOS deleted the equivalent slot in `775833d`
// with the argument that survives the deletion: a header that answers the question the next row
// answers is a second place for one fact to go stale.

struct SettingsRail: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsRailMetrics.titleBottomSpacing) {
            Text("Settings")
                .font(.system(size: SettingsRailMetrics.titleFontSize, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, SettingsRailMetrics.rowHorizontalPadding)

            // Still a ScrollView: the fourteen rows fit in a normal window, but this is
            // the only thing keeping the last group reachable in a very short one.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SettingsRailMetrics.groupSpacing) {
                    ForEach(SettingsCategoryGroup.all) { group in
                        SettingsRailGroup(
                            group: group,
                            selectedCategory: $selectedCategory
                        )
                    }
                }
            }
        }
        .padding(.horizontal, SettingsRailMetrics.horizontalInset)
        .padding(.vertical, SettingsRailMetrics.verticalInset)
        .frame(width: SettingsRailMetrics.columnWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }
}

private struct SettingsRailGroup: View {
    let group: SettingsCategoryGroup
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsRailMetrics.groupHeaderBottomSpacing) {
            Text(group.title.uppercased())
                .font(.system(size: SettingsRailMetrics.groupHeaderFontSize, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(SettingsRailMetrics.groupHeaderKerning)
                .padding(.horizontal, SettingsRailMetrics.rowHorizontalPadding)

            VStack(spacing: SettingsRailMetrics.rowSpacing) {
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

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsRailMetrics.iconLabelSpacing) {
                // The glyph is neutral until this is the row you are on — colour marks
                // the current category rather than tinting all fourteen at once.
                Image(systemName: category.icon)
                    .font(.system(size: SettingsRailMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? category.tint : Theme.dim)
                    .frame(width: SettingsRailMetrics.iconSlotWidth)

                Text(category.title)
                    .font(.system(size: SettingsRailMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: SettingsRailMetrics.trailingGap)
            }
            .padding(.horizontal, SettingsRailMetrics.rowHorizontalPadding)
            .padding(.vertical, SettingsRailMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsRailMetrics.rowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Theme.surfaceElevated
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.6)
        }
        return Color.clear
    }
}

/// The detail column's header: the selected category's name, tinted count-capsule-style by its own
/// colour, and nothing else.
///
/// The generic `TrailingContent` parameter is gone rather than left unused — see the tombstone
/// above `SettingsRail` for what it carried and why.
struct SettingsDetailHeader: View {
    let category: SettingsCategory

    var body: some View {
        CadenceSettingsHeader(
            title: category.title,
            tint: category.tint
        )
    }
}
#endif

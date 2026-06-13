#if os(iOS)
import SwiftData
import SwiftUI

struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            iOSSidebar(selection: $selection)
                .frame(width: iOSSidebarMetrics.railWidth)
                .background(Theme.bg)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.72))
                        .frame(width: 0.5)
                }
                .zIndex(1)

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
                .clipped()
                .zIndex(0)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.container)
    }
}

struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    @Query private var allTasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSSidebarRailBrand()
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(iOSStaticSidebarDestination.primaryCases) { destination in
                    railButton(for: destination)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            iOSSidebarRailDivider()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(iOSStaticSidebarDestination.secondaryCases) { destination in
                        railButton(for: destination)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            iOSSidebarRailDivider()
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(iOSStaticSidebarDestination.utilityCases) { destination in
                    railButton(for: destination)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .background(Theme.bg)
    }

    private func railButton(for destination: iOSStaticSidebarDestination) -> some View {
        iOSSidebarRailButton(
            title: destination.shortTitle,
            systemImage: destination.systemImage,
            tint: destination.tint,
            count: count(for: destination),
            isSelected: selection == destination.item
        ) {
            selection = destination.item
        }
    }

    private var todayCount: Int? {
        CadenceTaskQuerySupport.badgeCount(
            CadenceTaskQuerySupport.scheduledOrDueTodayCount(
                from: allTasks,
                todayKey: DateFormatters.todayKey()
            )
        )
    }

    private var inboxCount: Int? {
        CadenceTaskQuerySupport.badgeCount(
            CadenceTaskQuerySupport.openInboxTaskCount(from: allTasks)
        )
    }

    private var allTaskCount: Int? {
        CadenceTaskQuerySupport.badgeCount(
            CadenceTaskQuerySupport.openTaskCount(from: allTasks)
        )
    }

    private func count(for destination: iOSStaticSidebarDestination) -> Int? {
        switch destination {
        case .today: return todayCount
        case .allTasks: return allTaskCount
        case .focus: return nil
        case .inbox: return inboxCount
        case .calendar: return nil
        case .pursuits: return nil
        case .goals: return nil
        case .habits: return nil
        case .notes: return nil
        case .lists: return nil
        case .search: return nil
        case .settings: return nil
        }
    }
}

private enum iOSStaticSidebarDestination: CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case pursuits
    case goals
    case habits
    case notes
    case lists
    case search
    case settings

    var id: String { title }

    static let primaryCases: [iOSStaticSidebarDestination] = [
        .today,
        .allTasks,
        .inbox,
        .calendar
    ]

    static let secondaryCases: [iOSStaticSidebarDestination] = [
        .notes,
        .focus,
        .lists,
        .pursuits,
        .goals,
        .habits
    ]

    static let utilityCases: [iOSStaticSidebarDestination] = [
        .search,
        .settings
    ]

    var item: iOSSidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .pursuits: return .pursuits
        case .goals: return .goals
        case .habits: return .habits
        case .notes: return .notes
        case .lists: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .goals: return "Milestones"
        case .habits: return "Habits"
        case .notes: return "Notes"
        case .lists: return "Lists"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var shortTitle: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .goals: return "Goals"
        case .habits: return "Habits"
        case .notes: return "Notes"
        case .lists: return "Lists"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .pursuits: return "sparkles"
        case .goals: return "flag.fill"
        case .habits: return "flame.fill"
        case .notes: return "note.text"
        case .lists: return "folder.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: return Color(hex: "#FFB84D")
        case .allTasks: return Color(hex: "#5AA2FF")
        case .focus: return Color(hex: "#FF6B6B")
        case .inbox: return Color(hex: "#5AA2FF")
        case .calendar: return Color(hex: "#9E8CFF")
        case .pursuits: return Color(hex: "#A78BFA")
        case .goals: return Color(hex: "#4ECB71")
        case .habits: return Color(hex: "#FFB84D")
        case .notes: return Color(hex: "#9E8CFF")
        case .lists: return Color(hex: "#4ECB71")
        case .search: return Color(hex: "#9E8CFF")
        case .settings: return Color(hex: "#5AA2FF")
        }
    }
}

private enum iOSSidebarMetrics {
    static let railWidth: CGFloat = 128
    static let buttonHeight: CGFloat = 40
    static let iconSize: CGFloat = 14
    static let iconBoxSize: CGFloat = 26
    static let selectedCornerRadius: CGFloat = 10
}

struct iOSSidebarRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.54))
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
    }
}

struct iOSSidebarRailBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.blue.opacity(0.13))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("Cadence")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Cadence")
    }
}

struct iOSSidebarRailButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.muted.opacity(0.76))
                    .frame(width: iOSSidebarMetrics.iconBoxSize, height: iOSSidebarMetrics.iconBoxSize)
                    .background(isSelected ? tint.opacity(0.16) : Theme.surfaceElevated.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.text : tint)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18)
                        .frame(height: 17)
                        .background(isSelected ? Color.white.opacity(0.15) : tint.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: iOSSidebarMetrics.buttonHeight)
            .background(isSelected ? tint.opacity(0.13) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.26) : Color.clear, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: 3, height: 18)
                        .offset(x: -7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct iOSMissingListView: View {
    var body: some View {
        iOSEmptyPanel(
            systemImage: "questionmark.folder",
            title: "List not found",
            subtitle: "This list may have been archived, deleted, or changed on another device."
        )
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

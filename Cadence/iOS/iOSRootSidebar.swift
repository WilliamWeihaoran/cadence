#if os(iOS)
import SwiftData
import SwiftUI

struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            iOSSidebar(selection: $selection)
                .frame(width: 78)
                .background(Theme.surface)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.72))
                        .frame(width: 0.5)
                }

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.container)
    }
}

struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var unscopedAreas: [Area] {
        activeAreas.filter { $0.context == nil }
    }

    private var unscopedProjects: [Project] {
        activeProjects.filter { $0.context == nil && $0.area == nil }
    }

    private var hasOrganizeContent: Bool {
        !activeContexts.isEmpty || !unscopedAreas.isEmpty || !unscopedProjects.isEmpty
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ScrollView {
                VStack(alignment: .center, spacing: 7) {
                    iOSSidebarRailBrand()

                    ForEach(iOSStaticSidebarDestination.allCases) { destination in
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
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
    }

    private var todayCount: Int? {
        let count = allTasks.filter { task in
            guard !task.isDone && !task.isCancelled else { return false }
            return task.scheduledDate == todayKey || task.dueDate == todayKey
        }.count
        return count > 0 ? count : nil
    }

    private var inboxCount: Int? {
        let count = allTasks.filter { !$0.isDone && !$0.isCancelled && $0.area == nil && $0.project == nil }.count
        return count > 0 ? count : nil
    }

    private var allTaskCount: Int? {
        let count = allTasks.filter { !$0.isDone && !$0.isCancelled }.count
        return count > 0 ? count : nil
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

struct iOSSidebarRailBrand: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.blue.opacity(0.13))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1)
            }
            .padding(.bottom, 8)
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
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.text.opacity(0.74))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? tint.opacity(0.18) : Color.clear)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? tint.opacity(0.34) : Color.clear, lineWidth: 1)
                    }

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.text : tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.16) : tint.opacity(0.12))
                        .clipShape(Capsule())
                        .offset(x: 8, y: -5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: 3, height: 24)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct iOSSidebarBrand: View {
    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.blue.opacity(0.13))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cadence")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Workspace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.bottom, 2)
        .padding(.horizontal, 2)
    }
}

struct iOSSidebarCardButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)

                    Spacer()

                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.text : tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(isSelected ? Color.white.opacity(0.16) : tint.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 11)
                .padding(.horizontal, 11)

                Spacer(minLength: 8)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.88))
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 11)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.24) : tint.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.42) : tint.opacity(0.14), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct iOSSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 7) {
                content
            }
        }
    }
}

struct iOSSidebarContextGroup: View {
    @Bindable var context: Context
    @Binding var selection: iOSSidebarItem?

    private var listEntries: [iOSSidebarListEntry] {
        let areaEntries = (context.areas ?? []).filter(\.isActive).map(iOSSidebarListEntry.area)
        let projectEntries = (context.projects ?? []).filter(\.isActive).map(iOSSidebarListEntry.project)
        let entries = areaEntries + projectEntries
        let hasGlobalOrder = Set(entries.map(\.order)).count == entries.count
        guard hasGlobalOrder else { return areaEntries + projectEntries }
        return entries.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: context.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: context.colorHex))

                Text(context.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            if !listEntries.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color(hex: context.colorHex).opacity(0.22))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(listEntries) { entry in
                            iOSSidebarListButton(entry: entry, selection: $selection)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}

struct iOSSidebarLooseListsGroup: View {
    let areas: [Area]
    let projects: [Project]
    @Binding var selection: iOSSidebarItem?

    private var listEntries: [iOSSidebarListEntry] {
        let entries = areas.map(iOSSidebarListEntry.area) + projects.map(iOSSidebarListEntry.project)
        return entries.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LISTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(listEntries) { entry in
                    iOSSidebarListButton(entry: entry, selection: $selection)
                }
            }
            .padding(.leading, 8)
        }
    }
}

enum iOSSidebarListEntry: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id.uuidString)"
        case .project(let project): return "project-\(project.id.uuidString)"
        }
    }

    var item: iOSSidebarItem {
        switch self {
        case .area(let area): return .area(area.id)
        case .project(let project): return .project(project.id)
        }
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var label: String {
        switch self {
        case .area(let area): return area.name.isEmpty ? "Untitled Area" : area.name
        case .project(let project): return project.name.isEmpty ? "Untitled Project" : project.name
        }
    }

    var color: Color {
        switch self {
        case .area(let area): return Color(hex: area.colorHex)
        case .project(let project): return Color(hex: project.colorHex)
        }
    }

    var dueDateKey: String? {
        switch self {
        case .area: return nil
        case .project(let project): return project.dueDate.isEmpty ? nil : project.dueDate
        }
    }

    var order: Int {
        switch self {
        case .area(let area): return area.order
        case .project(let project): return project.order
        }
    }

    var kindRank: Int {
        switch self {
        case .area: return 0
        case .project: return 1
        }
    }
}

struct iOSSidebarListButton: View {
    let entry: iOSSidebarListEntry
    @Binding var selection: iOSSidebarItem?

    private var isSelected: Bool {
        selection == entry.item
    }

    var body: some View {
        Button {
            selection = entry.item
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(entry.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: entry.icon)
                        .foregroundStyle(entry.color)
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer(minLength: 8)

                if let dueDateKey = entry.dueDateKey {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Text(DateFormatters.relativeDate(from: dueDateKey))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(dueDateKey < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceElevated.opacity(0.7))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.22) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct iOSSidebarFooterButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Theme.blue.opacity(0.18) : Theme.surfaceElevated.opacity(0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? Theme.blue.opacity(0.34) : Theme.borderSubtle.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
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

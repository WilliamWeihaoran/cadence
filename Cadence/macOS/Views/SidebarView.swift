#if os(macOS)
import SwiftUI
import SwiftData


enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits

    var id: String { rawValue }

    var item: SidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .goals: return "target"
        case .habits: return "flame.fill"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .goals: return "Goals"
        case .habits: return "Habits"
        }
    }

    var color: Color {
        switch self {
        case .today: return Theme.amber
        case .allTasks: return Theme.blue
        case .focus: return Theme.red
        case .inbox: return Theme.blue
        case .calendar: return Theme.purple
        case .goals: return Theme.green
        case .habits: return Theme.amber
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""

    @State private var contextForNewList: Context? = nil

    private var todayKey: String { DateFormatters.todayKey() }

    private func count(for destination: SidebarStaticDestination) -> Int? {
        switch destination {
        case .today:
            let n = allTasks.filter { !$0.isDone && !$0.isCancelled && ($0.scheduledDate == todayKey || $0.dueDate == todayKey) }.count
            return n > 0 ? n : nil
        case .allTasks:
            let n = allTasks.filter { !$0.isDone && !$0.isCancelled }.count
            return n > 0 ? n : nil
        case .inbox:
            let n = allTasks.filter { !$0.isDone && !$0.isCancelled && $0.area == nil && $0.project == nil }.count
            return n > 0 ? n : nil
        case .goals:
            return activeGoals.isEmpty ? nil : activeGoals.count
        case .habits:
            return habits.isEmpty ? nil : habits.count
        case .focus, .calendar:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.surfaceElevated)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "checklist.checked")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cadence")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(.bottom, 2)

                let allDestinations = allVisibleDestinations
                if !allDestinations.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(allDestinations) { destination in
                            SidebarCardButton(
                                destination: destination,
                                count: count(for: destination),
                                isSelected: selection == destination.item
                            ) {
                                selection = destination.item
                            }
                        }
                    }
                }

                SidebarSection(title: "ORGANIZE") {
                    ForEach(contexts.filter { !$0.isArchived }) { context in
                        ContextSection(
                            context: context,
                            selection: $selection,
                            onAddList: { contextForNewList = context }
                        )
                        .padding(.vertical, 2)
                    }
                }

                SidebarSection(title: "NOTES") {
                    SidebarRow(item: .notes, icon: "doc.text", label: "Notes", color: Theme.purple, selection: $selection)
                }

                Spacer(minLength: 4)

                SidebarRow(item: .settings, icon: "gearshape.fill", label: "Settings", color: Theme.dim, selection: $selection)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    func setTabHidden(_ destination: SidebarStaticDestination, hidden: Bool) {
        var set = hiddenTabs
        if hidden { set.insert(destination) } else { set.remove(destination) }
        sidebarHiddenTabsRaw = set.map(\.rawValue).joined(separator: ",")
    }

    private var allVisibleDestinations: [SidebarStaticDestination] {
        let allDefaults: [SidebarStaticDestination] = [.today, .allTasks, .focus, .inbox, .calendar, .goals, .habits]
        return allDefaults.filter { !hiddenTabs.contains($0) }
    }
}

private struct SidebarCardButton: View {
    let destination: SidebarStaticDestination
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: destination.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : destination.color)

                    Spacer()

                    if let count {
                        Text("\(count)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isSelected ? .white : destination.color)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)

                Spacer(minLength: 6)

                Text(destination.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? destination.color
                        : destination.color.opacity(isHovered ? 0.22 : 0.14))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? destination.color.opacity(0.5) : destination.color.opacity(isHovered ? 0.3 : 0.18),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#endif

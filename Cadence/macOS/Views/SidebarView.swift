#if os(macOS)
import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Pursuit> { $0.statusRaw == "active" }) private var activePursuits: [Pursuit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""
    @AppStorage("sidebarTabOrder") private var sidebarTabOrderRaw = ""
    @AppStorage("sidebarTabColors") private var sidebarTabColorsRaw = ""

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
        case .pursuits:
            return activePursuits.isEmpty ? nil : activePursuits.count
        case .goals:
            return activeGoals.isEmpty ? nil : activeGoals.count
        case .habits:
            return habits.isEmpty ? nil : habits.count
        case .focus, .calendar:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                                    tint: Color(hex: destination.resolvedColorHex(from: sidebarTabColorsRaw)),
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
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            HStack {
                CompactSidebarIconButton(
                    item: .settings,
                    icon: "gearshape.fill",
                    color: Theme.dim,
                    isSelected: selection == .settings
                ) {
                    selection = .settings
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
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
        SidebarStaticDestination
            .orderedDestinations(from: sidebarTabOrderRaw)
            .filter { !hiddenTabs.contains($0) }
    }
}

#endif

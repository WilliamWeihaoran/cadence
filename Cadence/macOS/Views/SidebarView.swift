#if os(macOS)
import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""
    @AppStorage("sidebarTabOrder") private var sidebarTabOrderRaw = ""
    @AppStorage("sidebarTabColors") private var sidebarTabColorsRaw = ""

    @Environment(GlobalSearchManager.self) private var globalSearchManager

    @State private var contextForNewList: Context? = nil

    private var tasksInActiveContainers: [AppTask] {
        allTasks.filter { task in
            if let project = task.project {
                return project.isActive
            }
            if let area = task.area {
                return area.isActive
            }
            return true
        }
    }

    private var fullBadgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count
        )
    }

    private var activeContainerBadgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: tasksInActiveContainers,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count
        )
    }

    private func count(for destination: SidebarStaticDestination) -> Int? {
        switch destination {
        case .allTasks:
            return activeContainerBadgeSnapshot.count(for: destination.feature)
        case .today, .inbox, .goals, .habits:
            return fullBadgeSnapshot.count(for: destination.feature)
        case .focus, .calendar:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
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

                        Spacer(minLength: 0)

                        Button { globalSearchManager.present() } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.cadencePlain)
                        .help("Search (⌘K)")
                        .accessibilityLabel("Search")
                    }
                    .padding(.bottom, 2)

                    let primaryDestinations = visiblePrimaryDestinations
                    if !primaryDestinations.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(primaryDestinations) { destination in
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

                    // Long-term tracking sits in its own shelf at the bottom, deliberately
                    // separated from the task destinations above so "what am I doing today"
                    // and "what am I working toward" don't read as the same kind of thing.
                    trackShelf

                    SidebarRow(item: .notes, icon: "doc.text", label: "Notes", color: Theme.purple, selection: $selection)
                }
                .padding(.horizontal, 12)
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
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Theme.surface)
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    /// Goals + Habits, grouped onto a quietly tinted shelf. The tint is what does the
    /// separating — a divider alone would read as just another section break.
    @ViewBuilder
    private var trackShelf: some View {
        let trackingDestinations = visibleTrackingDestinations
        if !trackingDestinations.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("TRACK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(trackingDestinations) { destination in
                        SidebarTrackingButton(
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.dim.opacity(0.045))
            )
            .padding(.top, 2)
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

    private var visiblePrimaryDestinations: [SidebarStaticDestination] {
        allVisibleDestinations.filter(\.isPrimaryNavigation)
    }

    private var visibleTrackingDestinations: [SidebarStaticDestination] {
        allVisibleDestinations.filter(\.isTrackingNavigation)
    }
}

#endif

#if os(macOS)
import SwiftUI
import SwiftData

/// The sidebar is two fixed columns: a permanent, non-scrolling icon rail carrying every
/// app destination, and a scrolling panel dedicated entirely to lists (contexts →
/// areas/projects). Destinations no longer compete with lists for vertical space, so the
/// panel can grow without pushing navigation off-screen.
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

    // All Tasks counts only work inside still-active areas/projects; everything else
    // counts against the full task set. `fullBadgeSnapshot` already returns nil for the
    // badge-less destinations (focus, calendar, notes…), so a default branch here stays
    // correct even if new destinations are added to the enum.
    private func count(for destination: SidebarStaticDestination) -> Int? {
        switch destination {
        case .allTasks:
            return activeContainerBadgeSnapshot.count(for: destination.feature)
        default:
            return fullBadgeSnapshot.count(for: destination.feature)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)

            panel
        }
        .background(Theme.surface)
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    // MARK: - Rail

    /// Permanent icon-only navigation column. Never scrolls: the destination set is
    /// bounded and small enough to always fit, which is the whole point of moving it out
    /// of the scrolling panel.
    private var rail: some View {
        VStack(spacing: SidebarRailMetrics.spacing) {
            appIconTile
                .padding(.bottom, 6)

            ForEach(Array(railGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    SidebarRailSeparator()
                }

                ForEach(group) { entry in
                    SidebarRailButton(
                        icon: entry.icon,
                        label: entry.label,
                        tint: entry.tint,
                        count: entry.count,
                        isSelected: selection == entry.item,
                        accessibilityID: entry.accessibilityID
                    ) {
                        selection = entry.item
                    }
                }
            }

            Spacer(minLength: 0)

            SidebarRailButton(
                icon: CadenceFeatureDestination.settings.systemImage,
                label: CadenceFeatureDestination.settings.title,
                tint: Theme.blue,
                count: nil,
                isSelected: selection == .settings,
                accessibilityID: "sidebar.settings"
            ) {
                selection = .settings
            }
        }
        .frame(width: SidebarRailMetrics.width)
        .padding(.top, SidebarRailMetrics.topInset)
        .padding(.bottom, 12)
    }

    private var appIconTile: some View {
        RoundedRectangle(cornerRadius: SidebarRailMetrics.cornerRadius, style: .continuous)
            .fill(Theme.surfaceElevated)
            .frame(width: SidebarRailMetrics.buttonSize, height: SidebarRailMetrics.buttonSize)
            .overlay {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Panel

    /// Lists only. The header stays pinned so the search affordance is always reachable
    /// no matter how far the context list is scrolled.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Lists")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)

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
            .padding(.horizontal, 12)
            .padding(.top, SidebarRailMetrics.topInset)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contexts.filter { !$0.isArchived }) { context in
                        ContextSection(
                            context: context,
                            selection: $selection,
                            onAddList: { contextForNewList = context }
                        )
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tab visibility / order

    var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    private var allVisibleDestinations: [SidebarStaticDestination] {
        SidebarStaticDestination
            .orderedDestinations(from: sidebarTabOrderRaw)
            .filter { !hiddenTabs.contains($0) }
    }

    // MARK: - Rail grouping

    // The three rail groups are fixed structure, not user data: "what am I doing today",
    // "where do I go to look at things", and "what am I working toward" are different
    // kinds of destination and the hairlines are what make the icon-only rail readable.
    // The stored `sidebarTabOrder` therefore sorts *within* a group rather than across
    // groups — reordering in Settings still moves an icon, it just can't move it into a
    // different section of the rail.
    private static let dailyFeatures: [CadenceFeatureDestination] = [.today, .inbox]
    private static let viewFeatures: [CadenceFeatureDestination] = [.planning, .calendar, .allTasks, .notes]
    private static let trackingFeatures: [CadenceFeatureDestination] = [.focus, .goals, .habits]

    private static let staticDestinationFeatures: Set<CadenceFeatureDestination> =
        Set(SidebarStaticDestination.allCases.map(\.feature))

    /// Non-empty groups only, so hiding every destination in a group also removes its
    /// hairline instead of leaving a stray divider behind.
    private var railGroups: [[SidebarRailItem]] {
        [Self.dailyFeatures, Self.viewFeatures, Self.trackingFeatures]
            .map(railItems(for:))
            .filter { !$0.isEmpty }
    }

    private func railItems(for features: [CadenceFeatureDestination]) -> [SidebarRailItem] {
        let featureSet = Set(features)

        // `allVisibleDestinations` is already in the user's stored order with hidden
        // tabs stripped, so filtering it preserves both settings at once.
        var items = allVisibleDestinations
            .filter { featureSet.contains($0.feature) }
            .map { destination in
                SidebarRailItem(
                    id: destination.rawValue,
                    item: destination.item,
                    icon: destination.icon,
                    label: destination.label,
                    tint: Color(hex: destination.resolvedColorHex(from: sidebarTabColorsRaw)),
                    count: count(for: destination),
                    accessibilityID: "sidebar.destination.\(destination.rawValue)"
                )
            }

        // Notes has no `SidebarStaticDestination` case (and therefore no hide toggle, no
        // color override, and no entry in the stored order), so it is rendered straight
        // from the shared feature metadata and pinned to the end of its group. If a case
        // is ever added, the branch above takes over and both settings start working for
        // it automatically.
        if featureSet.contains(.notes), !Self.staticDestinationFeatures.contains(.notes) {
            items.append(
                SidebarRailItem(
                    id: CadenceFeatureDestination.notes.rawValue,
                    item: .notes,
                    icon: CadenceFeatureDestination.notes.systemImage,
                    label: CadenceFeatureDestination.notes.title,
                    tint: CadenceFeatureDestination.notes.tint,
                    count: nil,
                    accessibilityID: "sidebar.destination.notes"
                )
            )
        }

        return items
    }
}

#endif

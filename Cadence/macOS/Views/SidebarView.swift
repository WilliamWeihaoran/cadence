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

                    VStack(alignment: .leading, spacing: 7) {
                        tileRow
                        secondaryRows
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

                    // Long-term tracking sits below a hairline at the bottom, deliberately
                    // separated from the task destinations above so "what am I doing today"
                    // and "what am I working toward" don't read as the same kind of thing.
                    trackSection
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

    /// The four highest-traffic destinations, as one row of icon-only tiles.
    @ViewBuilder
    private var tileRow: some View {
        let tiles = tileDestinations
        if !tiles.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(tiles) { tile in
                    SidebarDestinationTile(
                        icon: tile.icon,
                        label: tile.label,
                        tint: tile.tint,
                        count: tile.count,
                        isSelected: selection == tile.item,
                        accessibilityID: tile.accessibilityID
                    ) {
                        selection = tile.item
                    }
                }
            }
        }
    }

    /// Primary destinations that didn't earn a tile (All Tasks, Planning, Focus…).
    @ViewBuilder
    private var secondaryRows: some View {
        let destinations = secondaryRowDestinations
        if !destinations.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(destinations) { destination in
                    compactRow(for: destination)
                }
            }
        }
    }

    /// Goals + Habits. A hairline plus the TRACK label carries the separation now — the
    /// old tinted shelf competed with the ORGANIZE section for weight.
    @ViewBuilder
    private var trackSection: some View {
        let trackingDestinations = visibleTrackingDestinations
        if !trackingDestinations.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                Text("TRACK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(trackingDestinations) { destination in
                        compactRow(for: destination)
                    }
                }
            }
        }
    }

    private func compactRow(for destination: SidebarStaticDestination) -> some View {
        SidebarCompactRow(
            icon: destination.icon,
            label: destination.label,
            tint: Color(hex: destination.resolvedColorHex(from: sidebarTabColorsRaw)),
            count: count(for: destination),
            isSelected: selection == destination.item,
            accessibilityID: "sidebar.destination.\(destination.rawValue)"
        ) {
            selection = destination.item
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

    // MARK: - Tile / row split

    /// The four destinations promoted to the icon tile row, in fixed visual order.
    /// Matched by `CadenceFeatureDestination` rather than by `SidebarStaticDestination`
    /// case so this keeps compiling (and keeps behaving) if new sidebar cases appear.
    private static let tileFeatures: [CadenceFeatureDestination] = [.today, .inbox, .calendar, .notes]

    private static let staticDestinationFeatures: Set<CadenceFeatureDestination> =
        Set(SidebarStaticDestination.allCases.map(\.feature))

    private struct SidebarTile: Identifiable {
        let id: String
        let item: SidebarItem
        let icon: String
        let label: String
        let tint: Color
        let count: Int?
        let accessibilityID: String
    }

    private var tileDestinations: [SidebarTile] {
        let visible = allVisibleDestinations
        return Self.tileFeatures.compactMap { feature -> SidebarTile? in
            if let destination = visible.first(where: { $0.feature == feature }) {
                return SidebarTile(
                    id: destination.rawValue,
                    item: destination.item,
                    icon: destination.icon,
                    label: tileLabel(for: feature, fallback: destination.label),
                    tint: Color(hex: destination.resolvedColorHex(from: sidebarTabColorsRaw)),
                    count: count(for: destination),
                    accessibilityID: "sidebar.destination.\(destination.rawValue)"
                )
            }

            // Notes has no `SidebarStaticDestination` case (and therefore no hide toggle
            // in Settings), so it is rendered straight from the shared feature metadata.
            // If a case is ever added, the branch above takes over and hiding starts
            // working for it automatically.
            if feature == .notes, !Self.staticDestinationFeatures.contains(.notes) {
                return SidebarTile(
                    id: feature.rawValue,
                    item: .notes,
                    icon: feature.systemImage,
                    label: tileLabel(for: feature, fallback: feature.title),
                    tint: Theme.purple,
                    count: nil,
                    accessibilityID: "sidebar.destination.notes"
                )
            }

            return nil
        }
    }

    /// Everything primary that isn't in the tile row falls through to a compact row.
    /// Hidden destinations are filtered out upstream, so a destination the user hid in
    /// Settings stays hidden in both groups.
    private var secondaryRowDestinations: [SidebarStaticDestination] {
        visiblePrimaryDestinations.filter { !Self.tileFeatures.contains($0.feature) }
    }

    /// "Calendar" doesn't fit a quarter-width tile.
    private func tileLabel(for feature: CadenceFeatureDestination, fallback: String) -> String {
        feature == .calendar ? "Cal" : fallback
    }
}

#endif

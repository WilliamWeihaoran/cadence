#if os(macOS)
import SwiftUI
import SwiftData

/// The sidebar is one column, top to bottom: app header, primary nav, lists, secondary
/// nav, settings.
///
/// **Only the lists region scrolls.** Everything else is pinned. Navigation and lists
/// share a column now, and if the whole column scrolled, a long list collection would
/// push the secondary nav and Settings below the fold — so the two nav groups and the
/// header are fixed and the lists region absorbs all remaining height.
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
        allTasks.filter(CadenceTaskQuerySupport.isInActiveContainer)
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

    /// Both snapshots for one render, built once. Each `Snapshot.init` makes three full passes
    /// over the task list, and this used to be called once per destination — with
    /// `primaryNavItems` itself evaluated twice in a single `body`, about eleven snapshots per
    /// render. Nothing is retained between passes.
    private struct BadgeCounts {
        let full: CadenceFeatureBadgeSupport.Snapshot
        let activeContainers: CadenceFeatureBadgeSupport.Snapshot

        // All Tasks counts only work inside still-active areas/projects; everything else
        // counts against the full task set. `full` already returns nil for the badge-less
        // destinations (focus, calendar, notes…), so a default branch here stays correct
        // even if new destinations are added to the enum.
        func count(for destination: SidebarStaticDestination) -> Int? {
            switch destination {
            case .allTasks:
                return activeContainers.count(for: destination.feature)
            default:
                return full.count(for: destination.feature)
            }
        }
    }

    var body: some View {
        let badgeCounts = BadgeCounts(
            full: fullBadgeSnapshot,
            activeContainers: activeContainerBadgeSnapshot
        )
        let primaryItems = navItems(for: Self.primaryFeatures, badgeCounts: badgeCounts)
        let secondaryItems = navItems(for: Self.secondaryFeatures, badgeCounts: badgeCounts)

        return VStack(alignment: .leading, spacing: 0) {
            SidebarAppHeader { globalSearchManager.present() }
                .padding(.top, SidebarMetrics.topInset)
                .padding(.bottom, SidebarMetrics.headerBottomSpacing)

            if !primaryItems.isEmpty {
                navGroup(primaryItems, emphasis: .primary)
                    .padding(.bottom, SidebarMetrics.groupSpacing)

                SidebarSectionDivider()
            }

            listsSection

            SidebarSectionDivider()

            bottomGroup(secondaryItems: secondaryItems)
        }
        .padding(.horizontal, SidebarMetrics.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        // The tonal step from Theme.surface to the page's Theme.bg is real but small on a
        // near-black palette, so without an edge the sidebar and whatever column it abuts —
        // the notes list especially — read as one continuous region. The hairline is what
        // actually separates them; the tone alone does not carry it.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    // MARK: - Nav groups

    private func navGroup(_ items: [SidebarNavItem], emphasis: SidebarNavRow.Emphasis) -> some View {
        VStack(spacing: SidebarMetrics.rowSpacing) {
            ForEach(items) { entry in
                SidebarNavRow(
                    icon: entry.icon,
                    label: entry.label,
                    tint: entry.tint,
                    count: entry.count,
                    isSelected: selection == entry.item,
                    emphasis: emphasis,
                    accessibilityID: entry.accessibilityID
                ) {
                    selection = entry.item
                }
            }
        }
    }

    /// Secondary nav plus Settings. Pinned to the bottom of the column by the lists
    /// region above it, which is the only part that flexes.
    private func bottomGroup(secondaryItems: [SidebarNavItem]) -> some View {
        VStack(spacing: SidebarMetrics.rowSpacing) {
            navGroup(secondaryItems, emphasis: .secondary)

            SidebarNavRow(
                icon: CadenceFeatureDestination.settings.systemImage,
                label: CadenceFeatureDestination.settings.title,
                tint: CadenceFeatureDestination.settings.tint,
                count: nil,
                isSelected: selection == .settings,
                emphasis: .secondary,
                accessibilityID: "sidebar.settings"
            ) {
                selection = .settings
            }
        }
        .padding(.top, SidebarMetrics.groupSpacing)
        .padding(.bottom, SidebarMetrics.bottomInset)
    }

    // MARK: - Lists

    /// The single scrolling region. Takes every point the pinned groups don't, so
    /// Settings stays on the bottom edge whether the user has two lists or forty.
    private var listsSection: some View {
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
            .padding(.vertical, SidebarMetrics.groupSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
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

    // MARK: - Nav grouping

    // The two nav groups are fixed structure, not user data: "where the day's work
    // happens" sits above the lists, "everything else I navigate to" sits below them.
    // The stored `sidebarTabOrder` therefore sorts *within* a group rather than across
    // groups — reordering in Settings still moves a row, it just can't move it past the
    // lists into the other group.
    private static let primaryFeatures: [CadenceFeatureDestination] = [
        .today, .inbox, .calendar, .allTasks
    ]
    private static let secondaryFeatures: [CadenceFeatureDestination] = [
        .notes, .focus, .goals, .habits
    ]

    private static let staticDestinationFeatures: Set<CadenceFeatureDestination> =
        Set(SidebarStaticDestination.allCases.map(\.feature))

    private func navItems(
        for features: [CadenceFeatureDestination],
        badgeCounts: BadgeCounts
    ) -> [SidebarNavItem] {
        let featureSet = Set(features)
        var items: [SidebarNavItem] = []

        // Notes has no `SidebarStaticDestination` case (and therefore no hide toggle, no
        // color override, and no entry in the stored order), so it is rendered straight
        // from the shared feature metadata and pinned to its declared position at the
        // head of its group — it can't take part in the sort the other rows use. If a
        // case is ever added, the branch below takes over and both settings start
        // working for it automatically.
        if featureSet.contains(.notes), !Self.staticDestinationFeatures.contains(.notes) {
            items.append(
                SidebarNavItem(
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

        // `allVisibleDestinations` is already in the user's stored order with hidden
        // tabs stripped, so filtering it preserves both settings at once.
        items += allVisibleDestinations
            .filter { featureSet.contains($0.feature) }
            .map { destination in
                SidebarNavItem(
                    id: destination.rawValue,
                    item: destination.item,
                    icon: destination.icon,
                    label: destination.label,
                    tint: Color(hex: destination.resolvedColorHex(from: sidebarTabColorsRaw)),
                    count: badgeCounts.count(for: destination),
                    accessibilityID: "sidebar.destination.\(destination.rawValue)"
                )
            }

        return items
    }
}

#endif

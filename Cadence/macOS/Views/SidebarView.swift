#if os(macOS)
import SwiftUI
import SwiftData

/// The sidebar is one column, top to bottom: app header, primary nav (Today, All Tasks,
/// Calendar, Notes), lists, secondary nav (Goals, Habits, Focus, Settings).
///
/// **Only the lists region scrolls.** Everything else is pinned. Navigation and lists
/// share a column, and if the whole column scrolled, a long list collection would push
/// the secondary nav and Settings below the fold — so the two nav groups and the header
/// are fixed and the lists region absorbs all remaining height.
///
/// Group membership lives in `CadenceSidebarLayout` rather than here; this view is the
/// macOS rendering of it, and the iPad sidebar is being brought to the same layout.
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @AppStorage(CadencePreferenceKeys.sidebarHiddenTabs) private var sidebarHiddenTabsRaw = ""
    @AppStorage(CadencePreferenceKeys.sidebarTabOrder) private var sidebarTabOrderRaw = ""
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = ""

    @Environment(GlobalSearchManager.self) private var globalSearchManager

    @State private var contextForNewList: Context? = nil

    /// Built once per render and handed to both groups. Each tally is one pass over the task
    /// list; this used to build two `CadenceFeatureBadgeSupport.Snapshot`s — three passes each —
    /// once per destination.
    ///
    /// All Tasks counts only work inside still-active areas/projects, the same scope its page
    /// uses. Today's overdue tally counts against every task, because Today itself does.
    private var countInputs: CadenceSidebarCountInputs {
        CadenceSidebarCountInputs(
            todayOverdueCount: CadenceSidebarLayout.overdueTaskCount(
                from: allTasks,
                todayKey: DateFormatters.todayKey()
            ),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(
                from: allTasks.filter(\.isInActiveContainer)
            ),
            activeGoalCount: activeGoals.count,
            habitCount: habits.count
        )
    }

    var body: some View {
        let counts = countInputs
        let primaryItems = navItems(in: .primary, counts: counts)
        let secondaryItems = navItems(in: .secondary, counts: counts)

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

    /// The secondary group, Settings included. Pinned to the bottom of the column by the
    /// lists region above it, which is the only part that flexes.
    ///
    /// Settings used to be appended here by hand, outside the group it belongs to; it is a
    /// member of `CadenceSidebarLayout.secondaryDestinations` now, and the layout keeps it
    /// last because it is one of the rows the stored order cannot move.
    private func bottomGroup(secondaryItems: [SidebarNavItem]) -> some View {
        navGroup(secondaryItems, emphasis: .secondary)
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

    /// Every row Settings → Sidebar offers a handle for — a visibility toggle, a place in the
    /// stored order, and a colour override.
    private static let customisableDestinations: Set<CadenceFeatureDestination> =
        Set(SidebarStaticDestination.allCases.map(\.feature))

    /// What the user actually dragged, parsed straight from the preference rather than through
    /// `orderedDestinations(from:)`. That spelling fills the gaps from a stored *default*
    /// sequence, which would silently reorder a group nobody has customised — Focus would climb
    /// above Goals and Habits on a fresh install because the old default listed it third.
    private var storedOrder: [CadenceFeatureDestination] {
        sidebarTabOrderRaw
            .split(separator: ",")
            .compactMap { SidebarStaticDestination(rawValue: String($0))?.feature }
    }

    // MARK: - Nav grouping

    // Which destinations sit in which group is `CadenceSidebarLayout`'s decision, not this
    // view's: the iPad sidebar is being brought to the same structure, and the grouping and
    // ordering rules are the parts worth having exactly once. The stored `sidebarTabOrder`
    // sorts *within* a group — reordering in Settings still moves a row, it just can't move it
    // past the lists into the other group.
    private func navItems(
        in group: CadenceSidebarLayout.NavGroup,
        counts: CadenceSidebarCountInputs
    ) -> [SidebarNavItem] {
        CadenceSidebarLayout.resolvedDestinations(
            in: group,
            customisable: Self.customisableDestinations,
            storedOrder: storedOrder,
            hidden: Set(hiddenTabs.map(\.feature))
        )
        .compactMap { destination in
            guard let item = destination.macSidebarItem else { return nil }
            return SidebarNavItem(
                id: destination.rawValue,
                item: item,
                icon: destination.systemImage,
                label: destination.title,
                // Notes and Settings have no `SidebarStaticDestination` case, so Settings →
                // Sidebar offers them no colour picker and they fall back to the shared feature
                // tint. Every row that *does* have one keeps the user's override.
                tint: destination.sidebarStaticDestination
                    .map { Color(hex: $0.resolvedColorHex(from: sidebarTabColorsRaw)) }
                    ?? destination.tint,
                count: CadenceSidebarLayout.count(for: destination, counts: counts),
                accessibilityID: "sidebar.destination.\(destination.rawValue)"
            )
        }
    }
}

#endif

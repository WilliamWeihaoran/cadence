#if os(macOS)
import SwiftUI
import SwiftData

/// The sidebar is one column, top to bottom: app header, primary nav (Today, Tasks,
/// Calendar, Notes), lists, secondary nav (Goals, Habits) and a footer row of two glyphs
/// (Settings leading, Focus trailing).
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
    // Queried flat, not read off `context.areas` / `context.projects`. Iterating the relationship
    // is what made a context-less list invisible on this column — see `listSections` (T-538).
    // Unsorted on purpose: the one ordering is `CadenceSidebarLists`'.
    @Query private var areas: [Area]
    @Query private var projects: [Project]
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
                    isSelected: rowSelection == entry.item,
                    emphasis: emphasis,
                    accessibilityID: entry.accessibilityID
                ) {
                    selection = entry.item
                }
            }
        }
    }

    /// The secondary group: Goals and Habits as labelled rows, then Settings and Focus as one
    /// row of two glyphs. Pinned to the bottom of the column by the lists region above it,
    /// which is the only part that flexes.
    ///
    /// **The glyph row is `CadenceSidebarLayout.footerGlyphDestinations`, which macOS now honours
    /// too.** It drew four labelled rows here until the user asked for the two columns to match,
    /// and the split is worth keeping either way: these are the two least-travelled destinations
    /// in the column, and giving each of them a full row of height above the window's bottom edge
    /// spent the column's scarcest space on its quietest entries.
    ///
    /// The user's Settings → Sidebar order and hidden set are applied *before* the split, so
    /// hiding Focus leaves Settings alone in the footer rather than leaving a gap.
    private func bottomGroup(secondaryItems: [SidebarNavItem]) -> some View {
        let footerIDs = Set(CadenceSidebarLayout.footerGlyphDestinations.map(\.rawValue))
        let rowItems = secondaryItems.filter { !footerIDs.contains($0.id) }
        let glyphItems = CadenceSidebarLayout.footerGlyphDestinations.compactMap { destination in
            secondaryItems.first { $0.id == destination.rawValue }
        }

        return VStack(alignment: .leading, spacing: 0) {
            if !rowItems.isEmpty {
                navGroup(rowItems, emphasis: .secondary)
            }

            if !glyphItems.isEmpty {
                SidebarFooterGlyphRow(items: glyphItems, selection: selection) { item in
                    selection = item
                }
                .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
                .padding(.top, SidebarMetrics.rowSpacing)
            }
        }
        .padding(.top, SidebarMetrics.groupSpacing)
        .padding(.bottom, SidebarMetrics.bottomInset)
    }

    /// The selection as the *rows* see it.
    ///
    /// Inbox has no row of its own — it is one of the two views inside the Tasks destination — so
    /// a `.inbox` selection, which the command palette still produces, has to light the Tasks row
    /// rather than lighting nothing. `CadenceSidebarLayout.navRow(for:)` is the rule; this walks
    /// the destinations to get from a `SidebarItem` back to one, and passes area/project
    /// selections straight through because no destination claims them.
    private var rowSelection: SidebarItem? {
        guard let selection else { return nil }
        guard let destination = CadenceFeatureDestination.allCases.first(where: { $0.macSidebarItem == selection })
        else { return selection }
        return CadenceSidebarLayout.navRow(for: destination).macSidebarItem
    }

    // MARK: - Lists

    /// The region, top to bottom — **through the same rule the iPad column uses** (T-538).
    ///
    /// This used to be `ForEach(contexts)` handing each `Context` to a section that then read its
    /// own `context.areas` / `context.projects`. `Area.context` and `Project.context` are
    /// optional, and iOS's list editor writes `nil` there from its "None" row in every mode — so
    /// the Mac inherits by sync a list that belongs to no context, and a region derived by
    /// *iterating contexts* reaches it from nowhere. It was not un-grouped in this column; it was
    /// **invisible**. Archiving a context did the same to every list inside it.
    ///
    /// `CadenceSidebarLists.sections` already answered this for iPad, where the leftovers get an
    /// "Other" section, and its own doc comment named the macOS gap. Both columns route through it
    /// now. `keepingEmptyContexts` is the one difference and it is load-bearing: this header
    /// carries the "+" that opens `CreateListSheet`, the only way to make a list in a given
    /// context on macOS, so a context with no lists yet must still get a section.
    private var listSections: [CadenceSidebarLists.ElementSection<SidebarListEntry>] {
        CadenceSidebarLists.sections(
            contexts: contexts.filter { !$0.isArchived }.map {
                CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name)
            },
            elements: areas.filter(\.isActive).map(SidebarListEntry.area)
                + projects.filter(\.isActive).map(SidebarListEntry.project),
            keepingEmptyContexts: true,
            item: { $0.sidebarListItem }
        )
    }

    /// The single scrolling region. Takes every point the pinned groups don't, so
    /// Settings stays on the bottom edge whether the user has two lists or forty.
    private var listsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(listSections) { section in
                    contextSection(section)
                        .padding(.vertical, 2)
                }
            }
            .padding(.vertical, SidebarMetrics.groupSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// The catch-all section gets no "+": it stands for no context, so there is nothing for
    /// `CreateListSheet` — which requires one — to be opened *in*.
    private func contextSection(
        _ section: CadenceSidebarLists.ElementSection<SidebarListEntry>
    ) -> some View {
        let owner = section.contextID.flatMap { id in contexts.first { $0.id == id } }
        return ContextSection(
            title: section.title,
            entries: section.elements,
            selection: $selection,
            onAddList: owner.map { context in { contextForNewList = context } }
        )
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
        let tintOverrides = CadenceSidebarTint.overrides(from: sidebarTabColorsRaw)

        return CadenceSidebarLayout.resolvedDestinations(
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
                // "Tasks", not "All Tasks": the row opens both All and Inbox now.
                label: CadenceSidebarLayout.rowTitle(for: destination),
                // Notes and Settings have no `SidebarStaticDestination` case, so Settings →
                // Sidebar offers them no colour picker and they fall back to the destination's
                // default. Every row that *does* have one keeps the user's override. The rule is
                // `CadenceSidebarTint`'s, so the iPad column reads the same preference.
                tint: Color(hex: tintOverrides[destination] ?? destination.defaultColorHex),
                count: CadenceSidebarLayout.count(for: destination, counts: counts),
                accessibilityID: "sidebar.destination.\(destination.rawValue)"
            )
        }
    }
}

#endif

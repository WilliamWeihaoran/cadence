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
    /// The synced layout (T-1274). One row for the whole account; `@Query` rather than a fetch so
    /// a change made on the iPad redraws this column without anything here asking.
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]
    /// The device-local values this preference replaced, read only as the fallback for a store that
    /// holds no synced row yet — see `CadenceSidebarLayoutPreferenceStore.layout(from:)`.
    @AppStorage(CadencePreferenceKeys.sidebarHiddenTabs) private var sidebarHiddenTabsRaw = ""
    @AppStorage(CadencePreferenceKeys.sidebarTabOrder) private var sidebarTabOrderRaw = ""
    /// Still device-local, deliberately: T-1274 synced *which rows and in what order*, which is
    /// what the owner asked for. Colour is a separate preference and stayed where it was.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = ""

    @Environment(GlobalSearchManager.self) private var globalSearchManager

    @State private var newListTarget: SidebarNewListTarget? = nil

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
        .sheet(item: $newListTarget) { target in
            CreateListSheet(context: target.context)
        }
        // Both halves, because the row under the selection can go away two ways: the user hides it
        // here, or a sync brings a layout hiding it from another device.
        .onChange(of: visibleRows) { _, _ in moveSelectionOffAHiddenRow() }
        .onAppear { moveSelectionOffAHiddenRow() }
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
    ///
    /// **What it draws when there is nothing to draw is `SidebarListRegionContent`'s decision
    /// (T-1113).** This was a bare `ForEach(listSections)`, and `listSections` is derived entirely
    /// from existing contexts and existing lists — so on a fresh install it rendered *nothing*, and
    /// with it went the only macOS route to `CreateListSheet`. The `.firstListAction` row opens the
    /// same sheet the headers do, on no context.
    private var listsSection: some View {
        let sections = listSections

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch SidebarListRegionContent.resolve(sectionCount: sections.count) {
                case .firstListAction:
                    SidebarAddFirstListButton {
                        newListTarget = SidebarNewListTarget(context: nil)
                    }
                    .padding(.vertical, SidebarMetrics.contextSectionOuterVerticalPadding)
                case .sections:
                    ForEach(sections) { section in
                        contextSection(section)
                            // Counted by `SidebarContextHeaderRhythm`: two neighbours contribute it
                            // once each to the gap above a header, and it was a bare `2` here — in a
                            // different file from the other three pads — for exactly as long as the
                            // T-1041 test measured the wrong gap.
                            .padding(.vertical, SidebarMetrics.contextSectionOuterVerticalPadding)
                    }
                }
            }
            .padding(.vertical, SidebarMetrics.groupSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// **Every header carries a "+", the catch-all included (T-559).** It used to be the one
    /// exception, and the reason given was true at the time: `CreateListSheet` took a non-optional
    /// `Context`, so there was nothing for it to be opened *in*. That sheet takes an optional now
    /// and states the context in a row you can change, so the catch-all's "+" opens it already on
    /// "No context" instead of making the user open some unrelated context's "+" and clear the row.
    ///
    /// It is not the *only* route to a context-less list — the row in the sheet is reachable from
    /// every header — and it cannot be, because this section is drawn only when it already has rows
    /// in it. It is the route that reads as one.
    private func contextSection(
        _ section: CadenceSidebarLists.ElementSection<SidebarListEntry>
    ) -> some View {
        let owner = section.contextID.flatMap { id in contexts.first { $0.id == id } }
        return ContextSection(
            title: section.title,
            entries: section.elements,
            selection: $selection,
            onAddList: { newListTarget = SidebarNewListTarget(context: owner) }
        )
    }

    // MARK: - Tab visibility / order

    /// The user's layout, synced, with the device-local preference as the fallback.
    ///
    /// What it carries is **only what the user actually dragged or hid**, never a defaults-filled
    /// sequence: a defaults-filled order would silently reorder a group nobody has customised —
    /// Focus climbed above Goals and Habits on a fresh install the one time that was tried.
    var sidebarLayout: CadenceSidebarLayoutPreferenceStore.Layout {
        CadenceSidebarLayoutPreferenceStore.layout(
            from: sidebarLayoutPreferences,
            legacyOrderRaw: sidebarTabOrderRaw,
            legacyHiddenRaw: sidebarHiddenTabsRaw
        )
    }

    /// Every row this column draws, top to bottom, with the user's order and hidden set applied.
    /// The fallback below picks from this, so it lands on a row the user is actually looking at.
    private var visibleRows: [CadenceFeatureDestination] {
        CadenceSidebarLayout.NavGroup.allCases.flatMap { resolvedDestinations(in: $0) }
    }

    private func resolvedDestinations(
        in group: CadenceSidebarLayout.NavGroup
    ) -> [CadenceFeatureDestination] {
        let layout = sidebarLayout
        return CadenceSidebarLayout.resolvedDestinations(
            in: group,
            customisable: CadenceSidebarLayout.customisableDestinations,
            storedOrder: layout.order,
            hidden: layout.hidden
        )
    }

    /// Moves the selection off a row that has just been hidden.
    ///
    /// The rule is `CadenceSidebarLayout.selectionFallback(for:visibleRows:)` — shared with iOS,
    /// because a detail pane still showing Habits on one device and the first visible row on the
    /// other is the same preference read two ways. Hiding the page you are on is not rare: it is
    /// the most likely thing to hide, since it is the one in front of you.
    private func moveSelectionOffAHiddenRow() {
        let rows = visibleRows
        guard let selection,
              let destination = CadenceFeatureDestination.allCases.first(where: { $0.macSidebarItem == selection }),
              let fallback = CadenceSidebarLayout.selectionFallback(for: destination, visibleRows: rows),
              let item = fallback.macSidebarItem
        else { return }
        self.selection = item
    }

    // MARK: - Nav grouping

    // Which destinations sit in which group is `CadenceSidebarLayout`'s decision, not this
    // view's: both columns render the same structure, and the grouping and ordering rules are the
    // parts worth having exactly once. The user's stored order sorts *within* a group —
    // reordering in Settings still moves a row, it just can't move it past the lists into the
    // footer.
    private func navItems(
        in group: CadenceSidebarLayout.NavGroup,
        counts: CadenceSidebarCountInputs
    ) -> [SidebarNavItem] {
        let tintOverrides = CadenceSidebarTint.overrides(from: sidebarTabColorsRaw)

        return resolvedDestinations(in: group)
        .compactMap { destination in
            guard let item = destination.macSidebarItem else { return nil }
            return SidebarNavItem(
                id: destination.rawValue,
                item: item,
                icon: destination.systemImage,
                // "Tasks", not "All Tasks": the row opens both All and Inbox now.
                label: CadenceSidebarLayout.rowTitle(for: destination),
                // Settings has no `SidebarStaticDestination` case, so Settings → Sidebar offers
                // it no colour picker and it falls back to the destination's default; Notes
                // gained one in T-1274 along with its visibility toggle. Every row that has one
                // keeps the user's override. The rule is `CadenceSidebarTint`'s, so the iPad
                // column reads the same preference.
                tint: Color(hex: tintOverrides[destination] ?? destination.defaultColorHex),
                count: CadenceSidebarLayout.count(for: destination, counts: counts),
                accessibilityID: "sidebar.destination.\(destination.rawValue)"
            )
        }
    }
}

/// What the sidebar's "+" opens `CreateListSheet` on.
///
/// A wrapper rather than a bare `Context?`, because `.sheet(item:)` needs something `Identifiable`
/// and the catch-all's target *is* "no context" rather than "nothing to present". Its `id` is the
/// same `CadenceSidebarLists.Section.ungroupedID` the section itself uses, so the two spellings of
/// "the leftovers" cannot drift apart.
struct SidebarNewListTarget: Identifiable {
    let context: Context?

    var id: String { context?.id.uuidString ?? CadenceSidebarLists.Section.ungroupedID }
}

#endif

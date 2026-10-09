#if os(iOS)
import SwiftData
import SwiftUI

struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    /// Only the user's docked fold choice persists. Window measurements and drawer taps do not.
    @AppStorage("ios.sidebar.collapsed") private var isSidebarCollapsed = false
    @State private var isDrawerPresented = false
    /// The editor's presenter must survive hiding the navigation.
    @State private var listEditorRequest: iOSSidebarListEditorRequest?
    /// The capture `+` the shell draws **only while the drawer is modal** — see `drawerCaptureButton`.
    @State private var drawerCapture = iOSCaptureInteraction(placement: .bottomTrailing)

    var body: some View {
        GeometryReader { proxy in
            let isDrawerMode = !CadenceRootShellLayout.usesExpandedSidebar(windowWidth: proxy.size.width)
            let isSidebarVisible = isDrawerMode ? isDrawerPresented : !isSidebarCollapsed
            let isModal = isDrawerMode && isDrawerPresented
            let sidebarWidth = CadenceRootShellLayout.sidebarWidth(
                windowWidth: proxy.size.width,
                isCollapsed: isSidebarCollapsed
            )
            let detailWidth = CadenceRootShellLayout.detailWidth(
                windowWidth: proxy.size.width,
                isCollapsed: isSidebarCollapsed
            )
            let drawerWidth = CadenceRootShellLayout.drawerWidth(windowWidth: proxy.size.width)

            // Keep one sidebar and one detail alive across folding, drawer taps and resizing.
            // Only the docked reservation changes; an overlay never subtracts from the page.
            ZStack(alignment: .leading) {
                iOSSidebar(
                    selection: navigationSelection(isDrawerMode: isDrawerMode),
                    style: .expanded,
                    onCreateList: { listEditorRequest = $0 },
                    onCollapse: { setSidebarVisible(false, isDrawerMode: isDrawerMode) }
                )
                .frame(width: drawerWidth, height: proxy.size.height)
                .background(Theme.surface)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(width: 1)
                }
                .cadenceFixedTypography()
                .clipped()
                .offset(x: isSidebarVisible ? 0 : -drawerWidth)
                .allowsHitTesting(isSidebarVisible)
                .accessibilityHidden(!isSidebarVisible)
                .accessibilityAction(.escape) {
                    setSidebarVisible(false, isDrawerMode: isDrawerMode)
                }
                .zIndex(2)

                if isModal {
                    Button {
                        setSidebarVisible(false, isDrawerMode: true)
                    } label: {
                        Theme.scrim
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close sidebar")
                    .accessibilityIdentifier("cadence.sidebar.drawerBackdrop")
                    .keyboardShortcut(.escape, modifiers: [])
                    .zIndex(1)
                }

                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: sidebarWidth)
                        .accessibilityHidden(true)

                    // Hard-size and clip at the pane boundary, not just at the window edge:
                    // descendant minimums and page-local capture scrims stay in their pane.
                    detail()
                        .frame(width: detailWidth, height: proxy.size.height)
                        .background(Theme.bg)
                        .clipped()
                        .allowsHitTesting(!isModal)
                        .accessibilityHidden(isModal)
                        .overlay(alignment: .leading) {
                            if !isSidebarVisible {
                                iOSSidebarExpandHandle {
                                    setSidebarVisible(true, isDrawerMode: isDrawerMode)
                                }
                            }
                        }
                        .zIndex(0)
                }
                .zIndex(0)

                if isModal {
                    drawerCaptureButton
                        .zIndex(3)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
            .onChange(of: isDrawerMode) { _, _ in
                isDrawerPresented = false
            }
            .onChange(of: selection) { _, _ in
                if isDrawerMode {
                    setSidebarVisible(false, isDrawerMode: true)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.container)
        .sheet(item: $listEditorRequest) { request in
            iOSListEditorSheet(mode: request.mode, seededContext: request.seededContext)
        }
        // The composers the drawer's own `+` asks for. Mounted on the shell rather than on a page
        // for the same reason the phone's is mounted on `iOSCompactRootShell`: the control it
        // belongs to is drawn above a modal scrim, outside every page.
        .iOSCaptureHost(drawerCapture)
    }

    /// The capture `+`, drawn by the **shell** for exactly as long as the drawer is modal (T-3009).
    ///
    /// **Why the shell has to draw one at all.** `CadenceRootShellLayout.expandedMinWindowWidth` is
    /// 865 since the sidebar's `expandedWidth` became 264, and an 11" iPad in portrait is 834 — so
    /// in the orientation the device is usually held the sidebar is *only* ever the drawer, and the
    /// only way to see the lists T-2054 made into drop targets is to open it. Opening it is what
    /// took the `+` away: the page's own button lives inside `detail()`, which goes
    /// `allowsHitTesting(false)` under the modal scrim, so a plain tap on it dismissed the drawer
    /// and opened no composer, and a drag from it committed nothing. Drag-to-create had no reachable
    /// gesture on the target device at all.
    ///
    /// **Why this is the `+` showing through the scrim rather than a second one.** It is the same
    /// control — `iOSCaptureRadialMenuButton` at `iOSCircularAddButton.floatingDiameter`, at the
    /// same `edgeInset` from the same corner, with the same tap / hold / drag — and it exists only
    /// while the page's copy is hit-test-disabled. **One `+` is reachable at any moment**, which is
    /// the duplication rule this app keeps, not a second affordance for one action. A hole punched
    /// in the scrim could not have said that: the button is four levels down inside a pane the shell
    /// deliberately clips and disables as a unit, and nothing inside an `allowsHitTesting(false)`
    /// subtree can opt back in.
    ///
    /// Its interaction is its own `@State` for the reason every other one is (T-491): several
    /// surfaces are alive at once on iPad and only the one under the finger may open a composer.
    /// The drawer's targets are the sidebar's own — `iOSSidebarListsRegion` registers them, and
    /// opening the drawer moves them on screen, which is a geometry change and so republishes them.
    ///
    /// **Not driven in landscape**, because nothing in the permitted simulator tooling rotates a
    /// device: at ≥865pt the sidebar docks, `isModal` is false, this draws nothing, and the page's
    /// own `+` is live exactly as before.
    private var drawerCaptureButton: some View {
        iOSCaptureRadialMenuButton(
            diameter: iOSCircularAddButton.floatingDiameter,
            interaction: drawerCapture
        )
        .cadenceFixedTypography()
        .padding(.trailing, iOSCircularAddButton.edgeInset)
        .padding(.bottom, iOSCircularAddButton.edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func navigationSelection(isDrawerMode: Bool) -> Binding<iOSSidebarItem?> {
        Binding(
            get: { selection },
            set: {
                selection = $0
                // A tap on the current destination still dismisses; onChange alone cannot do that.
                if isDrawerMode {
                    setSidebarVisible(false, isDrawerMode: true)
                }
            }
        )
    }

    private func setSidebarVisible(_ visible: Bool, isDrawerMode: Bool) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if isDrawerMode {
                isDrawerPresented = visible
            } else {
                isSidebarCollapsed = !visible
            }
        }
    }
}

/// What a sidebar control asks its host to present: the list editor's mode, and the context the
/// control was attached to.
///
/// **One value rather than two pieces of `@State`.** `.sheet(item:)` reads the seed at
/// presentation time, so a mode written into one `@State` and a context written into another
/// would agree only by the order SwiftUI happened to apply them — and the failure would be a
/// sheet that opens on the wrong group, which looks correct on screen. That is the exact failure
/// mode T-2054 was filed against at the other end of the same wire.
///
/// `seededContext` carries `iOSListEditorSheet.seededContext`'s rule, not a second one: it is the
/// context the sheet *opens on*, which the sheet's own Context row then states and can change.
/// `nil` opens on "No context", which is what every call site did before this type existed.
struct iOSSidebarListEditorRequest: Identifiable {
    let mode: iOSListEditorMode
    var seededContext: Context?

    /// The mode's identity plus the seed's, so opening the same mode on two different groups
    /// re-presents the sheet rather than reusing the one already up.
    var id: String {
        guard let seededContext else { return mode.id }
        return "\(mode.id)-\(seededContext.id)"
    }
}

/// The iPad shell's navigation column: app header, primary nav, the scrolling lists region,
/// secondary nav.
///
/// **Only the lists region scrolls.** Everything else is pinned, for the reason macOS's
/// `SidebarView` gives: navigation and lists share one column, and if the whole column scrolled a
/// long list collection would push Settings below the fold.
///
/// Group membership, ordering and the count rule live in `CadenceSidebarLayout`; which context owns
/// which list lives in `CadenceSidebarLists`. Both are in `Shared/` and both are what macOS reads,
/// so this file is a rendering of that layout rather than a second copy of it.
struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    let style: iOSSidebarStyle
    let onCreateList: (iOSSidebarListEditorRequest) -> Void
    let onCollapse: () -> Void

    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// The same preference macOS's Settings → Sidebar colour picker writes. This column has no
    /// picker of its own, so in practice this is empty and every row falls back to its
    /// destination's default — but reading it is what makes the two columns one sidebar rather
    /// than two that happen to agree today.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference
    /// The synced sidebar layout (T-1274) — which rows the user keeps and in what order. This
    /// column had no say in it until then: macOS honoured the preference and iPad drew the declared
    /// list, so one account's two sidebars disagreed by construction.
    ///
    /// No device-local fallback is read here, unlike `SidebarView`: the preference it falls back to
    /// was only ever written by macOS's Settings screen, so on iOS it is empty by definition.
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]

    private var tintOverrides: [CadenceFeatureDestination: String] {
        CadenceSidebarTint.overrides(from: sidebarTabColorsRaw)
    }

    private func tint(for destination: CadenceFeatureDestination) -> Color {
        Color(hex: tintOverrides[destination] ?? destination.defaultColorHex)
    }

    /// The selection as the *rows* see it.
    ///
    /// Inbox has no row of its own — it is one of the two views inside the Tasks destination — so
    /// a `.inbox` selection has to light the Tasks row rather than lighting nothing.
    /// `CadenceSidebarLayout.navRow(for:)` is the rule, shared with `SidebarView`.
    private var rowSelection: iOSSidebarItem? {
        guard let selection else { return nil }
        guard let destination = CadenceFeatureDestination.allCases.first(where: { $0.item == selection })
        else { return selection }
        return CadenceSidebarLayout.navRow(for: destination).item
    }

    /// Built once per render and handed to every row, the same shape `SidebarView` uses. Each tally
    /// is one pass over the task list.
    ///
    /// All Tasks counts only work inside still-active areas/projects, the scope its page uses.
    /// Today's overdue tally counts against every task, because Today itself does.
    private var countInputs: CadenceSidebarCountInputs {
        CadenceSidebarCountInputs(
            todayOverdueCount: CadenceSidebarLayout.overdueTaskCount(
                from: allTasks,
                todayKey: DateFormatters.todayKey()
            ),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(
                from: allTasks.filter(\.isInActiveContainer)
            )
        )
    }

    private var sidebarLayout: CadenceSidebarLayoutPreferenceStore.Layout {
        CadenceSidebarLayoutPreferenceStore.layout(from: sidebarLayoutPreferences)
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

    /// Every row this column draws, top to bottom, with the layout applied. `.lists` is not among
    /// them: it is this platform's own row and nothing can hide it.
    private var visibleRows: [CadenceFeatureDestination] {
        CadenceSidebarLayout.NavGroup.allCases.flatMap { resolvedDestinations(in: $0) }
    }

    /// Moves the selection off a row that has just been hidden, by the same shared rule macOS
    /// uses — `CadenceSidebarLayout.selectionFallback(for:visibleRows:)`. The layout is synced, so
    /// the row under the selection can go away because of an edit made on another device.
    private func moveSelectionOffAHiddenRow() {
        let rows = visibleRows
        guard let selection,
              let destination = CadenceFeatureDestination.allCases.first(where: { $0.item == selection }),
              let fallback = CadenceSidebarLayout.selectionFallback(for: destination, visibleRows: rows)
        else { return }
        self.selection = fallback.item
    }

    private var listSections: [CadenceSidebarLists.Section] {
        CadenceSidebarLists.sections(
            contexts: contexts.filter { !$0.isArchived }.map {
                CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name)
            },
            // Spelled as closures rather than `map(Item.init)`: an unapplied initializer reference
            // is resolved in a nonisolated context, and these read SwiftData relationships.
            items: areas.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
                + projects.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
        )
    }

    var body: some View {
        let counts = countInputs

        VStack(alignment: .leading, spacing: 0) {
            iOSSidebarHeader(
                style: style,
                onSearch: { selection = .search },
                onCollapse: onCollapse
            )
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)

            navGroup(resolvedDestinations(in: .primary), counts: counts)
                .padding(.bottom, iOSSidebarMetrics.groupSpacing)

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)

            listsRegion

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)

            // Settings and Focus collapse to one row of two glyphs, and since T-3073 there is
            // no labelled row left down here at all — Goals and Habits are nav rows in the group
            // at the top, and Lists is the region above rather than a row below it.
            //
            // The emptiness is guarded rather than assumed, exactly as `SidebarView.bottomGroup`
            // guards it: `navGroup` of nothing is still a padded stack, so an unguarded call
            // spends `groupSpacing` of dead height above the footer for a group that draws
            // nothing — and a future destination placed below the lists would find the row back.
            if style == .expanded {
                let secondaryRows = secondaryRowDestinations

                if !secondaryRows.isEmpty {
                    navGroup(secondaryRows, counts: counts)
                        .padding(.top, iOSSidebarMetrics.groupSpacing)
                }

                footerGlyphRow
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.top, iOSSidebarMetrics.rowSpacing)
                    .padding(.bottom, 12)
            }
        }
        // Both halves, because the row under the selection can go away two ways: the user hides it
        // in Settings, or a sync brings a layout hiding it from another device.
        .onChange(of: visibleRows) { _, _ in moveSelectionOffAHiddenRow() }
        .onAppear { moveSelectionOffAHiddenRow() }
    }

    /// Settings and Focus, one row, pushed to opposite ends.
    ///
    /// Tinted glyphs on the column's own hover/selection plate, at the nav rows' radius — the same
    /// treatment `SidebarFooterGlyphRow` draws on macOS, which adopted this row's *structure* in
    /// the same pass this row adopted macOS's *colouring*. These are the two least-travelled
    /// destinations in the column, which is why they share one row's height rather than taking
    /// one each; it is not a reason to strip their identity.
    private var footerGlyphRow: some View {
        // Filtered through the resolved group so a hidden Focus leaves Settings alone in the footer
        // rather than leaving a gap, which is what macOS's footer has always done. Ordered by
        // `footerGlyphDestinations`, because that list — not the user's — decides which glyph
        // leads.
        let glyphs = CadenceSidebarLayout.footerGlyphDestinations
            .filter { resolvedDestinations(in: .secondary).contains($0) }

        return HStack(spacing: 0) {
            ForEach(Array(glyphs.enumerated()), id: \.element) { index, destination in
                if index > 0 {
                    Spacer(minLength: 8)
                }

                iOSSidebarGlyphButton(
                    systemImage: destination.systemImage,
                    label: CadenceSidebarLayout.rowTitle(for: destination),
                    tint: tint(for: destination),
                    isSelected: rowSelection == destination.item
                ) {
                    selection = destination.item
                }
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: - Nav groups

    /// `CadenceSidebarLayout`'s secondary rows, and **nothing prepended to them (T-3073)**.
    ///
    /// This list carried `.lists` ahead of the shared rows from T-1275 until now, and the prepend
    /// was load-bearing rather than decorative: `iOSListsView` is the only surface that draws
    /// `iOSListCreateButtonsRow`, so for as long as this row was the only thing selecting `.lists`
    /// at regular width, deleting it made list creation unreachable — T-1113's shape on the other
    /// platform.
    ///
    /// The owner asked for the row to go — *"in ipados side bar, we're still showing 'lists' on
    /// the bottom with a green icon. remove that"* — and it goes **because the door moved into the
    /// region above**, not because the regression stopped being one. `iOSSidebarListsRegion` now
    /// carries a `+` on every context header and an "Add first list" row when it holds nothing at
    /// all, which is exactly what `SidebarView` has drawn on macOS since T-559/T-1113. Delete
    /// those and list creation is unreachable again; `theIPadListsRegionCarriesTheCreateDoorAndTheListsRowIsGone`
    /// is the pin.
    ///
    /// `.lists` survives as a *destination* — `iOSRootView` still routes it and
    /// `CadenceShellNavigationBridge` still projects a selected area or project onto it when the
    /// shell widens — it simply has no row of its own any more. It is still out of
    /// `CadenceSidebarLayout`'s shared groups, because macOS has no Lists page to route to.
    private var secondaryRowDestinations: [CadenceFeatureDestination] {
        CadenceSidebarLayout.secondaryRowDestinations.filter(isVisibleSecondaryRow)
    }

    /// Whether a row below the lists survives the user's hidden set (T-1274).
    ///
    /// There is no exception left in it. `.lists` was one from T-1274 to T-3073 — it is this
    /// platform's own row and Settings offers no handle for it, so the hidden set could only ever
    /// have hidden it by accident — and the row it protected no longer exists.
    private func isVisibleSecondaryRow(_ destination: CadenceFeatureDestination) -> Bool {
        resolvedDestinations(in: .secondary).contains(destination)
    }

    private func navGroup(
        _ destinations: [CadenceFeatureDestination],
        counts: CadenceSidebarCountInputs
    ) -> some View {
        VStack(alignment: .leading, spacing: iOSSidebarMetrics.rowSpacing) {
            ForEach(destinations) { destination in
                iOSSidebarButton(
                    title: CadenceSidebarLayout.rowTitle(for: destination),
                    systemImage: destination.systemImage,
                    tint: tint(for: destination),
                    count: CadenceSidebarLayout.count(for: destination, counts: counts),
                    isSelected: rowSelection == destination.item,
                    style: style
                ) {
                    selection = destination.item
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
    }

    // MARK: - Lists

    /// The sidebar's one scrolling region. See `iOSSidebarListsRegion`, which is where it lives.
    private var listsRegion: some View {
        iOSSidebarListsRegion(
            sections: listSections,
            style: style,
            isSelected: { selection == $0.selectionItem },
            onSelect: { selection = $0.selectionItem },
            onEdit: { item in
                editorMode(for: item)
                    .map { onCreateList(iOSSidebarListEditorRequest(mode: $0)) }
            },
            // The tap half of T-2054's drag, and since T-3073 the column's only create door.
            // `.newArea` is the editor's *entry* mode, not a decision: the first control in the
            // sheet is its Area/Project segment, so one `+` reaches both — which is why this
            // column does not need the Lists page's two buttons to say the same thing twice.
            onCreateList: { contextID in
                onCreateList(
                    iOSSidebarListEditorRequest(
                        mode: .newArea,
                        seededContext: contextID.flatMap { id in contexts.first { $0.id == id } }
                    )
                )
            }
        )
    }

    private func editorMode(for item: CadenceSidebarLists.Item) -> iOSListEditorMode? {
        switch item.kind {
        case .area:
            return areas.first { $0.id == item.id }.map(iOSListEditorMode.editArea)
        case .project:
            return projects.first { $0.id == item.id }.map(iOSListEditorMode.editProject)
        }
    }
}

// MARK: - The lists region

/// The sidebar's single scrolling region: every context's lists, grouped under the context's name,
/// and **nothing above them (T-1275).**
///
/// It was pinned under a row reading "Lists", which the owner read as a heading over the rows it
/// sat on: *"there shouldnt be a section called just lists cuz we're gonna show all the lists there
/// anyways"*. It is the standing page-header rule at sidebar scale, and the macOS column already
/// heads its own list region with nothing. The Lists *destination* is still a row — it is the first
/// of the secondary nav rows below the region now, because it is the only door to the one surface
/// that can make a *project*. See `iOSSidebar.secondaryRowDestinations`.
///
/// The context headers inside the region stay: those name something the rows under them do not say,
/// which is the difference between a heading and a label.
///
/// **A `struct`, and deliberately one declared in this file.** It was a computed property of
/// `iOSSidebar`, which made it unreachable from anywhere else; the iPhone Tasks index will draw
/// this same region, and a private computed property cannot be shared while a view can. Moving it
/// to a file of its own is the change *not* made: seven test suites read this path by name, so a
/// move would turn a view change into a seven-suite edit.
///
/// It takes closures rather than a `Binding` to the selection for the same reason the row below it
/// does: the region neither owns the selection nor knows what a selection means on the host that
/// draws it, and a second host is exactly what this struct exists for.
struct iOSSidebarListsRegion: View {
    let sections: [CadenceSidebarLists.Section]
    let style: iOSSidebarStyle
    let isSelected: (CadenceSidebarLists.Item) -> Bool
    let onSelect: (CadenceSidebarLists.Item) -> Void
    let onEdit: (CadenceSidebarLists.Item) -> Void
    /// **The region's create door (T-3073).** Takes the context the `+` was attached to, or `nil`
    /// from the catch-all and from the first-list row, which is the same `nil` the region's own
    /// drop target already hands `CadenceTaskDropSupport.newListDropKey(contextID:)`.
    ///
    /// A `UUID?` rather than a `Context`, for the reason every other closure here is a closure:
    /// this view holds values, not model objects, and two hosts draw it. Each resolves the id
    /// against its own query.
    let onCreateList: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                // Zero, and the sections pad themselves — the shape `SidebarView.listsSection`
                // already had. A stack spacing is one number for every boundary; the gap a reader
                // sees above a context header is four terms applied in four places, and
                // `CadenceSidebarContextHeaderRhythm` can only add them up if each is spelled where
                // it is spent.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        listSection(section)
                            .padding(.vertical, iOSSidebarMetrics.contextSectionOuterVerticalPadding)
                    }

                    if sections.isEmpty {
                        emptyListsRow
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, iOSSidebarMetrics.groupSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
        // **The outermost of the region's three drop layers, and the one that is always there.**
        //
        // A `+` released on a context section makes a list in that context; on a list row, a task
        // in that list; and here — on the gap under the last section, on the catch-all "Other", or
        // on a column that has no sections at all because nothing has been made yet — a list in no
        // group. `CadenceCaptureDropHitTest` takes the smallest containing frame, so the inner two
        // win wherever they are and no registration order has to be arranged, which is the same
        // thing `theMoreSpecificTargetWinsHoweverTheyWereRegistered` already pins.
        //
        // The third case is the load-bearing one. A fresh install draws `emptyListsRow` and
        // nothing else, and a create-door that only appears once something has been created is
        // T-1113's shape exactly: a region that drew nothing on a fresh install took the only
        // route to a list sheet with it.
        .iOSNewTaskDropTarget(
            horizontalInset: style.horizontalPadding,
            ghost: .region,
            dropKey: { CadenceTaskDropSupport.newListDropKey(contextID: nil) }
        )
    }

    /// A context's header and the rows under it — and, since T-2054, **a create-door**: a `+`
    /// dragged onto the group makes a list *in* that group.
    ///
    /// *"when i drag the blue + button onto the side bar lists, it should create a list there… the
    /// blue add button on ios and ipados should create things with inherited context when dragged
    /// into some region"*. A context group is the one region in this app that implies a list rather
    /// than a task, which is why it is the only thing that emits
    /// `CadenceTaskDropSupport.newListDropKey(contextID:)`.
    ///
    /// **The catch-all "Other" registers nothing**, and that is the rule
    /// `CadenceSidebarLists.Section.contextID` already states with `nil` and
    /// `CadenceTaskDropSupport.dropKey(forGroup:)` states for Overdue and Completed: a header with
    /// nothing to hand over does not light up. The empty key is how a call site says that — see
    /// `iOSNewTaskDropFrameRegistry.candidates()` — so a drop on "Other" falls through to the
    /// region's own target, which is "a list in no group", which is precisely what "Other"
    /// collects.
    @ViewBuilder
    private func listSection(_ section: CadenceSidebarLists.Section) -> some View {
        VStack(alignment: .leading, spacing: iOSSidebarMetrics.rowSpacing) {
            if style == .expanded {
                // `SectionEyebrowLabel` is already the app's one eyebrow, and macOS's own context
                // header chains off the same `Size.standard` figures — so the glyphs were never the
                // half that differed. What differed is the room: 14pt above and 7pt below, which
                // with the stack's own `rowSpacing` is the Mac's 26 above and 9 below.
                //
                // **Label, spacer, `+` — `ContextSection`'s own line, now on both columns
                // (T-3073).** The glyph is `iOSSidebarGlyphButton`, which is this column's
                // existing 26pt plate with a 44pt hit area, so the header gains a touch target
                // without gaining a touch target's *height*: none of
                // `CadenceSidebarContextHeaderRhythm`'s four terms moves.
                HStack(spacing: iOSSidebarMetrics.iconLabelSpacing) {
                    SectionEyebrowLabel(text: section.title)
                        .lineLimit(1)

                    Spacer(minLength: iOSSidebarMetrics.listTrailingItemSpacing)

                    iOSSidebarGlyphButton(
                        systemImage: "plus",
                        label: "Add list to \(section.title)"
                    ) {
                        onCreateList(section.contextID)
                    }
                }
                .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
                .padding(.top, iOSSidebarMetrics.contextHeaderTopPadding)
                .padding(.bottom, iOSSidebarMetrics.contextHeaderBottomPadding)
            }

            ForEach(section.items) { item in
                iOSSidebarListRow(
                    item: item,
                    isSelected: isSelected(item),
                    style: style,
                    onSelect: { onSelect(item) },
                    onEdit: { onEdit(item) }
                )
                // A row is a list, so it offers what every other list row in the app offers: a
                // task in it. Same identity, same key, same ghost — this column joins the table
                // rather than minting a second spelling of "which list".
                .iOSNewTaskDropTarget(
                    group: .list(key: Self.dropListKey(for: item), name: item.name),
                    horizontalInset: iOSSidebarMetrics.rowHorizontalPadding
                )
            }
        }
        .padding(.bottom, iOSSidebarMetrics.contextSectionBottomPadding)
        .iOSNewTaskDropTarget(
            horizontalInset: iOSSidebarMetrics.rowHorizontalPadding,
            ghost: .region,
            listName: { section.title },
            dropKey: {
                guard let contextID = section.contextID else { return "" }
                return CadenceTaskDropSupport.newListDropKey(contextID: contextID)
            }
        )
    }

    /// The `list:` value a sidebar row hands a dropped `+`, in the one spelling
    /// `CadenceTaskDropSupport.containerKey(for:)` owns.
    static func dropListKey(for item: CadenceSidebarLists.Item) -> String {
        switch item.kind {
        case .area: return CadenceTaskDropSupport.containerKey(for: .area(item.id))
        case .project: return CadenceTaskDropSupport.containerKey(for: .project(item.id))
        }
    }

    /// A statement **and**, since T-3073, a button — `SidebarAddFirstListButton`'s job on the
    /// touch column.
    ///
    /// It was a statement alone, and the reason given was that the way to make a list is the Lists
    /// row pinned below the region. That row is gone, so the sentence that justified drawing
    /// nothing here is the sentence that now requires drawing something: a fresh install has no
    /// contexts and no lists, this row is the whole of what the region draws, and a create door
    /// that only appears once something has been created is T-1113 exactly.
    ///
    /// The statement stays above the button rather than being replaced by it, because it is
    /// `CadenceEmptyStateCopy`'s one spelling of *what is missing* and the button says only what
    /// to do about it.
    @ViewBuilder
    private var emptyListsRow: some View {
        if style == .expanded {
            VStack(alignment: .leading, spacing: 6) {
                Text(CadenceEmptyStateCopy.listsTitle(isNarrowed: false))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)

                addFirstListButton
            }
            .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
            .padding(.vertical, 6)
        }
    }

    /// The macOS column's "Add first list" row, in this column's vocabulary: an
    /// `iOSSidebarListRow`-shaped plate on no context, so an empty region and a populated one
    /// share a left edge and a corner radius.
    private var addFirstListButton: some View {
        Button {
            onCreateList(nil)
        } label: {
            HStack(spacing: iOSSidebarMetrics.iconLabelSpacing) {
                Image(systemName: "plus.circle")
                    .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                    .frame(width: iOSSidebarMetrics.iconSlotWidth)

                Text(CadenceEmptyStateCopy.addFirstListAction)
                    .font(.system(size: iOSSidebarMetrics.labelFontSize, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: iOSSidebarMetrics.listTrailingItemSpacing)
            }
            .foregroundStyle(Theme.dim)
            .frame(height: iOSSidebarMetrics.buttonHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
            .background(
                RoundedRectangle(
                    cornerRadius: iOSSidebarMetrics.selectedCornerRadius,
                    style: .continuous
                )
                .fill(Theme.surfaceElevated.opacity(0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }
}

// MARK: - Model → value bridge

/// The two `Item` initialisers this extension used to hold live in `CadenceSidebarListsBridge`
/// now. macOS carried a second, divergent copy that took the context id as a **non-optional**
/// parameter, which is what made a context-less list undrawable on that column (T-538).
private extension CadenceSidebarLists.Item {
    var selectionItem: iOSSidebarItem {
        switch kind {
        case .area: return .area(id)
        case .project: return .project(id)
        }
    }
}

extension iOSSidebarItem {
    /// The feature this row stands for, for the projection that carries a selection across a
    /// size-class change (`CadenceShellNavigationBridge`, T-334).
    ///
    /// A specific area or project answers `.lists`: the compact shell reaches a list through the
    /// Lists screen, and pushing the list itself would need a route this projection has no business
    /// minting. Landing on Lists is the same room one door out; landing on Today is the bug.
    var featureDestination: CadenceFeatureDestination? {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .notes: return .notes
        case .lists, .area, .project: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }
}

extension CadenceFeatureDestination {
    var item: iOSSidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .notes: return .notes
        case .lists: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }
}

// MARK: - Style and metrics

/// **One case since T-3079**, and deliberately still an enum.
///
/// `.rail` was an icon-rail spelling of this column for a narrow window, and it was unreachable:
/// every construction site hardcodes `.expanded`, and nothing called the `style(for:)` that
/// computed it. Reachable it would still not have drawn a rail — `CadenceRootShellLayout`'s
/// narrow-window answer is a *drawer* whose width is `min(expandedWidth, width)`, so the column
/// would have been 264pt wide with rail-width glyphs in it. A genuine icon rail, if one is ever
/// wanted, gets designed against that layout rather than resurrected from this.
///
/// Collapsing the remaining case away at every call site is a separate change, not this one.
enum iOSSidebarStyle: Equatable {
    case expanded

    var horizontalPadding: CGFloat {
        switch self {
        case .expanded: return 10
        }
    }
}

/// The iPad column's spelling of `CadenceSidebarMetrics`.
///
/// **Every figure here is the shared one now.** The two columns had each been deciding for
/// themselves and had drifted in five dimensions nobody chose — 13pt glyphs against macOS's 15,
/// 14pt labels against 13, 9pt of icon-to-label against 10, a list colour bar 16pt tall against 14,
/// and an 11pt due-date caption against 10. The user asked for one sidebar, so the numbers live in
/// `Shared/` and both files read them. The colour bar's three figures are not among them any more:
/// the bar itself was removed on both platforms by T-2084.
///
/// `buttonHeight` and `listRowHeight` are the two exceptions, and they are
/// `CadenceSidebarMetrics`' exceptions rather than this file's. `buttonHeight` is 44pt because a
/// nav row is the most-tapped control in this shell, where macOS's 32 is right under a pointer.
/// `listRowHeight` is 36 (T-3072) because the owner asked for the Mac's tighter list rhythm and a
/// full-width row can give some of it back without dropping to a height a finger misses — the
/// trade is argued on `CadenceSidebarRowMetrics.listRowHeight`, not here.
enum iOSSidebarMetrics {
    private static let shared = CadenceSidebarMetrics.metrics(for: .tablet)

    static let buttonHeight: CGFloat = shared.rowHeight
    static let iconSize: CGFloat = shared.iconSize
    static let selectedCornerRadius: CGFloat = shared.cornerRadius
    static let rowSpacing: CGFloat = shared.rowSpacing
    static let rowHorizontalPadding: CGFloat = shared.horizontalPadding
    static let iconSlotWidth: CGFloat = shared.iconSlotWidth
    static let iconLabelSpacing: CGFloat = shared.iconLabelSpacing
    static let labelFontSize: CGFloat = shared.labelFontSize
    static let badgeLeadingGap: CGFloat = shared.badgeLeadingGap
    static let groupSpacing: CGFloat = shared.groupSpacing
    static let secondaryIconOpacity: Double = shared.secondaryIconOpacity

    // MARK: List rows

    /// **An Area/Project row is shorter than a nav row here, and only here (T-3072).**
    /// `buttonHeight` still carries every nav row at 44; this carries the list rows alone, so the
    /// column reads as a fixed nav group above a denser scrolling list region — which is where the
    /// owner was looking when they asked for it.
    ///
    /// Read from the shared constant rather than `shared.listRowHeight`, which is `Optional`
    /// because macOS states no list-row height at all: a `??` here would silently fall back to
    /// some other figure the day the table changed, and this surface has exactly one answer.
    static let listRowHeight: CGFloat = CadenceSidebarMetrics.touchListRowHeight
    static let listDueDateIconSize: CGFloat = shared.listDueDateIconSize
    static let listDueDateFontSize: CGFloat = shared.listDueDateFontSize
    static let listDueDateSpacing: CGFloat = shared.listDueDateSpacing
    static let listTrailingItemSpacing: CGFloat = shared.listTrailingItemSpacing

    // MARK: Context headers

    /// **The context header's rhythm is `CadenceSidebarContextHeaderRhythm`', not this file's
    /// (T-3072).** This column drew 8pt above a header and 4pt below against macOS's 26 and 9, so
    /// the headers that say which lists go together were the quietest thing in the column:
    /// *"make the context names stand out more and have more vertical space, make it to be the same
    /// as mac os"*. The terms are in `Shared/` now and both columns read them; the *text* treatment
    /// was already one decision, because both sides draw the app's eyebrow.
    ///
    /// Four names, not six: this column stacks its sections at zero spacing and pads each one, the
    /// way `SidebarView.listsSection` does, and it draws no leading drop zone — there is no list
    /// drag-reorder here — so the height macOS spends on that transparent target is folded into
    /// `touchHeaderBottomPadding` and the two columns still show the same gap.
    static let contextHeaderTopPadding: CGFloat = CadenceSidebarContextHeaderRhythm.headerTopPadding
    static let contextHeaderBottomPadding: CGFloat =
        CadenceSidebarContextHeaderRhythm.touchHeaderBottomPadding
    static let contextSectionBottomPadding: CGFloat =
        CadenceSidebarContextHeaderRhythm.sectionBottomPadding
    static let contextSectionOuterVerticalPadding: CGFloat =
        CadenceSidebarContextHeaderRhythm.sectionOuterVerticalPadding

    /// The footer row's two glyph plates, matching `SidebarMetrics.footerGlyphSize`.
    static let footerGlyphSize: CGFloat = 28
}

struct iOSSidebarRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

// MARK: - Header

/// The app mark, the product name, and the column's two controls: search, and fold.
///
/// The mark used to be the button that opened the lists drawer, wearing a `sidebar.leading` glyph
/// that promised to collapse the sidebar and did not. The glyph is now a control of its own, and it
/// does exactly what it has always looked like it would.
///
/// Search lives here because the sidebar's two nav groups are `CadenceSidebarLayout`'s, and that
/// layout deliberately leaves `.search` out of them — it is the header's button, on both platforms.
struct iOSSidebarHeader: View {
    let style: iOSSidebarStyle
    let onSearch: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        if style == .expanded {
            HStack(spacing: 8) {
                iOSIconTile(systemImage: "circle.hexagongrid.fill", color: Theme.blue, size: 28, iconSize: 14)

                Text("Cadence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                searchButton
                collapseButton
            }
            .frame(minHeight: 44)
        }
    }

    private var searchButton: some View {
        iOSSidebarGlyphButton(
            systemImage: CadenceFeatureDestination.search.systemImage,
            label: "Search",
            action: onSearch
        )
    }

    private var collapseButton: some View {
        iOSSidebarGlyphButton(
            systemImage: "sidebar.leading",
            label: "Hide Sidebar",
            action: onCollapse
        )
    }
}

/// A small plate with a 44pt hit area — `iOSIconButton`'s trick. The header has to hold a mark, a
/// wordmark and two controls inside 188pt, and padding either control out to 44pt in *layout* would
/// push the wordmark off the row.
///
/// Two jobs, told apart by `tint`. The header's search and collapse controls are **actions**: they
/// stay `Theme.dim` and can never be selected. The footer's Settings and Focus are
/// **destinations**: they carry the same per-destination tint the nav rows above them do, and
/// selection is the same `Theme.surfaceHighlight` plate at the same radius — one layer, one
/// radius. Brightening the glyph to `Theme.text` was how this row used to carry selection, and it
/// cannot survive a tinted glyph: the colour is the destination's identity, so overwriting it to
/// mean "selected" would say two things through one channel.
private struct iOSSidebarGlyphButton: View {
    let systemImage: String
    let label: String
    /// `nil` for the header's two action controls. See the type comment.
    var tint: Color? = nil
    var isSelected = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: plateSize, height: plateSize)
                .background(shape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
                .contentShape(shape)
                .iOSExpandedHitArea(9)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var glyphSize: CGFloat {
        tint == nil ? 13 : iOSSidebarMetrics.iconSize
    }

    private var plateSize: CGFloat {
        tint == nil ? 26 : iOSSidebarMetrics.footerGlyphSize
    }

    private var glyphColor: Color {
        guard let tint else { return Theme.dim }
        return tint.opacity(iOSSidebarMetrics.secondaryIconOpacity)
    }
}

/// The way back into a folded sidebar.
///
/// A tab on the leading edge rather than a button in a corner: page headers own the top-leading
/// corner of every detail pane, and a floating control there would cover one. 22pt of plate and
/// 44pt of target, vertically centred, where a thumb reaching round the bezel already is.
struct iOSSidebarExpandHandle: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 22, height: 56)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: Theme.radiusControl,
                        topTrailingRadius: Theme.radiusControl,
                        style: .continuous
                    )
                    .fill(Theme.surfaceElevated)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: Theme.radiusControl,
                        topTrailingRadius: Theme.radiusControl,
                        style: .continuous
                    )
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .iOSExpandedHitArea(11)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Show Sidebar")
    }
}

// MARK: - Rows

/// A navigation row in the iPad shell's sidebar.
///
/// **The glyph carries its destination's tint**, the same one macOS draws. This file argued the
/// opposite for a while — that six hues in one column encode nothing a reader can act on, and that
/// macOS only keeps its tints because Settings → Sidebar has a per-destination colour picker there
/// while iPad has none, so the hue was decoration here. The user compared the two columns and asked
/// for iOS to match macOS's colouring, which settles it: `CadencePreferenceKeys.sidebarTabColors`
/// is a plain preference string, `CadenceSidebarTint` parses it for both platforms, and this column
/// honours an override written on the Mac whether or not it ever grows the picker itself.
///
/// What carries state is the row: `Theme.surfaceHighlight` behind it, `Theme.text` on the label,
/// semibold. One layer, one radius — `SidebarNavRow`'s rule, and the iPhone More tab's.
struct iOSSidebarButton: View {
    let title: String
    let systemImage: String
    /// The destination's own colour, resolved through `CadenceSidebarTint` so this column reads
    /// the same `sidebarTabColors` preference macOS's picker writes.
    let tint: Color
    let count: CadenceSidebarCount?
    let isSelected: Bool
    let style: iOSSidebarStyle
    let action: () -> Void

    /// The glyph keeps its destination tint selected or not, exactly as `SidebarNavRow` does:
    /// selection is the plate and the heavier label, never the hue.
    private var glyphColor: Color {
        tint
    }

    var body: some View {
        Button(action: action) {
            if style == .expanded {
                expandedLabel
            }
        }
        .buttonStyle(.iosPressable)
        // T-1445, the same rule macOS's `SidebarNavRow` reads: the badge is drawn by the shared
        // `CadenceSidebarCountLabel`, which is `accessibilityHidden`, so the row is the only place
        // the number can be announced — and it has to say *what* it counts, because Today's is an
        // overdue tally and the Today page's header badge is a different one.
        .accessibilityLabel(CadenceSidebarLayout.rowAccessibilityLabel(title, count: count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var expandedLabel: some View {
        HStack(spacing: iOSSidebarMetrics.iconLabelSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iOSSidebarMetrics.iconSlotWidth)

            Text(title)
                .font(.system(size: iOSSidebarMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: iOSSidebarMetrics.badgeLeadingGap)

            if let count {
                CadenceSidebarCountLabel(count: count)
                    // The count is the row's fixed element; the label is what gives.
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionLayer)
        .contentShape(selectionShape)
    }

    private var selectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    /// One selection layer at one radius, the rule `SidebarNavRow` follows: selection is a step up
    /// the neutral ramp, not a coloured 2pt rail bolted to the leading edge of an otherwise
    /// unchanged row.
    private var selectionLayer: some View {
        selectionShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear)
    }
}

/// One area/project row: the name, and optional trailing metadata.
///
/// **No glyph, and no colour bar either (T-2084).** A list's icon was a second identity competing
/// with its colour and its name, and a column of a dozen different symbols is harder to scan than a
/// column of names, so the glyphs became a 2pt bar in the row's leading padding. The owner then read
/// the column of bars the same way and asked for them gone with nothing in their place — the same
/// removal `SidebarListRow` carries on macOS, and for the same reason. The bar was an `.overlay`, so
/// nothing reflowed when it went. `item.colorHex` is still the list's colour everywhere it is
/// chosen or shown; this row simply stopped drawing it.
struct iOSSidebarListRow: View {
    let item: CadenceSidebarLists.Item
    let isSelected: Bool
    let style: iOSSidebarStyle
    let onSelect: () -> Void
    let onEdit: () -> Void

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    private var displayName: String {
        CadenceTitleNormalization.display(item.name, fallback: CadenceTitleNormalization.defaultCompactTitle)
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if style == .expanded {
                    expandedLabel
                }
            }
            // A list row, not a nav row: `listRowHeight`, not `buttonHeight` (T-3072). The height
            // is still fixed and still the whole hit region — the row keeps one shape for its
            // selection fill, its `contentShape` and its `+`-drop frame, so nothing here is sized
            // against something else that would now disagree.
            .frame(height: iOSSidebarMetrics.listRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
            .contentShape(rowShape)
        }
        .buttonStyle(.iosPressable)
        // The touch equivalent of macOS's right-click-to-edit on the same row. Not `.swipeActions`:
        // that modifier does nothing outside a `List`, and this region is a `ScrollView`.
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit \(item.kind == .area ? "Area" : "Project")", systemImage: "pencil")
            }
        }
        .accessibilityLabel(displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var expandedLabel: some View {
        HStack(spacing: iOSSidebarMetrics.listTrailingItemSpacing) {
            Text(displayName)
                .font(.system(size: iOSSidebarMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: iOSSidebarMetrics.badgeLeadingGap)

            if let dueDateKey = item.dueDateKey {
                dueDateBadge(dueDateKey)
            }

            if let count = CadenceSidebarLayout.listCount(openTaskCount: item.openTaskCount) {
                CadenceSidebarCountLabel(count: count)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
    }

    /// Bare tinted text rather than a filled pill: as a capsule this annotation carried more weight
    /// than the list name it annotates. Read-only here — the date is set in the list editor, which
    /// the row's own context menu opens.
    private func dueDateBadge(_ key: String) -> some View {
        HStack(spacing: iOSSidebarMetrics.listDueDateSpacing) {
            Image(systemName: "flag.fill")
                .font(.system(size: iOSSidebarMetrics.listDueDateIconSize, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(DateFormatters.relativeDate(from: key))
                .font(.system(size: iOSSidebarMetrics.listDueDateFontSize, weight: .semibold))
                .foregroundStyle(key < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct iOSMissingListView: View {
    var body: some View {
        iOSEmptyPanel(
            systemImage: "questionmark.folder",
            title: CadenceEmptyStateCopy.missingListTitle,
            subtitle: CadenceEmptyStateCopy.missingListSubtitle
        )
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

#if os(iOS)
import SwiftData
import SwiftUI

/// The Tasks tab: an **index** of everywhere work lives, over one header carrying the day.
///
/// *"i think the page on the iphone 'tasks' icon from the nav bar should behave more like this
/// page from 'Things 3' … where you see all the lists and you can go into each list, then you can
/// also go to different views that we have, such as inbox and today and all tasks"* (T-2072). The
/// views are rows — Today, Tasks, Inbox — and the lists are under them, and every one of them
/// pushes.
///
/// **The segmented switcher is gone.** It was Today / All / Inbox, a three-segment spelling that
/// existed on this screen and nowhere else: macOS and iPad have *two* (`CadenceTasksPageScope`)
/// with Today as its own sidebar row. A switcher also has a fixed capacity — three slices and no
/// room for a list — so the lists were reachable only through More → Lists, two taps away from the
/// tab named after them. Rows have no such ceiling, which is the whole reason the owner asked for
/// this shape.
///
/// **It is the sidebar's rows, not a second set.** The destination rows come from
/// `CadenceCompactTab.tasksIndexDestinations(storedOrder:hidden:)`, which resolves them through
/// `CadenceSidebarLayout` so the synced hidden set and the user's order apply here too (T-1274);
/// the lists come from `CadenceSidebarLists.sections(contexts:items:)` and are drawn by
/// `iOSSidebarListsRegion`, the same view the iPad column draws. Nothing about the iPad or macOS
/// sidebar changes.
///
/// **The index is not a fifth tab.** It lives inside the Tasks tab, under the four-tab bar, which
/// is what three rounds of deleted Home-screen mocks bought.
///
/// The title is the greeting rather than the word "Tasks". The bar below already says Tasks and
/// the index itself names Today, Tasks, Inbox and every list; a page title would be the third
/// restatement.
struct iOSTasksTabView: View {
    /// Which slice the index last opened. The switcher that used to write it is gone, but the
    /// value is not dead: `CadenceShellNavigationBridge` reads it when the shell widens with
    /// nothing pushed, so an iPhone that was last in the Inbox widens into the Inbox rather than
    /// into a fixed guess (T-334).
    @Binding var section: CadenceTasksSection
    @Binding var path: NavigationPath

    @Query(sort: \Context.order) private var contexts: [Context]
    // No task `@Query` here (T-3156): the counts beside Today and Tasks are read over every task,
    // and this body re-runs whenever the shell hands it fresh `section` / `path` bindings — once
    // each way per New task sheet. `iOSTasksIndexDestinationRows` owns that fetch and its counting.
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// The same request the iPad column hands its shell, and the same reason for it being one
    /// value: this index draws `iOSSidebarListsRegion` too, so its `+` seeds a context the same
    /// way or it seeds nothing.
    @State private var editorRequest: iOSSidebarListEditorRequest?
    /// The day this index is drawn for ([[T-5011]]): the Today row's overdue count, the list rows'
    /// due-date flags and the header's date all read it. Every one of them has inputs that are the
    /// same on both sides of midnight, and the count sits behind `.equatable()` besides, so without
    /// a day in their inputs a phone left on this tab kept yesterday's count and date.
    @State private var observedDay = CadenceObservedDay()

    /// The column vocabulary, which since T-3079 is the only one `iOSSidebarStyle` has.
    private let style: iOSSidebarStyle = .expanded

    var body: some View {
        VStack(spacing: 0) {
            // Argument label rather than a trailing closure, deliberately. This body's first
            // drawing is pinned by name, and the guard that pins it looks for the call's opening
            // parenthesis — a trailing closure leaves none to find, which is how it went red.
            iOSTasksTabHeader(todayKey: observedDay.todayKey, onSearch: {
                path.append(CadenceFeatureDestination.search)
            })

            Divider().background(Theme.borderSubtle)

            index
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .cadenceScaledTypography()
        .iOSHidesCompactNavigationBar()
        .sheet(item: $editorRequest) { request in
            iOSListEditorSheet(mode: request.mode, seededContext: request.seededContext)
                .cadenceFixedTypography()
        }
        // **Mandatory, and silent when it is missing.** A `NavigationPath` push of a type the
        // stack has not registered is discarded with no warning and no push — which is exactly
        // what made every row on the Lists page dead on iPhone. `iOSCompactTabShell` registers
        // `CadenceFeatureDestination` for all four stacks; the list rows below push an
        // `iOSListRoute`, so this stack has to register that too.
        //
        // One registration per type per stack: `iOSListsView` registers `iOSListRoute` as well,
        // but it is the More tab's push and the two stacks are separate. Nothing appends `.lists`
        // to this path — its `compactTab` is `.more` — so the two cannot meet.
        .navigationDestination(for: iOSListRoute.self) { route in
            listDetail(for: route)
        }
        .cadenceTracksDayChanges($observedDay)
    }

    // MARK: - The index

    /// Destination rows, a rule, then the lists.
    ///
    /// The rows are **outside** the scroll view on purpose. `iOSSidebarListsRegion` is a
    /// `ScrollView` of its own — it is the iPad column's scrolling region and this screen reuses it
    /// rather than re-spelling it — and three 44pt rows under a header leave the lists the rest of
    /// the screen. Pinning them also means the three task surfaces never scroll away, which on a
    /// phone is worth more than one continuous scroll.
    private var index: some View {
        let todayKey = observedDay.todayKey

        return VStack(alignment: .leading, spacing: 0) {
            // `.equatable()` is what makes the move pay: the row block's only input that SwiftUI
            // cannot compare is `onOpen`, a fresh closure on every pass of this body, and a child
            // handed one re-runs with its parent. Its `==` ignores the closure, so a pass here
            // leaves the whole-store count alone; the block still re-runs when its own `@Query` or
            // preference changes — or when the day turns, which is why `todayKey` is in its `==`.
            iOSTasksIndexDestinationRows(style: style, todayKey: todayKey, onOpen: open)
                .equatable()

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)

            iOSSidebarListsRegion(
                sections: listSections,
                style: style,
                todayKey: todayKey,
                // Same reason as above: a pushed list is not a selection.
                isSelected: { _ in false },
                onSelect: { path.append(route(for: $0)) },
                onEdit: { item in
                    if let mode = listEditorMode(for: item) {
                        editorRequest = iOSSidebarListEditorRequest(mode: mode)
                    }
                },
                // The phone reaches Lists through the More tab rather than through a row in this
                // index, so this `+` is a second door here and the only one on iPad. It is drawn
                // from the same view either way: one region, one create affordance, one spelling.
                onCreateList: { contextID in
                    editorRequest = iOSSidebarListEditorRequest(
                        mode: .newArea,
                        seededContext: contextID.flatMap { id in contexts.first { $0.id == id } }
                    )
                }
            )
        }
    }

    /// Push, and record which slice we went to — see `section`.
    private func open(_ destination: CadenceFeatureDestination) {
        if let slice = destination.compactTasksSection {
            section = slice
        }
        path.append(destination)
    }

    // MARK: - Lists

    private var listSections: [CadenceSidebarLists.Section] {
        CadenceSidebarLists.sections(
            contexts: contexts.filter { !$0.isArchived }.map {
                CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name)
            },
            // Closures rather than `map(Item.init)`: an unapplied initializer reference is
            // resolved in a nonisolated context, and these read SwiftData relationships.
            items: areas.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
                + projects.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
        )
    }

    private func route(for item: CadenceSidebarLists.Item) -> iOSListRoute {
        switch item.kind {
        case .area: return .area(item.id)
        case .project: return .project(item.id)
        }
    }

    private func listEditorMode(for item: CadenceSidebarLists.Item) -> iOSListEditorMode? {
        switch item.kind {
        case .area:
            return areas.first { $0.id == item.id }.map(iOSListEditorMode.editArea)
        case .project:
            return projects.first { $0.id == item.id }.map(iOSListEditorMode.editProject)
        }
    }

    /// The same two-case switch `iOSListsView` pushes, because a list opened from this index is the
    /// same screen as one opened from the Lists page — and a list deleted on another device while
    /// its detail is on the stack has to land on `iOSMissingListView` rather than on nothing.
    @ViewBuilder
    private func listDetail(for route: iOSListRoute) -> some View {
        switch route {
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(area: area)
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(project: project)
            } else {
                iOSMissingListView()
            }
        }
    }
}

/// The index's destination rows — Today, Tasks, Inbox — with their counts and tints (T-3156).
///
/// **This is the only view on the Tasks tab that fetches every task.** The counts are O(n) over the
/// store, and they used to be computed in `iOSTasksTabView.body`, which re-runs once each way
/// whenever the New task sheet is presented over the index or anything pushed on it: the shell
/// rebuilds its `section` and `path` bindings from `Binding(get:set:)` closures on every pass, and
/// SwiftUI cannot compare closure-backed bindings, so `Self._printChanges()` names them as changed
/// although their values are not. That shell is not this file's to change, so the fetch moved
/// here instead, behind an `==` that a parent pass cannot fail.
///
/// `onOpen` is excluded from `==` on purpose. It only appends to the tab's path binding and writes
/// its section binding, both of which address state that outlives any one pass of the parent, so a
/// closure kept from an earlier pass reaches the same storage as a fresh one.
private struct iOSTasksIndexDestinationRows: View, Equatable {
    let style: iOSSidebarStyle
    /// The tab's observed day ([[T-5011]]). Compared in `==`: it is the one input that changes at
    /// midnight, and leaving it out kept yesterday's overdue count until a task was edited.
    let todayKey: String
    let onOpen: (CadenceFeatureDestination) -> Void

    @Query private var allTasks: [AppTask]
    /// The synced sidebar layout, read for exactly the reason the iPad column reads it: this index
    /// draws the same rows, so a row hidden on another device has to be hidden here.
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]
    /// The same preference macOS's Settings → Sidebar colour picker writes, so a retinted Today is
    /// retinted on the phone too.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style && lhs.todayKey == rhs.todayKey
    }

    var body: some View {
        let counts = countInputs

        VStack(alignment: .leading, spacing: iOSSidebarMetrics.rowSpacing) {
            ForEach(destinationRows) { destination in
                iOSSidebarButton(
                    title: CadenceSidebarLayout.rowTitle(for: destination),
                    systemImage: destination.systemImage,
                    tint: tint(for: destination),
                    count: CadenceSidebarLayout.count(for: destination, counts: counts),
                    // Nothing is ever "selected" here: this is an index of places to go, and
                    // the place you went is on top of the stack rather than highlighted
                    // underneath it.
                    isSelected: false,
                    style: style
                ) {
                    onOpen(destination)
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.top, iOSSidebarMetrics.groupSpacing)
        .padding(.bottom, iOSSidebarMetrics.groupSpacing)
    }

    /// The rows this index lists, with the user's synced sidebar layout applied.
    private var destinationRows: [CadenceFeatureDestination] {
        let layout = CadenceSidebarLayoutPreferenceStore.layout(from: sidebarLayoutPreferences)
        return CadenceCompactTab.tasksIndexDestinations(
            storedOrder: layout.order,
            hidden: layout.hidden
        )
    }

    /// Built once per render and handed to every row, the shape `iOSSidebar` and `SidebarView`
    /// both use.
    private var countInputs: CadenceSidebarCountInputs {
        CadenceSidebarCountInputs(
            todayOverdueCount: CadenceSidebarLayout.overdueTaskCount(
                from: allTasks,
                todayKey: todayKey
            ),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(
                from: allTasks.filter(\.isInActiveContainer)
            )
        )
    }

    private func tint(for destination: CadenceFeatureDestination) -> Color {
        let overrides = CadenceSidebarTint.overrides(from: sidebarTabColorsRaw)
        return Color(hex: overrides[destination] ?? destination.defaultColorHex)
    }
}

/// The tab's own header row.
///
/// The row **is** `iOSPageHeader`, at `.page` role. It used to re-spell that vocabulary by hand — a
/// 10pt uppercase kerned eyebrow over a 26pt bold title, with its own `Spacer(minLength: 8)` before
/// a trailing control — which are the header's exact compact `.page` figures, arrived at
/// independently. It survived the pass that collapsed six of these into one because it is
/// compact-only and so is not an iPhone-against-iPad divergence; being the *seventh* copy of a
/// vocabulary is what makes it worth closing anyway, since six copies is what a seventh becomes.
///
/// The eyebrow and title are the greeting and the date rather than the word "Tasks": the index
/// below already names Today, Tasks, Inbox and every list, and the tab bar below that already says
/// Tasks. They are also the two things this screen does not otherwise state — and they are what the
/// deleted Home screen opened with.
///
/// **It carries one row now, not two.** The segmented switcher that used to sit under the header
/// went with T-2072; its three slices are rows in the index.
private struct iOSTasksTabHeader: View {
    /// The tab's observed day, so the date eyebrow turns at midnight ([[T-5011]]).
    let todayKey: String
    let onSearch: () -> Void

    /// The greeting is hour-based, so a day key cannot keep it fresh: it reads the date of a
    /// coarse `TimelineView(.everyMinute)` instead of a one-shot `Date()`, which froze it at the
    /// last re-render ("Good morning" into the afternoon, [[T-5020]]). The schedule is
    /// minute-aligned, so a 5/12/17 boundary shows within a minute, and a timeline re-evaluates on
    /// return from the background, so activation needs no hook of its own.
    var body: some View {
        TimelineView(.everyMinute) { context in
            iOSPageHeader(
                eyebrow: CadenceCompactShellSupport.dateEyebrow(for: DateFormatters.date(from: todayKey) ?? Date()),
                title: CadenceCompactShellSupport.greeting(for: context.date)
            ) {
                iOSIconButton(
                    systemImage: "magnifyingglass",
                    accessibilityLabel: "Search",
                    plateSize: 38,
                    iconSize: 14,
                    action: onSearch
                )
            }
        }
    }
}
#endif

#if os(iOS)
import SwiftData
import SwiftUI

enum iOSSidebarItem: Hashable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits
    case notes
    case lists
    case search
    case settings
    case area(UUID)
    case project(UUID)
}

struct iOSRootView: View {
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    /// T-266. "Focus this" from a task row or a block sheet lands here as a `CadenceFocusHandoff`;
    /// this view is the only thing that can answer it, because navigation state lives here.
    @Environment(CadenceFocusHandoffCenter.self) private var focusHandoffCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Read for exactly one thing: resolving a `.task` deep link to a real row before navigating.
    /// A fetch by id, not a `@Query` — nothing here observes tasks.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasksForNotifications: [AppTask]
    @Query private var allHabitsForNotifications: [Habit]
    @State private var selection: iOSSidebarItem? = .today
    /// One `NavigationPath` per compact tab, so switching tabs preserves where you were. Each is
    /// type-erased — see `iOSCompactTabPaths`.
    @State private var compactPaths = iOSCompactTabPaths()
    /// Restored across launches, like `ios.calendar.anchorDateKey`.
    ///
    /// Written from exactly two places, both of them deliberate acts: a tap on a bar item, and a
    /// deep link (which is a tap on a widget or a URL). Nothing derived, nothing measured, nothing
    /// written during layout — that is the lesson of `ecaf80f`, where a persisted navigation value
    /// took an initial scroll reading for a user action and then compounded across launches.
    @AppStorage("ios.compact.selectedTab") private var selectedTabRaw = CadenceCompactTab.defaultTab.rawValue
    @AppStorage("ios.compact.tasksSection") private var tasksSectionRaw = CadenceTasksSection.defaultSection.rawValue
    /// The feature screen sitting on each tab's stack, mirrored here because `NavigationPath` can
    /// be replaced and counted but never read back. Only the size-class bridge consults it; see
    /// `iOSCompactRootShell.onFeatureDestinationAppear`.
    @State private var compactPushedFeature: [CadenceCompactTab: CadenceFeatureDestination] = [:]

    private var selectedTab: CadenceCompactTab {
        CadenceCompactTab.resolved(selectedTabRaw)
    }

    private var tasksSection: CadenceTasksSection {
        CadenceTasksSection.resolved(tasksSectionRaw)
    }

    /// The mirrored push, but only while the selected tab's stack is actually holding something.
    /// A tab popped back to its root keeps its last recorded value, and a count of zero is the one
    /// signal available that the value has been left behind.
    private var compactPushedDestination: CadenceFeatureDestination? {
        guard compactPaths[selectedTab].count > 0 else { return nil }
        return compactPushedFeature[selectedTab]
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadMacStyleRootShell(selection: $selection) {
                    detailView(for: selection ?? .today)
                }
            } else {
                iOSCompactRootShell(
                    selectedTab: Binding(
                        get: { selectedTab },
                        set: { selectedTabRaw = $0.rawValue }
                    ),
                    tasksSection: Binding(
                        get: { tasksSection },
                        set: { tasksSectionRaw = $0.rawValue }
                    ),
                    paths: $compactPaths,
                    onFeatureDestinationAppear: { tab, destination in
                        compactPushedFeature[tab] = destination
                    }
                )
            }
        }
        // Both shells, one call. A banner that only appeared on the iPad sidebar shell would
        // recreate the macOS/iOS asymmetry it exists to close, one level down.
        .cadenceStartupIssueBanner(PersistenceController.startupIssue)
        // T-201, and the same "both shells, one call" reasoning. The task inspector used to be
        // presented by the row that opened it, so any status write that moved the task out of its
        // section took the row down and the panel with it. Presented here, its lifetime is the
        // shell's: nothing a page's own query does can reach it. One host rather than one per page
        // because a page that forgets is a page where tapping a row does nothing — and every route
        // into this UI passes through here. A sheet that grows task rows of its own needs a nearer
        // host, since a host that is already presenting cannot present again; `iOSTaskInspectorHost`
        // records which surfaces that applies to.
        .iOSTaskInspectorHost()
        // T-217, the same shape one subject over. `iOSCalendarBundleDetailSheet` was presented by
        // the bundle card and the timeline bundle block, both of which sit in a `ForEach(bundles)`
        // filtered by day — and by hour on Today's schedule pane — so the panel's own Save tore it
        // down exactly when a re-date or a re-time succeeded. A separate host rather than a shared
        // one because it presents a different sheet on a different model; the *decision* about when
        // a held model is gone is shared, in `CadenceDetailPanelPresentation`.
        .iOSBundleInspectorHost()
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .statusBarHidden(horizontalSizeClass == .regular)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            handleDeepLinkRoute()
        }
        // T-334. Split View and Stage Manager make the regular/compact switch an ordinary gesture,
        // and until this existed it was the one navigation event that carried nothing across: the
        // shell the user was *not* looking at kept whatever it was last told, so Calendar on iPad
        // narrowed into a stale Tasks and compact Calendar widened back into a stale Today. Deep
        // links and the Focus handoff had always written both shells; plain navigation never did.
        //
        // Bridged here rather than on every selection write because this is the only moment the
        // two stores are asked to agree, and because a bridge on each write is two properties
        // observing each other — the shape that turns one tap into a loop.
        .onChange(of: horizontalSizeClass) { previous, sizeClass in
            // `nil -> something` is the shell being told its width for the first time, not a
            // resize, and there is nothing to carry across it. Bridging there would read the
            // sidebar's `@State` default of Today against a *restored* `ios.compact.selectedTab`,
            // decide they disagree, and write the default over the restored tab — a launch that
            // silently forgets which tab you left the app on.
            guard previous != nil else { return }
            bridgeNavigation(to: sizeClass)
        }
        // The shell navigates; the Focus screen adopts. Split that way because they are two
        // different pieces of knowledge — which tab owns Focus, and what happens to the session
        // already on the clock — and only one of them belongs to a root view.
        .onChange(of: focusHandoffCenter.pending?.id) { _, pending in
            guard pending != nil else { return }
            routeToFocus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                CadenceWidgetRefreshCenter.reloadAllWidgets()
            }
            // Both directions reconcile, and they reconcile for different reasons. Leaving active
            // sweeps up what this process just changed. *Becoming* active is the only checkpoint
            // iOS has for a write another process made while the app was away: a widget button or
            // a Siri phrase runs `CompleteTaskIntent` / `CaptureTaskIntent` /
            // `ToggleHabitCompletionIntent` inside the extension, which posts
            // `CadenceStoreSupport.postExternalWrite` and deliberately does **not** reconcile
            // there — its `UserDefaults.standard` is not the app's, so it cannot read
            // `notificationsEnabled` and must not decide. Without this arm a task completed from
            // the home screen keeps its pending reminder until something unrelated backgrounds the
            // app. `docs/TODO.md` T-312, and T-306 for the macOS half of the same contract.
            let tasks = allTasksForNotifications
            let habits = allHabitsForNotifications
            Task { await NotificationManager.shared.reconcile(tasks: tasks, habits: habits) }
        }
    }

    @ViewBuilder
    private func detailView(for item: iOSSidebarItem) -> some View {
        switch item {
        case .today:
            iPadTodayView()
        // One branch, one view: All Tasks and Inbox are two views of one page now, and separate
        // `switch` arms would give SwiftUI two identities and reset the page every time something
        // navigated between them.
        case .allTasks, .inbox:
            iOSTasksPageView(requestedScope: item == .inbox ? .inbox : nil)
        case .focus:
            iOSFocusView()
        case .calendar:
            iOSCalendarView()
        case .goals:
            iOSGoalsView()
        case .habits:
            iOSHabitsView()
        case .notes:
            NavigationStack {
                iOSNotesView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .lists:
            NavigationStack {
                iOSListsView()
            }
        case .search:
            NavigationStack {
                iOSSearchView()
            }
        case .settings:
            iOSSettingsView()
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

private extension iOSRootView {
    /// One route, resolved once, applied to both shells.
    ///
    /// The compact half is the part that changed shape: a link used to be a push onto the single
    /// stack, and now it has to answer *which tab* first. `CadenceCompactRoute` (in `Shared/`, with
    /// tests) is where that answer lives, so a widget tap cannot land on the wrong tab without a
    /// test failing.
    func handleDeepLinkRoute() {
        guard let deepLink = deepLinkManager.route?.deepLink else { return }
        // Not `deepLink.featureDestination`: a `.task` link has to be resolved against the store
        // first, because Today's scope is narrower than "any task" and the id it arms has no owner
        // outside a rendered row. `CadenceDeepLinkResolutionSupport` holds that decision, in
        // `Shared/` where `CadenceTests` can reach it.
        let destination = deepLinkManager.resolvedDestination(
            for: deepLink,
            modelContext: modelContext
        )
        selection = destination.item
        apply(destination.compactRoute)
    }

    /// Show the Focus screen on whichever shell is up, without disturbing a Focus screen already
    /// standing.
    ///
    /// The route comes from `CadenceCompactRoute` rather than being spelled here, so "the More tab,
    /// pushed" has one source and stays true if Focus ever moves. The equality guard is the part
    /// that is not decoration: replacing the stack with an equal-valued `NavigationPath` while the
    /// user is *on* Focus risks handing SwiftUI a fresh view identity, and a fresh `iOSFocusView`
    /// is a fresh `@State` clock — the running session would vanish at the exact moment the
    /// handoff was meant to be banked into it.
    func routeToFocus() {
        let route = CadenceFocusHandoff.destination.compactRoute
        selection = CadenceFocusHandoff.destination.item
        selectedTabRaw = route.tab.rawValue
        compactPushedFeature[route.tab] = route.pushedDestination
        let path = route.pushedDestination.map { NavigationPath([$0]) } ?? NavigationPath()
        if compactPaths[route.tab] != path {
            compactPaths[route.tab] = path
        }
    }

    /// Carry the selection from the shell that is going away into the one that is arriving.
    ///
    /// Only ever writes the *arriving* shell's store, and only when it disagrees. The compact
    /// stack is left alone when both shells already name the same feature, so narrowing while the
    /// sidebar is on a project lands on Lists without flattening a list detail you were already
    /// inside.
    func bridgeNavigation(to sizeClass: UserInterfaceSizeClass?) {
        if sizeClass == .regular {
            guard let destination = CadenceShellNavigationBridge.visibleDestination(
                tab: selectedTab,
                tasksSection: tasksSection,
                pushedDestination: compactPushedDestination
            ) else { return }
            let item = destination.item
            if selection != item {
                selection = item
            }
        } else {
            guard let destination = (selection ?? .today).featureDestination else { return }
            let showing = CadenceShellNavigationBridge.visibleDestination(
                tab: selectedTab,
                tasksSection: tasksSection,
                pushedDestination: compactPushedDestination
            )
            guard showing != destination else { return }
            apply(destination.compactRoute)
        }
    }

    /// Only the target tab's stack is touched. Pushing onto — or clearing — a tab the link did not
    /// name would quietly rearrange a screen the user is not looking at and will come back to.
    func apply(_ route: CadenceCompactRoute) {
        selectedTabRaw = route.tab.rawValue
        if let section = route.tasksSection {
            tasksSectionRaw = section.rawValue
        }
        compactPushedFeature[route.tab] = route.pushedDestination
        compactPaths[route.tab] = route.pushedDestination.map { NavigationPath([$0]) } ?? NavigationPath()
    }
}
#endif

#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListRoute: Hashable {
    case area(UUID)
    case project(UUID)
}

struct iOSListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var editorMode: iOSListEditorMode?
    @State private var selectedRoute: iOSListRoute?
    @State private var pendingDeletion: iOSListDeletionTarget?
    /// Set only when `CadenceContainerWindDownSummary.requiresConfirmation` says the wind-down
    /// would settle something. See `requestWindDown`.
    @State private var pendingWindDown: iOSListWindDownTarget?

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var archivedAreas: [Area] {
        areas.filter(\.isArchived)
    }

    private var archivedProjects: [Project] {
        projects.filter(\.isArchived)
    }

    /// **The one predicate that decides whether Archived exists on this screen** (T-526).
    ///
    /// Read by `archivedSection`, which draws it, *and* by `emptyStateSection`, whose subtitle
    /// used to offer "restore one from Archived" unconditionally. Held once rather than spelled at
    /// both sites: two copies of this expression is exactly how the sentence and the section came
    /// to disagree in the first place.
    private var hasArchivedLists: Bool {
        !archivedAreas.isEmpty || !archivedProjects.isEmpty
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var firstActiveRoute: iOSListRoute? {
        if let area = activeAreas.first {
            return .area(area.id)
        }
        if let project = activeProjects.first {
            return .project(project.id)
        }
        return nil
    }

    private var effectiveSelectedRoute: iOSListRoute? {
        guard let selectedRoute, containsActive(route: selectedRoute) else {
            return firstActiveRoute
        }
        return selectedRoute
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularSplitLayout
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Theme.bg)
        .sheet(item: $editorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
        .iOSListDeletion(target: $pendingDeletion)
        .iOSListWindDown(target: $pendingWindDown)
        .navigationDestination(for: iOSListRoute.self) { route in
            listDetail(for: route)
        }
        .onAppear(perform: selectDefaultListIfNeeded)
        .onChange(of: activeRouteKey) { _, _ in
            selectDefaultListIfNeeded()
        }
    }

    private var compactLayout: some View {
        oneColumnLayout(showsBack: true)
    }

    /// The same one column at regular width, where `CadenceRegularSplitLayout` has decided the pane
    /// cannot pay for two — and where this page is the sidebar's selection rather than a push, so
    /// there is nothing behind it for a chevron to return to.
    private var narrowLayout: some View {
        oneColumnLayout(showsBack: false)
    }

    private func oneColumnLayout(showsBack: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The nav bar above is hidden (see `.toolbar(.hidden…)` on the body), which is what
            // left iPhone with no way back other than the swipe gesture. The chevron lives here.
            iOSListsPageHeader(
                areaCount: activeAreas.count,
                projectCount: activeProjects.count,
                onBack: showsBack ? { dismiss() } : nil
            )

            iOSListCreateButtonsRow(editorMode: $editorMode)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            iOSListHairline()

            compactList
        }
        .background(Theme.bg)
    }

    /// `.plain` with the palette showing through, not the default inset-grouped `List`: grouped
    /// style paints its own `secondarySystemGroupedBackground` plates and its own grey headers,
    /// which is a second, non-palette surface stacked on the page background.
    private var compactList: some View {
        List {
            activeAreaSection
            activeProjectSection
            archivedSection
            emptyStateSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }

    /// The same `CadenceRegularSplitLayout` proportion Goals, Habits and Focus use. It used to be
    /// `minWidth: 300, idealWidth: 340, maxWidth: 380` here — the only one of the four surfaces that
    /// declared a maximum at all, and the reason this page was the least starved of them. Measuring
    /// against the pane rather than declaring a range is what keeps an 11" iPad's 632pt from landing
    /// on a 315pt chooser beside a 316pt list.
    private var regularSplitLayout: some View {
        iOSFeatureSplitLayout {
            iOSListsRegularPane(
                activeAreas: activeAreas,
                activeProjects: activeProjects,
                archivedAreas: archivedAreas,
                archivedProjects: archivedProjects,
                selectedRoute: $selectedRoute,
                editorMode: $editorMode,
                projectSubtitle: projectSubtitle,
                archiveArea: archive,
                archiveProject: archive,
                completeArea: complete,
                completeProject: complete,
                restoreArea: restore,
                restoreProject: restore,
                requestDeletion: { pendingDeletion = $0 }
            )
        } detail: {
            if let route = effectiveSelectedRoute {
                listDetail(for: route)
                    .id(route)
            } else {
                iOSEmptyPanel(
                    systemImage: "folder",
                    title: "Nothing to show yet",
                    subtitle: "Once you add an area or project, it'll open here."
                )
                .background(Theme.bg)
            }
        } narrow: {
            narrowLayout
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var activeAreaSection: some View {
        if !activeAreas.isEmpty {
            Section {
                ForEach(activeAreas) { area in
                    areaRow(area)
                }
            } header: {
                iOSListSectionHeader(title: "Areas")
            }
        }
    }

    private func areaRow(_ area: Area) -> some View {
        NavigationLink(value: iOSListRoute.area(area.id)) {
            iOSListPickerRow(
                title: area.name,
                subtitle: area.context?.name,
                icon: area.icon,
                colorHex: area.colorHex,
                count: CadenceTaskQuerySupport.openTaskCount(for: area)
            )
        }
        .iOSListRowChrome()
        .contextMenu {
            Button {
                editorMode = .editArea(area)
            } label: {
                Label("Edit Area", systemImage: "square.and.pencil")
            }

            completeAreaButton(area)

            archiveAreaButton(area, title: "Archive Area")

            iOSListDeleteMenuButton(target: .area(area)) { pendingDeletion = $0 }
        }
        // Not `.swipeActions`: the iPad pane draws the same row in a `ScrollView`, where SwiftUI
        // drops that modifier. See `iOSListRowSwipeActions`.
        .iOSSwipeActions(trailing: iOSListRowSwipeActions.archive { archive(area) })
    }

    @ViewBuilder
    private var activeProjectSection: some View {
        if !activeProjects.isEmpty {
            Section {
                ForEach(activeProjects) { project in
                    projectRow(project)
                }
            } header: {
                iOSListSectionHeader(title: "Projects")
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: iOSListRoute.project(project.id)) {
            iOSListPickerRow(
                title: project.name,
                subtitle: projectSubtitle(project),
                icon: project.icon,
                colorHex: project.colorHex,
                count: CadenceTaskQuerySupport.openTaskCount(for: project)
            )
        }
        .iOSListRowChrome()
        .contextMenu {
            Button {
                editorMode = .editProject(project)
            } label: {
                Label("Edit Project", systemImage: "square.and.pencil")
            }

            completeProjectButton(project)

            archiveProjectButton(project, title: "Archive Project")

            iOSListDeleteMenuButton(target: .project(project)) { pendingDeletion = $0 }
        }
        .iOSSwipeActions(trailing: iOSListRowSwipeActions.archive { archive(project) })
    }

    @ViewBuilder
    private var archivedSection: some View {
        if hasArchivedLists {
            Section {
                ForEach(archivedAreas) { area in
                    archivedAreaRow(area)
                }

                ForEach(archivedProjects) { project in
                    archivedProjectRow(project)
                }
            } header: {
                iOSListSectionHeader(title: "Archived")
            }
        }
    }

    private func archivedAreaRow(_ area: Area) -> some View {
        iOSArchivedListRow(
            title: area.name,
            subtitle: area.context?.name,
            icon: area.icon,
            colorHex: area.colorHex
        ) {
            restore(area)
        }
        .iOSListRowChrome()
    }

    private func archivedProjectRow(_ project: Project) -> some View {
        iOSArchivedListRow(
            title: project.name,
            subtitle: projectSubtitle(project),
            icon: project.icon,
            colorHex: project.colorHex
        ) {
            restore(project)
        }
        .iOSListRowChrome()
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if activeAreas.isEmpty && activeProjects.isEmpty {
            iOSEmptyPanel(
                systemImage: "folder",
                title: CadenceEmptyStateCopy.activeListsTitle,
                subtitle: CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: hasArchivedLists)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func archiveAreaButton(_ area: Area, title: String = "Archive") -> some View {
        Button(role: .destructive) {
            archive(area)
        } label: {
            Label(title, systemImage: "archivebox")
        }
    }

    private func archiveProjectButton(_ project: Project, title: String = "Archive") -> some View {
        Button(role: .destructive) {
            archive(project)
        } label: {
            Label(title, systemImage: "archivebox")
        }
    }

    /// Completion is offered in the **context menu only**, never on the row swipe, and the swipe
    /// keeps carrying Archive alone. Not squeamishness: a swipe is one flick with no second beat to
    /// read anything in, and the conditional confirmation deliberately does not appear for a list
    /// with nothing open — so a two-action swipe would put "mark this list finished" one
    /// mis-flick away from "file it away", on a control where the only difference is how far your
    /// thumb travelled. A long-press names both actions before either can be chosen.
    ///
    /// Not `role: .destructive` either, for the same reason the confirmation's button is not:
    /// finishing work is not destruction, and a red "Complete Area" would be the control lying
    /// about what it does. `iOSWindDownConfirmationSheet` derives its own colour from the outcome.
    private func completeAreaButton(_ area: Area) -> some View {
        Button {
            complete(area)
        } label: {
            Label("Complete Area", systemImage: iOSListWindDownAction.complete.icon)
        }
    }

    private func completeProjectButton(_ project: Project) -> some View {
        Button {
            complete(project)
        } label: {
            Label("Complete Project", systemImage: iOSListWindDownAction.complete.icon)
        }
    }

    private func projectSubtitle(_ project: Project) -> String {
        [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / ")
    }

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

    private var activeRouteKey: String {
        let areaIDs = activeAreas.map { "a:\($0.id.uuidString)" }
        let projectIDs = activeProjects.map { "p:\($0.id.uuidString)" }
        return (areaIDs + projectIDs).joined(separator: "|")
    }

    private func containsActive(route: iOSListRoute) -> Bool {
        switch route {
        case .area(let id):
            return activeAreas.contains { $0.id == id }
        case .project(let id):
            return activeProjects.contains { $0.id == id }
        }
    }

    private func selectDefaultListIfNeeded() {
        if let selectedRoute, containsActive(route: selectedRoute) {
            return
        }
        selectedRoute = firstActiveRoute
    }

    /// The one list wind-down decision on iOS, for both directions and for both the iPhone list and
    /// the iPad pane.
    ///
    /// Archiving cancels the list's remaining active tasks and completing marks them done — macOS
    /// has done both all along, so T-215 and T-214 are iOS catching up rather than new behaviour.
    /// Either way the gesture settles work irreversibly, so it is confirmed *when there is something
    /// to settle* and performed immediately when there is not.
    ///
    /// **The conditional rule is deliberately the same for completion as for archive**, and the
    /// reason it is not a stronger bar is that `requiresConfirmation` is not a measure of how big a
    /// claim the action makes — it is a test of whether anything irreversible happens at all.
    /// Completing an empty list writes one `status` and settles nothing; friction there is friction
    /// people learn to dismiss without reading, which is what makes the *other* sheet worth
    /// stopping for. What completion does get is different copy: it settles as `.done`, which
    /// asserts the work happened and feeds every surface that counts finished work, and it files the
    /// list somewhere else. See `iOSListWindDownTarget.windDownSubject`.
    ///
    /// `CadenceContainerWindDownSummary.requiresConfirmation` owns the test and is asked here, once,
    /// so no surface can answer it differently.
    private func requestWindDown(_ target: iOSListWindDownTarget) {
        guard target.summary.requiresConfirmation else {
            modelContext.windDownList(target)
            return
        }
        pendingWindDown = target
    }

    private func archive(_ area: Area) {
        requestWindDown(.area(area, .archive))
    }

    private func archive(_ project: Project) {
        requestWindDown(.project(project, .archive))
    }

    private func complete(_ area: Area) {
        requestWindDown(.area(area, .complete))
    }

    private func complete(_ project: Project) {
        requestWindDown(.project(project, .complete))
    }

    private func restore(_ area: Area) {
        area.status = .active
        try? modelContext.save()
    }

    private func restore(_ project: Project) {
        project.status = .active
        try? modelContext.save()
    }
}
#endif

#if os(iOS)
import SwiftData
import SwiftUI

struct iOSListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    let area: Area?
    let project: Project?
    /// The column to bring into view on the Kanban page, and briefly ring. Set only by a caller
    /// that named one — Today's past-due **section** card is the only one so far. It stays a
    /// `let` rather than becoming `@State` because it is the request, not the board's own state;
    /// `iOSListKanbanPanel` owns the fade-out.
    let highlightedSectionName: String?
    /// Set when this page is *presented* rather than navigated to. The header's back control is
    /// otherwise compact-only, and correctly so: at regular width this view is a detail pane with
    /// nothing behind it. Inside a sheet there always is something behind it, on both widths, and a
    /// form sheet on iPad with no visible way out is the same class of defect as a chevron that
    /// looks wired and does nothing.
    let isPresentedModally: Bool
    @State private var editorMode: iOSListEditorMode?
    /// `nil` until the reader taps a tab — the page they see before that is the one they chose in
    /// Settings, read live rather than copied into `@State` in `onAppear`, so changing the
    /// preference does not need a relaunch to take effect and a stale copy cannot outlive it.
    ///
    /// A caller that opened this page *at* a particular tab seeds it here, which is why the seed is
    /// an `init` argument and not an `onAppear` write: the first render has to be the right page,
    /// or the board scroll below lands on a tab nobody is looking at.
    @State private var selectedPage: ListDetailPage?
    @AppStorage(CadencePreferenceKeys.listDetailDefaultPage) private var defaultPageRaw = ListDetailPage.defaultPage.rawValue

    init(
        area: Area,
        initialPage: ListDetailPage? = nil,
        highlightedSectionName: String? = nil,
        isPresentedModally: Bool = false
    ) {
        self.area = area
        self.project = nil
        self.highlightedSectionName = highlightedSectionName
        self.isPresentedModally = isPresentedModally
        _selectedPage = State(initialValue: initialPage)
    }

    init(
        project: Project,
        initialPage: ListDetailPage? = nil,
        highlightedSectionName: String? = nil,
        isPresentedModally: Bool = false
    ) {
        self.area = nil
        self.project = project
        self.highlightedSectionName = highlightedSectionName
        self.isPresentedModally = isPresentedModally
        _selectedPage = State(initialValue: initialPage)
    }

    private var title: String {
        area?.name ?? project?.name ?? "List"
    }

    private var subtitle: String {
        if let area {
            return area.context?.name ?? "Area"
        }
        if let project {
            return [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / ")
        }
        return ""
    }

    /// The tab on screen. The stored preference is resolved rather than force-unwrapped from its
    /// raw value: it can still read "Planning", a tab that no longer exists on either platform, and
    /// `ListDetailPage.resolved(_:)` lands that on Tasks instead of on nothing.
    private var page: ListDetailPage {
        selectedPage ?? ListDetailPage.resolved(defaultPageRaw)
    }

    private var pageBinding: Binding<ListDetailPage> {
        Binding(get: { page }, set: { selectedPage = $0 })
    }

    /// Which list this page is showing, as a value SwiftUI can compare across an update.
    private var containerIdentity: UUID? {
        area?.id ?? project?.id
    }

    /// The same list, in the form the task composer takes.
    private var containerSelection: TaskContainerSelection {
        if let area { return .area(area.id) }
        if let project { return .project(project.id) }
        return .inbox
    }

    private var colorHex: String {
        area?.colorHex ?? project?.colorHex ?? Theme.blueHex
    }

    private var accent: Color {
        Color(hex: colorHex)
    }

    private var sectionConfigs: [TaskSectionConfig] {
        area?.sectionConfigs ?? project?.sectionConfigs ?? []
    }

    /// Same fallback as macOS's `KanbanSectionColumnView.hideColumnDueDateIfEmpty`: with neither a
    /// list nor a project there is no flag to read, and a board with nothing to hide shows.
    private var hideSectionDueDateIfEmpty: Bool {
        if let area { return area.hideSectionDueDateIfEmpty }
        if let project { return project.hideSectionDueDateIfEmpty }
        return false
    }

    @AppStorage("ios.listDetail.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.listDetail.showCompleted") private var showCompleted = false

    /// Read-only: the picker writes `sortModeRaw` through its own `Binding(get:set:)` below. The
    /// setter this used to carry was uncallable — a `View`'s `body` cannot mutate `self`.
    private var sortMode: CadenceTaskSortMode {
        CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: filteredTasks,
            sortMode: sortMode,
            sectionNames: configuredSectionNames
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: filteredTasks)
    }

    private var filteredTasks: [AppTask] {
        CadenceTaskQuerySupport.tasks(for: area, project: project, in: allTasks)
    }

    private var configuredSectionNames: [String] {
        area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName]
    }

    private var sectionNames: [String] {
        var names = configuredSectionNames
        for task in activeTasks {
            let name = task.resolvedSectionName
            if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSListDetailHeader(
                eyebrow: subtitle.isEmpty ? (area == nil ? "Project" : "Area") : subtitle,
                title: title,
                colorHex: colorHex,
                onBack: (isPresentedModally || horizontalSizeClass == .compact) ? { dismiss() } : nil,
                onEdit: presentEditor
            )

            iOSListDetailPagePicker(
                page: pageBinding,
                counts: [
                    .tasks: activeTasks.count,
                    .kanban: activeTasks.count,
                    .completed: completedTasks.count
                ]
            )
                .padding(.horizontal, horizontalSizeClass == .regular ? 18 : 12)
                .padding(.bottom, 8)

            iOSListHairline()

            // The identity of the page is the list it belongs to, not just which tab is showing.
            //
            // On iPad this view is reached through a `@ViewBuilder switch` on the sidebar route,
            // which *updates* the subtree when you switch lists rather than rebuilding it — so
            // every panel's `@State` survived the switch. `iOSListNotesPanel` seeds its note in
            // `onAppear` and only there, so switching area A → B while the Notes tab was open left
            // you typing into A's note under B's header, and a task created from inside it landed
            // in B. `iOSListViews`' own split view already does this with `.id(route)`; this is the
            // same discipline applied where the panels live, so it holds for every host.
            pageBody
                .id(containerIdentity)
        }
        .background(Theme.bg.ignoresSafeArea())
        // Unseeded. It used to hand this page's list to the composer; T-337 moved that inheritance
        // to the drop — the list's own section headers, its kanban columns and its empty state are
        // all drop targets, and each seeds this container by name. That also retires the staleness
        // this comment used to warn about: with nothing captured at the button, switching lists in
        // the iPad sidebar has nothing left to leave pointing at the list you just left.
        .iOSFloatingCreateTaskButton()
        // The page carries its own header, so an empty inline nav title was the only thing keeping
        // the bar around — 44pt of chrome holding one chevron above a header that already named the
        // list. The chevron is in the header now and the bar is gone. On iPad this view is hosted
        // with no navigation stack at all, which is why the edit control had to move out of the
        // toolbar: as a `ToolbarItem` it had nowhere to render and the list editor was unreachable
        // from the detail pane.
        .iOSHidesCompactNavigationBar()
        .sheet(item: $editorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
    }

    private func presentEditor() {
        if let area {
            editorMode = .editArea(area)
        } else if let project {
            editorMode = .editProject(project)
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .tasks:
            taskColumn
        case .kanban:
            iOSListKanbanPanel(
                tasks: activeTasks,
                sectionNames: sectionNames,
                sectionConfigs: sectionConfigs,
                hideSectionDueDateIfEmpty: hideSectionDueDateIfEmpty,
                accent: accent,
                container: containerSelection,
                listName: title,
                highlightedSectionName: highlightedSectionName
            )
        case .documents:
            // `iOSListNotesView`, not the old `iOSListNotesPanel`: this list may hold many notes,
            // filed into folders on a Mac, and the panel showed exactly one of them at the root of
            // a filing system it could not draw. See T-193 and `CadenceNoteFolderPath`.
            iOSListNotesView(area: area, project: project)
        case .links:
            iOSListLinksPanel(area: area, project: project)
        case .completed:
            iOSListCompletedPanel(tasks: completedTasks)
        }
    }

    private var taskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if isTaskColumnEmpty {
                // The list itself is the only placement left when the page has neither rows nor
                // columns drawn to point at — the `.list` half of `groupIdentity`, and the same
                // move the Inbox's empty panel already makes. See `iOSTaskCollectionSections`.
                // Words shared with the Mac's `ListTasksView`. The subtitle used to say "Add a
                // task above", naming an inline field this page has never had — the affordance is
                // the floating `+` applied above — which is the exact mistake
                // `CadenceTodayPresentationSupport.emptySubtitle` already records having made.
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: CadenceEmptyStateCopy.listDetailTitle,
                    subtitle: CadenceEmptyStateCopy.listDetailSubtitle
                )
                .iOSNewTaskDropTarget(
                    group: CadenceTaskDropSupport.groupIdentity(
                        container: containerSelection,
                        listName: title
                    )
                )
            } else {
                sectionStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }

    private func sectionColor(for name: String) -> Color {
        guard let config = sectionConfigs.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            return Theme.dim
        }
        return config.isCompleted ? Theme.green : Color(hex: config.colorHex)
    }

    private var isTaskColumnEmpty: Bool {
        activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty)
    }

    /// **Every configured column, including the ones with nothing in them.** `sectionGroups`
    /// discards an empty section by default, which is right where a heading over no rows would say
    /// nothing — and wrong here, because this is a surface you can add to. An unfilled kanban
    /// column is the case `CadenceTaskDropSupport.showsWhenEmpty(_:)` was written for, and the rule
    /// could never fire on this page: the column was gone before `iOSTaskGroupSection` got to
    /// decide. The whole-page empty state above still wins over a stack of zeroes.
    private var sectionGroups: [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.sectionGroups(
            from: activeTasks,
            sectionNames: sectionNames,
            includingEmpty: true
        )
    }

    /// The Tasks tab's rows, on `iOSTaskGroupSection` — the same counted group Today, Inbox and All
    /// Tasks are built from.
    ///
    /// It used to be a `List` of `Section`s headed by a bare `iOSTaskSectionHeader`, which is why
    /// a section header on this page took no dropped `+`: the header was a label with nothing
    /// behind it, and the drop identity lives on the component. Moving onto the shared group also
    /// picks up its count badge, its uniform spacing, and its empty-group rule. What the `List`
    /// provided was already switched off or replaced app-wide — see `iOSTaskCollectionPage` for
    /// that accounting; the rows' swipe actions are `iOSSwipeActions`, which works in either host.
    private var sectionStack: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: iOSTaskCollectionMetrics.groupSpacing) {
                ForEach(sectionGroups) { group in
                    iOSTaskGroupSection(
                        title: group.title,
                        // Same colour the board's column dot takes, so a column is the same column
                        // whichever tab you are looking at it from.
                        color: sectionColor(for: group.title),
                        tasks: group.tasks,
                        // Scoped to one list already — the chip would name the page you are on.
                        showsContainer: false,
                        dropIdentity: CadenceTaskDropSupport.groupIdentity(
                            container: containerSelection,
                            listName: title,
                            sectionName: group.title
                        )
                    )
                }

                if showCompleted && !completedTasks.isEmpty {
                    // `.completion` resolves to no key: done-ness is not something a new task can
                    // be seeded with, so this header neither lights up nor survives emptying.
                    iOSTaskGroupSection(
                        title: "Completed",
                        color: Theme.green,
                        tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch),
                        showsContainer: false,
                        opacity: 0.62,
                        dropIdentity: .completion,
                        hiddenCount: CadenceTaskSurfaceOptions.hiddenCompletedCount(from: completedTasks, tier: .touch)
                    )
                }
            }
            // One gutter, not two (T-613). This was `.padding(12)` — the inset of the
            // `.cadenceCard()` `85809ff` deleted — *plus* the panel's own 12, so the section
            // headers and rows sat at 24 while the options bar directly above them sat at 16.
            .padding(.horizontal, iOSListDetailTaskMetrics.horizontalPadding)
            .padding(.bottom, iOSListDetailTaskMetrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
    }

}

/// The Tasks tab's gutters. Its own type rather than `iOSTaskCollectionMetrics`, whose numbers are
/// read off a page header this tab does not draw — the header and the tab picker are the page's,
/// above this panel. The group spacing is the collection page's, so the rows sit the same distance
/// apart wherever they are read.
///
/// **`cardPadding` is gone and the gutter is 16 (T-613).** There were two horizontal insets here,
/// 12 + 12: the panel's own, and the inset of a `.cadenceCard()` that `85809ff` deleted. The card
/// went and its 12 stayed, which put this tab's section headers 24pt in against an options bar and
/// a page header at 16 — the "header indented from the rows under it" defect
/// `CadencePageHeaderMetrics.horizontalPadding` keeps the desktop gutter at 18 to avoid, stated the
/// other way round. One inset now, and it is the 16 the bar above it already uses.
private enum iOSListDetailTaskMetrics {
    static let horizontalPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 16
}

/// The one place this page names itself: the back control on iPhone, the context path it lives
/// under, its name in the list's own colour, and the control that opens the list editor.
///
/// It replaces a `.navigationBarTitleDisplayMode(.large)` title *plus* a second `iOSPanelHeader`
/// inside the Tasks tab that repeated the same name and context one row lower, and it carries the
/// edit control that a `ToolbarItem` could not render on iPad.
private struct iOSListDetailHeader: View {
    let eyebrow: String
    let title: String
    let colorHex: String
    var onBack: (() -> Void)? = nil
    let onEdit: () -> Void

    var body: some View {
        // The list's own `colorHex` is the only thing this header adds to the shared one; the edit
        // control rides in the single trailing slot, which is where it has to be — a `ToolbarItem`
        // cannot render it on iPad. The colour used to sit on an identity tile, which is gone from
        // every page header on both platforms; it lands on the count capsule now, same as macOS.
        iOSPageHeader(
            eyebrow: eyebrow,
            title: TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
            color: Color(hex: colorHex),
            onBack: onBack
        ) {
            iOSIconButton(
                systemImage: "slider.horizontal.3",
                accessibilityLabel: "Edit list",
                action: onEdit
            )
        }
    }
}
#endif

#if os(iOS)
import SwiftData
import SwiftUI

struct iOSListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
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
    /// `nil` until the reader taps a tab — the page they see before that is this list's remembered
    /// tab, or failing that the one they chose in Settings, both read live rather than copied into
    /// `@State` in `onAppear`, so changing the preference does not need a relaunch to take effect
    /// and a stale copy cannot outlive it.
    ///
    /// A caller that opened this page *at* a particular tab seeds it here, which is why the seed is
    /// an `init` argument and not an `onAppear` write: the first render has to be the right page,
    /// or the board scroll below lands on a tab nobody is looking at.
    ///
    /// **Tagged with the list it was picked on** (`selectedPageListKey`). On iPad the sidebar
    /// swaps lists under this one live view, so an untagged pick made on list A was still the
    /// page when list B opened (T-7032). `ListDetailPage.displayedPage` honours it only on its own
    /// list.
    @State private var selectedPage: ListDetailPage?
    @State private var selectedPageListKey: String?
    @AppStorage(CadencePreferenceKeys.listDetailDefaultPage) private var defaultPageRaw = ListDetailPage.defaultPage.rawValue
    /// **The Kanban tab's "Show Archived" chip, the Mac's `showArchivedKanbanColumns`** ([[T-8565]]).
    /// Stored as the list it was switched on for rather than as a bare `Bool`, for the reason
    /// `selectedPageListKey` is: the iPad sidebar swaps lists under this one live view, and an
    /// untagged "on" made on list A would open list B on its archived columns (T-7032). The Mac
    /// gets the same per-list reset from keying its page on the list ([[T-5831]]).
    @State private var showArchivedKanbanColumnsListKey: String?
    /// **The Tasks tab's Sort / Order / Group and the board's Sort / Order, the Mac's per-list
    /// controls** ([[T-13561]], [[T-13562]]). A pick is held with the list it was made on, for the
    /// reason `selectedPageListKey` is, and written through to the keys the Mac's list page reads,
    /// so a list opens the same way on both. `ListDetailSortControls.displayed` decides.
    @State private var taskControlsChoice: ListDetailSortControls.Tasks?
    @State private var taskControlsListKey: String?
    @State private var kanbanControlsChoice: ListDetailSortControls.Kanban?
    @State private var kanbanControlsListKey: String?
    /// The day the By Date groups are cut against ([[T-5012]]), as the Mac's `ListTasksView` holds.
    @State private var observedDay = CadenceObservedDay()
    /// What the last row dropped on a Tasks tab heading has to say ([[T-16682]]): a refusal, or a
    /// landing the active sort does not show -- the Mac's `ListTasksView` pair, from the same
    /// `ListTasksGroupDrop.dropOnHeader` answer.
    @State private var headingDropFailureNotice: String?
    @State private var headingDropLandingNotice: String?

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
        _selectedPageListKey = State(initialValue: ListDetailPage.rememberedPageDefaultsKey(areaID: area.id, projectID: nil))
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
        _selectedPageListKey = State(initialValue: ListDetailPage.rememberedPageDefaultsKey(areaID: nil, projectID: project.id))
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

    /// Where this list's tab is remembered — the key macOS uses for the same list.
    private var rememberedPageKey: String {
        ListDetailPage.rememberedPageDefaultsKey(areaID: area?.id, projectID: project?.id)
    }

    /// The tab on screen. Stored values are resolved rather than force-unwrapped from their raw
    /// value: either can still read "Planning", a tab that no longer exists on either platform, and
    /// `ListDetailPage.resolved(_:)` lands that on Tasks instead of on nothing.
    private var page: ListDetailPage {
        ListDetailPage.displayedPage(
            choice: selectedPage,
            choiceListKey: selectedPageListKey,
            listKey: rememberedPageKey,
            storedRawValue: CadenceDefaults.store.string(forKey: rememberedPageKey),
            defaultPageRawValue: defaultPageRaw
        )
    }

    /// A tap records the pick against this list and remembers it, as macOS does on every change.
    private var pageBinding: Binding<ListDetailPage> {
        Binding(get: { page }, set: { newPage in
            let key = rememberedPageKey
            selectedPage = newPage
            selectedPageListKey = key
            CadenceDefaults.store.set(newPage.rawValue, forKey: key)
        })
    }

    private var showArchivedKanbanColumns: Bool {
        showArchivedKanbanColumnsListKey == rememberedPageKey
    }

    /// The columns the Kanban tab draws. Off, the list's live columns -- and only those: a section
    /// only a task names no longer gets a column of its own, which brought an archived column back
    /// onto the live board; the panel files such a card under Default, as the Mac board does
    /// ([[T-11222]] (b), `ListBoardCardFiling`). On, the list's archived columns through the rule the
    /// Mac board reads, `ListDetailKanbanBoard.visibleSectionConfigs` ([[T-8565]]).
    private var kanbanSectionNames: [String] {
        guard showArchivedKanbanColumns else { return configuredSectionNames }
        return ListDetailKanbanBoard.visibleSectionConfigs(sectionConfigs, showArchived: true).map(\.name)
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

    @AppStorage(CadencePreferenceKeys.iosListDetailShowCompleted) private var showCompleted = false
    /// The Tasks tab's folded columns, by group id ([[T-12191]]): unpersisted, one set per page,
    /// as the Mac's `ListTasksView.collapsedGroupIDs` is.
    ///
    /// **Tagged with the list it was folded on** (`collapsedGroupIDsListKey`, [[T-14521]]), for the
    /// reason `selectedPageListKey` is: the iPad sidebar swaps lists under this one live view, and
    /// group ids name the same group on every list, so an untagged fold on list A folded list B's
    /// group of the same name. The groups read it through `collapsedGroupIDsBinding` only.
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var collapsedGroupIDsListKey: String?

    /// The fold set on this list, and a fold recorded against this list.
    private var collapsedGroupIDsBinding: Binding<Set<String>> {
        Binding(get: {
            CadenceTaskGroupFold.displayed(
                collapsedGroupIDs,
                foldedOnListKey: collapsedGroupIDsListKey,
                listKey: rememberedPageKey
            )
        }, set: { collapsed in
            collapsedGroupIDs = collapsed
            collapsedGroupIDsListKey = rememberedPageKey
        })
    }

    private var tasksKeyPrefix: String {
        ListDetailSortControls.tasksKeyPrefix(areaID: area?.id, projectID: project?.id)
    }

    private var kanbanKeyPrefix: String {
        ListDetailSortControls.kanbanKeyPrefix(areaID: area?.id, projectID: project?.id)
    }

    /// The retired app-wide `ios.listDetail.sortMode`, read only as the fallback for a list this
    /// device has never sorted on its own (`ListDetailSortControls.tasks(prefix:in:legacyMode:)`).
    private var legacySortMode: CadenceTaskSortMode? {
        CadenceDefaults.store.string(forKey: CadencePreferenceKeys.iosListDetailSortMode)
            .flatMap(CadenceTaskSortMode.init(rawValue:))
    }

    private var taskControls: ListDetailSortControls.Tasks {
        ListDetailSortControls.displayed(
            choice: taskControlsChoice,
            choiceListKey: taskControlsListKey,
            listKey: tasksKeyPrefix
        ) {
            ListDetailSortControls.tasks(prefix: tasksKeyPrefix, in: CadenceDefaults.store, legacyMode: legacySortMode)
        }
    }

    private var kanbanControls: ListDetailSortControls.Kanban {
        ListDetailSortControls.displayed(
            choice: kanbanControlsChoice,
            choiceListKey: kanbanControlsListKey,
            listKey: kanbanKeyPrefix
        ) {
            ListDetailSortControls.kanban(prefix: kanbanKeyPrefix, in: CadenceDefaults.store)
        }
    }

    /// One of the Tasks tab's three controls, written to this list's keys as the Mac writes them.
    private func taskControl<Value>(_ keyPath: WritableKeyPath<ListDetailSortControls.Tasks, Value>) -> Binding<Value> {
        Binding(get: { taskControls[keyPath: keyPath] }, set: { value in
            var next = taskControls
            next[keyPath: keyPath] = value
            taskControlsChoice = next
            taskControlsListKey = tasksKeyPrefix
            ListDetailSortControls.save(next, prefix: tasksKeyPrefix, in: CadenceDefaults.store)
        })
    }

    /// One of the board's two controls, under the Mac board's own `kanban_<uuid>` keys.
    private func kanbanControl<Value>(_ keyPath: WritableKeyPath<ListDetailSortControls.Kanban, Value>) -> Binding<Value> {
        Binding(get: { kanbanControls[keyPath: keyPath] }, set: { value in
            var next = kanbanControls
            next[keyPath: keyPath] = value
            kanbanControlsChoice = next
            kanbanControlsListKey = kanbanKeyPrefix
            ListDetailSortControls.save(next, prefix: kanbanKeyPrefix, in: CadenceDefaults.store)
        })
    }

    /// The Tasks tab's open rows, in its own Sort + Order.
    private var activeTasks: [AppTask] {
        let controls = taskControls
        return ListDetailSortControls.sortedOpenTasks(
            filteredTasks,
            sortField: controls.sortField,
            sortDirection: controls.sortDirection
        )
    }

    /// The board's open cards, in the board's OWN Sort + Order ([[T-13562]]) — not the Tasks tab's,
    /// which is what the board silently took before it had controls of its own.
    private var kanbanTasks: [AppTask] {
        let controls = kanbanControls
        return ListDetailSortControls.sortedOpenTasks(
            filteredTasks,
            sortField: controls.sortField,
            sortDirection: controls.sortDirection
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: filteredTasks)
    }

    /// The board's finished cards, in the board's own Sort + Order as the Mac's column sorts them
    /// ([[T-16301]]) -- not the Completed tab's most-recent-first list above.
    private var kanbanCompletedTasks: [AppTask] {
        let controls = kanbanControls
        return ListDetailSortControls.sortedFinishedTasks(
            filteredTasks,
            sortField: controls.sortField,
            sortDirection: controls.sortDirection
        )
    }

    private var filteredTasks: [AppTask] {
        CadenceTaskQuerySupport.tasks(for: area, project: project, in: allTasks)
    }

    private var configuredSectionNames: [String] {
        area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName]
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSListDetailHeader(
                eyebrow: subtitle.isEmpty ? (area == nil ? "Project" : "Area") : subtitle,
                title: title,
                colorHex: colorHex,
                projectDueDate: project?.dueDate,
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
            // every panel's `@State` survived the switch. `iOSListNotesPanel` seeded its note in
            // `onAppear` and only there, so switching area A → B while the Notes tab was open left
            // you typing into A's note under B's header, and a task created from inside it landed
            // in B. `iOSListViews`' own split view already does this with `.id(route)`; this is the
            // same discipline applied where the panels live, so it holds for every host.
            pageBody
                .id(containerIdentity)
        }
        .cadenceScaledTypography()
        .background(Theme.bg.ignoresSafeArea())
        // The By Date groups' day ([[T-13561]]), observed once for the page as the Mac's
        // `ListTasksView` does.
        .cadenceTracksDayChanges($observedDay)
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
                .cadenceFixedTypography()
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
            kanbanPage
        case .documents:
            // `iOSListNotesView`, not the old `iOSListNotesPanel`: this list may hold many notes,
            // filed into folders on a Mac, and the panel showed exactly one of them at the root of
            // a filing system it could not draw. See T-193 and `CadenceNoteFolderPath`.
            iOSListNotesView(area: area, project: project)
                .cadenceFixedTypography()
        case .links:
            iOSListLinksPanel(area: area, project: project)
        case .completed:
            iOSListCompletedPanel(tasks: completedTasks, todayKey: observedDay.todayKey)
        }
    }

    /// The Kanban tab: Sort, Order and "Show Archived" on a band of their own, as the Tasks tab
    /// carries its controls, then the board ([[T-8565]], [[T-13562]]). The Mac draws the same three
    /// in its tab bar, in this order, with Order only where the field honours one (T-7006).
    private var kanbanPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                iOSEnumChoiceChip(title: "Sort", glyph: "arrow.up.arrow.down", selection: kanbanControl(\.sortField))
                if kanbanControls.sortField.honorsDirection {
                    iOSEnumChoiceChip(title: "Order", glyph: "arrow.up.arrow.down.square", selection: kanbanControl(\.sortDirection))
                }
                archivedColumnsChip
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            iOSListKanbanPanel(
                tasks: kanbanTasks,
                // [[T-9837]]: the finished half, which the board used never to be given at all --
                // so a column whose work was all done read "0" and empty here while the Mac showed
                // it behind a Completed toggle. The page's own Completed TAB keeps these same tasks;
                // one surface naming finished work does not excuse the other dropping it, which is
                // the Mac's position on its own list page.
                // [[T-16301]]: in the board's Sort + Order, as the Mac column draws them.
                completedTasks: kanbanCompletedTasks,
                sectionNames: kanbanSectionNames,
                sectionConfigs: sectionConfigs,
                hideSectionDueDateIfEmpty: hideSectionDueDateIfEmpty,
                todayKey: observedDay.todayKey,
                accent: accent,
                container: containerSelection,
                listName: title,
                highlightedSectionName: highlightedSectionName,
                area: area,
                project: project,
                spanTasks: filteredTasks,
                showsArchivedColumns: showArchivedKanbanColumns
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }

    /// The Mac pill's words, glyph and "on" cues (`ListDetailTabBarView.archivedColumnsButton`) on the
    /// chip shape the Sort chip beside the Tasks tab already uses: neutral, never accent-tinted;
    /// on reads as a brighter fill, brighter label, filled glyph and the shorter label.
    private var archivedColumnsChip: some View {
        let isOn = showArchivedKanbanColumns
        return Button {
            showArchivedKanbanColumnsListKey = isOn ? nil : rememberedPageKey
        } label: {
            Label(
                ListDetailKanbanBoard.ArchivedColumnsToggle.title(showingArchived: isOn),
                systemImage: ListDetailKanbanBoard.ArchivedColumnsToggle.systemImage(showingArchived: isOn)
            )
            .cadenceFont(.controlLabel, base: iOSTaskChipMetrics.fontSize)
            .foregroundStyle(isOn ? Theme.text : Theme.dim)
            .padding(.horizontal, iOSTaskChipMetrics.horizontalPadding)
            .frame(minHeight: 44)
            .background(Theme.surfaceElevated.opacity(isOn ? 1 : 0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(ListDetailKanbanBoard.ArchivedColumnsToggle.accessibilityLabel(showingArchived: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Sort / Order / Group over this list's own keys, with By List called "By Section" — the Mac's
    /// list tab, control for control ([[T-13561]]).
    private var taskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSTaskSortGroupBar(
                sortField: taskControl(\.sortField),
                sortDirection: taskControl(\.sortDirection),
                groupingMode: taskControl(\.grouping),
                groupingLabel: ListTasksGroupingLabel.label(for:)
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // [[T-6201]]: an empty page draws its own sections too, so a section "+ Section" just
            // made appears. Only a page with nothing to draw at all — no task and no section of
            // the user's (`listSectionGroups` leaves Default out of an empty page) — takes the
            // whole-column empty panel; otherwise `sectionStack` heads its columns with it.
            if isTaskColumnEmpty && sectionGroups.isEmpty {
                // The list itself is the only placement left when the page has neither rows nor
                // columns drawn to point at — the `.list` half of `groupIdentity`, and the same
                // move the Inbox's empty panel already makes. See `iOSTaskCollectionSections`.
                // Words shared with the Mac's `ListTasksView`. The subtitle used to say "Add a
                // task above", naming an inline field this page has never had — the affordance is
                // the floating `+` applied above — which is the exact mistake
                // `CadenceTodayPresentationSupport.emptySubtitle` already records having made.
                listEmptyPanel
                if groupsBySection {
                    CadenceSectionCreationRow(area: area, project: project)
                        .padding(.horizontal, iOSListDetailTaskMetrics.horizontalPadding)
                        .padding(.bottom, iOSListDetailTaskMetrics.bottomPadding)
                }
            } else {
                sectionStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }

    /// **Only By Section draws sections, so only By Section offers the row that makes one** — the
    /// Mac's rule ([[T-5832]] (b)): under By Date, By Priority and None a new section would appear
    /// nowhere, and the control would read as broken.
    private var groupsBySection: Bool {
        taskControls.grouping == .byList
    }

    /// The page's empty state, with the list itself as its drop placement. Drawn alone when the
    /// column has nothing else, and at the head of `sectionStack` above the user's empty sections
    /// when it does ([[T-6201]]) — so an empty list with sections still says it has no tasks
    /// rather than reading as a column of blank headings.
    private var listEmptyPanel: some View {
        iOSEmptyPanel(
            systemImage: CadenceEmptyStateCopy.listDetailSystemImage,
            title: CadenceEmptyStateCopy.listDetailTitle,
            subtitle: CadenceEmptyStateCopy.listDetailSubtitle
        )
        .iOSNewTaskDropTarget(
            group: CadenceTaskDropSupport.groupIdentity(
                container: containerSelection,
                listName: title
            )
        )
    }

    /// **Finished work counts as content whether or not it is unfolded (T-2090).** This read
    /// `!showCompleted || completedTasks.isEmpty`, which was right while a chip decided whether the
    /// Completed section existed at all; it is always on the page now, so a list whose only work is
    /// already done draws a folded "Completed" instead of calling itself empty directly above one.
    private var isTaskColumnEmpty: Bool {
        activeTasks.isEmpty && completedTasks.isEmpty
    }

    /// **Every configured column, including the ones with nothing in them.** `sectionGroups`
    /// discards an empty section by default, which is right where a heading over no rows would say
    /// nothing — and wrong here, because this is a surface you can add to. An unfilled kanban
    /// column is the case `CadenceTaskDropSupport.showsWhenEmpty(_:)` was written for, and the rule
    /// could never fire on this page: the column was gone before `iOSTaskGroupSection` got to
    /// decide. Since [[T-6201]] that holds on a page with no tasks as well — the shared rule the
    /// Mac's list Tasks tab reads too, which leaves only Default out of an empty page.
    ///
    /// The headings are the live columns only: a task whose section names none of them is drawn
    /// under Default, not under a heading appended for its name, which brought an archived column
    /// back onto this tab while the Mac's showed the task nowhere ([[T-12121]]).
    ///
    /// **That is the By Section arm.** Since [[T-13561]] the Group chip picks among the Mac's four
    /// arms through `ListDetailSortControls.taskGroups`, each group tinted as the Mac's heading is.
    private var sectionGroups: [CadenceTaskDisplayGroup] {
        ListDetailSortControls.taskGroups(
            from: activeTasks,
            grouping: taskControls.grouping,
            sectionNames: configuredSectionNames,
            sectionConfigs: sectionConfigs,
            pageIsEmpty: isTaskColumnEmpty,
            todayKey: observedDay.todayKey
        )
    }

    /// Where a `+` dropped on a group's heading lands: the section, under By Section; the list
    /// itself under the other three, whose groups are days and priorities, not places to file a task.
    private func dropIdentity(for group: CadenceTaskDisplayGroup) -> CadenceTaskGroupDropIdentity {
        guard groupsBySection else {
            return CadenceTaskDropSupport.groupIdentity(container: containerSelection, listName: title)
        }
        return CadenceTaskDropSupport.groupIdentity(
            container: containerSelection,
            listName: title,
            sectionName: group.title
        )
    }

    /// **A task row dragged onto a heading re-files it, as the Mac's list Tasks tab does
    /// ([[T-16682]]).** The whole drop is `ListTasksGroupDrop.dropOnHeader`, the Mac header's own
    /// steps: into the group (section, priority or date bucket), then to its top; an empty
    /// section's heading files it there with no renumber. `nil` -- no row destination at all --
    /// for a heading that names nothing to file under (the ungrouped "Tasks", Overdue, Leftover,
    /// Due Today), so it never accepts a row it then files nowhere (T-591).
    private func headingRowDrop(for group: CadenceTaskDisplayGroup) -> ((String) -> Bool)? {
        guard ListTasksGroupDrop.takesDroppedRow(group) else { return nil }
        let controls = taskControls
        // The page's observed day, never the clock -- the day its By Date groups were cut on.
        let dayKey = observedDay.todayKey
        return { payload in
            let outcome = ListTasksGroupDrop.dropOnHeader(
                payload: payload,
                onto: group,
                groupingMode: controls.grouping,
                listTasks: filteredTasks,
                todayKey: dayKey,
                modelContext: modelContext,
                sortKeyOrder: {
                    TaskOrdering.sortKeyOrder($0, $1, field: controls.sortField, direction: controls.sortDirection)
                }
            )
            switch outcome {
            case .applied(let notice):
                headingDropFailureNotice = nil
                headingDropLandingNotice = notice
                return true
            case .refused(let notice):
                headingDropLandingNotice = nil
                headingDropFailureNotice = notice
                return false
            case .resolvedNothing:
                return false
            }
        }
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
                if let headingDropFailureNotice {
                    CadenceInlineFailureNotice(text: headingDropFailureNotice)
                }
                if let headingDropLandingNotice {
                    CadenceInlineNotice(text: headingDropLandingNotice, tone: .informational)
                }
                if isTaskColumnEmpty {
                    listEmptyPanel
                }
                ForEach(sectionGroups) { group in
                    iOSTaskGroupSection(
                        title: group.title,
                        // Under By Section, the colour the board's column dot takes, so a column is
                        // the same column whichever tab you are looking at it from.
                        color: group.accent,
                        tasks: group.tasks,
                        // Scoped to one list already — the chip would name the page you are on.
                        showsContainer: false,
                        todayKey: observedDay.todayKey,
                        dropIdentity: dropIdentity(for: group),
                        collapsedGroupIDs: collapsedGroupIDsBinding,
                        groupID: group.id,
                        onDropTaskPayload: headingRowDrop(for: group)
                    )
                }

                // **Always drawn, at the foot of the columns, folded until it is asked for
                // (T-2090).** This was `if showCompleted { iOSTaskGroupSection("Completed") }` over
                // the options bar's "Completed" chip; the chip is gone from every iOS surface and
                // this heading is the control, which is what macOS's own list detail already drew
                // (`ListTasksCompletedSectionView`). The empty-section predicate comes with the
                // component — `.completion` resolves to no drop key, so the group never survived
                // emptying and the drop target it used to declare was inert.
                iOSCompletedTasksSection(
                    title: "Completed",
                    tint: Theme.green,
                    tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch),
                    // Scoped to one list already — the chip would name the page you are on.
                    showsContainer: false,
                    todayKey: observedDay.todayKey,
                    accessibilityNoun: "the tasks you have finished",
                    isExpanded: $showCompleted
                )
                if groupsBySection {
                    CadenceSectionCreationRow(area: area, project: project)
                }
            }
            // One gutter, not two (T-613). This was `.padding(12)` — the inset of the
            // `.cadenceCard()` `85809ff` deleted — *plus* the panel's own 12, so the section
            // headers and rows sat at 24 while the options bar directly above them sat at 16.
            .padding(.horizontal, iOSListDetailTaskMetrics.horizontalPadding)
            .padding(.bottom, iOSListDetailTaskMetrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
        // **The list itself, for the blank space between its columns** (T-1276) — the same identity
        // the page's empty state takes above, which is what a page scoped to one list has to give
        // and all it has: the section headers inside name a column each, and they keep winning on
        // area wherever one is under the finger.
        .iOSNewTaskDropRegion(
            CadenceTaskDropSupport.groupIdentity(container: containerSelection, listName: title)
        )
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
    let projectDueDate: String?
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
            HStack(spacing: 8) {
                if let projectDueDate, !projectDueDate.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .cadenceFont(.metadata, base: 10, weight: .regular)
                            .accessibilityHidden(true)
                        Text(DateFormatters.shortDateString(from: projectDueDate))
                            .cadenceFont(.metadata, base: 11, weight: .regular)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(ListDetailHeaderAccessibility.deadlineLabel(dueDate: projectDueDate))
                }
                // [[T-12602]]: the Mac's control -- the shared pencil, in the list's own colour.
                iOSIconButton(
                    systemImage: ListDetailHeaderAccessibility.editGlyph,
                    accessibilityLabel: ListDetailHeaderAccessibility.editLabel(listName: title),
                    tint: Color(hex: colorHex),
                    action: onEdit
                )
            }
        }
    }
}
#endif

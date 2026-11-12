#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Loaders

// **The `else` on each of these loaders is T-345's second half, and it is not decoration.**
//
// `SidebarSelectionNormalizer` retargets a selection whose list has been deleted, but it runs on a
// query change, which means there is a render — and after a CloudKit delete, potentially several —
// in which the selection still names the missing id. Without an `else` the detail pane draws
// *nothing at all* in that window: not an explanation, not an empty state, blank content, which
// reads as the app having lost the page rather than as the list having been deleted.
//
// Both halves are needed. The normalizer alone leaves a blank frame reachable; this state alone
// leaves the user parked on a tombstone with no way back except clicking another list.

struct AreaDetailLoader: View {
    let id: UUID
    @Query private var areas: [Area]

    var body: some View {
        if let area = areas.first(where: { $0.id == id }) {
            // [[T-5831]]: one identity per list, so Area A -> Area B builds a fresh page whose
            // `onAppear` restores B's own tab, Sort, Order and Group rather than keeping A's
            // `@State` — the sidebar sets `selection` directly, which is the same switch arm.
            ListDetailView(area: area, project: nil)
                .id(area.id)
        } else {
            MissingListDetailView()
        }
    }
}

struct ProjectDetailLoader: View {
    let id: UUID
    @Query private var projects: [Project]

    var body: some View {
        if let project = projects.first(where: { $0.id == id }) {
            // [[T-5831]]: see `AreaDetailLoader`.
            ListDetailView(area: nil, project: project)
                .id(project.id)
        } else {
            MissingListDetailView()
        }
    }
}

/// One state for both loaders rather than a near-copy each — and **iOS's wording, not a second
/// one.** `iOSMissingListView` has shipped this exact sentence since iOS grew the same `else` on the
/// same `if let area = areas.first(where:)`, so the only thing macOS was missing here was the
/// branch. Two platforms explaining one situation in two different sentences is the drift the
/// root guide's "one style, differing by layout" rule is about.
///
/// Both sentences are `CadenceEmptyStateCopy.missingList*` now (T-522). They used to be typed out
/// here and again in `iOSRootSidebar`, held level only by a test asserting the two files matched —
/// which is a weaker mechanism than one declaration, and it was the last thing keeping an
/// allowance in `CadenceEmptyStateAuditTests`.
///
/// The panel component differs because it has to: `iOSEmptyPanel` is inside `#if os(iOS)` and
/// `EmptyStateView` is the shared one macOS pages already use. The glyph is still spelled at both
/// call sites, because a symbol name is a picture and not a sentence.
struct MissingListDetailView: View {
    var body: some View {
        EmptyStateView(
            message: CadenceEmptyStateCopy.missingListTitle,
            subtitle: CadenceEmptyStateCopy.missingListSubtitle,
            icon: "questionmark.folder"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

// `ListTasksGroupingLabel` — "By Section" for `.byList` on this page — lives in
// `Shared/CadenceListDetailSortControls.swift` since [[T-13561]]: the iPhone and iPad list tab draws
// the same Group chip.

// MARK: - Detail View

// `ListDetailPage` — the tabs below — lives in `Shared/CadenceListDetailPage.swift`, because iOS
// draws the same five tabs and had its own drifting copy of this enum.

private struct ListDetailView: View {
    var area: Area?
    var project: Project?

    @Environment(ListNavigationManager.self) private var listNavigationManager
    @AppStorage(CadencePreferenceKeys.listDetailDefaultPage) private var defaultPageRawValue = ListDetailPage.tasks.rawValue
    @State private var tab: ListDetailPage = .tasks
    @State private var showEdit = false
    @State private var keyMonitor: Any? = nil
    @State private var showArchivedKanbanColumns = false
    // Defaults and keys are `ListDetailSortControls`', which iOS reads too ([[T-13561]]).
    @State private var kanbanSortField: TaskSortField = ListDetailSortControls.defaultKanban.sortField
    @State private var kanbanSortDirection: TaskSortDirection = ListDetailSortControls.defaultKanban.sortDirection
    @State private var taskGroupingMode: TaskGroupingMode = ListDetailSortControls.defaultTasks.grouping
    @State private var taskSortField: TaskSortField = ListDetailSortControls.defaultTasks.sortField
    @State private var taskSortDirection: TaskSortDirection = ListDetailSortControls.defaultTasks.sortDirection
    @State private var highlightedKanbanSectionName: String?
    @State private var requestedEventNoteID: UUID?
    /// The list document a global-search hit asked for ([[T-3084]]), handed to the Documents tab
    /// the same way `requestedEventNoteID` is.
    @State private var requestedListNoteID: UUID?

    private var kanbanUDKey: String {
        ListDetailSortControls.kanbanKeyPrefix(areaID: area?.id, projectID: project?.id)
    }

    private var taskUDKeyPrefix: String {
        ListDetailSortControls.tasksKeyPrefix(areaID: area?.id, projectID: project?.id)
    }

    private var tabDefaultsKey: String {
        ListDetailPage.rememberedPageDefaultsKey(areaID: area?.id, projectID: project?.id)
    }

    var body: some View {
        ListDetailChromeView(
            area: area,
            project: project,
            tab: pickedTab,
            showEdit: $showEdit,
            showArchivedKanbanColumns: $showArchivedKanbanColumns,
            kanbanSortField: $kanbanSortField,
            kanbanSortDirection: $kanbanSortDirection,
            taskSortField: $taskSortField,
            taskSortDirection: $taskSortDirection,
            taskGroupingMode: $taskGroupingMode,
            highlightedKanbanSectionName: highlightedKanbanSectionName,
            requestedEventNoteID: $requestedEventNoteID,
            requestedListNoteID: $requestedListNoteID
        )
            .modifier(ListDetailLifecycleModifier(
                navigationToken: listNavigationManager.request?.token,
                onAppearAction: {
                    restoreRememberedTab()
                    applyPendingNavigationIfNeeded()
                    installKeyMonitorIfNeeded()
                    restoreTaskAndKanbanControls()
                },
                onDisappearAction: removeKeyMonitor,
                onNavigationChange: applyPendingNavigationIfNeeded
            ))
            .modifier(ListDetailKanbanPersistenceModifier(
                kanbanSortField: $kanbanSortField,
                kanbanSortDirection: $kanbanSortDirection,
                kanbanUDKey: kanbanUDKey
            ))
            .modifier(ListDetailTaskPreferencePersistenceModifier(
                taskSortField: $taskSortField,
                taskSortDirection: $taskSortDirection,
                taskGroupingMode: $taskGroupingMode,
                taskUDKeyPrefix: taskUDKeyPrefix
            ))
    }

    /// **The tab bar's binding: a pick made on this list, remembered as this list's page**
    /// ([[T-14281]]).
    ///
    /// The tab used to be written to the list's key by an `onChange(of: tab)`, which also fired
    /// for `restoreRememberedTab()`'s own write. So a list opened for the first time while the
    /// Settings "Default page" was Kanban saved Kanban as its page -- a page nobody picked on it --
    /// and when the default later moved to Notes, every list ever opened kept opening on Kanban,
    /// against the setting's own subtitle ("Used when a list does not have a saved page") and
    /// against iOS, whose `pageBinding` writes on a tap only. Only a pick writes now: a tab click
    /// (this binding) and Cmd-Shift-[ / ] (`moveTab`). The restore and a navigation request's
    /// page are what the list OPENS on, not a pick, as iOS's `initialPage` seed is never written.
    private var pickedTab: Binding<ListDetailPage> {
        Binding(get: { tab }, set: { pickTab($0) })
    }

    private func pickTab(_ page: ListDetailPage) {
        tab = page
        CadenceDefaults.store.set(page.rawValue, forKey: tabDefaultsKey)
    }

    private func restoreRememberedTab() {
        tab = ListDetailPage.rememberedPage(
            storedRawValue: CadenceDefaults.store.string(forKey: tabDefaultsKey),
            defaultPageRawValue: defaultPageRawValue
        )
    }

    private func applyPendingNavigationIfNeeded() {
        guard let request = listNavigationManager.consumeIfMatches(
            areaID: area?.id,
            projectID: project?.id
        ) else { return }
        tab = request.page
        highlightedKanbanSectionName = request.page == .kanban ? request.sectionName : nil
        requestedEventNoteID = request.page == .documents ? request.eventNoteID : nil
        requestedListNoteID = request.page == .documents ? request.listNoteID : nil
    }

    private func restoreTaskAndKanbanControls() {
        let ud = CadenceDefaults.store
        let kanban = ListDetailSortControls.kanban(prefix: kanbanUDKey, in: ud)
        kanbanSortField = kanban.sortField
        kanbanSortDirection = kanban.sortDirection
        let tasks = ListDetailSortControls.tasks(prefix: taskUDKeyPrefix, in: ud)
        taskSortField = tasks.sortField
        taskSortDirection = tasks.sortDirection
        taskGroupingMode = tasks.grouping
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), flags.contains(.shift) else { return event }
            switch event.keyCode {
            case 33: // [
                moveTab(by: -1)
                return nil
            case 30: // ]
                moveTab(by: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func moveTab(by delta: Int) {
        let tabs = ListDetailPage.allCases
        guard let currentIndex = tabs.firstIndex(of: tab), !tabs.isEmpty else { return }
        let nextIndex = (currentIndex + delta + tabs.count) % tabs.count
        pickTab(tabs[nextIndex])
    }
}

private struct ListDetailChromeView: View {
    var area: Area?
    var project: Project?
    @Binding var tab: ListDetailPage
    @Binding var showEdit: Bool
    @Binding var showArchivedKanbanColumns: Bool
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode
    let highlightedKanbanSectionName: String?
    @Binding var requestedEventNoteID: UUID?
    @Binding var requestedListNoteID: UUID?

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    private var name: String { area?.name ?? project?.name ?? "" }
    private var colorHex: String { area?.colorHex ?? project?.colorHex ?? Theme.blueHex }
    /// An area's own tasks exclude any also filed under a project ([[T-15431]]).
    private var tasks: [AppTask] {
        if let area { return CadenceTaskQuerySupport.listedTasks(for: area) }
        return project?.tasks ?? []
    }
    private var allowsSectionEditing: Bool { area != nil || project != nil }
    private var editableHoverID: String {
        "list-detail-\(area?.id.uuidString ?? project?.id.uuidString ?? "unknown")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ListDetailTabBarView(
                tab: $tab,
                showArchivedKanbanColumns: $showArchivedKanbanColumns,
                kanbanSortField: $kanbanSortField,
                kanbanSortDirection: $kanbanSortDirection,
                taskSortField: $taskSortField,
                taskSortDirection: $taskSortDirection,
                taskGroupingMode: $taskGroupingMode,
                allowsSectionEditing: allowsSectionEditing
            )

            Divider().background(Theme.borderSubtle)

            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
        .sheet(isPresented: $showEdit) {
            editSheetContent
        }
    }

    private var header: some View {
        // The list's own `colorHex` is what this header adds to the shared one. It used to spend
        // it on an identity tile; with page tiles gone it lands on the count capsule, which is the
        // only thing `tint` colours now.
        DesktopPageHeader(
            title: ListDetailHeaderAccessibility.displayTitle(listName: name),
            tint: Color(hex: colorHex)
        ) {
            HStack(spacing: 8) {
                if let project = project, !project.dueDate.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text(DateFormatters.shortDateString(from: project.dueDate)).font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    // T-7080: a bare "Oct 30" to VoiceOver; iOS's chip says whose date it is.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ListDetailHeaderAccessibility.deadlineLabel(dueDate: project.dueDate))
                    .help(ListDetailHeaderAccessibility.deadlineLabel(dueDate: project.dueDate))
                }

                CadenceIconButton(
                    systemImage: ListDetailHeaderAccessibility.editGlyph,
                    accessibilityLabel: ListDetailHeaderAccessibility.editLabel(listName: name),
                    tint: Color(hex: colorHex),
                    action: { showEdit = true }
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredEditableManager.beginHovering(id: editableHoverID) {
                    showEdit = true
                }
            } else {
                hoveredEditableManager.endHovering(id: editableHoverID)
            }
        }
    }

    @ViewBuilder
    private var editSheetContent: some View {
        if let area {
            EditAreaSheet(area: area)
        } else if let project {
            EditProjectSheet(project: project)
        }
    }

    private var pageBody: AnyView {
        switch tab {
        case .tasks:
            return AnyView(ListTasksView(
                tasks: tasks,
                area: area,
                project: project,
                sortField: taskSortField,
                sortDirection: taskSortDirection,
                groupingMode: taskGroupingMode
            ))
        case .kanban:
            return AnyView(ListSectionsKanbanView(
                tasks: tasks,
                universeTasks: tasks,
                area: area,
                project: project,
                showArchived: $showArchivedKanbanColumns,
                sortField: kanbanSortField,
                sortDirection: kanbanSortDirection,
                highlightedSectionName: highlightedKanbanSectionName
            ))
        case .documents:
            return AnyView(ListNotesView(
                area: area,
                project: project,
                requestedEventNoteID: $requestedEventNoteID,
                requestedListNoteID: $requestedListNoteID
            ))
        case .links:
            return AnyView(LinksView(area: area, project: project))
        case .completed:
            return AnyView(ListLogView(tasks: tasks))
        }
    }
}

private struct ListDetailLifecycleModifier: ViewModifier {
    let navigationToken: UUID?
    let onAppearAction: () -> Void
    let onDisappearAction: () -> Void
    let onNavigationChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearAction)
            .onDisappear(perform: onDisappearAction)
            .onChange(of: navigationToken) { _, _ in
                onNavigationChange()
            }
    }
}

/// The board's Sort / Order. The tab is not persisted here any more: an `onChange` cannot tell a
/// pick from the restore, so it is written where it is picked (`ListDetailView.pickTab`, [[T-14281]]).
private struct ListDetailKanbanPersistenceModifier: ViewModifier {
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection

    let kanbanUDKey: String

    func body(content: Content) -> some View {
        content
            .onChange(of: kanbanSortField) { _, value in
                CadenceDefaults.store.set(value.rawValue, forKey: ListDetailSortControls.sortFieldKey(kanbanUDKey))
            }
            .onChange(of: kanbanSortDirection) { _, value in
                CadenceDefaults.store.set(value.rawValue, forKey: ListDetailSortControls.sortDirectionKey(kanbanUDKey))
            }
    }
}

private struct ListDetailTaskPreferencePersistenceModifier: ViewModifier {
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode

    let taskUDKeyPrefix: String

    func body(content: Content) -> some View {
        content
            .onChange(of: taskSortField) { _, value in
                CadenceDefaults.store.set(value.rawValue, forKey: ListDetailSortControls.sortFieldKey(taskUDKeyPrefix))
            }
            .onChange(of: taskSortDirection) { _, value in
                CadenceDefaults.store.set(value.rawValue, forKey: ListDetailSortControls.sortDirectionKey(taskUDKeyPrefix))
            }
            .onChange(of: taskGroupingMode) { _, value in
                CadenceDefaults.store.set(value.rawValue, forKey: ListDetailSortControls.groupingKey(taskUDKeyPrefix))
            }
    }
}

private struct ListDetailTabBarView: View {
    @Binding var tab: ListDetailPage
    @Binding var showArchivedKanbanColumns: Bool
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode
    let allowsSectionEditing: Bool

    /// The bar's height is pinned rather than derived from its children. `trailingControls`
    /// only exists on Tasks and Kanban, so an unconstrained HStack sized itself to whichever
    /// controls happened to be present and the bar visibly grew/shrank on every tab switch.
    private static let barHeight = CadenceDesktopMetrics.compactControlHeight + 20

    var body: some View {
        HStack(spacing: 12) {
            tabCluster
            Spacer(minLength: 16)
            trailingControls
        }
        .padding(.horizontal, 16)
        .frame(height: Self.barHeight)
    }

    private var tabCluster: some View {
        HStack(spacing: CadenceQuietPillMetrics.clusterSpacing) {
            ForEach(ListDetailPage.allCases, id: \.self) { page in
                CadenceQuietTabButton(title: page.rawValue, isSelected: tab == page) {
                    tab = page
                }
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if tab == .tasks, CadenceTaskSurfaceOptions.options(for: .listDetail).showsSort {
            HStack(spacing: 6) {
                CadenceEnumPickerBadge(title: "Sort", selection: $taskSortField)
                // Custom is the drag order, which no direction reverses (T-7006).
                if taskSortField.honorsDirection {
                    CadenceEnumPickerBadge(title: "Order", selection: $taskSortDirection)
                }
                CadenceEnumPickerBadge(
                    title: "Group",
                    selection: $taskGroupingMode,
                    labelOverride: ListTasksGroupingLabel.label(for:)
                )
            }
            .padding(.trailing, 4)
        } else if tab == .kanban, allowsSectionEditing {
            HStack(spacing: 6) {
                CadenceEnumPickerBadge(title: "Sort", selection: $kanbanSortField)
                // Custom is the drag order, which no direction reverses (T-7006).
                if kanbanSortField.honorsDirection {
                    CadenceEnumPickerBadge(title: "Order", selection: $kanbanSortDirection)
                }
                archivedColumnsButton
            }
            .padding(.trailing, 4)
        }
    }

    /// Boolean filter, so unlike the sort/order controls beside it this one has a meaningful "on"
    /// state. With the accent gone, it is carried by four neutral cues at once — brighter fill,
    /// brighter label, filled glyph, and a shorter label — rather than by a blue outline.
    private var archivedColumnsButton: some View {
        CadenceQuietPillButton(
            state: showArchivedKanbanColumns ? .active : .resting,
            action: { showArchivedKanbanColumns.toggle() }
        ) {
            HStack(spacing: 6) {
                Image(systemName: ListDetailKanbanBoard.ArchivedColumnsToggle.systemImage(showingArchived: showArchivedKanbanColumns))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(ListDetailKanbanBoard.ArchivedColumnsToggle.title(showingArchived: showArchivedKanbanColumns))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(showArchivedKanbanColumns ? Theme.text : Theme.dim)
        }
        .accessibilityLabel(ListDetailKanbanBoard.ArchivedColumnsToggle.accessibilityLabel(showingArchived: showArchivedKanbanColumns))
        .accessibilityAddTraits(showArchivedKanbanColumns ? .isSelected : [])
    }
}

#endif

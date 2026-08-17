#if os(iOS)
import SwiftData
import SwiftUI

struct iOSListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    let area: Area?
    let project: Project?
    @State private var editorMode: iOSListEditorMode?
    /// `nil` until the reader taps a tab — the page they see before that is the one they chose in
    /// Settings, read live rather than copied into `@State` in `onAppear`, so changing the
    /// preference does not need a relaunch to take effect and a stale copy cannot outlive it.
    @State private var selectedPage: ListDetailPage?
    @AppStorage(CadencePreferenceKeys.listDetailDefaultPage) private var defaultPageRaw = ListDetailPage.defaultPage.rawValue

    init(area: Area) {
        self.area = area
        self.project = nil
    }

    init(project: Project) {
        self.area = nil
        self.project = project
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

    private var icon: String {
        area?.icon ?? project?.icon ?? "folder.fill"
    }

    private var accent: Color {
        Color(hex: colorHex)
    }

    private var sectionConfigs: [TaskSectionConfig] {
        area?.sectionConfigs ?? project?.sectionConfigs ?? []
    }

    @AppStorage("ios.listDetail.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.listDetail.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
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
                icon: icon,
                colorHex: colorHex,
                onBack: horizontalSizeClass == .compact ? { dismiss() } : nil,
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
        // Seeded with this list, so the composer opens already filed where you are. The seed is
        // recomputed from `containerSelection` on every update, so switching lists in the iPad
        // sidebar — which updates this subtree rather than rebuilding it — cannot leave the button
        // pointing at the list you just left.
        .iOSFloatingCreateTaskButton(seed: CadenceTaskComposerSeed(container: containerSelection))
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
                accent: accent
            )
        case .documents:
            iOSListNotesPanel(area: area, project: project)
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

            if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: "No tasks here yet",
                    subtitle: "Add a task above or move one here from Inbox."
                )
            } else {
                List {
                    ForEach(sectionGroups, id: \.name) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                iOSTaskListRow(task: task, showsContainer: false)
                            }
                        } header: {
                            // Same colour the board's column dot takes, so a column is the same
                            // column whichever tab you are looking at it from.
                            iOSTaskSectionHeader(title: group.name, color: sectionColor(for: group.name))
                        }
                    }

                    if showCompleted && !completedTasks.isEmpty {
                        Section {
                            ForEach(CadenceTaskSurfaceOptions.completedRows(from: completedTasks)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62, showsContainer: false)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

    private var sectionGroups: [(name: String, tasks: [AppTask])] {
        CadenceTaskQuerySupport.sectionGroups(from: activeTasks, sectionNames: sectionNames)
            .map { ($0.title, $0.tasks) }
    }

}

/// The one place this page names itself: the back control on iPhone, an identity tile in the list's
/// own colour, the context path it lives under, its name, and the control that opens the list
/// editor.
///
/// It replaces a `.navigationBarTitleDisplayMode(.large)` title *plus* a second `iOSPanelHeader`
/// inside the Tasks tab that repeated the same name and context one row lower, and it carries the
/// edit control that a `ToolbarItem` could not render on iPad.
private struct iOSListDetailHeader: View {
    let eyebrow: String
    let title: String
    let icon: String
    let colorHex: String
    var onBack: (() -> Void)? = nil
    let onEdit: () -> Void

    var body: some View {
        // The list's own `colorHex` on the tile is the only thing this header adds to the shared
        // one; the edit control rides in the single trailing slot, which is where it has to be —
        // a `ToolbarItem` cannot render it on iPad.
        iOSPageHeader(
            eyebrow: eyebrow,
            title: title.isEmpty ? "Untitled" : title,
            systemImage: icon,
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

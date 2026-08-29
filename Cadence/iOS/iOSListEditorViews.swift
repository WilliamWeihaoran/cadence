#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListEditorMode: Identifiable {
    case newArea
    case newProject
    case editArea(Area)
    case editProject(Project)

    var id: String {
        switch self {
        case .newArea: return "new-area"
        case .newProject: return "new-project"
        case .editArea(let area): return "area-\(area.id)"
        case .editProject(let project): return "project-\(project.id)"
        }
    }
}

struct iOSListEditorSheet: View {
    let mode: iOSListEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var name = ""
    @State private var details = ""
    @State private var icon = ""
    @State private var colorHex = ""
    @State private var selectedContextID = "none"
    @State private var selectedAreaID = "none"
    @State private var sectionDrafts: [CadenceSectionDraft] = [CadenceSectionDraft(name: TaskSectionDefaults.defaultName)]
    @State private var originalSectionConfigs: [TaskSectionConfig] = []
    @State private var hideEmptyDueDates = true
    /// The list's `hideSectionDueDateIfEmpty`. iOS could set a *column's* due date and had no say
    /// over whether an empty one showed, because iOS drew no column due dates at all — see T-331.
    @State private var hideEmptySectionDueDates = true
    @State private var hasProjectDueDate = false
    @State private var projectDueDate = Date()
    @State private var hasLoaded = false
    @State private var showContextPicker = false
    @State private var showAreaPicker = false
    /// Set only when `CadenceContainerWindDownSummary.requiresConfirmation` says the column has
    /// open work to settle. See `requestColumnWindDown`.
    @State private var pendingColumnWindDown: iOSColumnWindDownTarget?
    /// Set when the commit was refused. The editor stays open holding it — see `save()`.
    @State private var saveFailureNotice: String?

    private var isProjectMode: Bool {
        switch mode {
        case .newProject, .editProject:
            return true
        case .newArea, .editArea:
            return false
        }
    }

    private var isEditing: Bool {
        switch mode {
        case .editArea, .editProject:
            return true
        case .newArea, .newProject:
            return false
        }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    /// Read out of the same list the popover offers, which is the point: this used to resolve
    /// against `activeContexts` while `save()` resolved against the unfiltered query, so a project
    /// whose context had been archived showed "None" here and kept the archived context on save.
    private var contextTitle: String {
        CadenceContextPickerSupport.selectionTitle(
            from: contexts,
            selectedID: selectedContext?.id,
            noneTitle: "None"
        )
    }

    private var areaTitle: String {
        guard selectedAreaID != "none",
              let area = activeAreas.first(where: { $0.id.uuidString == selectedAreaID }),
              !area.name.isEmpty
        else { return "None" }
        return area.name
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSectionConfigs: [TaskSectionConfig] {
        CadenceSectionEditingSupport.configs(from: sectionDrafts)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveFailureNotice {
                    Section {
                        CadenceInlineFailureNotice(text: saveFailureNotice)
                    }
                    .iOSListEditorSectionChrome()
                }

                Section {
                    // Tile + name on one line, then the two strips that drive the tile — the same
                    // shape `ListEditorIdentityHeader` gives the macOS list editors.
                    HStack(spacing: 12) {
                        iOSListIconBadge(icon: normalizedIcon, colorHex: normalizedColor, size: 38)

                        TextField(isProjectMode ? "Project name" : "Area name", text: $name)
                            .font(.system(size: 17, weight: .semibold))
                    }

                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
                .iOSListEditorSectionChrome()

                Section {
                    iOSListColorStrip(selected: $colorHex)
                    iOSListIconStrip(selected: $icon, colorHex: normalizedColor)
                } header: {
                    iOSListEditorSectionHeader(title: "Appearance")
                }
                .iOSListEditorSectionChrome()

                Section {
                    HStack {
                        Text("Context")
                        Spacer()
                        iOSChoiceValueButton(title: contextTitle, color: Theme.text) {
                            showContextPicker = true
                        }
                        .popover(isPresented: $showContextPicker) {
                            iOSChoicePopoverList(
                                rows: CadenceContextPickerSupport.items(
                                    from: contexts,
                                    selectedID: selectedContext?.id,
                                    noneTitle: "None"
                                ).map { item in
                                    iOSChoiceRow(
                                        value: item.id?.uuidString ?? "none",
                                        title: item.title,
                                        systemImage: item.icon,
                                        color: item.tint,
                                        id: AnyHashable(item.id)
                                    )
                                },
                                selection: $selectedContextID,
                                isPresented: $showContextPicker
                            )
                        }
                    }

                    if isProjectMode {
                        HStack {
                            Text("Area")
                            Spacer()
                            iOSChoiceValueButton(title: areaTitle, color: Theme.text) {
                                showAreaPicker = true
                            }
                            .popover(isPresented: $showAreaPicker) {
                                iOSChoicePopoverList(
                                    rows: [iOSChoiceRow(value: "none", title: "None", color: Theme.dim)]
                                        + activeAreas.map { area in
                                            iOSChoiceRow(value: area.id.uuidString, title: area.name.isEmpty ? "Untitled Area" : area.name, color: Color(hex: area.colorHex))
                                        },
                                    selection: $selectedAreaID,
                                    isPresented: $showAreaPicker
                                )
                            }
                        }
                    }

                    if isProjectMode {
                        Toggle("Due date", isOn: $hasProjectDueDate)
                        if hasProjectDueDate {
                            HStack {
                                Text("Due")
                                    .foregroundStyle(Theme.subdued)
                                Spacer()
                                CadenceDatePicker(selection: $projectDueDate)
                            }
                        }
                    }

                    // Lives here rather than under "Columns", where it read as a column setting:
                    // `hideDueDateIfEmpty` is about the *task* rows in this list. macOS spells the
                    // two apart as "Hide empty task due date" / "Hide empty column due date".
                    Toggle("Hide empty task due dates", isOn: $hideEmptyDueDates)
                    // The column half of the same pair macOS spells "Hide empty task due date" /
                    // "Hide empty column due date". It sits beside its sibling rather than under
                    // "Columns" so the two read as one choice with two halves.
                    Toggle("Hide empty column due dates", isOn: $hideEmptySectionDueDates)
                } header: {
                    iOSListEditorSectionHeader(title: "Organize")
                }
                .iOSListEditorSectionChrome()

                Section {
                    ForEach($sectionDrafts) { $draft in
                        iOSSectionDraftRow(draft: $draft, lifecycle: lifecycle(for: draft))
                    }
                    .onDelete { offsets in
                        sectionDrafts.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        sectionDrafts.move(fromOffsets: source, toOffset: destination)
                    }

                    Button {
                        sectionDrafts.append(CadenceSectionDraft(name: ""))
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                            Text("Add Column")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                } header: {
                    iOSListEditorSectionHeader(title: "Columns")
                }
                .iOSListEditorSectionChrome()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.blue)
            .navigationTitle(isEditing ? "Edit List" : "New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
            .iOSColumnWindDown(target: $pendingColumnWindDown, perform: applyColumnWindDown)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Column lifecycle

    /// The list being edited, or `nil` for a list that does not exist yet. A column can only be
    /// wound down against a saved list, because until then it has no `TaskSectionConfig` on disk
    /// and no task can point at it.
    private var editedArea: Area? {
        if case .editArea(let area) = mode { return area }
        return nil
    }

    private var editedProject: Project? {
        if case .editProject(let project) = mode { return project }
        return nil
    }

    /// The column **as the model has it**, matched by `uuid` — deliberately not the draft. The
    /// settle walks `AppTask.resolvedSectionName` against the column's name, so a column renamed in
    /// this sheet but not yet saved must still be counted and settled under the name its tasks
    /// actually carry.
    private func liveConfig(for draft: CadenceSectionDraft) -> TaskSectionConfig? {
        let configs = editedArea?.sectionConfigs ?? editedProject?.sectionConfigs ?? []
        return configs.first { $0.uuid == draft.id }
    }

    /// `nil` — no Complete, no Archive — for two columns, and the second reason is a model
    /// invariant rather than a taste.
    ///
    /// A column added during this edit has no `TaskSectionConfig` on disk and no task can point at
    /// it. And the **Default** column cannot be wound down at all: `normalizedSectionConfigs`
    /// forces `isCompleted = false` and `isArchived = false` on it on every read *and* every write,
    /// so the flag would be discarded while the settle underneath it still cancelled or finished
    /// every task in the column — a confirmation stating a number and then leaving the column
    /// visibly Active. macOS gates its Archive item the same way (`KanbanColumnSupportViews`,
    /// `if !section.isDefault`); its *completion* item is not gated, which is the same defect one
    /// door down (`docs/TODO.md` T-268).
    private func lifecycle(for draft: CadenceSectionDraft) -> iOSSectionRowLifecycle? {
        guard let config = liveConfig(for: draft), !config.isDefault else { return nil }
        return iOSSectionRowLifecycle(
            isCompleted: config.isCompleted,
            isArchived: config.isArchived,
            complete: { requestColumnWindDown(.init(config: config, area: editedArea, project: editedProject, action: .complete)) },
            archive: { requestColumnWindDown(.init(config: config, area: editedArea, project: editedProject, action: .archive)) },
            reopen: { reopenColumn(config) }
        )
    }

    /// The one column wind-down decision on iOS.
    ///
    /// Archiving a column cancels its remaining active tasks and completing one marks them done —
    /// macOS has done both all along, and T-247 is iOS catching up rather than a new behaviour.
    /// That makes this an irreversible settlement wearing a reversible word, so it is confirmed
    /// *when there is something to settle* and performed immediately when there is not;
    /// `CadenceContainerWindDownSummary.requiresConfirmation` owns that test, exactly as it does
    /// for a whole list.
    private func requestColumnWindDown(_ target: iOSColumnWindDownTarget) {
        guard target.summary.requiresConfirmation else {
            applyColumnWindDown(target)
            return
        }
        pendingColumnWindDown = target
    }

    /// **Applied to the model now, not drafted for Save**, which is the shape half of T-247. A
    /// draft flag committed with a rename and a colour change has no moment at which a count could
    /// be stated, and it makes one gesture mean two things: flip-and-flip-back settles nothing,
    /// flip-and-save settles twelve tasks forever. The draft is then brought into step so the row
    /// reads truthfully and so the sheet's own Save cannot write the flag back off.
    private func applyColumnWindDown(_ target: iOSColumnWindDownTarget) {
        modelContext.windDownColumn(target)
        updateDraft(target.config.uuid) { draft in
            switch target.action {
            case .archive: draft.isArchived = true
            case .complete: draft.isCompleted = true
            }
        }
    }

    private func reopenColumn(_ config: TaskSectionConfig) {
        modelContext.reopenColumn(config, area: editedArea, project: editedProject)
        updateDraft(config.uuid) { draft in
            draft.isArchived = false
            draft.isCompleted = false
        }
    }

    private func updateDraft(_ id: UUID, _ mutate: (inout CadenceSectionDraft) -> Void) {
        guard let index = sectionDrafts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sectionDrafts[index])
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .newArea:
            name = ""
            details = ""
            icon = "folder.fill"
            colorHex = CadenceColorPalette.areaDefault
            hasProjectDueDate = false
            projectDueDate = Date()
            hideEmptySectionDueDates = true
        case .newProject:
            name = ""
            details = ""
            icon = "checklist"
            colorHex = CadenceColorPalette.projectDefault
            hasProjectDueDate = false
            projectDueDate = Date()
            hideEmptySectionDueDates = true
        case .editArea(let area):
            name = area.name
            details = area.desc
            icon = area.icon
            colorHex = area.colorHex
            selectedContextID = area.context?.id.uuidString ?? "none"
            originalSectionConfigs = area.sectionConfigs
            sectionDrafts = CadenceSectionEditingSupport.drafts(from: originalSectionConfigs)
            hideEmptyDueDates = area.hideDueDateIfEmpty
            hideEmptySectionDueDates = area.hideSectionDueDateIfEmpty
        case .editProject(let project):
            name = project.name
            details = project.desc
            icon = project.icon
            colorHex = project.colorHex
            selectedContextID = project.context?.id.uuidString ?? "none"
            selectedAreaID = project.area?.id.uuidString ?? "none"
            originalSectionConfigs = project.sectionConfigs
            sectionDrafts = CadenceSectionEditingSupport.drafts(from: originalSectionConfigs)
            hideEmptyDueDates = project.hideDueDateIfEmpty
            hideEmptySectionDueDates = project.hideSectionDueDateIfEmpty
            if let date = DateFormatters.date(from: project.dueDate) {
                projectDueDate = date
                hasProjectDueDate = true
            } else {
                projectDueDate = Date()
                hasProjectDueDate = false
            }
        }
    }

    /// T-321: every branch below wrote, ran `try? modelContext.save()` and dismissed, so the
    /// editor closed the same way whether or not the store took the change — and the two edit
    /// branches re-point tasks *before* that save, so a swallowed failure left the reassignment
    /// half-applied with the editor closed over it.
    ///
    /// **The undo differs by branch, and neither of them is `rollback()`.** A creation deletes
    /// what it inserted (`commitInsert`). An edit reaches further than its own fields —
    /// `applySectionConfigEdits` rewrites the column blob and `reassignTasks` walks
    /// `AppTask.sectionName` and `AppTask.context` across every task in the list — so it hands all
    /// of that to `CadenceListEditSnapshot`, which is also where the reason a rollback would *not*
    /// have worked is written down.
    ///
    /// The sheet's `@State` still holds everything the user typed either way, so a refused save
    /// leaves the editor open and intact rather than empty.
    private func save() {
        do {
            switch mode {
            case .newArea:
                let area = Area(name: trimmedName, context: selectedContext, colorHex: normalizedColor, icon: normalizedIcon)
                area.desc = details
                area.order = nextAreaOrder()
                area.sectionConfigs = normalizedSectionConfigs
                area.hideDueDateIfEmpty = hideEmptyDueDates
                area.hideSectionDueDateIfEmpty = hideEmptySectionDueDates
                modelContext.insert(area)
                try CadencePendingChangePersistence.commitInsert(of: area, in: modelContext)
            case .newProject:
                let project = Project(name: trimmedName, context: selectedContext, area: selectedArea, colorHex: normalizedColor)
                project.desc = details
                project.icon = normalizedIcon
                project.order = nextProjectOrder()
                project.sectionConfigs = normalizedSectionConfigs
                project.hideDueDateIfEmpty = hideEmptyDueDates
                project.hideSectionDueDateIfEmpty = hideEmptySectionDueDates
                project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
                modelContext.insert(project)
                try CadencePendingChangePersistence.commitInsert(of: project, in: modelContext)
            case .editArea(let area):
                // Snapshotted before the first write, and it holds the tasks as well as the list:
                // `reassignTasks` below re-points every one of them. See `CadenceListEditSnapshot`
                // for why this is a snapshot rather than `modelContext.rollback()`.
                let undo = CadenceListEditSnapshot(area, tasks: area.tasks ?? [])
                area.name = trimmedName
                area.desc = details
                area.icon = normalizedIcon
                area.colorHex = normalizedColor
                area.context = selectedContext
                // The columns are merged *before* the tasks are re-pointed, because the merge is what
                // decides which columns actually survive — a column another device deleted while this
                // sheet was open is gone from the result even though the drafts still list it, and its
                // tasks have to follow (`docs/TODO.md` T-358).
                area.applySectionConfigEdits(base: originalSectionConfigs, edited: normalizedSectionConfigs)
                reassignTasks(in: area.tasks ?? [], area: area)
                area.hideDueDateIfEmpty = hideEmptyDueDates
                area.hideSectionDueDateIfEmpty = hideEmptySectionDueDates
                try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
            case .editProject(let project):
                let undo = CadenceListEditSnapshot(project, tasks: project.tasks ?? [])
                project.name = trimmedName
                project.desc = details
                project.icon = normalizedIcon
                project.colorHex = normalizedColor
                project.context = selectedContext
                project.area = selectedArea
                project.applySectionConfigEdits(base: originalSectionConfigs, edited: normalizedSectionConfigs)
                reassignTasks(in: project.tasks ?? [], project: project)
                project.hideDueDateIfEmpty = hideEmptyDueDates
                project.hideSectionDueDateIfEmpty = hideEmptySectionDueDates
                project.dueDate = hasProjectDueDate ? DateFormatters.dateKey(from: projectDueDate) : ""
                try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
            }
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    /// Re-points what this editor just invalidated on the tasks already in the list.
    ///
    /// Two copies go stale, for the same reason: SwiftData re-points relationships, not the
    /// denormalized copies beside them.
    ///
    /// A renamed or removed column leaves `AppTask.sectionName` pointing at a name no column has
    /// any more — nothing re-points a plain string. macOS's kanban column calls `moveTasks`; this
    /// is the same rule, applied to every column the editor changed at once.
    ///
    /// A changed context — or, for a project, a changed area — leaves `AppTask.context` pointing
    /// at the context the list *used* to be in. The list moved and its tasks did not, so they
    /// stayed in the list and dropped out of the context (T-293). Pass the list back in so the
    /// shared rule can re-derive it; omitting it silently restores that bug.
    private func reassignTasks(in tasks: [AppTask], area: Area? = nil, project: Project? = nil) {
        let surviving = area?.sectionConfigs ?? project?.sectionConfigs ?? normalizedSectionConfigs
        let moves = CadenceSectionConfigMerge.sectionNameMoves(base: originalSectionConfigs, merged: surviving)
        CadenceSectionEditingSupport.applySectionNameChanges(
            renames: moves.renames,
            removedNames: moves.removedNames,
            to: tasks
        )
        CadenceTaskMutationSupport.reassignInheritedContext(in: tasks, area: area, project: project)
    }

    private var selectedContext: Context? {
        guard let id = UUID(uuidString: selectedContextID) else { return nil }
        return contexts.first { $0.id == id }
    }

    private var selectedArea: Area? {
        guard let id = UUID(uuidString: selectedAreaID) else { return nil }
        return areas.first { $0.id == id }
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isProjectMode ? "checklist" : "folder.fill"
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return isProjectMode ? CadenceColorPalette.projectDefault : CadenceColorPalette.areaDefault
        }
        return trimmed
    }

    private func nextAreaOrder() -> Int {
        (areas.map(\.order).max() ?? -1) + 1
    }

    private func nextProjectOrder() -> Int {
        (projects.map(\.order).max() ?? -1) + 1
    }
}

/// One kanban column in the list editor.
///
/// iOS read `sectionConfigs` in no production file at all — the editor was a newline-separated
/// list of names, so a column's colour, due date, completion and archived flag were invisible
/// here and a rename silently discarded all four. These are the same four properties macOS's
/// column editor exposes.
///
/// The 7pt dot + name is the board's own column header in miniature, so a column is recognisable
/// between the editor and the board.
///
/// **Completed and Archived are not drafted here, and that is T-247.** They were two `Toggle`s on
/// the draft, saved with the rename and the colour and settling nothing, while macOS cancelled or
/// finished the column's remaining active tasks on the same transitions. They are actions now,
/// handed in whole as `iOSSectionRowLifecycle` and confirmed by the host when there is open work —
/// `nil` for a column added during this edit, which has nothing on the model to act on.
private struct iOSSectionDraftRow: View {
    @Binding var draft: CadenceSectionDraft
    let lifecycle: iOSSectionRowLifecycle?
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: draft.colorHex))
                    .frame(width: 8, height: 8)

                TextField("Column name", text: $draft.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .frame(minHeight: 32)

            iOSSectionColorPicker(selectedHex: $draft.colorHex)

            Toggle("Due date", isOn: $hasDueDate)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.subdued)

            if hasDueDate {
                HStack {
                    Text("Due")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                    Spacer()
                    CadenceDatePicker(selection: $dueDate)
                }
            }

            if let lifecycle {
                lifecycleControls(lifecycle)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            hasDueDate = !draft.dueDate.isEmpty
            dueDate = DateFormatters.date(from: draft.dueDate) ?? Date()
        }
        .onChange(of: hasDueDate) { _, isOn in
            draft.dueDate = isOn ? DateFormatters.dateKey(from: dueDate) : ""
        }
        .onChange(of: dueDate) { _, newValue in
            guard hasDueDate else { return }
            draft.dueDate = DateFormatters.dateKey(from: newValue)
        }
    }

    /// State first, then only the transitions available from it. An archived column offers one
    /// button, because archiving it again is not a thing and completing it after the fact would be
    /// a second settle over work already cancelled.
    @ViewBuilder
    private func lifecycleControls(_ lifecycle: iOSSectionRowLifecycle) -> some View {
        HStack(spacing: 6) {
            Text("Status")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.subdued)
            Spacer(minLength: 0)
            Text(lifecycle.stateLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor(lifecycle))
        }

        HStack(spacing: 8) {
            if lifecycle.isArchived {
                iOSActionButton(
                    title: "Unarchive Column",
                    systemImage: "tray.and.arrow.up.fill",
                    size: .compact,
                    action: lifecycle.reopen
                )
            } else {
                if lifecycle.isCompleted {
                    iOSActionButton(
                        title: "Reopen",
                        systemImage: "arrow.uturn.backward",
                        size: .compact,
                        action: lifecycle.reopen
                    )
                } else {
                    iOSActionButton(
                        title: "Complete",
                        systemImage: "checkmark.circle",
                        size: .compact,
                        tint: Theme.green,
                        action: lifecycle.complete
                    )
                }

                iOSActionButton(
                    title: "Archive",
                    systemImage: "archivebox",
                    role: .destructive,
                    size: .compact,
                    action: lifecycle.archive
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func statusColor(_ lifecycle: iOSSectionRowLifecycle) -> Color {
        if lifecycle.isArchived { return Theme.amber }
        if lifecycle.isCompleted { return Theme.green }
        return Theme.muted
    }
}

/// The section palette is `CadenceColorPalette.offeredSectionColors(for:)` — the same swatch menu
/// the Mac's kanban column editor draws, for the same `TaskSectionConfig.colorHex` field.
///
/// It was `[TaskSectionDefaults.defaultColorHex] + TagSupport.colorOptions`, nine hues overlapping
/// the Mac's eight in exactly one, so a column tinted `#e671b8` on the phone opened on the Mac
/// wearing a hue the Mac could not offer (T-261). Borrowing the **tag** palette was the deeper
/// problem: its own doc comment says tags are a separate palette with a separate job, so a hue
/// decision about tags silently redrew this row — and three of the eight it lent (`#ffb84d`,
/// `#5aa2ff`, `#9e8cff`) are the pre-T-166 drifted near-copies of `Theme`'s amber, blue and purple.
///
/// The keep-the-stored-value rule comes with it: a column already wearing one of the tag hues still
/// shows a selected swatch and keeps its colour, because `offeredSectionColors(for:)` appends it.
private struct iOSSectionColorPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CadenceColorPalette.offeredSectionColors(for: selectedHex), id: \.self) { option in
                    iOSListColorSwatch(
                        hex: option,
                        isSelected: CadenceColorPalette.matches(option, selectedHex)
                    ) {
                        selectedHex = option
                    }
                }
            }
        }
    }
}

// MARK: - Identity strips

/// A hex text field is not a colour picker. This is the same swatch strip `ListEditorColorStrip`
/// gives the macOS list editors, at touch size.
private struct iOSListColorStrip: View {
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CadenceColorPalette.offeredColors(for: selected), id: \.self) { hex in
                    iOSListColorSwatch(hex: hex, isSelected: CadenceColorPalette.matches(hex, selected)) {
                        selected = hex
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }
}

private struct iOSListColorSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.text, lineWidth: 1.5)
                        .padding(-4)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Selected colour" : "Use this colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Same idea for the glyph: the field used to want a raw SF Symbol name typed in, which is a
/// developer's input, and a typo silently fell back to the default icon on save.
private struct iOSListIconStrip: View {
    @Binding var selected: String
    let colorHex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CadenceIconPalette.offeredIcons(for: selected), id: \.self) { icon in
                    let isSelected = icon == selected
                    Button {
                        selected = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? Color(hex: colorHex) : Theme.dim)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                    .fill(isSelected ? Theme.surfaceHighlight : Color.clear)
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Form chrome

/// A `Form` section header is UIKit's own: system grey small-caps. This is the shared eyebrow.
private struct iOSListEditorSectionHeader: View {
    let title: String

    var body: some View {
        SectionEyebrowLabel(text: title)
            .textCase(nil)
            .padding(.bottom, 2)
    }
}

private extension View {
    /// `Form` rows sit on `secondarySystemGroupedBackground` — a UIKit grey that ignores the
    /// palette entirely and reads a full step lighter than every other surface in the app.
    func iOSListEditorSectionChrome() -> some View {
        listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.borderSubtle)
    }
}
#endif

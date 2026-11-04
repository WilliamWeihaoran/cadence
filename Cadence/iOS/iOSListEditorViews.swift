#if os(iOS)
import EventKit
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
    /// The group a `.newArea` / `.newProject` opens on, when something already knew one — today
    /// that is a `+` dragged onto a context group in the iPad sidebar (T-2054). It is the iOS
    /// spelling of `CreateListSheet(context:)`'s argument and carries that type's rule: **the
    /// context this sheet opens on, not the context it creates in.** `selectedContextID` is the
    /// sheet's one answer after `load()`, the picker states and changes it, and `nil` — every
    /// existing call site — opens on "No context" exactly as before.
    var seededContext: Context?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// [[T-8562]]: read for `isAuthorized` and the calendar lists only. Nothing here requests
    /// access; with none granted the Apple Calendar row is not drawn at all.
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// [[T-8562]], T-624: the identifiers this device has seen EventKit carry -- the evidence the
    /// macOS `ListEditorCalendarRow` reads, so a synced link another device made is not called gone.
    @AppStorage(CadenceCalendarLinkObservations.observedCalendarIDsKey) private var observedCalendarIDsRaw = ""
    @State private var name = ""
    @State private var details = ""
    @State private var icon = ""
    @State private var colorHex = ""
    @State private var selectedContextID = "none"
    @State private var selectedAreaID = "none"
    @State private var createsProject = false
    @State private var sectionDrafts: [CadenceSectionDraft] = [CadenceSectionDraft(name: TaskSectionDefaults.defaultName)]
    @State private var originalSectionConfigs: [TaskSectionConfig] = []
    @State private var hideEmptyDueDates = true
    /// The list's `hideSectionDueDateIfEmpty`. iOS could set a *column's* due date and had no say
    /// over whether an empty one showed, because iOS drew no column due dates at all — see T-331.
    @State private var hideEmptySectionDueDates = true
    /// [[T-9804]]: the project's due date exactly as `save()` stores it -- "" for none. Whether the
    /// project is dated is this value alone; there is no separate "Due date" switch to disagree with it.
    @State private var projectDueDateKey = ""
    /// Where the picker opens while the project is undated, and the last day picked. Never read as
    /// the due date on its own: a cleared project still holds the cleared day here.
    @State private var projectDueDate = Date()
    /// [[T-8562]]: the list's `linkedCalendarID` as Save will write it, "" for none.
    @State private var selectedCalendarID = ""
    @State private var showCalendarPicker = false
    /// [[T-8562]]: the editor's Complete / Archive, awaiting the shared confirmation. Set only
    /// when `CadenceContainerWindDownSummary.requiresConfirmation` says there is work to settle.
    @State private var pendingListWindDown: iOSListWindDownTarget?
    /// [[T-8562]]: the editor's Delete, awaiting the shared cascade confirmation.
    @State private var pendingListDeletion: iOSListDeletionTarget?
    /// [[T-8562]]: the lifecycle move a Status / Archive row hands the one `save()` it calls. Set
    /// immediately before that call and cleared by it; `nil` for the Save button.
    @State private var lifecycleStep: iOSListEditorLifecycleStep?
    @State private var hasLoaded = false
    /// [[T-5174]]: the draft as `load()` left it, against which a swipe-down is refused.
    @State private var openedDraft: CadenceListEditorDraftSnapshot?
    @State private var showContextPicker = false
    @State private var showAreaPicker = false
    /// Set only when `CadenceContainerWindDownSummary.requiresConfirmation` says the column has
    /// open work to settle. See `requestColumnWindDown`.
    @State private var pendingColumnWindDown: iOSColumnWindDownTarget?
    /// A saved column swiped away, awaiting "Delete Column?" ([[T-8564]]). The row stays until the
    /// answer: Delete drafts the removal (Save still commits it, Cancel on the sheet still undoes
    /// it), and the alert's own Cancel leaves the column where it was.
    @State private var pendingColumnDeletion: CadenceSectionDraft?
    /// Set when the commit was refused. The editor stays open holding it — see `save()`.
    @State private var saveFailureNotice: String?
    /// Set when *this editor* declined a column name rather than the store declining the write
    /// (T-1053). Separate from `saveFailureNotice` for the reason `KanbanColumnRenameRefusal`
    /// gives: "try again" is the wrong advice for a name that will be refused every time.
    @State private var nameRefusalNotice: String?

    private var resolvedMode: iOSListEditorMode {
        guard !isEditing else { return mode }
        return createsProject ? .newProject : .newArea
    }

    private var isProjectMode: Bool {
        switch resolvedMode {
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

    /// Read out of the same list the popover offers, which is the point: this used to resolve
    /// against `activeContexts` while `save()` resolved against the unfiltered query, so a project
    /// whose context had been archived showed "None" here and kept the archived context on save.
    private var contextTitle: String {
        CadenceContextPickerSupport.selectionTitle(
            from: contexts,
            selectedID: selectedContext?.id,
            noneTitle: Self.contextNoneTitle
        )
    }

    /// [[T-8561]]: macOS's `ListEditorContextRow.noneTitle`, word for word. This row and its
    /// popover said "None" while the Mac's list editors, its context picker and this sheet's own
    /// doc comment on `seededContext` all say "No context" — the same field reading two ways on
    /// one app ([[T-8201]]).
    static let contextNoneTitle = "No context"

    /// [[T-8561]]: the sheet names the kind of list it edits, as macOS's `EditAreaSheet` /
    /// `EditProjectSheet` do and as the "Edit Area" / "Edit Project" menu row that opens it
    /// already does. It said "Edit List" under a menu that had just said "Edit Area".
    private var sheetTitle: String {
        guard isEditing else { return "New List" }
        return isProjectMode ? "Edit Project" : "Edit Area"
    }

    /// [[T-8562]]: the one field list the macOS sheets read too. iOS draws every field in it.
    private var fields: [CadenceListEditorField] {
        CadenceListEditorFieldSet.fields(
            kind: isProjectMode ? .project : .area,
            isEditing: isEditing,
            isCalendarAccessGranted: calendarManager.isAuthorized
        )
    }

    /// [[T-8562]]: the same `CadenceCalendarLink` macOS's `ListEditorCalendarRow` builds, so the
    /// row's value and the picker's offer come off one decision on both platforms (T-441, T-464),
    /// with `.synced` evidence because `linkedCalendarID` is CloudKit-synced (T-624).
    private var calendarLink: CadenceCalendarLink {
        CadenceCalendarLink(
            linkedCalendarID: selectedCalendarID,
            allCalendars: calendarManager.allCalendars,
            visibleCalendars: calendarManager.availableCalendars,
            evidence: .synced(
                observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(
                    from: observedCalendarIDsRaw
                )
            )
        )
    }

    /// The Status row's value, worded by the shared field set as the Mac's is.
    private var statusLabel: String {
        if let editedArea { return CadenceListEditorFieldSet.statusLabel(editedArea.status) }
        if let editedProject { return CadenceListEditorFieldSet.statusLabel(editedProject.status) }
        return CadenceListEditorFieldSet.statusLabel(AreaStatus.active)
    }

    private var editedIsDone: Bool {
        editedArea?.isDone ?? editedProject?.isDone ?? false
    }

    private var editedIsArchived: Bool {
        editedArea?.isArchived ?? editedProject?.isArchived ?? false
    }

    private var listNoun: String {
        isProjectMode ? "Project" : "Area"
    }

    /// The same rule as `contextTitle`, one row down, and for the same reason (T-488): this used to
    /// resolve against `areas.filter(\.isActive)` while `save()` resolved `selectedArea` against
    /// the unfiltered query, so a project whose area had been completed or archived read "None"
    /// here and wrote the inactive area back on Save. Both halves take `areas` now, so the label
    /// and the saved value cannot name two different things.
    private var areaTitle: String {
        CadenceAreaPickerSupport.selectionTitle(
            from: areas,
            selectedID: selectedArea?.id,
            noneTitle: "None"
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentDraft: CadenceListEditorDraftSnapshot {
        CadenceListEditorDraftSnapshot(
            name: name,
            details: details,
            icon: icon,
            colorHex: colorHex,
            selectedContextID: selectedContextID,
            selectedAreaID: selectedAreaID,
            dueDateKey: projectDueDateKey,
            hideEmptyDueDates: hideEmptyDueDates,
            hideEmptySectionDueDates: hideEmptySectionDueDates,
            columns: sectionDrafts.map { CadenceListEditorDraftSnapshot.Column($0) },
            linkedCalendarID: selectedCalendarID
        )
    }

    private var normalizedSectionConfigs: [TaskSectionConfig] {
        CadenceSectionEditingSupport.configs(from: sectionDrafts)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        iOSSegmentedChoice(
                            options: [(false, "Area"), (true, "Project")],
                            selection: $createsProject
                        )
                        .accessibilityLabel("List type")
                    }
                    .iOSListEditorSectionChrome()
                }

                if let editorFailureNotice {
                    Section {
                        CadenceInlineFailureNotice(text: editorFailureNotice)
                    }
                    .iOSListEditorSectionChrome()
                }

                Section {
                    // Tile + name on one line, then the two strips that drive the tile — the same
                    // shape `ListEditorIdentityHeader` gives the macOS list editors.
                    HStack(spacing: 12) {
                        iOSListIconBadge(icon: normalizedIcon, colorHex: normalizedColor, size: 38)

                        // [[T-10045]]: Return saves, as it confirms the Mac list sheets
                        // ([[T-7266]]); blank does nothing, as the disabled Save does.
                        TextField(isProjectMode ? CadenceListVocabularyCopy.projectNamePlaceholder : CadenceListVocabularyCopy.areaNamePlaceholder, text: $name)
                            .font(.system(size: 17, weight: .semibold))
                            .submitLabel(.done)
                            .onSubmit(submitName)
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
                                    noneTitle: Self.contextNoneTitle
                                ).map { item in
                                    iOSChoiceRow(
                                        value: item.id?.uuidString ?? "none",
                                        title: item.title,
                                        systemImage: item.icon,
                                        color: item.tint
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
                                    rows: CadenceAreaPickerSupport.items(
                                        from: areas,
                                        selectedID: selectedArea?.id,
                                        noneTitle: "None"
                                    ).map { item in
                                        // The canonical area glyph, not the area's own `icon`
                                        // ([[T-10145]], [[T-8553]]): a chooser speaks one
                                        // per-kind vocabulary. Read at this call site because
                                        // `CadencePickerItem` also feeds the Context picker above.
                                        iOSChoiceRow(
                                            value: item.id?.uuidString ?? "none",
                                            title: item.title,
                                            systemImage: item.isNone ? nil : CadenceListKindIcon.area,
                                            color: item.tint
                                        )
                                    },
                                    selection: $selectedAreaID,
                                    isPresented: $showAreaPicker
                                )
                            }
                        }
                    }

                    // [[T-9804]]: the column row's one placeholder picker, not a "Due date" switch
                    // plus a picker. It reads "No due date" while empty, a pick sets the date and
                    // Clear unsets it. Every pick commits through the setter rather than `.onChange`:
                    // after a clear the bound day is still the cleared one, and picking it again
                    // changes nothing.
                    if isProjectMode {
                        HStack {
                            Text("Due date")
                                .foregroundStyle(Theme.subdued)
                            Spacer()
                            CadenceDatePicker(
                                selection: Binding(
                                    get: { projectDueDate },
                                    set: { newValue in
                                        projectDueDate = newValue
                                        projectDueDateKey = DateFormatters.dateKey(from: newValue)
                                    }
                                ),
                                placeholder: projectDueDateKey.isEmpty ? CadenceBoardColumnDueDatePlan.emptyLabel : nil,
                                showsClear: !projectDueDateKey.isEmpty,
                                onClear: { projectDueDateKey = "" }
                            )
                        }
                    }

                    // [[T-8562]]: the Apple Calendar link macOS's edit sheets carry. Gated on
                    // access already granted -- the row never asks for it.
                    if fields.contains(.appleCalendar) {
                        calendarRow
                    }

                    // Lives here rather than under "Columns", where it read as a column setting:
                    // `hideDueDateIfEmpty` is about the *task* rows in this list.
                    Toggle(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle, isOn: $hideEmptyDueDates)
                    // The column half of the same pair. It sits beside its sibling rather than
                    // under "Columns" so the two read as one choice with two halves.
                    Toggle(CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle, isOn: $hideEmptySectionDueDates)
                } header: {
                    iOSListEditorSectionHeader(title: "Organize")
                }
                .iOSListEditorSectionChrome()

                Section {
                    ForEach($sectionDrafts) { $draft in
                        iOSSectionDraftRow(draft: $draft, lifecycle: lifecycle(for: draft))
                            // T-5835: Default cannot be removed. A swiped-away Default came back
                            // on Save, synthesised by `normalizedSectionConfigs`, in the default
                            // grey and with no due date — a delete that only erased its settings.
                            .deleteDisabled(draft.isDefaultColumn)
                    }
                    .onDelete(perform: requestColumnDeletion)
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
                        // [[T-9483]]: the whole form row. Under `.plain` a row without a hit
                        // shape took a tap only on the glyph and the two words.
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    iOSListEditorSectionHeader(title: "Columns")
                }
                .iOSListEditorSectionChrome()

                if fields.contains(.status) {
                    lifecycleSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.blue)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // [[T-10046]]: Escape on an iPad keyboard cancels, as the Mac's list sheets'
                    // Cancel does ([[T-7266]]).
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // [[T-8563]] (a): a new list is created, an existing one saved.
                    Button(isEditing ? "Save" : CadenceListVocabularyCopy.createActionTitle) {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: createsProject) { oldValue, newValue in
                guard !isEditing else { return }
                let oldIcon = oldValue ? "checklist" : "folder.fill"
                let oldColor = oldValue ? CadenceColorPalette.projectDefault : CadenceColorPalette.areaDefault
                if icon == oldIcon { icon = newValue ? "checklist" : "folder.fill" }
                if colorHex == oldColor {
                    colorHex = newValue ? CadenceColorPalette.projectDefault : CadenceColorPalette.areaDefault
                }
                showAreaPicker = false
            }
            .iOSColumnWindDown(target: $pendingColumnWindDown, perform: applyColumnWindDown)
            .iOSListWindDown(target: $pendingListWindDown, perform: performListWindDown)
            .iOSListDeletion(target: $pendingListDeletion, onDeleted: { dismiss() })
            .alert(
                CadenceSectionEditingSupport.columnDeleteConfirmationTitle,
                isPresented: Binding(
                    get: { pendingColumnDeletion != nil },
                    set: { if !$0 { pendingColumnDeletion = nil } }
                ),
                presenting: pendingColumnDeletion
            ) { draft in
                Button("Delete", role: .destructive) {
                    sectionDrafts.removeAll { $0.id == draft.id }
                    pendingColumnDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingColumnDeletion = nil }
            } message: { draft in
                Text(CadenceSectionEditingSupport.columnDeleteConfirmationMessage(
                    columnName: CadenceSectionEditingSupport.deletionConfirmationName(for: draft)
                ))
            }
            // [[T-5174]]: Save is the only write, so an unsaved name, colour or column edit lives
            // nowhere but this sheet's state; a swipe that dropped it said nothing. (b) brought the
            // NEW-list mode under the same rule — a half-typed list is typed text too. Every
            // presenter is `.sheet`, never `.popover` — [[T-3240]] measured this modifier pushing
            // an iPad popover out of its popover.
            .interactiveDismissDisabled(
                CadenceSheetDismissGuard.blocksSwipe(opened: openedDraft, current: currentDraft)
            )
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Apple Calendar (T-8562)

    /// The row's offer: Cadence's visible calendars plus the one already linked when it is hidden,
    /// off the same `CadenceCalendarLink` the value is read from, so the row can never name a
    /// calendar the menu under it does not offer (T-464).
    private var calendarChoiceRows: [iOSChoiceRow<String>] {
        let link = calendarLink
        let none = iOSChoiceRow(
            value: "",
            title: CadenceCalendarLinkRowState.unlinkedText,
            systemImage: "circle",
            color: Theme.dim
        )
        return [none] + link.pickableCalendars(from: calendarManager.allCalendars).map { calendar in
            iOSChoiceRow(
                value: calendar.calendarIdentifier,
                title: link.pickerLabel(title: calendar.title, calendarID: calendar.calendarIdentifier),
                systemImage: "circle.fill",
                color: Color(cgColor: calendar.cgColor)
            )
        }
    }

    private var calendarRow: some View {
        let state = calendarLink.rowState
        return HStack {
            Text(CadenceAppleCalendarNaming.integrationSectionTitle)
            Spacer()
            iOSChoiceValueButton(title: state.valueText, color: state.isSet ? Theme.text : Theme.dim) {
                showCalendarPicker = true
            }
            .popover(isPresented: $showCalendarPicker) {
                iOSChoicePopoverList(
                    rows: calendarChoiceRows,
                    selection: $selectedCalendarID,
                    isPresented: $showCalendarPicker
                )
            }
        }
    }

    // MARK: - List lifecycle (T-8562)

    /// Status, Archive and Delete, the three rows macOS's edit sheets carry. Every one goes through
    /// the Lists page's own machinery -- `iOSListWindDownTarget` and its confirmation for the two
    /// wind-downs, `iOSListDeletionTarget` and its cascade confirmation for Delete -- so the editor
    /// cannot settle or delete a list any differently from the row's context menu.
    private var lifecycleSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Menu {
                    Button {
                        reopenList()
                    } label: {
                        Label("Active", systemImage: editedIsDone || editedIsArchived ? "circle" : "checkmark")
                    }
                    .disabled(!(editedIsDone || editedIsArchived))
                    Button {
                        requestListWindDown(.complete)
                    } label: {
                        Label("Completed", systemImage: editedIsDone ? "checkmark" : iOSListWindDownAction.complete.icon)
                    }
                    .disabled(editedIsDone)
                } label: {
                    Text(statusLabel)
                        .foregroundStyle(Theme.text)
                }
            }

            if fields.contains(.archive) {
                Button {
                    if editedIsArchived { reopenList() } else { requestListWindDown(.archive) }
                } label: {
                    Label(
                        editedIsArchived ? "Unarchive \(listNoun)" : "Archive \(listNoun)",
                        systemImage: editedIsArchived ? "tray.and.arrow.up" : iOSListWindDownAction.archive.icon
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
            }

            if fields.contains(.delete), let target = deletionTarget {
                // The context menu's own row, so the title and glyph are spelled once.
                iOSListDeleteMenuButton(target: target) { pendingListDeletion = $0 }
                    .foregroundStyle(Theme.red)
            }
        } header: {
            iOSListEditorSectionHeader(title: "Status")
        }
        .iOSListEditorSectionChrome()
    }

    private var deletionTarget: iOSListDeletionTarget? {
        if let editedArea { return .area(editedArea) }
        if let editedProject { return .project(editedProject) }
        return nil
    }

    private func windDownTarget(_ action: iOSListWindDownAction) -> iOSListWindDownTarget? {
        if let editedArea { return .area(editedArea, action) }
        if let editedProject { return .project(editedProject, action) }
        return nil
    }

    /// The Lists page's rule: confirmed when there is open work to settle, done at once when not.
    private func requestListWindDown(_ action: iOSListWindDownAction) {
        guard let target = windDownTarget(action) else { return }
        guard target.summary.requiresConfirmation else {
            performListWindDown(target)
            return
        }
        pendingListWindDown = target
    }

    /// As macOS's `apply(_:)` does, the pending field edits are written first -- a lifecycle move
    /// closes the editor, and the dismissal must not throw them away. So the move is handed to
    /// `save()`, which settles it after its own commit and not at all when that commit is refused.
    private func performListWindDown(_ target: iOSListWindDownTarget) {
        lifecycleStep = .windDown(target)
        save()
    }

    /// Back to Active. Reopening settles nothing, so it is not a wind-down: `save()` writes the
    /// status inside the edit's own commit, whose snapshot already holds it for the undo.
    private func reopenList() {
        lifecycleStep = .reopen
        save()
    }

    // MARK: - Column lifecycle

    /// **A swipe on a saved column asks first, in the Mac's words** ([[T-8564]]). The Mac board's
    /// column popover confirms "Delete Column?" and says the cards go to Default; this swipe used
    /// to drop the row silently and move the cards on Save. A column added during this edit holds
    /// no card and goes at once, as it always did.
    private func requestColumnDeletion(at offsets: IndexSet) {
        let swiped = offsets.map { sectionDrafts[$0] }
        let confirmed = swiped.filter { CadenceSectionEditingSupport.deletionNeedsConfirmation($0) }
        let immediate = Set(swiped.filter { !CadenceSectionEditingSupport.deletionNeedsConfirmation($0) }.map(\.id))
        sectionDrafts.removeAll { immediate.contains($0.id) }
        if let first = confirmed.first {
            pendingColumnDeletion = first
        }
    }

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

    /// `selectedContextID`'s spelling of `seededContext`. The picker speaks `"none"` rather than
    /// an empty string, so an absent seed has to resolve to that one word and not to `""`.
    private var seededContextValue: String {
        seededContext?.id.uuidString ?? "none"
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .newArea:
            createsProject = false
            name = ""
            details = ""
            icon = "folder.fill"
            colorHex = CadenceColorPalette.areaDefault
            projectDueDateKey = ""
            projectDueDate = Date()
            hideEmptySectionDueDates = true
            selectedContextID = seededContextValue
        case .newProject:
            createsProject = true
            name = ""
            details = ""
            icon = "checklist"
            colorHex = CadenceColorPalette.projectDefault
            projectDueDateKey = ""
            projectDueDate = Date()
            hideEmptySectionDueDates = true
            selectedContextID = seededContextValue
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
            selectedCalendarID = area.linkedCalendarID
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
            selectedCalendarID = project.linkedCalendarID
            if let date = DateFormatters.date(from: project.dueDate) {
                projectDueDate = date
                projectDueDateKey = DateFormatters.dateKey(from: date)
            } else {
                projectDueDate = Date()
                projectDueDateKey = ""
            }
        }
        // [[T-5174]] (b): every mode snapshots, creation included. A new list opens on defaults —
        // `createsProject`'s icon/colour pair, the seeded context — so those defaults are what the
        // sheet "opened on", and only a change away from them is typed work worth holding.
        openedDraft = currentDraft
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
    /// Return in the name field: the Save button's own `save()`, refused on the same blank name
    /// that disables the button.
    private func submitName() {
        guard !trimmedName.isEmpty else { return }
        save()
    }

    private func save() {
        // [[T-8562]]: a lifecycle row's step lives for this one call, whichever way it ends.
        defer { lifecycleStep = nil }
        // **A column whose name the user cleared is a refused rename, not a delete (T-1053).**
        // `CadenceSectionEditingSupport.configs(from:)` used to drop such a draft, which read as
        // "this caller removed the column" — so the column left the blob, its colour and due date
        // went with it, and its cards were emptied into Default, from clearing a text field, with
        // no confirmation and nothing said. The column now keeps the name it had; this is what
        // says so.
        let refusal: KanbanColumnRenameRefusal? =
            CadenceSectionEditingSupport.clearedColumnNames(in: sectionDrafts).isEmpty ? nil : .emptyName
        nameRefusalNotice = refusal?.notice
        do {
            switch resolvedMode {
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
                project.dueDate = projectDueDateKey
                modelContext.insert(project)
                try CadencePendingChangePersistence.commitInsert(of: project, in: modelContext)
            case .editArea(let area):
                // Snapshotted before the first write, and it holds the tasks as well as the list:
                // `reassignTasks` below re-points every one of them. See `CadenceListEditSnapshot`
                // for why this is a snapshot rather than `modelContext.rollback()`.
                //
                // **`area.tasks` is not that set (T-685).** The reassignment below cascades by
                // design ([[T-340]]): an area's move also re-points the tasks of every child
                // project whose own `context` is `nil`, because those read their context through
                // the area. Snapshotting the area's direct tasks alone restored the area and left
                // those tasks pointing at the context a refused save never landed.
                // `inheritedContextTargets` is the set the cascade actually writes, and it is what
                // the Mac's editors already hand their snapshot.
                let undo = CadenceListEditSnapshot(
                    area,
                    tasks: CadenceTaskMutationSupport.inheritedContextTargets(area: area)
                )
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
                // [[T-8562]], T-624: before the assignment, as macOS's `EditAreaSheet` does -- only a
                // changed pick is evidence this device has seen the calendar.
                CadenceCalendarLinkObservations.recordPick(selectedCalendarID, replacing: area.linkedCalendarID)
                area.linkedCalendarID = selectedCalendarID
                if case .reopen? = lifecycleStep { area.status = .active }
                try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
            case .editProject(let project):
                // Nothing inherits from a project, so this is `project.tasks` — asked for by the
                // same name the area branch uses, so neither branch re-derives the set the
                // reassignment reaches.
                let undo = CadenceListEditSnapshot(
                    project,
                    tasks: CadenceTaskMutationSupport.inheritedContextTargets(project: project)
                )
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
                project.dueDate = projectDueDateKey
                CadenceCalendarLinkObservations.recordPick(selectedCalendarID, replacing: project.linkedCalendarID)
                project.linkedCalendarID = selectedCalendarID
                if case .reopen? = lifecycleStep { project.status = .active }
                try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)
            }
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        // The sheet stays open when a column name was refused, because the notice is the only
        // thing that would say so and a dismissed sheet cannot draw it. Everything else in the
        // save has already landed and been committed, exactly as the macOS column popover leaves
        // a refused rename's colour and date in the store with the popover still up (T-914).
        guard refusal == nil else { return }
        // [[T-8562]]: a Complete / Archive from the Status rows settles only once the edits it
        // carries have landed -- macOS's `apply(_:)` order -- and never over a refused save.
        if case .windDown(let target)? = lifecycleStep {
            modelContext.windDownList(target)
        }
        dismiss()
    }

    /// The one line the editor shows, and the order is the one macOS's column popover settled on
    /// (T-914): a refused *commit* leads a refused *name*, because of the two it is the one with
    /// work still pending behind it. Both can be true at once, and the next Save re-answers both.
    private var editorFailureNotice: String? {
        saveFailureNotice ?? nameRefusalNotice
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
    /// The day the picker shows and opens on. Whether the column HAS a due date is
    /// `draft.dueDate` alone ([[T-9804]]) -- there is no switch beside the picker to disagree with it.
    @State private var dueDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // [[T-10045]]: the board header's own dot size; this drew 8pt beside a 7pt header.
                Circle()
                    .fill(Color(hex: draft.colorHex))
                    .frame(
                        width: CadenceBoardColumnHeaderMetrics.dotSize,
                        height: CadenceBoardColumnHeaderMetrics.dotSize
                    )

                // T-5835: Default's name is not editable. A rename re-pointed every Default card
                // to the new name and `normalizedSectionConfigs` then synthesised an empty
                // "Default" beside it. The caption is the Mac column popover's own sentence.
                if draft.isDefaultColumn {
                    Text(draft.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                } else {
                    TextField("Column name", text: $draft.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .frame(minHeight: 32)

            if draft.isDefaultColumn {
                Text("Default always stays available and cannot be renamed, completed, archived, or deleted.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            iOSSectionColorPicker(selectedHex: $draft.colorHex)

            // [[T-9804]]: the Mac column popover's one-button field, not a "Due date" switch plus a
            // picker. It reads "No due date" while empty, a pick sets the date and Clear unsets it.
            // Every pick commits through the setter rather than `.onChange`: after a clear the
            // bound day is still the cleared one, and picking it again changes nothing.
            HStack {
                Text("Due date")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                Spacer()
                CadenceDatePicker(
                    selection: Binding(
                        get: { dueDate },
                        set: { newValue in
                            dueDate = newValue
                            draft.dueDate = DateFormatters.dateKey(from: newValue)
                        }
                    ),
                    placeholder: draft.dueDate.isEmpty ? CadenceBoardColumnDueDatePlan.emptyLabel : nil,
                    showsClear: !draft.dueDate.isEmpty,
                    onClear: { draft.dueDate = "" }
                )
            }

            if let lifecycle {
                lifecycleControls(lifecycle)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            dueDate = DateFormatters.date(from: draft.dueDate) ?? Date()
        }
    }

    /// State first, then only the transitions available from it. An archived column offers one
    /// button, because archiving it again is not a thing and completing it after the fact would be
    /// a second settle over work already cancelled.
    ///
    /// Every title here is a bare verb ([[T-6983]]): the editor is already about one column, and
    /// macOS's "X Column" pair would not fit one `lineLimit(1)` row on a 393 pt iPhone.
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
                    title: "Unarchive",
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
        .accessibilityLabel(isSelected ? "Selected color" : "Use this color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Same idea for the glyph: the field used to want a raw SF Symbol name typed in, which is a
/// developer's input, and a typo silently fell back to the default icon on save.
/// Not `private`: the context editor in Settings had the same typed field and draws this strip
/// now ([[T-8541]]), as macOS's `CreateContextSheet` draws the same palette as its list editors.
struct iOSListIconStrip: View {
    @Binding var selected: String
    let colorHex: String

    /// **The selection is scrolled into view** ([[T-8902]]). The strip is about seven plates wide
    /// on a 393 pt phone and the palette is over forty, so a list whose icon sat past the seventh
    /// -- or a stored icon outside the palette, which `offeredIcons(for:)` appends last -- opened
    /// on a row of unselected grey glyphs, with only the preview card saying what was set. The
    /// same `ScrollViewReader` pattern `iOSListDetailPagePicker` keeps its selected tab centred
    /// with: no animation on appear, so the sheet opens already scrolled rather than visibly
    /// sliding, and an animated follow when the selection moves. The Mac draws the palette as a
    /// full `IconGrid`, so there is nothing scrolled out of view to bring back ([[T-8201]]).
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CadenceIconPalette.offeredIcons(for: selected), id: \.self) { icon in
                        iconButton(icon)
                            .id(icon)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, newIcon in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newIcon, anchor: .center) }
            }
        }
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = icon == selected
        return Button {
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
        .accessibilityLabel(CadenceIconPalette.accessibilityName(for: icon))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
/// [[T-8562]]: what a list editor's Status or Archive row asks `save()` to do after its commit.
enum iOSListEditorLifecycleStep {
    /// Back to Active, inside the edit's own commit.
    case reopen
    /// Complete or Archive, through `ModelContext.windDownList` once the edit has landed.
    case windDown(iOSListWindDownTarget)
}
#endif

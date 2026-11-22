#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Capture's floating presentation of the shared schedule panel. The host owns stores and commits;
/// the panel owns the form. Both palette arms arrive here with their kind already selected.
struct iOSCreateTaskSheet: View {
    let onCreated: ((AppTask) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var draft: CadenceScheduleDraft
    @State private var selectedTagIDs: Set<String> = []
    @State private var actionError: String?
    @State private var cardHeight: CGFloat = 260
    /// The card panel standing open, held here so Escape closes it before the composer
    /// ([[T-18083]], the Mac's [[T-16041]] rule). The card mirrors it through `activeField`.
    @State private var openField: CadenceCaptureField?
    /// Cmd+Shift+T / Cmd+Shift+D: the card panel to open ([[T-18540]], the Mac's [[T-13792]] pair).
    @State private var fieldRequest: CadenceCaptureField?
    /// [[T-5174]] (b): the draft as `onAppear`'s opening normalisation left it, against which a
    /// swipe-down is refused. `nil` until then, so the normalisation itself is never read as typing.
    @State private var openedDraft: CadenceCreateTaskDraftSnapshot?

    init(
        seed: CadenceTaskComposerSeed = CadenceTaskComposerSeed(),
        initialKind: CadenceScheduleDraftKind = .task,
        onCreated: ((AppTask) -> Void)? = nil
    ) {
        self.onCreated = onCreated
        // [[T-13792]]: the shared opening rule, which the Mac's Cmd+N composer reads too.
        _draft = State(initialValue: CadenceTaskComposerSupport.captureDraft(seed: seed, initialKind: initialKind))
    }

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: CadenceScheduleDraftChoices.listChoices(for: draft, areas: areas, projects: projects),
                sectionChoices: CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: areas, projects: projects),
                calendarChoices: iOSScheduleDraftCreation.calendarChoices(calendarManager),
                calendarUnavailableNotice: calendarUnavailableNotice,
                failureNotice: actionError,
                canCommit: canCreate,
                offersSubtasks: true,
                actions: CadenceSchedulePanelActions(commit: create, cancel: { dismiss() })
            ) {
                markerSuggestions
                // [[T-7073]]: the slot sheet's control, which opens Settings after a refusal
                // rather than re-asking a prompt iOS will never show again.
                if draft.kind == .event {
                    iOSCaptureCalendarAccessButton(calendarManager: calendarManager) {
                        normalizeCalendar()
                    }
                }
            }
            .capturePresentation(CadenceScheduleCaptureOptions(
                tagChoices: TagSupport.uniqueBySlug(tags.filter { !$0.isArchived }).map {
                    CadenceSchedulePanelChoice(id: $0.id.uuidString, name: $0.name, color: Color(hex: $0.colorHex), systemImage: "tag")
                },
                selectedTagIDs: $selectedTagIDs,
                createTag: createTag,
                fieldRequest: $fieldRequest,
                activeField: $openField
            ))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
            .frame(maxWidth: 540)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .iOSCaptureKeyboardCommands(
            draft: $draft,
            fieldRequest: $fieldRequest,
            commit: { actionError = create() },
            cancel: { iOSCaptureKeyboardCancel(openField: &openField, dismiss: { dismiss() }) }
        )
        .scrollDismissesKeyboard(.never)
        .scrollIndicators(.hidden)
        .cadenceScaledTypography()
        .tint(Theme.blue)
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(cardHeight)])
        // [[T-5174]] (b), the owner's "one rule for every sheet": a swipe-down cannot discard a
        // half-typed new task. Presented by `.sheet(item:)` from `iOSCaptureRadialMenu` and never
        // by `.popover` — [[T-3240]] measured this modifier pushing an iPad popover presentation
        // out of its popover and clipping it, and a test pins that every presenter is a sheet.
        .interactiveDismissDisabled(
            CadenceSheetDismissGuard.blocksSwipe(opened: openedDraft, current: currentDraft)
        )
        .onAppear {
            reconcileContainer()
            normalizeCalendar()
            // [[T-5174]] (b). Taken *after* the two normalisations above, which reconcile a seeded
            // container and a missing calendar before the user has touched anything — snapshotting
            // the `init` value instead would hold the sheet over work nobody did. Taken once: this
            // fires again when the sheet comes back from a pushed picker.
            if openedDraft == nil { openedDraft = currentDraft }
        }
        // A picked list re-resolves the section inside the panel ([[T-8591]], [[T-8601]]); the
        // calls to `normalizeSection()` below are for the sheet's own programmatic list changes.
        .onChange(of: containerStillExists) { _, _ in reconcileContainer() }
        .onChange(of: draft.kind) { _, _ in
            actionError = nil
            normalizeCalendar()
        }
        .onChange(of: calendarManager.writableCalendars.map(\.calendarIdentifier)) { _, _ in normalizeCalendar() }
    }

    /// [[T-5174]] (b): what the sheet holds right now, in the form the snapshot compares.
    private var currentDraft: CadenceCreateTaskDraftSnapshot {
        CadenceCreateTaskDraftSnapshot(draft: draft, tagIDs: selectedTagIDs)
    }

    @ViewBuilder
    private var markerSuggestions: some View {
        if draft.kind == .task, let shortcut = TaskTitleSupport.containerShortcut(in: draft.title) {
            CadenceTaskComposerMarkerSuggestions(
                kind: .list, shortcut: shortcut, areas: areas, projects: projects, allTags: tags,
                onPickContainer: { selection in
                    draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    draft.listToken = CadenceTaskComposerSupport.token(for: selection)
                    normalizeSection()
                }, onPickTag: { _ in }, onCreateTag: { _ in }
            )
        } else if draft.kind == .task, let shortcut = TaskTitleSupport.tagShortcut(in: draft.title) {
            CadenceTaskComposerMarkerSuggestions(
                kind: .tag, shortcut: shortcut, areas: areas, projects: projects, allTags: tags,
                onPickContainer: { _ in },
                onPickTag: { tag in
                    draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    selectedTagIDs.insert(tag.id.uuidString)
                },
                onCreateTag: { name in
                    // Keep the shortcut on refusal, so no typed input is lost.
                    if createTag(name) == nil {
                        draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    }
                },
                onUnarchiveTag: { tag in
                    // [[T-13963]]: the same keep-on-refusal as Create.
                    if unarchiveTag(tag) == nil {
                        draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    }
                },
                // The `#` stays in the title: the strip then lists the new tags to pick from.
                onAddDefaultTags: addDefaultTags
            )
        }
    }

    private var selection: TaskContainerSelection { CadenceTaskComposerSupport.selection(fromToken: draft.listToken) }
    private var resolver: TaskContainerResolver { TaskContainerResolver(areas: areas, projects: projects) }
    private var containerStillExists: Bool {
        !CadenceTaskComposerSupport.namesMissingContainer(selection, areas: areas, projects: projects)
    }
    private var canCreate: Bool {
        switch draft.kind {
        case .task: return CadenceTaskComposerSupport.canCreate(title: draft.title)
        case .event:
            return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && calendarManager.writableCalendars.contains { $0.calendarIdentifier == draft.calendarID }
        }
    }
    private var calendarUnavailableNotice: String? {
        guard draft.kind == .event else { return nil }
        if !calendarManager.isAuthorized { return CadenceCalendarAccessNotice.eventCreationNeedsAccessSentence }
        return calendarManager.writableCalendars.isEmpty ? "No writable calendars are available." : nil
    }

    private func normalizeSection() {
        draft.sectionName = resolver.normalizedSectionName(draft.sectionName, for: selection)
    }
    /// The shared resolution, not a copy of it ([[T-8552]]): this sheet's own copy took the first
    /// writable calendar after the shared one had learned to prefer the default.
    private func normalizeCalendar() {
        iOSScheduleDraftCreation.resolveCalendarSelection(&draft, calendarManager: calendarManager)
    }
    @discardableResult
    private func reconcileContainer() -> Bool {
        guard CadenceTaskComposerSupport.namesMissingContainer(selection, areas: areas, projects: projects) else { return true }
        draft.listToken = CadenceTaskComposerSupport.token(for: .inbox)
        normalizeSection()
        actionError = CadenceTaskComposerSupport.missingContainerNotice
        return false
    }

    /// [[T-9231]]: the strip's Add Default Tags chip, the same committing seed the tag popover and
    /// the Mac's placeholder row run. A refusal rolls the whole seed back and says so.
    private func addDefaultTags() {
        do {
            try TagSupport.seedDefaultTagsCommitting(in: modelContext)
            actionError = nil
        } catch {
            actionError = CadencePendingChangePersistence.editFailureNotice
        }
    }

    /// [[T-13963]]: the strip's Unarchive chip. The un-archive is committed before the tag is
    /// selected, so the chip never outruns the store.
    private func unarchiveTag(_ tag: Tag) -> String? {
        guard TagSupport.committedUnarchive(tag, in: modelContext) else {
            actionError = CadencePendingChangePersistence.editFailureNotice
            return actionError
        }
        selectedTagIDs.insert(tag.id.uuidString)
        actionError = nil
        return nil
    }

    private func createTag(_ name: String) -> String? {
        // [[T-17326]]: an archived tag's name un-archives it, so the chip shows in the card's list.
        guard let tag = TagSupport.committedFieldTag(named: name, in: tags, context: modelContext) else {
            actionError = CadencePendingChangePersistence.editFailureNotice
            return actionError
        }
        selectedTagIDs.insert(tag.id.uuidString)
        actionError = nil
        return nil
    }

    /// The card's Add, its title's Return, and Cmd+Return ([[T-18083]]). `nil` when the draft left
    /// the sheet, the sentence to draw when it did not.
    ///
    /// [[T-18797]]: Cmd+Return reaches this without the card's `commit()`, so the card's title gate
    /// is asked here too, as the Mac's `CreateTaskSheet.commit()` asks it ([[T-17746]]). An empty
    /// title failed `canCreate` silently, and a title of marks alone (`!!!`) passed it, the service
    /// made nothing, and the chord did nothing with no word said.
    private func create() -> String? {
        guard draft.hasCommittableTitle else { return CadenceTaskComposerSupport.noNameNotice }
        guard canCreate else { return nil }
        if draft.kind == .event { return createEvent() }
        guard reconcileContainer() else { return actionError }
        // The Mac's Cmd+N card builds through the same call ([[T-14794]]): a hand-rolled copy here
        // carried the raw series end where the shared builder carries `effectiveSeriesEndMode`.
        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft,
            container: selection,
            tags: tags.filter { selectedTagIDs.contains($0.id.uuidString) },
            subtaskTitles: draft.subtaskTitles
        )
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: creation, into: modelContext)
        } catch {
            actionError = TaskCreationService.saveFailureNotice
            return actionError
        }
        guard let task = created else { return CadenceTaskComposerSupport.noNameNotice }
        actionError = nil
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        onCreated?(task)
        dismiss()
        return nil
    }

    private func createEvent() -> String? {
        if let failure = iOSScheduleDraftCreation.createEvent(from: draft, calendarManager: calendarManager) {
            return failure
        }
        dismiss()
        return nil
    }
}

/// **[[T-18083]] / [[T-18540]]: the capture composer's hardware-keyboard keys on iPad, the Mac's.**
/// Cmd+N opens this composer ([[T-13281]]), so it is the one sheet a keyboard user opens BY
/// keyboard, and under [[T-8201]] a hardware keyboard is the same input on both platforms. So it
/// answers the Mac `CreateTaskSheet`'s nine keys: Cmd+Return creates and Escape cancels
/// ([[T-18083]]); Cmd+T / Cmd+D set or clear today as the do and due date, Cmd+Shift+T /
/// Cmd+Shift+D open the card's Do and Due panels through its `fieldRequest`, Cmd+P cycles
/// priority, and Cmd+Shift+= / Cmd+Shift+- nudge the do date a day ([[T-18540]]: it had only the
/// first two). The draft edits are the shared `CreateTaskKeyboardCommands` the Mac's buttons call.
/// None needs hover -- each acts on the open draft, not a row. Cmd+Return matters because Return
/// in the notes field is a newline. Zero-size, transparent buttons in `iOSRootView`'s Cmd+K /
/// Cmd+N form rather than `.hidden()`, which can drop a button's shortcut; titled, so the Cmd-hold
/// overlay lists them. Applied by both hosts of the capture card, `iOSCreateTaskSheet` and
/// `iOSCalendarQuickCreateSheet`.
extension View {
    func iOSCaptureKeyboardCommands(
        draft: Binding<CadenceScheduleDraft>,
        fieldRequest: Binding<CadenceCaptureField?>,
        commit: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        background {
            Group {
                Button("Create", action: commit)
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Do Today") { CreateTaskKeyboardCommands.toggleDoToday(&draft.wrappedValue) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Do Date") { fieldRequest.wrappedValue = .doDate }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Due Today") { CreateTaskKeyboardCommands.toggleDueToday(&draft.wrappedValue) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Due Date") { fieldRequest.wrappedValue = .dueDate }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Next Priority") { CreateTaskKeyboardCommands.cyclePriority(&draft.wrappedValue) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Do Date a Day Later") { CreateTaskKeyboardCommands.nudgeDoDate(&draft.wrappedValue, by: 1) }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("Do Date a Day Earlier") { CreateTaskKeyboardCommands.nudgeDoDate(&draft.wrappedValue, by: -1) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

/// [[T-18083]], with [[T-16041]]'s panel-first rule: Escape closes an open card panel (Do, Due,
/// Repeat...) and leaves the draft; only with no panel up does it close the composer, as the card's ✕
/// does.
func iOSCaptureKeyboardCancel(openField: inout CadenceCaptureField?, dismiss: () -> Void) {
    if openField != nil {
        openField = nil
    } else {
        dismiss()
    }
}
#endif

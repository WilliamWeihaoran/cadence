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
    /// [[T-5174]] (b): the draft as `onAppear`'s opening normalisation left it, against which a
    /// swipe-down is refused. `nil` until then, so the normalisation itself is never read as typing.
    @State private var openedDraft: CadenceCreateTaskDraftSnapshot?

    init(
        seed: CadenceTaskComposerSeed = CadenceTaskComposerSeed(),
        initialKind: CadenceScheduleDraftKind = .task,
        onCreated: ((AppTask) -> Void)? = nil
    ) {
        self.onCreated = onCreated
        var draft = CadenceScheduleDraft.quickCreate(
            dateKey: seed.doDateKey.isEmpty ? DateFormatters.todayKey() : seed.doDateKey,
            startMin: seed.scheduledStartMin >= 0 ? seed.scheduledStartMin : min(
                max(Calendar.current.component(.hour, from: Date()) + 1, CadenceScheduleSupport.calendarStartHour),
                CadenceScheduleSupport.calendarEndHour - 1
            ) * 60,
            opensTimed: seed.scheduledStartMin >= 0,
            kind: initialKind
        )
        draft.title = seed.title
        draft.notes = seed.notes
        draft.dueDateKey = seed.dueDateKey
        draft.priority = seed.priority
        draft.listToken = CadenceTaskComposerSupport.token(for: seed.container)
        draft.sectionName = seed.sectionName
        draft.setEstimate(seed.estimatedMinutes)
        draft.estimateIsExplicit = seed.estimatedMinutes != CadenceTaskComposerSupport.defaultEstimatedMinutes
        if initialKind == .task, seed.doDateKey.isEmpty { draft.clearDoDate() }
        _draft = State(initialValue: draft)
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
                createTag: createTag
            ))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
            .frame(maxWidth: 540)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
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
        .onChange(of: draft.listToken) { _, _ in normalizeSection() }
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
            iOSTaskComposerMarkerSuggestions(
                kind: .list, shortcut: shortcut, areas: areas, projects: projects, allTags: tags,
                onPickContainer: { selection in
                    draft.title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    draft.listToken = CadenceTaskComposerSupport.token(for: selection)
                    normalizeSection()
                }, onPickTag: { _ in }, onCreateTag: { _ in }
            )
        } else if draft.kind == .task, let shortcut = TaskTitleSupport.tagShortcut(in: draft.title) {
            iOSTaskComposerMarkerSuggestions(
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
                }
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
        if !calendarManager.isAuthorized { return "Calendar access is needed to create events." }
        return calendarManager.writableCalendars.isEmpty ? "No writable calendars are available." : nil
    }

    private func normalizeSection() {
        draft.sectionName = resolver.normalizedSectionName(draft.sectionName, for: selection)
    }
    private func normalizeCalendar() {
        guard draft.kind == .event else { return }
        if !calendarManager.writableCalendars.contains(where: { $0.calendarIdentifier == draft.calendarID }) {
            draft.calendarID = calendarManager.writableCalendars.first?.calendarIdentifier ?? ""
        }
    }
    @discardableResult
    private func reconcileContainer() -> Bool {
        guard CadenceTaskComposerSupport.namesMissingContainer(selection, areas: areas, projects: projects) else { return true }
        draft.listToken = CadenceTaskComposerSupport.token(for: .inbox)
        normalizeSection()
        actionError = CadenceTaskComposerSupport.missingContainerNotice
        return false
    }

    private func createTag(_ name: String) -> String? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {
            actionError = CadencePendingChangePersistence.editFailureNotice
            return actionError
        }
        selectedTagIDs.insert(tag.id.uuidString)
        actionError = nil
        return nil
    }

    private func create() -> String? {
        guard canCreate else { return nil }
        if draft.kind == .event { return createEvent() }
        guard reconcileContainer() else { return actionError }
        let fields = CadenceTaskComposerFields(
            container: selection, sectionName: draft.sectionName, doDateKey: draft.startDateKey,
            dueDateKey: draft.dueDateKey, priority: draft.priority
        )
        var creation = CadenceTaskComposerSupport.draft(
            title: draft.title, notes: draft.notes, fields: fields,
            tags: tags.filter { selectedTagIDs.contains($0.id.uuidString) },
            scheduledStartMin: draft.scheduledStartMin, estimatedMinutes: draft.estimateMinutes
        )
        creation.repeatRule = draft.repeatRule
        creation.seriesEndMode = draft.seriesEndMode
        creation.seriesEndDateKey = draft.seriesEndDateKey
        creation.seriesEndCount = draft.seriesEndCount
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: creation, into: modelContext)
        } catch {
            actionError = TaskCreationService.saveFailureNotice
            return actionError
        }
        guard let task = created else { return nil }
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
#endif

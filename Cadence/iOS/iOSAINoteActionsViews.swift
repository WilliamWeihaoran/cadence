#if os(iOS)
import SwiftData
import SwiftUI

/// The iOS entry point for AI note actions, and the review sheets that stand between a model's
/// answer and anything being written.
///
/// iOS shipped the whole AI settings screen — key entry, model ID, connection test, and a
/// disclosure row reading "AI requests run only after you choose an AI command" — for a feature it
/// had no command for. This file is the command.
///
/// **Absent, not disabled, with no key.** macOS greys its two rows and captions them "Add an API
/// key to enable AI", because they sit inside a menu the note already has. There is no such menu
/// here, so the same treatment would mean adding a control to every note header for a feature the
/// user has not opted into. AI is optional and off by default: with no key this view renders
/// nothing at all, and nothing here touches the network until a menu item is tapped.
struct iOSNoteAIActionsMenu: View {
    let note: Note
    var area: Area?
    var project: Project?

    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var payload: iOSAIReviewPayload?
    @State private var runningAction: CadenceNoteAIAction?
    @State private var errorMessage: String?

    var body: some View {
        // The gate, and the whole of it. `hasAPIKey` is read from the Keychain-backed manager at
        // launch and refreshed by Settings; it makes no request of its own.
        if aiSettingsManager.hasAPIKey {
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(CadenceNoteAIAction.allCases) { action in
                Button {
                    run(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        } label: {
            label
        }
        .disabled(runningAction != nil)
        // A sheet, not a direct write. `payload` is the only thing an AI response can set, and the
        // only things that read it are the two review sheets.
        .sheet(item: $payload) { payload in
            reviewSheet(for: payload)
        }
        .alert("AI Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The same quiet tile `iOSNotesHeaderIconButton` and `iOSNoteTemplateMenu`'s label draw, at the
    /// same 34pt with the same 44pt hit area — these three controls sit in the same row and are the
    /// same kind of control. Blue is reserved for the thing you came to the note to do.
    @ViewBuilder
    private var label: some View {
        if runningAction != nil {
            ProgressView()
                .controlSize(.small)
                .frame(width: 34, height: 34)
                .frame(minWidth: 44, minHeight: 44)
        } else {
            iOSIconTile(systemImage: "sparkles", color: Theme.muted, size: 34, iconSize: 13)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("AI actions")
        }
    }

    @ViewBuilder
    private func reviewSheet(for payload: iOSAIReviewPayload) -> some View {
        switch payload {
        case .summary(let markdown):
            iOSAISummaryReviewSheet(markdown: markdown) {
                try CadenceAINoteSummary.append(markdown, to: note, modelContext: modelContext)
            }
        case .taskDrafts(let drafts):
            iOSAITaskDraftReviewSheet(
                drafts: drafts,
                area: area,
                project: project,
                areas: areas,
                projects: projects
            )
        }
    }

    /// The one place iOS reaches the provider. Nothing is persisted here — not the prompt, not the
    /// response, not the key — and the error surfaced is `AIErrorPresenter`'s, which reads an
    /// error's `errorDescription` and never the request that produced it.
    private func run(_ action: CadenceNoteAIAction) {
        Task { @MainActor in
            runningAction = action
            errorMessage = nil
            defer { runningAction = nil }
            do {
                let provider = try aiSettingsManager.provider()
                let context = try AIActionService.noteContext(note: note, area: area, project: project)
                switch action {
                case .summarize:
                    payload = .summary(try await provider.summarizeNote(context))
                case .extractTasks:
                    payload = .taskDrafts(try await provider.extractTasks(from: context))
                }
            } catch {
                errorMessage = AIErrorPresenter.message(for: error)
            }
        }
    }
}

/// What came back, waiting to be reviewed. Deliberately not "what was applied" — the only
/// transition out of this state is a sheet the user drives.
private enum iOSAIReviewPayload: Identifiable {
    case summary(String)
    case taskDrafts([AITaskDraft])

    var id: String {
        switch self {
        case .summary: return "summary"
        case .taskDrafts: return "taskDrafts"
        }
    }
}

// MARK: - Summary review

/// A summary is reviewable the same way a draft is: it is shown, and appending it is a separate
/// confirmation. Closing the sheet leaves the note untouched.
struct iOSAISummaryReviewSheet: View {
    let markdown: String
    /// Throwing, so a failed commit reaches this sheet rather than being swallowed under it.
    /// `Append` used to dismiss unconditionally over a `try? modelContext?.save()`, which is a
    /// sheet closing on a summary that was never written (T-315).
    let onAppend: () throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The same slot `iOSAITaskDraftReviewSheet` keeps, feeding the same kind of alert.
    @State private var errorMessage: String?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(markdown)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
                    .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("AI Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Append") { append() }
                        .fontWeight(.semibold)
                }
            }
            .tint(Theme.blue)
            .alert("Nothing Appended", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Dismisses only once the summary is in the store. The draft sheet below already worked this
    /// way; the summary half of the same service had drifted, and this is it adopting the neighbour.
    private func append() {
        do {
            try onAppend()
            dismiss()
        } catch {
            errorMessage = AIErrorPresenter.message(for: error)
        }
    }
}

// MARK: - Task draft review

/// **The review gate's screen.** Every draft is listed, editable, and individually approvable;
/// Create is dark until `CadenceAIDraftReview.canCreate` says the approved set is both non-empty
/// and valid, and the write goes through `applyApproved`, which refuses on its own account rather
/// than trusting this view to have checked.
///
/// One layout at both sizes. What the size class changes is the gutter — the same figure every other
/// editor sheet ramps — and nothing else: a draft card is the same card on a phone and an iPad.
struct iOSAITaskDraftReviewSheet: View {
    let area: Area?
    let project: Project?
    let areas: [Area]
    let projects: [Project]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var review: CadenceAIDraftReview
    @State private var errorMessage: String?

    init(
        drafts: [AITaskDraft],
        area: Area?,
        project: Project?,
        areas: [Area],
        projects: [Project]
    ) {
        self.area = area
        self.project = project
        self.areas = areas
        self.projects = projects
        _review = State(initialValue: CadenceAIDraftReview(drafts: drafts))
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Read from `AIActionService.container`, which is also what `applyApproved` writes through —
    /// so the label and the destination are one answer rather than two that agreed by hand. They
    /// used to be two, both spelling `area ?? project`, and a note owned by an area *and* a project
    /// is the case where that answer is wrong (T-316).
    private var destinationName: String {
        AIActionService.container(area: area, project: project).name ?? "Inbox"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Task Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(createTitle) { createApproved() }
                        .fontWeight(.semibold)
                        .disabled(!review.canCreate)
                }
            }
            .tint(Theme.blue)
            .alert("Nothing Created", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var createTitle: String {
        let count = review.selectedIDs.count
        return count == 0 ? "Create" : "Create \(count)"
    }

    @ViewBuilder
    private var content: some View {
        if review.drafts.isEmpty {
            EmptyStateView(
                message: "No tasks found",
                subtitle: "The note did not contain clear action items.",
                icon: "sparkles"
            )
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                // Says where the approved drafts will land, which is the one fact the cards below
                // and the title above do not carry.
                SectionEyebrowLabel(text: "Creating in \(destinationName)")

                ForEach($review.drafts) { $draft in
                    iOSAITaskDraftCard(
                        draft: $draft,
                        isApproved: Binding(
                            get: { review.isSelected(draft) },
                            set: { review.setSelected($0, for: draft.id) }
                        ),
                        validation: review.validation(for: draft)
                    )
                }

                if let refusal = review.refusalMessage {
                    Text(refusal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(review.blockingErrors.isEmpty ? Theme.muted : Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The single write path, and it is the review's, not this view's.
    private func createApproved() {
        do {
            try review.applyApproved(
                area: area,
                project: project,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            errorMessage = AIErrorPresenter.message(for: error)
        }
    }
}

/// One proposed task, as a reviewable and correctable card.
///
/// Every field a draft carries is either editable here or clearable here, because a model is free
/// to answer `priority: "urgent"` or `dueDate: "next Tuesday"` and the alternative to correcting
/// those is coercing them — which is how a draft becomes a task with a silently wrong date. What
/// cannot be corrected can always be rejected: the approval circle is the other half of review.
private struct iOSAITaskDraftCard: View {
    @Binding var draft: AITaskDraft
    @Binding var isApproved: Bool
    let validation: AITaskDraftValidation

    /// `nil` when the model's answer is not one of the four priorities — so no segment lights up,
    /// rather than "None" lighting up and disagreeing with the error underneath.
    private var resolvedPriority: TaskPriority? {
        TaskPriority(rawValue: draft.priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    var body: some View {
        iOSEditorSection(title: nil, style: .card) {
            titleRow

            iOSEditorDivider()
            notesRow

            iOSEditorDivider()
            priorityRow

            iOSEditorDivider()
            dateRow(
                label: "Do",
                systemImage: "sun.max.fill",
                emptyPlaceholder: "No do date",
                keyPath: \.scheduledDate
            )

            iOSEditorDivider()
            dateRow(
                label: "Due",
                systemImage: "flag.fill",
                emptyPlaceholder: "No due date",
                keyPath: \.dueDate
            )

            iOSEditorDivider()
            sectionRow

            if !chips.isEmpty {
                iOSEditorDivider()
                chipRow
            }

            if !draft.subtaskTitles.isEmpty {
                iOSEditorDivider()
                subtaskRow
            }

            if !validation.isValid {
                iOSEditorDivider()
                Text(validation.errors.joined(separator: " "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
        }
        // One layer, one radius — the card is `iOSEditorSection(style: .card)`'s, and this only
        // recolours its edge when the draft cannot be created as written.
        .overlay {
            if !validation.isValid {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.45), lineWidth: 1)
            }
        }
        .opacity(isApproved ? 1 : 0.55)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                isApproved.toggle()
            } label: {
                Image(systemName: isApproved ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isApproved ? Theme.blue : Theme.dim)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(isApproved ? "Approved, tap to reject" : "Rejected, tap to approve")

            TextField("Task title", text: $draft.title, axis: .vertical)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var notesRow: some View {
        TextField("Notes", text: $draft.notes, axis: .vertical)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .textInputAutocapitalization(.sentences)
            .frame(minHeight: 30)
    }

    private var priorityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            iOSEditorInlineLabel(label: "Priority", systemImage: "exclamationmark.triangle.fill")

            // `iOSSegmentedChoice`'s two primitives rather than the wrapper: the wrapper's selection
            // is non-optional, and "the model said something that is not a priority" has to be
            // representable as no segment selected.
            iOSSegmentedPillGroup {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    iOSSegmentedPill(
                        title: priority.label,
                        isSelected: resolvedPriority == priority,
                        tint: Theme.priorityColor(priority),
                        fillsWidth: true
                    ) {
                        draft.priority = priority.rawValue
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// A date the model got wrong is shown **verbatim** in the trigger rather than as "No due date".
    /// `AIActionService.normalizedDate` would drop it on the way to `TaskCreationDraft`, so hiding it
    /// here would mean the card silently disagreeing with the error line below it.
    private func dateRow(
        label: String,
        systemImage: String,
        emptyPlaceholder: String,
        keyPath: WritableKeyPath<AITaskDraft, String>
    ) -> some View {
        let raw = draft[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = DateFormatters.date(from: raw)

        return iOSEditorFieldRow(
            label: label,
            systemImage: systemImage,
            color: raw.isEmpty || parsed != nil ? Theme.dim : Theme.red
        ) {
            CadenceDatePicker(
                selection: Binding(
                    get: { parsed ?? Date() },
                    set: { draft[keyPath: keyPath] = DateFormatters.dateKey(from: $0) }
                ),
                placeholder: parsed == nil ? (raw.isEmpty ? emptyPlaceholder : raw) : nil,
                minHeight: 44,
                showsClear: !raw.isEmpty,
                onClear: { draft[keyPath: keyPath] = "" }
            )
        }
    }

    private var sectionRow: some View {
        iOSEditorFieldRow(label: "Section", systemImage: "square.grid.2x2") {
            TextField(TaskSectionDefaults.defaultName, text: $draft.sectionName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
        }
    }

    /// The two numeric fields, stated so the user can see what would be written — and tappable to
    /// clear, because there is no other way to correct an out-of-range one.
    private var chips: [(label: String, isValid: Bool, clear: () -> Void)] {
        var result: [(String, Bool, () -> Void)] = []
        if let startMin = draft.scheduledStartMin {
            result.append((
                TimeFormatters.timeString(from: max(0, min(1439, startMin))),
                (0...1439).contains(startMin) && !draft.scheduledDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                { draft.scheduledStartMin = nil }
            ))
        }
        if let estimate = draft.estimatedMinutes {
            result.append((
                CadenceTaskPresentationSupport.estimateLabel(minutes: estimate),
                (1...1440).contains(estimate),
                { draft.estimatedMinutes = nil }
            ))
        }
        return result
    }

    private var chipRow: some View {
        CadenceWrappingHStack(spacing: 8, lineSpacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Button(action: chip.clear) {
                    HStack(spacing: 5) {
                        Text(chip.label)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chip.isValid ? Theme.muted : Theme.red)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(
                        Capsule().fill((chip.isValid ? Theme.muted : Theme.red).opacity(0.12))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Clear \(chip.label)")
            }
        }
        .padding(.vertical, 4)
    }

    private var subtaskRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            iOSEditorInlineLabel(label: "Subtasks", systemImage: "checklist")
            ForEach(Array(draft.subtaskTitles.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

#endif

#if os(macOS)
import SwiftUI
import SwiftData

struct AISummaryReviewSheet: View {
    let markdown: String
    /// Throwing, so a failed commit reaches this sheet instead of being swallowed under it. The
    /// append was `try? modelContext?.save()` and this button dismissed unconditionally, so the
    /// sheet closed on a note that had not been written (T-315).
    let onAppend: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    /// The same slot `AITaskDraftReviewSheet` keeps for the same reason: what went wrong stays on
    /// the sheet the user is looking at.
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Summary")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
            ScrollView {
                Text(markdown)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
            }

            // [[T-9451]]: the shared action button, so the hit area and the hover wash are the
            // plate. Both buttons padded (and Append filled) OUTSIDE `.buttonStyle(.cadencePlain)`,
            // so the style's contentShape and wash wrapped only the label text -- the plate's rim
            // was dead to a click, and hover lit a smaller rectangle inside it ([[T-9351]]'s shape).
            HStack {
                Spacer()
                // T-7289: Escape closes and Return appends; neither key did anything.
                CadenceActionButton(title: "Close", role: .ghost, size: .compact, shortcut: .cancelAction) {
                    dismiss()
                }

                CadenceActionButton(title: "Append to Note", role: .primary, size: .compact, shortcut: .defaultAction) {
                    append()
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Theme.bg)
    }

    /// Dismisses only once the summary is actually in the store. Exactly what
    /// `AITaskDraftReviewSheet.createSelected` below already does with its own write — the two
    /// halves of this service had drifted apart, and this is the one adopting the other.
    private func append() {
        do {
            try onAppend()
            dismiss()
        } catch {
            statusMessage = AIErrorPresenter.message(for: error)
        }
    }
}

struct AITaskDraftReviewSheet: View {
    let area: Area?
    let project: Project?
    let areas: [Area]
    let projects: [Project]
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    /// Drafts *and* which of them are approved, held together in `CadenceAIDraftReview` — the same
    /// value iOS's review sheet drives, and the only thing either sheet writes through. It was two
    /// separate `@State`s here, and the gate was "is the selection non-empty" with validity checked
    /// by `applyTaskDrafts` throwing *after* Create was pressed.
    @State private var review: CadenceAIDraftReview
    @State private var statusMessage: String?

    init(
        initialDrafts: [AITaskDraft],
        area: Area?,
        project: Project?,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) {
        self.area = area
        self.project = project
        self.areas = areas
        self.projects = projects
        self.modelContext = modelContext
        _review = State(initialValue: CadenceAIDraftReview(drafts: initialDrafts))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Task Drafts")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Review each draft before creating anything in Cadence.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            if review.drafts.isEmpty {
                EmptyStateView(
                    message: CadenceEmptyStateCopy.noteActionTasksTitle,
                    subtitle: CadenceEmptyStateCopy.noteActionTasksSubtitle,
                    icon: "sparkles",
                    // [[T-8532]]: a model's answer about one note, not a view of the store, so an
                    // iCloud import in flight cannot be why it came back empty.
                    statesColdImport: false
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($review.drafts) { $draft in
                            AITaskDraftRow(
                                draft: $draft,
                                isSelected: Binding(
                                    get: { review.isSelected(draft) },
                                    set: { review.setSelected($0, for: draft.id) }
                                ),
                                validation: review.validation(for: draft)
                            )
                        }
                    }
                    .padding(2)
                }
            }

            if let message = statusMessage ?? review.refusalMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(statusMessage == nil && !review.blockingErrors.isEmpty ? Theme.red : Theme.muted)
            }

            HStack {
                Spacer()
                // T-7289: Escape cancels. Return is deliberately NOT bound to Create Selected:
                // this sheet is a stack of editable fields, and T-7290 asks the owner whether a
                // Return typed in one should create every approved task.
                // [[T-9451]]: the shared action button, as in the summary sheet above.
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact, shortcut: .cancelAction) {
                    dismiss()
                }

                CadenceActionButton(
                    title: "Create Selected",
                    role: .primary,
                    size: .compact,
                    isDisabled: !review.canCreate
                ) {
                    createSelected()
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
        .background(Theme.bg)
    }

    /// Through the review, not around it. `applyApproved` refuses on its own account, so a future
    /// edit that loses the `isDisabled: !review.canCreate` above cannot write anything.
    private func createSelected() {
        do {
            let created = try review.applyApproved(
                area: area,
                project: project,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
            statusMessage = "Created \(created.count) task\(created.count == 1 ? "" : "s")."
            dismiss()
        } catch {
            statusMessage = AIErrorPresenter.message(for: error)
        }
    }
}

private struct AITaskDraftRow: View {
    @Binding var draft: AITaskDraft
    @Binding var isSelected: Bool
    /// Handed in by the sheet from `CadenceAIDraftReview.validation(for:)`, the same source its
    /// Create button reads. It was recomputed here off `AIActionService.validation` directly, so
    /// the row's red border and the button's enabled state were two reads of one rule — fine while
    /// they agreed, and exactly the shape that drifts. iOS's card takes it the same way.
    let validation: AITaskDraftValidation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // The row has no static title to borrow — the text beside this checkbox is an
                // editable `TextField` — so the name is stated here rather than inherited, and it
                // names the draft (T-7294): five drafts are no longer five "Include this task"s.
                Toggle(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: draft.title), isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityHint(CadenceAIDraftReview.approvalAccessibilityHint(isApproved: isSelected))
                TextField("Task title", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            // T-9061: every field carries a visible label, so a filled card no longer reads as two
            // unlabelled dates side by side. Do before Due, the order iOS's card states them in.
            // T-9082: priority is the same four-way choice and the dates the same picker iOS's
            // card uses, rather than free text and typed `yyyy-MM-dd` strings.
            HStack(alignment: .top, spacing: 12) {
                AITaskDraftCaptioned(label: "Priority") { priorityChoice }
                AITaskDraftCaptioned(label: "Section") {
                    TextField(TaskSectionDefaults.defaultName, text: $draft.sectionName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 26)
                        .accessibilityLabel("Section")
                }
                .frame(width: 140, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 12) {
                dateField(label: "Do", emptyPlaceholder: "No do date", keyPath: \.scheduledDate)
                dateField(label: "Due", emptyPlaceholder: "No due date", keyPath: \.dueDate)
            }

            // The start time and estimate this draft would write, drawn from the same shared chips
            // iOS's card uses. There is no other control for either, so clicking one clears it —
            // the only way to correct an out-of-range value short of unticking the draft.
            let chips = CadenceAIDraftReview.numericChips(for: draft)
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        Button {
                            chip.clear(&draft)
                        } label: {
                            HStack(spacing: 5) {
                                Text(chip.label)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(chip.isValid ? Theme.muted : Theme.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((chip.isValid ? Theme.muted : Theme.red).opacity(0.12)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(chip.accessibilityLabel)
                        .help(chip.accessibilityLabel)
                    }
                }
            }

            if !validation.isValid {
                Text(validation.errors.joined(separator: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(validation.isValid ? Theme.borderSubtle : Theme.red.opacity(0.45), lineWidth: 1)
        }
    }

    /// iOS's four segments. Its pill group is iOS-only and its selection non-optional; a model
    /// answer that is not a priority has to read as no segment selected, so the selection comes from
    /// `CadenceAIDraftReview.resolvedPriority(for:)`, the rule iOS's card reads too.
    private var priorityChoice: some View {
        let resolved = CadenceAIDraftReview.resolvedPriority(for: draft)
        return HStack(spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                let isSelected = resolved == priority
                let tint = priority == .none ? Theme.muted : Theme.priorityColor(priority)
                Button {
                    draft.priority = priority.rawValue
                } label: {
                    Text(priority.label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? tint : Theme.dim)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusControlCompact - 2)
                                .fill(isSelected ? tint.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .accessibilityLabel("Priority \(priority.label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControlCompact).strokeBorder(Theme.borderSubtle))
    }

    /// iOS's date row: the shared picker with a clear button, and a value the model got wrong shown
    /// verbatim with a red caption (`CadenceAIDraftReview.dateField`), so the card never reads
    /// "No due date" above an error line about that date.
    private func dateField(
        label: String,
        emptyPlaceholder: String,
        keyPath: WritableKeyPath<AITaskDraft, String>
    ) -> some View {
        let field = CadenceAIDraftReview.dateField(draft[keyPath: keyPath], emptyPlaceholder: emptyPlaceholder)
        return AITaskDraftCaptioned(label: label, isInvalid: field.isInvalid) {
            CadenceDatePicker(
                selection: Binding(
                    get: { field.parsed ?? Date() },
                    set: { draft[keyPath: keyPath] = DateFormatters.dateKey(from: $0) }
                ),
                placeholder: field.placeholder,
                showsClear: field.showsClear,
                onClear: { draft[keyPath: keyPath] = "" }
            )
        }
    }
}

/// One of the draft card's fields with its name drawn above it (T-9061). A placeholder vanishes as
/// soon as the field has text, so it can never be the only label. A date the model got wrong turns
/// its caption red, matching iOS's date row, so the error line has a field to point at.
private struct AITaskDraftCaptioned<Content: View>: View {
    let label: String
    var isInvalid: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isInvalid ? Theme.red : Theme.dim)
            content
        }
    }
}
#endif

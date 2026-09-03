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

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Button("Append to Note") {
                    append()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    icon: "sparkles"
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
                Button("Cancel") { dismiss() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Button("Create Selected") {
                    createSelected()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(review.canCreate ? Theme.blue : Theme.dim)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(!review.canCreate)
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
        .background(Theme.bg)
    }

    /// Through the review, not around it. `applyApproved` refuses on its own account, so a future
    /// edit that loses the `disabled(!review.canCreate)` above cannot write anything.
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
                // editable `TextField` — so the name is stated here rather than inherited.
                Toggle("Include this task", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                TextField("Task title", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            HStack(spacing: 8) {
                TextField("Priority", text: $draft.priority)
                    .frame(width: 90)
                TextField("Due yyyy-MM-dd", text: $draft.dueDate)
                    .frame(width: 120)
                TextField("Do yyyy-MM-dd", text: $draft.scheduledDate)
                    .frame(width: 120)
                TextField("Section", text: $draft.sectionName)
                    .frame(width: 110)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text)

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
}
#endif

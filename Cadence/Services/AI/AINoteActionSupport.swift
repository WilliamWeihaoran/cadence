import Foundation
import SwiftData

/// The cross-platform half of AI note actions: which actions a note offers, how a summary is filed
/// into a note, and — the part that matters — the **review gate** every task draft has to pass
/// before it can become an `AppTask`.
///
/// This file is deliberately outside any platform guard and holds no SwiftUI. `Cadence/iOS/` is
/// entirely inside `#if os(iOS)` and invisible to the macOS-built `CadenceTests`, so a decision
/// that lives in an iOS view cannot be pinned; a decision that lives here can. Same reason
/// `CadenceCompactTab` and `CadencePageHeaderMetrics` sit outside the guard.

/// The two actions a note can run through AI, and the one vocabulary both platforms read them from.
///
/// macOS spelled these as two literal strings inside `NoteActionMenu`'s `aiSection`; iOS reading
/// the same enum is what keeps "Summarize Note" from becoming "Summarise" on one platform and
/// "Extract Tasks" from becoming "Find Tasks" on the other.
enum CadenceNoteAIAction: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case extractTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize Note"
        case .extractTasks: return "Extract Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize: return "text.magnifyingglass"
        case .extractTasks: return "sparkles.rectangle.stack"
        }
    }

    /// The line under the title once a key is configured.
    var detail: String {
        switch self {
        case .summarize: return "Generate a concise recap"
        case .extractTasks: return "Turn notes into task drafts"
        }
    }
}

/// How an accepted summary is filed into the note it came from.
///
/// The string work is a pure function so the separator rule — one blank line before the heading,
/// and none when the note is empty — is testable without a `ModelContext`.
enum CadenceAINoteSummary {
    static let heading = "## AI Summary"

    /// `nil` when there is nothing to append, so a caller cannot write an empty section.
    static func appending(_ summary: String, to existing: String) -> String? {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return nil }
        let separator = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        return "\(existing)\(separator)\(heading)\n\n\(trimmedSummary)"
    }

    @MainActor
    static func append(_ summary: String, to note: Note, modelContext: ModelContext?) {
        guard let content = appending(summary, to: note.content) else { return }
        note.content = content
        note.updatedAt = Date()
        try? modelContext?.save()
    }
}

/// The review gate for AI task drafts.
///
/// `docs/CLAUDE_REFERENCE.md` states the rule this type exists to make unbreakable: drafts go
/// through a review sheet **before anything is written**. Holding the drafts and the selection
/// together, with the only write path guarded on `canCreate`, is what turns that from a property of
/// one sheet's layout into a property of the model both sheets drive.
///
/// Two things close the gate, and both matter:
///
/// - **Nothing selected.** A model that proposed five tasks you did not want must create none.
/// - **A selected draft that does not validate.** `AIActionService.applyTaskDrafts` already throws
///   in that case, and threw *after* the user pressed Create; refusing up front means the button is
///   dark and the offending card is marked while it is still editable. A model is free to answer
///   `priority: "urgent"` or `dueDate: "next Tuesday"`, and the difference between refusing that and
///   coercing it is a task with a silently wrong date.
struct CadenceAIDraftReview: Equatable, Sendable {
    /// Every draft the model proposed, in the order it proposed them. Editable — the review sheet
    /// is a place to fix a draft, not only to accept or drop it.
    var drafts: [AITaskDraft]
    /// Which of them the user has approved. Starts as all of them, matching macOS's sheet.
    var selectedIDs: Set<UUID>

    init(drafts: [AITaskDraft]) {
        self.drafts = drafts
        self.selectedIDs = Set(drafts.map(\.id))
    }

    var selectedDrafts: [AITaskDraft] {
        drafts.filter { selectedIDs.contains($0.id) }
    }

    func isSelected(_ draft: AITaskDraft) -> Bool {
        selectedIDs.contains(draft.id)
    }

    mutating func setSelected(_ isSelected: Bool, for id: UUID) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    /// Per-draft validation, straight from `AIActionService` rather than re-derived. A second
    /// spelling of "what makes a draft valid" is exactly how the sheet and the writer end up
    /// disagreeing.
    func validation(for draft: AITaskDraft) -> AITaskDraftValidation {
        AIActionService.validation(for: draft)
    }

    /// The errors that are actually stopping creation — only from drafts the user approved. An
    /// unselected broken draft is not a problem; it is a draft the user already rejected.
    var blockingErrors: [String] {
        selectedDrafts.flatMap { validation(for: $0).errors }
    }

    var canCreate: Bool {
        !selectedIDs.isEmpty && blockingErrors.isEmpty
    }

    /// What to show when the gate is closed. Distinguishes the two reasons, because "select
    /// something" and "fix this date" are different instructions.
    var refusalMessage: String? {
        if selectedIDs.isEmpty {
            return drafts.isEmpty
                ? "There is nothing to create."
                : "Select at least one draft to create it."
        }
        let errors = blockingErrors
        return errors.isEmpty ? nil : errors.joined(separator: " ")
    }

    /// **The only write path.** Refuses before touching the store when the review has not passed,
    /// so a caller cannot skip the gate by reaching for `AIActionService.applyTaskDrafts` with the
    /// same arguments. `AINoteActionReviewTests` pins that the iOS surface calls this and never
    /// that.
    @discardableResult
    @MainActor
    func applyApproved(
        area: Area? = nil,
        project: Project? = nil,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) throws -> [AppTask] {
        guard canCreate else {
            throw AIActionError.invalidDrafts(refusalMessage ?? "These drafts cannot be created yet.")
        }
        return try AIActionService.applyTaskDrafts(
            drafts,
            selectedIDs: selectedIDs,
            area: area,
            project: project,
            areas: areas,
            projects: projects,
            modelContext: modelContext
        )
    }
}

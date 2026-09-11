#if os(macOS)
import SwiftData
import SwiftUI

@MainActor
@Observable
final class DeleteConfirmationManager {
    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmLabel: String

        /// What the confirmed action reports back.
        ///
        /// Most deletes on this manager cannot fail in a way the user could act on and are wrapped
        /// by `present(…)` to answer `.deleted` unconditionally. `presentRefusable(…)` is for the
        /// ones that can, and the refusal carries its own sentence.
        let attempt: () -> Outcome
    }

    /// What a confirmed delete reports back to the overlay that asked for it.
    ///
    /// **Why the sentence travels with the answer (T-919).** `presentRefusable(…)` used to answer
    /// `Bool` against a `failureNotice: String` fixed at the call site. That is right for a delete
    /// whose only refusal is a rolled-back store save: there is exactly one thing to say and the
    /// call site knows it before it asks. A macOS calendar-event delete is not that. It answers a
    /// typed `CalendarWriteFailure` whose `message` names the actual cause — Calendar access not
    /// granted, the store's own save error — and a sentence chosen *before* the attempt cannot
    /// carry any of it, so those two deletes reported through the window-wide
    /// `.calendarWriteFailureAlert()` instead, which is generic where the manager could be exact.
    ///
    /// Deliberately **one** entry point rather than a typed sibling beside the `Bool` one. Two
    /// `presentRefusable` overloads differing only in their trailing closure's return type is the
    /// resolution `presentRefusable`'s own doc already refuses for `present`.
    enum Outcome: Equatable {
        /// The store took it. The overlay closes.
        case deleted
        /// It was refused and nothing was removed. The overlay stays open and says this.
        case refused(notice: String)
    }

    static let shared = DeleteConfirmationManager()

    var request: Request?

    /// Set when the confirmed action reported that it did not happen, and shown inside the still-open
    /// confirmation overlay. Cleared by the next confirm, present, or cancel.
    private(set) var failureNotice: String?

    private init() {}

    var isPresented: Bool { request != nil }

    /// A delete whose outcome the user has nothing to decide about.
    func present(
        title: String,
        message: String,
        confirmLabel: String = "Delete",
        action: @escaping () -> Void
    ) {
        present(
            request: Request(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                attempt: { action(); return .deleted }
            )
        )
    }

    /// A delete that can be refused. `attempt` answers `.refused(notice:)` when nothing was
    /// removed, and the overlay then stays open carrying that sentence.
    ///
    /// Deliberately a **different base name** rather than an overload of `present`. Both would end in
    /// a trailing closure, and the two candidates differ only in the closure's return type — a
    /// resolution the compiler can make and a reader cannot.
    func presentRefusable(
        title: String,
        message: String,
        confirmLabel: String = "Delete",
        attempt: @escaping () -> Outcome
    ) {
        present(
            request: Request(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                attempt: attempt
            )
        )
    }

    func confirm() {
        guard let request else { return }
        failureNotice = nil

        switch request.attempt() {
        case .deleted:
            self.request = nil
        case .refused(let notice):
            // The action was refused and rolled back. Dismissing here is what made the failure
            // invisible on macOS (T-376): the row reappears on its own, which reads as the delete
            // never having been asked for. Hold the overlay open and say what happened, the way the
            // list and note sheets already do.
            failureNotice = notice
        }
    }

    func cancel() {
        request = nil
        failureNotice = nil
    }

    private func present(request: Request) {
        failureNotice = nil
        self.request = request
    }
}

extension DeleteConfirmationManager {
    /// The one macOS way to confirm deleting a single task.
    ///
    /// **Why it lives here (T-376).** Five surfaces — the task row, a kanban card, the inspector's
    /// trash button, a timeline block, and the `Cmd+Delete` command — each open the same
    /// confirmation with the same title and message and then discard `deleteTask`'s `Bool`. Nothing
    /// was lost, because the rollback puts the row back, but macOS stayed silent where the iOS row
    /// shows `CadenceTaskMutationSupport.deleteFailureNotice`.
    ///
    /// The notice belongs on the confirmation, not on the five rows. Those five have five different
    /// geometries — a hover row, a card, an inspector column, an absolutely-positioned timeline
    /// block — and one of them, `RootCommandActionSupport.handleDeleteShortcut`, is not a view at
    /// all and has nowhere to put state. The confirmation overlay is the only thing all five already
    /// share, it is on screen at the moment the answer arrives, and it is the surface that asked the
    /// question. So the overlay stays open and reports, which is the same shape `EditListSheet` and
    /// `iOSNoteDeleteConfirmationSheet` use.
    ///
    /// It also collapses five copies of the title and message. Four of them spelled the fallback as
    /// `task.title.isEmpty ? "Untitled" : task.title` and the fifth used
    /// `TaskTitleSupport.displayTitle`, which is the shared one — a difference of exactly the kind
    /// [[T-374]] is about. `displayTitle` wins.
    ///
    /// - Parameter willDelete: surface-local teardown — clearing hover or selection that points at
    ///   the row about to go. Runs before the delete, and still runs if the delete is refused; the
    ///   row re-registers hover on the next mouse move, so there is nothing to undo.
    /// - Parameter commit: forwarded to `ModelContext.deleteTask(_:commit:)` for the same reason
    ///   that wrapper forwards it — this is now the only macOS-side task delete, so a test that
    ///   wants to watch a refused commit arrive at the overlay needs the seam to reach this far.
    func presentTaskDelete(
        _ task: AppTask,
        in modelContext: ModelContext,
        willDelete: @escaping () -> Void = {},
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        let title = TaskTitleSupport.displayTitle(task.title, fallback: "Untitled")
        presentRefusable(
            title: "Delete Task?",
            message: "This will permanently delete \"\(title)\"."
        ) {
            willDelete()
            guard modelContext.deleteTask(task, commit: commit) else {
                return .refused(notice: CadenceTaskMutationSupport.deleteFailureNotice)
            }
            return .deleted
        }
    }
}
#endif

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

        /// `false` when the confirmed action was refused and rolled back, so nothing was removed.
        ///
        /// Most deletes on this manager cannot fail in a way the user could act on and are wrapped
        /// by `present(…)` to return `true` unconditionally. `presentRefusable(…)` is for the ones
        /// that can.
        let action: () -> Bool

        /// The sentence to show when `action` returns `false`. `nil` for a request that never
        /// reports failure.
        let failureNotice: String?
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
                action: { action(); return true },
                failureNotice: nil
            )
        )
    }

    /// A delete that can be refused. `attempt` returns `false` when the store rolled the delete back
    /// and nothing was removed; the overlay then stays open and says `failureNotice`.
    ///
    /// Deliberately a **different base name** rather than an overload of `present`. Both would end in
    /// a trailing closure, and the two candidates differ only in the closure's return type — a
    /// resolution the compiler can make and a reader cannot.
    func presentRefusable(
        title: String,
        message: String,
        confirmLabel: String = "Delete",
        failureNotice: String,
        attempt: @escaping () -> Bool
    ) {
        present(
            request: Request(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                action: attempt,
                failureNotice: failureNotice
            )
        )
    }

    func confirm() {
        guard let request else { return }
        failureNotice = nil

        guard request.action() else {
            // The action was refused and rolled back. Dismissing here is what made the failure
            // invisible on macOS (T-376): the row reappears on its own, which reads as the delete
            // never having been asked for. Hold the overlay open and say what happened, the way the
            // list and note sheets already do.
            guard let notice = request.failureNotice else {
                self.request = nil
                return
            }
            failureNotice = notice
            return
        }

        self.request = nil
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
            message: "This will permanently delete \"\(title)\".",
            failureNotice: CadenceTaskMutationSupport.deleteFailureNotice
        ) {
            willDelete()
            return modelContext.deleteTask(task, commit: commit)
        }
    }
}
#endif

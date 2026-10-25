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

        /// A second, differently-scoped confirm on the same overlay, or `nil` for the single-button
        /// confirmation every delete but one uses ([[T-6115]]).
        ///
        /// `nil` is load-bearing rather than merely a default: the overlay draws no third button
        /// for it, so a delete that does not supply one cannot grow a second step. Only
        /// `presentTaskDelete` supplies one, and only for a task whose series the delete would
        /// otherwise end.
        let alternate: Alternate?

        /// What the confirmed action reports back.
        ///
        /// Most deletes on this manager cannot fail in a way the user could act on and are wrapped
        /// by `present(…)` to answer `.deleted` unconditionally. `presentRefusable(…)` is for the
        /// ones that can, and the refusal carries its own sentence.
        let attempt: () -> Outcome
    }

    /// The second confirm button on a delete that has two meanings, with its own words and its own
    /// attempt ([[T-6115]]).
    ///
    /// A *button*, not a scope. The manager is a macOS confirmation surface and knows nothing about
    /// recurrence; what it holds is a label and a closure, exactly as the primary confirm is a
    /// label and a closure. The `CadenceTaskRecurrenceDeleteScope` that chose both lives one frame
    /// up, in `presentTaskDelete`, which is the only thing in the app that builds one of these.
    ///
    /// It answers the same `Outcome` as the primary, so a refusal on either arm lands in the same
    /// still-open overlay with the same sentence — the whole of T-376, applied to both buttons
    /// rather than inherited by one.
    struct Alternate {
        let label: String
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
                alternate: nil,
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
        alternate: Alternate? = nil,
        attempt: @escaping () -> Outcome
    ) {
        present(
            request: Request(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                alternate: alternate,
                attempt: attempt
            )
        )
    }

    func confirm() {
        guard let request else { return }
        resolve(request.attempt)
    }

    /// Confirms the second button, when the request has one ([[T-6115]]). A no-op otherwise, which
    /// is what keeps a single-button confirmation single-button even if a future overlay forgets to
    /// hide the control.
    func confirmAlternate() {
        guard let alternate = request?.alternate else { return }
        resolve(alternate.attempt)
    }

    private func resolve(_ attempt: () -> Outcome) {
        failureNotice = nil

        switch attempt() {
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
    /// **A repeating task is asked which delete it is ([[T-6115]]).** Deleting the live occurrence
    /// used to end the whole series in silence, because `spawnNextOccurrenceIfNeeded` was reached
    /// only from `markDone` and `markCancelled` — so a user deleting today's occurrence to skip it
    /// lost every future one, and this sentence said only that the task would be permanently
    /// deleted. The owner's decision was the largest of the four shapes on offer: ask, the way
    /// Calendar does, and make "this occurrence" genuinely leave the repeat alive.
    ///
    /// **What a non-repeating task sees is byte-identical to before** — the same title, the same
    /// sentence, one `Delete` button and one step. The guard is
    /// `CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice`, which both platforms ask,
    /// so neither can decide on its own that a plain task has a series; its doc argues the two
    /// cases where a *repeating* task is also left alone, including the settled occurrence whose
    /// successor is already alive.
    ///
    /// **"Delete This Occurrence" is the primary button.** It is the arm that loses less — one row
    /// rather than a repeat — and it is what the user who opened a confirmation on today's
    /// occurrence overwhelmingly means. "Delete Series" is the `Alternate`, still red and still
    /// destructive, but not what `Return` presses.
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
        let attempt: (CadenceTaskRecurrenceDeleteScope) -> Outcome = { scope in
            willDelete()
            guard modelContext.deleteTask(task, recurrenceScope: scope, commit: commit) else {
                return .refused(notice: CadenceTaskMutationSupport.deleteFailureNotice)
            }
            return .deleted
        }

        guard CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: task) else {
            presentRefusable(
                title: "Delete Task?",
                message: "This will permanently delete \"\(title)\"."
            ) {
                attempt(.wholeSeries)
            }
            return
        }

        presentRefusable(
            title: CadenceRecurrenceScopeCopy.deleteScopeTitle,
            message: "\"\(title)\" repeats. " + CadenceRecurrenceScopeCopy.deleteScopeMessage,
            confirmLabel: CadenceTaskRecurrenceDeleteScope.thisOccurrence.label,
            alternate: Alternate(label: CadenceTaskRecurrenceDeleteScope.wholeSeries.label) {
                attempt(.wholeSeries)
            }
        ) {
            attempt(.thisOccurrence)
        }
    }
}
#endif

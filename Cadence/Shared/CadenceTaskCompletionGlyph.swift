import SwiftUI

/// The five things a task's completion control can be saying.
///
/// macOS spelled this as an ordered `if` chain in two places (`TaskCompletionButton` in
/// `TasksPanelComponents` and `KanbanCardComputedSupport`) and a two-state one in a third
/// (`TimelineTaskBlockSupportViews`); iOS had two states and no third, so **a cancelled task drew
/// exactly like an open one** on every iOS row, board card and timeline block. Cancelling is
/// reachable from the iOS swipe tray, the context menu and the inspector's Cancel button, so that
/// was a state the platform could enter and could not show.
///
/// The order of the tests below is load-bearing and is macOS's: a *settled* status wins over a
/// pending animation, so a task that finished completing while its ring was still filling reads
/// as done rather than as still-completing.
///
/// `.inProgress` deliberately resolves to `.todo`. The circle answers "is this finished?", and
/// in-progress is not; iOS says so with the status eyebrow above the title, macOS with the row's
/// own chrome.
nonisolated enum CadenceTaskCompletionState: String, CaseIterable, Equatable, Hashable {
    case todo
    /// Mid-animation on macOS only: the completion ring is filling and the tap can still be taken
    /// back. iOS completes immediately and never produces this.
    case pendingCompletion
    /// Mid-animation on macOS only, as above, for a cancellation.
    case pendingCancellation
    case done
    case cancelled

    static func resolve(
        status: TaskStatus,
        isPendingCompletion: Bool = false,
        isPendingCancellation: Bool = false
    ) -> Self {
        if status == .cancelled { return .cancelled }
        if status == .done { return .done }
        if isPendingCancellation { return .pendingCancellation }
        if isPendingCompletion { return .pendingCompletion }
        return .todo
    }

    static func resolve(
        task: AppTask,
        isPendingCompletion: Bool = false,
        isPendingCancellation: Bool = false
    ) -> Self {
        resolve(
            status: task.status,
            isPendingCompletion: isPendingCompletion,
            isPendingCancellation: isPendingCancellation
        )
    }

    /// Read by strikethrough and dimming, which treat "over" the same way whichever way it ended.
    var isSettled: Bool { self == .done || self == .cancelled }
}

/// What the completion control looks like for one state — the decision, with no view attached.
///
/// It is described twice over, once per platform's drawing primitive, because the two surfaces
/// genuinely render differently and always have: macOS stamps an SF Symbol (`symbolName`), iOS
/// draws a ring and fills it (`isFilled` + `mark`). Sharing the *decision* rather than the drawing
/// is the point — the thing that drifted was which states exist, not how a circle is stroked.
nonisolated struct CadenceTaskCompletionGlyph: Equatable {
    /// What sits inside the ring.
    enum Mark: Equatable {
        case none
        /// The inset disc macOS's `circle.inset.filled` draws while a completion is pending.
        case dot
        case checkmark
        case cross
    }

    let state: CadenceTaskCompletionState
    /// The SF Symbol macOS draws, tinted with `tint`. `.fill` variants are knockouts: the mark is
    /// the background showing through, which is why iOS draws its mark in `Theme.onColor` instead.
    let symbolName: String
    let mark: Mark
    /// Solid disc (settled) versus stroked ring (still open).
    let isFilled: Bool
    let tint: Color

    static func resolve(
        status: TaskStatus,
        priority: TaskPriority,
        isPendingCompletion: Bool = false,
        isPendingCancellation: Bool = false
    ) -> Self {
        let state = CadenceTaskCompletionState.resolve(
            status: status,
            isPendingCompletion: isPendingCompletion,
            isPendingCancellation: isPendingCancellation
        )
        return Self(state: state, priority: priority)
    }

    static func resolve(
        task: AppTask,
        isPendingCompletion: Bool = false,
        isPendingCancellation: Bool = false
    ) -> Self {
        resolve(
            status: task.status,
            priority: task.priority,
            isPendingCompletion: isPendingCompletion,
            isPendingCancellation: isPendingCancellation
        )
    }

    /// The two-state glyph for controls that are not backed by an `AppTask` and have no status to
    /// read — a `Subtask`'s tick, and the decorative circles in the swipe tray and the schedule
    /// placeholder row.
    static func binary(isDone: Bool, tint: Color) -> Self {
        isDone ? Self(state: .done, priority: .none) : Self(state: .todo, priorityTint: tint)
    }

    private init(state: CadenceTaskCompletionState, priority: TaskPriority) {
        self.init(state: state, priorityTint: Theme.priorityColor(priority))
    }

    private init(state: CadenceTaskCompletionState, priorityTint: Color) {
        self.state = state
        switch state {
        case .todo:
            symbolName = "circle"
            mark = .none
            isFilled = false
            // Priority, and only priority. Falling back to the *container* colour for an
            // unprioritised task made one glyph mean two things; both platforms rejected that.
            tint = priorityTint
        case .pendingCompletion:
            symbolName = "circle.inset.filled"
            mark = .dot
            isFilled = false
            tint = Theme.green
        case .pendingCancellation:
            symbolName = "xmark.circle"
            mark = .cross
            isFilled = false
            tint = Theme.dim
        case .done:
            symbolName = "checkmark.circle.fill"
            mark = .checkmark
            isFilled = true
            // Every priority converges here once a task is done — priority stops being shown.
            tint = Theme.doneFill
        case .cancelled:
            symbolName = "xmark.circle.fill"
            mark = .cross
            isFilled = true
            tint = Theme.dim
        }
    }
}

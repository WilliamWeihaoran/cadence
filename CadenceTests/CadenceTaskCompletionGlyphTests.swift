import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// Pins the state→appearance table for the task completion control (T-134).
///
/// The bug this covers: iOS drew two states — done and not-done — against macOS's five, so a
/// cancelled task was pixel-identical to an open one on every iOS surface. The table below is the
/// contract both platforms now render; a change to any row is a change to what the most-drawn
/// control in the app means, and should have to be made here first.
struct CadenceTaskCompletionGlyphTests {

    // MARK: - State resolution

    @Test func everyStatusAndPendingCombinationResolvesToExactlyOneState() {
        // Settled beats pending: a task that finished completing while its ring was still filling
        // reads as done, not as still-completing. This is macOS's original `if` order, and it is
        // the reason the tests below pass pending flags on already-settled statuses.
        #expect(CadenceTaskCompletionState.resolve(status: .todo) == .todo)
        #expect(CadenceTaskCompletionState.resolve(status: .inProgress) == .todo)
        #expect(CadenceTaskCompletionState.resolve(status: .done) == .done)
        #expect(CadenceTaskCompletionState.resolve(status: .cancelled) == .cancelled)

        #expect(CadenceTaskCompletionState.resolve(status: .todo, isPendingCompletion: true) == .pendingCompletion)
        #expect(CadenceTaskCompletionState.resolve(status: .todo, isPendingCancellation: true) == .pendingCancellation)

        // Pending cancel outranks pending complete — the tap being taken back is the newer one.
        #expect(
            CadenceTaskCompletionState.resolve(
                status: .todo,
                isPendingCompletion: true,
                isPendingCancellation: true
            ) == .pendingCancellation
        )

        // A settled status ignores both flags.
        for status in [TaskStatus.done, .cancelled] {
            let expected: CadenceTaskCompletionState = status == .done ? .done : .cancelled
            #expect(
                CadenceTaskCompletionState.resolve(
                    status: status,
                    isPendingCompletion: true,
                    isPendingCancellation: true
                ) == expected
            )
        }
    }

    /// `.inProgress` is deliberately not its own glyph state: the circle answers "is this
    /// finished?", and in-progress is not. If someone adds a sixth state this test is where the
    /// decision has to be re-argued.
    @Test func inProgressIsNotADistinctGlyphState() {
        #expect(CadenceTaskCompletionState.allCases.count == 5)
        #expect(
            CadenceTaskCompletionGlyph.resolve(status: .inProgress, priority: .high)
                == CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .high)
        )
    }

    @Test func onlyDoneAndCancelledCountAsSettled() {
        let settled = CadenceTaskCompletionState.allCases.filter(\.isSettled)
        #expect(Set(settled) == Set([.done, .cancelled]))
    }

    // MARK: - The appearance table

    @Test func eachStateHasItsOwnSymbolFillAndMark() {
        // Five states, five distinct symbols. macOS renders these directly; the count is what
        // regressed on iOS.
        let symbols = CadenceTaskCompletionState.allCases.map { state in
            CadenceTaskCompletionGlyph.resolve(
                status: state == .done ? .done : (state == .cancelled ? .cancelled : .todo),
                priority: .none,
                isPendingCompletion: state == .pendingCompletion,
                isPendingCancellation: state == .pendingCancellation
            ).symbolName
        }
        #expect(Set(symbols).count == 5)

        let todo = CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .none)
        #expect(todo.symbolName == "circle")
        #expect(todo.mark == .none)
        #expect(todo.isFilled == false)

        let pendingDone = CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .none, isPendingCompletion: true)
        #expect(pendingDone.symbolName == "circle.inset.filled")
        #expect(pendingDone.mark == .dot)
        #expect(pendingDone.isFilled == false)
        #expect(pendingDone.tint == Theme.green)

        let pendingCancel = CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .none, isPendingCancellation: true)
        #expect(pendingCancel.symbolName == "xmark.circle")
        #expect(pendingCancel.mark == .cross)
        #expect(pendingCancel.isFilled == false)
        #expect(pendingCancel.tint == Theme.dim)

        let done = CadenceTaskCompletionGlyph.resolve(status: .done, priority: .high)
        #expect(done.symbolName == "checkmark.circle.fill")
        #expect(done.mark == .checkmark)
        #expect(done.isFilled)
        #expect(done.tint == Theme.doneFill)

        let cancelled = CadenceTaskCompletionGlyph.resolve(status: .cancelled, priority: .high)
        #expect(cancelled.symbolName == "xmark.circle.fill")
        #expect(cancelled.mark == .cross)
        #expect(cancelled.isFilled)
        #expect(cancelled.tint == Theme.dim)
    }

    /// The regression itself, stated as a single expectation: a cancelled task must not draw the
    /// same control as an open one. It did on iOS, at every priority.
    @Test func aCancelledTaskNeverRendersLikeAnOpenOne() {
        for priority in TaskPriority.allCases {
            let open = CadenceTaskCompletionGlyph.resolve(status: .todo, priority: priority)
            let cancelled = CadenceTaskCompletionGlyph.resolve(status: .cancelled, priority: priority)
            #expect(open != cancelled)
            #expect(open.symbolName != cancelled.symbolName)
            #expect(open.mark != cancelled.mark)
            #expect(open.isFilled != cancelled.isFilled)
        }
    }

    // MARK: - Tint

    @Test func priorityTintsOnlyTheOpenStateAndEveryPriorityConvergesOnceSettled() {
        for priority in TaskPriority.allCases {
            #expect(
                CadenceTaskCompletionGlyph.resolve(status: .todo, priority: priority).tint
                    == Theme.priorityColor(priority)
            )
            // Priority stops being shown once a task is over — CLAUDE.md's rule, and the reason
            // `Theme.doneFill` exists as its own token.
            #expect(CadenceTaskCompletionGlyph.resolve(status: .done, priority: priority).tint == Theme.doneFill)
            #expect(CadenceTaskCompletionGlyph.resolve(status: .cancelled, priority: priority).tint == Theme.dim)
        }

        // A high-priority open task is red and a none-priority open task is dim — the glyph is a
        // priority readout while the task is open, and nothing else.
        #expect(CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .high).tint == Theme.red)
        #expect(CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .none).tint == Theme.dim)
    }

    // MARK: - The non-task entry point

    /// `binary` backs the controls with no status behind them: a `Subtask`'s tick and the two
    /// decorative circles. It must keep honouring a caller-supplied tint while open, and must
    /// still converge on `doneFill` when ticked.
    @Test func binaryGlyphKeepsItsCallerTintWhileOpenAndConvergesWhenDone() {
        let openCustom = CadenceTaskCompletionGlyph.binary(isDone: false, tint: Theme.purple)
        #expect(openCustom.state == .todo)
        #expect(openCustom.tint == Theme.purple)
        #expect(openCustom.isFilled == false)
        #expect(openCustom.mark == .none)

        let ticked = CadenceTaskCompletionGlyph.binary(isDone: true, tint: Theme.purple)
        #expect(ticked.state == .done)
        #expect(ticked.tint == Theme.doneFill)
        #expect(ticked.mark == .checkmark)
        #expect(ticked.isFilled)
    }
}

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
            // Priority stops being shown once a task is over — the archived Claude reference's
            // rule, and the reason `Theme.doneFill` exists as its own token.
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

    // MARK: - T-8202 / T-9401: the window the control is drawing

    /// **The owner's ruling, as the one number that is left.**
    ///
    /// "1.2s total" is not cosmetic: `animationDuration` gates the `.done` write itself, so it is
    /// the undo window a mis-tap can be withdrawn inside. The ruling it came from also put a check
    /// mark at halfway; on 2026-10-31 the owner removed the mark and kept the window ([[T-9401]]),
    /// so the threshold, the derived delay and the showsConfirmation helper went with it.
    /// What stays pinned here is the window, and that the type says nothing else.
    @Test func theCompletionWindowIsTwelveHundredMillisecondsAndIsTheOnlyTimingStated() throws {
        #expect(CadenceTaskCompletionTiming.animationDuration == 1.2)

        // The removed members are removed, not merely uncalled: a constant describing a mark that
        // never appears is exactly what [[T-9401]] was spent clearing, so a reinstated one must
        // red here rather than sit unread. Source-scanned because a reference to a deleted member
        // would not compile, so this cannot be written as an expression.
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskCompletionTiming.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code.contains("enum CadenceTaskCompletionTiming"), "the scan did not read the timing file")
        #expect(code != raw, "nothing was stripped, so the scan is reading prose as code")
        #expect(code.count == raw.count, "the stripper changed the length, so offsets no longer hold")
        #expect(code.contains("static let animationDuration"), "the window itself is gone")
        for gone in ["confirmationThreshold", "confirmationDelay", "showsConfirmation"] {
            #expect(!code.contains(gone), "`\(gone)` is back: a mark that never appears has an API again")
        }
    }

    /// **A filling ring never shows a mark, at any progress ([[T-9401]]).**
    ///
    /// The old rule was "from the midpoint onward"; the owner watched it and ruled the mark out
    /// altogether, ring and window untouched. The readings below are the ones that separated the
    /// two previous rules — 0.4999 against 0.5, and 0.6 against 0.7 — plus the ends and the raw
    /// out-of-range values a caller's `elapsed / animationDuration` can hand over. Every one of
    /// them is now the same answer, which is the point.
    @Test func aFillingRingShowsNoMarkAtAnyProgress() {
        func filling(_ progress: Double, cancelling: Bool = false) -> CadenceTaskCompletionCircleFace {
            .resolve(
                glyph: .resolve(
                    status: .todo,
                    priority: .high,
                    isPendingCompletion: !cancelling,
                    isPendingCancellation: cancelling
                ),
                progress: progress
            )
        }

        for progress in [-3, 0, 0.4999, 0.5, 0.5000001, 0.6, 0.7, 1, 4.2] as [Double] {
            #expect(!filling(progress).showsMark, "the fill marked itself at \(progress)")
            #expect(!filling(progress, cancelling: true).showsMark, "the cancellation marked itself at \(progress)")
        }

        // Still a fill, though: the ring it is drawing is unchanged, clamped as before, and it
        // still knows which mark it would be — the face just does not draw one.
        #expect(filling(0.25).ring == .filling(0.25))
        #expect(filling(4.2).ring == .filling(1))
        #expect(filling(-3).ring == .filling(0))
        #expect(filling(0.5).mark == .checkmark)
        #expect(filling(0.5, cancelling: true).mark == .cross)

        // And the distinction survives: a resting face still marks. Both halves in one test so a
        // blanket `showsMark = false` cannot pass by making everything silent.
        let settled = CadenceTaskCompletionCircleFace.resolve(
            glyph: .resolve(status: .done, priority: .high, isPendingCompletion: false, isPendingCancellation: false),
            progress: nil
        )
        #expect(settled.showsMark)
        #expect(settled.mark == .checkmark)
    }

    // MARK: - T-8411: one drawn circle for both platforms

    /// **The drawing keeps no threshold of its own, and no longer asks for one ([[T-9401]]).**
    /// Moved here from `TaskCompletionAnimationManagerTests` with the circle it reads ([[T-8411]]).
    ///
    /// Until 2026-10-31 this pinned the opposite: that the view asked the shared timing when to
    /// mark, because a literal here silently stopped meaning "halfway" whenever the window moved.
    /// The owner then removed the mid-fill mark entirely, so the pin becomes its mirror — the
    /// filling arm resolves `showsMark: false` flat, the resting arm still resolves `true`, and no
    /// numeric cue reappears in between. Written over the source because the two arms are literal
    /// arguments inside `resolve`, which no expression test can tell apart from its result alone.
    @Test func theFillingRingResolvesNoMarkAndSpellsNoThresholdOfItsOwn() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTaskCompletionCircle.swift")
        let code = CadenceSourceScan.codeOnly(raw)

        // Non-vacuity: the read found the right file, and the stripper ran without shortening it.
        #expect(code.contains("struct CadenceTaskCompletionCircleFace"), "the scan did not read the circle's file")
        #expect(code != raw, "nothing was stripped, so the scan is reading prose as code")
        #expect(code.count == raw.count, "the stripper changed the length, so offsets no longer hold")

        #expect(
            CadenceSourceScan.matchCount(#"showsMark: false"#, in: code) == 1,
            "the filling face no longer resolves `showsMark: false`, so a fill can mark itself again"
        )
        #expect(
            CadenceSourceScan.matchCount(#"showsMark: true"#, in: code) == 1,
            "the resting face no longer resolves `showsMark: true`, so a settled disc lost its mark"
        )
        #expect(
            !code.contains("showsConfirmation"),
            "the circle asks for a confirmation mark again"
        )
        let comparison = #"\b(fill|progress)\s*[<>]=?\s*[0-9.]+"#
        #expect(CadenceSourceScan.matchCount(comparison, in: code) == 0, "the circle spells its own threshold again")
        #expect(CadenceSourceScan.matchCount(comparison, in: "let shown = fill > 0.7") == 1)
        #expect(CadenceSourceScan.matchCount(comparison, in: "let shown = somethingElse > 0.7") == 0)
    }

    /// The face each state draws, which is the same on both platforms because there is one table.
    /// Resting: open ring for open and pending glyphs, a disc for settled ones. A pending glyph with
    /// no progress — Reduce Motion ([[T-8412]]) — keeps its own still mark rather than a bare track.
    @Test func eachStateDrawsOneFaceWhetherStillOrFilling() {
        func glyph(_ status: TaskStatus, completing: Bool = false, cancelling: Bool = false) -> CadenceTaskCompletionGlyph {
            .resolve(status: status, priority: .high, isPendingCompletion: completing, isPendingCancellation: cancelling)
        }
        typealias Face = CadenceTaskCompletionCircleFace

        #expect(Face.resolve(glyph: glyph(.todo), progress: nil) == Face(ring: .open, mark: .none, showsMark: true))
        #expect(Face.resolve(glyph: glyph(.done), progress: nil) == Face(ring: .filled, mark: .checkmark, showsMark: true))
        #expect(Face.resolve(glyph: glyph(.cancelled), progress: nil) == Face(ring: .filled, mark: .cross, showsMark: true))
        #expect(Face.resolve(glyph: glyph(.todo, completing: true), progress: nil) == Face(ring: .open, mark: .dot, showsMark: true))
        #expect(Face.resolve(glyph: glyph(.todo, cancelling: true), progress: nil) == Face(ring: .open, mark: .cross, showsMark: true))

        // Filling: the ring sweeps and says nothing while it does ([[T-9401]]).
        #expect(Face.resolve(glyph: glyph(.todo, completing: true), progress: 0.25) == Face(ring: .filling(0.25), mark: .checkmark, showsMark: false))
        #expect(Face.resolve(glyph: glyph(.todo, completing: true), progress: 0.5) == Face(ring: .filling(0.5), mark: .checkmark, showsMark: false))
        #expect(Face.resolve(glyph: glyph(.todo, cancelling: true), progress: 0.75) == Face(ring: .filling(0.75), mark: .cross, showsMark: false))
        // Clamped, so a raw `elapsed / duration` cannot draw past a full ring.
        #expect(Face.resolve(glyph: glyph(.todo, completing: true), progress: 3) == Face(ring: .filling(1), mark: .checkmark, showsMark: false))

        // A settled or open glyph ignores a progress reading: only a pending one fills.
        #expect(Face.resolve(glyph: glyph(.done), progress: 0.3) == Face(ring: .filled, mark: .checkmark, showsMark: true))
        #expect(Face.resolve(glyph: glyph(.todo), progress: 0.3) == Face(ring: .open, mark: .none, showsMark: true))
    }

    /// The board column's circle is three rows of the same table: open in dim, completing green,
    /// completed as a done disc. It spelled these as three SF Symbol names inline before [[T-8411]].
    @Test func aColumnCircleIsOpenCompletingOrCompleted() {
        let open = CadenceTaskCompletionGlyph.column(isCompleted: false, isPendingCompletion: false)
        let completing = CadenceTaskCompletionGlyph.column(isCompleted: false, isPendingCompletion: true)
        let completed = CadenceTaskCompletionGlyph.column(isCompleted: true, isPendingCompletion: true)
        #expect(open.state == .todo)
        #expect(open.tint == Theme.dim)
        #expect(completing.state == .pendingCompletion)
        #expect(completing.tint == Theme.green)
        #expect(completed.state == .done, "a settled column must not read as still completing")
        #expect(completed.tint == Theme.green)
    }

    /// One drawing: declared once, in `Shared/`, and every completion control on both platforms
    /// draws it. The SF Symbol glyph macOS drew is gone rather than kept beside it.
    @Test func everyCompletionControlDrawsTheOneSharedCircle() throws {
        let shared = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTaskCompletionCircle.swift"))
        #expect(CadenceSourceScan.matchCount(#"struct CadenceTaskCompletionCircle\b"#, in: shared) == 1)

        let hosts = [
            "Cadence/macOS/Views/TasksPanelComponents.swift",
            "Cadence/macOS/Views/KanbanCardSupportViews.swift",
            "Cadence/macOS/Views/KanbanColumnSupportViews.swift",
            "Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift",
            "Cadence/macOS/Views/ListDetailSupportViews.swift",
            "Cadence/iOS/iOSFeatureComponents.swift",
        ]
        for path in hosts {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceTaskCompletionCircle("), "\(path) no longer draws the shared circle")
        }

        var everything = ""
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            everything += CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        }
        #expect(everything.contains("struct CadenceTaskCompletionCircle"), "non-vacuity: the sweep did not read Shared")
        #expect(!everything.contains("TaskCompletionProgressGlyph"), "macOS draws its own completion glyph again")
        #expect(!everything.contains("struct iOSTaskCompletionCircle"), "iOS draws its own completion circle again")
    }
}

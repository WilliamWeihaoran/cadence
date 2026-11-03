import CoreGraphics
import Foundation

// **A task-embed card's circle joins the deferred completion ([[T-8395]], owner call: both
// platforms).**
//
// The row, the board card, the swipe and the timeline block fill for
// `CadenceTaskCompletionTiming.animationDuration` with a take-back ([[T-8203]]); the embed card's
// circle — in a note, in Focus's task notes, in the inspector's notes, on both platforms — wrote
// at once. It now asks the same `TaskCompletionAnimationManager.advanceCompletionControl(for:)`
// every other circle asks, so the clock, the three-tap walk, the termination and scene-phase
// settle and the settled-elsewhere guard are the one object's, not a second copy.
//
// What is new is only what the card needs because it is not a SwiftUI view: it is drawn from a
// `MarkdownTaskEmbedRenderInfo` snapshot by the editor (an AppKit decoration on macOS, a canvas
// image on iOS), so nothing re-renders it while the fill runs or when the deferred write lands.
// `CadenceTaskEmbedCompletionDriver` is that repaint, and `CadenceTaskEmbedPendingFill` is what
// both editors draw over the resting circle.

/// A running deferral as the card draws it.
nonisolated struct CadenceTaskEmbedPendingFill: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Green, settling as done.
        case completing
        /// Grey, settling as cancelled — the second tap of the walk.
        case cancelling
    }

    let kind: Kind
    /// How far the window has run, `0...1`.
    let progress: Double

    /// The swept wedge inside the circle `rect`, clockwise from twelve o'clock, for a y-down
    /// context — both editors draw flipped (`NSTextView.isFlipped`, UIKit's image renderer).
    ///
    /// A wedge **fill** rather than a ring reveal: the card's resting open circle is already a dim
    /// ring, and a grey cancellation revealed over a grey ring would not show at all.
    func wedgePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = -CGFloat.pi / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: start + 2 * .pi * CGFloat(fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    /// Draws the fill over a circle already drawn in `rect`. `reducesMotion` draws the whole disc at
    /// a steady weight instead of a sweep, as the SwiftUI circle draws its still pending glyph
    /// under Reduce Motion ([[T-8412]]).
    func draw(in rect: CGRect, tint: CGColor, reducesMotion: Bool, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let disc = rect.insetBy(dx: 2.5, dy: 2.5)
        context.setFillColor(tint)
        if reducesMotion {
            context.setAlpha(0.45)
            context.addEllipse(in: disc)
        } else {
            context.setAlpha(0.9)
            context.addPath(wedgePath(in: disc))
        }
        context.fillPath()
    }
}

extension TaskCompletionAnimationManager {
    /// The running fill for the task `id`, completion first as `pendingProgress(for:now:)` has it,
    /// or `nil` when none is running. By id because the editors hold render snapshots, not tasks.
    func embedPendingFill(forTaskID id: UUID, now: Date = Date()) -> CadenceTaskEmbedPendingFill? {
        let duration = CadenceTaskCompletionTiming.animationDuration
        if let start = pendingStartTimes[id] {
            return CadenceTaskEmbedPendingFill(
                kind: .completing,
                progress: min(max(now.timeIntervalSince(start) / duration, 0), 1)
            )
        }
        if let start = pendingCancelStartTimes[id] {
            return CadenceTaskEmbedPendingFill(
                kind: .cancelling,
                progress: min(max(now.timeIntervalSince(start) / duration, 0), 1)
            )
        }
        return nil
    }
}

/// The repaint for an embed card while its deferral runs, and once when it ends.
///
/// One per editor. `tap(_:)` is the card circle's whole action: it walks the shared control and
/// then `track`s the task, repainting its circle every frame while the manager still holds a fill
/// for it. The frame the manager stops holding one — the write landed, the tap was taken back, or a
/// settled task was restored at once — it calls `settled`, which is where the editor rebuilds the
/// card from the task as it now is. iOS's editor cannot reach the `AppTask` (its surface resolves
/// the id), so it walks the control there and `track`s the id here.
final class CadenceTaskEmbedCompletionDriver {
    /// ~30 fps: the circle is 22pt, and a 60 fps redraw of a text view buys nothing it can show.
    static let frameInterval: TimeInterval = 1.0 / 30

    private let manager: TaskCompletionAnimationManager
    /// Redraw the card's circle for this task id; the fill is read from the manager at draw time.
    var repaint: (UUID) -> Void = { _ in }
    /// The deferral for this task id ended; rebuild its card.
    var settled: (UUID) -> Void = { _ in }

    private var tracked: Set<UUID> = []
    private var timer: Timer?

    /// `nil` is the shared manager, resolved here rather than in a default argument, which is
    /// evaluated outside the main actor that `shared` belongs to.
    init(manager: TaskCompletionAnimationManager? = nil) {
        self.manager = manager ?? .shared
    }

    var isTracking: Bool { !tracked.isEmpty }

    /// The card circle's tap: the three-tap walk every task circle takes ([[T-8203]]), then the
    /// repaint until it settles.
    func tap(_ task: AppTask) {
        manager.advanceCompletionControl(for: task)
        track(task.id)
    }

    func track(_ id: UUID) {
        tracked.insert(id)
        tick()
        guard isTracking, timer == nil else { return }
        // Weak, and the timer stops itself once its editor is gone: a timer holds its block until
        // it is invalidated, and nothing else would.
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.tick()
            }
        }
        // `.common`, so the fill keeps running while the note scrolls.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One frame. Callable so a test steps it without a run loop ([[T-268]]: no sleep-and-assert).
    func tick(now: Date = Date()) {
        for id in tracked {
            if manager.embedPendingFill(forTaskID: id, now: now) != nil {
                repaint(id)
            } else {
                tracked.remove(id)
                settled(id)
            }
        }
        if tracked.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}

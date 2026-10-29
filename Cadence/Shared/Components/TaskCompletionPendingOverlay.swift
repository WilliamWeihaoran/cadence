import SwiftUI

/// The row-wide half of a deferred completion: while a task's fill runs, the whole row (or card,
/// or block) carries a tinted wash with a glow sweeping across it and a progress capsule along its
/// foot, green for a completion and grey for a cancellation.
///
/// **One drawing for both platforms ([[T-8354]]).** This lived in
/// `macOS/Views/TaskCompletionAnimationViews.swift`, so the macOS task row, Kanban card and
/// timeline block swept while their iOS counterparts showed only the ring -- a UI difference no
/// hardware or input constraint names, which is drift under [[T-8201]]. It moved here whole rather
/// than being copied; macOS's call sites still spell `TaskCompletionPendingOverlay(...)` and are
/// unchanged.
///
/// The sweep's clock is the ring's: both read `TaskCompletionAnimationManager`'s progress, which is
/// `elapsed / CadenceTaskCompletionTiming.animationDuration`, so the glow reaches the far edge on
/// the same frame the ring closes.
struct TaskCompletionPendingOverlay: View {
    let progress: Double
    let tint: Color
    var cornerRadius: CGFloat = 8

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let progressWidth = max(12, width * CGFloat(clampedProgress))
            let glowWidth = min(86, max(34, width * 0.18))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(0.075))

                Capsule()
                    .fill(tint.opacity(0.18))
                    .frame(width: glowWidth, height: height * 1.35)
                    .blur(radius: 16)
                    .offset(x: (width + glowWidth) * CGFloat(clampedProgress) - glowWidth)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(tint.opacity(0.62))
                        .frame(width: progressWidth, height: 2.5)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
            // The sweeping glow capsule is deliberately TALLER than the host view
            // (height * 1.35) and blurred, so the ZStack's own layout size grows past
            // the geometry proposal. `.clipShape` clips to the view's own bounds, so
            // clipping the raw ZStack clips to that oversized box — and since
            // GeometryReader never clips its content, the green sweep painted outside
            // the host block. Pin back to the proposed size FIRST, then clip, so the
            // fill/border sit exactly on the block's rounded rect and nothing can
            // escape it in any direction.
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

/// Which sweep, if any, a task's row should be drawing right now ([[T-8354]]).
///
/// The decision behind `TaskCompletionPendingSweep`, lifted out of a `body` so a unit test can
/// reach it. Completion is asked first, the order `TaskCompletionAnimationManager.glyph(for:)` and
/// `pendingProgress(for:now:)` already use, so the wash and the ring cannot name two different
/// deferrals for one task.
struct CadenceTaskCompletionSweepFrame: Equatable {
    /// How far the deferral has run, `0...1`.
    let progress: Double
    /// A cancellation sweeps grey; a completion sweeps green.
    let isCancellation: Bool

    var tint: Color { isCancellation ? Theme.dim : Theme.green }

    @MainActor
    static func resolve(
        for task: AppTask,
        in manager: TaskCompletionAnimationManager? = nil,
        now: Date = Date()
    ) -> CadenceTaskCompletionSweepFrame? {
        // Optional rather than defaulted to `.shared`: a default argument is evaluated outside the
        // main actor, where the main-actor `shared` cannot be read.
        let manager = manager ?? .shared
        if manager.isPending(task) {
            return CadenceTaskCompletionSweepFrame(progress: manager.progress(for: task, now: now), isCancellation: false)
        }
        if manager.isPendingCancel(task) {
            return CadenceTaskCompletionSweepFrame(progress: manager.cancelProgress(for: task, now: now), isCancellation: true)
        }
        return nil
    }
}

/// The live host the iOS task row, board card and Calendar timed block lay over themselves
/// ([[T-8354]]): `TaskCompletionPendingOverlay`, fed by the shared manager while this task's fill
/// runs.
///
/// **`TimelineView(.animation)` is in the hierarchy only while this task is pending**, the gate
/// `iOSTaskCompletionFill` keeps for the ring and for the same reason: an ungated display-link
/// redraw would repaint every visible row at screen rate for ever.
///
/// **Reduce Motion draws no sweep.** The sweep is nothing but motion, and the ring beside it already
/// draws the pending state still under that setting (`iOSTaskCompletionFill`), so the row says
/// "pending" without anything moving. macOS's ring and sweep do not read the setting yet; that gap
/// is [[T-8412]], not a reason to animate here.
struct TaskCompletionPendingSweep: View {
    let task: AppTask
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion, CadenceTaskCompletionSweepFrame.resolve(for: task) != nil {
            TimelineView(.animation) { context in
                if let frame = CadenceTaskCompletionSweepFrame.resolve(for: task, now: context.date) {
                    TaskCompletionPendingOverlay(
                        progress: frame.progress,
                        tint: frame.tint,
                        cornerRadius: cornerRadius
                    )
                }
            }
        }
    }
}

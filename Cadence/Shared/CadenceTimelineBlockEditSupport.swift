import CoreGraphics
import Foundation
import SwiftData

/// Moving and edge-resizing a task's **own** time on a touch timeline ([[T-1475]]).
///
/// **What this is not.** [[T-3170]] removed the block-on-block drag that *formed a Block*, for
/// good. Nothing here forms, joins or leaves a bundle: the only fields written are the task's own
/// `scheduledStartMin` and, for a resize, `estimatedMinutes` — the two the Mac canvas's move drop
/// and edge strips have always written (`SchedulingActions.dropTask`,
/// `TimelineTaskBlockInteractionSupport.updateResize`). There is no drag payload and no drop
/// destination; the gesture is resolved inside the day column that drew the block.
///
/// **The arithmetic is here, not in the view, so a test can ask it** what a drag offset means in
/// minutes without a gesture recognizer, and so the move and the two edges cannot each grow their
/// own idea of the grid.
enum CadenceTimelineBlockEdit {
    /// Which part of the block the finger took hold of.
    enum Kind: Equatable {
        case move
        case resizeStart
        case resizeEnd
    }

    /// **The touch grid, not the Mac's pointer grid — the same rule, read for the same reason**
    /// (T-1293, `CadenceScheduleSupport.touchTimeGridMinutes`). The Mac snaps a pointer drag to
    /// 5 minutes because a pointer can aim at 5 minutes; on a 58pt hour row 5 minutes is under five
    /// points, narrower than the finger covering it. Apple Calendar — the owner's reference for
    /// this surface ([[T-3168]]) — drags a block in quarter hours for exactly that reason, and every
    /// other placement on this canvas (tap, dropped `+`, press-and-hold draft) already lands on the
    /// touch grid, so a moved block lands on a minute the rest of the screen can also express.
    static let gridMinutes = CadenceScheduleSupport.touchTimeGridMinutes

    /// Shortest a resize may leave a block: one grid step, the draft block's own floor
    /// (`CadenceScheduleDraft.minimumDurationMinutes`), and the shortest block the iOS canvas draws
    /// (`CadenceScheduleSupport.blockRange`).
    static let minimumDurationMinutes = CadenceScheduleSupport.touchTimeGridMinutes

    /// How long a finger must rest on a block before it lifts. The canvas's own press-and-hold
    /// draft (`iOSCalendarTimelineDayColumn.draftPressGesture`) uses the same figure — it reads it
    /// from here since [[T-7550]] rather than repeating the number — so a press is one length
    /// everywhere on the grid. A finger that moves first is a scroll, which the hold fails on; that
    /// is the whole reason for the hold.
    ///
    /// **That last sentence was a claim about the gesture, and for a while it was false**
    /// ([[T-7550]]). It is true of UIKit's long press and not of SwiftUI's
    /// `LongPressGesture.sequenced(before: DragGesture)`, which both call sites used: a finger
    /// that moved first scrolled nothing at all, because the SwiftUI drag had already taken the
    /// touch from the enclosing `ScrollView`. `iOSTimelinePressDragRecognizer` is what makes the
    /// sentence true, and it is where the measurement lives.
    static let liftPressDuration: Double = 0.35

    /// The touch band each resize handle answers to: the 44pt minimum, not the 2–4pt of paint.
    static let handleTouchTarget: CGFloat = 44

    /// Block interior the handles never cover, so a lifted short block can still be pressed to move.
    static let minimumMoveCoreHeight: CGFloat = 16

    /// How far a handle's touch band reaches **inside** a block drawn `blockHeight` tall; the rest
    /// of the 44pt band hangs outside the edge, the same trade `iOSTimelineDraftBlock.edgeHandle`
    /// makes. Never more than half the band, and never into `minimumMoveCoreHeight`.
    static func handleInsideReach(blockHeight: CGFloat) -> CGFloat {
        let available = max(0, (blockHeight - minimumMoveCoreHeight) / 2)
        return min(handleTouchTarget / 2, available)
    }

    /// A vertical drag offset as a whole number of grid steps, in minutes. Rounded, not floored, so
    /// a drag of half a step either way lands on the nearer line rather than always the earlier one.
    static func snappedMinuteDelta(
        translationY: CGFloat,
        hourHeight: CGFloat,
        gridMinutes: Int = gridMinutes
    ) -> Int {
        guard hourHeight > 0 else { return 0 }
        let grid = max(1, gridMinutes)
        let rawMinutes = Double(translationY / hourHeight) * 60
        return Int((rawMinutes / Double(grid)).rounded()) * grid
    }

    /// The block's minute range partway through, or at the end of, an edit.
    ///
    /// A move keeps the duration and slides both ends by the snapped delta, stopping at the edges
    /// of the drawn day. A resize moves one end and pins the other, never closer than
    /// `minimumDurationMinutes` to it. The delta is **relative** — a task at 9:07 dragged one step
    /// lands at 9:22 — so a press that never travels a step changes nothing, which is what lets the
    /// caller skip the commit for a lift-and-release.
    static func editedRange(
        kind: Kind,
        start: Int,
        end: Int,
        translationY: CGFloat,
        hourHeight: CGFloat,
        dayStartMinute: Int = CadenceScheduleSupport.calendarStartHour * 60,
        dayEndMinute: Int = CadenceScheduleSupport.calendarEndHour * 60
    ) -> (start: Int, end: Int) {
        let delta = snappedMinuteDelta(translationY: translationY, hourHeight: hourHeight)
        let duration = max(minimumDurationMinutes, end - start)
        switch kind {
        case .move:
            let latestStart = max(dayStartMinute, dayEndMinute - duration)
            let movedStart = min(max(start + delta, dayStartMinute), latestStart)
            return (movedStart, movedStart + duration)
        case .resizeStart:
            let latestStart = max(dayStartMinute, end - minimumDurationMinutes)
            let movedStart = min(max(start + delta, dayStartMinute), latestStart)
            return (movedStart, end)
        case .resizeEnd:
            let earliestEnd = min(dayEndMinute, start + minimumDurationMinutes)
            let movedEnd = max(min(end + delta, dayEndMinute), earliestEnd)
            return (start, movedEnd)
        }
    }

    /// Writes an edit's result to the task and commits it, answering whether it is in the store.
    ///
    /// **The field transaction the iOS board's day drop answers with** ([[T-1470]]):
    /// `CadenceTaskFieldEditCommit.commit` snapshots the task, applies the write, and on a refused
    /// save puts every field back — without rolling back the one app-wide context and taking other
    /// surfaces' pending edits with it. `false` therefore means the task is exactly where it was,
    /// so the caller's block, which draws the stored minute, is already back at its origin; the
    /// caller's only remaining job is to say so on screen.
    ///
    /// A move writes the start alone and leaves `estimatedMinutes` as it was, so moving a task
    /// with no estimate does not invent one. A resize writes both ends.
    ///
    /// The notification reconcile is the one `CadenceTaskDateEditing` runs after a time edit
    /// (T-362): the reminder for the old minute must not survive the move. A refusal has already
    /// reconciled inside the commit's undo, so it runs here only for a change that landed.
    @MainActor
    @discardableResult
    static func commit(
        _ task: AppTask,
        kind: Kind,
        range: (start: Int, end: Int),
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: context,
            reconciler: reconciler,
            commit: commit
        ) {
            task.scheduledStartMin = range.start
            if kind != .move {
                task.estimatedMinutes = max(minimumDurationMinutes, range.end - range.start)
            }
        }
        if landed {
            (reconciler ?? .default).run(in: context)
        }
        return landed
    }
}

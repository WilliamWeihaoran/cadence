import CoreGraphics
import Foundation
import SwiftData

/// Moving and edge-resizing a task's **own** time on a touch timeline ([[T-1475]]).
///
/// **What this is not.** [[T-3170]] removed the block-on-block drag that *formed a Block*, for
/// good. Nothing here forms, joins or leaves a bundle: the only fields written are the task's own
/// `scheduledStartMin` (with `scheduledDate` for a move onto another day) and, for a resize,
/// `estimatedMinutes` — the fields the Mac canvas's move drop and edge strips have always written (`SchedulingActions.dropTask`,
/// `TimelineTaskBlockInteractionSupport.updateResize`). There is no drag payload and no drop
/// destination; the gesture is resolved by the day column that drew the block.
///
/// **The arithmetic is here, not in the view, so a test can ask it** what a drag offset means in
/// minutes without a gesture recognizer, and so the move and the two edges cannot each grow their
/// own idea of the grid.
///
/// **A move may cross days on a scrolling grid** ([[T-8301]]): the Mac's Week canvas has always
/// dropped a block on another day, and the owner chose full parity ([[T-1475]], [[T-8201]]). The
/// move is still resolved inside the press recognizer — no payload, no drop destination — by
/// `dayDelta`, and written by `commit(_:kind:range:onDay:in:)`.
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

    /// How many day columns a **moved** block's finger has crossed, Week canvas to Week canvas
    /// ([[T-8301]]).
    ///
    /// macOS moves a block onto another day through one page-wide `TimelineTaskDragSession`: the
    /// system drag is over whichever column the pointer is in, and that column's day is where the
    /// block lands. A touch block has no system drag — the move stays inside the press recognizer
    /// ([[T-7550]]) — so the column under the finger is computed instead: where the finger went
    /// down in its own column (`grabX`, the column's own space), plus how far it has travelled
    /// sideways, in whole column widths, **floored** — the finger is over column `n` from its
    /// leading edge to its trailing one, not from half a column before it.
    ///
    /// `allowed` is the run of columns the finger can be released over: the ones on screen
    /// (`visibleDayDeltaRange`) on a scrolling grid, `0...0` on a single-day pane, which has no
    /// other day to move to. A finger that strays over the hour rail or past the trailing edge
    /// lands on the nearest day in view, never on a column the user cannot see.
    static func dayDelta(
        grabX: CGFloat,
        translationX: CGFloat,
        columnWidth: CGFloat,
        allowed: ClosedRange<Int>
    ) -> Int {
        guard columnWidth > 0 else { return 0 }
        let raw = Int(((grabX + translationX) / columnWidth).rounded(.down))
        return min(max(raw, allowed.lowerBound), allowed.upperBound)
    }

    /// The day offsets a block in column `columnIndex` may move by: every column from the leading
    /// one on screen to the last one on screen. Always contains `0`, so a block in a column that is
    /// only half on screen can still be moved within its own day.
    static func visibleDayDeltaRange(
        columnIndex: Int,
        leadingIndex: Int,
        visibleDayCount: Int
    ) -> ClosedRange<Int> {
        let lower = leadingIndex - columnIndex
        let upper = leadingIndex + max(1, visibleDayCount) - 1 - columnIndex
        return min(lower, 0)...max(upper, 0)
    }

    /// The overlap slot a moved block is drawn in while it is carried ([[T-8452]]).
    ///
    /// Over its own day (`dayDelta == 0`) it keeps the slot its day solved for it, so its neighbours
    /// hold still under it. Over **any other day** it is a lone block (`.single`): the full slot of
    /// that column, in front of whatever is there, with the target day's blocks not re-solved
    /// around it. That is the Mac's rule, not a new one: `TimelineDropPreviewOverlay` draws the
    /// dragged task at its own layout in the column that holds it and at column 0 of 1 in every
    /// other column (`previewLayout?.column ?? 0`), and iOS's own drop plate is the same lone
    /// block (`horizontalFrame(nil, kind: .task)`). Keeping the SOURCE day's split slot, which is
    /// what the carry did before this, drew a narrow block at the source's offset over the target's
    /// full-width ones. No hardware reason separates the two platforms here ([[T-8201]]).
    static func carriedPlacement(
        own: CadenceCalendarOverlapPlacement?,
        dayDelta: Int
    ) -> CadenceCalendarOverlapPlacement {
        guard dayDelta == 0, let own else { return .single }
        return own
    }

    /// The day a block moved `dayDelta` columns from `date` lands on, or `nil` for a move that
    /// stayed on its own day — which writes no day at all, exactly as before [[T-8301]].
    static func movedDateKey(from date: Date, dayDelta: Int, calendar: Calendar = .current) -> String? {
        guard dayDelta != 0,
              let moved = calendar.date(byAdding: .day, value: dayDelta, to: date) else { return nil }
        return DateFormatters.dateKey(from: moved, calendar: calendar)
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
    /// **A move onto another day writes that day too, in the same transaction** ([[T-8301]]):
    /// `dateKey` is `movedDateKey`'s answer, `nil` for a move that stayed on its column. One commit
    /// rather than this plus `commitDrop`, for `commitDrop`'s own reason — a day written by one
    /// save and a minute by another is a move that can half-land where no undo reaches it. A
    /// resize never changes the day, so `dateKey` is ignored for one.
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
        onDay dateKey: String? = nil,
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
            if kind == .move, let dateKey {
                task.scheduledDate = dateKey
            }
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

    /// A task **dropped onto a day column** — its day and its start minute together, in one field
    /// transaction ([[T-8141]]).
    ///
    /// `commit(_:kind:range:in:)` above moves a block that is already on the column, so it writes
    /// the minute alone. A dropped task may be arriving from another day entirely — Today's list
    /// holds yesterday's overdue work as well as today's — so the day has to be written too, and it
    /// has to be written in the *same* transaction: `CadenceTaskFieldEditCommit` restores every
    /// field it snapshotted when the save is refused, so a day written by one commit and a minute
    /// by another is a drop that can half-land where no undo reaches it (the rule T-1580 states for
    /// a drop key that writes a list and a date).
    ///
    /// Day **and** minute, never one of them: a task given a minute but left on yesterday is drawn
    /// nowhere the user dropped it, and a task given a day but no minute lands back in the untimed
    /// column it was dragged out of — both read on screen as "the drop did nothing".
    ///
    /// `false` means the task is exactly where it was, so the list the row was dragged from is
    /// already correct and the caller's only remaining job is to say so.
    @MainActor
    @discardableResult
    static func commitDrop(
        _ task: AppTask,
        dateKey: String,
        startMin: Int,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let minute = min(max(0, startMin), CadenceScheduleSupport.calendarEndHour * 60 - gridMinutes)
        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: context,
            reconciler: reconciler,
            commit: commit
        ) {
            task.scheduledDate = dateKey
            task.scheduledStartMin = minute
        }
        if landed {
            (reconciler ?? .default).run(in: context)
        }
        return landed
    }

    /// The drop as a *host* sees it: an id off the wire, resolved against the host's own task
    /// universe, then committed ([[T-8141]]).
    ///
    /// Both iOS grid hosts — Today's schedule pane and the Calendar page — hand the grid the same
    /// closure, and this is it, so neither can grow its own idea of what a dropped task does. An id
    /// that names nothing in `tasks` answers `false`, which is also the right answer for a payload
    /// from another app: the drop is refused rather than silently swallowed.
    @MainActor
    static func commitDrop(
        taskID: UUID,
        among tasks: [AppTask],
        dateKey: String,
        startMin: Int,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) -> Bool {
        guard let task = droppedTask(taskID, among: tasks) else { return false }
        return commitDrop(task, dateKey: dateKey, startMin: startMin, in: context, reconciler: reconciler)
    }

    /// The task a drag's id names in a host's universe, or `nil` for one it does not hold.
    ///
    /// One lookup for the drop's commit above AND for the hover that precedes it ([[T-8142]]): the
    /// column asks it for the hovering task's length, and a hover that resolved a task the commit
    /// then could not find would preview a block the release refuses.
    static func droppedTask(_ taskID: UUID, among tasks: [AppTask]) -> AppTask? {
        tasks.first(where: { $0.id == taskID })
    }
}

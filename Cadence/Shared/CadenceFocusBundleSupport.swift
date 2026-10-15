import Foundation
import SwiftData

/// What a focus session is running against, as a value.
///
/// The stopwatch needs an identity it can compare across renders. It stays an enum rather than a
/// bare `UUID` because every rule about leaving a session — commit the seconds, hand the next
/// subject a clock at zero — is stated against it, and a bare id would make those rules read as
/// arithmetic on an optional.
enum CadenceFocusTarget: Hashable {
    case task(UUID)

    var taskID: UUID? {
        guard case .task(let id) = self else { return nil }
        return id
    }
}

/// The model behind a `CadenceFocusTarget`, for the moment a session is actually being left.
enum CadenceFocusSubject {
    case task(AppTask)

    var target: CadenceFocusTarget {
        switch self {
        case .task(let task): return .task(task.id)
        }
    }
}

/// One row of the focus picker: a ready task you can run the timer against.
///
/// This was `FocusPickItem` in `macOS/Views/FocusPickerSupportViews.swift` behind `#if os(macOS)`,
/// in a file whose only platform dependency is the *views* below it — the enum itself is date-key
/// arithmetic and string matching. That guard is the whole reason the iPhone's focus picker listed
/// nothing of its own (T-242). Moved rather than copied; `FocusPickItem` is now a typealias.
enum CadenceFocusPickItem: Identifiable {
    case task(AppTask)

    var id: String {
        switch self {
        case .task(let task): return "task-\(task.id.uuidString)"
        }
    }

    var target: CadenceFocusTarget {
        switch self {
        case .task(let task): return .task(task.id)
        }
    }

    /// The default number of rows offered when nothing has been typed. macOS's picker is a search
    /// field over everything ready, so a long unfiltered list there is noise; iOS's picker *is* the
    /// list (there is no search field), so it passes `nil` and shows all of them rather than
    /// silently hiding the nineteenth ready task behind a cap with no way to search past it.
    static let defaultUnfilteredLimit = 18

    static func filtered(
        tasks: [AppTask],
        query: String,
        todayKey: String,
        limit: Int? = defaultUnfilteredLimit
    ) -> [CadenceFocusPickItem] {
        let items = tasks.map(CadenceFocusPickItem.task)
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            guard let limit else { return items }
            return Array(items.prefix(limit))
        }

        return items.filter { $0.matches(cleanedQuery) }
    }

    private func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        return searchText.lowercased().contains(needle)
    }

    private var searchText: String {
        switch self {
        case .task(let task):
            return [
                task.title,
                task.containerName,
                task.priority.label,
                task.dueDate,
                task.scheduledDate
            ].joined(separator: " ")
        }
    }
}

extension CadenceFocusSupport {

    /// Spread `totalMinutes` across `tasks`, weighted by estimate, and roll the same minutes up into
    /// each task's list the way `bankElapsedSeconds(_:to:)` does for a single task.
    ///
    /// Moved out of `#if os(macOS)` under T-242, which is why an iPhone could not log a session
    /// across more than one task at all. The last task absorbs the remainder rather than each share
    /// being rounded independently, so the minutes handed out always total exactly what the
    /// stopwatch measured.
    ///
    /// **Throws and takes `commit:` now (T-654).** Every increment `CadenceFocusLedger.bank` writes
    /// is a pending insert (a `FocusSessionLog` row per task/project/area) plus an `actualMinutes` /
    /// `loggedMinutes` `+=` — and `+=` is exactly the shape the standing "a refused save is fine
    /// because the next fetch corrects it" reasoning does not cover: a fetch re-reads whatever the
    /// counter now holds, and a lost increment stays lost. `BankedMinutes` is captured for every task
    /// actually credited, **before** its bank runs, so a refused commit restores every one of them —
    /// with exactly one task in `tasks` this reduces to the same shape `CadenceFocusSupport.complete`
    /// already uses for the single-task door (T-636(c)), which is what lets `endSession` below
    /// bank through one call.
    ///
    /// **Commits through `commitEdit(in:commit:undo:)`, not `commitInsert`, and that is
    /// deliberate.** The pending change here is `BankedMinutes`' captured-before snapshot restored
    /// on refusal — the same shape a field edit uses — not a list of freshly-inserted models
    /// `commitInsert` could delete. Routing the actual commit
    /// through `CadencePendingChangePersistence` rather than calling `commit(modelContext)` inline
    /// also keeps this reachable by `AGENTS.md`'s "the `try? save()` rule" scan, which recognizes a
    /// commit by name -- `.save()`, or one of `CadencePendingChangePersistence`'s commit helpers
    /// such as `CadencePendingChangePersistence.commitEdit(in:commit:_:)` -- and cannot see through
    /// a bare call to a parameter.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func distributeMinutes(
        _ totalMinutes: Int,
        across tasks: [AppTask],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard totalMinutes > 0, !tasks.isEmpty else { return }
        let weights = tasks.map { max($0.estimatedMinutes, 5) }
        let totalWeight = max(weights.reduce(0, +), 1)
        var remaining = totalMinutes
        var banked: [CadenceFocusSupport.BankedMinutes] = []

        for (index, task) in tasks.enumerated() {
            let minutes: Int
            if index == tasks.count - 1 {
                minutes = max(0, remaining)
            } else {
                minutes = min(
                    remaining,
                    max(0, Int((Double(totalMinutes) * Double(weights[index]) / Double(totalWeight)).rounded()))
                )
                remaining -= minutes
            }
            guard minutes > 0 else { continue }
            banked.append(CadenceFocusSupport.BankedMinutes(task))
            CadenceFocusLedger.bank(minutes, forTaskAndItsList: task, in: modelContext)
        }

        guard !banked.isEmpty else { return }
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            // **Reversed, and it has to be.** Two tasks in the same project each snapshot that
            // project's counter — the second snapshot captures whatever the *first* task's write
            // already left it at, not the true pre-distribution value. Restoring forward would let
            // that second, already-mutated snapshot win. Restoring in reverse — last write undone
            // first — means the snapshot taken before any write in this distribution ran (the
            // first task's) is applied last, so it is the one left standing. Measured: forward
            // order left a shared project's `loggedMinutes` at an intermediate value rather than
            // its original one.
            for snapshot in banked.reversed() {
                snapshot.restore(in: modelContext)
            }
        }
    }

    /// Stopwatch seconds banked against the tasks a session credited.
    ///
    /// Goes through `minutes(fromElapsedSeconds:)` — the one definition of what a stopwatch reading
    /// is worth — rather than re-deriving it, for the same reason the log-session seeds do: a second
    /// rounding rule here would make the same clock log a different number depending on which door
    /// it came through.
    ///
    /// - Parameter commit: See `distributeMinutes(_:across:in:commit:)`.
    static func logElapsedSeconds(
        _ seconds: Int,
        across tasks: [AppTask],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try distributeMinutes(minutes(fromElapsedSeconds: seconds), across: tasks, in: modelContext, commit: commit)
    }

    /// Leave one focus subject for another: bank the seconds the outgoing one earned, then hand the
    /// incoming one a clock at zero.
    ///
    /// The subject-shaped form of `commitElapsed(leaving:switchingTo:state:…)`. The task overload
    /// forwards here, so there is one rule: re-selecting what is already focused is not
    /// leaving a session and returns the state untouched, and under a whole minute nothing is
    /// written, because `minutes(fromElapsedSeconds:)` rounds to the nearest minute and a zero is not
    /// worth a `save()`.
    ///
    /// **Throws now (T-654).** See `endSession(leaving:state:modelContext:now:commit:)`.
    static func commitElapsed(
        leaving outgoing: CadenceFocusSubject?,
        switchingTo next: CadenceFocusTarget,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> CadenceFocusTimerState {
        guard outgoing?.target != next else { return state }
        return try endSession(leaving: outgoing, state: state, modelContext: modelContext, now: now, commit: commit)
    }

    /// Leave a focus session for **nothing**: bank the seconds it earned and clear the clock.
    ///
    /// The half of `commitElapsed(leaving:switchingTo:…)` that is not about the incoming subject,
    /// named after the act macOS spells `FocusManager.endSession()` — closing a session is the same
    /// act of leaving one, so it banks the same way. It exists separately because the switching
    /// form cannot express it: its first parameter of that decision is "am I being handed the
    /// subject I already have", and there is no target to compare against when you are simply
    /// walking away from the screen.
    ///
    /// Same two silences as the switching form, deliberately: no subject writes nothing, and a
    /// clock under a whole minute writes nothing, because `minutes(fromElapsedSeconds:)` rounds to
    /// the nearest minute and a zero is not worth a `save()`.
    ///
    /// **Throws and takes `commit:` now (T-654).** It used to bank through the swallowing
    /// `logElapsedSeconds` and always return the *reset* state, so a refused (or, on macOS, never
    /// attempted — `FocusManager.commitElapsed` called none of this) commit cleared the only copy of
    /// the elapsed seconds with nothing left to retry. Banking now goes through
    /// `distributeMinutes(_:across:in:commit:)` — a single task is just a one-element credit
    /// list — so there is one commit, one undo, and the clock is only reset once
    /// that commit actually lands; on a refusal the caller gets the thrown error and the *original*
    /// `state`, unreset, so the session already running is still there to retry.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func endSession(
        leaving outgoing: CadenceFocusSubject?,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> CadenceFocusTimerState {
        var reset = state
        reset.reset()

        guard let outgoing else { return reset }
        let seconds = state.elapsedSeconds(now: now)
        guard minutes(fromElapsedSeconds: seconds) > 0 else { return reset }

        let creditedTasks: [AppTask]
        switch outgoing {
        case .task(let task):
            creditedTasks = [task]
        }
        try logElapsedSeconds(seconds, across: creditedTasks, in: modelContext, commit: commit)
        return reset
    }

    /// The stopwatch state after the play/pause control on a pick row is tapped, stated against
    /// targets rather than ids.
    ///
    /// Tapping the control on the subject already loaded toggles it, so one row is start and pause.
    /// Tapping a *different* row's control starts that subject from zero rather than inheriting the
    /// elapsed count: the seconds on the clock were measured against what they were started on, and
    /// carrying them over would log one subject's minutes onto another.
    /// The stopwatch state after a session is **handed over** from another surface — a task row's
    /// context menu, a task inspector — as opposed to tapped on a pick row.
    ///
    /// The difference from `timerState(afterPlayTapOn:…)` is the one that matters, and it is why
    /// this is a second function rather than a second caller of that one: a play control *toggles*,
    /// so routing a handoff through it would **pause** the session when the subject asked for is
    /// the subject already running. "Focus this" is never a pause. Asking for the running subject
    /// therefore leaves its clock exactly where it is rather than restarting it at zero, which
    /// would silently discard the minutes measured so far.
    ///
    /// A *different* subject still starts from zero, for the reason the play control does: the
    /// seconds on the clock were earned by what they were started on. Banking them is the caller's
    /// job, through `commitElapsed(leaving:switchingTo:…)`, before this is reached.
    static func timerState(
        startRequestFor requested: CadenceFocusTarget,
        selectedTarget: CadenceFocusTarget?,
        state: CadenceFocusTimerState,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        var next = state
        if selectedTarget != requested {
            next.reset()
        }
        guard !next.isRunning else { return next }
        next.toggle(now: now)
        return next
    }

    static func timerState(
        afterPlayTapOn tapped: CadenceFocusTarget,
        selectedTarget: CadenceFocusTarget?,
        state: CadenceFocusTimerState,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        var next = state
        if selectedTarget != tapped {
            next.reset()
        }
        next.toggle(now: now)
        return next
    }
}

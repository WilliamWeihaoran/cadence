import Foundation
import SwiftData

/// What a focus session is running against, as a value.
///
/// The stopwatch needs an identity it can compare across renders, and "the selected task's `UUID`"
/// stopped being enough the moment a `TaskBundle` could be the subject: a bundle and one of its
/// members are different sessions that would otherwise be indistinguishable ids. Every rule about
/// leaving a session — commit the seconds, hand the next subject a clock at zero — is stated
/// against this rather than against a bare `UUID`.
enum CadenceFocusTarget: Hashable {
    case task(UUID)
    case bundle(UUID)

    var taskID: UUID? {
        guard case .task(let id) = self else { return nil }
        return id
    }

    var bundleID: UUID? {
        guard case .bundle(let id) = self else { return nil }
        return id
    }
}

/// The models behind a `CadenceFocusTarget`, for the moment a session is actually being left.
///
/// A bundle carries the member selection with it because the two are one fact: "these minutes were
/// earned by this block, and they go to the members that were ticked while it ran". Passing the
/// bundle without the ticks is how a commit path ends up guessing — either crediting every member
/// or none — and the guess is unrecoverable once the clock is reset.
enum CadenceFocusSubject {
    case task(AppTask)
    case bundle(TaskBundle, selectedTaskIDs: Set<UUID>)

    var target: CadenceFocusTarget {
        switch self {
        case .task(let task): return .task(task.id)
        case .bundle(let bundle, _): return .bundle(bundle.id)
        }
    }
}

/// One row of the focus picker: a ready task, or a bundle you can run the timer against.
///
/// This was `FocusPickItem` in `macOS/Views/FocusPickerSupportViews.swift` behind `#if os(macOS)`,
/// in a file whose only platform dependency is the *views* below it — the enum itself is date-key
/// arithmetic and string matching. That guard is the whole reason the iPhone's focus picker listed
/// tasks and nothing else (T-242). Moved rather than copied; `FocusPickItem` is now a typealias.
enum CadenceFocusPickItem: Identifiable {
    case task(AppTask)
    case bundle(TaskBundle)

    var id: String {
        switch self {
        case .task(let task): return "task-\(task.id.uuidString)"
        case .bundle(let bundle): return "bundle-\(bundle.id.uuidString)"
        }
    }

    var target: CadenceFocusTarget {
        switch self {
        case .task(let task): return .task(task.id)
        case .bundle(let bundle): return .bundle(bundle.id)
        }
    }

    /// The default number of rows offered when nothing has been typed. macOS's picker is a search
    /// field over everything ready, so a long unfiltered list there is noise; iOS's picker *is* the
    /// list (there is no search field), so it passes `nil` and shows all of them rather than
    /// silently hiding the nineteenth ready task behind a cap with no way to search past it.
    static let defaultUnfilteredLimit = 18

    static func filtered(
        tasks: [AppTask],
        bundles: [TaskBundle],
        query: String,
        todayKey: String,
        limit: Int? = defaultUnfilteredLimit
    ) -> [CadenceFocusPickItem] {
        let activeBundles = bundles
            .filter { !$0.sortedTasks.isEmpty && !$0.isCompleted }
            // Rank first, *then* the day inside a rank. Comparing "keys differ" before "ranks
            // differ" meant two bundles in the same rank but on different days — every pair of
            // future bundles, and every pair of past ones — compared as equal, so the day was
            // never consulted and `startMin`/`createdAt` were never reached: a bundle eight days
            // out could sort above tomorrow's. It also made the comparator inconsistent (A on the
            // 13th "equals" both B and C on the 20th, while B and C order strictly by `startMin`),
            // which is not a strict weak ordering and leaves `sorted(by:)` free to return anything.
            .sorted { lhs, rhs in
                let lhsRank = bundleDateRank(lhs.dateKey, todayKey: todayKey)
                let rhsRank = bundleDateRank(rhs.dateKey, todayKey: todayKey)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.dateKey != rhs.dateKey {
                    // Upcoming days read soonest-first; past days read most-recent-first, so a
                    // bundle left over from yesterday sits above one from six months ago.
                    return lhsRank == pastBundleRank
                        ? lhs.dateKey > rhs.dateKey
                        : lhs.dateKey < rhs.dateKey
                }
                if lhs.startMin != rhs.startMin {
                    return lhs.startMin < rhs.startMin
                }
                return lhs.createdAt > rhs.createdAt
            }

        let items = tasks.map(CadenceFocusPickItem.task) + activeBundles.map(CadenceFocusPickItem.bundle)
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            guard let limit else { return items }
            return Array(items.prefix(limit))
        }

        return items.filter { $0.matches(cleanedQuery) }
    }

    private static let pastBundleRank = 3

    private static func bundleDateRank(_ dateKey: String, todayKey: String) -> Int {
        if dateKey == todayKey { return 0 }
        if dateKey.isEmpty { return 2 }
        return dateKey > todayKey ? 1 : pastBundleRank
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
        case .bundle(let bundle):
            return ([bundle.displayTitle, bundle.dateKey] + bundle.sortedTasks.map(\.title)).joined(separator: " ")
        }
    }
}

/// What a bundle row says about itself in a focus surface.
///
/// One sentence, one definition. macOS spelled it inline in `FocusPickItemRow.bundleDetail`; the
/// iPhone's row needs the same facts in the same order, and a second hand-written version of
/// "N tasks / Today / 9:00 – 9:55 AM" is exactly the near-copy the bundle member row already had to
/// be rescued from (`CadenceBundleTaskRowSupport`).
enum CadenceFocusBundlePresentation {
    static func summaryLine(for bundle: TaskBundle, todayKey: String = DateFormatters.todayKey()) -> String {
        summaryParts(for: bundle, todayKey: todayKey).joined(separator: " / ")
    }

    /// The same facts unjoined, for a surface that renders them as chips instead of a line. The
    /// leading `"Bundle"` label is dropped for those: a chip strip under a bundle's own title does
    /// not need to be told twice what it is describing.
    static func summaryParts(for bundle: TaskBundle, todayKey: String = DateFormatters.todayKey()) -> [String] {
        var parts = ["Bundle", memberCountLabel(for: bundle)]
        if !bundle.dateKey.isEmpty {
            parts.append(bundle.dateKey == todayKey ? "Today" : DateFormatters.relativeDate(from: bundle.dateKey))
        }
        parts.append(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
        if bundle.totalEstimatedMinutes > 0 {
            parts.append("\(bundle.totalEstimatedMinutes)m tasks")
        }
        return parts
    }

    static func memberCountLabel(for bundle: TaskBundle) -> String {
        let count = bundle.sortedTasks.count
        return "\(count) task\(count == 1 ? "" : "s")"
    }

    /// "3 of 4 tasks receive this session's time" — the sentence the member panel puts under its
    /// heading, so the consequence of unticking a row is stated where the ticks are.
    static func selectionSummary(for bundle: TaskBundle, selectedTaskIDs: Set<UUID>) -> String {
        let total = bundle.sortedTasks.count
        let selected = CadenceFocusSupport.selectedTasks(in: bundle, selectedTaskIDs: selectedTaskIDs).count
        guard selected > 0 else { return "No tasks will receive this session's time." }
        return "\(selected) of \(total) task\(total == 1 ? "" : "s") receive this session's time."
    }
}

extension CadenceFocusSupport {

    /// Every member, because a block you sat down to work through is presumed to be the work.
    /// Unticking is the exception, so it is the thing that takes a tap.
    static func defaultSelectedTaskIDs(for bundle: TaskBundle) -> Set<UUID> {
        Set(bundle.sortedTasks.map(\.id))
    }

    /// The members a bundle session's minutes go to, **in bundle order**. Filtering the bundle
    /// rather than mapping the id set is what keeps the order and drops ids belonging to tasks that
    /// have since left the block.
    static func selectedTasks(in bundle: TaskBundle, selectedTaskIDs: Set<UUID>) -> [AppTask] {
        bundle.sortedTasks.filter { selectedTaskIDs.contains($0.id) }
    }

    /// Spread `totalMinutes` across `tasks`, weighted by estimate, and roll the same minutes up into
    /// each task's list the way `logElapsedSeconds(_:to:)` does for a single task.
    ///
    /// Moved from `FocusSessionSupport.distributeBundleMinutes` — arithmetic over models, inside
    /// `#if os(macOS)`, which is why an iPhone could not run a block's timer at all. The last member
    /// absorbs the remainder rather than each share being rounded independently, so the minutes
    /// handed out always total exactly what the stopwatch measured.
    static func distributeMinutes(_ totalMinutes: Int, across tasks: [AppTask]) {
        guard totalMinutes > 0, !tasks.isEmpty else { return }
        let weights = tasks.map { max($0.estimatedMinutes, 5) }
        let totalWeight = max(weights.reduce(0, +), 1)
        var remaining = totalMinutes

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
            task.actualMinutes += minutes
            if let project = task.project {
                project.loggedMinutes += minutes
            } else if let area = task.area {
                area.loggedMinutes += minutes
            }
        }
    }

    /// Stopwatch seconds banked against a bundle's ticked members.
    ///
    /// Goes through `minutes(fromElapsedSeconds:)` — the one definition of what a stopwatch reading
    /// is worth — rather than re-deriving it, for the same reason the log-session seeds do: a second
    /// rounding rule here would make the same clock log a different number depending on whether the
    /// subject was a task or a block.
    static func logElapsedSeconds(_ seconds: Int, across tasks: [AppTask]) {
        distributeMinutes(minutes(fromElapsedSeconds: seconds), across: tasks)
    }

    /// Leave one focus subject for another: bank the seconds the outgoing one earned, then hand the
    /// incoming one a clock at zero.
    ///
    /// The subject-shaped generalisation of `commitElapsed(leaving:switchingTo:state:…)`, which took
    /// an `AppTask?` and a `UUID` and therefore could not express "I am leaving a block". The task
    /// overload now forwards here, so there is one rule: re-selecting what is already focused is not
    /// leaving a session and returns the state untouched, and under a whole minute nothing is
    /// written, because `minutes(fromElapsedSeconds:)` rounds to the nearest minute and a zero is not
    /// worth a `save()`.
    static func commitElapsed(
        leaving outgoing: CadenceFocusSubject?,
        switchingTo next: CadenceFocusTarget,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        guard outgoing?.target != next else { return state }
        return endSession(leaving: outgoing, state: state, modelContext: modelContext, now: now)
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
    static func endSession(
        leaving outgoing: CadenceFocusSubject?,
        state: CadenceFocusTimerState,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> CadenceFocusTimerState {
        var reset = state
        reset.reset()

        guard let outgoing else { return reset }
        let seconds = state.elapsedSeconds(now: now)
        guard minutes(fromElapsedSeconds: seconds) > 0 else { return reset }

        switch outgoing {
        case .task(let task):
            logElapsedSeconds(seconds, to: task)
        case .bundle(let bundle, let selectedTaskIDs):
            logElapsedSeconds(seconds, across: selectedTasks(in: bundle, selectedTaskIDs: selectedTaskIDs))
        }
        try? modelContext.save()
        return reset
    }

    /// The stopwatch state after the play/pause control on a pick row is tapped, stated against
    /// targets so a bundle row's control behaves like a task row's.
    ///
    /// Tapping the control on the subject already loaded toggles it, so one row is start and pause.
    /// Tapping a *different* row's control starts that subject from zero rather than inheriting the
    /// elapsed count: the seconds on the clock were measured against what they were started on, and
    /// carrying them over would log one subject's minutes onto another.
    /// The stopwatch state after a session is **handed over** from another surface — a task row's
    /// context menu, a block's inspector — as opposed to tapped on a pick row.
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

import Foundation

/// The task surfaces the app lists tasks on, named once so the things that are true of *all* of
/// them can be stated once.
enum CadenceTaskSurface: String, CaseIterable, Sendable {
    case today
    case inbox
    case allTasks
    case listDetail
}

/// Whether a surface is being drawn for a **pointer** or for a **finger**.
///
/// **This is not the size class the file below rules out, and the distinction is the whole
/// argument.** "iPhone Today has no sort control" is a statement about a width, and stays
/// unspellable — iPhone and iPad are one tier here and always will be, so an exception written for
/// `.touch` is written for both of them at once. What this axis can express is the one thing a
/// width genuinely cannot: whether the surface is reached with a scroll wheel, a trackpad and a
/// window you can make taller, or with a thumb.
///
/// Only `completedRowLimit(for:)` reads it. Every other answer in this file is the same on both
/// tiers, and adding a second one should be argued for rather than assumed.
enum CadenceTaskSurfaceTier: String, CaseIterable, Sendable {
    case touch
    case desktop
}

/// Which of a task surface's chrome controls it offers.
struct CadenceTaskViewOptions: Equatable, Sendable {
    /// The sort chip.
    var showsSort: Bool
    /// The "Completed N" toggle, which is the only thing that can write `showCompleted`.
    var showsCompletedToggle: Bool
    /// Whether a row names the list its task is in.
    ///
    /// Off for the surfaces that are already scoped to one list, where the chip names the page you
    /// are standing on: the Inbox drew "Inbox" on every row, and a list's own Tasks tab would draw
    /// its own name. On for Today and All Tasks, which mix lists and where the chip is both the
    /// answer and the picker for changing it.
    ///
    /// This has to be one value for both widths. When the chip first started rendering for
    /// container-less tasks it was so the Inbox's tasks — the ones most in need of filing — stopped
    /// being the only ones that could not be filed from the row; that reasoning is about the *row*,
    /// and the Inbox page is where it does not apply.
    ///
    /// **macOS re-decided this on the row until T-290**, as
    /// `style == .standard && !task.containerName.isEmpty` — an axis about the row rather than the
    /// surface, and one whose second clause reproduced the exact defect this value was written to
    /// fix, in reverse: an Inbox task in Today or All Tasks has an empty `containerName`, so the
    /// tasks most in need of filing were the only ones with no chip to file them from.
    var showsContainerChip: Bool
}

/// What every task surface offers, and how much of the completed list it shows.
///
/// This exists because iPhone Today shipped with neither control while iPad Today had both — and
/// the compact view still *read* a `showCompleted` binding that nothing on screen could write, so
/// completed work was permanently hidden on the phone with no way to ask for it.
///
/// **There is deliberately no size class in this file.** The options a surface offers are a
/// property of the surface, not of the width it happens to be drawn at, so "iPhone Today has no
/// sort control" is not expressible here. A future surface that genuinely needs fewer controls
/// says so by `CadenceTaskSurface` case, and then says it for both widths at once.
///
/// `CadenceTaskSurfaceTier` is not a hole in that rule — see its own doc.
enum CadenceTaskSurfaceOptions {
    /// How many completed rows a **touch** surface lists before it stops.
    ///
    /// One number across the touch surfaces, because there was never a reason for two: Today and
    /// Inbox capped at 12 while All Tasks capped at 24, so the same finished task was listed on one
    /// screen and dropped on another. 24 is the larger of the two — it never hides work the smaller
    /// cap would have shown, and All Tasks has been rendering that many since it was written.
    ///
    /// Prefer `completedRowLimit(for:)`. This constant is the touch tier's answer, kept named
    /// because that is the number the two iOS caps were reconciled to.
    static let completedRowLimit = 24

    /// Every surface offers the same two chrome controls; they differ only in whether a row names
    /// its list. The `surface` parameter is what keeps each exception attached to a *surface*
    /// rather than to a width — an exception written here is written for both widths at once.
    static func options(for surface: CadenceTaskSurface) -> CadenceTaskViewOptions {
        CadenceTaskViewOptions(
            showsSort: true,
            showsCompletedToggle: true,
            showsContainerChip: showsContainerChip(on: surface)
        )
    }

    /// Whether a surface's rows name the list each task is in. See `showsContainerChip`.
    static func showsContainerChip(on surface: CadenceTaskSurface) -> Bool {
        switch surface {
        case .today, .allTasks:
            return true
        case .inbox, .listDetail:
            return false
        }
    }

    /// How many completed rows a surface lists on a given tier, or `nil` for "all of them".
    ///
    /// **`.desktop` is uncapped, and that is a decision rather than an oversight (T-290).** The
    /// tempting move was to hand macOS the 24 and call it one number; it is the wrong one, for
    /// three reasons that outrank symmetry.
    ///
    /// - **There is no "show more" anywhere in this app.** A cap with no spill-over is not a
    ///   rendering budget, it is a ceiling on what the logbook can ever show. Outside Today —
    ///   whose Completed section is scoped to a single day and so is bounded by construction — this
    ///   list *is* the record of finished work: All Tasks' Completed section and a list's own are
    ///   the only places Cadence lists it at all. 24 would be the whole of a Mac user's visible
    ///   history.
    /// - **It would force a lie into the header.** `TasksListView` hands its completed section the
    ///   true `completedTaskCount` and renders the rows separately. Cap the rows and the header
    ///   reads 300 over 24 of them — the "N rows under a count of M" shape this repo has had to
    ///   correct more than once. Cap the count too and the app understates what has been done.
    /// - **The 24 has no measured reason behind it.** `git log -S "prefix(24)"` puts its origin in
    ///   `iOSCompactAllTasksView`, a compact-view detail that never reached macOS; the number this
    ///   file settled on is the larger of iOS's own two, not a figure anybody profiled. "A list with
    ///   thousands of completed tasks" is the case a cap would be *for*, and it is not the case it
    ///   came from.
    ///
    /// The touch tier keeps it. A phone builds its completed rows inside `iOSTaskGroupSection`'s
    /// plain `VStack`, has no scroll bar, and reaches the list with a thumb; a Mac window has a
    /// scroll bar, a trackpad flick, and a disclosure that starts collapsed and has to be opened on
    /// purpose. Same rows, different cost to leave uncapped.
    ///
    /// **The touch tier's silence was the other half of this, and it is fixed rather than open**
    /// (T-386; the pointer here used to name a closed, archived ticket about ordering inside a list
    /// cascade, which cost the next reader the same search). iOS's options bar read the true count
    /// while the section header under it counted the capped array, so a phone with 40 finished
    /// tasks offered "Completed 40" and drew 24 rows under a header that also said 24 — two counts
    /// on one screen, both derived from the same list. The cap stays; what it now carries is
    /// `hiddenCompletedCount(from:tier:)` and the caption below it, so the header counts the whole
    /// section and the rows say how many of it they are.
    static func completedRowLimit(for tier: CadenceTaskSurfaceTier) -> Int? {
        switch tier {
        case .touch:
            return completedRowLimit
        case .desktop:
            return nil
        }
    }

    /// The completed rows a surface actually lists — the full set, capped at the tier's limit.
    ///
    /// `tier` has no default on purpose. A default is what lets a call site not know the question
    /// exists, and "macOS never asked" is the whole of T-290.
    static func completedRows<Task>(from tasks: [Task], tier: CadenceTaskSurfaceTier) -> [Task] {
        guard let limit = completedRowLimit(for: tier) else { return tasks }
        return Array(tasks.prefix(limit))
    }

    /// The completed rows a surface lists, with one row guaranteed to be among them.
    ///
    /// **T-375: "expanded" has to mean "listed".** A deep link to finished work opens All Tasks'
    /// Completed section so the task the URL names is on the page. On the touch tier that section
    /// stops at `completedRowLimit`, and the rows are ordered newest-settled first — so the
    /// links most in need of the reveal, the ones for work finished long enough ago that the user
    /// went looking through a widget, are exactly the ones the cap would drop. Expanding a section
    /// that still does not contain the task is the original defect with an extra animation.
    ///
    /// The revealed row is appended rather than promoted: its place in the logbook is a fact about
    /// when it was settled, and reordering the list around a deep link would misdate it. It joins
    /// the end only when the cap would otherwise have excluded it — inside the cap, this is
    /// `completedRows(from:tier:)` exactly, and on `.desktop`, which has no cap, it always is.
    static func completedRows<Task: Identifiable>(
        from tasks: [Task],
        tier: CadenceTaskSurfaceTier,
        revealing revealedID: Task.ID?
    ) -> [Task] {
        let rows = completedRows(from: tasks, tier: tier)
        guard let revealedID, !rows.contains(where: { $0.id == revealedID }) else { return rows }
        guard let revealed = tasks.first(where: { $0.id == revealedID }) else { return rows }
        return rows + [revealed]
    }

    /// How many completed rows the tier's cap is **not** drawing, or `nil` when it draws them all.
    ///
    /// The denominator half of `completedRows(from:tier:)`, deliberately taking the same uncapped
    /// array so the two cannot disagree about what "more" means — the shape
    /// `CadenceTaskPresentationSupport.hiddenSubtaskCount(for:)` already uses for the row's
    /// "+N more". `nil` rather than `0` for the same reason it does: there is no "+0 more" line.
    static func hiddenCompletedCount<Task>(from tasks: [Task], tier: CadenceTaskSurfaceTier) -> Int? {
        let hidden = tasks.count - completedRows(from: tasks, tier: tier).count
        return hidden > 0 ? hidden : nil
    }

    /// What a capped section says under its rows, or `nil` when it is drawing all of them.
    ///
    /// **It names both numbers rather than only the remainder.** "+16 more" is the right line for a
    /// task row's subtasks, where tapping the row opens the rest; there is no "show more" anywhere
    /// in this app, so on a completed section the same words would promise an affordance that does
    /// not exist. "Showing 24 of 40" states what the screen *is* instead, and it is the line that
    /// reconciles the two numbers T-386 found disagreeing: the options bar's 40 and the rows you
    /// can count.
    ///
    /// Takes the two counts rather than the array so the caption cannot be computed from a
    /// different list than the one that was capped.
    static func overflowCaption(shown: Int, total: Int) -> String? {
        guard total > shown else { return nil }
        return "Showing \(shown) of \(total)"
    }

    /// The **other** line the paragraph above contrasts itself with: what a capped *row* or *cell*
    /// says about the items it is not drawing.
    ///
    /// **T-598(c). It is `"+3 more"`, with no space after the plus.** Twelve sites in the app draw
    /// this line and they had split nine to three. The unspaced nine are the board cards, the
    /// kanban card, the markdown task embed and preview, the iOS task row and the macOS timeline
    /// bundle block; the spaced three were all calendar — two on the iOS timeline and month grid,
    /// one on macOS's month grid — so the Calendar disagreed with the rest of the app *and*, at
    /// `iOSCalendarTimelineViews`' second site, with itself. The majority wins, and it is also the
    /// typographically right one: `+3` is a signed quantity, not a plus sign followed by a number.
    ///
    /// It lives next to `overflowCaption` because the two lines are one decision seen twice, and
    /// the paragraph above is where the app already explains which of them a surface gets: this one
    /// where opening the thing reveals the rest, that one where nothing does.
    ///
    /// `MarkdownRenderedBlockTruncation.overflowLabel(unit:)` is deliberately **not** folded in
    /// here. It says "+ 4 more rows" — a different sentence, naming what was cut and pluralising
    /// the unit, under a rendered table rather than beside a list of chips. It happens to spell its
    /// plus the spaced way; that is that line's separate question, recorded rather than swept up
    /// with this one.
    ///
    /// **The declaration is a guard the sweep cannot supply.** `CadenceSharedConstantReuseSweepTests`
    /// harvests non-interpolated `static let` strings only, and this is interpolated by nature, so a
    /// thirteenth site typing `"+\(n) more"` would not be caught there.
    /// `CadenceCalendarConsistencySurfaceTests` pins the calendar surfaces by hand instead.
    ///
    /// Takes the count the caller is hiding, which is the number every one of those sites had
    /// already computed.
    static func moreLabel(hidden: Int) -> String {
        "+\(hidden) more"
    }
}

import Foundation

/// The task surfaces the app lists tasks on, named once so the things that are true of *all* of
/// them can be stated once.
enum CadenceTaskSurface: String, CaseIterable, Sendable {
    case today
    case inbox
    case allTasks
    case listDetail
}

/// Which of a task surface's chrome controls it offers.
struct CadenceTaskViewOptions: Equatable, Sendable {
    /// The sort chip.
    var showsSort: Bool
    /// The "Completed N" toggle, which is the only thing that can write `showCompleted`.
    var showsCompletedToggle: Bool
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
enum CadenceTaskSurfaceOptions {
    /// How many completed rows any surface lists before it stops.
    ///
    /// One number, because there was never a reason for two: Today and Inbox capped at 12 while
    /// All Tasks capped at 24, so the same finished task was listed on one screen and dropped on
    /// another. 24 is the larger of the two — it never hides work the smaller cap would have
    /// shown, and All Tasks has been rendering that many since it was written.
    static let completedRowLimit = 24

    /// Ignores its argument today, on purpose: every surface offers the same two controls, and the
    /// parameter is what keeps a future exception attached to a *surface* rather than to a width.
    static func options(for surface: CadenceTaskSurface) -> CadenceTaskViewOptions {
        CadenceTaskViewOptions(showsSort: true, showsCompletedToggle: true)
    }

    /// The completed rows a surface actually lists — the full set, capped at `completedRowLimit`.
    static func completedRows<Task>(from tasks: [Task]) -> [Task] {
        Array(tasks.prefix(completedRowLimit))
    }
}

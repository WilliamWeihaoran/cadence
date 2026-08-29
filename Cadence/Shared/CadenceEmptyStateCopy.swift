import Foundation

/// Empty-state wording that more than one screen shows.
///
/// Each of these used to be written out at the call site, which is how three pairs of screens
/// ended up saying the same thing in different words: All Tasks promised your tasks would collect
/// here "on iPad or Mac" at one width and "on iPhone, iPad, or Mac" at the other; the two Inboxes
/// had a sentence each for one idea; and Focus managed two subtitles under one title inside a
/// single file. Copy that appears twice lives here so it cannot drift a third time.
///
/// `nonisolated` because the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a bare
/// enum here is main-actor isolated: reading it from one of the `nonisolated` presentation values
/// that need it warns today and is an error under Swift 6. It was missed by the pass that
/// unisolated the rest of these, which is why `CadenceTaskCollection` kept its empty-state words
/// in a private iOS-only extension instead of on the enum. Constants have no state to protect.
nonisolated enum CadenceEmptyStateCopy {
    static let inboxTitle = "Inbox is clear"
    /// Says what to do and what happens next, which the alternative ("Fast capture lives here
    /// before you decide where things belong") only implied.
    static let inboxSubtitle = "Capture tasks here before scheduling or filing them."

    static let allTasksTitle = "No active tasks"
    /// Names all three surfaces the app runs on. The iPad spelling omitted iPhone, which is a
    /// device the reader is holding one of.
    static let allTasksSubtitle = "Tasks you create on iPhone, iPad, or Mac will collect here."

    static let focusTitle = "No focus tasks"
    /// The shorter of the two that shipped: an empty state states the one thing to do.
    static let focusSubtitle = "Schedule a task for today to focus it here."

    /// A list, project or area detail page with nothing in it — the Mac's `ListTasksView` and the
    /// phone's `iOSListDetailView`, which are the same page at two widths.
    ///
    /// Deliberately avoids the word "yet": the retired desktop title was "No tasks yet", and a new
    /// spelling that contains the old one as a substring is indistinguishable from a revert to any
    /// guard reading source text.
    static let listDetailTitle = "No tasks here"
    /// **Names a control that is actually on the screen.** Both surfaces put a floating `+` on this
    /// page — `floatingNewTaskButton` on the Mac, `iOSFloatingCreateTaskButton` on the phone — and
    /// both subtitles pointed somewhere else: the Mac said "Create a task to get started", the
    /// phone said "Add a task above" beside a page with no field above it. Same failure, and the
    /// same one `CadenceTodayPresentationSupport.emptySubtitle` already records.
    static let listDetailSubtitle = "Add a task with +, or move one here from Inbox."
}

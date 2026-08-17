import Foundation

/// Empty-state wording that more than one screen shows.
///
/// Each of these used to be written out at the call site, which is how three pairs of screens
/// ended up saying the same thing in different words: All Tasks promised your tasks would collect
/// here "on iPad or Mac" at one width and "on iPhone, iPad, or Mac" at the other; the two Inboxes
/// had a sentence each for one idea; and Focus managed two subtitles under one title inside a
/// single file. Copy that appears twice lives here so it cannot drift a third time.
enum CadenceEmptyStateCopy {
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
}

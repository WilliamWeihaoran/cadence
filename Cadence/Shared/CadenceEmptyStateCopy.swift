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

    // MARK: - Pages that exist at two widths

    /// The saved-links panel on a list, area or project detail page.
    ///
    /// **Deliberately names no control.** The two surfaces do not carry the same one: the Mac's
    /// `LinksView` header holds a bare `+` glyph, the phone's `iOSListLinksPanel` holds a labelled
    /// `Add Link` button. The Mac's spelling was "Tap + to save a link", which is wrong twice —
    /// a Mac is clicked rather than tapped, and the `+` it names is not what the other surface
    /// shows. A sentence that says what the panel is *for* is true at both widths.
    static let savedLinksTitle = "No saved links"
    static let savedLinksSubtitle = "Save URLs that belong with this list."

    /// The notes column of a list, area or project detail page.
    ///
    /// Here the `+` *is* the same control on both — a menu behind a bare plus glyph
    /// (`ListNotesHeaderView` on the Mac, `iOSListNotesView.newNoteMenu` on the phone) — so the
    /// subtitle may name it, in the same shape `listDetailSubtitle` uses. The Mac said "Tap + to
    /// create one" and the phone "Tap + to create one." — one idea, two spellings, differing by a
    /// full stop, which is what a shared constant is for.
    static let listNotesTitle = "No notes"
    static let listNotesSubtitle = "Add a note with +."

    /// The Log / Completed tab of a list detail page.
    ///
    /// The Mac's subtitle ("Completed tasks will appear here") restated its own title and said
    /// nothing about scope; the phone's says which list the reader is looking at.
    static let completedTasksTitle = "No completed tasks"
    static let completedTasksSubtitle = "Completed work from this list will collect here."

    /// The review sheet after asking the AI for tasks from a note.
    ///
    /// Not a "you have nothing" state and not a filter miss: the extraction ran and found nothing,
    /// so the subtitle says that rather than telling anyone to create something.
    static let noteActionTasksTitle = "No tasks found"
    static let noteActionTasksSubtitle = "The note did not contain clear action items."

    /// The Lists page, phone and iPad pane. Both draw `iOSListCreateButtonsRow` above this, so
    /// "here" is true on both.
    static let activeListsTitle = "No active lists"
    static let activeListsSubtitle = "Create an area or project here, or restore one from Archived."

    // MARK: - The Notes page, tab for tab

    /// `iOSNotesView` carried a private copy of all four pairs under a comment claiming they were
    /// "Same words macOS uses, tab for tab". They were not: the Events subtitle had a full stop the
    /// Mac's did not. A comment cannot hold two spellings together; this can.
    static let dailyNotesTitle = "Nothing written yet"
    static let dailyNotesSubtitle = "Days you write on appear here. Pick a date above to open one."
    static let weeklyNotesTitle = "Nothing written yet"
    static let weeklyNotesSubtitle = "Weeks you write in appear here. Pick a date above to open one."
    static let notepadTitle = "No notes yet"
    static let notepadSubtitle = "Notepad holds notes that belong to no particular day."
    /// The one tab with no control of its own — `NotesListHeader(title: "Event Notes")` takes
    /// neither `onCreate` nor `onPickDate` — so this points at the screen that does have one.
    static let meetingNotesTitle = "No meeting notes yet"
    static let meetingNotesSubtitle = "Create one from a calendar event."

    // MARK: - "You have nothing" is not "your filter matched nothing"

    /// Whether a list came up empty **because something is narrowing it**.
    ///
    /// Three macOS pages asked only `searchText.isEmpty` while also holding a status or scope
    /// filter, so the filter's own misses fell through to the first-run sentence: Habits defaults
    /// to *Due Today*, so a habit set to Mon/Wed/Fri, read on a Tuesday, produced "No habits yet /
    /// Create a habit, then link it to the goal it supports." beside a page full of habits. Goals
    /// and the goal roadmap default to *Active* and did the same to a finished goal. Each already
    /// offered the right words in its other branch — "Try a different search or status." — and just
    /// never reached them.
    ///
    /// The search half is **trimmed**: a field holding only spaces narrows nothing, because the
    /// matchers trim before comparing, so it must not be reported as a filter that did.
    static func isNarrowedToEmpty(searchText: String, filterNarrows: Bool) -> Bool {
        filterNarrows || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

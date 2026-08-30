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

    /// The same page when the list it was showing is not there any more — the Mac's
    /// `MissingListDetailView` and the phone's `iOSMissingListView`, which are one situation
    /// explained on two devices.
    ///
    /// **The last pair the app held together with a test instead of a constant** (T-522).
    /// `CadenceDeletedSelectionGuardTests.theMacMissingListStateReusesTheSentenceIOSAlreadyShips`
    /// asserted the two files carried the *same literals*, deliberately: macOS borrowed the
    /// sentence iOS had already shipped rather than writing a second one, and pinning the pair was
    /// how that borrowing was kept honest. It pinned the drift without removing the second copy,
    /// and it cost `CadenceEmptyStateAuditTests` a standing `emptyStateDuplicateAllowance` entry
    /// saying so. Both are gone: the guard still fails if either surface stops saying this, and it
    /// reads the constant to do it.
    ///
    /// The glyph stays spelled at both call sites. `questionmark.folder` is a picture rather than a
    /// sentence, which is the same distinction `CadenceSharedConstantReuseSweepTests` makes when it
    /// drops SF Symbol names from its harvest.
    static let missingListTitle = "List not found"
    /// Names all three ways a list goes missing, including the one that happens where this reader
    /// cannot see it: another device. "Deleted" on its own would be a guess about which.
    static let missingListSubtitle = "This list may have been archived, deleted, or changed on another device."

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

    /// **The second clause is only true when the section it names is on screen** (T-526).
    ///
    /// This was one unconditional sentence ending "…, or restore one from Archived." — but both
    /// shells draw the Archived section only when something is archived
    /// (`!archivedAreas.isEmpty || !archivedProjects.isEmpty`), and the empty state itself only
    /// shows when there are no *active* lists. On a fresh or fully emptied store both hold at
    /// once, so the one reader guaranteed to see this sentence — someone who has never made a
    /// list — is the one reader for whom the section it points at is not drawn. Same defect as
    /// T-469's "Add a task above": copy naming something that is not on the screen is worse than
    /// no copy. The pattern was already in the app one screen over — `iOSSettingsView`'s
    /// "No active contexts" row says "Create one here" and stops.
    ///
    /// A function rather than two constants, in the shape `isNarrowedToEmpty` already uses, so a
    /// call site cannot take a half without answering the question. The caller must pass the
    /// **same** predicate that draws the section: `iOSListsView` and `iOSListsRegularPane` each
    /// hold it once as `hasArchivedLists` and feed both the section and this.
    ///
    /// The first-run half keeps "here", which stays true — `iOSListCreateButtonsRow` is directly
    /// above the panel on both shells.
    static func activeListsSubtitle(hasArchived: Bool) -> String {
        hasArchived
            ? "Create an area or project here, or restore one from Archived."
            : "Create an area or project here."
    }

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

    /// **"Nothing selected" is not "nothing exists", so these three carry no subtitle** (T-548).
    ///
    /// The editor pane beside a notes column that *has* rows in it. Both surfaces already said the
    /// same three words in four places — `NotesEditorPlaceholder` on the Mac's Notes page,
    /// `ListNotesEditorPlaceholder` in its list-detail notes column, `iOSNotesView.placeholderTitle`
    /// and `iOSListNotesView` on the phone — and `iOSNotesView`'s copy was annotated "macOS's three
    /// placeholders, tab for tab", which is the comment-instead-of-a-constant shape this file's own
    /// doc comment opens by describing. `"Select a note"` is the pair the widened duplicate sweep
    /// could see; its two siblings are here because they are the same sentence one tab over and
    /// would have drifted the same way.
    static let selectNoteTitle = "Select a note"
    static let selectWeekTitle = "Select a week"
    static let selectMeetingNoteTitle = "Select a meeting note"

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

    /// **The Goals list and the Goals roadmap are one page in two view modes, so they get one
    /// title** (T-540).
    ///
    /// `GoalsViewModeToggle` switches between them without changing the page's identity, and both
    /// were spelling this pair out at their own call site. They agreed exactly at the point this
    /// was written — which is luck rather than discipline: the sweep that exists to catch a
    /// sentence spelled twice **could not see either of them**, because both are written as
    /// `isNarrowedToEmpty ? … : …` and its reader matched only a literal placed directly after
    /// `message:`. Widening that reader is what surfaced this pair, and these are the only two
    /// duplicates it found.
    ///
    /// A function taking the predicate, in the shape `activeListsSubtitle(hasArchived:)` and
    /// `isNarrowedToEmpty` already use, so a call site cannot take one half of the pair without
    /// answering the question that decides which half is true.
    ///
    /// **The two subtitles stay at their call sites, and that is not an oversight.** They name
    /// different controls because the two modes carry different ones: the list has a visible
    /// search field beside a status picker ("Try a different search or status."), the roadmap has
    /// a single popover button labelled *Filter* holding both ("Try a different filter."). Same
    /// reasoning as `savedLinksSubtitle` naming no control at all — copy converges when the
    /// surfaces really do show the same thing, not because two sentences sit next to each other.
    static func goalsTitle(isNarrowed: Bool) -> String {
        isNarrowed ? "No matching goals" : "No goals yet"
    }

    /// **The Habits page's title, on both surfaces** (T-548).
    ///
    /// Same shape as `goalsTitle(isNarrowed:)` and found the same way, one widening later: the Mac
    /// spelled `"No habits yet"` in `HabitsView` and the phone spelled it again in
    /// `iOSFeatureViews`, byte for byte, while the sweep that exists to catch that could see
    /// neither — `iOSFeatureViews` names no empty-state component at all, reaching `iOSEmptyPanel`
    /// through `iOSFeatureEmptyState` → `iOSFeatureEmptyDetail`.
    ///
    /// **The phone passes `false` because its Habits chooser holds no search field and no filter**,
    /// so `nil` there means the collection is empty. That is the question the parameter exists to
    /// make a caller answer, rather than a formality: the Mac's page defaults to *Due Today*, and
    /// answering it wrong is exactly the defect `isNarrowedToEmpty` was written for.
    ///
    /// **The subtitles stay apart, and unlike the goals pair they have already drifted** — the Mac
    /// says "Create a habit, then link it to the goal it supports.", the phone "Create repeating
    /// commitments and track today.". Which one is true of which surface is a copy decision, not a
    /// de-duplication, so it is left where a reader can see both.
    static func habitsTitle(isNarrowed: Bool) -> String {
        isNarrowed ? "No matching habits" : "No habits yet"
    }
}

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

    /// **The Focus picker's empty state, on both platforms ([[T-6003]]).** The picker offers every
    /// task `CadenceFocusSupport.canFocus` admits — not done and not cancelled — whatever its date,
    /// so this shows only when there is no open task at all. The phone used to say "Schedule a task
    /// for today to focus it here." and the Mac's popover "When a task is ready, it will appear
    /// here.": neither is the rule, and they disagreed. What is needed here is any task.
    static let focusTitle = "No open tasks"
    static let focusSubtitle = "Add a task to focus on it here."

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

    /// The iPad/iPhone list Kanban tab when the list has **no columns at all** — every section
    /// archived. It used to read "No kanban cards" whenever the list had no open tasks, which hid
    /// the configured columns (and their `+` drop targets) exactly when a fresh list needed them
    /// ([[T-7033]]); columns are drawn now whenever there are any, as macOS always did. The
    /// subtitle names the control under it, `CadenceSectionCreationRow`.
    static let listKanbanTitle = "No columns"
    static let listKanbanSubtitle = "Add a section below to start this board."

    // MARK: - Pages that exist at two widths

    /// A calendar day with nothing on it — the Board's day column and the day inspector, which are
    /// the same day drawn two ways on the same screen.
    ///
    /// **T-601(a).** The Board column already said this through `CadenceInlineEmpty(surface:
    /// .touch)`; the inspector re-drew that component by hand — same words, same 13pt, same
    /// `Theme.dim`, same `Theme.surfaceElevated.opacity(0.38)` wash, same `Theme.radiusControl` —
    /// and got the vertical padding wrong at 6 against the shared touch metric's 14. It carried an
    /// "Add" button inside the card as well, which the Board answers with the ordinary
    /// `iOSCalendarAddItemRow` above the line rather than a second add control of its own; the
    /// inspector's non-empty branch was already drawing exactly that row, so the empty branch now
    /// matches its own sibling as well as the Board's.
    ///
    /// The sentence has to live here for the same reason every other one on this enum does: with
    /// both surfaces reading the real component, `noEmptyStateSentenceIsSpelledInTwoFiles` sees
    /// two files spelling it. At seventeen characters it also clears
    /// `CadenceSharedConstantReuseSweepTests`' twelve-character floor, so declaring it genuinely
    /// arms that sweep against a third surface typing the words out — which is not true of every
    /// constant this ticket touched.
    static let nothingScheduledTitle = "Nothing scheduled"

    /// **T-5013(a).** The Calendar Board's Overdue rail, which draws a header over nothing in the
    /// state it is in for anyone who keeps up. `form(for:boardForm:)` returns `.expanded` whenever
    /// the pane is wide enough regardless of the count, `addBehavior` answers `nil` for this rail
    /// (a task cannot be dragged — or created — into being late), and `KanbanColumnScroll` then
    /// draws `content()` alone inside a `.frame(minHeight: 200)`. So "Overdue 0" stood over 200pt
    /// of empty column at the leading edge of the board.
    ///
    /// The owner declined collapsing the rail when empty: the count crosses zero often, and a rail
    /// that comes and went would shift the whole board each time. Being caught up has to read as
    /// deliberate rather than broken, which is what a sentence does and a blank does not.
    ///
    /// Phrased as a state rather than an instruction, unlike `nothingScheduledTitle`'s neighbours
    /// that sit beside an add row: there is no control here to point at, and there should not be.
    static let nothingOverdueTitle = "Nothing overdue"

    /// **T-5013(b).** iOS Search with an empty query on a narrowed scope. `resultSection` draws
    /// nothing for an empty array and the "No results" panel is gated on `isSearching`, so
    /// choosing Notes / Lists / Events with nothing to suggest — a new store, or no events in
    /// the window — left the scope picker sitting over blank space. macOS's
    /// `GlobalSearchEmptyState` has had an idle state for exactly this since it was written.
    ///
    /// macOS says "Start typing to search or run a command" over a whole panel; this is the
    /// one-line form, because the phone draws it inline under a scope picker rather than in a
    /// panel of its own. It names the scope when the user has narrowed to one, since the blank
    /// they are looking at is scope-shaped — they have just picked a kind of thing, and the
    /// surface should say which.
    static func searchIdleTitle(scopeNoun: String?) -> String {
        guard let scopeNoun else { return "Start typing to search" }
        return "Start typing to search \(scopeNoun)"
    }

    /// **[[T-6971]] / [[T-6975]].** A failed search whose matches are all finished tasks, with the
    /// Completed filter off — the default on both platforms. Without this line the Mac palette said
    /// "No matches found" and iOS "No results" over generic advice, which is false: the tasks exist
    /// and the Completed control beside the field shows them. Both surfaces name that control by
    /// its label, so one sentence is true on both. `nil` when nothing is held back, so each surface
    /// keeps its own ordinary advice.
    static func searchWithheldCompletedTasks(count: Int) -> String? {
        switch count {
        case ..<1:
            return nil
        case 1:
            return "1 completed task matches. Turn on Completed to show it."
        default:
            return "\(count) completed tasks match. Turn on Completed to show them."
        }
    }



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

    /// The list-detail Notes tab when it has notes and its search or tag filter reaches none of
    /// them. Both platforms ([[T-7031]] gave iOS the filter).
    static let listNotesNoMatchesTitle = "No matches"
    static let listNotesNoMatchesSubtitle = "Try a different search"

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
    ///
    /// **`hasCandidates` is the half T-1446 added, and it is the one the first reader hits.**
    /// `filterNarrows` answers "is a narrowing filter *selected*", which is not the same question
    /// as "is that filter hiding anything" — and on an empty store the two part company. Goals
    /// defaults to *Active* and Habits to *Due Today*, so someone who has never made a goal or a
    /// habit was told "No matching goals / Try a different search or status." on a page with no
    /// search term typed and nothing whatever to match: sent to adjust a control they never
    /// touched, away from the one thing there is to do. **Nothing can be narrowed out of an empty
    /// collection**, so when the collection this page draws from is empty the answer is `false`
    /// however the controls are set, and the first-run copy is what shows.
    ///
    /// The caller answers it, never this function: "the collection this page draws from" is a
    /// different array on every surface (every goal, every habit, every list), and a filtered one
    /// is always empty in exactly the state being asked about — which is why it cannot be inferred
    /// here. Same shape, and the same reason, as the retired goalsTitle(isNarrowed:allComplete:)'s
    /// `allComplete` had. Defaulted to `true` so a caller that has genuinely nothing to report — the
    /// attach-lists sheet, whose `filterNarrows` is already a constant `false` — reads as it did.
    static func isNarrowedToEmpty(
        searchText: String,
        filterNarrows: Bool,
        hasCandidates: Bool = true
    ) -> Bool {
        guard hasCandidates else { return false }
        return filterNarrows || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // **goalsTitle(isNarrowed:allComplete:) and habitsTitle(isNarrowed:) left with
    // [[T-5002]].** T-540, T-548 and T-689 converged the Goals and Habits titles here because four
    // call sites were spelling them, and the owner has since deleted all four screens: [[T-2079]]
    // retired every in-app writer of a `Goal` or a `Habit` and [[T-2076]] left the pages with no
    // route in, so the pages, their empty states and these two titles went together. The five
    // strings — "No goals yet", "No matching goals", "All goals complete", "No habits yet",
    // "No matching habits" — are entries in `cadenceRetiredCopy`, so a screen written next year
    // cannot bring one back without saying so. The models stay: `Habit`, `HabitCompletion` and
    // `Goal` are still in `CadenceSchema`, still exported and still cleared by
    // `CadencePrivacyDataResetService`.

    /// **"No lists yet", converged from three spellings** (T-699). `CadenceListsSummary.eyebrow(…)`
    /// returned it as the fallback branch of the Lists page's summary line, `iOSRootSidebar`'s
    /// collapsed-sections row typed it as a bare `Text`, and `iOSGoalAttachListsSheet` typed
    /// `isNarrowedToEmpty ? "No matching lists" : "No lists yet"` — the third site named the shape
    /// the other two lacked, so this takes `isNarrowed:` the way the retired goalsTitle(isNarrowed:)
    /// and habitsTitle(isNarrowed:) did, rather than being a bare constant. `"No matching lists"` had
    /// no declaration anywhere before this.
    static func listsTitle(isNarrowed: Bool) -> String {
        isNarrowed ? "No matching lists" : "No lists yet"
    }

    /// **The create row both sidebars draw when their lists region holds nothing** — macOS's
    /// `SidebarAddFirstListButton` (T-1113) and the touch column's `addFirstListButton` (T-3073).
    ///
    /// Here rather than on either component, for the reason this type exists at all: the two
    /// columns cannot share the *button* — one is sized for a pointer off `SidebarMetrics` and one
    /// for a finger off `iOSSidebarMetrics` — but they must not be allowed to disagree about the
    /// words. It is the action, not a statement of what is missing, so it sits beside
    /// `listsTitle(isNarrowed:)` rather than replacing it: the touch column says both, one under
    /// the other.
    static let addFirstListAction = "Add first list"
}

# Decisions waiting on you

Refreshed 2026-10-27 by agent `decisions1108` from `./scripts/ledger-view.sh head` at `33927d3a`.
Every item is an OPEN or PARTIAL ticket whose only remainder is yours. Each line: the question,
the options, **a recommendation**, the ticket. The reasoning is in the ticket
(`./scripts/ledger-view.sh head T-NNNN`); this file is a queue, not a record. "Code checked"
means the cited symbol was read at HEAD and still says what the ticket says.

---

## A. Things you would see in the app

Ranked by how often you would meet it, 11-inch iPad first, then the Mac.

1. **Focus timer card says "Paused" before a session has ever started** -- the first word on
   the iPad two-pane Focus, which always arrives with a task selected. Show "Ready" while
   `elapsedSeconds == 0`, or leave. **"Ready"**, one shared third state for both platforms.
   [T-7018] Code checked (iOS label is now `iOSFocusView.swift:815`, not `:773`; Mac `:123`).
2. **iOS task sheet shows two buttons that both say "Cancel"**: the status button cancels the
   task, the panel footer discards the edits. (a) status button "Cancel Task" / "Restore",
   (b) footer "Close", (c) leave. **(a)** -- the footer's "Cancel" is the sheet convention every
   panel host shares. [T-7204] Code checked (`StatusAction.title(for:)`,
   `CadenceTaskInspectorSupport.swift:143`; footer `CadenceSchedulePanel.swift:850`).
3. **Kanban columns are "column" on every control but a new one is named "New Section".**
   (a) default "New Column" and the iOS Kanban tab's add row says "Add column", (b) leave,
   (c) one word everywhere. **(a)** -- only the default for new columns changes, never a stored
   name. [T-7085] Code checked (`KanbanBoardSupport.nextSectionName`, `CadenceSectionCreationRow`).
4. **iOS Settings splits the Calendar toolbar's Week / Month / Board into two rows**, so with
   Board on, "Calendar view" still reads "Week". (1) one row with all three, (2) grey the row
   under Board, (3) leave. **(1)** -- it is what the page's toolbar already shows. [T-7074]
   Code checked (`calendarViewRow` / `calendarStyleRow`).
5. **iPad Today drag-create opens its editor as a popover on the block**, which drops for the
   length of an edge-handle drag; the Calendar page uses a sheet. Redesign as an in-pane panel
   or keep. **Keep until after the RC** -- it is the shape you chose (T-3169, T-3240), and it
   comes back by itself. [T-3171] (item v) [T-3252]
6. **Cancelled task: iOS shows "Reopen" + "Restore" (same action twice); the Mac shows
   "Mark done" + "Restore".** Pick one rule. **The Mac's**: the completion button keys on done
   only, so a cancelled task offers Complete + Restore, two different actions; each platform
   keeps its own verbs. [T-7012] Code checked (iOS keys `isFinishedTask`, Mac keys `isDone`).
7. **Mac Cmd+K search copy**: an untitled daily note reads `2026-10-26` over
   `Daily • 2026-10-26` (iOS `Daily / 2026-10-26`); the empty title is "No matches found" on the
   Mac, "No results" on iOS; the idle line leaves out notes. **Format the dates through
   `DateFormatters`, "No results" on both, add "notes"** to the idle line. [T-7205] Code checked
   (`GlobalSearchIndexSupport.swift:456-457`, `GlobalSearchSupportViews.swift:502,514`,
   `iOSSearchView.swift:345`).
8. **Mac `/` picker in a note has no height cap** -- a bare `/` lists ~22 rows (~580pt), more than
   a 13-inch MacBook fits beside the caret. Cap it (~10 rows, scrolling with the highlight) or
   leave. **Cap it** -- the keyboard highlight can walk off screen today. [T-7233] Code checked
   (`MarkdownSlashCommandPickerView` is a bare `VStack`, no `ScrollView` in the file).
9. **Mac menu bar names Search (Cmd+K), the sidebar (Cmd+O) and the timeline (Cmd+\) nowhere**;
   the keys work. Settings... / Cmd+, already landed under T-7232, so only the View-menu half is
   left. (a) a View-menu group routed to the same actions the key monitor fires (no double-fire),
   (b) leave. **(a)**; keep Cmd+O as the sidebar key unless you want the system's Ctrl+Cmd+S.
   [T-7203] Code checked (only `.newItem` and `.appSettings` groups in
   `macOSRootMenuCommands.swift`; arms `case 40/42/31` in `macOSRootCommandEventSupport.swift`).
10. **List order cannot be changed on the iPad at all, and a Mac drag onto another context's
    section silently does nothing.** (b) **refuse the cross-context drop now** (no re-filing);
    (a) iPad reorder **after the RC** unless you reorder lists on the iPad. [T-7260] Code checked
    (`reorderList` returns early, `performDrop` still answers `true`; no `onMove` in
    `iOSRootSidebar.swift` / `iOSListViews.swift`).
11. **A saved link can be neither edited nor reordered**, on either platform; a typo means delete
    and re-add (which moves it to the bottom). (a) Edit, (b) Edit + drag reorder, (c) leave.
    **(a) Edit, after the RC**; reorder can wait. [T-7259] Code checked (`order` written once at
    insert, `LinksView.swift:107`, `iOSListSupportViews.swift:792`; nothing writes `title`/`url`).
12. **Mac Links tab opens with a "Saved Links" label under a tab already reading "Links".**
    (a) drop it, (b) match iOS's leading "Add Link" button, (c) leave. **(b)** -- one vocabulary,
    and the add action gets a word. [T-7257] Code checked (`LinksView.swift:28`; iOS
    `iOSListSupportViews.swift:707`).
13. **iPhone Focus picker cuts task titles at one line** (~30 characters at 393pt). (a) two lines
    on iOS, (b) keep, (c) two lines on both. **(a)** -- the task-row rule, and the Mac's width
    rarely truncates. [T-7089] Code checked (`iOSFocusPickRow` title `.lineLimit(1)`).
14. **iOS Search's sixth chip reads "More" and opens a section headed "Pages"** (the Mac says
    "Pages"). **Rename the chip "Pages"** -- one word, matches the section and the Mac. [T-6984]
    Code checked.
15. **iOS column editor: "Complete" / "Reopen" / "Archive" but "Unarchive Column".** Add the noun
    to all four (Mac's wording, may truncate at 393pt) or drop it from the fourth. **Drop it**
    ("Unarchive") -- safe at every width. [T-6983] Code checked (`iOSListEditorViews.swift:767`).
16. **Mac New List: switching Area / Project resets the colour and icon you already picked**;
    iOS keeps them. (1) match iOS, (2) move only a colour/icon still at the old type's default,
    (3) keep resetting. **(1)** -- the platforms agree and nothing you chose is thrown away.
    [T-7269] Code checked (`CreateListSheet.swift:84-85`).
17. **Should Return create the approved drafts in the Mac AI task-draft sheet?** Every card is a
    column of text fields, so Return would turn "finish this title" into "create everything".
    (1) leave (today), (2) Return, (3) Cmd+Return. **(3)**. [T-7290] Code checked
    (`NoteActionReviewSheets.swift:158`, Return deliberately unbound).
18. **The AI review sheets use different words per platform**: summary Mac "Close" / "Append to
    Note" vs iOS "Discard" / "Append"; drafts Mac "AI Task Drafts" / "Create Selected" vs iOS
    "Task Drafts" / "Create 3". **One shared set: "Close" / "Append to Note", title "Task
    Drafts", "Create 3"** (the count says what will happen). [T-7291] Code checked
    (`NoteActionReviewSheets.swift:51,116,169`; `iOSAINoteActionsViews.swift:194,197,281`).
19. **Settings AI pane: the "Selected note content" row says "may be sent ... related list names"**,
    vaguer than the definite privacy sentence two rows above it, on both platforms. (1) retitle
    "The note you run it on" / "Its title, its full text, and the name of its list.", (2) delete
    the row, (3) leave. **(1)**, one shared constant pair -- privacy copy, so your eye.
    [T-7210] Code checked (`SettingsSectionViews.swift:207`,
    `iOSSettingsTemplateAndListSections.swift:457`).
20. **Settings > Reminders draws an untitled Apple Reminders list as a blank row**, and the two
    delete-everything gates list different kinds (Mac names documents not focus history, iPhone
    the reverse; neither names habits, goals or images). **"Untitled List" at display time only;
    the gates stop enumerating** ("everything Cadence holds in this store") so they cannot go
    stale. [T-7209] Code checked (`listRows` groups by raw `listTitle`,
    `CadenceRemindersPresentationSupport.swift:210`; `SettingsDataSafetySection.swift:591`,
    `iOSDataResetSettingsSection.swift:149`).
21. **VoiceOver headings rotor lands on each page header's eyebrow, not the title.** (a) the title
    is the heading, eyebrow loses the trait, (b) both, (c) leave. **(a)**, low priority -- one
    heading per header. [T-7090] Code checked (title in `titleColumn` has no trait).
22. **VoiceOver: the AI draft approval controls do not say which draft they act on** (Mac: five
    identical "Include this task"; iOS: "Approved, tap to reject"). **"Include <draft title>",
    state as the accessibility value, on both.** Overlaps item 18. [T-7294] Code checked
    (`NoteActionReviewSheets.swift:220`, `iOSAINoteActionsViews.swift:454`).
23. **VoiceOver reads Mac list icons by SF Symbol name** ("folder.fill"). The 44 human names are
    the decision. **Let an agent draft the table beside `CadenceIconPalette` for your
    approval**, read by both Mac pickers and both iOS pickers. [T-7270] Code checked (strip
    `ListEditorSupportViews.swift:237`; the grid goes through `.cadenceControlLabel("Select
    \(icon) icon")`, `CreateContextSheet.swift:175`, not a bare `accessibilityLabel` -- same
    words read).

## B. Data edges (rare, nothing lost today)

Nothing open: every item in the last pass was answered on 2026-10-26 (see the list below).
T-6482 (a merge can unparent a child still in CloudKit flight) was checked and needs no owner
call -- it is a POST-RC fix with two technical shapes for the agent who takes it.

## C. Things only you can do (hands, not choices)

24. **Create a Mac Installer Distribution certificate** (Xcode > Settings > Accounts > Manage
    Certificates > +). Without it the macOS leg archives but cannot be packaged for TestFlight;
    the iOS leg is fine. [T-7102]
25. Five-minute EventKit check on your Mac + iPhone. [T-1117]
    (`docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`)
26. Turn on 24-Hour Time on the Mac, relaunch, say whether Cadence follows. [T-1163]
27. Restore a backup on a test account and see whether newer iCloud edits sync back in; that
    decides the backup note's wording. [T-3226]
28. `git config core.hooksPath .githooks`. Today it points at the deleted
    `~/Desktop/Projects/Cadence/.git/hooks`, so no hook runs (checked 2026-10-26). [T-4900]
29. App Store Connect privacy answers: Name, Email, User ID -> not collected. Public release
    only. [T-1424]
30. Logo: supply concept-A artwork (never committed) or approve a redraw. [T-16]
31. Two-device archive comparison on your own iCloud account. [T-2053]
32. Answer the per-session automation prompt when a UI run asks. [T-2049]
33. One attended `CADENCE_T710_RUNS=40` run of `CadenceSeededSidebarTimingUITests` (it drives
    your screen) to find the blank-launch cause; everything else in the ticket landed. [T-2020]
    Code checked (the variable is read at `CadenceSeededSidebarTimingUITests.swift:79`, not `:80`).

## D. Tooling and process (nothing a user sees)

34. **Delete the dead symbols that only tests still read** (`GoalAssignmentRules`,
    `goalsShowsInspector`, `HabitInfoCard`, `iOSTrackingEditorShell`, ...) together with the
    tests that pin them? **Yes** -- nothing user-visible, and their pins are now unleased.
    [T-5523] (part a)

---

**Decided 2026-10-26, not yet built** (still OPEN/PARTIAL; listed so nobody asks again):
T-3213 remove task bundles from the app (the CloudKit model type itself must stay; slice 1, the
queries and dead surface code, landed -- the remainder is T-7182),
T-6541 retry the CI step once T-6821 clears.

Built 2026-10-26 by agent `decideapp2208` and removed from the list above: T-6191 (count repaired
on open), T-3227 (comment fixed).

Carried into the ledger 2026-10-26 by agent `decideclose2208` and removed from the list above:
CLOSED on the ruling -- T-1845, T-2074, T-4721, T-3116, T-3044, T-3018, T-3015, T-5500, T-1990,
T-3092; kept open with a SHIP-NOTE because the ruling defers them -- T-6481 and T-3019 (after the
RC), T-3207 (after T-1475 is seen on screen). Stale "still open" comments those closes left in
source are T-7186.

Removed this pass because the ticket is CLOSED: T-7067 (Mac month-grid cell now names its day
to VoiceOver, agent `maca11y2108`).

Checked this pass and left out: already ruled -- T-1840 (yes, delete the recovery store and
earlier store folders too, 2026-10-22; POST-RC build), T-4501 (13-inch one-point miss, low
priority, 2026-10-22), T-3147 (capture latency parked past the RC); not an owner call -- T-168,
T-3013, T-3114, T-3152, T-3160, T-3297, T-6410 (agent work, or blocked on T-3259). Earlier
history is in this file's git log.

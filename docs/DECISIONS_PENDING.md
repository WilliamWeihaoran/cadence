# Decisions waiting on you

Refreshed 2026-10-26 by agent `decisions2108` from `./scripts/ledger-view.sh brief` at `87fa0968`.
Every item is an OPEN or PARTIAL ticket whose only remainder is yours. Each line: the question,
the options, **a recommendation**, the ticket. The reasoning is in the ticket
(`./scripts/ledger-view.sh head T-NNNN`); this file is a queue, not a record. "Code checked"
means the cited symbol was read at HEAD and still says what the ticket says.

---

## A. Things you would see in the app

Ranked by how often you would meet it, 11-inch iPad first.

1. **Focus timer card says "Paused" before a session has ever started** -- the first word on
   the iPad two-pane Focus, which always arrives with a task selected. Show "Ready" while
   `elapsedSeconds == 0`, or leave. **"Ready"**, one shared third state for both platforms.
   [T-7018] Code checked (iOS label is now `iOSFocusView.swift:815`, not `:773`; Mac `:123`).
2. **Kanban columns are "column" on every control but a new one is named "New Section".**
   (a) default "New Column" and the iOS Kanban tab's add row says "Add column", (b) leave,
   (c) one word everywhere. **(a)** -- only the default for new columns changes, never a stored
   name. [T-7085] Code checked (`KanbanBoardSupport.nextSectionName`, `CadenceSectionCreationRow`).
3. **iOS Settings splits the Calendar toolbar's Week / Month / Board into two rows**, so with
   Board on, "Calendar view" still reads "Week". (1) one row with all three, (2) grey the row
   under Board, (3) leave. **(1)** -- it is what the page's toolbar already shows. [T-7074]
   Code checked (`calendarViewRow` / `calendarStyleRow`).
4. **iPad Today drag-create opens its editor as a popover on the block**, which drops for the
   length of an edge-handle drag; the Calendar page uses a sheet. Redesign as an in-pane panel
   or keep. **Keep until after the RC** -- it is the shape you chose (T-3169, T-3240), and it
   comes back by itself. [T-3171] (item v) [T-3252]
5. **Cancelled task: iOS shows "Reopen" + "Restore" (same action twice); the Mac shows
   "Mark done" + "Restore".** Pick one rule. **The Mac's**: the completion button keys on done
   only, so a cancelled task offers Complete + Restore, two different actions; each platform
   keeps its own verbs. [T-7012] Code checked (iOS keys `isFinishedTask`, Mac keys `isDone`).
6. **iPhone Focus picker cuts task titles at one line** (~30 characters at 393pt). (a) two lines
   on iOS, (b) keep, (c) two lines on both. **(a)** -- the task-row rule, and the Mac's width
   rarely truncates. [T-7089] Code checked (`iOSFocusPickRow` title `.lineLimit(1)`).
7. **iOS Search's sixth chip reads "More" and opens a section headed "Pages"** (the Mac says
   "Pages"). **Rename the chip "Pages"** -- one word, matches the section and the Mac. [T-6984]
   Code checked.
8. **iOS column editor: "Complete" / "Reopen" / "Archive" but "Unarchive Column".** Add the noun
   to all four (Mac's wording, may truncate at 393pt) or drop it from the fourth. **Drop it**
   ("Unarchive") -- safe at every width. [T-6983] Code checked (`iOSListEditorViews.swift:767`).
9. **VoiceOver headings rotor lands on each page header's eyebrow, not the title.** (a) the title
   is the heading, eyebrow loses the trait, (b) both, (c) leave. **(a)**, low priority -- one
   heading per header. [T-7090] Code checked (title in `titleColumn` has no trait).
10. **Mac month-grid cell names no day to VoiceOver** -- being fixed now by agent `maca11y2108`;
    the wording follows iOS's `CadenceCalendarDayAccessibility`. Override only if you disagree.
    [T-7067] Code checked (`MonthDayCell` has no accessibility modifier yet).

## B. Data edges (rare, nothing lost today)

Nothing open: every item in the last pass was answered on 2026-10-26 (see the list below).
T-6482 (a merge can unparent a child still in CloudKit flight) was checked and needs no owner
call -- it is a POST-RC fix with two technical shapes for the agent who takes it.

## C. Things only you can do (hands, not choices)

11. **Create a Mac Installer Distribution certificate** (Xcode > Settings > Accounts > Manage
    Certificates > +). Without it the macOS leg archives but cannot be packaged for TestFlight;
    the iOS leg is fine. [T-7102]
12. Five-minute EventKit check on your Mac + iPhone. [T-1117]
    (`docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`)
13. Turn on 24-Hour Time on the Mac, relaunch, say whether Cadence follows. [T-1163]
14. Restore a backup on a test account and see whether newer iCloud edits sync back in; that
    decides the backup note's wording. [T-3226]
15. `git config core.hooksPath .githooks`. Today it points at the deleted
    `~/Desktop/Projects/Cadence/.git/hooks`, so no hook runs (checked 2026-10-26). [T-4900]
16. App Store Connect privacy answers: Name, Email, User ID -> not collected. Public release
    only. [T-1424]
17. Logo: supply concept-A artwork (never committed) or approve a redraw. [T-16]
18. Two-device archive comparison on your own iCloud account. [T-2053]
19. Answer the per-session automation prompt when a UI run asks. [T-2049]

## D. Tooling and process (nothing a user sees)

20. **Delete the dead symbols that only tests still read** (`GoalAssignmentRules`,
    `goalsShowsInspector`, `HabitInfoCard`, `iOSTrackingEditorShell`, ...) together with the
    tests that pin them? **Yes** -- nothing user-visible, and their pins are now unleased.
    [T-5523] (part a)

---

**Decided 2026-10-26, not yet built** (still OPEN/PARTIAL; listed so nobody asks again):
T-3213 remove task bundles from the app (the CloudKit model type itself must stay),
T-6541 retry the CI step once T-6821 clears.

Built 2026-10-26 by agent `decideapp2208` and removed from the list above: T-6191 (count repaired
on open), T-3227 (comment fixed).

Carried into the ledger 2026-10-26 by agent `decideclose2208` and removed from the list above:
CLOSED on the ruling -- T-1845, T-2074, T-4721, T-3116, T-3044, T-3018, T-3015, T-5500, T-1990,
T-3092; kept open with a SHIP-NOTE because the ruling defers them -- T-6481 and T-3019 (after the
RC), T-3207 (after T-1475 is seen on screen). Stale "still open" comments those closes left in
source are T-7186.

Removed this pass because the ticket is CLOSED: T-6223, T-6114, T-6201, T-6291, T-4515,
T-3232, T-6781, T-6351 (heartbeat task file fixed: one xcb id per run, so T-3071 is now CLOSED;
T-1920 stays PARTIAL, as the file still calls neither `ci-run-coverage.sh report` nor
`heartbeat-progress.sh report`). Earlier history is in this file's git log.

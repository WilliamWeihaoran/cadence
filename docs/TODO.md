# Cadence — task list

The running record of work: open, in progress, done, cancelled. Started 2026-08-16.

**Format.** One line per item: `- [id] Title — note`. Ids are stable and never reused, so a
cancelled or done item can still be referenced later. Done items keep their commit sha, because the
commit message is where the *reasoning* lives; this file is only the index.

**Rule (set 2026-08-17).** *Every* request the user makes lands here the moment it is made, whether
or not work starts on it — under **In progress** if it is being worked now, otherwise under the
right Open section. An item moves to **Done** only when the code behind it is committed (or
otherwise verified), not when it is written.

**Target devices** (set 2026-08-16). Build and verify for these three only; anything that exists
solely to serve other hardware is dead weight and should be removed rather than maintained:

| Device | Points | Notes |
|---|---|---|
| iPhone 15 (base) | 393 × 852 | compact width, the only phone shape that matters |
| iPad Pro 11" | 834 × 1210 portrait · 1210 × 834 landscape | pane = window − 188pt sidebar → **646** portrait, **1022** landscape |
| MacBook Pro 14" | 1512 × 982 | the macOS surface |

Both iPad panes matter to Today's layout: 646pt portrait falls **below**
`CadenceTodayLayoutSupport.twoPaneMinimumWidth` (761), so portrait is one column and landscape is
two. The three-pane floor of 1022pt that this note used to cite is gone with the layout itself
(T-06).

---

## In progress

Four strands running in parallel, three of them in agents.

- [T-06] **Remove the Focus/Mac layout picker** — Today is always two panes. Note this deletes a
  layout the 11" Pro *can* reach in landscape (1022pt); decided anyway. Picker, its enum, and the
  Settings → Navigation rows that also carried it are out of the working tree; verification pending.
- [T-27] **The iPad sidebar must be foldable** — collapse/expand it, so the detail pane can have
  the full window. Note `CadenceRootShellLayout` already owns the sidebar/detail split and
  guarantees they sum to the window width; a collapsed state is a width of zero there, not a new
  layout path.
- [T-07] **iPad sidebar shows lists inline**, like macOS — no floating panel. Supersedes the
  lists-drawer work in `e792fe8`.
- [T-28] **Calendar: no inspector on Board, and drop the day date bar** — the Board's right-hand
  inspector goes entirely, and the standalone date bar comes out of *both* the Month inspector and
  the Board.
- [T-29] **Notes header: two rows into one.** The second row held one button — the template menu —
  left behind when the Live/Edit/Preview picker that shared it was deleted in `c9fb369`. Both hosts
  (`iOSNotesPanel`, `iOSCompactNotesView`) now pass it as the header's trailing slot; header height
  120 → 64. Needs a width check on the 393pt phone, where the row is back + "Notes" + four tabs +
  the button.

## Open — decided, not started

- [T-30] **Merge Today's sort row into the task-column header row.** With the Focus/Mac picker gone
  (T-06) the header's trailing edge is empty and `iOSTaskViewOptionsBar` sits alone on the band
  below it. Merging them reclaims a full band. Open question for whoever takes it: what happens to
  `iPadTodaySummaryLine`, which shares that band and would otherwise be a padded row holding one dim
  sentence.
- [T-31] **Daily and Weekly notes need a date picker on iOS and iPadOS.** Jump to a particular day
  or week. Requested as "iPhone has it, iPad doesn't" — **checked, and it is neither**: both phone
  and iPad go through `CadenceCoreNoteSupport.loadOrCreateCoreNotes`, which hardcodes
  `DateFormatters.todayKey()` / `currentWeekKey()` (`CadenceNotePlanningSupport.swift:103-104`, and
  again at `:112`/`:114`). The only iOS escape hatch is Search, which finds a past note only if it
  already has text. **macOS is the reference**: `NotesView.swift:550` `NotesDateJumpButton` — a
  calendar pill wrapping `MonthCalendarPanel` — plus a browse-by-date list of every dated note; both
  Daily (`:105`) and Weekly (`:197`) have it, and weekly resolves a picked *day* to its week. The
  two arbitrary-key call sites to copy are `NotesView.swift:161` and `:256`. Note the picker's range
  is bounded to ±24 months (`CadenceDatePicker.swift:94`). Largest instance of T-32 found so far.

  **Decided 2026-08-17.** *Placement:* the header title becomes the date and **is** the control —
  `Aug 17 ⌄` on Daily, `Aug 17–23 ⌄` on Weekly, falling back to the constant word `Notes` on Pad and
  Events, which have no date. This was chosen over a second row and over a second icon button
  because the phone row is full at 390pt (back + "Notes" + four tabs + template button), and because
  a header whose title never changes is spending a slot on nothing. *Scope:* jump-to-date only — no
  browse-by-date list. Picking a day you have never written on must **create** that day's note, which
  is the thing Search cannot do.
- [T-05] **Drag-to-create from the add button** — drag the iPad corner `+` (and the iPhone tab-bar
  `+`) onto a section, list or date; the created task inherits that destination's attributes.
  `CadenceTaskDisplayGroup` already carries a `dropKey`, which is the hook.
- [T-08] **Device-targeting cleanup** — remove handling that exists only for hardware outside the
  three targets above.

## Open — needs a decision

_Nothing open._

## Open — known, unscheduled

- [T-33] **Markdown tables do not render correctly in Notes.** Reported 2026-08-17; no reproduction
  case captured yet, so the first job is to pin down *which* surface and *what* "incorrectly" means
  — the macOS AppKit editor, the iOS editor, or both, and whether it is the parse, the layout, or
  the caret behaviour inside a table. Where to look: table logic belongs in
  `Cadence/Services/Markdown*Support.swift` (which has test coverage) and **not** in `macOS/Editor/`,
  which is only the NSTextView lifecycle and drawing layer. Note tables are a rendered block, so
  they are neighbours of the code-block and task-embed work — both had the same underlying shape
  (characters hidden behind an attachment) and both needed the caret-reveal machinery from `c9fb369`.
  Related: [T-26].

- [T-32] **Feature-consistency scan across platforms.** Added 2026-08-17 at the user's direction;
  **do not run it yet.** The goal state is that no platform has a feature another lacks — macOS,
  iPadOS and iOS offer the same set, differing only in how it is laid out. This directly reverses
  the standing "iOS is not guaranteed parity with macOS by design" note in `CLAUDE.md`, which will
  need rewriting when this lands. Known gaps to fold in when it starts: T-31 (daily/weekly date
  picker missing on iPad), and the `EstimatePickerControl` / macOS-roller split. Two things to
  settle before doing the work rather than during it: whether "same feature" means the same
  *capability* or the same *control*, and what happens to macOS-only surfaces that have no phone
  shape at all (the MCP bridge, global hot keys, the AppKit markdown editor).

- [T-26] **Task embeds in notes are rough to actually use.** The insert works; living with it does
  not. Reported symptoms, all in the markdown editor's task-embed path:
  - **The caret does not move to the task title after inserting one** — you insert an embed and
    then have to go find the title to type it, which makes the common case (insert, name it, carry
    on) two gestures longer than it should be.
  - **Selection behaves oddly around the embed** — selecting across or into it does not do what a
    reader expects.
  - **Position and movement.** Where the embed lands on insert, and moving it once placed.
  Worth knowing before starting: an embed is an `NSTextAttachment` with the underlying characters
  hidden behind it, which is the same construction that made code blocks uneditable until the
  caret-reveal work in `c9fb369` — the reveal machinery and `MarkdownRenderedBlockDeletionSupport`
  are the neighbours to read first. Embed *references* are `[[task:UUID|Title]]`, parsed in
  `Services/Markdown*Support.swift`, which is where behaviour belongs; `macOS/Editor/` is only the
  AppKit bridge. Also relevant: `iOSMarkdownEditor.publishSelectedRange` already snaps the caret
  past hidden runs, so there is an existing rule for "where the caret may sit" rather than a blank
  page.
- [T-24] **Tapping an empty hour lane shoves the timeline grid down.** The "Create at 11 PM"
  composer inserts *above* the scroll view, pushing the hour grid ~120pt, so the row you tapped
  jumps away from your finger while the composer appears at the top of the pane. Pre-existing, but
  far more visible now the grid is 24 rows rather than 17.
- [T-25] **"Ready to Schedule" offers a hardcoded 9 AM / 1 PM / 4 PM.** Three fixed hours covered a
  reasonable slice of a 6-to-23 day; against a full 24 they cover much less of it.
- [T-11] **`iOSSegmentedChoice` truncates silently** past four options for labels over ~9 chars —
  fixed in the control, but worth re-checking call sites as labels change.
- [T-12] **`CadenceReadService` prints "8d" for week-based streaks** — same mislabel fixed
  elsewhere in `38af360`; left alone because the MCP boundary is out of scope without an MCP task.
- [T-13] **Empty container directories leak** — every app/test launch leaves an empty
  `<UUID>-<pid>-<hex>` directory in the macOS app's sandbox container; 1,763 of them, 97 MB.
  Reproduced (count rises by one per test run). Not our code — framework-level — but it accumulates.
- [T-14] **Accessibility permission for window capture** — System Events cannot read the Mac app's
  window geometry from the agent shell, so macOS UI cannot be screenshot-verified. Granting
  accessibility to the terminal would remove a real verification gap.

## Backlog — not scheduled

Added 2026-08-16 at the user's direction. **Not to be worked on now.** Notes are context for
whoever picks these up, not a plan.

- [T-15] **More colour themes.** Note what this reverses: the seven-theme `ThemeManager` was
  deliberately deleted in favour of one fixed near-black dark palette, and `Theme.swift` is now the
  single source of colour on every target including `CadenceWidgets`. Re-introducing themes means
  restoring a selection mechanism *without* letting call sites go back to inventing their own
  colours — the no-hardcoded-colour rule is what makes a theme swap possible at all, so it has to
  survive. A light variant is the harder half: the whole UI has been tuned against a near-black
  ground, and several decisions (the `onColor*` family, hover washes, the marker-highlight pen)
  assume it.
- [T-16] **Redesign the logo.** Currently the app mark in the sidebar header and the app icon.
- [T-17] **Expand the target device list.** Directly reverses [T-08]; anything deleted as
  "unnecessary for the three targets" would need reinstating, so [T-08] should be done in a way that
  is easy to read back out of git history. Backlogged.
- [T-18] **Chinese localisation.** Backlogged. Nothing is localised today: user-facing strings are
  hardcoded English at the call site, and `DateFormatters` uses fixed formats. Two known hazards
  already documented in this repo — `Calendar.current` is not Gregorian everywhere (a `yyyy-MM-dd`
  storage key becomes `2569-…` under a Buddhist calendar), and weekday symbol arrays are indexed by
  weekday number rather than by `firstWeekday`. Both bit us before; both get worse with a second
  locale.
- [T-19] **Data safety, backup and controls.** `PrivacyDataResetService` (wipes every model),
  `StoreBackupManager`, and `DataIntegrityRepairService` exist; Settings → Data Safety is the
  surface. Worth reviewing as a whole: what a reset actually removes, whether backups are
  restorable, and whether the controls say plainly what they do. Note the standing rule that every
  new `@Model` must be added to the reset path or a wipe leaves orphans.
- [T-20] **Settings UI for macOS**, and possibly iPad/iOS after. iOS Settings was rebuilt in
  `775833d` — category list plus value rows — and macOS has not caught up; it is the older
  twelve-category shell. Bringing macOS to the same vocabulary would also settle which of the two is
  the reference.
- [T-21] **Verify the Apple Reminders integration end to end.** `RemindersManager` is macOS-only,
  separately authorised from Calendar, surfaced at Settings → Reminders. The app must keep working
  when access is denied — that path is the one most likely to be untested.
- [T-22] **Audit against Apple's App Review guidelines** before publishing. `docs/app-review-notes.md`
  and `docs/privacy.html` are the existing submission material and are the place to start. Likely
  areas: what the privacy manifest declares versus what is actually collected, Sign in with Apple
  being entitlement-gated and optional, the AI feature requiring a user-supplied key, and EventKit
  usage strings matching real behaviour.

## Done

Newest first. The commit message carries the reasoning; this is the index.

- [D-22] `545f429` Week could not show a week — seven columns at every real pane width.
- [D-21] `8a316c4` Month stopped changing mechanism on rotation; Lists eyebrow says its shape.
- [D-20] `71fbd1f` macOS sidebar: one nav block, colour bar instead of icons, Inbox restored.
- [D-19] `f2a1227` Today panel said "late" four times; now once.
- [D-18] `c9fb369` Notes has one live editable mode; code blocks stay editable.
- [D-17] `5a3cd63` Timeline shows 24 hours; three range spellings collapsed to one.
- [D-16] `cce1a4d` Sidebar pushed off-screen by a pane three levels down; capture bars deleted.
- [D-15] `8b5b0d8` iPad pane layouts: Calendar mode picker rendered as "…" at 632pt; day inspector
  took 54% of an 11" pane leaving 2 of 7 days; Goals/Habits/Focus split every pane exactly in half.
- [D-14] `e792fe8` Workspace drawer → lists picker; Planning deleted from iOS list detail; iOS and
  macOS list-detail page enums consolidated into `Shared/`.
- [D-13] `779bf68` Two-pane layout had no minimum width — an 11" iPad split 632pt into 312/320 and
  clipped its own capture field. Floor now derived from the panes.
- [D-12] `17f9f7a` iPad Today caught up with the phone; note templates stopped being silently
  discarded when the editor held focus.
- [D-11] `6277539` iOS task comparator was a partial order — list sequence depended on whatever row
  order SwiftData returned.
- [D-10] `717d330` Segmented picker hid two of its four options; widget printed "8d" for weeks.
- [D-09] `68c860e` Month became a grid over a live agenda; Week stopped opening at 6 AM.
- [D-08] `38af360` Thirteen bugs from a read-only audit, each confirmed before fixing.
- [D-07] `94f4540` Tab bar shell replaced the Home grid; iOS gained a real task-creation sheet.
- [D-06] `775833d` Settings became a category list with value rows; notes header stopped repeating
  its own tab name.
- [D-05] `f3b68ed` Six Focus play buttons that only changed the selection; goal detail's inert rows.
- [D-04] `ecaf80f` Calendar Board opened seven months in the past and persisted the bad anchor.
- [D-03] `5a14dda` Task inspector stopped showing five chips for fields it already let you edit.
- [D-02] `ec1912f` Task row: colour reserved for the exceptional; swipe actions that worked outside
  a `List`; a metadata strip that could not scroll.
- [D-01] `74f59ee` Seven keyboard toolbars, five of which never rendered — and the `/` slash menu
  they were hiding.

## Cancelled

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.

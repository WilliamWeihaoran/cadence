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

Started 2026-08-17, four agents on disjoint file sets.

**F — drag-to-create drop preview**
- [T-46] **The drop preview highlights an existing task, which is a lie.** `47328af` lights up the
  row you hover, but nothing happens *to* that task — it is only read for its placement. Show a
  ghost block opening **between** rows with the neighbours parting, not a selection on a row that
  is not the subject.

**G — note editor chrome and gestures** (`iOSMarkdownTextView`, `iOSMarkdownEditor`)
- [T-47] **Remove the "Done" bar under the iOS note editor.** A full-width bar whose only control
  drops focus and takes the caret away. The caret staying in the note is fine.
- [T-42] **Double-tap on plain text does nothing.** `renderedBlockTap` cancels the touch then
  returns early when the hit is not a code/table block, so a double tap neither places the caret
  nor selects a word.

**H — harden special-block rendering** (`iOSMarkdownStylingSupport`, block canvases, Services parsing)
- [T-48] **Harden the iOS markdown editor's rendering of special blocks.** Requested directly.
  `f1c55ea` made them draw at all and `a43b8fd` fixed two consequences; the layer has never had a
  systematic pass. Tables, fenced code, dividers, images, task embeds, quote bars, checkboxes.
- [T-41] **`iOSMarkdownStylingSupportTests.swift` never runs** — the whole file is inside
  `#if os(iOS)` and the test target builds macOS. Dead coverage that reads as real coverage.

**I — device-targeting cleanup**
- [T-08] **Device-targeting cleanup.** Scanned 2026-08-17, and **most of what looks like dead
  device code is not**: the 58pt sidebar **rail** below an 820pt window is reachable by a 2/3 Split
  View on the 11" Pro (~782–795pt) and by Stage Manager, so it stays. What is genuinely
  unreachable: `iPadTodayView.sidePanelMinWidth`'s `320` branch (needs a 949–1088pt window —
  Stage Manager only), three upper clamps that never bind (`inspectorMaxWidth` 430, two `540`s, a
  `760`), and `tvOS`/`watchOS`/`visionOS` names in one `#if` that compile to nothing. Week's
  1183pt inspector split is unreachable but is a *parameter* feeding a shared gate Month still
  uses — flag, don't cut. Test fixtures enumerate iPad mini and 13" widths; one assertion pins the
  rail at 744 (mini) rather than at a Split View width, which is what makes deleting the rail look
  safe. **Open question for the user:** the app target declares `TARGETED_DEVICE_FAMILY "1,2,7"`
  and ships `xros`/`xrsimulator` with an `XROS_DEPLOYMENT_TARGET`, while `CadenceWidgets` does
  not — so the app claims a visionOS family its own widget extension cannot ship into.

## Open — decided, not started

- [T-49] **Rework the iOS task creation sheet: fields belong in the page, not pinned to the floor.**
  Requested with a screenshot. Today `iOSCreateTaskSheet` is title + notes at the top, then ~700pt
  of dead space, then a horizontally-scrolling chip strip on the bottom edge — and the strip
  scrolls, so the tag chip is clipped off the right on a 390pt phone. The user wants list, do date,
  due date and the rest **in the middle of the page**. Mocks presented 2026-08-17; awaiting a
  choice. Note the sheet is shared with the tab bar `+`, the iPad corner `+` and now the
  drag-to-create seed path (`47328af`), so whatever shape is chosen has to read well both empty and
  pre-seeded — a seeded value must be visible without scrolling or the assumption is hidden again.


## Open — known, unscheduled

- [T-43] **Renaming a task embed after it is created.** `aca2787` made the embed take its title at
  creation, which covers the common case. There is still no way to rename one afterwards on iOS:
  macOS opens a text field over the card (`beginInlineTaskTitleEdit` → `onRenameEmbeddedMarkdownTask`)
  and iOS has no rename callback at all. A parity gap, and an instance of T-32.
- [T-44] **No way to move a task embed on iOS.** macOS has drag via `draggingTaskEmbedID`; iOS has
  nothing. Raised as part of T-26 but it is a missing feature rather than a defect, so it was not
  built on the way past.
- [T-45] **Sample data on the two simulators is dirty.** Three agents driving the same simulators
  left artefacts while verifying: a `[Sample Note] Today review` title line reading
  `**## [Sample Note] Today review`, stray `Buy bread` / `Buy milk` task embeds and tasks, a
  `( ) Call mum` fragment on the iPhone scratch note, and the `Dropped from tab bar plus` task from
  T-40. **All of it is DEBUG-only seeded data (`iOSSampleDataSupport`) on simulators — nothing in
  the repo, nothing on a real device, nothing synced.** Reset it by wiping the simulators' app data
  next time neither is in use; not worth doing while agents are running.

- [T-39] **Group headers should be drop targets too.** `47328af` made task *rows* accept a dropped
  `+`, which covers every grouping by construction but cannot reach an **empty** group — the one
  case where seeding a new task from the group is most useful. `CadenceTaskDropSupport`'s resolver
  already accepts group keys, so this is wiring `iOSTaskSectionHeader`'s 14 call sites, not new
  logic. Left out only because those files were held by another agent at the time.
- [T-32] **Feature-consistency scan across platforms.** Added 2026-08-17 at the user's direction;
  **do not run it yet.** The goal state is that no platform has a feature another lacks — macOS,
  iPadOS and iOS offer the same set, differing only in how it is laid out. This directly reverses
  the standing "iOS is not guaranteed parity with macOS by design" note in `CLAUDE.md`, which will
  need rewriting when this lands. Known gaps to fold in when it starts: T-31 (daily/weekly date
  picker missing on iPad), and the `EstimatePickerControl` / macOS-roller split. Two things to
  settle before doing the work rather than during it: whether "same feature" means the same
  *capability* or the same *control*, and what happens to macOS-only surfaces that have no phone
  shape at all (the MCP bridge, global hot keys, the AppKit markdown editor).

- [T-11] **`iOSSegmentedChoice` truncates silently** past four options for labels over ~9 chars —
  fixed in the control, but worth re-checking call sites as labels change.
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

- [D-34] `68d78ec` Month's agenda opened past the end of its own content; Board's counts strip and
  Month Day's missing add control (T-34, T-35, T-36).
- [D-33] `aca2787` A task embed named itself "Untitled Task" and then argued with the note (T-26);
  plus the macOS twin of the frontmatter/divider bug.

- [D-32] `a43b8fd` A checkbox you typed was never a checkbox, and tagged notes grew two
  rules (T-37, T-38).

- [D-31] `47328af` Drag the + onto a task and the new one lands where that one lives (T-05).

- [D-30] `4c63084` The MCP surface called eight kept weeks "8 day streak" (T-12).

- [D-29] `a4bdaa5` Nothing that renders a block rendered on iOS — tables, code blocks and
  dividers were all invisible (T-33).

- [D-28] `2929867` Daily and Weekly notes could only ever be today's — the header title became the
  date and the control that changes it (T-31); tabs renamed Daily/Weekly; template menu moved into
  the editor's format row.
- [D-27] `6609bf7` A past-due line measured its colour and its words against different days —
  `relativeDate` ignored the injected `todayKey` and read the system clock.
- [D-26] `42de745` Board has no inspector, and no surface repeats the day it is showing (T-28).
- [D-25] `bea12c7` iPad Today: Focus/Mac picker deleted (T-06), composer stays where you tapped
  (T-24), free slots derived rather than hardcoded (T-25), sort row merged into the header (T-30).
- [D-24] `8d1bbab` The iPad sidebar shows its lists, and folds out of the way (T-07, T-27).
- [D-23] `40e2381` The Notes header's second row held one button; it holds nothing now (T-29).

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

# Cadence — task list

The running record of work: open, in progress, done, cancelled. Started 2026-08-16.

**Format.** One line per item: `- [id] Title — note`. Ids are stable and never reused, so a
cancelled or done item can still be referenced later. Done items keep their commit sha, because the
commit message is where the *reasoning* lives; this file is only the index.

**Target devices** (set 2026-08-16). Build and verify for these three only; anything that exists
solely to serve other hardware is dead weight and should be removed rather than maintained:

| Device | Points | Notes |
|---|---|---|
| iPhone 15 (base) | 393 × 852 | compact width, the only phone shape that matters |
| iPad Pro 11" | 834 × 1210 portrait · 1210 × 834 landscape | pane = window − 188pt sidebar → **646** portrait, **1022** landscape |
| MacBook Pro 14" | 1512 × 982 | the macOS surface |

The 11" Pro landscape pane of 1022pt is *exactly* the three-pane floor
(`CadenceTodayLayoutSupport.threePaneMinimumWidth`). Worth remembering before anyone tunes that
number: it is the difference between the three-pane layout existing on the target hardware or not.

---

## In progress

- [T-01] **Corner add button + capture-bar removal** — every inline "Add a task…" bar comes out
  app-wide; iPad gets one blue circular button bottom-right, iPhone keeps the tab bar `+`. Also in
  this pass: iPad sidebar clipped in portrait ("KSPACE"/"GRESS"), and the Inbox Overview pane
  deleted.
- [T-02] **Timeline shows all 24 hours** — Today's timeline was hardcoded 06:00–22:59. Must open
  near the current hour, without persisting a measured scroll value (see `ecaf80f`).
- [T-03] **Delete the notes editor mode picker** — Live/Edit/Preview goes on iOS, iPadOS **and**
  macOS; live editable preview becomes the only mode. A stored `edit`/`preview` must resolve to
  live.
- [T-09] **Sidebar restructure, all platforms** — Today/Tasks/Calendar/Notes pinned top; lists
  scrolling in the middle; Goals/Habits/Focus/Settings bottom. List rows lose their icon and gain a
  2pt coloured leading bar in the list's own `colorHex` — a bar rather than a dot, so names stay
  aligned and the column scans. Counts only when non-zero; red on Today's overdue alone. macOS is
  building now; **iPad/iOS follows and must read the same shared code, not a second copy**.
- [T-10] **Month: agenda/day toggle** — the two ways of seeing a day were mutually exclusive *by
  width*, so rotating an 11" Pro silently swapped the mechanism (agenda at 646pt, inspector at
  1022pt). Both are now available in both orientations, chosen by a toggle that persists. The
  toggle picks the *content*; pane width picks the *placement* — beside the grid when there is room,
  below it when there is not, because the inspector's 340pt floor at 646pt would leave ~43pt per
  weekday column.
- [T-04] **macOS Today panel colour pass ("option A")** — red survives only on the date that is
  actually late. Background washes, the "List" chip, the red section heading and red group counts
  all go.

## Open — decided, not started

- [T-05] **Drag-to-create from the add button** — drag the iPad corner `+` (and the iPhone tab-bar
  `+`) onto a section, list or date; the created task inherits that destination's attributes.
  `CadenceTaskDisplayGroup` already carries a `dropKey`, which is the hook.
- [T-06] **Remove the Focus/Mac layout picker** — Today is always two panes. Note this deletes a
  layout the 11" Pro *can* reach in landscape (1022pt); decided anyway.
- [T-07] **iPad sidebar shows lists inline**, like macOS — no floating panel. Supersedes the
  lists-drawer work in `e792fe8`.
- [T-08] **Device-targeting cleanup** — remove handling that exists only for hardware outside the
  three targets above.

## Open — needs a decision

_Nothing open._

## Open — known, unscheduled

- [T-23] **Week starves its own grid just above the 681pt split.** At an 844pt pane the day
  inspector takes 340, leaving 503 for a grid whose columns have a 112pt minimum — so Week shows
  about four and a half of its seven days behind a horizontal scroller. Same starvation shape
  `8b5b0d8` fixed *below* 681pt; it survives just above it. Found while building the Month toggle,
  left alone because Week was out of that scope.
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

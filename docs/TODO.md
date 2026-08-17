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

**AJ — short timeline blocks are almost entirely un-tappable** ([T-101])

**AK — Cmd+N dead on Calendar Board columns; two dead calendar bindings** ([T-102])

## Open — decided, not started

- [T-73] **Audit iPhone/iPad divergence and share what should be shared.** Standing rule added to
  `AGENTS.md` and `CLAUDE.md` 2026-08-17: the two differ in *layout* only, never in how a row, chip,
  header or picker looks or behaves. This item is the sweep to make the code match that — find the
  places where a phone view and an iPad view are near-copies and collapse them into one view
  parameterised by size class. Distinct from [T-32], which is macOS↔iOS *feature* parity; this is
  iPhone↔iPad *implementation* sharing. The Notes starting point is closed (`D-44`, one view for all
  three hosts) and so is the page-header family (`D-62`). What is left of the original list —
  `iPadTodayView` vs the compact Today, and the compact/regular branches inside the task row — is
  in flight now.


- [T-105] **`drawBackground` still blocks Swift 6, and the block is structural.** `D-73` resolved
  three of the editor's four errors; the fourth cannot be annotated away. Swift 6 region isolation
  rejects capturing task-isolated, non-`Sendable` `self` in a main-actor closure, and the decoration
  pass reads *and writes* `CadenceTextView`'s hit-rect and hover caches — `CadenceTextView` being
  main-actor isolated by AppKit, since `NSTextView` is. The real fix is moving the decoration pass
  onto `CadenceTextView`, a refactor of a documented risk hotspot that needs visual verification.
  Note also that "four errors" was an undercount: xcodebuild aborts after the first failing batch,
  so a whole-module probe is the only honest count, and it shows blockers outside that file too.

- [T-106] **`CadenceEmptyStateCopy` is main-actor isolated**, missed by `f94361a`'s `nonisolated`
  pass. Reading it from a deliberately-`nonisolated` metrics file emits isolation warnings, which is
  why `D-72` had to keep `emptyTitle`/`emptySubtitle` in a private extension rather than on the enum
  where they belong. One-word fix plus the cleanup it unblocks.

- [T-104] **The dead wiring the T-97 audit turned up.** None of these misbehaves; each is a control
  or parameter that reads as live and is not, i.e. the raw material for the next real bug. Grouped
  because they are one afternoon, not one task:
  - The iOS markdown editor's command-injection path (`iOSMarkdownEditor`) — its only construction
    site omits `pendingCommand`, so it is permanently `.constant(nil)`; formatting runs through
    `applyCommandToDraft` instead.
  - `iOSIconButton` has three parameters no call site passes (`foreground`, `isEnabled`,
    `showsPlate`). `foreground`'s own doc comment claims it fixed a calendar tint bug — there is no
    calendar caller at all, so it fixed nothing.
  - `iOSSegmentedPill.isEnabled` is never passed `false`; the three-pane "Mac" layout it was written
    for is deleted.
  - `CadenceTextView.onCreateMarkdownTag` is assigned and never invoked — the only one of that
    type's fourteen closure properties in that state.
  - Three identical write-only `@State var isEditorFocused` (`NoteEditorPane`, `NotePanel`,
    `ListNotesSupportViews`): written on every focus change, read nowhere, so each focus gain and
    loss invalidates the pane for nothing.
  - Four `set { }` blocks nothing can call, and a list of never-called helpers and three
    never-instantiated `View` structs. Full inventory in the audit.

## Open — known, unscheduled

- [T-95] **Part 3 only: `ListNotesView` shows out-of-list embeds as missing.** Parts 1 and 2 shipped in `D-67`.
  `ListNotesView` passes list-scoped `relatedTasks` to its editor, so an embed of a task from
  *another* list falls through to `.missing` and shows the cached title with missing-card styling —
  i.e. a live task rendered as if it were deleted. Fixing it means either widening the `[[task:`
  suggestion scope or splitting suggestion tasks from embed tasks in `MarkdownEditorView`, and those
  are different products: the first makes any task embeddable from any list, the second keeps
  suggestions list-scoped while rendering whatever is already embedded. **Needs a decision before
  the work, not during it.**

  Two more readers left deliberately, both cheap to fix and both wrong to fix here:
  `iOSMarkdownPreview`'s inline runs (its *cards* are already correct — the one-line remedy is a
  `resolving(...)` call where `markdown:` enters the view, at `iOSFocusView`), and the reference
  picker's note *filter*, which searches raw content so a note is not findable under a renamed
  task's new name.

  Also unconverted on purpose: `iOSMarkdownEditingSurface`'s `[[` autocomplete filters notes by
  content, but that is completion rather than user-facing search, and resolving there costs a pass
  per note per keystroke inside the editor.

- [T-89] **Drag-and-drop cannot be driven from the simulator harness.** Neither `touch_path` nor
  `swipe` lifts a `UIDragInteraction`, so no drop ever fires — verified against the row target from
  `47328af`, which fails identically, so it predates and is independent of any one change. Every
  drag-to-create claim in this repo is therefore unit-tested rather than seen. Worse, an abandoned
  drag attempt leaves the tab bar swallowing taps until relaunch, which can silently poison a later
  verification in the same session. Until this is solved, treat "drag works" as inference.

- [T-86] **Agents building into the shared DerivedData can crash a running Mac app.** On 2026-08-17
  the user hit "Cadence quit unexpectedly" — `EXC_BREAKPOINT` on the main thread, five seconds after
  launch. **Not app code:** the whole backtrace is `dyld` → `libSystem_initializer` →
  `_libsecinit_appsandbox`, i.e. App Sandbox setup failing *before `main()` runs*, and the app
  bundle had vanished from `Build/Products/Debug/` by the time it was inspected — a concurrent agent
  clean build wiped it under the running process. A fresh build into a private `derivedDataPath`
  launched and stayed up. Two agents had already reported `build.db is locked` from the same
  contention. **Mitigation:** every agent brief should require a private `-derivedDataPath`, which
  most already do ad hoc; worth making standing in `AGENTS.md`. Nothing to fix in the app.

  **Mitigation shipped 2026-08-18** — the rule is standing in `AGENTS.md`. Left open because the
  underlying contention still exists and this keeps producing *new* disguises: the same day it
  reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt `SourcePackages`,
  which read as a broken package checkout and briefly made a correct agent report look wrong. The
  standing rule now says an unexplained build failure is a private-path re-run before it is a
  finding. Close this only if the contention itself is removed.

- [T-55] **Three things need a real phone, not a simulator** — written up as a checklist in
  `docs/device-checks.md` (keyboard dismissal, double-tap, and drag-to-create per [T-89]).
  Original note:
  1. **Can a phone still dismiss the keyboard in the Notes tab?** The Done bar was the dedicated
     affordance and it is gone. `keyboardDismissMode = .interactive` remains, so dragging the note
     down should carry the keyboard off — Apple Notes behaves this way — but it was never seen to
     happen: both simulators suppress the software keyboard while the Mac's hardware keyboard is
     attached, and that toggle lives in Simulator.app, which is off limits. The Notes tab is the
     exposed case because it hides its navigation bar; every sheet-hosted editor has its own
     Done/Cancel above the keyboard. If it sticks, the answer is a nav-bar Done or tap-outside, not
     the bar returning.
  2. **Double tap on plain text, and on a code block or table.** The `shouldBegin` gate makes the
     prose case true by construction, but neither case was observed: the simulator tooling has no
     double-tap action and two scripted taps fall outside UIKit's ~350ms window.
- [T-32] **Feature-consistency scan across platforms.** Added 2026-08-17 at the user's direction;
  **do not run it yet.** The goal state is that no platform has a feature another lacks — macOS,
  iPadOS and iOS offer the same set, differing only in how it is laid out. This directly reverses
  the standing "iOS is not guaranteed parity with macOS by design" note in `CLAUDE.md`, which will
  need rewriting when this lands. Known gaps to fold in when it starts: T-31 (daily/weekly date
  picker missing on iPad), and the `EstimatePickerControl` / macOS-roller split. Two things to
  settle before doing the work rather than during it: whether "same feature" means the same
  *capability* or the same *control*, and what happens to macOS-only surfaces that have no phone
  shape at all (the MCP bridge, global hot keys, the AppKit markdown editor).

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

- [D-73] `234a794` Three of the four Swift 6 errors go; the fourth is a refactor (T-96).

- [D-72] `7091a6a` All Tasks and Inbox were one page rendered through two containers (T-98, T-99).

- [D-71] `c9d2d78`+`7091a6a` **A commit broke HEAD for iOS.** `git add <paths>` stages *on top of*
  whatever is already in the index, so another agent's staged deletion of two view files rode into
  an unrelated commit while their callers were still uncommitted. iOS did not build between the two
  commits. Third occurrence of this sweep; now a standing rule in `AGENTS.md` (`git commit --only`).
  Worth recording that verification could not have caught it: isolating a change with
  `git archive HEAD` reproduces HEAD's tree, not its index.

- [D-70] `d8965a8` Cmd+Return deleted one task and completed another (T-103, from the T-97 audit).

- [D-69] The audit for controls that look wired and do nothing (T-97). No code; it produced T-101,
  T-102, T-103 and T-104, and a *cleared* list — deep links, notification reconcile paths, all 36
  `@AppStorage` keys, every documented keyboard chord — so the next agent does not re-chase them.

- [D-68] `f35ace2` A sheet's width is its own, not the screen's (T-100).

- [D-67] `c9d2d78` Note rows named tasks by whatever they were called last time (T-95 parts 1, 2).

- [D-66] `9b08364` The phone was not told how much of its day was already timed (T-73 remainder).

- [D-65] `646ff9e` The task is the record; the embedded title is a cache (T-92).

- [D-64] `dfae0d3` `isCustomDoDate` outlived its only caller (T-93).

- [D-63] `62dc384` The MCP server target compiled a file it never used (T-94).

- [D-62] `c5a4ea5` Six page headers had drifted into six title sizes (T-73 group B remainder).

- [D-61] `f94361a` 215 value types were main-actor isolated, including ones widgets use (T-87).

- [D-60] `b554824` Month's date picker opened on a layout constant (T-90, T-91; T-11 closed as
  already fixed).

- [D-59] `49a273e` macOS rewrites an embed's reference when its inspector closes (T-88).

- [D-58] `3097749` The creation sheet is a grid of value tiles, measured to fit (T-85).

- [D-57] `69bf02d` A group header takes a dropped + only when it can say where it lands (T-39).

- [D-56] `fcb2168` Renaming a task never updated the note that embeds it (T-84).

- [D-55] `7d39af2` 1195 test warnings were hiding five real ones (T-82).

- [D-54] `7f21fab` One board card, one timeline block, and two more ungated scroll reports (T-73
  group B, T-80).
- [D-53] `661a602` A task row is one row, and the Inbox stops naming itself (T-78, T-77).
- [D-52] `2a30319` Three near-copies collapse into the components they were copies of (T-73 group B).
- [D-51] `457ca47` The estimate picker was still three, and CLAUDE.md still said two — two false
  claims in `3ecfeaf` caught by a read-only verifier.

- [D-50] `0e8db6c` The creation sheet puts its fields in the page, not on the floor (T-49). Height
  risk only partly closed — the Tags row sits ~53pt below the fold with a keyboard up; awaiting the
  user's call on whether to retreat further.
- [D-49] `11883bb` One date-jump title, and the scroll gate stops being copied (T-59, T-70).
- [D-48] `3ecfeaf` One estimate picker, and macOS loses its status list too (T-75, T-76).

- [D-47] `29735a6` A task-embed card was tappable only along its leading 8 points (T-57, T-43).
- [D-46] `b8b329e` iPhone and iPad stop disagreeing about seven things (T-73 visible half).
- [D-45] `0f7b756` The task row stops pointing at itself and starts being editable (T-68, T-74).
- [D-44] `a240a74` Notes is one view for all three hosts (T-73 largest, T-56, T-58, T-54).

- [D-43] `ecfc9a3` Month scrolls, every surface names one date, and nothing steps by button
  (T-61…T-65, T-69, T-71, T-72).

- [D-42] `8f2fd9f` Settings and Focus share one row of glyphs at the sidebar's foot (T-66).
- [D-41] `ae3ac48` Checklist circles sat on the baseline, which reads as floating (T-67).

- [D-40] `cf785a8` The calendar scrolls instead of stepping, and its headers stay put (T-50).

- [D-39] `7d93f7f` Drop visionOS from the build settings (T-53).

- [D-38] `4f00e55` Three line-numbering conventions were feeding each other's indexes (T-48, T-41).

- [D-37] `64218d1` The note editor loses two bars and stops eating double taps (T-47, T-51, T-42).

- [D-36] `88c05d1` Today's two panes asked for one point more than the pane had (T-52, T-08).

- [D-35] `a911d5a` The drop preview stops highlighting a task nothing happens to (T-46).

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

- [X-03] **[T-83] Remove the nav arrows from Month and Board** — filed and decided on a false
  premise, then found already delivered. `cf785a8` scoped the removal to the timed grids; `ecfc9a3`
  superseded it two hours later and removed the cluster from **all four** surfaces, saying so in its
  own message. My summary to the user reported the earlier scoping as the shipped state, so the user
  was asked to decide something already done. Nothing was changed. The lesson is cheap and worth
  keeping: **report the shipped state from the code, not from the decision you remember briefing.**

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.

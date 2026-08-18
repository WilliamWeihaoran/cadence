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

## Open — decided, not started

- [T-116] **Exercise every drag-and-drop path in Cadence, now that drags can be driven.** Sidebar
  reorder, task-to-timeline, kanban and Calendar Board columns, all-day event chips, drag-to-create,
  the tab-bar `+` → task-row path from `47328af`. Not one of these has ever been *observed* working;
  every claim rests on tracing that a producer and a consumer both exist. Two hit-target bugs this
  session (an 8pt-wide embed card, a 6pt timeline block interior) were invisible to exactly that
  kind of reasoning. iOS first, using the `AGENTS.md` recipe.

- [T-117] **A project-file lock is a new disguise in the T-86 family — now confirmed twice.** Builds
  deadlock in `NSFileCoordinator` reading `Cadence.xcodeproj`, 20+ minutes at 0% CPU, with an empty
  derivedDataPath. A `sample` of a stalled process caught it in `_blockOnAccessClaim` on the project
  file, with a concurrent agent's `xcodebuild` holding it and the user's Xcode — open six days —
  also claiming it. **It produces no diagnostic at all**: the run simply sits at the "Command line
  invocation" line, which reads as a broken checkout. Distinct from DerivedData contention.
  Mitigations: quit Xcode when a batch of agents is running, and treat total silence as this rather
  than as a failure to be debugged.
  Related but *not* universal: one agent found a fresh private DerivedData could not start because
  package resolution is sandbox-blocked, and worked around it with
  `-clonedSourcePackagesDirPath` + `-disableAutomaticPackageResolution`. Recorded as situational
  rather than as a rule — my own fresh-DD runs this session resolved packages fine, so do not add
  those flags by default.

- [T-115] **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

- [T-112] **A fourth editor sheet, and the 16-vs-14 spacing split.** `D-84` shared the markdown
  well's height, gutter, title size and form breakpoints across three editor sheets, and stopped
  short of section spacing and card padding: the inspector says 14, the two calendar sheets say 16,
  and so does `iOSTrackingEditorShell` (`Cadence/iOS/iOSTrackingEditorComponents.swift`), a fourth
  editor sheet that was outside that change's scope. Three-to-one, so pulling two to 14 would have
  created a new split. Needs one pass covering all four. While there: the inspector's own notes well
  still draws its box a fourth way (`cadenceCard` at `radiusCard`) in
  `Cadence/iOS/iOSTaskDetailSheetSections.swift` — it shares the *height* now, not the border.

- [T-113] **EventKit is unauthorized on both simulators**, so the calendar event edit sheet cannot be
  reached and was the one surface `D-84` could not screenshot. Any future calendar work has the same
  blind spot. Granting Cadence calendar access on the iPhone 17e simulator and creating one event
  would clear it — a shared-device change, so worth doing deliberately rather than mid-task.

- [T-73] **Audit iPhone/iPad divergence and share what should be shared.** Standing rule added to
  `AGENTS.md` and `CLAUDE.md` 2026-08-17: the two differ in *layout* only, never in how a row, chip,
  header or picker looks or behaves. This item is the sweep to make the code match that — find the
  places where a phone view and an iPad view are near-copies and collapse them into one view
  parameterised by size class. Distinct from [T-32], which is macOS↔iOS *feature* parity; this is
  iPhone↔iPad *implementation* sharing. The Notes starting point is closed (`D-44`, one view for all
  three hosts) and so is the page-header family (`D-62`). What is left of the original list —
  `iPadTodayView` vs the compact Today, and the compact/regular branches inside the task row — is
  in flight now.


- [T-105] **The macOS Swift 6 migration has one blocker left — and it is no longer blocked.**
  `D-89` established that macOS screenshot verification works, so the visual questions that stopped
  `D-77` landing the refactor (a multi-line selection tinting an embed card, the insertion point
  under a card, `dirtyRect`-derived glyph ranges) can now actually be looked at. Do the CGEvent
  caveat honestly: screenshots are safe, but driving the pointer is not while the user is at the
  machine., and it is a decision rather than an
  annotation. `D-77` established the honest count with a whole-module probe (a batched
  build stops at the first failing batch; a type error stops the compiler before SIL diagnostics
  run, so both undercount):

  1. **`MarkdownEditorInteractionSupport.swift` — `CadenceLayoutManager.drawBackground`.** The
     refactor exists and compiles: six of the eight decoration passes go `nonisolated` untouched
     **once `Theme` is `nonisolated`** (every `MarkdownStylist` colour is `= Theme.ns*`, and a
     nonisolated constant cannot initialise from a main-actor one — note `Theme.swift` also compiles
     into `CadenceWidgets`, so that wants its own pass); the other two genuinely touch
     `CadenceTextView` state and must move onto the view. It is unlanded because AppKit offers no
     main-actor hook between the background and glyph passes, so moving them changes z-order, and
     the three residual questions are visual only — a multi-line selection would no longer tint an
     embed card, the insertion point would fall under it, and the glyph range must be derived from
     `dirtyRect` rather than received. **Blocked on [T-14]**, not on effort.
     *Rejected on purpose, because it will tempt the next person:* moving the hit-rect and hover
     caches into a nonisolated holder compiles, changes no z-order, and is not spelled
     `nonisolated(unsafe)` — but it removes the diagnostic without removing the hazard.
  2. ~~`HabitNotificationReconcileSupport`~~ — fixed in `D-80`. The context never actually crossed
     actors; the signature just failed to say so.

  With the editor override alone stubbed, the whole-module Swift 6 build is now clean. **iOS has 3 more errors**, all in
  `Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift` — the same `NSLayoutManager` shape, and the
  *easy* half: plain `nonisolated` annotations of the kind `D-73` already applied on macOS. That is
  the cheapest remaining step and is [T-109].

- [T-109] **Annotate the iOS layout-manager overrides `nonisolated`.** Three Swift 6 errors in
  `iOSMarkdownBlockCanvasRendering.swift` (`init()`, `init(coder:)`, `drawGlyphs` on
  `iOSMarkdownBlockCanvasLayoutManager`), identical to what `D-73` fixed on macOS. Unlike [T-105]
  these need no refactor and no visual check.

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

- [D-90] `8772628` Tests stranded a UserDefaults plist on every run — 4,629 of them (T-114).
  Bounded at 11 files total, verified by a third independent run showing delta 0.

- [D-89] **T-89 and T-14 were both false, and both had been shaping decisions for days.**
  *Drag-and-drop can be driven on the iOS simulator.* `UIDragInteraction`'s lift recognizer needs
  the touch stationary ~350ms before any movement — measured, `itemsForBeginning` fires at 326–349ms
  — so a `swipe`, or any path that moves immediately, never lifts. 300ms fails too. The working
  recipe is in `AGENTS.md`, proven end-to-end on real Cadence: a Calendar Board card dragged between
  day columns, with the SwiftData change surviving a relaunch.
  *The "tab bar swallows taps" folklore is also wrong.* A touch beginning within 4pt of an edge is
  synthesised as the OS home gesture; an incomplete one leaves the window ~35pt short, so
  bottom-anchored controls move up and taps aimed from an old screenshot miss. Nothing is swallowed.
  Almost certainly caused by aiming with screenshot **pixels** where the API takes **points**.
  *macOS UI can be screenshot- and event-verified.* All four preflights return true; I confirmed
  this independently. T-14's symptom is real but misdiagnosed — `count of windows` on an app with no
  window returns 0 and indexing errors `-1719`, which reads like a permission denial.
  **One real constraint survives:** posting CGEvents drives the user's *physical* cursor, so a
  scripted macOS drag fights them for it. Screenshots and reads are safe any time.

- [D-88] **Every "verified by inference" caveat in this repo's history predates the recipe above.**
  Recorded separately because it is the expensive part: two limitations nobody had retested were
  used to justify not verifying whole features, and one of them ([T-14]) also blocked [T-105].

- [D-87] `2ff8d39` The calendar's day header reserved less space than its contents need (T-73
  calendar slice). 33 branches → 5 reads; one of them was arithmetic that was simply wrong.

- [D-86] `813fe0d` The iOS layout manager's overrides now agree with their superclass (T-109).

- [D-85] **T-13 closed as won't-fix, and its headline figure was wrong.** `xcodebuild` creates one
  directory per launched test process inside the app's sandbox container, hands it to that process
  as `LLVM_PROFILE_FILE`, then deletes the profile file and not the directory. Caught in the act:
  the PID in the directory name resolved to a live `xcodebuild test` 5 times out of 5, and the test
  host's captured environment names that exact directory. The container is the only place a
  sandboxed test host may write, which is why this happens here and not on the simulators.
  **The "97 MB" was wrong** — empty directories occupy no data blocks on APFS. All 2,109 of them
  cost ~0 bytes; the 6 MB measured is 5 stray `.profraw` files. The real cost is directory entries.
  Ruled out with evidence: SwiftData (the UI-test runner container shows the same pattern and links
  no Cadence code), CloudKit (tests run `cloudKitDatabase: .none` and still leak; the simulators do
  run CloudKit and leak nothing), the sandbox machinery (907 containers on the machine, only the
  three dev-built Cadence ones do this), and app code. Nothing in the repo can prevent it short of
  dropping the app test host.

- [D-84] `2b0b1f7` Four sheets drew one markdown well four different ways (T-111). One height, 340,
  from the two surfaces that never ramped. Unifying the box surfaced a real rendering bug: a
  `.stroke` on a clipped path had half its border cut away, at 0.68 alpha, in two sheets.

- [D-83] `2a15f27` Section headers respond to the first click again (T-107). Decided by the user:
  two clicks should be two toggles. The gesture cost ~352ms on *every* click to smooth over an
  accidental double-click that nobody performs on purpose.

- [D-82] `11d8891` A note in one list drew another list's task as if it were deleted (T-95 part 3).
  User chose the wider reading: any task is embeddable from anywhere. One array fed three things, so
  it also fixed reference resolution and click-to-open.

- [D-81] `0b2f976` The MCP scheme had two warnings sitting under a baseline that never looked at it
  (T-110). The baseline now covers all three schemes, verified rather than assumed.

- [D-80] `92ad0af` The notification reconcile carried a ModelContext across actors (T-105 item 2).
  With it fixed, the editor override is the only remaining macOS Swift 6 blocker.

- [D-79] `b346fe3` Two more types the nonisolated pass missed, and the workaround one forced (T-106).

- [D-78] `fd669d8` Wiring that read as live and was not — iOS (T-104).

- [D-77] `a679f94` The editor's Swift 6 blocker is one error, and the fix is not landable yet
  (T-105). The refactor was **built and proven to compile**; it is not landed because three residual
  questions are visual only and macOS UI cannot be checked from the agent shell. See [T-108].

- [D-76] `fcf0a6e` 173 lines that read as wiring and were not — macOS (T-104).

- [D-75] `1dc7d33` Cmd+N did nothing over a Calendar Board column, and a double-click mystery
  (T-102). The third item was suspected dead and turned out to be neither hypothesis — measured, not
  reasoned about.

- [D-74] `7c6e259` A short timeline block was 6pt of tap target and 16pt of resize strip (T-101).
  Also fixed an unconditional EventKit write on a plain click, which raised an unprompted "Change
  recurring event?" dialog.

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

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

_Nothing in flight._

## Where findings come from

This file is authoritative. Two other documents hold *findings*, not tracked work:

- [`refactor-phases-4-6.md`](refactor-phases-4-6.md) — 153 findings from a read-only audit at
  `249b475`, **two weeks stale**. A good hunting ground; verify each finding against current code
  before filing it, because several have been overtaken.
- [`TODO_DONE.md`](TODO_DONE.md) — everything shipped, with SHAs. **Search it before filing**;
  tickets have been re-reported here more than once.

## Open — decided, not started



- [T-462] *(narrowed 2026-08-30, measured by replaying all 210 revisions of the file: the gap is **200, not 284**. All 200 are recoverable verbatim, but that is ~33k tokens onto a file whose purpose is to be cheap to search — and **87.5% were removed by bookkeeping commits that changed no Swift**, so each entry's SHA would need its own bisect: 200 investigations for a file half of which would be blank. **Do not backfill.** The cheap half is done — 32 entries reading `(title not recovered)` were unsearchable and all 32 titles were recovered from the file's own revisions (the earlier reconstruction had searched commit *messages*), and the header count, which had never been true at any revision, now reads the real 177. Residue: [[T-501]].)* **`docs/TODO_DONE.md` had no `T-4xx` entry at all until `ca06ad1`+1.** Eighty-five tickets
  closed in this session were removed from Open and never archived, and the same gap runs back to
  T-01 — **284 in total**. Today's 85 are now reconstructed from git history; the older 199 are not.
  Either backfill them the same way or state that the archive begins at this session and stop
  implying otherwise.





- [T-447] *(narrowed 2026-08-30: both landings reviewed. T-281 is a faithful but visually inert extraction — the two headers were already byte-identical before it. T-283's renames are correct and complete. Defects found and filed separately as [[T-492]] and [[T-493]]. Predicate two is effectively answered off-device already: the commit outcome is covered in `CadenceEventKitPlatformParityTests` and its position by `theEventSheetKeepsItsCommitNoticeInsideTheHeader` — only the pixel is left. Predicate one is narrowed by `nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader`: **nothing in `Cadence/` writes that environment key**, so only SwiftUI's own re-derivation inside NavigationStack -> HStack -> .frame remains device-only. That residue belongs with T-55 / T-280.)* **Nothing rendered the two iOS surfaces [[T-281]] and [[T-283]] changed.** Both landed on
  source-scan evidence plus four green scheme builds (`Cadence` macOS, `CadenceWidgets`,
  `CadenceMCPServer`, `Cadence` for `generic/platform=iOS Simulator`) — which is all
  `CadenceTests` can offer, since `Cadence/iOS/` is inside `#if os(iOS)` and the test target builds
  for macOS. No simulator ran: both booted devices were held by live agents, and
  `scripts/simulator-claim.sh` correctly refuses to reclaim one.
  Two predicates a device answers and a scan cannot. **One:** `iOSNoteEditorSheetHeader` now reads
  `@Environment(\.horizontalSizeClass)` itself instead of taking the flag from its sheet. That is
  the same trait either way *in theory* — a `.frame(width: 320)` does not change a scene trait — so
  the regular-width rail on both note sheets should still draw the 24pt title, the 20/20 padding and
  the full-height rail. If the trait does not propagate into that rail the title drops to 22pt and
  the padding to 18/14, which is visible and which no scan can see. **Two:** the event sheet's
  commit-failure notice still appears under the title, inside the header block, when a note saves
  but its Apple Calendar mirror does not.
  Cheap: one iPad-width run of each note sheet, one iPhone-width run of Today and Inbox.




- [T-452] *(narrowed 2026-08-30: tier confirmed self-consistent — both tiers 0.08em, and 0.08 x 10 reproduces the standard tier's 0.8 exactly, so the 19 correct sites did not move. Not wrong by the design system's own rules; no value changed. Separately, this ticket's claim that the derivation was pinned was **false** — `theCompactKerningIsDerivedRatherThanASecondLiteral` was cited at `SectionEyebrowLabel.swift:80` and had never existed. It exists now and kills a flattening mutation the whole pre-existing T-284 suite passes. Remaining ask: one screenshot pass over the six tightened 9pt labels and the two that gained tracking.)* **T-284's 9pt tier is pinned by value and by source, and has still never been looked at.**
  The ticket's remaining ask was "one screenshot pass over those 8 sites", and the subagent runbook
  forbids launching or building the app for inspection — so the *judgement* is now recorded
  (letterspacing is optical, so the compact tier takes the same 0.08em the 19 correct 10pt sites
  take; the plurality of 0.6/0.54 was two independent guesses, not a decision) and the derivation is
  pinned against being re-flattened into two literals, but nobody has seen the six tightened labels
  or the two that gained tracking rendered. One pass by whoever can run the app closes it.











- [T-352] **DECIDE: should the root destination persist? A comment already says it does.** From the
  same audit; **premise verified** — `macOSRootView` holds the selection in `@State` with **zero**
  `SceneStorage` or `AppStorage`, and no restore path exists anywhere. iPad regular width is the
  same, while the *compact* tab and task subsection are persisted, so one platform has two
  different answers depending on width.
  **The defect worth acting on is not the missing feature — it is the comment.**
  `macOSRootSupportViews.swift` documents a parameter as non-nil for "an `.inbox` selection
  **restored at launch**", describing a mechanism that does not exist. That is the **third** such
  comment found this week: [[T-333]] has one claiming macOS reads a shared sorter it does not, and
  [[T-337]] carries one justifying an unseeded button by a drop path that no longer exists. A
  comment asserting a mechanism is worse than a missing mechanism, because it stops the next reader
  checking.
  So: decide the contract, and **fix the comment either way**. If root navigation should persist,
  start with stable destinations only — Today, Inbox, All Tasks, Habits, Goals, Calendar. **Do not
  persist area or project ids until [[T-345]] lands**, or launch will restore a selection pointing
  at a deleted list, which is that ticket's bug made permanent.



- [T-237] **`git archive HEAD` over the whole tree runs at ~5 KB/s here; root cause unconfirmed.**
  Measured 2026-08-22 and worked around rather than fixed — `AGENTS.md` now prescribes
  `rsync` + `git show HEAD:<path>` restore instead. The workaround has a real ongoing cost: the
  restore step is manual, and an agent that skips it verifies another agent's in-flight code while
  believing it tested HEAD. That is worth removing, not just documenting.
  Evidence: one file (`git archive --format=tar HEAD -- AGENTS.md`) is instant; the whole tree
  sampled at 10s intervals gave 1259520 → 1310720 → 1372160 → 1484800 → 1525760 → 1576960 bytes,
  ~25 min for a 15 MB tree, and emits a **0-byte file** for the first minutes so it reads as a hang
  (two runs were killed at 2 and 3 minutes for that reason). The repo is healthy —
  `git rev-parse HEAD` is 0.018s.
  Prime suspect, **not confirmed**: a global `filter.lfs` with `required = true` while `git-lfs` is
  not installed (`git lfs version` → "not a git command"). Against that theory,
  `-c filter.lfs.process= -c filter.lfs.required=false` did not help, and the repo has no
  `.gitattributes`. Next steps: `git config --global --get-regexp '^filter\.'`, then try
  `GIT_TRACE=1 GIT_TRACE_PERFORMANCE=1 git archive HEAD > /dev/null` to see where the time goes, and
  test whether the slowness follows the global config into a scratch repo. Fixing it restores a
  one-command isolation step for every future agent.


- [T-168] **iOS Focus mode: widgets and a landscape timer.** Two halves.
  *(a)* A widget showing the running timer plus what is being worked on, and a second showing the
  task list — exact split is a design call, make a good one rather than shipping two widgets that
  say the same thing. Two constraints to design around, both real: **WidgetKit timelines cannot
  tick**, so a live count needs `Text(timerInterval:)` (the system animates it without waking the
  extension) or ActivityKit for a Live Activity on the lock screen and Dynamic Island — a timeline
  that reloads every second is not an option. And **`FocusManager` is `#if os(macOS)` only**
  (`macOS/Services/FocusManager.swift`); iOS focus lives in `iOSFocusView.swift` with no shared
  state object, so session state is in-memory and a widget process cannot see it. Persisting focus
  state to the app-group store is the prerequisite, not a detail. Existing widgets to match:
  `CalendarSnapshotWidget`, `HabitCheckInWidget`, `MilestoneMomentumWidget`, `TodayTasksWidget`.
  *(b)* iPhone **landscape** layout for the running timer and its tasks. The compact shell
  (`iOSCompactTabShell`) is built around a portrait tab bar; landscape focus wants the timer large
  and the chrome gone, which is a different shape rather than the same one rotated.






- [T-122] **Flip `SWIFT_VERSION` to 6.0 — now an open question rather than a blocked one.** `D-95`
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  cleared the last macOS error, so nothing in the app's source blocks it. What remains: 10
  Swift-6-mode *warnings* elsewhere in the app (byte-identical before and after T-105, none in
  editor files), and on iOS the toolchain bug in [T-115] — swift-frontend crashes in IRGen once the
  diagnostics are gone, which is not app code. So macOS could plausibly flip first; iOS cannot until
  the toolchain moves. `CadenceMCPServer` has been on 6.0 all along.

  **MEASURED 2026-08-26 against `36be8ba` and re-confirmed on `ea77271`, Xcode 26.6 / Swift 6.3.3.
  Recommendation: do not flip anything yet — flip nothing before the two items in "what a flip
  needs" below are done, and never flip iOS while [T-115] stands.** Every number below is one
  `xcodebuild` run into a private `-derivedDataPath` over an `rsync`-isolated tree, exit status read
  on the xcodebuild line, diagnostics counted from the log with **no path filter** and attributed to
  a target by the `(in target 'X' from project 'Cadence')` line above them.

  | Target | Swift 5 today | Swift 6 (`SWIFT_VERSION=6.0` override) |
  |---|---|---|
  | `Cadence` (macOS) | 0 errors, 0 warnings | **0 errors, 10 warnings** |
  | `Cadence` (iOS Simulator) | 0 errors, 0 warnings | 0 errors, 1 warning — **but swift-frontend crashes, no build** ([T-115]) |
  | `CadenceWidgets` | 0 errors, 0 warnings | **0 errors, 0 warnings** |
  | `CadenceMCPServer` | already 6.0: 0 errors, 0 warnings | already 6.0 |
  | `CadenceTests` | 0 errors, 0 warnings | **611 errors** |
  | `CadenceUITests` | 0 errors, 0 warnings | 0 errors, 5 warnings |

  Notes on how those were obtained, because two of them are not what a single run reports.
  - A Swift 6 build of the app **stops at `EmitSwiftModule` on two errors in one file** —
    `Cadence/Services/CadenceDataExportService.swift:228`, `nonisolated static let
    recordCountsByEntityName: [String: KeyPath<CadenceArchive, Int>]`, because `KeyPath` is not
    `Sendable`. That file postdates `D-95`, so **the app's Swift-6 error count is not a fixed
    quantity that T-105 drove to zero — it regressed to 2 the moment ordinary new code was written
    under Swift 5.** Nothing else in the app module errors: with that one declaration changed to
    `nonisolated(unsafe)` **in the scratch copy only**, the whole macOS app module compiles.
  - The per-target error counts were then taken with `SWIFT_COMPILATION_MODE=wholemodule`, because
    the default batch mode surfaces **one failing batch at a time** — the first Swift 6 run of
    `CadenceTests` reported 18 errors in one file and stopped, and the module actually holds 611.
    Any future count of this debt must be taken whole-module or it is a lower bound.
  - The 10 macOS app warnings are the same 10 this ticket has always claimed, and they are in five
    files: `Services/CadenceRemindersManager.swift` (1 — the only cross-platform one, and the iOS
    build's single warning), `macOS/Views/TimelineDropInteractionSupport.swift` (3),
    `macOS/Services/QuickTaskPanelController.swift` (3), `macOS/Services/CalendarManager.swift` (1),
    `macOS/Services/CadenceMCPRefreshCoordinator.swift` (1),
    `macOS/Views/CalendarBoardDayColumnSupportViews.swift` (1). All are ordinary main-actor
    isolation, none is in `macOS/Editor/`.

  **`CadenceTests`' 611 errors are one build setting, not 611 problems.** The app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `CadenceTests` and `CadenceUITests` do not. So under
  Swift 6 every `@Test` function is nonisolated by default and every call into the app's
  main-actor-by-default API is an error — 365 of the 611 are literally "call to main actor-isolated
  static method 'X' in a synchronous nonisolated context". Adding
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to the test target takes `CadenceTests` from **611
  errors to 0**, measured. It also takes `CadenceUITests` from 0 to **11**, all of the form
  "main actor-isolated instance method 'setUpWithError()' has different actor isolation from
  nonisolated overridden declaration" — `XCTestCase` overrides, a handful of `nonisolated` keywords.
  That asymmetry is the whole shape of the problem: the two test targets want opposite defaults.

  **What a flip needs, in order.** (1) Fix `CadenceDataExportService`'s key-path table — and note
  `nonisolated(unsafe)` was only a probe, not a proposal. (2) Clear the 10 app warnings; they are
  real isolation questions in scheduling, panel and EventKit callbacks, not cosmetics, and the
  zero-warning baseline is worth more than the language mode. (3) Set the test targets' actor
  isolation deliberately and re-measure — and consider that making every `@Test` main-actor is a
  behavioural change to the suite, not just a compile fix. (4) iOS stays on 5.0 until [T-115]'s
  compiler crash clears, whatever macOS does.

  **A partial flip is available and is the recommendation *when* the above is done, not now.**
  `SWIFT_VERSION` is per-target, `CadenceMCPServer` has been 6.0 beside 5.0 targets all along
  without splitting anything, and `CadenceWidgets` compiles under Swift 6 today with 0 errors and 0
  warnings. So "two dialects" is already the status quo and costs nothing new. What a macOS-only
  flip *would* split is the app target itself — one module built two ways per platform — which is
  the one combination worth refusing: `Cadence/Shared/` and `Cadence/Services/` compile into both,
  so an isolation fix accepted by the macOS flip would still have to satisfy the iOS Swift 5 build,
  and a regression introduced on the iOS side would be invisible until [T-115] cleared. Flip
  `CadenceWidgets` and (after step 3) `CadenceTests` if a partial flip is wanted early; leave the
  app target alone until both platforms can move together.


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

  **Re-checked 2026-08-24 under 14 concurrently-building agents: not reproduced, and the tell is now
  in `AGENTS.md`.** Live `ps` found no bare `xcodebuild` pinned at 0% CPU; every process that looked
  stalled at a glance was a `test-host-lock.sh acquire` wait (T-236's mutex, working as designed —
  `sleep 10` in a loop, not a hang) or a polling wrapper shell around one. The user's Xcode was not
  running at all, so one of the two confirmed claimants from the original report was simply absent
  tonight — consistent with the mitigation ("quit Xcode when a batch of agents is running") rather
  than with the mechanism having gone away. Two processes stranded the same night — an `xcodebuild
  test` at 3h14m against a suite that normally runs ~15 minutes, and a runner script at 4h30m — were
  both killed before anyone captured a `sample`, so neither can be attributed to this ticket by
  evidence; that would be a third confirmation resting on inference, which is exactly the shape T-119
  warns against. The runner script fits `58e20a4` ("agents stall by launching a background job and
  returning," the same night, four other agents confirmed) far better than it fits a project-file
  deadlock: a wrapper script outliving the agent that launched it, with no one left to read its
  `DONE` file, is that failure's signature, not this one's. Downgrading the open half of this ticket
  accordingly: the mechanism from the original two `sample` captures stands and the mitigation stays,
  but there is nothing further to *fix* here — this is a recognition guide, not open work. See
  `AGENTS.md`'s new bullet (after the T-236 test-host mutex entry) for the exact tell command.

- [T-115] **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

  **STILL REAL — reproduced 2026-08-26 on the installed toolchain (Xcode 26.6, Apple Swift version
  6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)), twice, in two compilation modes.** This was worth
  re-testing rather than inheriting: the toolchain had not moved, and it has not. Recipe:
  `-scheme Cadence -destination 'generic/platform=iOS Simulator' SWIFT_VERSION=6.0 build` over an
  isolated tree, with `CadenceDataExportService`'s key-path table made `nonisolated(unsafe)` in the
  scratch copy so the module gets past `EmitSwiftModule` (see [T-122]). The iOS module is then
  **diagnostically clean — 0 errors, 1 warning** — and swift-frontend aborts anyway:

  ```
  4.	While evaluating request IRGenRequest(IR Generation for file ".../Cadence/iOS/iOSCalendarView.swift")
  5.	While emitting IR SIL function "@$s7Cadence0A19CalendarMonthDetailOScA_pSgIeAghyg_ACIeAghn_TR".
  ```

  which `swift-demangle` reads as `reabstraction thunk helper from @escaping @isolated(any)
  @callee_guaranteed @Sendable (@unowned Cadence.CadenceCalendarMonthDetail, @guaranteed
  Swift.Actor?) -> () to @escaping @isolated(any) @callee_guaranteed @Sendable (@in_guaranteed
  Cadence.CadenceCalendarMonthDetail) -> ()` — the `(any Actor)?` reabstraction thunk this ticket
  named. Two details the earlier write-up did not have:

  - **It is not one unlucky type.** Under `SWIFT_COMPILATION_MODE=wholemodule` the same abort fires
    on a *different* thunk, `@$sSSScA_pSgIeAghgg_SSIeAghn_TR` (the `String` one). Whatever is wrong
    is general to `@isolated(any)` thunk emission for this module, not to `CadenceCalendarMonthDetail`,
    so "find the one call site and rephrase it" is unlikely to be a workaround.
  - **The stack names the failure**, and it is an assertion, not a segfault:
    `IRGenSILFunction::visitFullApplySite` → `SyncCallEmission::setArgs` →
    `llvm::SmallVectorBase<unsigned int>::grow_pod` → `report_at_maximum_capacity` →
    `llvm::report_fatal_error` → `abort`. An LLVM `SmallVector` exceeding its maximum capacity while
    setting call arguments. Worth quoting verbatim in any bug report filed against the toolchain.

  Control confirmed in the same session: the identical tree on Swift 5 builds the iOS target to
  `** BUILD SUCCEEDED **`, exit 0, 0 errors, 0 warnings — so this is the language mode, not the
  sources. macOS emits IR for the same shared modules with no trouble, so it is iOS-only.
  Recheck on the next toolchain bump; there is nothing to fix in Cadence.

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

- [T-55] *(rewritten 2026-08-30 as `docs/device-checks.md`, 5 items, ~5 minutes. **Two of the three original items were materially stale**: the drag-to-create item claimed no simulator API can lift a `UIDragInteraction`, which was already wrong when written and is now moot since neither `+` uses system drag; and the double-tap item told you to double-tap a table expecting source, when since [[T-221]] a table is not revealable that way — so following the old checklist would report a pass as a failure. Now includes the [[T-447]] size-class residue with a **binary tell** rather than a pixel judgement: if the class fails to propagate, the rail's `Theme.surface` stops under the title instead of filling the sheet.)* **Three things need a real phone, not a simulator** — written up as a checklist in
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

- [T-16] **Redesign the logo.** Currently the app mark in the sidebar header and the app icon.
- [T-17] **Expand the target device list.** Directly reverses [T-08]; anything deleted as
  "unnecessary for the three targets" would need reinstating, so [T-08] should be done in a way that
  is easy to read back out of git history. Backlogged.

  **Axis decided 2026-08-24, still backlogged.** The user's answer: *more iPhone and iPad sizes* —
  not a lower OS floor and not a new platform family. Both of those are explicitly out of scope, so
  do not touch `IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` or add a
  `TARGETED_DEVICE_FAMILY` entry on the strength of this ticket. **The user will name the exact
  devices and OS versions when they want this done — do not start it before then.**
  Investigated 2026-08-24 without changes. `TARGETED_DEVICE_FAMILY = "1,2"` on every target already,
  so any iPhone or iPad can install today; nothing at the build level blocks it and **no
  `project.pbxproj` edit is needed for this axis**. T-08 removed no device-specific code — it deleted
  width clamps unreachable at the three targeted sizes (`inspectorMaxWidth` 430, two 540 inspector
  caps, a 760 task cap) and replaced them with proportion-pinning tests, so there is nothing to
  reinstate. The whole cost is layout auditing: the current breakpoints (Goals' inspector gate at
  901, Today's 761/841/900/928 bands, the Calendar Board's rails, the Settings templates card) were
  tuned and tested against three screen profiles only. D-155, b1239e0 and 8b73c78 each found a real
  defect at a width nobody had measured, so expect more of that shape rather than a settings flip.

- [T-18] **Chinese localisation.** Backlogged. Nothing is localised today: user-facing strings are
  hardcoded English at the call site, and `DateFormatters` uses fixed formats. Two known hazards
  already documented in this repo — `Calendar.current` is not Gregorian everywhere (a `yyyy-MM-dd`
  storage key becomes `2569-…` under a Buddhist calendar), and weekday symbol arrays are indexed by
  weekday number rather than by `firstWeekday`. Both bit us before; both get worse with a second
  locale.
  **Scoped 2026-08-24; no code changed.** Measured with
  `python3 count_strings.py` (comment-stripped regex over `Text(`/`Label(`/`Button(` &c., the
  `.navigationTitle`/`.help`/`.accessibilityLabel` modifiers, `return "…"` display copy, and
  labelled `title:`/`message:`/`subtitle:` arguments): **~2,000 hard-coded call sites, ~1,233 unique
  strings, ~4,660 English words** across `macOS` (848) / `iOS` (707) / `Shared` (271) /
  `Services` (188) / `Models` (68). Infrastructure is **zero** — no `.strings`, `.xcstrings` or
  `.lproj` anywhere, `knownRegions = (en, Base)`, zero `NSLocalizedString` / `String(localized:)` /
  `LocalizedStringKey`. 250 of the unique strings carry `\(…)` interpolation, and 57 do English
  pluralisation inline as `\(n == 1 ? "" : "s")` — those are the restructuring cost, not the
  translation cost. `CadenceTests` holds **342** `== "Capitalised copy"` assertions that pin English
  literals; they are the loudest thing a translation breaks.
  **Storage boundary (do not cross):** `DateFormatters.ymd`, every `dateKey`, `weekKey`, and
  `TaskSectionDefaults.defaultName = "Default"` are storage. The last one is the sharp edge — it is
  the default value of the persisted `AppTask.sectionName` *and* the subject of
  `TaskSectionConfig.isDefault`'s `caseInsensitiveCompare`, so it is a display string that is also a
  comparison key. Translating it silently orphans every existing task's column.
  Two latent defects found while scoping, both **already wrong today** and neither Chinese-specific:
  - `DateFormatters.longDate` / `shortDate` / `fullShortDate` / `dayOfWeek` / `monthAbbrev` are the
    only fixed-format formatters in the file that are **not** locale-pinned, while `monthYear`'s doc
    comment states pinning as the repo's rule. Verified against Foundation: on a `zh_Hans_CN` device
    `"EEEE, MMMM d"` already renders `星期一, 八月 24` and `"EEE"` renders `周一` — half-translated
    output beside English chrome, which is the exact outcome `monthYear` was pinned to prevent.
  - `MonthCalendarPanel` (`Shared/Components/CadenceDatePicker.swift`) hardcodes
    `["Su","Mo","Tu","We","Th","Fr","Sa"]` and derives its leading blanks from
    `component(.weekday,…) - 1`, i.e. Sunday-first unconditionally — it ignores `firstWeekday`. Its
    sibling `CadenceScheduleSupport.weekdaySymbols` rotates by `firstWeekday` over
    `calendar.shortWeekdaySymbols`, and its doc comment records that exact skew shipping in Germany
    and Saudi Arabia. So the two shared month grids already disagree in Monday-first regions, and on
    a Chinese device the iOS grid reads `周日 周一…` while the macOS picker reads `Su Mo…`.
  Not a hazard after all: the `Calendar.current`-is-not-Gregorian storage risk this ticket names is
  contained — `%04d-%02d-%02d` key derivation exists in exactly two files and both route through
  `DateFormatters.storageCalendar`, and `zh_Hans_CN` is Gregorian and Sunday-first anyway.
  Also out of scope by decision: `CadenceMCPServer` / `Services/MCPReadOnly` strings are a
  machine-facing protocol surface and must stay English.

  **The two date defects are fixed and pushed (`c09f67d`); the rest stays backlogged.** Six
  fixed-format formatters are now locale-pinned — `dayNumber` was the sixth, missed by the original
  count and the same class, since numerals follow the locale too. And both month grids read one
  function, `CadenceScheduleSupport.weekdaySymbols` / `leadingBlankCount`, with language pinned and
  **week start honoured from `firstWeekday`** — that is a real preference, not a language one.
  Three mutations killed at 0 compile errors each; 2480 passed / 0 failed.
  **This inverts when localisation actually happens**, and both doc comments say so: the pins come
  off and the fixed patterns must become `setLocalizedDateFormatFromTemplate` or `Date.FormatStyle`,
  because idiomatic zh is `8月24日` rather than a translated `MMMM d`.

- [T-274] **Importing a Cadence archive.** [[T-19]] shipped the export and deliberately stopped
  there: an unverified restore is worse than none, because it invites the user to trust it.
  `CadenceDataExportService.decode` already returns a `CadenceArchive`, and
  `CadenceDataExportSurfaceTests.theArchiveRoundTripsThroughJSON` proves encode → decode → equal, so
  the *parsing* half is done and tested. What is not decided, and what makes this a design ticket
  rather than a loop over twenty arrays:
  1. **CloudKit.** The store is `.private("iCloud.com.haoranwei.Cadence")`. An import is not a local
     write — every row inserted is uploaded to every other device, so "restore my backup" on one
     device is "push 4,000 rows at the others" from theirs. A restore has to state whether it
     targets the syncing store at all, or whether it goes through the `CADENCE_LOCAL_STORE_ONLY`
     path and asks the user to re-enable sync afterwards.
  2. **Identity.** Records carry their original `id`s. Re-inserting them means the merge policy
     decides which copy of a row wins, and nothing in the app currently reasons about that. The
     three plausible modes — replace the store, merge by id, import as copies with fresh ids — have
     different answers and only one of them can be the default.
  3. **Referential integrity.** Relationships are stored as id references, so an import is a
     two-pass rebuild: insert every row, then wire every reference. A reference to a row the archive
     does not contain (a hand-edited file, or an archive from a newer `formatVersion`) has to fail
     loudly rather than silently produce an orphan — `DataIntegrityRepairService` is the repair pass
     for stale relationships, not a substitute for validating input.
  4. **The legacy note models.** `DailyNote` / `WeeklyNote` / `PermNote` / `EventNote` / `Document`
     are exported because a pre-migration archive is the only copy of them. Importing one into a
     store where `NoteMigrationService` has already run would re-create rows that were already
     folded into `Note`, i.e. duplicate every note. The importer has to run the migration after the
     insert, or refuse those tables when the destination has already migrated.
  Do **not** ship this behind a confirmation and call it verified. The bar is a test that imports an
  archive into a container and asserts the graph came back — every foreign key resolved, counts
  equal, and a second import of the same file changing nothing.
- [T-280] *(narrowed 2026-08-30: the iOS paste is **not** a second implementation — it composes the same two shared calls, and its extra hop adds no padding, so the text it writes is computable on macOS and equals a path measured against a real clipboard. Four tests, four mutations, all killed. **What is left is one value**: whether UIKit consults `canPerformAction` for `paste:` when it builds the edit menu. That is item 1 of `docs/device-checks.md`. Do not close until someone taps it.)* **The iOS half of T-279 is fixed by construction and unverified on a device.**
  `iOSMarkdownTextView.canPerformAction` now returns `true` for `paste:` when
  `UIPasteboard.general.hasImages`, mirroring the macOS `readablePasteboardTypes` widening. The
  macOS half was measured before *and* after against a real clipboard holding a real PNG; the iOS
  half has only an iOS **build**. `Cadence/iOS/` is inside `#if os(iOS)` and invisible to the
  macOS-built `CadenceTests`, so there is no unit-test route to it. The predicate to check on a
  simulator is one value: with an image on the pasteboard and the caret in a note, **Paste** appears
  in the edit menu and inserts the picture. Do not close this by reading the diff — a correct
  `paste(_:)` override that was never dispatched is exactly how the macOS bug survived.





















- [T-481] **DECIDE: one top-level suite per test file?** Raised and deliberately *not* landed while
  closing [[T-465]]. It would provably stop the sibling-suite risk surface from growing and has zero
  false positives — but it imposes a new authoring rule that **32 existing files already break**, so it
  is a decision, not a fix. Options: adopt with those 32 allowlisted; adopt and split them; decline and
  keep the periodic `scripts/test-suite-index.sh` read that T-465 settled on.




- [T-485] **Three sibling suites still leave fabricated launch reports in the test host's `UserDefaults`.**
  Demonstrated live by [[T-480]]'s own final run, which left `dataIntegrityRepair.lastReport.v1` =
  `{"source":"test"}` behind. `DataIntegrityRepairServiceTests` (11 call sites, 1 guarded test),
  `CadenceHabitCompletionDuplicateTests` (3, 0), `CadenceNoteFolderSurfaceTests` (1, 0). Each needs a
  one-line `@Suite(.preservesTheStoredLaunchReports)`. To make it durable rather than a one-off cleanup,
  a `CadenceScanInstrument` sweep asserting every suite that reaches `migrateIfNeeded`/`repairIfNeeded`
  carries the trait.

- [T-486] **Extension methods declared in non-member files are invisible to the membership guard.**
  [[T-435]]'s own text named this alongside free functions; only the free-function half is closed.
  Measured: **117** extension-method names are declared in files the MCP target does not compile. A crude
  dot-qualified probe surfaced 2 candidates and **both are false positives** — one resolves to a member
  file, one is inside a doc comment — so there is no live violation. A real check needs receiver-type
  resolution, a different instrument from the two in that file, which is why this is separate rather than
  a widening.

- [T-487] **DECIDE: `TasksPanel`'s `.byDoDate` mode is unreachable.** No caller constructs it —
  `TodayView.swift:29` is the only construction and takes the `.todayOverview` default; the only
  `.byDoDate` panel in the repo is in a test. The mode still costs branches in `TasksPanel.swift`
  (`:246,339,514,679`), `TasksPanelDerivedState.swift:87` and `TasksPanelSupportViews.swift:37,46,73`.
  **Its empty state held two retired strings for the entire time nobody could see it**, which is how dead
  UI decays. Either it is a planned All Tasks panel and something should draw it, or it and its branches
  should go.


- [T-488] **`iOSListEditorSheet`'s Area row has the defect [[T-446]] just fixed for Context.** Same file,
  one row down the same `Form`: `areaTitle` (`iOS/iOSListEditorViews.swift:83`) resolves against
  `areas.filter(\.isActive)` while `selectedArea` (`:510`), which `save()` uses, resolves against the
  unfiltered `areas`, and the popover offers only active ones. So editing a project whose area was since
  deactivated **shows "None" and saves the inactive area**. There is no shared support type for area
  picking to route it through — `CadenceContextPickerSupport` is the model to copy.

- [T-489] **DECIDE: `.stroke` vs `.strokeBorder` app-wide.** Withdrawn from [[T-449]] rather than done.
  `macOS/Views/SettingsListManagementSections.swift:381` draws a 28x28 glyph at radius 7 with `.stroke`,
  which centres the 1pt line on the path — so the control renders 1pt wider than it measures, the defect
  `CadenceSettingsWell`'s own doc names as the tell. `.strokeBorder` is the value-preserving fix, but it
  is a 1pt visual change nobody has looked at and **28 other sites spell it the same way**. Either an
  app-wide sweep or nothing.

- [T-490] **`CadenceChoiceRow` defaults its `id` to `AnyHashable(title)`, and 32 call sites take the
  default.** Two options with the same displayed title collide into one `ForEach` identity in
  `CadenceChoicePopoverList`. [[T-446]] passed an explicit id at its three context sites; the other 32 in
  `Cadence/iOS/` still default. Either make `id` non-defaulted or derive it from `value`, which is
  already `Hashable`, rather than from the title.

- [T-491] **The iPad capture palette's scrim stops at the detail pane.** Found while closing [[T-282]].
  `iPadMacStyleRootShell` clips `detail()` and the capture host is inside it, so an open palette **dims
  the page and leaves the sidebar bright**; on iPhone the shell-level host dims everything including the
  tab bar. The scrim's `.ignoresSafeArea()` is a no-op inside that clip. Placement-vs-capability
  judgement, so it needs a decision rather than a fix.

- [T-492] **`iOSNoteEditorSheetHeader` hand-spells the editor-sheet host gutter.** Residue from
  [[T-281]] — the fix that closed one duplication opened this one.
  `.padding(.horizontal, isRegularWidth ? 20 : 18)` is exactly
  `iOSEditorSheetMetrics.gutter(isRegularWidth:)`, which five surfaces read and whose own comment says it
  exists so that figure is stated once. Worse, T-281's `oneSharedViewOwnsTheNoteEditorHeaderRamp`
  **asserts the literal is present**, pinning the copy in place. Closing it is one line of view source
  plus removing the named exclusion in `noEditorSheetSurfaceSpellsTheHostGutterRampItself`. Worth doing
  for a second reason: `iOSEditorSheetMetrics` sits outside `#if os(iOS)` so `CadenceTests` can read it,
  so routing the header through it converts that ramp into a behavioural assertion.

- [T-493] **`iPadTodaySidePanel`'s kept prefix rests on a claim the code does not keep.**
  `iPadTodaySupportViews.swift` says all three kept types are built only by the two-pane host and "a
  compact width cannot reach any of them". True for two of the three. **False for `iPadTodaySidePanel`**:
  `iOSTodayView.swift:24` names it in an `@AppStorage` default — a stored-property initialiser evaluated
  at every width — and `iOSCompactTabShell`, `iOSTasksTabView` and `iOSSearchView` all construct that
  view at compact width. [[T-283]]'s test silently omitted the enum from its reachability check, which is
  why nothing said so. Either rename it or correct the comment.


- [T-495] **`MarkdownEditorView` replaces `NSTextView`'s dragged-type registration rather than adding to
  it.** `registerForDraggedTypes` sets the accepted-type list wholesale and `configure(_:context:)` has
  called it unconditionally since before [[T-478]], so the macOS note editor may accept only the types
  Cadence names — **plain-text and RTF drags into a note might silently do nothing**. **Not measured**: no
  drag was performed, and `NSTextView` re-registers `acceptableDragTypes` on its own at various points,
  which may already restore them. Cheap to settle by hand — drag selected text from another app into a
  note. If real, union with `super`'s types in `CadenceTextView.registerMarkdownDraggedTypes()`.

- [T-496] **One uppercase label size, three trackings.** `SectionEyebrowLabel.Size.standard` is 10/0.8
  (0.08em, derived), `CadenceBoardColumnHeaderMetrics` is 10/0.4 (literal),
  `CadenceCalendarWeekdayHeaderMetrics` is 10/0.5 (literal). All three are uppercased semibold at 10pt,
  and **each file's doc cites the other two as the authority for its size while disagreeing on
  tracking** — the [[T-284]] defect one file over. Deliberately not picked: choosing 0.08em doubles the
  tracking on every kanban column header, which is the un-inspected change [[T-452]] is open for. Needs
  the same screenshot pass, then a ratio.






- [T-501] **`docs/TODO_DONE.md`'s "Landed in" SHAs record where a ticket was *removed*, not where it
  shipped.** Found while applying [[T-462]]'s title recovery: T-285's entry reads "Landed in `0dd7258`",
  whose subject is *"Deduplicate docs/TODO.md"* — a bookkeeping commit that changed no Swift.
  [[T-462]]'s measurement explains why: **175 of 200 archived tickets were removed by commits that
  touched only `docs/TODO.md`.** So an unknown share of the 177 existing entries attribute a fix to a
  commit that did not contain it, which is worse than a missing SHA because it reads as authoritative.
  Establish how many are wrong before deciding whether to re-derive them.


- [T-503] **The `try? save()` rule is blind to "insert and never commit at all."** Found by [[T-497]]
  while applying the rule. **Both halves key on the *presence* of a `try? ...save()`**, so a function
  that inserts and never commits passes both sweeps. Measured over 552 files: **21 declarations call
  `modelContext.insert(...)` and reach neither `save()` nor any `commit*`. Four of those also report
  success in the same function** — [[T-471]]'s defect with the save missing entirely rather than
  swallowed:
  `CreateContextSheet.create` (`insert; dismiss()`), `CreateListSheet.create` (same),
  `HabitsFormSheets.create` (`insert; scheduleReconcile; dismiss()`), and
  `TimelineEventBlockSupportViews.openEventNote` — **the exact macOS twin of the site T-497 just fixed
  on iOS, one platform behind, and worse: iOS at least attempted a save.** Cost is the one [[T-322]]
  measured: the row stays *pending* in the single `ModelContext`, committed by the next unrelated save
  from any screen or discarded by the next unrelated `rollback()`. Fix: route the four through
  `commitInsert`, then add a **third half** to the rule (a declaration that inserts must reach a
  commit), subtracting the 17 helper cases **by rule** — those are inserts whose *caller* owns the unit
  of work. Also add `presented[A-Z]\w* =` to half 2's vocabulary.

- [T-504] **An enabled Paste that does nothing, at the four hosts that refuse images.** Symmetric on
  both platforms, confirmed by construction. iOS: `canPerformAction` returns `true` for any image-only
  pasteboard, but `createPastedImageAssets` returns `[]` when `allowsImageInsertion` is false, so
  `paste(_:)` falls through to `super.paste`, which does nothing on a view with
  `allowsEditingTextAttributes = false`. macOS: `readablePasteboardTypes`
  (`MarkdownEditorInteractionSupport.swift:101`) widens **unconditionally**, even though the same class
  already carries `allowsMarkdownImageInsertion` — `registerMarkdownDraggedTypes` and
  `markdownImageDropOperation` both consult it and this one does not. Affects the note-template editor
  on both platforms, the calendar event-edit sheet, and quick-create in event mode. One clause on
  macOS; thread the flag onto `iOSMarkdownTextView` for iOS.

- [T-505] **Four "Untitled ..." labels have no declaration anywhere.** Found while closing [[T-499]].
  Unlike the three labels that one moved, `"Untitled Goal"`, `"Untitled Habit"`,
  `"Untitled Milestone"` and `"Untitled Note"` are re-typed with nowhere to read them from —
  `CadenceReadService.swift:901,915,1126,1155`, `CadenceHabitWidgetSupport.swift:200`,
  `CadenceMilestoneWidgetSupport.swift:284`, `CadenceNoteExportSupport.swift:107`,
  `AIActionService.swift:86`, plus ~a dozen iOS sites. **The sweep structurally cannot see them**: it
  reports a *shared constant* re-typed, and with no declaration there is nothing to compare against.
  T-499 makes the fix cheap — declare them beside the other three in `CadenceTitleNormalization` and the
  sweep picks them up automatically, since the harvest now reads `Cadence/Models/`. Spans all three
  targets.


- [T-497] **Tier 3 of the condemned `try? save()` sites — 2 left of the original 12.**
  **Tier 1 and Tier 2 closed 2026-08-30** (7 sites, each exemption entry deleted with its fix, pinned by
  `CadenceTagAndNoteCommitSurfaceTests` — 3 behavioural, 5 source-shape, 10 mutations all killed by
  named tests). Two things that tiering did not predict: `openEventNote` **could not un-insert blindly**,
  because `noteForEditing` returns an existing note as often as it creates one, so a naive
  `commitInsert(of:)` would have deleted a note the user already had; and the notice it reports through
  **did not exist at regular width** — `iOSCalendarEventEditSheet.regularFormLayout` carried
  `readOnlyNotice` but not `actionErrorNotice`, so on iPad *every* failure that sheet reports was
  invisible, including refused EventKit saves and deletes predating that work. Both fixed.

  **Remaining: `iOSSearchSupportViews` (note editor Done) and `iOSTaskDetailSheet.finishEditingAndDismiss`.**
  Both are "flush an in-place edit, then close", and both are **blocked on a decision**, not on work:
  what does undo mean for a field the user is still looking at and still has focus in? Tier 2's inline
  row editors were the easy half — they hold their drafts in `@State`, so restoring the model does not
  fight a caret. These two do. Answer it once and both fall out. Written up in
  `docs/DECISIONS_PENDING.md`.

  The three genuine non-defects keep their exemptions: `TagSupport.seedDefaultTags`/`deduplicateTags`
  (launch-time, idempotent, both already take a save flag) and `CadenceUITestSupport.seedDataIfNeeded`
  (no user). See [[T-503]] for the hole this work found in the rule itself.


- [T-506] **macOS note export can silently fail *after* the user picks a destination** (Codex, P2,
  measured). `macOS/Services/NoteExportService.swift:39,46` write markdown and PDF bytes with `try?`;
  a failed write is swallowed and no UI state records it, so the user picks a folder, sees nothing, and
  has no file. **Three correct patterns already exist** — `iOS/iOSNoteExportMenu.swift:82-85` reports
  `fileExporter` failure, and both data-export sections
  (`macOS/Views/SettingsDataSafetySection.swift:118-126`, `iOS/iOSDataExportSettingsSection.swift:79-87`)
  report theirs. Return/report the error through the macOS caller, then pin it. **Note this is a file
  write, not a `save()`** — see [[T-508]].

- [T-507] **iOS saved links throw away the shared persistence helper's failure signal** (Codex, P2,
  measured). `iOS/iOSListSupportViews.swift:687` calls `try? CadenceSavedLinkPersistence.insert(...)`
  then clears the title, clears the URL and closes the add form **regardless**; `:699` does the same for
  delete. The helper (`Shared/CadenceSavedLinkPersistence.swift:35-45`) already commits and rolls back
  correctly — the caller discards the answer. **macOS is already right**: `LinksView.swift:109-114`
  catches insert failure and leaves the form open, `:125-130` catches delete. Mirror it, add an iOS
  `actionError` notice near the saved-links section, and pin so iOS cannot reintroduce `try?`. Same
  shape as [[T-470]]/[[T-471]].

- [T-508] **The `try? save()` rule keys on `save()` specifically, so it misses `try?` on commit helpers
  and file writes.** Distinct from [[T-503]] and found the same way — by two real defects it could not
  see. The sweep's patterns are `try? save()` and `try? modelContext.save()`, so
  `try? CadenceSavedLinkPersistence.insert(...)` ([[T-507]]) and `try? content.write(to:)` ([[T-506]])
  both pass all halves. **Widen the vocabulary to the commit surface rather than the method name**: any
  `try?` on a `CadencePendingChangePersistence.commit*`, on a `Cadence*Persistence` helper, or on a
  `Foundation` write whose failure the caller then reports success over. Measure the new hit count
  before shipping — the value of this rule so far has been that 86% of sites legitimately pass it.

- [T-509] **Saved-link URL normalisation mangles an uppercase scheme, on both platforms** (Codex, P3,
  measured). `macOS/Views/LinksView.swift:99` and `iOS/iOSListSupportViews.swift:677` both test
  `hasPrefix("http://")`/`hasPrefix("https://")` **case-sensitively**, so `HTTPS://example.com` becomes
  `https://HTTPS://example.com`. Two hand-rolled checks, one defect, twice — [[T-374]]'s shape. One
  shared normalisation helper read by both, pinned on lowercase, uppercase, mixed case, leading/trailing
  whitespace and scheme-less input.

- [T-510] **Release packet and review notes disagree about which platforms ship** (Codex, P3, measured
  doc drift, **not a runtime bug**). `docs/app-store-submission-packet.md:13` says *Platforms: macOS*,
  while `docs/app-review-notes.md:8` says Cadence targets macOS **plus iOS/iPadOS from one app target**,
  and the project lists `iphoneos iphonesimulator macosx`. If the next submission is Mac-only the packet
  should say so explicitly; if it includes iOS/iPadOS, the packet and its readiness tests need updating.
  **Decide before submitting, not after.**


## Done

Moved to [`TODO_DONE.md`](TODO_DONE.md) on 2026-08-26 — 220 entries, with their reasoning and shipping SHAs intact.
The working list was ~82k tokens and two thirds of it was finished work. **Search the archive
before filing**: this list has had the same ticket re-reported more than once.

- [T-161] **Tests pin helpers, not wiring.** The T-149 verifier proved by mutation that reverting the
  `macOSRootCommandActionSupport` fix leaves all 1692 tests green, and the same holds for T-150 —
  nothing observes that `MarkdownEditorView` calls the shared functions. `D-113` closed this for the
  markdown indent formula by testing that the stylist *reads the shared metrics*, not merely that the
  numbers are right. Worth applying that pattern to the two search fixes, and treating it as the
  default shape for consolidation work: a test that passes when the call site is reverted has not
  pinned the consolidation.

  **Survey, 2026-08-25, against `6e1f1e0`.** Measured rather than estimated, because nobody had:
  **2,514 `@Test` functions, of which 154 read a `.swift` file as text**, spread over **32 of 189**
  test files. Of those 154, **73 assert nothing but that some text exists** and 81 also assert at
  least one value produced by a real call. So the source-scan population is ~6% of the suite — small
  — and it is concentrated where the risk is: iOS surfaces the macOS target cannot compile, plus a
  tail of macOS files where a value *was* available and nobody reached for it. The script is
  reproducible from the classification described here; it strips comments and masks string literals
  before matching, because `func select(` inside a needle literal otherwise reads as a declaration.

  **Partly shipped in `902b386`: three fixed, each with the blindness proved first** (pre-fix
  mutation → all green, post-fix same mutation → red, both at 0 compile errors). Six more
  whole-file needle counts, listed below, were recorded as remaining rather than fixed — this
  ticket stays open for those:
  - *macOS's settings rail was pinned one case at a time.* `SettingsCategoryGroup` was `private`, so
    `theSyncCategoryIsFiledInTheMacOSRail` and `theAboutCategoryIsFiledInTheRailAndRoutedToItsSection`
    each found `static let all: [SettingsCategoryGroup]` in the source text, sliced to the next
    `\n}`, and asked whether the slice contained `".sync"` / `".about"`. Deleting `.notifications`
    from the Connections group — Settings → Notifications unreachable on macOS — passed. The struct
    is `internal` now and `theRailFilesEverySharedCategoryExactlyOnce` states the general rule.
  - *Both edit sheets' wind-down was two whole-file counts.* `macOSStillWindsDownOnArchiveAndOnCompletion`
    asserted `cancelRemainingActiveTasks(` == 2 and `completeRemainingActiveTasks(` == 2 in
    `EditListSheet.swift`. **Swapping them** — archiving a list marks its leftovers *done*, completing
    one cancels them — leaves both counts at 2 and passed. The branch is a value now
    (`ListEditorLifecycleChoice.windDownOutcome`) over a new
    `TaskContainerLifecycleService.settleRemainingActiveTasks(…outcome:)`, and the surviving scan is
    scoped to `apply(_:)`'s brace-matched body instead of the file.
  - *T-240, closed in `902b386` — see Done.*

  **`cadenceFunctionBody(_:in:)` is now the one brace matcher in `CadenceTests`** — `cfa3b3b`'s
  `focusFunctionBody`, promoted to `internal` and renamed, read by `FocusPickerPlayControlTests`,
  `AppStoreReviewReadinessTests` and `CadenceListWindDownSurfaceTests`. Anything else scoping a scan
  to one function calls it rather than writing a second.

  **Second pass, 2026-08-26 against `36be8ba`: four of the six done, each proved by mutation**
  (apply → red on exactly the intended test, restore → green; 0 compile errors on every run, and
  for each one the *old* whole-file needle was grepped in the mutated file and found still present,
  which is the blindness proof stated mechanically rather than by re-running a deleted assertion).
  - *The two inspector-host suites.* The repo-wide dictionaries are kept — they are the right shape
    for "exactly N places in the whole app" — and the per-file half is now placement.
    `theHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule` (and its bundle twin) pin the panel to
    the `.stay` arm of `CadenceDetailPanelPresentation.resolveHeldSubject`; **swapping the `.stay`
    and `.close` arms** leaves `iOSTaskDetailSheet(` at one occurrence in one file, every old
    assertion green, and every row in the app opening nothing.
    `theRootAppliesTheHostAboveBothShellsRatherThanInsideOne` (and its bundle twin) slice
    `iOSRootView`'s `Group` and require the host, the bundle host and the startup banner to be
    applied *to* it, not inside it; **moving `.iOSTaskInspectorHost()` into the
    `horizontalSizeClass == .regular` branch** — iPad keeps the inspector, the iPhone's four tabs
    get dead taps — keeps the file count at exactly 1.
    `theNestedHostSitsOnTheSheetThatCarriesAWholePageOfRows` scopes the nested host to
    `iOSTodayOverdueListSheet`'s **`var body`**, and the reason is a measured one: the first draft
    scoped it to the *struct* and survived a mutation that moved the modifier onto a second computed
    property in the same struct. Struct-level was not enough; `var body` is.
  - *`CadenceTodayOverdueSummarySurfaceTests.theMacCardsHopTheNavigationManagerThroughTheSharedRequest`
    is behavioural now.* macOS's half is compiled by this target and nobody had reached for it: the
    test drives `TasksPanelSupport.openOverdueListSummary` / `openOverdueSectionSummary` against
    `ListNavigationManager.shared` and reads the request it is left holding. Two mutations that the
    old scan could not see: **swapping the `.area` and `.project` arms** of the private
    `open(_:listNavigationManager:)`, and **dropping `sectionName:`** from both hops so the board
    lands on whatever column it last showed. The one whole-file assertion kept is the *absence*
    (`if let projectID = summary.projectID`), which is the claim a scan states better than a call.
  - *`CadenceTodayRolloverSurfaceTests.theMacSpellingDelegatesToTheSharedMutation` is scoped and
    stated as an equality.* `cadenceFunctionBody` slices `SchedulingActions.rollOverTaskToToday` and
    the whole trimmed body must equal the one delegating call, so **any** added statement fails —
    proved with `task.scheduledStartMin = -1` appended under the delegation, which the old
    `contains(…)` cannot see.
  - *`55d696b`'s owed evidence is paid.* Forcing `CadenceTaskGroupHeadingMetrics.showsCapsule` to
    `true` fails `CadenceInboxRemindersSurfaceTests.onlyAnUnknownCountSuppressesTheCapsule`, exit 65
    at 0 compile errors. The behavioural test was load-bearing all along.

  **Still open, and the list is shorter than it was for one reason worth reading.**
  - `CadenceKanbanColumnLifecycleSurfaceTests.bothVisibleCompletionControlsSitInsideTheLifecycleGate`
    and `theKeyboardRouteAndTheConvergencePointBothRefuseDefault`. Both already assert *structure*
    with brace-adjacent regexes; what is unscoped is the pair of
    `section.supportsLifecycle` == 2 counts beside them. Not attempted here.
  - `CadenceListDetailTabStripMarginTests.theResetIsTheStripsAloneAndTheHostCompensatesForNothing`.
    Not attempted. Note while you are in the file: it declares a **second** declaration slicer
    (`declaration(named:in:)`, which slices to the next `\nstruct` rather than brace-matching), and
    `CadencePageHeaderMetricsTests` / `CadenceTodayUnificationTests` declare a **third** between
    them (`declarationBody(of:in:)`, twice, byte-identical). Three private near-copies of the thing
    `cadenceFunctionBody(_:in:)` was promoted to be.
  - `CadenceSharedBoardChromeTests.bothBoardsDrawTheSharedMetadataChip`. Not attempted.
  - `CadenceSharedTaskRowJobsTests.theRowsAnimatedPartsAreStillExtractedIntoTheirOwnSubViews` was
    **rewritten but is the one place a mutation did not survive on its own merits**, and that is the
    finding rather than the fix. It now asks each declaration for its own count —
    `TaskCompletionButton` 1, `TaskRowBackground` 1, `MacTaskRow` 0, `MacTaskRowEstimateChip` 0 —
    over `cadenceFunctionBody`, with the whole-file 2 kept as a no-fifth-reader guard. The mutation
    (the row observes the manager and hands it down to `TaskRowBackground` as a `let`) does turn it
    red, but it turns `CadenceTodayUnificationTests.theTaskRowStillDoesNotObserveTheCompletionAnimationManager`
    red too — that test has scoped `MacTaskRow` and `MacTaskRowEstimateChip` to their declaration
    bodies all along, so the bullet's stated gap ("cannot tell the two extracted sub-views from
    `MacTaskRow` growing one of its own") was already closed by a neighbour nobody had checked.
    The residue the new assertion adds — *both* observations in one sub-view and none in the other —
    could not be mutated into existence in code that compiles, because a view that uses `manager`
    has to obtain it and the only non-observing route needs a holder that is itself forbidden from
    observing. Recorded as unprovable rather than claimed as proved.
  **Closed 2026-08-29. `CadenceScanInstrument` validates a detector against a positive **and** a negative fixture in its *initializer*, so a blinded detector cannot reach a sweep; `sweep`'s `atLeast:`/`including:` are non-defaulted, so omitting the non-vacuity assertion is a compile error. Evidence: the same blinding mutation, both at 0 strict compile errors, left the bare-predicate sweep green and made the instrument-backed sweep fail with `does not fire on its own positive witness`. Also scanned the test target against itself: 13 shared names across 46 declarations -> 0 duplicates across 3,394 tests. The wrong-`struct` trap is not closed mechanically -- see [[T-465]].**

- [T-367] **Global Cmd+Z on the model context is either a feature or a hazard, and nothing says
  which.** P3, source measured, runtime behaviour not measured. The macOS root installs an
  `UndoManager` on the shared `ModelContext` and routes non-text Cmd+Z/Cmd+Shift+Z into it, while
  destructive copy elsewhere tells the user "This cannot be undone." Editor undo is correctly scoped
  to the text view. **Decide:** if global model undo is real, pin what it may undo; if not, remove
  the root fallback. Do not leave it undecided — the current state means neither the code nor the
  copy can be trusted.
  **Closed 2026-08-29 **as a removal, not a fix.** `modelContext.undoManager = UndoManager()` is gone from `macOSRootLifecycleSupport.handleAppear` and `case 6:` is gone from the Cmd-key table, so Cmd+Z falls through to `default: return event` and `NSTextView` keeps its own undo. Reasons: one shared `ModelContext` across every surface; destructive paths pair store writes with effects (EventKit, notifications, file removal) that no undo stack saw; the "This cannot be undone" copy already contradicted it. A headless measurement -- recorded as a bound, not as the app's behaviour, since there is no run loop -- had `canUndo` true while `undo()` left a deleted row deleted and removed an edited row rather than restoring its title.**

- [T-414] **`subGoalCount` and `habitCount` have the same naming defect [[T-388]] just fixed.**
  They report own-only numbers under names that read like totals. Left alone deliberately so the
  breaking wire change stayed one rename rather than three — but the DTO is now half-renamed, and a
  half-applied convention is worse than either end state. Close it before it ossifies.
  **Closed 2026-08-29. `subGoalCount`/`habitCount` -> `ownSubGoalCount`/`ownHabitCount`, matching [[T-388]]; arithmetic untouched. Wire-key test pins all four new keys present and all four old keys absent. Breaking bump 0.5.0 -> 0.6.0.**

- [T-415] **The MCP page slice still happens in memory.** From [[T-384]]: `taskSort` and
  `CadenceMCPOrdering` both end on `id.uuidString`, `UUID` is not `Comparable`, and `isDone` is
  computed — so `offset`/`limit` cannot be pushed into the store's sort descriptor and the rows are
  still materialised before being sliced. Reads are far narrower now, but the last hop is unchanged.
  **Closed 2026-08-29 as **a documented limit, not a fix** -- see `[X-09]` in the Cancelled section. The ticket's stated reason was wrong (`UUID` *is* `Comparable`), but three real blockers stand.**

- [T-433] **`CadenceListDeletionSummary` says its counts "mirror
  `ModelContext.deleteArea/deleteProject/deleteContext` exactly" and omits the image sweep all
  three of them run.** Found while fixing [[T-423]], which was the same defect one summary over.
  The struct counts tasks, notes, links, projects, areas, goals and habits; it has no `images`
  field at all, while every cascade it mirrors ends in `deleteUnreferencedMarkdownImageAssets`. So
  deleting an area holding twenty image-bearing notes destroys those `.externalStorage` bytes with
  the confirmation saying nothing about them — and the note confirmation beside it *does* say
  "N embedded images", so the two disagree about whether images are worth mentioning.
  The arithmetic is now available: `CadenceNoteDeletionSummary.forNote` reads it through
  `CadenceMarkdownSourceInventory.liveMarkdownTexts(in:excludingNoteIDs:)`, and the list version is
  the same call with every doomed note's id in the exclusion set. Two things to settle first,
  though, which is why this is filed rather than done: the list summaries are computed from model
  objects with **no `ModelContext` parameter** (`forArea(_:)`, `forProject(_:)`, `forContext(_:)`),
  so the signature has to change the way `forNote` already has; and the cascade counts are exact
  today, so adding a count that can be a floor means porting `hasUnknownImpact` across too, or the
  new number silently breaks the "may not over-promise" rule the whole file is built on.
  Fix the doc comment's "exactly" in the same pass either way.
  **Closed 2026-08-29. `CadenceListDeletionSummary` gains `images` and `hasUnknownImpact`; `forArea/forProject/forContext` now take `in modelContext:`; the doc comment's "exactly" is retired. The amber unknown-impact row is now one shared `iOSDeleteUnknownImpactRow` across both sheets.**

- [T-445] **`DataIntegrityRepairReport` is a synthesized `Codable`, so adding a counter makes the
  stored report undecodable.** Synthesized decoding does not apply property defaults for missing
  keys, so `lastReport.v1` written before a new field cannot be read after. `lastReport()` swallows
  it with `try?`, so nothing breaks — but the diagnostic is lost, and `repairAndRecordFailure`
  returns `nil` on exactly the launch that meant to hand back the last good report. **Second
  occurrence** — T-359 added the first counter, T-428 the second. One `init(from:)` using
  `decodeIfPresent` closes it. Not data loss; no user data lives in that key.
  **Closed 2026-08-29. `nonisolated extension DataIntegrityRepairReport { init(from:) }` with `decodeIfPresent(...) ?? 0` per counter; the four head fields stay `decode`. An extension rather than the struct body, so the memberwise init survives. `nonisolated` matters: the first spelling warned that the `Decodable` conformance crossed into main-actor code -- invisible to the MCP scheme, the one target without `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.**

- [T-287] **The `~` list-search panel is implemented twice on macOS.** From the [[T-123]] split.
  `CLAUDE.md` already records this as "a standing violation of the 'one shared component over
  near-copies' rule, recorded here so it is not mistaken for a deliberate split" — and it has never
  been a ticket, so it has stayed standing. `macOS/Views/QuickCreateChoicePopover.swift` carries
  `tildeFlatContainers` (288), `selectTildeContainer` (318), `selectTildeContainerItem` (324),
  `clampTildeHighlight` (416) and its own `TildeContainerItem`; `macOS/Views/TaskTitleEntryField.swift`
  carries the same five under the same names plus `TaskTitleTildeContainerItem`. They share
  `TildeContainerPickerRow` and nothing else — including the silent `normalizeSelectedSection()`
  that both must perform after a container change, which is the half most likely to be fixed in one
  copy only.
  Done: one panel — the container list, the highlight arithmetic, the selection and the section
  normalisation — read by both the title field and the drag-create popover, one item type, and a
  test that fails if either file re-declares `tildeFlatContainers`.
  **Closed 2026-08-29. The two copies had diverged and the difference was a **bug, not a distinction**: `TaskTitleEntryField` restored the literal `~query` on Escape and on backspace-at-empty, and `QuickCreateChoicePopover` had neither, so the only way out of the drag-create panel was to pick a list -- Escape fell through to the enclosing popover and discarded the draft. `TildeContainerPicker` is one panel, one item type, one `applySelection` carrying the section renormalisation, replacing ~400 lines across two hosts and following the `TaskTitleInlineTagPicker` precedent [[T-123]] set for `#` and never applied to `~`. A third open-coded `normalizeSelectedSection` in `CreateTaskSheet` went with it.**

- [T-372a] **`CadenceSearchMatcher.rank` is the one ordering left partial after [[T-372]].** Found
  while fixing T-372 and deliberately not fixed there: `rank` ends at score-then-title
  (`Shared/CadenceSearchMatcher.swift` lines 27-30), so two hits with the same score and the same
  title — two tasks called "Admin" in two contexts, a duplicated saved link — come back in fetch
  order. It is the *shared* matcher, so the MCP `search()` tool and the macOS/iOS search surfaces
  all inherit it, and closing it means threading an identity closure through every `rank` call
  site rather than the one-file change T-372 was. Scoped out to keep the MCP fix reviewable; the
  fix shape is the same `id` tail `CadenceMCPOrdering.precedes` now uses.
  **Closed 2026-08-29. The ticket was one revision stale: T-372 had already added the `identity` leg, but as an **optional** parameter that neither remaining caller passed, so `search_cadence` and `Cmd+K` both still stopped at title. `identity` is non-optional on both overloads now -- an optional tie-break is one the next call site silently declines. MCP ties on `entityType:entityId` (eleven scope loops over eight tables, so the type has to be in it); macOS on the category-prefixed result id. The pre-existing tie-break test **could not see a score/title swap** -- its fixture agreed on both tiers -- so the new one uses a fixture where every pair disagrees on exactly one tier while the tiers below point the other way.**

- [T-442] **The macOS note-template editor is a bare `TextEditor` while iOS gets the full markdown
  surface.** An unrecorded parity gap, and the reason T-421's fix is iOS-only: macOS never had an
  image door to close.
  **Closed 2026-08-29. `SettingsTemplatesSection`'s Body field is `MarkdownEditor(allowsImageInsertion: false)` rather than a `TextEditor` -- macOS's own shared surface, not a port of the iOS view, whose format toolbar and photos picker are phone chrome. **One flag reaches all four macOS image doors where iOS needed three guards**, because the panel, paste and drop all funnel through `onCreateMarkdownImages`. The `/image` refusal became `MarkdownSlashCommand.refusingImageInsertion`, now read by both platforms instead of open-coded twice ([[T-374]]). Also answered the inventory question: the template body **cannot** be a `CadenceMarkdownSourceInventory` case -- all seven cases are stored `String`s on `CadenceSchema` models reached by a `ModelContext` fetch, and a template body is JSON in `UserDefaults`. That is now a value assertion rather than prose.**

- [T-451] **`CadenceNotesListSupport` re-types the eyebrow's `0.8` as a literal.** Residue from
  [[T-284]]. The notes group header (`.kerning(0.8)`, line ~656) is *not* an eyebrow — it is bold,
  sentence-case, `Theme.text`, at 11/12pt — so folding it into `SectionEyebrowLabel` would be the
  size-decision-dressed-as-a-refactor that ticket refused twice. But 0.8 is the standard tier's own
  number, hand-typed, and it is now the only copy of it left outside `Theme`-adjacent metrics.
  Decide whether that header's tracking is its own decision (and say so beside it) or the eyebrow's.
  **Closed 2026-08-29. The heading reads `SectionEyebrowLabel.Size.standard.kerning`. It takes the tier's **setting**, not `kerningRatio x headerLabelSize`: the ratio was derived over 10/9pt uppercase runs and this heading is bold sentence-case at 11/12pt, so re-deriving would silently retrack it to 0.88/0.96 with nobody having looked -- the un-inspected change [[T-452]] is already open for. Value-preserving. The ticket's "only copy left" was off by one; see [[T-476]].**

- [T-463] **`CadenceTests/CadenceCalendarLinkHealthTests.swift` was a directory containing a file of
  the same name.** A staging error of mine, now flattened. It compiled and ran — the synchronized
  root group descends into it — which is why nothing caught it. Worth a guard: a `.swift` path that
  is a directory should fail the build, not quietly work.
  **Closed 2026-08-29. Already flattened by `193f257`; verified at HEAD as a plain file, no directory-shaped `.swift` anywhere, and `project.pbxproj` never referenced the path. Two pieces of residue closed it out: the doc comment on `cadenceRepoSwiftFiles(under:)` still asserted in the present tense that the directory exists, and the guard the ticket actually asked for did not exist -- every walk skipped the shape *silently*, which is how the original survived a whole session. `noSwiftPathInTheRepositoryIsADirectory` now reports it across 688 files in five source roots.**

- [T-464] **The list-editor row can now say "(Hidden)" but the picker still offers only visible
  calendars.** From [[T-441]]. So the row names the problem and the repair is in Settings. Putting
  hidden calendars in the picker is a second decision, left deliberately.
  **Closed 2026-08-29. [[T-441]] taught the row four verdicts but left the popover over `availableCalendars`, so the row could say "Team (Hidden)" over a menu with no Team in it and the only reachable move was "None" -- the silent overwrite T-441 exists to prevent, performed by the user instead of the code. The offer is now visible-plus-the-linked-one: exactly one hidden calendar can appear, and only because it is already stored, so no new hidden link can be made here. `CadenceCalendarLink` holds the three inputs once and answers both `rowState` and `pickableCalendars`, and `hiddenTitle(_:)` is the one spelling of "(Hidden)", so the two surfaces cannot form separate opinions or word it differently.**

- [T-465] **A test can be declared in the wrong `struct` and no assertion can catch it.** This is the
  one shape [[T-161]] did **not** close mechanically: a test that belongs to the calendar suite but
  is declared inside the deletion suite compiles, runs, and passes. Nothing can compare a test's
  location against its author's intent. `scripts/test-suite-index.sh` prints suite -> test names for
  review; the ask here is a periodic read of that output, not a guard. Filed rather than solved so the
  gap is written down instead of assumed closed by T-161.
  **Closed 2026-08-29 -- one arm mechanically, the other explicitly refused. **Closable:** a `@Test` past the last suite's closing brace is a free function, invisible to `-only-testing:`, so every mutation against it reads as a survivor -- and both `cadenceTestDeclarations` and `scripts/test-suite-index.sh` attributed it to the suite it had just escaped. Attribution is by suite **extent** now, held at zero by `noTestInTheTargetIsDeclaredOutsideEverySuite` through a `CadenceScanInstrument` sweep, no allowlist. **Not closable:** a test in the wrong *sibling* suite. Measured before deciding, so nobody re-derives it -- the best heuristic flags 13 tests on a clean target, all 13 hand-read as correctly placed, and catches 43.3% of 1,643 simulated misplacements (47.5% missed, 9.2% undecidable). Zero precision at under half recall is not a guard. That arm stays a periodic read of `scripts/test-suite-index.sh`. Known false-positive shape for the guard that did ship: `extension SomeSuite { @Test ... }`, of which the target has none -- widen the regex rather than allowlist a file.**

- [T-466] **`NoteMigrationReport` is [[T-445]] untouched.** Same synthesized-`Codable` shape: adding a
  counter makes every previously stored report fail to decode, so the history silently empties. T-445
  fixed `DataIntegrityRepairReport` with a `nonisolated extension` and `decodeIfPresent(...) ?? 0` per
  counter, plus a test that removes each key in turn. Apply the identical treatment here. Note the
  actor-isolation trap T-445 hit: the naive spelling warns only under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which the MCP scheme does not set, so an MCP-only build
  reports zero warnings on broken code.
  **Closed 2026-08-29. `nonisolated extension NoteMigrationReport { init(from:) }` with `decodeIfPresent(...) ?? 0` for all fourteen counters; the four head fields stay `decode`. Impact was wider than the app: `CadenceMCPToolDefinitions.diagnostics` defaults `noteMigrationReport:` to `NoteMigrationService.lastReport()`, so an MCP client read *never migrated* instead of *unreadable*. The `nonisolated` trap was reproduced, not assumed -- dropping it warns that the `Decodable` conformance crosses into main-actor code, at 0 errors.**

- [T-482] **Free-function `@Test` was misattributed by both [[T-161]] parsers.**
  **Closed 2026-08-29, fixed as a prerequisite of [[T-465]].** `cadenceTestDeclarations` and
  `scripts/test-suite-index.sh` both used "nearest top-level type declared above", so a `@Test` outside
  every suite was reported as a member of the preceding suite — the index built to answer *"where did my
  test actually land?"* gave a confidently wrong answer for the single case it exists to catch, and
  `<file scope>` was unreachable in practice. **Did not affect**
  `everyTestFunctionNameInTheTargetIsUniqueAcrossSuites` (name uniqueness does not depend on suite
  attribution), and the target had zero such tests — a latent hole, not an active miss.

- [T-483] **`CadenceSourceScan.codeOnly` read a raw string's trailing backslash as an escape.**
  **Closed 2026-08-29, fixed as a prerequisite of [[T-465]].** On `#"photo\"#` the masker skipped the
  closing quote, ran to end of line and blanked live code — including the `{` opening the enclosing
  `for` body. Brace depth in `CadenceTests/MarkdownImageAssetServiceTests.swift` came out one short,
  which is why T-465's new guard first produced 11 false accusations. 45 test files use raw strings;
  exactly 1 desynced, because the desync needs a backslash immediately before the closing quote.
  **Did not affect** needle-counting scans, which is every existing scan — no shipped assertion changed
  verdict, and `scripts/test-suite-index.sh` output after both fixes is byte-identical to HEAD's.

- [T-435] **The target-membership guard matches capitalised identifiers, so a top-level `func` still
  slips through.** From [[T-409]]. It catches a type referenced across a target boundary, which is
  the shape `aaa0064` had, but a free function or an extension method declared in a non-member file
  is invisible to it. The honest close is building `-scheme CadenceMCPServer` in CI; the test is the
  cheap half.
  **Closed 2026-08-30. The hole was wider than filed: the declaration side matched only types and the reference side only capitalised identifiers, so a call like `monthStart(for:calendar:)` produces **no capitalised token at all** — the sweep read the line and saw nothing. The repo has 16 top-level `func`s, 14 non-private, none in either explicit-list target: every one invisible. Blindness proved directly rather than asserted — the same compiling mutation (an MCP file calling a free function it cannot compile) passes HEAD's guard at `EXIT=0`/0 errors and kills the widened one at `EXIT=65`/0 errors, naming the offending path. Driven through `CadenceScanInstrument` with a real unreachable free function as the positive witness. **Still open:** the ticket's own "honest close", building `-scheme CadenceMCPServer` in CI. Extension methods remain uncovered — see [[T-486]].**

- [T-436] **Two membership guards overlap and neither is redundant — say so before someone deletes
  one.** T-406's pins one symbol's build-phase membership *and* that the trim rule is spelled exactly
  once; T-409's covers every symbol across both explicit-list targets but does not check spelling
  counts. The widget half of T-409's guard is also a coverage demonstration rather than a kill: a
  real widget membership violation is a compile error under `-scheme Cadence`, so no compiling
  mutation can make that assertion fire.
  **Closed 2026-08-30 as documentation, both guards kept. They ask different *questions*, not different scopes: [[T-409]]'s asks reachability over the whole graph, [[T-406]]'s asks singularity and placement. Counting is outside T-409's vocabulary — a second declaration in a non-member file leaves the type reachable, so that sweep stays silent by design. Measured: re-forking the trim kills only `theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles` while all 6 membership tests and the behavioural trim pin stay green (two correct copies of a trim agree on every sample). Also recorded: `-scheme Cadence` builds `CadenceWidgets`, so a real widget violation is a compile failure before any test runs — that half is coverage, not a kill.**

- [T-469] **The iOS empty list detail names a control that is not on the screen** (Codex, P3, measured).
  `iOS/iOSListDetailView.swift:260` says "Add a task above or move one here from Inbox." There is no
  inline field above; the page uses the floating `+`. This repo has already made and fixed this exact
  mistake — `CadenceTodayPresentationSupport.emptySubtitle` says "Add a task with +..." and its comment
  records the retired "Add a task above" wording as the failure. Copy naming a control that does not
  exist is worse than no subtitle, and this is a *first* empty list. Fix the wording, consider one
  shared list-detail empty-state constant if the two surfaces should stay pinned, and add a source scan
  for the retired phrase.
  **Closed 2026-08-30. Same shared constants as [[T-473]]. The title deliberately avoids "yet" so it does not contain the retired "No tasks yet" as a substring.**

- [T-470] **iOS calendar quick-create swallows task-save failures and the button looks inert** (Codex,
  P2, measured). `iOS/iOSCalendarQuickCreateSheet.swift:542` guards on
  `try? CadenceTaskMutationSupport.insertScheduledTask(...)` and just returns, never writing the
  visible `actionError` notice — while the *same sheet* has a working red `actionErrorNotice` that its
  Event branch uses correctly (`:312`). The right pattern is already in
  `iOSCreateTaskSheet.create()`: catch, set `actionError = TaskCreationService.saveFailureNotice`,
  return before dismissing. Instance of [[T-322]]. Extend `CadenceCreateTaskCommitSurfaceTests` to
  cover this file.
  **Closed 2026-08-30. `createTask()` uses `do`/`catch` in the shape of `iOSCreateTaskSheet.create()`: a refused insert sets `actionError = TaskCreationService.saveFailureNotice` and returns before the reconcile and `dismiss()`. The `nil` answer — a title with nothing to make a task from, unreachable because `canCreate` requires a non-empty title — stays a silent return but no longer dismisses. That separation of *throw* from *nil* was not in the ticket.**

- [T-471] **iOS calendar quick-create dismisses as success when a bundle insert fails** (Codex, P2,
  measured). Worse than [[T-470]]: `iOSCalendarQuickCreateSheet.swift:595` does
  `_ = try? CadenceTaskMutationSupport.insertBundle(...)` and dismisses regardless, so the sheet closes
  as though a block was created. `CadenceTaskMutationSupport.swift:798` already does the right thing —
  it deletes the pending bundle and rethrows — and the caller throws that signal away. `dismiss()` must
  happen only after the `try` succeeds. Instance of [[T-322]].
  **Closed 2026-08-30. `dismiss()` is reachable only through the `try` succeeding; a throw sets the new shared `CadenceTaskMutationSupport.bundleSaveFailureNotice` ("Couldn't save this block.") and returns. The Block branch needed its own sentence — all five existing failure constants name an object this branch was not making, and a `TaskBundle` is a *block* in every user-facing string. Held beside the mutation that throws it, not spelled at the sheet, per that sheet's own rule against "a third spelling of 'that didn't work'". No "Nothing was created." clause: the create family does not carry one and the delete family does, and that asymmetry is now pinned.**

- [T-473] **The macOS list-detail Tasks tab still ships copy [[T-285]] retired** (Codex, P3, measured).
  `macOS/Views/ListDetailComponents.swift:68,103` says "Create a task to get started" while the actual
  affordance on that screen is the floating `+` bottom-right. T-285 removed exactly this wording from
  the macOS Tasks page and pinned it — but **the existing test only covers `TasksListView.swift`**,
  which is why this copy survived. Same family as [[T-469]] on iOS. Replace the subtitle with copy that
  names the reachable control, and widen the scan to `ListDetailComponents.swift`.
  **Closed 2026-08-30 by the repo-wide sweep rather than a second per-screen assertion. Reads `CadenceEmptyStateCopy.listDetail*`, shared with [[T-469]] so the two surfaces stay pinned to one sentence.**

- [T-474] **The iOS reset says the account was deleted, and iOS has no account** (Codex, P2; measured
  source plus a contradiction with a shipped doc). `iOS/iOSDataResetSettingsSection.swift:15,89`
  correctly explains that Sign in with Apple is macOS-only and "there is no account profile to clear
  here" — then, on success, prints the shared
  `PrivacyDataResetOutcome.statusMessage`: *"Cadence account and data were deleted."* The success
  message claims more than the action performed. The pre-action button on the same screen is already
  right ("Delete Cadence Data", not "Delete Account & Data"), and `docs/app-review-notes.md:23,36`
  distinguishes macOS account deletion from iOS data deletion — so the shipped notes and the shipped
  UI disagree. Keep one deletion sequence; split only the presentation sentence
  (`dataOnlyStatusMessage` / `accountAndDataStatusMessage`). Pin both, and assert the iOS success state
  does not contain "account". This is the error-message-accuracy class that
  [[T-374]]'s brief called out: a notice promising something the code did not do.
  **Closed 2026-08-30. `PrivacyDataResetOutcome` splits into `dataOnlyStatusMessage` (iOS) and `accountAndDataStatusMessage` (macOS); one deletion sequence, two presentation sentences. **The ticket found one instance and there were two** — the iOS *section label* was also "Delete Account & Data", the same claim one control earlier on the same screen, now "Delete Cadence Data". No live drawn string in that file names an account in any casing. No conflict with `AppStoreReviewReadinessTests` — its assertion reads the macOS pane, which keeps the wording — and `docs/app-review-notes.md` needed no edit: the shipped UI now agrees with it.**

- [T-475] **`TaskSectionConfig` is the third [[T-445]] shape and the first that loses real user data.**
  `Cadence/Models/AppTask.swift:9` — five defaulted properties (`uuid`, `colorHex`, `dueDate`,
  `isCompleted`, `isArchived`), persisted as JSON in `Project.sectionConfigsRaw` /
  `Area.sectionConfigsRaw`, decoded with `try?` at `Models/Project.swift:113` and
  `Models/Area.swift:112`. Adding a sixth property makes every stored section list undecodable; the
  getter then falls back to `sectionNamesRaw`, which keeps only the **names** — colour, due date,
  completion and archive state are silently dropped — and the setter rewrites `sectionConfigsRaw` from
  that degraded list on the next write, **making the loss permanent**. Unlike T-445 and [[T-466]] this
  is user data, and it is in `Models/`, which compiles into every target. Wants the `init(from:)`
  treatment plus a round-trip test *before* anyone adds a field. **Highest-priority open ticket.**
  **Closed 2026-08-30, **and the ticket's stated cause was already fixed**. `TaskSectionConfig.init(from:)` with `decodeIfPresent(...) ?? default` per field exists at HEAD, added by `7dddba8` — so "adding a sixth property makes every stored section list undecodable" was false when filed. The *second* half was real and is the half that loses data: `[TaskSectionConfig]` decoding is all-or-nothing, so one column with no `name`, a `null`, or a wrong JSON type drops the whole array to `sectionNamesRaw` — names only — and the setter writes that back permanently. Fixed with element-wise salvage (`StoredList` `.clean`/`.salvaged`/`.empty`): readable columns keep `uuid`/`colorHex`/`dueDate`/flags, unreadable ones recover by name. **No stored property added, removed or retyped** — the only model-file changes are an extension on the non-`@Model` `TaskSectionConfig` and two computed-property bodies.**

- [T-480] **`NoteMigrationServiceTests` leaves a fabricated migration report in the test host's
  `UserDefaults`.** 20 call sites reach `migrateIfNeeded` / `migrateAndRecordFailure`, each calling
  `record(...)` which writes `noteMigration.lastReport.v1`; only one test saves and restores it.
  `DataIntegrityRepairServiceTests` already guards this ("so a test run cannot leave a fabricated report
  behind for the app to read"), so the convention exists and this suite predates it.
  **Closed 2026-08-30, wider than filed: the suite pollutes **two** keys, not one — `noteMigration.lastReport.v1` and `dataIntegrityRepair.lastReport.v1`, measured before any change. The guard is a recursive `@Suite(.preservesTheStoredLaunchReports)` trait in the existing `TemporaryDefaultsSupport.swift`, and the one hand-rolled guard it made redundant is gone. Proved by hashing the whole stored value out of the test host's plist either side of a scoped run: guard removed → CHANGED, `isRecursive` false → CHANGED, as written → unchanged. See [[T-485]] for the three sibling suites that still leak.**

- [T-282] **The iPad's corner `+` carries the same palette, pointing the only way it can.**
  **VERIFIED 2026-08-26 — keep open. The value half is strongly pinned; the device run still has not
  happened.** Four mutations caught, including unifying the corner arc and weakening the drag arm,
  and the old system-drag path is gone with zero live references. Placement is pinned as
  *deliberately different* in both directions.
  Still outstanding, and it is the one thing the ticket was left open for: **nobody has driven an
  iPad.** The verifier was blocked all session — both booted simulators were held by live agents,
  and the claim script correctly refuses to reclaim a device with live operations on it.
  One specific risk only a device answers: `iOSCaptureRadialMenuOverlay`'s own comment says it sits
  at the **shell's** level so a palette is not clipped by a 46pt bar row — but on iPad the host is
  applied to the page's content, not the shell. The arc opens up-and-left so it probably clears.
  "Probably clears" is what a simulator run is for.
  From the [[T-73]] / [[T-170]] split, and the one genuine "control present at one width and absent
  at the other" that audit found. [[T-171]] had shipped the hold-for-palette gesture on
  `iOSCaptureRadialMenuButton`, whose **only** caller was `iOSCompactTabShell` — so holding the
  centre `+` on iPhone offered `CadenceCaptureAction`'s three segments (Task / Event / Note) and a
  drag onto a drop target, while the iPad's corner `+` (`iOSFloatingCreateTaskButton` →
  `iOSCircularAddButton` + `.iOSNewTaskDragSource`) tapped straight into `iOSCreateTaskSheet` and
  could capture nothing but a task. **Confirmed against the source before any of it was rebuilt.**
  The corner button now renders that same `iOSCaptureRadialMenuButton`.
  **What stayed different, deliberately, is the arc — and only the arc.** A button 50pt from the
  trailing edge cannot draw a semicircle: two of its three segments would be off the display. So
  `CadenceCapturePalettePlacement` gives `.bottomTrailing` a quadrant opening up and to the left,
  and a wider `layoutRadius` because three tiles packed into 90° instead of 180° would otherwise
  overlap — the tile width is published now so that claim is a test rather than a taste. The hold
  delay, the drag slop, the dead zone and the margins the outer and escape rings keep past the tiles
  are all the *same value*, asserted field by field.
  **The three outcomes do coexist on that button, and the reason is the reason T-171 gives.** The
  iPad's `+` carried a system `.onDrag`, and `UIDragInteraction`'s lift *is* a ~350ms long press —
  the same window the palette wants — so the two could never have shared a touch. It carries
  `CadenceCapturePressResolver`'s one `DragGesture` instead, exactly as the phone's does. Verified
  on a booted iPad simulator: press-and-move drags, press-and-hold opens the palette, and moving
  inside the radius slides between segments.
  **Two things went with it rather than being left beside it.** The system drag lost its last
  source, so `iOSNewTaskDragSource`, the drop target's `.onDrop`, `CadenceTaskDropPayload`,
  `CadenceTaskDropCoordinator` and `UTType.cadenceNewTaskDrag` are deleted — a sourceless second
  path into the same insertion ghost is how a comment ends up claiming "two mechanisms, on purpose"
  about one. And the three composers a finished press can ask for moved out of `iOSCompactRootShell`
  into `.iOSCaptureHost(_:)`, which both placements apply, because copying that routing to the iPad
  is the near-copy this repo keeps paying for.
  `iOSCircularAddButton`'s doc comment claimed the two buttons were "the same action in deliberately
  different *places*" while they were not. It now says which parts are shared (the face, the gesture,
  the composers, the feel) and which the placement chooses (the diameter, the corner inset, the arc)
  — and the `Button` wrapper of that name is gone, the name having moved down to the circle it
  always described.
  **Closed 2026-08-30 **from source, without a device**. The ticket's one open item was whether the palette is clipped. There *is* a clip — `iPadMacStyleRootShell` applies `.clipped()` to the detail pane and the capture host is inside it — and the arc clears it provably: every corner tile stays within 50pt of the button centre, the tightest sitting 54.5pt inside the page's trailing edge. Pinned by `theCornerPalettesTilesFitInsideTheButtonsOwnCornerInset`, arithmetic over the real shared metrics. **Take this out of the device-blocked group.** Two residues filed: the scrim does *not* clear the clip ([[T-491]]), and this ticket contradicts itself about whether an iPad was ever driven — the top says nobody has, the historical section describes a booted iPad simulator session.**

- [T-446] **Two "pick a context" controls with nothing shared underneath.** Residue from [[T-288]],
  which named `CadenceContextPicker` "the one with a live counterpart to converge on" and then had
  to move it instead. The move is correct and the convergence is still owed.
  What was found: the macOS control is keyboard-first — `onMoveCommand` (macOS/tvOS only), a search
  field that takes focus on appear, an arrow-driven `highlightIndex`, an `onSubmit` that commits it,
  and a hover wash on every row. None of that fires on iOS, and unfencing the file would have put a
  list with a permanently-raised keyboard in front of the next iOS reader. The two iOS sites
  (`iOSListEditorViews.swift:124`, `iOSTrackingEditorSheets.swift:167`/`:385`) already route through
  the `iOSChoiceRow` / `iOSChoicePopoverList` idiom, which is the touch answer to the same question.
  So the duplication is real but it is not a *view*: it is `sortedContexts`, the `localizedLowercase`
  filter, the `allowNone` "No context" row and the flattening — spelled once in
  `CadenceContextPickerList` and again, differently, at each iOS site.
  Done: one shared item model + filter (a `CadenceContextPickerSupport` beside the other
  `Cadence*Support` types), read by `CadenceContextPickerList` and by both iOS popovers, with the
  presentations left as the two they legitimately are. A test that fails if either platform
  re-derives the sort or the filter.
  **Closed 2026-08-30, **and the four spellings had diverged into a defect**. `Cadence/Shared/CadenceContextPickerSupport.swift` owns the sort, the archive rule, the unnamed fallback and the "none" row; the macOS list and all three iOS popovers read it, and the two presentations [[T-288]] refused to merge stay two. What the divergence actually was: `Context.isArchived` is excluded everywhere a context is *offered* — both sidebars, both settings panes, the MCP default — but only one of the four pickers filtered it, so **archiving a context did not stop you picking it fresh** on three surfaces. And the one site that did filter read its button label out of the *filtered* array while `save()` read the *unfiltered* one, so a project whose context had since been archived **displayed "None" and saved the archived context**. Also fixed: equal `order` resolved differently per platform (macOS broke ties on name, iOS relied on `@Query(sort:)` alone, which promises nothing among equal keys — and `order` defaults to 0, so every context created outside the reorder UI ties), and an empty name rendered three ways. Rule landed: hide what you could newly pick, never the one already assigned.**

- [T-449] **The last painted-under hairline is in `SettingsListManagementSections.swift`, and the
  sweep names it rather than allowing it.** Residue from [[T-286]]. That file was outside this
  batch, and it still carries the two-line `Divider().background(Theme.borderSubtle)` (calendar
  rows) plus a `.stroke(Theme.borderSubtle` well — the same two defects the other seven panes just
  lost. `noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak` skips exactly this one path by
  name, so the hole is one line of test source and closing it is one line of view source.
  **Closed 2026-08-30. Both calendar-row hairlines read `CadenceRowDivider(leadingInset: 44)`; the named exclusion is gone and the sweep scans all 15 settings panes. The exact-count pin for that file went 5 → 7, so reverting either site alone fails. **The ticket's second half is withdrawn**: the cited `.stroke(Theme.borderSubtle)` is a 28x28 menu glyph, not a typed-value well — `cadenceSettingsWell()` would force a min-height and 12pt of leading air, both wrong for a fixed glyph, and 28 other sites spell it the same way. See [[T-489]].**

- [T-450] **`SidebarTabEditorSheet.settingsPanelRow` is a fifth private settings row.** Residue from
  [[T-286]]. A title over a subtitle with a trailing accessory, on its own `cadenceCard` — which is
  `CadenceSettingsNoticeRow` minus the state glyph. It was left alone deliberately: inventing a
  glyph to reach the shared component would put a verdict on a sheet that reports none. Either the
  notice row grows an optional glyph or this row keeps its own spelling on purpose; it should not
  stay undecided.
  **Closed 2026-08-30. `CadenceSettingsNoticeRow.systemImage` is optional, `SidebarTabEditorSheet` reads the shared row, private `settingsPanelRow` deleted. [[T-286]]'s reason for keeping it was right about the glyph and wrong about the outcome: the private copy had already drifted to an **11pt subtitle where the other four say 12** — including the identity block twenty lines above it in the same sheet. Cosmetic divergence, but drift rather than decision, which is what settled the either/or.**

- [T-472] **The markdown toolbar has tooltips but no accessibility labels** (Codex, P2; source shape
  measured, the VoiceOver announcement itself inferred — the app was not launched). Every icon-only
  button in `macOS/Editor/MarkdownEditorView.swift` (`:203`, `:210`, `:333`, `:354`, `:375`) passes a
  good semantic string — "Bold", "Inline code", "Note link", "Task reference" — to `.help(...)` and
  nothing else, so assistive tech falls back to a symbol-ish or generic description. **The correct
  pattern already exists**: `macOS/Views/CadenceButtons.swift:109`, where `CadenceIconButton` applies
  `.accessibilityLabel(...)` *and* `.help(...)` from one string. Instance of [[T-374]]. Add the label
  to `MarkdownReferenceMenuButton`, `MarkdownToolbarButton`, and also `MarkdownToolbarTextButton` —
  the last one has visible `H1`/`H2` text, but the accessible name should be "Heading 1"/"Heading 2".
  Pin it with a source scan so a tooltip-only regression fails.
  **Closed 2026-08-30. All three markdown toolbar button types apply `.accessibilityLabel(...)` and `.help(...)` from one stored property — `CadenceIconButton`'s shape. **The durable half is the rename**: that property is called `accessibilityLabel` rather than `help` at all 19 call sites, because a parameter named `help` is what tells the next author the string is tooltip-only. Heading buttons are named "Heading 1"/"Heading 2" against visible `H1`/`H2`; `.accessibilityLabel` *replaces* a label's text rather than appending, so that is substitution, not double announcement. **What is verified is that the label is set** — nothing launched the app, so no claim is made about what VoiceOver announces. Ticket line numbers were one revision stale.**

- [T-477] **`SectionEyebrowLabel`'s doc comment names a type that does not exist.**
  `Shared/Components/SectionEyebrowLabel.swift:18` explains its `nonisolated` members by reference to
  "`CadenceEyebrowMetrics`' readers"; `rg CadenceEyebrowMetrics` returns exactly that one line in the
  repo. Stale prose from [[T-284]]'s conversion — the reasoning is still right, the name is not.
  **Closed 2026-08-30, **conclusion reversed on measurement**. Stripping `nonisolated` from all three `Size` members builds clean for the app *and* for `CadenceTests`, so the annotation is **not** load-bearing there: the target sets `SWIFT_APPROACHABLE_CONCURRENCY`, and every live `Size` reader is main-actor already. The static `SectionEyebrowLabel.fontSize` **is** load-bearing, for the `nonisolated struct CadenceTaskGroupHeadingMetrics` — which is the true statement the stale sentence was a corrupted copy of. Annotation kept, rationale corrected, and `theEyebrowDocOnlyNamesMetricsTypesThatExist` now stops this file's prose naming a type nobody can grep.**

- [T-478] **The macOS editor shows a copy cursor for an image drop it will refuse.**
  `MarkdownEditorView.updateNSView` calls `registerForDraggedTypes([.fileURL, .tiff, .png])`
  unconditionally and `CadenceTextView.draggingEntered` answers `.copy` for any image payload, so at a
  host with `allowsImageInsertion: false` ([[T-442]]) the cursor promises a capability the host has just
  declined, then `performDragOperation` falls through to `super`. The fallthrough is the safe direction,
  so this is cosmetic — but it is a control stating something untrue. Thread the flag into the
  representable.
  **Closed 2026-08-30. `allowsImageInsertion` now reaches the drop — the one image door [[T-442]] missed. `draggingEntered` delegates to `markdownImageDropOperation(for:)`, which returns `nil` (deferring to `super`) unless the host allows images *and* the pasteboard carries one, and `.tiff`/`.png` are registered only at an allowing host. `.fileURL` stays registered on both paths deliberately: it is not image-specific, and the operation rule already answers the dragged-image-file case. The verdict was split out of `draggingEntered` so it could be driven with a private `NSPasteboard`, since `NSDraggingInfo` is a protocol with a dozen members this decision does not read.**

- [T-484] **Visible settings toggles carry no accessible label** (Codex, P3; source measured, VoiceOver
  behaviour inferred). The visible row text says what the switch controls, but the control is
  `Toggle("", ...)` plus `.labelsHidden()`, so the switch's own semantic label is disconnected from the
  title beside it — `iOS/iOSNotificationsSettingsSection.swift:38,49`,
  `macOS/Views/SettingsNotificationsSection.swift:29,32`, `macOS/Views/SettingsSupportViews.swift:329`.
  **The correct pattern is already in the repo**: `iOS/iOSCalendarSettingsSection.swift:457` and
  `macOS/Views/SettingsListManagementSections.swift:332` pass a real label, e.g. `Toggle("Active", ...)`.
  Instance of [[T-374]]; same family as [[T-472]]. Do Settings > Notifications on both platforms first,
  then sweep. **Leave zero-size hidden keyboard-shortcut buttons alone** — different mechanism, not a
  defect. Pin with a source scan for a visible `Toggle("", ...)` not paired with an accessibility label.
  **Closed 2026-08-30, **and the ticket listed 3 of the 5**. The sweep found two more: the habit reminder row and the AI task-draft checkbox, alongside Notifications on both platforms and the sidebar-visibility row. `.labelsHidden()` stays — it hides the label from layout, not from the accessibility tree — and `SettingsSupportViews` **gained** it, because it was the one site without it, so a named toggle there would have drawn the row title twice. Zero-size keyboard-shortcut buttons are untouched and untouchable by construction: the rule keys on `Toggle("",` and they are `Button`s. Verified that the label is set; no VoiceOver announcement measured.**

- [T-322] **Decide the rule for `try? save()`, then sweep — there are 133 of them.** Measured, not
  estimated: `try? modelContext.save()` / `try? context.save()` appears **133 times** across
  `Cadence/`. [[T-319]], [[T-320]] and [[T-321]] are four of them; [[T-291]], [[T-298]], [[T-307]]
  and [[T-315]] are the same shape found by four earlier audits in unrelated code.
  **This is a convention, not a set of bugs, and it should not be fixed with a sed.** Many of the
  133 are probably fine — a save whose failure the user cannot act on, or a transient object. What
  is missing is a rule saying which is which, so the next one is written correctly instead of
  found by the ninth audit.
  Proposed shape, to be decided: a save is allowed to swallow its error only when nothing visible
  depends on it. Any save whose failure would let the UI **dismiss, navigate, or report success**
  must throw and be handled. Then triage the 133 against that rule rather than converting them all.
  Write the rule into `AGENTS.md` when it is decided — a rule an agent reads before writing the
  134th is worth more than fixing the first 133.
  **Closed 2026-08-30. The rule is in `AGENTS.md` under "The `try? save()` rule", both halves enforced by `CadenceSaveCommitDisciplineTests`. **112 live sites, not 133** — that figure predates eight earlier conversions, and 15 matches are tombstone comments quoting the retired line. **96 of 112 (86%) pass and should stay `try?`**; converting them would be 96 `do`/`catch` blocks buying nothing. 16 condemned, 4 fixed worst-first, 12 carried in exemption lists **by function name** with a test that fails when an entry goes stale *or* when a new offender hides beside an allowed one. **The proposed rule needed a second half.** "A save whose failure lets the UI dismiss or report success" is caller-local, so it cannot see a *helper* that swallows while its caller dismisses — which is what [[T-471]] was. The **existence** half (the function also `insert`s or `delete`s) catches that from one function, with no judgement. **And the cost was misstated**: this app has one `ModelContext`, so a swallowed failure does not mean the change did not happen — it stays *pending*, committed by the next unrelated `save()` from any screen or discarded by the next unrelated `rollback()`. Swallowing is a coin flip resolved on someone else's code path. Worst fix: `saveGoal`/`saveHabit` ended `try? save(); return resolved` and **all three callers read non-nil as success and dismissed** — create a goal, sheet closes, goal gone. Remainder is [[T-497]].**

- [T-374] **The most common defect shape in 21 audits is "a correct shared helper exists and call
  sites don't use it" — enforce it mechanically.** Synthesis, not a new defect. [[T-359]] (four
  open-coded habit toggles), [[T-362]] (eleven unreconciled date edits), [[T-364]] (creation paths
  bypassing `TaskCreationService`), [[T-365]], [[T-343]] all have that shape, and each was found by
  a human-scale read that will not repeat reliably. `CadenceCreateTaskCommitSurfaceTests` is already
  the right instrument. Extend that source-scan pattern to habit completion, task date/time
  mutation, and delete commit — **after** each shared wrapper exists, not before, or the test
  becomes a brittle census of scattered call sites.
  **Closed 2026-08-30 — **one sweep shipped, two families measured and refused.** Shipped: `CadenceSharedConstantReuseSweepTests`, every `static let` string constant in `Cadence/Shared/` harvested *from source* rather than hand-listed, swept over all 552 files under `Cadence/` through `CadenceScanInstrument`, two target boundaries subtracted by rule, one measured exemption. **28 raw hits, 22 true positives of 23 verdicts (96%)**, all 22 fixed. **Refused with numbers:** 80 numeric constants in `Shared/` produce **10,745 hits** and are *unattributable* — 11 distinct constants each equal `1`, 11 equal `8`, 11 equal `10`, so a hit cannot name which constant it should have read; and verbatim-line duplication yields 496 candidates topped by `.frame(maxWidth: .infinity, alignment: .leading)` in 72 files, which is SwiftUI idiom, not a helper. Both numbers live in the test so the claim can be re-run rather than trusted. One user-visible change: 16 fixed sites stop using `.isEmpty`, which the shared helper documents as the wrong guard, so a whitespace-only task title now reads "Untitled Task" instead of rendering blank. **The sweep caught its own author's mistake** — a first pass "fixed" 5 sites in files the MCP target compiles, turning the membership guard red; those are now subtracted by rule using that guard's own graph.**

- [T-453] **`CadenceWidgetDateSupport.storageCalendar(inheritingTimeZoneFrom:)` has no callers.**
  Found by a mutation that **survived**: re-pointing it to return the caller's calendar changed
  nothing, because nothing calls it. Its sibling forwards to `DateFormatters.dateKey(from:calendar:)`,
  which forces Gregorian itself — so the widget is correct and this is a dead pass-through left
  behind when [[T-301]] collapsed the hand-rolled copies. Delete it or give it the one caller it was
  written for.
  **Closed 2026-08-30, **and the interesting version was true**. Not dead on arrival: `b49b76e` added `storageCalendar(inheritingTimeZoneFrom:)` *with* two callers inside the same enum, and [[T-301]]'s collapse in `0e78c5b` rewrote both bodies to forward to `DateFormatters`, leaving an uncalled forwarding shim. Deleted; the Buddhist/Japanese/Islamic-calendar history it carried is already on `DateFormatters.storageCalendar`, with a tombstone pointing there. Guarded by a **census** rather than a name check — every `static func` in `CadenceWidgetDateSupport` must be reachable, counted two ways so an unqualified in-enum call is not miscounted as dead — so the next collapse that strands a member fails here instead of waiting for a survived mutation.**

- [T-467] **`CadenceCalendarPickerButton` collapses "hidden or read-only" into "No calendar"** — the
  [[T-441]] bug on a second surface. It renders `selected?.title ?? "No calendar"` by looking
  `selectedID` up in whatever `calendars` it was handed, and `TimelineEventBlockSupportViews.swift:195`
  hands it `calendarManager.writableCalendars` (active AND `allowsContentModifications`). Events are
  fetched from `availableCalendars`, which does not filter by writability, so an event on a subscribed
  read-only calendar should reach the timeline and print its calendar name in `calendarLabel` while the
  Calendar row directly beneath says "No calendar" — two contradictory readings in one card. Route it
  through `CadenceCalendarLink` ([[T-464]]), which now exists for exactly this. **Reachability narrowed by a second audit (Codex, 2026-08-29, measured source flow):** the *hidden*
  case is **not** reachable — the timeline fetch uses `availableCalendars`, which already excludes hidden
  calendars. The reachable case is an **active read-only / subscribed** calendar: the timeline shows its
  events, the detail picker is handed `writableCalendars` (`TimelineEventBlockSupportViews.swift:195`),
  `selected` comes back nil and the row renders "No calendar"
  (`CadenceCalendarPicker.swift:230,248`; `CalendarManager.swift:159,164`). So fix the read-only case and
  drop the hidden framing. The QuickCreate call
  site (`QuickCreateChoiceSupportViews.swift:203`) is a create flow with `allowNone: false` and is not
  affected.
  **Closed 2026-08-30, **reachability confirmed independently first**. Two audits had disagreed; the second was right. Measured from source: `fetchEvents`/`fetchAllDayEvents` build their EventKit predicate from `availableCalendars`, and `isActiveCalendar` consults visibility **only, never writability** — so a hidden calendar's events never reach the timeline and **the hidden case cannot be opened in this editor**. The live case is an active read-only/subscribed calendar. The fact that made the fix clean: `availableCalendars \ writableCalendars` is *exactly* the active read-only set, so `.readOnly` is always the true word for whatever the offer adds back. Routed through `CadenceCalendarLink` with a new `CadenceCalendarLinkExclusion` (`.hidden`/`.readOnly`) — calling a read-only calendar "(Hidden)" would be the same collapse one word further down. The picker list and button take the link rather than a set of ids, so the button's value and the menu it opens cannot word the same calendar differently.**

- [T-468] **macOS silent push registration has two launch callers** (Codex, P3, source drift measured;
  the duplicate-OS-call risk is inferred). `CadenceApp.swift:13` and
  `macOS/Services/CadenceAppDelegate.swift:10,27` both call the same registrar on a normal launch.
  `registerIfNeeded()` checks `isRegisteredForRemoteNotifications`, so it may collapse to one OS call
  depending on timing — the defect is that the launch wiring is duplicated while docs and history
  describe the AppDelegate as *the* registration site, which is how a future launch audit or an App
  Review explanation gets subtly wrong. Not a permission-prompt bug: the app still correctly avoids
  `requestAuthorization()` on cold launch. Pick one owner (probably the AppDelegate), delete the other
  call, and pin **exactly one production caller** with a source scan. Confirm:
  `rg -n "registerIfNeeded\(|registerForRemoteNotifications\(" Cadence/CadenceApp.swift Cadence/macOS/Services/CadenceAppDelegate.swift`
  **Closed 2026-08-30 **with its limit stated**. `CadenceApp.init()`'s call is gone; `applicationDidFinishLaunching` is the sole owner, pinned by a body-scoped scan. **No double OS registration was fixed or claimed** — `registerIfNeeded()` guards on `isRegisteredForRemoteNotifications`, which only turns true after a completed round trip, so the second caller *plausibly* fired a second registration, but nothing in a test host can observe that. Unproven either way, exactly as the audit had it. Three things are pinned: exactly one qualified caller and it is inside that method; the registrar is the only thing in the app calling AppKit's `registerForRemoteNotifications()`; and cold launch still calls no `requestAuthorization`. The scan reads comment-stripped source, which is load-bearing — the new tombstone comment names the call it no longer makes, and a raw scan would count it as the second caller.**

- [T-476] **The iOS template editor's `BODY` label is the last hand-typed letterspacing in the app.**
  `iOS/iOSSettingsTemplateAndListSections.swift:594` — a hand-rolled `SectionEyebrowLabel`, so the fix
  is the component, which changes the weight from bold to semibold, and no macOS test target can render
  an iOS view to check the result. `exactlyOneHandTypedLetterspacingIsLeftInTheApp` names this path;
  closing it turns that expected list into `[]`. Also the last piece of [[T-442]]'s parity gap — macOS's
  template Body label is already `CadenceSettingsField`'s eyebrow.
  **Closed 2026-08-30. `SectionEyebrowLabel(text: "Body")`; `exactlyOneHandTypedLetterspacingIsLeftInTheApp` is now `noHandTypedLetterspacingIsLeftInTheApp` with an expected list of `[]`, plus a direct read of the site — an empty sweep and a sweep that stopped reading the file look identical. Size, tint, uppercasing and 0.8 tracking are value-preserved and asserted. **The weight goes bold → semibold and that result is unverified**: no macOS test target can render an iOS view. Somebody has to look at it on a phone.**

- [T-479] **The iOS search surface never adopted `CadenceSearchMatcher.rank`.** Found while closing
  [[T-372a]]. `iOSSearchView` scores through the shared `matchScore`, then sorts each of its seven
  sections with a bare `.sorted { $0.score > $1.score }` (`:105,123,172,199,230,245,261`) — no title
  leg, no identity leg. That is **more** partial than the state T-372 found macOS in, so two iPhone
  results that merely tie on score come back in `@Query` order, and T-372a's fix does not reach them
  because they never call `rank`. The shape is `GlobalSearchIndexSupport.rankedResults` — one funnel per
  surface passing `title:` and `identity:` — not seven threaded closures.
  **Closed 2026-08-30. **`iOSSearchResult.id = UUID()` was the real blocker** — a per-construction UUID *is* a total order, but a different one on every recomputation, so adopting it as the identity leg would have produced exactly the nondeterminism the leg removes while looking like a fix. `id` is a stable `String`, non-optional in the memberwise init ([[T-372a]]'s rule one level down). Also **six sections, not the ticket's seven**: `:123` is an idle-suggestion sort on dueDate-then-order, a different shape. Spellings live in a shared `CadenceSearchIdentity`, adopted by macOS's nine literals too, so the fix did not author a tenth hand-typed `"task-\(uuid)"`. Two are decisions: events tie on the **occurrence-scoped** identifier, deliberately against a neighbouring file whose prior leg is the start instant (this one's is the score, and a week of one standup scores and titles identically); and goals/habits both navigate to `.feature(...)` — the page, not the entity — which is why `id` is stored rather than derived. Idle-branch windows are [[T-498]].**

- [T-494] **Three retired `iPad*` names survive in agent-facing docs.** `docs/IOS_AGENTS_REFERENCE.md:129,318`
  and `docs/CLAUDE_REFERENCE.md:1149` still name `iPadTodayScheduleViews` and `iPadTodayView`.
  [[T-283]]'s retired-name sweep covers `Cadence/**/*.swift` only, so these are unguarded and **will send
  the next agent to files that do not exist**. Widen that sweep to `docs/`.
  **Closed 2026-08-30, **and the free answer is "nothing else"**. Three names fixed across the two references; the retired-name list is now one constant read by both the code sweep and a new doc sweep, so a fifth name cannot be added to one copy only. The widened sweep walks the root guides, every scoped `AGENTS.md` and `docs/`, minus the two ticket ledgers — excluded **by rule**, because an archive entry describing a rename has to spell the old name. Checked both failure shapes repo-wide: the only absent identifiers left are four **tombstones** — sentences that exist to say a type never existed — which must stay, and one frozen audit snapshot whose citations were deliberately not rewritten, since that would make the snapshot describe a tree it was not taken from.**

- [T-119] **Not reproduced — and the obvious fix breaks scrolling.** Reported by the drag sweep as a
  Week-view task block opening the Edit Task sheet after a 700ms press and 250pt of travel. Five
  gesture variants on HEAD — vertical both ways, horizontal, single-jump, diagonal — all scrolled the
  grid and opened nothing. That matches the construction: the block is a plain `Button`, which does
  not fire when released outside its bounds, and the grid's scroll views claim the pan first.
  The fix was built anyway and **regressed scrolling**: a `simultaneousGesture(DragGesture(minimumDistance: 0))`
  on scroll content claims the touch, so a plain swipe starting on a block stopped scrolling where
  HEAD scrolls. Reverted, helper and tests deleted.
  Most likely the original observation was the grid scrolling 1:1 under the finger — 250pt relative
  to the screen, none relative to the control. **Left open only as a warning**, not as work: it joins
  T-89 and T-14 as an observation whose mechanism was misattributed, and it should not be "fixed"
  without a fresh reproduction.
  **Closed 2026-08-30 **as unreproducible, with the argument made exhaustive**. There are exactly five `taskInspector(` call sites in `Cadence/iOS/` and only two on a Week surface: a stock SwiftUI `Button` (`.iosPressable` is a bare `ButtonStyle` over `configuration.isPressed`, installing no recogniser) and an `onTapGesture`. **`onLongPressGesture` does not appear anywhere in `Cadence/iOS/`.** A better-fitting explanation than the ticket's own: the two **bundle** blocks carry a `.contextMenu` whose single item is "Edit Block", and press-drag-release onto it is the documented way to invoke a context menu — bundle blocks sit beside task blocks in the same column at the same title size. Under that reading the reverted fix was suppressing correct system behaviour, which is consistent with it having broken scrolling. **No test added**: pinning an absence for an unreproduced observation is the shape this ticket warns against.**

- [T-336] **DECISION NEEDED: should the iPhone `+` inherit the page you are on?** From the same
  **ANSWERED 2026-08-26 by the user, and superseded by [[T-337]].** The question was whether the
  iPhone `+` should inherit the page. The answer is **neither button should** — context comes from
  the *drop target*, not from the page you happen to be standing on. That resolves this ticket and
  reverses the iPad's current page-seed at the same time. Keep this entry only as the record of how
  the question was framed; the work is T-337.
  audit, and filed as a question rather than a defect because **the current behaviour is deliberate
  and test-pinned**, which the audit established rather than assumed.
  The iPad's page-corner `+` passes a seed — Today seeds today's date, a list detail seeds that
  list. The iPhone's centre `+` is deliberately unscoped, and `CadenceCapturePaletteTests` asserts
  it carries no `baseSeed`.
  So this is only a ticket if the wanted behaviour is: tapping `+` from iPhone Today or a list
  should inherit that context. Note it sits beside the rule the user set for [[T-282]] — placement
  may differ across widths, capability may not — and a seed is arguably capability rather than
  placement. **Ask the user before touching it**, and if the answer is "leave it", record that here
  and close, because the test currently pins the opposite of what a reader might assume.
  **Closed 2026-08-30 as **stale bookkeeping — it was already answered, shipped and pinned.** The user answered on 2026-08-26: neither button inherits; context comes from the drop target, not the page you are standing on. [[T-337]] shipped it. `iOSCaptureRadialMenuButton` has **no `baseSeed` property at all**, so filling it back in from a call site is a compile error rather than a convention, and three tests in `CadenceCapturePaletteTests` pin it — including that the only route from page to new task is `CadenceCaptureSeedResolver.seed(...)` reading the drop target.**


- [T-498] **iOS search's *idle* suggestion windows are cut from a partial order.** [[T-479]] fixed the
  `isSearching` branches; the idle ones take `prefix` straight off a partial order in four of six
  sections — `taskResults` sorts dueDate then `order` (per-list, so cross-list ties are routine) then
  `.prefix(8)`; `listResults`, `noteResults`, `progressResults` prefix straight off `@Query` order. On a
  partial order the **window itself** is nondeterministic, not just its arrangement: tied rows past the
  cut are dropped by fetch order, so *which eight* suggestions appear changes between reads. `pageResults`
  (catalog order) and `eventResults` (already total, [[T-373]]) are fine. The fix is a final identity leg
  on each idle comparator, **not** the score funnel — an idle list is deliberately chronological/manual
  rather than scored.
  **Closed 2026-08-30. Four idle sections cut their window through `CadenceSearchSuggestionWindow.take`, which completes each section's **own** comparator with a `CadenceSearchIdentity` leg and **detects** ties rather than declaring them — under a strict weak ordering two rows are equivalent exactly when neither precedes the other, so there is no `Key` type and no second closure a call site could let drift. Deliberately **not** the score funnel, and the reason is written down: with no query every row scores 0, so ranking would re-sort all four idle lists to alphabetical and destroy the chronological/manual order they exist to show. `pageResults`/`eventResults` untouched — exactly one `.prefix(8)` survives in the file and it is the events one. The membership mutation is the load-bearing one: a bare `prefix` over the same fixture returns two different **sets** depending on input direction.**

- [T-499] **The MCP server target re-types three user-facing fallbacks it cannot read.**
  `CadenceReadService.swift:814,843,1069,1251` and `NoteReferenceSupport.swift:113` spell
  `"Untitled Task"`/`"Untitled Context"` because `Cadence/Shared/` is not in the `CadenceMCPServer`
  source list. Real duplication, not reachable duplication — **the app and the MCP surface can drift on
  user-visible copy.** Fix by moving `TaskTitleSupport.defaultDisplayTitle` and
  `CadenceContextPickerSupport.untitledName` to `Models/` (the [[T-354]] boundary), or give the MCP target
  its own named constant. Currently subtracted by [[T-374]]'s sweep and pinned by
  `theSweepSkipsTheFilesTheMCPServerTargetCompiles`, which **fails when this is fixed**, so the
  subtraction gets deleted along with it.
  **Closed 2026-08-30 **by moving to `Models/`, not by an MCP-local constant** — that would be the drift relocated rather than removed. `Models/ModelEnums.swift` already hosts `CadenceTitleNormalization` and `TaskTitleShortcutParsing` for exactly this reason ([[T-354]]/[[T-406]]). Three labels moved, including `"Untitled"` at `NoteReferenceSupport.swift:122`, which the sweep could not see at 8 characters; the `Shared/` names stay as forwarders so no app call site changed. **The [[T-374]] subtraction was narrowed to a predicate rather than deleted** — its premise still holds for `Shared/`-only constants, so a flat deletion would re-arm a false positive nobody could fix; as a predicate it retires itself when a declaration moves, which it then did, and the five hits it had been hiding became ordinary offenders and were fixed. The harvest now walks `Cadence/Models/` too, or this move would have **silently dropped `"Untitled Task"` out of the sweep**; measured 0 pre-existing qualifying constants there, so no added noise.**

- [T-500] **Four near-duplicate title-fallback helpers.** `CadenceMCPServiceSupport.resolvedTitle`,
  `CadenceReadService.resolvedTitle`, `MarkdownTaskEmbedSupport.sanitizedReferenceTitle` and
  `NoteReferenceSupport.sanitizedReferenceTitle` are four re-implementations of
  `CadenceTitleNormalization.display(_:fallback:)`. A [[T-374]] instance its string sweep **structurally
  cannot see**: that sweep detects a duplicated literal, not a duplicated function.
  **Closed 2026-08-30, **and the divergence check changed the answer: the four are two.** `CadenceMCPServiceSupport.resolvedTitle` is character-for-character `CadenceTitleNormalization.display`, and `CadenceReadService.resolvedTitle` was already a private *forwarder* to it, not a fourth implementation — both deleted, 11 call sites now call `display`. The two `sanitizedReferenceTitle`s are byte-identical to each other and **not** re-implementations of `display`: they are `display` composed with a five-character markdown escape. **Collapsing all four as the ticket asked would have dropped the escaping that keeps `[[task:UUID|Read [ch. 3]]]` from ending two characters early.** Consolidated as `CadenceTitleNormalization.referenceDisplay`, which had to live in `Models/`: the MCP target compiles `NoteReferenceSupport.swift` and not `MarkdownTaskEmbedSupport.swift`, so the two halves had no other file they could both reach.**

## Cancelled

- [X-03] **[T-83] Remove the nav arrows from Month and Board** — filed and decided on a false
  premise, then found already delivered. `cf785a8` scoped the removal to the timed grids; `ecfc9a3`
  superseded it two hours later and removed the cluster from **all four** surfaces, saying so in its
  own message. My summary to the user reported the earlier scoping as the shipped state, so the user
  was asked to decide something already done. Nothing was changed. The lesson is cheap and worth
  keeping: **report the shipped state from the code, not from the decision you remember briefing.**

- [X-08] **[T-208] CLOSED, FALSE PREMISE — Today's Completed section cannot show three rows above a
  count of two, and neither can the surfaces it was re-scoped onto.** The ticket said the section
  lists cancelled tasks while the header's "N done" does not count them. Re-derived from the code at
  `902b386`, independently of the note `CLAUDE.md` already carried.

  **The two numbers a user reads at that section are both `.count` over the array the rows are
  drawn from, so rows and count are the same number by construction.**
  - macOS: `TasksPanel.completedSection(derived:)` hands `TasksPanelCompletedSectionView` its
    `tasks: derived.doneTasks`, and that view heads itself with
    `TasksPanelIntentSectionHeader(count: tasks.count)` — the same array it `ForEach`es. The
    column-header `· N done` is `CadenceTodaySummary.completedCount`, built by
    `CadenceTodayPresentationSupport.summary(completedTasks: derived.doneTasks)` as
    `completedTasks.count` — the same array again.
  - iOS: `iOSTodayTaskSections.groupStack` passes
    `CadenceTaskSurfaceOptions.completedRows(from: completedTasks)` to `iOSTaskGroupSection`, whose
    capsule is `count: tasks.count` over that same (row-capped) array.
  - `derived.doneTasks` in `.todayOverview` is `CadenceTaskQuerySupport.completedTodayTasks`, whose
    predicate is `isFinishedTask` — done **or** cancelled — so a cancelled task is in the rows *and*
    in both counts. Three rows show a count of three.

  **`completedTaskCount` — the `isDone`-only rule the ticket is really about — is not read by that
  section at all.** `CadenceTaskQuerySupport.completedTaskCount` has three call sites: the iOS
  Settings **Completed** metric tile (`iOSSettingsView.completedTaskCount` →
  `iOSLocalDataSettingsSection`) and the past-due kanban-column summary built in
  `CadenceTodayOverdueSummarySupport.summaries(...)`. (`TasksListView` declares a private
  `completedTaskCount` of its own for All Tasks / Inbox; it counts `isDone || isCancelled`, matching
  its own `completedTasks` array exactly. Three MCP DTO fields share the name over an inline
  `filter(\.isDone).count`.)

  **Neither of those is defective either, which is why this closes rather than being re-scoped.**
  The overdue column card (`CadenceTodayOverdueSectionCard`) draws "N open" from `openTaskCount`
  and "N done" from `completedTaskCount`, and a cancelled task is in neither — but the card states
  no total, and both labels are literally true of the numbers under them. The Settings tiles are
  the same shape: independent "Active tasks" and "Completed" tiles, no sum, both accurate. An
  omission with no claim attached is not the visible inconsistency the ticket was filed on.

  One correction to the note `CLAUDE.md` carried, which said the two overdue summary cards are
  macOS's: `CadenceTodayOverdueSummaryCards.swift` is in `Shared/Components/` and
  `CadenceTodayOverdueSectionCard` is rendered by `TasksPanel.overdueSectionsSection` **and** by
  `iOSTodayTaskSections`. If anyone ever does decide cancelled work should be visible on that card,
  it is one change for both platforms, not a macOS one.

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.

- [X-04] **The kanban header's `overdueCount > 0` guard is not a coverage gap** — a mutation batch
  reported it as "genuinely unpinned": deleting the `> 0` from `ListDetailSupportViews.swift:176`
  passes the whole suite, and no test names the view's own display rule. Both halves are true and
  the conclusion does not follow. `TasksPanelSupport.overdueCount(in:)` returns
  `count > 0 ? count : nil`, so **zero never reaches the view** — every call site into the header
  either goes through that producer or passes `nil` outright. The mutation is behaviourally inert,
  which is why it survived. The invariant it leans on *is* tested, at
  `TaskOverdueSupportTests.swift:120` (`overdueCount(in: [doneLate]) == nil`). Leave the guard.
  Recorded so the next agent neither "fixes" it nor re-files it — and as a reminder that a
  surviving mutation means *the tests cannot see this change*, which is a hole only when the
  change is one a user could ever observe.

- [X-05] **[T-267] CLOSED, NOT A BUG — the iOS month date picker never killed the app. `tccd` did.**
  The ticket read as the highest-priority open crash and the premise was false, so the correction
  matters more than the closure. Re-verified against `b1239e0` on the shared `iPhone 17 Pro`
  (`7B642065-…`, iOS 26.5), clean Debug build, **seven** day-cell taps across all three entry
  points — `iOSTaskComposerDateTile` (Do and Due), `iOSTaskRowDateChip` on a live Today row, and
  the task inspector's `CadenceDatePicker` — covering today's cell, a future cell, a **past** cell,
  and a cell in a **different month** (the one that really moves `viewMonth` and re-derives all 49
  months). Every tap set the date and left the app running. `MonthCalendarPanel`'s day `Button` is
  **not** the defect; do not "fix" the `selection` / `syncViewMonthToSelection()` / `isOpen = false`
  sequence on the strength of this ticket, and do not touch it lightly at all — it is
  `Shared/Components/`, macOS reads it from six call sites including the `Cmd+Shift+T`/`Cmd+Shift+D`
  hovered-date overlay.
  **What actually happened.** Every disappearance-to-Home in this simulator's log — ten of them
  across 2026-08-22, including the four consecutive ones at 12:50:44 / 12:53:17 / 12:55:02 /
  12:55:37 that are this ticket's "reproduced four times" — is the same line:
  `tccd: Terminating com.haoranwei.Cadence[<pid>] because access to the kTCCServiceReminders
  service changed`, followed by `launchd_sim: … exited with exit reason (namespace: 11 code: 0x0)
  - OS_REASON_TCC`. Each one is preceded by milliseconds with
  `tccd REQUEST: sender_pid=81487, function=TCCAccessSetInternal` (or `TCCAccessResetInternal`) —
  pid 81487 is **CoreSimulatorBridge**, i.e. a host-side `xcrun simctl privacy <udid>
  grant|revoke|reset reminders com.haoranwei.Cadence`. Changing a TCC grant for a *running* app is
  specified to kill it; nothing in Cadence can cause it. The msgIDs form one ascending series
  (`81487.2 … .16`) across the whole day, which is what an unrelated agent's repeated
  `simctl privacy` calls on a **shared** device look like from inside the app.
  **Demonstrated, not inferred.** With the picker open and no tap on the grid,
  `xcrun simctl privacy … grant reminders com.haoranwei.Cadence` from the host reproduced the exact
  reported symptom — app gone, Home screen, sheet state lost — and logged `msgID=81487.16` with the
  identical two lines. `auth_value` in the device's `TCC.db` was `2` before and `2` after, so the
  demonstration changed no state on the shared device.
  **The two "supporting" observations were both true and both misleading.** Nothing in
  `~/Library/Logs/DiagnosticReports` and no exception, because `OS_REASON_TCC` is not a crash and
  writes no report — the same reason the ticket's `SIGKILL`-shaped reading felt right. And the
  quick pills worked "every time" because they were not tapped during the seconds a `simctl
  privacy` call happened to land.
  **The lesson is the shared simulator, not the picker.** The root `AGENTS.md` simulator bullet now
  carries it: on a device several agents share, an app vanishing to the Home screen is an *external
  termination* until the log says otherwise, and
  `log show --predicate 'process == "tccd" OR process == "launchd_sim"'` settles it in one command.

- [X-06] **[T-179] CLOSED, EXTERNAL CONSTRAINT — `control action=detach` ignores the `udid` argument and
  closes every simulator panel.** Re-verified 2026-08-24: this is a bug in the iOS Simulator control
  tool itself (the `mcp__Claude_Code_iOS_Simulator__control` action), not in anything under this
  repo, so there is no code here that can fix it. An agent detaching its own device once closed
  three other agents' panels (iPhone 17e, iPhone 17 Pro Max, iPad Air 11-inch); no device or app
  state was altered and every closed panel could just re-`attach`, so the blast radius is annoyance,
  not data loss. The one mitigation available from this side of the boundary is documentation, and
  it is now in place: `AGENTS.md`'s simulator bullet states `detach` as global regardless of `udid`
  and tells agents to only call it when they have reason to believe no one else is attached. Closing
  rather than leaving open because there is nothing left to *build* — reopen only if the tool itself
  changes or a repo-side workaround (e.g. an attach-tracking convention) is actually designed.


- [X-07] **[T-257]** ~~**`HEAD` does not build from a clean clone.**~~ **Withdrawn — the premise is false, and
  following the instruction breaks the build.** `TaskContainerLifecycleService` *is* declared at
  `HEAD`, in the committed `Cadence/macOS/Services/TaskWorkflowService.swift:58`; the untracked
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift` is another agent's uncommitted
  **move** of that type — which is why `Cadence/macOS/Services/TaskWorkflowService.swift` shows as
  modified in the same `git status` the ticket was written from. So the committed call sites in
  `EditListSheet.swift` and `CadenceCancelledTaskReachabilityTests.swift` resolve fine, and a clean
  clone builds. What does *not* build is `HEAD` plus that one untracked file, which is exactly the
  isolation [[T-21]] was told to construct: measured on 2026-08-22, three errors — `invalid
  redeclaration of 'TaskContainerLifecycleService'` and two `has no member 'remainingActiveTasks'`
  against `HEAD`'s smaller version of the type. Dropping the file instead gave macOS TEST SUCCEEDED
  and an iOS BUILD SUCCEEDED. Do **not** `git add` it — that would commit half of somebody else's
  in-flight refactor. The general rule stands and is the one worth keeping: the project uses Xcode
  **file-system-synchronized groups** (6 `PBXFileSystemSynchronizedRootGroup` entries in
  `project.pbxproj`), so any `.swift` file under `Cadence/` is compiled by directory membership with
  no `project.pbxproj` change to show for it. An untracked file therefore silently joins every
  build, and restoring `HEAD` means **deleting** it, not keeping it.

- [X-09] **Push the MCP page slice into the fetch (was [[T-415]]).** Not doing it. The ticket's stated
  reason was false -- `UUID` *is* `Comparable` in Foundation, and `UUID() < UUID()` typechecks at
  `-target arm64-apple-macos14.0`. Three real blockers stand, each independently sufficient: both
  comparators lead on **computed** properties (`AppTask.isDone` off `statusRaw`, `Note.displayTitle`)
  that a `SortDescriptor` key path cannot reach; the title leg is `localizedCaseInsensitiveCompare`
  while `SortDescriptor` offers only numeric-aware `.localizedStandard`, so pushing it down changes
  the very order `offset` is defined against; and half the candidate lists are relationship edges
  ([[T-384]]) or cross-kind merges ([[T-383]]) with no `FetchDescriptor` to carry `fetchOffset`.
  Reopening would need a stored `Comparable` sort key on `AppTask`/`Note` reproducing today's order,
  plus a partial revert of T-384 -- a CloudKit migration, with no `SchemaMigrationPlan` in the repo,
  to remove one array slice from reads whose fetch is already bounded and asserted. The limit is
  documented on `CadencePage.paging` and in the MCP guide instead.

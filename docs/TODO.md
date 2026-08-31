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






- [T-122] *(rechecked 2026-08-30 at `a1556ae`: **do not flip, and the reason is now measured on both platforms.** macOS Swift 6 builds but costs **10 warnings** in 6 files against a zero-warning baseline — a flip that produces warnings is not done, so macOS fails on its own merits even setting iOS aside. **Step (1) is now solved**: the one blocking error was an erased `KeyPath` table, fixed with `& Sendable` — one word, **no `nonisolated(unsafe)`** — verified on macOS Swift 6, iOS Swift 5, macOS Swift 5 and the export suite, and it is the only `static let ... KeyPath<` in the app, so that is complete rather than a sample. Landed; inert under Swift 5. Steps (2)-(4) untouched.)* **Flip `SWIFT_VERSION` to 6.0 — now an open question rather than a blocked one.** `D-95`
  *(measured 2026-08-31, timeboxed probe in an isolated `git archive HEAD` tree; nothing landed.
  **This ticket's "611 -> 0" no longer holds: it is 775 -> 6.** The suite grew. Naive flip of
  `CadenceTests` to 6.0 = 775 strict errors / 0 crashes, all one root cause — a nonisolated `@Test`
  calling app API that is MainActor by default (472 static-method calls, 119 properties, 68 static
  properties, 49 in `#expect` autoclosures, 27 key paths, the rest instance/init/default-value).
  Adding `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to `CadenceTests` collapses that to **6 errors +
  1 warning in 3 files**: `TemporaryDefaultsSupport.swift` (4, the `CadenceSourceScan` helpers),
  `CalendarDateMemoryTests.swift` (2, a `UserDefaults` subclass whose overrides now differ in
  isolation from what they override), `MarkdownTableHostedEditingTests.swift` (1 warning).
  **`CadenceWidgets` is free today: 0 errors, 0 warnings.** The **app target is still a don't** — it
  builds clean (0 errors) but throws **10 warnings** against a zero-warning baseline, each a real
  design question about where a callback runs: 3 x `TimelineDropInteractionSupport.swift`,
  3 x `QuickTaskPanelController.swift`, and one each in `CalendarManager.swift`,
  `CadenceMCPRefreshCoordinator.swift`, `CalendarBoardDayColumnSupportViews.swift`,
  `CadenceRemindersManager.swift`. Estimate: widgets free, tests an afternoon, app 2-3 days.
  Caveat recorded rather than hidden: the tests probe was a **compile** measurement only. No scoped
  test run was done, and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every `@Test` main-actor,
  which is a behavioural change to the suite. Budget a full `CadenceTests` run before believing it.
  Step (1) is confirmed landed: `CadenceDataExportService.swift:228` is now
  `[String: any KeyPath<CadenceArchive, Int> & Sendable]`.)*
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

- [T-115] *(re-confirmed 2026-08-30 at `a1556ae`: **still blocked, and the toolchain never moved** — Xcode 26.6/17F113, the same build the original measurement used, so there was nothing new to test against. The frontend abort reproduces in **both** compilation modes with a byte-identical stack. **Two conflicting reports from this session are now explained and neither was flaky**: the "IRGen abort in `iOSTaskRowActionViews.swift`" was a **mis-attribution** — that file never appears on an `IRGenRequest` or `While emitting` line and is not even a `-primary-file` of the crashing invocation; the crashing file is `iOSCalendarView.swift`. And the "clean, no abort" run was a **Swift 5** build, so it never tested this condition.)* **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  *(re-measured 2026-08-31: **premise still reproduces, byte-for-byte. Not disproved.** Toolchain
  unchanged at Xcode 26.6 / 17F113, so there was nothing new to test against. iOS Simulator build with
  the app at `SWIFT_VERSION=6.0` + `SWIFT_COMPILATION_MODE=wholemodule`: **0 errors, 0 warnings,
  2 `please submit a bug report` crashes**, BUILD FAILED, exit 65. Crash signature matches the ticket:
  `IRGenSILFunction::visitFullApplySite` -> `SyncCallEmission::setArgs` -> `SmallVectorBase::grow_pod`
  -> `report_at_maximum_capacity`, while emitting the `String` `@isolated(any)` reabstraction thunk
  `@$sSSScA_pSgIeAghgg_SSIeAghn_TR` — exactly the thunk this ticket predicted for whole-module mode.
  Nothing to fix in Cadence; recheck on the next Xcode bump. **Textbook case of the strict-error trap:
  the error count on that build is 0 and it is a total failure.**)*
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






- [T-489] **DECIDE: `.stroke` vs `.strokeBorder` app-wide.** Withdrawn from [[T-449]] rather than done.
  `macOS/Views/SettingsListManagementSections.swift:381` draws a 28x28 glyph at radius 7 with `.stroke`,
  which centres the 1pt line on the path — so the control renders 1pt wider than it measures, the defect
  `CadenceSettingsWell`'s own doc names as the tell. `.strokeBorder` is the value-preserving fix, but it
  is a 1pt visual change nobody has looked at and **28 other sites spell it the same way**. Either an
  app-wide sweep or nothing.


- [T-491] **The iPad capture palette's scrim stops at the detail pane.** Found while closing [[T-282]].
  `iPadMacStyleRootShell` clips `detail()` and the capture host is inside it, so an open palette **dims
  the page and leaves the sidebar bright**; on iPhone the shell-level host dims everything including the
  tab bar. The scrim's `.ignoresSafeArea()` is a no-op inside that clip. Placement-vs-capability
  judgement, so it needs a decision rather than a fix.





- [T-496] *(narrowed 2026-08-30: role confirmed — all three are 10pt semibold uppercased, asserted at all four draw sites, and `CadencePageHeaderMetrics.eyebrowSize` is **not** a fourth tracking. **Conversions computed**: 0.08em leaves the eyebrow alone but **doubles** the board's; 0.05em cuts the eyebrow to 0.625x and lifts the board 1.25x; 0.04em halves the eyebrow. **No candidate moves fewer than two of the three roles, and the one the design system already derives has the largest single jump** — which confirms the earlier refusal. **Ticket correction**: the citation graph is 4 of 6 directed edges, not mutual — the calendar file cites both siblings, the eyebrow and board cite each other and neither cites the calendar, so the calendar's 0.5 is the only one chosen with both siblings in view and it still disagrees with both. Status quo frozen by `CadenceUppercaseLabelTrackingTests` (6 tests) so the disagreement cannot widen while the decision is pending. **Reviewer checklist**: a kanban and a section-board column header on both platforms, the collapsed calendar-board rail (its label is rotated -90 degrees, the one place tracking moves a layout slot rather than a line width), a macOS week day column, the iOS timed grid day header, and one 9pt compact eyebrow popover heading.)* **One uppercase label size, three trackings.** `SectionEyebrowLabel.Size.standard` is 10/0.8
  (0.08em, derived), `CadenceBoardColumnHeaderMetrics` is 10/0.4 (literal),
  `CadenceCalendarWeekdayHeaderMetrics` is 10/0.5 (literal). All three are uppercased semibold at 10pt,
  and **each file's doc cites the other two as the authority for its size while disagreeing on
  tracking** — the [[T-284]] defect one file over. Deliberately not picked: choosing 0.08em doubles the
  tracking on every kanban column header, which is the un-inspected change [[T-452]] is open for. Needs
  the same screenshot pass, then a ratio.







- [T-497] *(**re-scoped 2026-08-31 by [[T-566]]: it is 4 sites, not 2.** The widened
  save-commit detector follows a call one frame down, which the old pattern structurally could not —
  it needed a literal `try?` at the call site. The 2 new sites are
  `iOSMarkdownReferenceSupport.swift` `body` (a third instance of "flush an in-place edit, then close",
  blocked on the same undecided question as the original two) and
  `KanbanCardMetaSupportViews.swift` `select` (popover closes over a swallowed `moveToContainer`; not
  blocked on anything, just out of scope then). Both carried as exemptions with reasons.)* **Tier 3 of the condemned `try? save()` sites — 2 left of the original 12.**
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








- [T-511] **Does a plain-text drag reach the macOS note editor at all?** Residue from [[T-495]], which
  disproved the clobbering mechanism. **Not answerable headless** — an offscreen `NSTextView` registers
  no drag types under any sequence tried, which is either the real behaviour or an artifact of a test
  host with no display server. **One manual drag settles it**: open a note on macOS, drag a text
  selection from another app onto the editor, watch for the insertion caret following the pointer. If it
  fails, the fix is a **deliberate registration of the text types — not** a union with
  `acceptableDragTypes`, which would re-advertise bitmaps at a refusing host and undo half of [[T-478]].








- [T-517] **~1.7 GB of shared DerivedData belongs to scratch trees that no longer exist.** 13 of the 14
  `Cadence-*` entries under `~/Library/Developer/Xcode/DerivedData/` are orphans from agent trees that
  have been deleted. `scripts/xcb.sh audit` lists them with dates and sizes. **Deliberately not deleted
  by any script — one of the fourteen is the user's own Xcode entry**, and telling them apart is a
  judgement no cleanup script should make unattended.
















- [T-530] **A stale mutation needle reads as a surviving mutant.** Found by the T-516 agent, on itself.
  Its `assert old in s` went stale when it renamed a function; Python raised, the zsh runner had **no
  `set -e`**, so the mutation silently never applied and the run reported `EXIT=0` — which reads exactly
  as *"the mutant survived"*. Same family as the compiler-crash blind spot: **it fails quiet.** Every
  mutation step must verify it applied (`grep -q` for the new text, loud if absent) before its result is
  evidence. Two of this session's runners already do it; the runbook rule should be general.

- [T-531] **macOS UI tests need a one-time system authorisation that no agent can grant.** Measured
  2026-08-30 in integration run r31: `CadenceUITests` fails at launch with *"The test runner failed to
  initialize for UI testing. (Underlying Error: Authentication canceled. System authentication…)"*. The
  tests themselves are well built — they isolate their store per run with `CADENCE_LOCAL_STORE_ONLY`, a
  fresh `CADENCE_UI_TEST_STORE_ID` and reset flags — so this is purely the macOS automation-permission
  gate, which requires the user's password. **The integration runner now defaults the UI stage off**
  (`run-ui` as arg 2 enables it) so batches are not blocked. Once authorised, turn it on and it becomes
  the third gate alongside the unit suite and the MCP build.





- [T-535] **Nothing in the release gate ever compiles the iOS surface.** `apple-release-readiness.md` is
  the stated readiness source of truth, mentions iOS **zero** times, and both its verification commands
  are `-destination 'platform=macOS'`. The iOS minimum (26.2) is stated in exactly one prose line
  (`app-review-notes.md:8`) and pinned by no test. Worth fixing whichever way [[T-510]] is decided.





- [T-539] **`iOSTaskDetailComponents.swift:72` prompts with a placeholder value, not a noun phrase.** Its
  title `TextField` prompts `"Untitled task"`, where every other title prompt in the app is a noun phrase
  ("Task title", "Note title", "Column name", "Event title"). [[T-513]] left it deliberately: capitalising
  it would make it the only prompt phrased as a value, and folding it into `defaultTaskTitle` would freeze
  the drift under a change that looks like cleanup. The real fix is "Task title". It is currently the
  first entry in `cadenceUndeclaredPlaceholderLabels`; **deleting that entry is part of the fix.**


- [T-541] **A Goals detail pane can show a goal that has no row beside it.** `iOSFeatureViews.swift` gives
  `listPane` `count: activeGoals.count` where `activeGoals` filters `status != .done`, but `selected` ends
  `?? goals.first`, **unfiltered**. With every goal completed the chooser says "No goals yet" while the
  detail pane renders a done goal in full. The mirror image of [[T-514]]/[[T-534]] — there the list had no
  row for where you are; here the detail shows what the list filtered away. **Not fixed deliberately**: the
  fallback's unfiltered tail is load-bearing for the deleted-out-from-under-you case the code comments
  describe, so choosing between them is a decision.



- [T-543] **Settings > Calendar's access card says two things and draws two glyphs.** macOS shows an
  **amber warning triangle even in the not-yet-asked state** with "Allow Cadence to create and sync
  calendar events."; iOS shows a neutral blue `calendar.badge.plus` with "Allow Cadence to show events and
  connect Apple calendars to areas or projects." **iOS is right on the glyph** — "nobody has been asked
  yet" is not an error state. The subtitle is a genuine copy decision (both sentences are true of both
  platforms), which is why [[T-524]] converged the identical literals around it and left this pair alone.
  Referenced from `CadenceSettingsSectionCopy.accessRequiredTitle`.

- [T-544] **The macOS work-hours subtitle names the wrong surface, twice.** It says "**Weekly calendar
  views** gently highlight…" but the highlight is applied per **day-column**, and its two call sites are
  `CalendarPageMonthSupportViews` **and `SchedulePanelShellViews`** — and the Schedule panel is not a
  calendar view at all. iOS says "Calendar day columns", which is closer but not fully right either.
  [[T-524]] pins the two subtitles as *still different* so a later pass cannot collapse them silently.
  Referenced from `CadenceSettingsSectionCopy.workdayBoundaryTitle`.

- [T-545] **macOS's empty-calendar row is a one-liner where iOS is two.** macOS: `"No Apple calendars
  found."` (trailing period, no subtitle). iOS: `"No Apple calendars found"` plus a subtitle saying what
  will happen. **iOS is right** — it tells the user what to do — but macOS cannot converge without a
  two-line row, and its three sibling empty rows all share the one-line house style. A small design
  decision, not a defect.

- [T-546] **Six lifecycle section labels duplicated between the Settings trees.** `"Active Contexts"`,
  `"Archived Contexts"`, `"Completed Areas"`, `"Archived Areas"`, `"Completed Projects"`,
  `"Archived Projects"` — all byte-identical between `SettingsListManagementSections.swift` and
  `iOSSettingsView.swift` / `iOSSettingsTemplateAndListSections.swift`. All clean conversions;
  [[T-524]]'s agent left them **only** because a sibling agent might have owned those files.

- [T-547] **`"Apple Calendar"` is one literal serving at least two concepts across 7 files.** Sometimes the
  integration section's label, sometimes a fallback for `calendar.source?.title` / `event.calendar?.title`.
  **Declaring it makes 7 offenders at once**, so this is a whole-app naming decision rather than a
  de-duplication. Same shape for `"Allow Access"` (12 sites, and also `RemindersAccessAction.requestAccess.title`,
  so converging couples the calendar permission button to the reminders one) and `"Open Settings"` (13).



  **Escalated 2026-08-31 by the batch-8 verification pass — this is live at HEAD with the suite green,
  not hypothetical.** `componentNames` is `["EmptyStateView(", "iOSEmptyPanel("]`, and
  `Cadence/iOS/iOSFeatureViews.swift` contains **zero occurrences of either** — verified — so that whole
  file is invisible to `noEmptyStateSentenceIsSpelledInTwoFiles`. It reaches `iOSEmptyPanel` one hop away
  through `iOSFeatureEmptyState` → `iOSFeatureEmptyDetail.body`, whose call carries only identifiers.
  Three live consequences: **`"No habits yet"` is spelled in two files** (`HabitsView.swift:158` and
  `iOSFeatureViews.swift:411`), byte-identical, with their subtitles **already diverged**;
  **`"No goals yet"` is re-typed at `iOSFeatureViews.swift:221` after [[T-540]] converged it** into
  `CadenceEmptyStateCopy.goalsTitle` — and `noCallSiteRetypesASharedStringConstant` cannot see that
  either, because it harvests `static let` and `goalsTitle` is a `static func`; and `"Select a note"` is
  spelled in `NotesView.swift` (via a fourth entry point, `NotesEditorPlaceholder`) and
  `iOSListNotesView.swift:271`. **The suite already names `iOSFeatureEmptyState` at lines 820 and 890
  without adding it to `componentNames`** — so this is an unnoticed gap between two same-session tickets,
  not a recorded decision. [[T-533]]'s guard checks within `iOSFeatureViews.swift`; T-540's checks the two
  macOS goals files; neither crosses.

- [T-550] **Two redundant `emptyText:` arguments.** `CreateGoalSheet.swift:139` and
  `HabitsFormSupportViews.swift:49` pass `emptyText: "No matching goals"`, which is identical to
  `GoalPickerViews`' own parameter default. Behaviour-neutral removal, [[T-374]] family.


- [T-551] **[[T-495]]'s verdict holds but one supporting clause did not reproduce — and it is the one that
  made [[T-511]] look like a formality.** The batch-8 pass re-measured on a real offscreen
  `CadenceTextView` built by the suite's own fixture. **Reproduced exactly:** registration-never-called
  gives `registeredDraggedTypes == []` at every step, and `acceptableDragTypes` carries the legacy TIFF
  and PNG names with `importsGraphics = false` — so the "unioning would undo half of [[T-478]]" argument
  is sound and the closure stands. **Did not reproduce:** "AppKit's own re-registration unions rather
  than replaces — toggling `isEditable` yields 22 types". Measured **3** after an `isEditable` toggle,
  **3** after `isRichText = true`, **3** after `importsGraphics = true`; a refusing host stayed at **1**.
  The construction is offscreen with no window, which may be why `updateDragTypeRegistration` never
  fires — so the clause is **unverified rather than disproved**. But if it is false, the editor advertises
  3 types where AppKit would have offered 19 text-ish ones, which makes **T-511 a live question rather
  than a formality**. Re-read this before T-511 is closed cheaply.





- [T-554] **R1 refused: the resolve-for-display / resolve-for-save split cannot be made unrepresentable
  in Swift — the sweep holding it is derived instead.** Investigated 2026-08-31 as the first refactor
  target, on the evidence of four independent bugs ([[T-446]], [[T-488]], [[T-514]], [[T-534]]).
  **The abstraction would not have prevented three of them.** All three narrowed the array *at the call
  site*, before any helper was reached — and Swift cannot express "this array is the whole collection", so
  `Resolver(areas.filter(\.isActive), selectedID:)` **reproduces T-488 exactly and compiles**. Every
  candidate shape has such an initializer. The invariant a resolver would add **already holds** given the
  same two arguments; what is missing is *argument agreement*, which is not a type property. T-534 was
  already closed the compile-forced way, by making `selection:` non-defaulted. **What shipped instead**:
  the four sweeps holding those fixes named six and four hardcoded paths, so a fifth surface in a new file
  was swept by nobody — both the control set (44 `View` types taking a whole list array) and the
  picker-surface file set are derived from the tree now. Mutation A is the evidence: pre-filtering at a
  macOS call site kills **only** the new sweep while all four pinning tests stay green. **Recorded as a
  closed investigation so the abstraction is not proposed again without new evidence.**

- [T-555] **`cadenceSharedStringConstants` harvests `static let` only, so a `static func` constant is
  unguarded app-wide.** Found while closing [[T-548]], whose `goalsTitle(isNarrowed:)` and
  `habitsTitle(isNarrowed:)` are exactly that shape — the empty-state family is covered by a new guard,
  but the general case is open. Measured over `Shared/` + `Models/`: a `static func` harvest would surface
  `"No goals yet"` in `GoalPickerViews.swift` and `"No matching goals"` in `CreateGoalSheet.swift`,
  `GoalPickerViews.swift` and `HabitsFormSupportViews.swift` — **the last two are already [[T-550]]'s
  redundant `emptyText:` arguments, so sequence the two tickets together.**

- [T-557] **An archived-but-linked area keeps its `linkedCalendarID` and no Settings surface names it.**
  The connect menu, the summary and the broken-link card all narrow to active, by the policy stated in
  `CadenceCalendarLinkHealth.missingLinks` — so this is **consistent, not the [[T-554]] class of defect**.
  But the link survives where the user cannot see or clear it, which is a product question worth an
  answer.


- [T-558] **`TildeContainerPickerSupport.flatContainers` drops every context-less list — the fifth instance
  of this shape.** `macOS/Views/TildeContainerPicker.swift:56-79` is `for context in contexts { areas.filter
  { $0.context?.id == context.id } … }`, so a list with `context == nil` matches no iteration and is never
  appended. **This is the only source of rows for the `~` list-search panel on both macOS composers**
  (`TaskTitleEntryField.swift:248`, `QuickCreateChoicePopover.swift:310`), so a task cannot be filed into a
  context-less list from either. Same fix as [[T-538]]: append the unfiled lists after the loop, keyed on the
  *offered* context set so an archived context's lists are caught too.

- [T-559] **macOS can now see a context-less list but still cannot create or correct one.** `CreateListSheet`
  takes a **non-optional** `let context: Context` and titles itself "in \(context.name)"; `EditAreaSheet` and
  `EditProjectSheet` have **no context control at all**. So a Mac user sees the row under "Other" and has no
  way to file it. `CadenceContextPickerSupport` and the keyboard-first `CadenceContextPickerList` already
  exist; the work is a `ListEditorContextRow` beside `ListEditorCalendarRow`, plus making
  `CreateListSheet.context` optional.

- [T-560] **The test target leaks a directory into the user's real app container on every run, and it is
  live.** `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/` holds **3,268** UUID directories, each with
  an `inMemory_store_ckAssets`, 2.9 MB, oldest 2026-08-22. **Attributed causally rather than assumed**: six
  test runs took it from 3,176 → 3,264, about 13–15 per full run, matching the 13 `isStoredInMemoryOnly: true`
  sites. One directory per in-memory `ModelContainer`, never cleaned. Same shape as [[T-516]]'s stranded
  plists. **The existing 3,268 are the user's to delete**; the fix is the cause.

- [T-561] **Re-triage `docs/device-checks.md` now that simulator use is established.** The checklist was
  written when nobody could drive anything. Since then agents have driven iPhone simulators successfully —
  [[T-514]]'s before/after and [[T-538]]'s create half both came from one. Several of its 15 steps may now be
  coverable without hardware. **Two genuinely are not**: pasting an image needs a real clipboard, and the
  keyboard-dismiss gesture cannot be exercised because *"the simulator suppresses the software keyboard while
  a Mac keyboard is attached"*. Establish which of the rest a simulator can cover and shorten the list.


- [T-562] *(RESOLVED 2026-08-31 — **this ticket's premise was wrong, and the wrong half was mine.**
  Not a regression, not a never-worked, and not a sidebar defect at all. `testLaunchesToTodayWithSeededSidebarLists`
  **passes about 4 runs in 5**: 5 runs measured (working tree @5ae916a pass 7.4s; isolated `git archive HEAD`
  pass 7.1s, FAIL 15.9s, pass 5.8s). The one failure was at `CadenceUITests.swift:74` —
  `wait(for: .runningForeground, timeout: 10)` inside `launchApp` — so the app never reached the
  foreground and no sidebar query was ever made. The originating run's xcresult shows the same thing:
  `CadenceUITestsLaunchTests` **also** failed, at its identical foreground wait, and both tests ran
  3-5x slower than normal. That exonerates the seeder, the sidebar data path and the identifier.
  **All three hypotheses killed, H2 by direct measurement:** a 0.3s process poller caught the launch —
  pid 98099 was `…/Build/Products/Debug/Cadence.app/Contents/MacOS/Cadence` (confirmed via `lsof` txt)
  carrying the test env vars. XCUITest launches the freshly built debug app, **not**
  `/Applications/Cadence.app`. The identical-bundle-id hazard does not apply to this target.
  H1 died to archaeology: the row's accessibility chain is byte-identical from `2d3a82f` (where the
  test and the identifier were both introduced) to HEAD.
  **Root cause was process, not code, and it was the orchestrator's:** the originating run was a bare
  `xcodebuild`, which takes **no test-host lock**, while another agent's hosts were live. `scripts/xcb.sh`
  acquires the lock (`xcb.sh:183`); bare `xcodebuild` does not. Standing rule now: **run UI tests as
  `scripts/xcb.sh <id> test -only-testing:CadenceUITests`.** Superseded by [[T-563]] for the residual flake.)*
  ~~**The first-ever UI test run fails: no seeded sidebar list is visible.**~~ Measured 2026-08-31,
  immediately after the user granted the macOS automation authorisation that [[T-531]] was blocked on.
  `Testing started` now reaches real tests, so the gate is open and T-531's blocker is cleared.
  `testLaunchesToTodayWithSeededSidebarLists` finds `sidebar.destination.today` but then fails at
  `CadenceUITests.swift:23` after five retries over 5s waiting for `sidebar.list.area.alpha-area`.
  The other two UI tests skipped (they need `CADENCE_RUN_INTERACTIVE_UI_TESTS=1`).
  **Do not assume this is a regression.** `CadenceUITests.swift` was last touched in `0dc7d3a`, long
  before batches 1-10, and the target has been dark that entire time -- so this test may never have
  passed. Establish that first; "it never worked" and "we broke it" need different fixes.
  What is already ruled out: the identifier is derived, not typed
  (`SidebarSupportViews.swift:353` builds `sidebar.list.\(kind.accessibilityFragment).\(slug(label))`,
  and "Alpha Area" slugs to `alpha-area`); there is no `DisclosureGroup`/collapsed section around the
  row; the seeder inserts all three lists under a context and does `try? modelContext.save()`
  (`CadenceUITestSupport.swift:29-44`); `prepareAppState` is wired at `macOSRootView.swift:102`.
  **Leading hypothesis, and it is cheap to test: the identical bundle id.** `/Applications/Cadence.app`
  is `com.haoranwei.Cadence` **build 16** -- the same id XCUITest launches ("Open com.haoranwei.Cadence").
  The runner may be attaching to the user's installed release app instead of the freshly built debug
  one. Confirm which binary actually launched before theorising further.
  Second hypothesis: the lists are seeded but never reach the sidebar's data source -- adjacent to
  [[T-558]] and [[T-559]], though note these seeded lists *do* have a context, so it is not the
  context-less path those tickets describe.
  Safety, already checked: the user's real store was NOT written -- `~/Library/Containers/com.haoranwei.Cadence/`
  Application Support is still dated 2026-08-19, untouched by the run. The per-run
  `CADENCE_UI_TEST_STORE_ID` isolation held. Keep it that way.

- [T-563] **`CadenceUITests` flakes on app activation, ~1 run in 5.** Split from [[T-562]], whose
  sidebar premise was disproved. Measured 2026-08-31 across 5 runs. The flake is always the same
  assertion, in two places: `wait(for: .runningForeground, timeout: 10)` at `CadenceUITests.swift:74`
  and `CadenceUITestsLaunchTests.swift:30`. When it fires, the app has not reached the foreground and
  nothing downstream of launch has run — so any failure it causes is misattributed to whatever the
  test was about to assert. That misattribution already cost one ticket.
  Do the cheap thing first and measure before touching the tests: **route UI runs through
  `scripts/xcb.sh <id> test -only-testing:CadenceUITests`** so they take the test-host lock. The
  originating failure happened under another agent's concurrent test hosts, so lock discipline alone
  may remove most of it.
  Only if it survives that: consider `app.activate()` before the foreground wait and a longer timeout.
  **Both are test-behaviour changes, not app changes.** A ~20% flake cannot be shown fixed by a
  handful of runs — budget ~20 runs before and after, or the "fix" is unfalsifiable.
  Do not raise the timeout as a first move: a timeout bump that hides a real activation regression is
  strictly worse than a flake that reports one.

- [T-564] **DECIDE: collapse the now single-case `TasksPanelMode`, and the half-pair it left behind.**
  Split out of [[T-487]] deliberately — the agent did the deletion it was asked for and stopped at the
  two changes that are design calls rather than cleanup.
  **(a)** `TasksPanelMode` has one case left. `switch mode` is still written out in `taskSections`,
  `doneTasks` and `isEmptyState` so that a future second mode must be *answered* rather than silently
  fall through. Collapsing the enum removes a type; keeping it keeps that forcing function. If Today
  and All Tasks may ever diverge again, keep it.
  **(b)** `TasksPanelDropCoordinator.taskDropHandler` is now unreferenced (its call site was
  `liveFlatSection`), but it is one half of a symmetric currying pair whose sibling `sectionDropHandler`
  is still live. Deleting half a pair is a shape change, not a dead-code removal.
  Note the interaction with the macOS Today scan: `TasksPanelSupport.assignTask` has a live drop bug
  (compound `list:<uuid>|date:today` keys never split on `|`), so **do not restructure the drop
  coordinator until that is fixed or explicitly deferred** — a refactor landing first would make the
  bug harder to see.

- [T-565] **A shared guard against the T-333 / T-337 / T-352 class: comments asserting machinery the
  code no longer has.** Three tickets this week were the same defect — prose naming a mechanism that
  does not exist, which is worse than a missing mechanism because it stops the next reader checking.
  Proposed by the T-352 agent, which was asked to report rather than build it.
  The instrument already exists: `CadenceScanInstrument`, plus the `strippingComments`-vs-raw pairing
  that ticket's third test uses to prove a sentence lives in a comment. A sweep would pin a small
  registry of **retired mechanism phrases** (`SceneStorage`, `todayDateSections`,
  `SidebarStaticDestination`, ...) as absent from comments in files where they are also absent from
  live code — i.e. flag prose asserting machinery no live line in the same file references.
  **Keep the registry hand-curated.** A fully automatic version would fire on legitimate tombstones,
  which this repo uses deliberately and well — 22 of them survive [[T-487]] on purpose. The value is
  in catching the *claim*, not the *memorial*.
  Use `strippingComments`, never `codeOnly` — `codeOnly` blanks string literals too, which is what
  made an earlier copy scan permanently and silently green.

- [T-572] **The iOS Board's day columns are unreadable to VoiceOver.**
  `iOSCalendarBoardView.swift:315-343` has no `accessibilityLabel`; macOS
  `CalendarBoardDayColumnSupportViews.swift:121` announces "<long date>, N scheduled items". The
  correct pattern is one file over.

- [T-584] *(**premise CORRECTED 2026-08-31 — this ticket, written by the coordinator, overstated the
  defect in two ways.** (1) **It is not an unnoticed bug; it is a recorded decision.**
  `CadenceTodayLayoutSupportTests.swift:142` `everyInspectorWidthTheTargetIPadsProduceFallsBackToOneNotesColumn`
  already asserts this exact outcome over these exact devices, and `:167`
  `theInspectorFloorWasNotRaisedToFitTwoNotesColumns` costs out the alternative. T-177 chose the
  one-column fallback **on purpose**; the behaviour it replaced was a 39pt editor. (2) **"Never a note"
  is literally false** — `iOSNotesView.open(_:)` (`:498-509`) routes `.oneColumn` at regular width to
  `presentedNote`, so a note *is* readable.
  Also corrected: the widest reachable rail is **545.4pt** (13" landscape, sidebar folded), not the 483
  the ticket claimed. It changes nothing — a 601 rail needs a 1505 pane, which no iPad produces — so
  `.oneColumn` at every shipping width still holds.
  **The real complaint, which survives and is still worth fixing:** the rail is an index, and reading a
  note means a `fullScreenCover` that blanks a 1366pt iPad. The Events tab uses `.sheet`, so it is a
  form sheet rather than a blank-out — the two paths already disagree.)*
  **AWAITING USER DECISION — four options costed, agent recommends option 1.**
  **1. A one-column *editor* mode in the rail** (recommended). At regular width with a note selected,
  render the editor in the pane with a return-to-list control instead of presenting a cover. Mostly
  reuse: `editorPane` exists standalone (`iOSNotesView.swift:363-388`) and `iOSNoteEditorCover`
  (`:622+`) is already a complete editor. Work: a third branch in `content`; `open(_:)` stops setting
  `presentedNote` at regular width; `showsHeaderTemplateMenu` (`:146`) must become true in the editor
  state or the header silently drops three controls; `iOSNoteEditorCover` needs an injected dismiss.
  **Must be applied to `iOSListNotesView` too** (`:173-175`, same split, same cover) or the two notes
  surfaces diverge. Takes nothing from the task column; fixes every narrow regular-width host.
  **2. Lower `twoColumnMinimumWidth`** — dead end. Even at macOS's `columnIdealWidth` of 224 the floor
  is 545, which only 13"-landscape-folded clears, so the rail would gain and lose its editor on
  rotation. This is T-177's 39pt editor with a bigger number.
  **3. Raise `inspectorPaneFloor` to 601** — refuted in-repo: `twoPaneMinimumWidth` becomes 1042 and a
  13" portrait iPad loses the task column that is the page's subject, to make room for a notes index.
  **3b.** Give the inspector the notes floor only when the pane can afford it (>=1042). Works
  arithmetically, but the split appears and disappears with sidebar folding and the switcher reflows
  the task column.
  **4. Route the rail's Notes half through a different component** — e.g. today's daily note, edited
  directly, no index. Arguably the best *product* answer and it sidesteps width entirely, but it
  removes browse-all-notes from the rail and leaves other narrow hosts index-only.
  **Nobody has looked at this on a device.** The whole analysis is arithmetic and source reading. Before
  committing, capture the rail at 1366 and at 836 on a simulator.
- [T-595] **iOS calendar: put the drawn numbers in `iOSCalendarMetrics`.** Approved 2026-08-31.
  **(a) Ten hairline weights on one screen.** `Theme.borderSubtle` appears at 1.0, 0.75, 0.65, 0.46,
  0.42, 0.35, 0.34, 0.30, 0.28 and 0.20 across `iOSCalendarTimelineViews.swift:559,564,607,635,643`,
  `iOSCalendarMonthViews.swift:423,428`, `iOSCalendarBoardView.swift:328`,
  `iOSCalendarBundleDetailSheet.swift:349`. Sharpest instance: **one month cell whose right edge is
  0.30 and bottom edge is 0.42** (`:423`/`:428`), while the timeline day header's two edges agree at
  0.65. **(b)** Weekday header band height is `36` (`iOSCalendarMonthViews.swift:22`) and `22`
  (`iOSCalendarMonthAgendaViews.swift:35`), both feeding the same grid; same file also carries a bare
  `104` and a `gridBottomPadding = 8`. `CadenceCalendarWeekdayHeaderMetrics` already owns the label's
  *size* for exactly this reason (T-277) — the band's *height* was left behind.
  `iOSCalendarMetrics.swift` opens by claiming to hold "every measurement the iOS calendar's three
  presentations are drawn with" and holds none of these. **Make the claim true, and pin it.**
  Where two values disagree, do NOT invent a third — report the pair and use the one with a stated
  rationale, or ask.

- [T-596] **iOS Today rail: the same, for the schedule panel.** Approved 2026-08-31.
  **(a)** The two iOS hour grids disagree: `iOSTodaySchedulePanel.swift:361-363` draws `height: 1` at
  `opacity(hour % 3 == 0 ? 0.55 : 0.25)`; `iOSCalendarTimelineViews.swift:632-636` draws `height: 0.5`
  at `0.46 : 0.20`. **Same `% 3` cadence, so the rule was copied and the values were not** — 2x line
  weight and two opacity pairs for one hairline. The hour *label* opacities do match (0.9/0.45), which
  is what makes the line divergence look accidental. **(b)** One 7pt radius spelled two ways in one
  file: `Theme.radiusControl - 3` (`:437`, the repo's inner-pill idiom) and a bare `cornerRadius: 7`
  (`:558`) — the only hardcoded radius in the six scoped files. **(c)** The two Today hosts type their
  own gutters and have drifted: `iOSTodayView.swift:343-345` (14 / top 12 / bottom 20) vs
  `iOSTodayCompactViews.swift:49-56` (14 / top 10 / bottom 16) — **after both already read
  `contentMaxWidth` from `CadenceTodaySectionMetrics` precisely so "the two hosts cannot drift apart
  again."** Finish that unification; `CadenceTodaySectionMetrics` is keyed on layout and is the home.

- [T-597] **macOS Today: two chips and two headers that ignore their own metrics types.** Approved
  2026-08-31. **(a)** The Cancelled chip (`TasksPanelComponents.swift:68-77`) hardcodes `size: 10`,
  padding `6/3`, while its four siblings on the same row — do-date pill, due-date pill, bundle badge,
  estimate chip — all use `metrics.secondaryFontSize` (11 on `.desktop`) with `4/2`.
  `CadenceTaskRowMetrics.desktop` exists precisely so these do not drift. **(b)** Two adjacent section
  headers differ by **1pt** of bottom padding — `TasksPanelSectionViews.swift:63-65` (bottom 5) vs
  `:182-184` (bottom 6) — and neither reads `TaskListDisplayMetrics`, which owns
  `headerHorizontalInset = 24` and is used with bottom 8 by the list-detail siblings.
  `TasksPanel.swift:349,365,381,390` repeats the bare `16` four more times. iOS puts every one of these
  in `CadenceTodaySectionMetrics`, keyed on layout — that is the target shape.

- [T-598] **iOS calendar: say it once.** Approved 2026-08-31.
  **(a)** One start-time control, three labels: "Starts" (`iOSCalendarQuickCreateSheet.swift:460`),
  "Time" (`iOSCalendarEventEditSheet.swift:352`), "Start" (`iOSCalendarBundleDetailSheet.swift:146`) —
  three sheets reachable from one screen, all opening the same 15-minute popover.
  **(b)** `"Read Only"` (`iOSCalendarSettingsSection.swift:428`) against the shared
  `CadenceCalendarLinkExclusion.readOnly.qualifier` = `"Read-only"`
  (`CadenceCalendarLinkRowState.swift:152`), in a type whose doc exists so *"the shape is shared and
  the word is a parameter"*; the event sheet's prose says "read-only calendar". **Three spellings of
  one fact.** macOS `SettingsListManagementSections.swift:301` has the same `"Read Only"` — both drift
  from the shared constant together, so fix both.
  **(c)** `"+ 3 more"` (`iOSCalendarTimelineViews.swift:542`, `iOSCalendarMonthViews.swift:401`) vs
  `"+3 more"` (`:1095`). Repo-wide the unspaced form wins 9-3, but the two spaced calendar sites match
  macOS's spaced `CalendarPageMonthSupportViews.swift:349` — so the calendar is split internally *and*
  from the rest of iOS. Pick one, hoist it, and say which in the closure.

- [T-599] **Settings: say it once.** Approved 2026-08-31. Five copy divergences; hoist each to
  `CadenceSettingsSectionCopy` rather than editing two literals into agreement.
  **(a)** Tags empty state: macOS `"Create a tag or add the default set."`
  (`SettingsTagsSection.swift:103`) vs iOS `"Create one or add the default set."`
  (`iOSSettingsTagsSection.swift:118`). Recommend macOS's — "a tag" is concrete where "one" needs the
  title above it to parse.
  **(b)** Templates footnote written twice (`SettingsTemplatesSection.swift:58` vs
  `iOSSettingsTemplateAndListSections.swift:63`). Keep iOS's second sentence; **macOS's first clause
  names "the note sidebar", which is a real macOS surface and a false one on iPhone** — so that clause
  stays macOS-only. Same family as [[T-544]].
  **(c)** The **AI privacy disclosure** is one sentence longer on macOS
  (`SettingsSectionViews.swift:172` has "such as summarizing a note or extracting task drafts"; iOS
  `:367` does not). Everything else on the card is byte-identical, so this is drift, not a decision.
  macOS is right — the examples make "AI action" concrete. **This is privacy copy; treat accuracy as
  the bar.**
  **(d)** Four AI buttons, four labels, verbosity **inverted**: macOS "Save API Key"/"Test
  Connection"/"Delete Key"; iOS "Save Key"/"Test"/"Delete API Key". Recommend iOS's Delete ("Delete API
  Key" — a destructive button should name the whole noun) and macOS's Test ("Test Connection" says what
  is tested).
  **(e)** `"Apple Calendars"` (macOS `SettingsListManagementSections.swift:27`, plural, inside the
  authorized branch) vs `"Apple Calendar"` (iOS `iOSCalendarSettingsSection.swift:67`, singular, and
  **above** the branch so it also heads the access-denied card). macOS is right on both counts.
  *Extends [[T-547]]* — that ticket is the noun serving two concepts; this is the section label.

- [T-600] **Settings empty states: converge the component first, then the four copies.** Approved
  2026-08-31. **Strictly sequenced — (a) before (b).**
  **(a)** iOS has two near-identical empty-row components: `iOSSettingsEmptyRow`
  (`iOSSettingsComponents.swift:368-393`, 13pt title, glyph hardcoded to `tray`) and
  `iOSSettingsEmptyInlineRow` (`iOSSettingsTemplateAndListSections.swift:704-733`, 14pt title, glyph
  parameterised). Both drawn in the same card vocabulary, **already drifted by a point**. Keep
  `iOSSettingsEmptyInlineRow` — the parameterised glyph is strictly more capable — and delete the
  other. *Extends [[T-548]]*.
  **(b)** Then close the four macOS one-liners against their iOS two-line twins: Reminders lists
  (`SettingsRemindersSection.swift:79`), Contexts (`SettingsListManagementSections.swift:428`), Lists
  (`:507`, where iOS also has an "Inactive Lists" eyebrow macOS lacks), Templates
  (`SettingsTemplatesSection.swift:195`, a bare `Text` not even in a card row). **macOS says only what
  is absent and never what would fill it; iOS says both.** iOS is right in all four.
  *Extends [[T-545]]*, which named only the empty-calendar row — these are four more of the identical
  shape and should probably be absorbed into it.

- [T-601] **Three call sites that ignore a correct shared helper.** Approved 2026-08-31. The repo's
  most common defect shape (T-374).
  **(a)** `iOSCalendarInspectorView.swift:145-169` reproduces `CadenceInlineEmpty(surface: .touch)`
  exactly — same text, 13pt, `Theme.dim`, `Theme.surfaceElevated.opacity(0.38)`, `Theme.radiusControl`
  — **except vertical padding is 6 where the shared touch metric is 14**. The Board day column on the
  same screen uses the real component.
  **(b)** `iOSCalendarTimelineViews.swift:612-617` hand-rolls `hourLabel(_:)` to produce
  "12 AM / 1 AM / 12 PM / 1 PM". `TimeFormatters.timeString(from: hour * 60)` returns those strings
  **byte-for-byte**, and **the other iOS hour rail already calls it**
  (`iOSTodaySchedulePanel.swift:441-443`).
  **(c)** `iOSTodaySchedulePanel.swift:587-598` re-implements `Theme.priorityColor`
  (`Theme.swift:368-375`) case for case, **except `.none` returns `Theme.dim.opacity(0.76)` instead of
  `Theme.dim`**. Nine other call sites use the shared function. If the 0.76 was deliberate, say so and
  leave it; if not, it is a bug wearing taste's clothes.

- [T-603] **iOS month grid: one selection layer, not three. DECIDED 2026-08-31 - badge only.**
  `iOSCalendarMonthViews.swift:414-419` with `:437` and `:445` currently paint (a) a square-cornered
  `Theme.blue.opacity(0.075)` cell fill, (b) a `RoundedRectangle(Theme.radiusControl)` ring inset 4pt
  at `Theme.blue.opacity(0.65)`, 1.5pt, and (c) a wash behind the day badge - three layers, two radii,
  for one state. **User's decision: drop the fill and the ring, keep the badge wash.**
  This is also the convergent answer: the compact cell beside it already uses badge-only
  (`iOSCalendarMonthAgendaViews.swift:499-533`) and macOS uses badge plus a plate change, so all three
  month surfaces end up agreeing and no new value is invented.

- [T-604] **iOS calendar sheets: all three `.ruled`. DECIDED 2026-08-31.**
  Quick-create (`iOSCalendarQuickCreateSheet.swift:309-491`) is `.ruled`; the event-edit and
  block-detail sheets are the default `.card`. Two of them draw a "Schedule" section, one ruled and one
  carded, so the same section reads as two different components.
  **User's decision: converge all three on `.ruled`**, matching the style's own doc
  (`CadenceFieldRows.swift:42-44`): `.ruled` is *"for compact sheets where a stack of cards would read
  as a stack of unrelated boxes"*, and all three are compact sheets sharing one section vocabulary.
  Chrome (toolbar vs circular buttons) is **out of scope** unless converging the section style makes a
  sheet incoherent; if it does, report rather than expanding.

- [T-605] **macOS Today's headings converge on the 14pt bold style. DECIDED 2026-08-31.**
  Today draws `CadenceTaskGroupHeading` - 10pt uppercase eyebrow, single count capsule, no bar
  (`TasksPanelSectionViews.swift:122-153`). All Tasks, Inbox and list detail draw `TaskListGroupHeader`
  - 3x22pt accent bar, 14pt bold sentence-case title, split "3 / 7" overdue/regular counts
  (`ListDetailSupportViews.swift:99-180`).
  **User's decision: move Today onto `TaskListGroupHeader`.** macOS becomes internally consistent and
  Today gains the split counts the other three already show; one screen changes rather than three.
  **Accepted consequence: macOS and iOS headings now differ** (iOS routes Today, Inbox and All Tasks
  through the eyebrow style). That divergence is deliberate as of this decision - **record it in a
  comment so it is not re-filed later as drift.** *Adjacent to [[T-496]], which is about tracking on
  the uppercase tier, not which tier Today sits on.*

- [T-606] **macOS Today adopts iOS's named sort set. DECIDED 2026-08-31.**
  macOS has two chips - Sort (Custom/Date/Priority) x Order (Ascending/Descending), default Date +
  Ascending (`TasksPanel.swift:341-352`, `Models/TaskOrdering.swift:16-28`). iOS has one control -
  List Order / Priority / Do Date / Due Date / Newest, default Priority
  (`CadenceTaskPlanningSupport.CadenceTaskSortMode`). Only "Priority" is common, and **macOS's "Date"
  does not say which date, on a page whose whole vocabulary is do-date vs due-date.**
  **User's decision: adopt iOS's named set on macOS.** The separate Order chip goes; direction folds
  into the named modes.
  **Handle the persisted preference deliberately - this is the one hazard in this batch.**
  `TaskOrdering` and the Order chip are very likely persisted. Removing enum cases can strand a stored
  value that no longer decodes, and this project has **no `SchemaMigrationPlan`**, so a stored-property
  change is dangerous. Before editing: find every persisted read/write of sort and order, decide the
  mapping for each retiring case (Custom -> List Order, Date -> Do Date is the likely intent but
  **verify against what macOS actually sorts by** rather than assuming), and make an unknown stored
  value fall back rather than crash or silently re-sort. **If the mapping cannot be proven from the
  code, stop and report rather than guessing.**

- [T-607] **macOS All Tasks / Inbox accept a section drop that resolved nothing — the same shape
  [[T-591]] just fixed on Today.** `TasksListView.swift:236-243`'s `onDropOnSectionPayload` calls
  `assignTask` and returns `true` unconditionally. Its keys are *bare*, so the compound-key parse bug
  does not reach it — but a `list:p_<uuid>` whose project has been deleted is still silently accepted:
  the row highlights, the drop is taken, nothing moves.
  `TasksPanelSupport.assignTask` already answers `Bool` after T-591, so the fix is literally
  `return assignTask(...)`. **Filed rather than done because it changes drop rejection on two more
  screens and no evidence was gathered for those surfaces** — the agent was right not to widen scope
  on a hunch. Gather the evidence first, then it is a one-line change plus a test.

- [T-608] **Converge macOS Today's row block onto `TaskListInteractiveRow`.** Proposed by the T-593
  agent, deliberately not done. The Today block in `TasksPanelSectionViews` is a line-for-line
  re-implementation of `TaskListInteractiveRow` (`ListDetailSupportViews.swift:307`) — draggable,
  dropDestination, top indicator, 0.15s animation, same asymmetric transition — and the shared one
  **already takes `leadingInset`/`trailingInset` as parameters**, so passing `leadingInset: 16` would
  delete ~20 lines outright. The only real difference is `MacTaskRow`'s `.opacity(opacity)` on the
  dimmed Completed group, which needs one more parameter.
  Sequencing: this is safe to do after [[T-591]] landed, and it overlaps [[T-564]]'s drop-coordinator
  question — do them together or decide T-564 first, but do not restructure the same code twice.

- [T-609] **25 sites still hand-spell an empty-title fallback instead of using the shared helper.**
  Split from [[T-569]], which fixed the four calendar sites and **measured** the remainder rather than
  estimating it: 25 across `Cadence/`, `CadenceWidgets/` and `CadenceMCPServer/` spell
  `title.isEmpty ? "..." : title`. The shared `TaskTitleSupport.displayTitle(_:fallback:)` **trims
  first**, so every one of these draws a blank line for a whitespace-only title.
  Two things to decide before sweeping, not during: (a) the fallback copy is not uniform — some sites
  say "Untitled", `displayTitle`'s own default is "Untitled Task", and T-569 deliberately preserved the
  compact wording rather than promoting it, so a blind sweep would silently re-word ~25 strings;
  (b) `CadenceMCPServer` and `CadenceWidgets` are separate targets, so check the helper is available
  there before assuming one call fits all. Pin the result with a scan so the 26th site cannot appear.

- [T-610] **44 tooltip-only controls still have no accessible name, in 28 files.** Split from
  [[T-594]], which widened the T-472 sweep from one file to the whole app and ledgered what it found.
  All macOS. `cadenceControlLabel(_:)` is the fix and **each entry deletes its own line** from
  `CadenceControlAccessibilityLabelTests.knownUnnamedTooltipSites` — the ledger is exact, so a new site
  fails *and* a stale entry fails, which means this can be done a file at a time without losing the
  count. Densest: `TagPickerSupportViews.swift` (5), `ListEditorSupportViews.swift` (3),
  `TaskInspectorContentSupportViews.swift` (3).

- [T-611] **The iOS task row has the hole macOS's just lost: 1 accessibility label across 25 buttons.**
  `Cadence/iOS/iOSTaskRowActionViews.swift`. Split from [[T-594]].
  Mostly call sites — `CadenceTaskControlAccessibility` already holds the words (`doDate`, `dueDate`,
  `estimate`, `list`) and `CadenceTaskCompletionState.accessibilityActionLabel` holds the completion
  circle's. **But the widened sweep is structurally blind here:** `.help` does not exist on iOS, so the
  "tooltip without a name" rule cannot fire. A separate rule is needed — probably "an icon-only
  `Button` whose label is a bare `Image`/`systemName` must carry a label" — and it should be written
  before the call sites, or nothing stops the 26th.

- [T-612] **A fourth spelling of the carried-day dim, and this one has no plate to move.**
  `iOSCalendarMonthAgendaViews.swift:477` (`Theme.dim` at full) x `:527` (`.opacity(0.5)` on the whole
  cell). Found by the [[T-568]] agent. It nets 0.50 so it does not break the contrast floor today, but
  it is a *multiplied pair* — the same shape T-568 removed — and it fades the today ring and the item
  dot along with the label.
  **Not a copy of T-568's fix:** unlike the full-size cell this one has no plate to move, so it needs a
  design call — add a plate, or accept label-only dimming. Ask before landing.

- [T-613] **Three more orphan `cardPadding` insets from the same commit [[T-587]] cleaned up.**
  `iOSTaskCollectionPage.swift:262`, `iOSListDetailView.swift:357`, `iOSInboxRemindersSection.swift:59`
  each still apply a 12pt inset for a card `85809ff` deleted, on top of their page's own gutter — All
  Tasks and Inbox rows sit at 28 against a header at 16. `iOSTaskCollectionMetrics.cardPadding`'s doc
  still calls it "The group card's inset."
  Today is fixed; these three are the identical residue and **should be decided together** rather than
  one at a time, since they share a metrics constant.

- [T-614] **The contexts reorder commits two different ways on the two platforms — decide the rule.**
  Split from [[T-583]], which decided macOS's `moveContext` should keep its `try? save()` and documented
  that as deliberate: `order` is a field on rows the store already holds, nothing after it reports
  success, so it is the case `AGENTS.md`'s rule leaves alone.
  But [[T-581]] gave **iOS** the opposite treatment — its reorder commits through
  `CadencePendingChangePersistence` and shows an inline notice on refusal, and its doc comment names
  macOS's `try?` as the weaker half. Both agents reasoned well and reached different answers, which
  means **the rule is underdetermined, not that either is wrong.**
  The question is general, not about this pane: *does a visible rearrangement count as "reporting
  success"?* A refused save leaves the rows where the user dragged them until the next launch silently
  undoes it — which is the shape the `try? save()` rule exists to catch, but the write itself is a field
  edit. Answer it once in `AGENTS.md`, then make both platforms match.

- [T-615] **`RootTimelineSidebarPane` says "timeline" twice.** `macOSRootSupportViews.swift:327-352`
  titles itself "Today Timeline" and then hosts the standard `SchedulePanel`. Before [[T-602]] that pane
  said the word three times; it now says it twice. Noticed by the T-602 agent and deliberately left —
  reversible either way, and small enough that it wants a decision rather than a guess: drop the pane's
  own title, or drop the hosted panel's when it is hosted there.

## Done

- [T-583] **CLOSED 2026-08-31 (`a4b03cd`).** The INFERRED half does **not** survive: autosave is on,
  but "eventually" is exactly what T-327 measured, so deleting the four neighbouring saves was the wrong
  branch. **And the case was stronger than the ticket knew** — macOS's *own*
  `SettingsTagsSection.swift:192-201` already had the `archive(_:)`/`restore(_:)` shape, so the contexts
  pane was deviating from its own platform, not merely from iOS.
  The two inline closures are now `archiveContext(_:)`/`restoreContext(_:)` beside `moveContext`, each
  doing the write plus the save, with the convention written down: **existence changes report, field
  edits commit quietly.** `moveContext`'s swallowed save — left open by [[T-581]] — is decided the same
  way and documented as deliberate; making it the one reporting mutation among five would have
  re-created the inconsistency this ticket is about. Residual platform disagreement about the *reorder*
  commit split out as [[T-614]].

- [T-602] **CLOSED 2026-08-31 (`1dd6c4a`).** `NOTES / <active tab>` and `SCHEDULE / Timeline` are now
  simply **Notes** and **Timeline**. `PanelHeader.eyebrow` is optional and unused; `NotePanel.headerTitle`
  — which restated the tab strip eight lines below it — is deleted.
  **Neither column had a second fact to promote** the way the task column had the date, so neither
  invented one. **And it is deliberately not "no header at all":** iPad *does* delete both, because
  `iPadTodayInspectorSwitcher` names the pane; macOS's three columns stand side by side with nothing
  else naming them, so one title each stays. "Timeline" over "Schedule" because that is the word the
  zoom control, the `Close timeline` label and iPad's switcher already use.
  **Cost stated as computed, not observed:** with no eyebrow the two titles sit ~14pt higher inside the
  unchanged 100pt band. The app was not launched.


- [T-579] **CLOSED 2026-08-31 (`4849cea`).** iOS Settings > Defaults now carries a "Default page" row
  over `ListDetailPage.allCases`, on the same shared value-row/popover vocabulary macOS uses, with
  macOS's one-time stale-value normalization brought across. Nothing removed from macOS; `ios.calendar.*`
  remains genuinely iOS-only.

- [T-580] **CLOSED 2026-08-31 (`87872f4`).** `.sync` retitled "iCloud Sync" — one string fixed both
  platforms: macOS no longer draws two rows about an account, iOS no longer says "Account" on a
  platform with none. **Both checks the ticket asked for came back clean:** the string is a label only,
  `rawValue` (`"sync"`) is what persists and decodes and was untouched, and the only test hits on the
  old title were `#require` *messages*, not assertions.

- [T-581] **CLOSED 2026-08-31 (`a95423e`).** iOS gained Move Up / Move Down in the context menu each
  row already had, greyed at the ends — **not `.onMove`**, which needs a `List` in edit mode and this is
  a card of rows. Index arithmetic is now shared (`CadenceOrderReassignment`) and macOS reads it too, so
  there is no second copy to drift.
  **It did not copy macOS's swallowed save.** macOS ends `moveContext` in `try? save()`, which is inside
  the letter of the rule but leaves a refused save as a rearrangement the next launch silently undoes.
  iOS commits through `CadencePendingChangePersistence.commitEdit(in:undo:)`, restoring every `order` on
  refusal so the card re-sorts to the store, with an inline failure notice. Both sides renumber over
  *every* context including archived ones — numbering only the visible slice hands them indices archived
  rows already hold, and a sort on ties is unstable.

- [T-568] **CLOSED 2026-08-31 (`4628fd7`).** User chose macOS's documented 0.50, one layer. Token now
  `CadenceCalendarDayBadge.outOfMonthLabelOpacity` in Shared (iOS cannot see `Cadence/macOS/`), read by
  both platforms, with the contrast maths beside it. The badge's second dim and the whole-cell
  `.opacity(0.52)` are gone; **following macOS's shape, the plate moves instead** — in-month
  `Theme.surface`, carried `Theme.bg` — with today's and the selection's washes drawn over it, so the
  today ring and the event chips are no longer faded. No third value invented.

- [T-572] **CLOSED 2026-08-31 (`321cafd`).** **The prerequisite was right and saved the ticket from
  shipping a bug twice.** macOS's label announced active+completed while its header drew active-only,
  so copying it to iOS would have exported the mismatch. Fixed macOS in the same change and gave
  neither side its own sentence: both read `CadenceBoardColumnAccessibility.dayColumnLabel`. macOS's
  `totalCount` had one reader and is deleted. Pinned as a value **and** as a call-site scan asserting
  the *argument* — a count-only scan would stay green if a sum were passed back in.

- [T-573] **CLOSED 2026-08-31 (`bd8da45`).** `.isSelected` added; all three cells now say what is on
  the day via `CadenceCalendarDayAccessibility`. **Label rule chosen deliberately:** count where a
  count is drawn, presence where only a dot is, both where two are. The agenda count *is* knowable and
  is deliberately not announced — stating a figure that is nowhere on screen is the mirror of the
  T-571 mismatch.
  **Premise did not reproduce:** `iOSCalendarTimelineViews:569` is **not** a third instance. That
  header carries no selection state by design — its doc says so, its background keys on `isToday`
  alone, and the grid passes it no `isSelected`. Adding the trait would announce a state the screen was
  deliberately changed to stop drawing. Exemption pinned by
  `theTimelineDayHeaderHasNoSelectedStateToAnnounce`.

- [T-587] **CLOSED 2026-08-31 (`2668841`).** **Git settled it:** `git log -S'drawsCard'` shows the card
  removed at this exact call site in `85809ff`, deliberately and five sites wide — *"macOS never drew
  one, so the rows now read the same on both platforms."* So the flag, the padding, the doc sentence and
  both tests were residue.
  **The padding was not inert residue.** Both hosts already inset the list 14pt, so compact drew its
  groups at 26 while the page header, options bar, rollover banner and past-due cards — siblings in the
  same `VStack` — stayed at 14. **Visible change on iPhone Today:** group headers and rows move 12pt left
  onto the same gutter as everything above them.
  The old test pair pinned `drawsCard` and `cardPadding` *to each other*, which is exactly why it
  survived the card's deletion — including the one whose own doc forbids "an inset with no fill behind
  it". Replaced by a memberwise-init equality pin, so a new per-layout field now fails to **compile**.

- [T-588] **CLOSED 2026-08-31 (`816329f`).** The row reads `iOSCalendarTimelineMetrics` for hour
  height, label size and trailing inset. **8 won over 9** because it is the value with a measurement
  behind it (`theHourLabelFitsTheNarrowRail`) and the one the Calendar rail already draws at both
  widths — taking 9 would have moved the surface that measured to match the surface that did not.
  **Extra finding:** all three literals sat behind a `rowHeight > 50` ramp with an unreachable lower
  branch — the same dead compact ramp this file's own header records deleting from `rowHeight` itself,
  still live three lines down. Collapsed with them.

- [T-590] **CLOSED 2026-08-31 (`0da8318`).** Line numbers had moved exactly as warned. **The sweep
  found a second instance the ticket did not list** — the same `title.isEmpty ? "task"` in
  `iOSCalendarTimelineViews`' clear-time control. Both now read `TaskTitleSupport.displayTitle`, and
  the app-wide rule is pinned: no accessibility label may spell its own empty-title fallback. Note both
  take the full "Untitled Task" where the block beside them draws compact "Untitled" — that spelling's
  stated reason is "a row with no width for the noun", **and a spoken label has no width.**

- [T-594] **CLOSED 2026-08-31 (`7aa7de9`).** All six named. Three value chips take
  `.accessibilityLabel` + `.accessibilityValue` (so "Do date, Tomorrow", not a bare "Tomorrow"); the
  container badge is named on the shared `ContainerPickerBadge`, so the composer and inspector
  breadcrumb inherit it; the completion circle keys on
  `CadenceTaskCompletionState.accessibilityActionLabel`, whose five branches mirror `handleTap()`
  — **mid-fill a second tap cancels, so a state reading would have been wrong.**
  **Sweep widened from one file to the app: 44 unnamed-tooltip sites in 28 files remain**, recorded as
  an exact per-file ledger so a new one fails *and* a stale entry fails. Split out as [[T-610]]; the
  iOS twin is [[T-611]].
  **A collateral run caught a real break** the scoped run would not have: `CadenceTodayUnificationTests`
  pins `TasksPanelComponents.swift` at exactly one `estimateLabel` call site and the new
  `.accessibilityValue` made it two. Fixed by having the chip read one property for both, **not** by
  raising the pinned number.


- [T-577] **CLOSED 2026-08-31 (`aac3679`).** Both gaps fixed. Titles now read
  `CadenceTitleNormalization.display(_:fallback:)` — **stronger than iOS's `.isEmpty` check**, which let
  a whitespace-only name through.
  **One judgement worth recording:** copying iOS's `"No parent list"` literally would have put a second
  inline copy in the repo — 2 sites in 2 files, exactly the threshold `CadenceSharedConstantReuseSweepTests`
  and [[T-505]] say must be declared. *The fix for a drift would have committed the defect that sweep
  exists to catch.* It is now `CadenceListSettingsCopy.parentSubtitle`, declared once and registered
  with the sweep so a third surface arms it.

- [T-578] **CLOSED 2026-08-31 (`dfce44a`).** Heading dropped rather than renamed — `iOSSettingsPageHeader`
  sits directly above it in both layouts and already reads "Notifications", so this matches macOS's
  `title: nil` exactly and does not read as orphaned.
  **Consequence caught in passing:** `theSettingsCopyScanReadsLiteralsRatherThanBlankingThem` used that
  exact heading as its **non-vacuity witness for the whole suite** — deleting it would have made every
  literal assertion in that suite silently vacuous. The witness moved to `"bell.fill"` with the reason
  recorded.

- [T-582] **CLOSED 2026-08-31 (`3a3538f`).** The Backups card now owns `backupStatusMessage`; the
  export-to-reset sharing is kept because that part was deliberate, and the doc comment asserting a
  pane-wide shared line was rewritten rather than left standing ([[T-565]]'s class).
  **The test asserts both directions on purpose** — no backup function reaches the shared line, *and*
  export/delete still do — because a one-directional assertion is satisfied by splitting the export
  pair too, which is the opposite fix.

- [T-570] **CLOSED 2026-08-31 (`9fa6ed7`).** Premise reproduced. **The ticket's caveat was real and the
  one-line fix would have been wrong.** Measured against the real window functions: Month never moves
  the selection with the grid (`keepSelectedDateInView` is gated on `isTimedGrid`), and a day carried
  from Aug 15 is inside the window at displayed months Jul/Aug/Sep but **outside** at Jun or Oct — so a
  bare `?? []` would have emptied a pane that has events in it. Fix is
  `visibleEventsByDate[selectedKey] ?? selectedDayEvents`, with a cached per-day fetch that runs only
  when the window cache lacks the day. **No EventKit query remains in `body`.** The timed grids
  provably cannot reach the fallback and that is now a test with a non-vacuity assert, not a claim.

- [T-571] **CLOSED 2026-08-31 (`a5aebd4`).** iOS changed to active-only, matching macOS. The reasoning
  is the ticket's open question answered: the count sits above the column's own list, that list is the
  active items, and finished work is behind the "Completed" toggle **which already carries its own
  count**. Summing them stated a total nothing on screen adds up to, counted the same task twice on a
  column showing both halves, and made a fully cleared day read as busy as an untouched one. It also
  matches every other board header in the app. iOS's `totalCount` had one reader and went with it.

- [T-586] **CLOSED 2026-08-31 (`f5bc288`).** The whole rail is `Theme.surface` — switcher strip and
  both halves — matching the task column across the divider, plus the `.ignoresSafeArea()` the schedule
  panel was missing.
  **Premise correction worth keeping:** the ticket blamed `iOSNotesView.swift:170`, but that line is not
  what you see — the notes header (`:265`) and sidebar (`:314`) each draw `Theme.surface` in front of
  it, so changing `:170` alone would have changed nothing on screen. That ruled out "move Notes to
  `Theme.bg`" as a scoped fix. `iOSNotesView` is a standalone page too, so the two rail-only views moved
  instead and it was left untouched.


- [T-585] **CLOSED 2026-08-31 (`d35470a`).** Premise reproduced, **plus one the ticket missed**: the
  day-end clamp (`lastStart`) was computed for 30 minutes too, so a 90-minute task could be offered
  23:30. New `ReadyScheduleContext` in `CadenceScheduleSupport` resolves the day once — one clock, one
  work window, one set of busy ranges — and each row derives its own start times from its own task's
  length.
  **On the once-per-pane tension the ticket flagged, the agent kept the half that is load-bearing and
  dropped the half that cannot be true.** "Every row offers the same times" is only honest while every
  task is the same length; with mixed lengths one answer for every row is wrong for all but one of
  them. The property that actually mattered — a filled slot leaves every row at once — comes from all
  rows reading the same live day, which the context carries. It also fixes a latent bug: per-row calls
  would each have taken their own `Date()`. An estimate-less task still resolves to 30 and its answer
  is bit-identical to before, pinned by `anEstimatelessTaskGetsTheSameSlotsTheOldSharedAnswerGave`.
  8 new tests; 3 mutations, each confirmed compiled.

- [T-589] **CLOSED 2026-08-31 (`35790d3`).** `quickCreateError` was cleared only by
  `selectQuickCreateStart` and `cancelQuickCreate` — both about the composer rather than the field — so
  the notice sat in red while you typed the title it was asking for. Now cleared on title change.
  **The `.onSubmit` half was deliberately NOT guarded, and the reasoning is in source.** The `+` button
  refuses *visibly* by greying out; Return has no such affordance, so guarding it would make the key do
  nothing at all — the inert-control-with-no-explanation failure T-470/T-471 went through this app
  removing. It would also have made "Add a title first." unreachable dead code. Return reports; the
  report now clears itself. `returnOnAnEmptyFieldStillReportsRatherThanDoingNothing` fails if someone
  later adds that guard. 3 new tests; 2 mutations, each confirmed compiled.


- [T-566] **CLOSED 2026-08-31 (`750be02`).** `updateBundle` now takes `commit:` and throws through
  `CadencePendingChangePersistence.commitEdit`; the Save button catches and alerts instead of
  dismissing, the shape the Delete button beside it has had since T-322. **The undo restores each
  member's `scheduledDate`/`scheduledStartMin`, not just the block's four fields** — moving a block
  moves its tasks, so a header-only undo would have left them on the day the store refused while the
  alert claimed nothing changed. That is the bug the obvious fix would have introduced.
  **Detector widened, and it re-scopes [[T-497]] from 2 sites to 4.** The new half indexes every
  declaration reaching a swallowed commit to a fixed point *across files*, keyed by callee name **and
  enclosing type**, then reports a success report in the same block. Two frames were required, not one:
  the button called `save()`, `save()` called `updateBundle`, and only the third frame held the `try?`.
  **Type-pairing was measured rather than assumed** — name-only resolution reports 17 sites where the
  paired rule reports 2, and one of the extras was read through and confirmed a genuine false positive.
  The 2 new sites are carried as exemptions with reasons.

- [T-567] **CLOSED 2026-08-31 (`5417b60`).** `canCreate` now requires a title for `.bundle`,
  spelled exactly as `.task` does, and the noun has one home: `TaskBundle.defaultDisplayTitle = "Block"`
  plus `storedTitle(_:)`, mirroring `CadenceEventTitleSupport`'s stored/display split (so a title of
  spaces no longer reaches the store either).
  **Premise correction: the ticket named 3 sites; there were 9 — and 3 of them *stored* the word
  rather than drawing it** (`SchedulingActions.createBundle`, `QuickCreateChoicePopover.create`,
  `TimelineBundleBlockSupportViews`'s `onSubmit`). A display-only fix would have left "Task Bundle" in
  the database. All 9 now read the constant or `bundle.displayTitle`.

- [T-569] **CLOSED 2026-08-31 (`f3d87e3`).** The four named sites now go through
  `TaskTitleSupport.displayTitle(_:fallback:)` with the compact fallback, so **the trim is the only
  thing that changed** — the copy stays "Untitled" rather than being promoted to `displayTitle`'s
  default "Untitled Task". Repo-wide remainder measured: **25 sites** still spell
  `title.isEmpty ? "..."` across `Cadence/`, `CadenceWidgets/` and `CadenceMCPServer/` (the ticket
  estimated ~20). Split out as [[T-609]].


- [T-574] **CLOSED 2026-08-31 (`54cc616`).** Premise reproduced exactly. `saveAPIKey` now throws
  `AISettingsError.emptyAPIKey` on an empty/whitespace draft instead of falling through to
  `removeAPIKey()`; macOS's Save button is additionally disabled and dimmed on a blank draft, matching
  what `iOSActionButton(isDisabled:)` already did. **Both halves were fixed deliberately** — a disabled
  button is not testable in isolation, and the credential loss lived in the manager, so fixing only the
  button would have left the hazard reachable from any other caller. `AIAPIKeySaveGuardTests` pins the
  stored key surviving `""`, `"   "` and `"\n\t "`, that `saveAPIKey`'s body never reaches the removal
  path, and that neither platform offers a live Save on a blank draft. Two mutations, three tests
  killed, each confirmed compiled.

- [T-575] **CLOSED 2026-08-31 (`e509ae2`).** macOS's one-click `confirmationDialog` replaced by
  `SettingsDataResetConfirmationSheet` behind `PrivacyDataResetConfirmation.authorizes` — **the shared
  gate now has two callers instead of one.** iOS untouched, so the guarded path was raised to meet the
  unguarded one rather than the reverse. The doc comment calling the split deliberate, and the matching
  sentence in `docs/app-review-notes.md`, were corrected rather than left asserting machinery the code
  no longer has — the exact defect class [[T-565]] exists to catch. `AppStoreReviewReadinessTests`' pin
  on "requires the word DELETE to be typed" still passes. One mutation, one test killed.

- [T-576] **CLOSED 2026-08-31 (`19fd461`).** Premise reproduced on **both** platforms. T-253's
  hook was **generalised rather than copied**: new `Cadence/Shared/CadenceAuthorizationLifecycle.swift`
  takes a refresh *closure* instead of a `RemindersManager`, because the two managers share no protocol
  and disagree on async-ness — but agree on *when*. That is the right seam. All four reminders call
  sites are unchanged; `notificationsAuthorizationLifecycle` is new on both platforms, so both panes now
  re-derive on appear **and** on foreground. Reminders file keeps a tombstone. Two mutations, three
  tests killed.

- [T-591] **CLOSED 2026-08-31 (`1f53aa8`).** Compound key now split on
  `CadenceTaskDropSupport.separator` and applied part by part; the parse extracted as the pure
  `TasksPanelSupport.dropAssignments(forDropKey:)`, testable with no `ModelContext`. **The half that
  mattered more:** `assignTask` reports whether anything resolved and `handleSectionDrop` returns it,
  so an unresolvable key now bounces the row instead of swallowing it. `handleTaskDrop` still returns
  `true` deliberately (the reorder ran either way) and says so. 8 tests; two mutations, **both
  confirmed compiled** — restoring the parse bug killed 6, restoring the unconditional `true` killed
  exactly 1, which is the attribution that matters: the silent-accept guard has its own test,
  independent of the parse. Follow-on filed as [[T-607]].

- [T-592] **CLOSED 2026-08-31 (`c39ff74`).** `isEmptyState` now also requires both past-due
  summary arrays empty, matching `iOSTodayTaskSections`, with iOS's reasoning carried into a comment.
  Mutation killed `theMacTodayIsNotEmptyWhileAPastDueCardIsOnScreen` alone; the test also asserts a
  genuinely empty day still reports empty, so the guard cannot be satisfied by never returning `true`.
  **One thing the ticket did not have:** macOS needs no rollover-notice clause, unlike iOS's guard —
  the banner's rows are `overdoTasks`, which `isEmptyState` already counted. The agent recorded that in
  the comment rather than copying a clause that would be dead here.

- [T-593] **CLOSED 2026-08-31 (`7dea6b5`).** All three sites — rows, Completed rows and the
  drop indicator — now read `TaskListDisplayMetrics.taskTrailingInset`, the sibling's own constant
  rather than a restated `12`. Leading stays 16, extracted as `todayRowLeadingInset` with a comment on
  why it differs from the shared 52. **Build-verified only, not looked at** — no test pins it and the
  app was not launched. Convergence proposed as [[T-608]], deliberately not done.


- [T-352] **CLOSED 2026-08-31 (`5ae916a`).** Premise confirmed and then *inverted*: no persistence was
  added, per the user's decision, because the defect was never a missing feature — it was a comment in
  `macOSRootSupportViews.swift` asserting a launch-restore mechanism that has never existed.
  `@SceneStorage` appears in **zero** of the 300+ files under `Cadence/`. Comment rewritten with a
  tombstone naming the claim it replaced. `CadenceRootSelectionLaunchContractTests` (3 tests) now pins
  both the code contract (the wrapper is read off the `selection` declaration by regex, so a *new*
  persisted `*selection*` property also fails) and the prose contract. Non-vacuity proven by two
  mutations that were **confirmed to compile** before their kills were believed.

- [T-487] **CLOSED 2026-08-31 (`53e223c`).** `.byDoDate` deleted along with every branch, helper, view
  and derived value that existed only to serve it: 4 section builders, 6 flat-section helpers, the
  frozen list/flat snapshot chain, 4 orphaned views, the grouping control, and
  `byDoDateBase{Tasks,SortedTasks}` — which were computed **unconditionally**, so every Today render
  filtered every task and fully sorted the result for a mode nothing could reach. Net -711/+151.
  Tests were retargeted rather than dropped. The first full run surfaced **2 genuine regressions**,
  which is evidence the source scans were reading this change rather than passing through it — one of
  them found a needle pinning two call sites as "two that must agree" where the second was inside a
  function whose own doc said *"Currently unreferenced"*. Green at 3719 tests, 0 warnings.
  **Deliberately not done, now [[T-564]]:** `TasksPanelMode` is single-case and was NOT collapsed, and
  `TasksPanelDropCoordinator.taskDropHandler` was left unreferenced rather than half a currying pair
  removed. Both are design changes the user has not seen.

- [T-556] **CLOSED 2026-08-31 (`3eb8237`).** Suite renamed to `CadenceControlAccessibilityLabelTests`
  to match its file. All four repo-wide mentions of the old name were checked and **none was an
  invocation**. The T-552 hazard was *demonstrated rather than asserted*: against one build, the old
  suite name ran **0 tests and xcodebuild called that a success**, while `xcb.sh`'s guard refused it
  with exit 4; the new name ran 12.

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

- [T-488] **`iOSListEditorSheet`'s Area row has the defect [[T-446]] just fixed for Context.** Same file,
  one row down the same `Form`: `areaTitle` (`iOS/iOSListEditorViews.swift:83`) resolves against
  `areas.filter(\.isActive)` while `selectedArea` (`:510`), which `save()` uses, resolves against the
  unfiltered `areas`, and the popover offers only active ones. So editing a project whose area was since
  deactivated **shows "None" and saves the inactive area**. There is no shared support type for area
  picking to route it through — `CadenceContextPickerSupport` is the model to copy.
  **Closed 2026-08-30 **by generalising [[T-446]]'s list rather than copying it**. The two support types were diffed before choosing: everything was identical except offerability and the untitled label, so `CadencePickerSupport` is now generic over a `CadencePickable` and the Area and Context types are a typealias plus those two facts. **The offerability difference matters** — an area has three states, so copying Context's `!isArchived` rule would leave a *completed* area offerable; the mutation that swaps it in kills a test by name. `theAreaPickerSupportIsNotASecondCopyOfTheContextPicker` pins that exactly one file declares the rules, so the [[T-374]] near-copy cannot come back. `Project` is deliberately not conformed — nothing picks a project alone. Third instance of the split filed as [[T-514]].**

- [T-490] **`CadenceChoiceRow` defaults its `id` to `AnyHashable(title)`, and 32 call sites take the
  default.** Two options with the same displayed title collide into one `ForEach` identity in
  `CadenceChoicePopoverList`. [[T-446]] passed an explicit id at its three context sites; the other 32 in
  `Cadence/iOS/` still default. Either make `id` non-defaulted or derive it from `value`, which is
  already `Hashable`, rather than from the title.
  **Closed 2026-08-30, **more strongly than the ticket proposed**. Rather than making `id:` mandatory, the parameter is **removed** and identity is `AnyHashable(value)` as a computed property — checked across all 35 call sites, including the `["none"] + areas`, `[-1] + minutes` and `[nil] + goalIDs` concatenations, and `value` is already what `selection` compares against. That takes the decision away from authors instead of asking 35 of them to answer it.**

- [T-492] **`iOSNoteEditorSheetHeader` hand-spells the editor-sheet host gutter.** Residue from
  [[T-281]] — the fix that closed one duplication opened this one.
  `.padding(.horizontal, isRegularWidth ? 20 : 18)` is exactly
  `iOSEditorSheetMetrics.gutter(isRegularWidth:)`, which five surfaces read and whose own comment says it
  exists so that figure is stated once. Worse, T-281's `oneSharedViewOwnsTheNoteEditorHeaderRamp`
  **asserts the literal is present**, pinning the copy in place. Closing it is one line of view source
  plus removing the named exclusion in `noEditorSheetSurfaceSpellsTheHostGutterRampItself`. Worth doing
  for a second reason: `iOSEditorSheetMetrics` sits outside `#if os(iOS)` so `CadenceTests` can read it,
  so routing the header through it converts that ramp into a behavioural assertion.
  **Closed 2026-08-30. `iOSNoteEditorSheetHeader` reads `iOSEditorSheetMetrics.gutter(isRegularWidth:)`; the named exclusion is deleted so the allowlist is down to the file that defines the ramp. **The ticket's second reason is the one that paid**: [[T-281]]'s test listed the margin as the literal `isRegularWidth ? 20 : 18`, so it was *pinning the copy in place*. It names the shared call now and states the figure as a value, which `iOSEditorSheetMetrics` sitting outside `#if os(iOS)` makes possible — converting a source-shape assertion into a behavioural one. Proved by mutation rather than claimed: flattening `gutter` to `20 : 20` **never touches the header file's text** and the header's own test still fails, which the pre-T-492 version could not have done.**

- [T-495] **`MarkdownEditorView` replaces `NSTextView`'s dragged-type registration rather than adding to
  it.** `registerForDraggedTypes` sets the accepted-type list wholesale and `configure(_:context:)` has
  called it unconditionally since before [[T-478]], so the macOS note editor may accept only the types
  Cadence names — **plain-text and RTF drags into a note might silently do nothing**. **Not measured**: no
  drag was performed, and `NSTextView` re-registers `acceptableDragTypes` on its own at various points,
  which may already restore them. Cheap to settle by hand — drag selected text from another app into a
  note. If real, union with `super`'s types in `CadenceTextView.registerMarkdownDraggedTypes()`.
  **Closed 2026-08-30 **as not a defect, disproven by measurement.** On a real offscreen `CadenceTextView` built exactly as `makeNSView` builds it: with registration never called, `registeredDraggedTypes == []` at *every* step of the real sequence — so there was nothing for `registerForDraggedTypes` to displace; it adds 3 to an empty list. **AppKit's own re-registration unions rather than replaces**: toggling `isEditable` yields 22 types, `acceptableDragTypes`' 19 plus Cadence's 3. And the proposed union has a measured cost — `acceptableDragTypes` carries the legacy TIFF and PNG names **even with `importsGraphics` off**, so unioning would re-advertise bitmap drags at a refusing host and **undo half of [[T-478]]**. Residual, filed as [[T-511]]: whether a plain-text drag reaches the editor at all in the running app, which is not answerable headless and is not caused by Cadence's call either way.**

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
  **Closed 2026-08-30. **The 21 re-measured and confirmed at exactly 21.** Four sites routed through `commitInsert` — `CreateContextSheet.create`, `CreateListSheet.create` (which records *which* switch arm ran, so the undo cannot un-insert the wrong one), `HabitsFormSheets.create` (whose `scheduleReconcile` fetches the habit table back, so it would have scheduled a reminder for a row about to be un-inserted), and `TimelineEventBlockSupportViews.openEventNote`. **[[T-497]]'s trap does apply to the macOS twin**: `noteForEditing` forwards to the same shared function, so it returns an existing note as often as it creates one and a blind `commitInsert(of:)` would delete a note the user already had — pinned through the macOS *wrapper*, since a forwarder that dropped its `insert:` closure is how this platform could inherit the shape without the behaviour. **Half 3's exemption list is empty, and that emptiness is the claim**: 16 of 17 helpers subtract by signature (`: ModelContext` in the parameter list *is* "my caller owns the unit of work" — deliberately not bare `ModelContext`, since `commit: (ModelContext) throws -> Void` is a commit handed *in*), and the 17th owns its context and commits two hops away, so commit-reach follows same-file calls to a fixed point.**

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
  **Closed 2026-08-30, both platforms. macOS: `readablePasteboardTypes` returns `super`'s list unchanged when the flag is false — it was the only one of that class's three image doors not reading a flag its two neighbours already read. iOS: a new `allowsMarkdownImageInsertion` consulted in `canPerformAction` **before** `UIPasteboard.general.hasImages`, so a refusing host never raises the "pasted from" banner to answer a question it has already answered; set in `makeUIView` **and** `updateUIView`, the second being load-bearing because quick create flips `kind != .event` on a live text view. `paste(_:)` is left unguarded on purpose — its fall-through to `super.paste` is already correct and pinned. **The advertisement was the door.****

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
  **Closed 2026-08-30. **The four labels were seven and the ~20 sites were 45**, in 20 files across all three targets — re-measured rather than inherited, under a stated rule (declare iff the literal appears at ≥2 sites in ≥2 files), which added `"Untitled Area"` (9), `"Untitled Project"` (8) and `"Untitled Reminder"` (2). **No line of the sweep changed** — [[T-499]]'s harvest already read `Models/`, so declaring the constants was the whole fix, and the sweep went from silent to naming all seven the instant a declaration existed. **Kept deliberately behaviour-preserving**: every site kept its own guard rather than being routed through `display(_:fallback:)`, because `display` trims and `isEmpty` does not — converting 45 sites would have been a silent behaviour change to whitespace-only titles smuggled in under a de-duplication. Residues filed as [[T-512]] and [[T-513]].**

- [T-508] **The `try? save()` rule keys on `save()` specifically, so it misses `try?` on commit helpers
  and file writes.** Distinct from [[T-503]] and found the same way — by two real defects it could not
  see. The sweep's patterns are `try? save()` and `try? modelContext.save()`, so
  `try? CadenceSavedLinkPersistence.insert(...)` ([[T-507]]) and `try? content.write(to:)` ([[T-506]])
  both pass all halves. **Widen the vocabulary to the commit surface rather than the method name**: any
  `try?` on a `CadencePendingChangePersistence.commit*`, on a `Cadence*Persistence` helper, or on a
  `Foundation` write whose failure the caller then reports success over. Measure the new hit count
  before shipping — the value of this rule so far has been that 86% of sites legitimately pass it.
  **Closed 2026-08-30 **with the measurement, and one carve-out**. Widened to the commit surface (`try?` on a `Cadence*Persistence` helper) and generalised `isPresented = false` to `is<Something> = false`. Measured over 552 files: **either half alone finds 0 new offenders; both together find exactly 1**, and that one is [[T-507]], now held in `reportExemptions` cross-referenced — whoever fixes it must delete the entry or the rot test fails. **`write(to:)` deliberately excluded**: measured at +0, and [[T-506]] is invisible not because of the needle but because nothing after that write reports success in source — the report is the *absence* of an error sheet. Out of the rule's shape, not hidden from it. Recorded in the rule so nobody re-derives it.**

- [T-501] **`docs/TODO_DONE.md`'s "Landed in" SHAs record where a ticket was *removed*, not where it
  shipped.** Found while applying [[T-462]]'s title recovery: T-285's entry reads "Landed in `0dd7258`",
  whose subject is *"Deduplicate docs/TODO.md"* — a bookkeeping commit that changed no Swift.
  [[T-462]]'s measurement explains why: **175 of 200 archived tickets were removed by commits that
  touched only `docs/TODO.md`.** So an unknown share of the 177 existing entries attribute a fix to a
  commit that did not contain it, which is worse than a missing SHA because it reads as authoritative.
  Establish how many are wrong before deciding whether to re-derive them.
  **Closed 2026-08-30 — **and the ticket's premise did not survive measurement. 5 of the 177 entries had a wrong SHA, not ~175.** I filed this by generalising one example (T-285 citing a "Deduplicate docs/TODO.md" commit); the generalisation was wrong. [[T-462]]'s 175/200 figure measured **removal** commits for the 200 tickets that were *never archived* — a different population. The archive mostly does not cite removal commits at all: 79 entries cite a deliberately different commit, and of the 85 that do cite their removal, 80 are large code batches that shipped the fix *and* closed the ticket together (the per-batch citation counts match the "N fixes" in each batch's own subject). **The bug was in T-462's reconstruction fallback, not in the archive's convention.** All five were recovered and corrected — T-284→`96b5583`, T-285/T-286/T-288→`b05869d`, T-361→`5d2c196` — plus six entries that had no SHA but did have code behind them, and T-279's entry, which still claimed "working tree, not committed" after `cb53c78` committed it. **The other 172 are deliberately not re-derived**: two independent channels corroborate them, and a blanket `git log -S` pass would replace correct attributions with first-touch SHAs, which for a symbol like `MarkdownHeadingRamp` lands on the wrong ticket entirely. Nine remaining SHA-less entries are correctly SHA-less — closed by splitting, audits that changed nothing, or shipped as `AGENTS.md`/`scripts/` changes where a docs SHA is the right answer.**

- [T-485] **Three sibling suites still leave fabricated launch reports in the test host's `UserDefaults`.**
  Demonstrated live by [[T-480]]'s own final run, which left `dataIntegrityRepair.lastReport.v1` =
  `{"source":"test"}` behind. `DataIntegrityRepairServiceTests` (11 call sites, 1 guarded test),
  `CadenceHabitCompletionDuplicateTests` (3, 0), `CadenceNoteFolderSurfaceTests` (1, 0). Each needs a
  one-line `@Suite(.preservesTheStoredLaunchReports)`. To make it durable rather than a one-off cleanup,
  a `CadenceScanInstrument` sweep asserting every suite that reaches `migrateIfNeeded`/`repairIfNeeded`
  carries the trait.
  **Closed 2026-08-30. Three siblings annotated and `DataIntegrityRepairServiceTests`' now-redundant hand-rolled guard deleted — T-480's precedent is one spelling of the guard, not two. **The durable half is the sweep**: `everyTestSuiteReachingALaunchReportWriterPreservesTheStoredReports` attributes the trait **per suite**, using the extent reader extracted out of `cadenceTestDeclarations` rather than a second copy. Failing-first named exactly the three files; three mutations killed by name, **one of them inside `CadenceScanInstrument`'s own constructor** ("does not fire on its own positive witness"). Leakage re-proved from outside the process with a **full-value** `sha256` of the test host's plist, not a truncated digest — guarded run unchanged, unguarded 407→416 bytes and a different hash — so detection was shown to distinguish guarded from unguarded *before* the green was trusted. The unguarded run left a fabricated report on the real app state and the snapshotted bytes were restored and re-verified.**

- [T-486] **Extension methods declared in non-member files are invisible to the membership guard.**
  [[T-435]]'s own text named this alongside free functions; only the free-function half is closed.
  Measured: **117** extension-method names are declared in files the MCP target does not compile. A crude
  dot-qualified probe surfaced 2 candidates and **both are false positives** — one resolves to a member
  file, one is inside a doc comment — so there is no live violation. A real check needs receiver-type
  resolution, a different instrument from the two in that file, which is why this is separate rather than
  a widening.
  **Closed 2026-08-30 **by refusal, with numbers.** Receiver-blind dot-qualified matching: 138 candidate names, **0 hits in the target** (the ticket's 2 candidates were an unstripped comment and a name resolving to a member file — both vanish under proper stripping). On a 558-file precision corpus, 73 instance-receiver hits of which **≥12 are provably ambiguous inside the repo alone** — `badges.count(for:)` resolves to a nested `func count(for:)`, not to `extension CadenceSidebarLayout` — with framework collisions unbounded without a type-checker. **The sound subset exists and provably adds nothing**: type-qualified `T.m(` is 100% precise, but 85 of 94 candidate pairs have a receiver the existing type guard already rejects, and the 9 with a reachable receiver are all *instance* methods (`Goal.isOverdue`, `Habit.isDone`, …) that can never be spelled `T.m(`. Net new detections: **0**. Widgets identical (90/7/0). **The residual hole is real and named** — a member file writing `goal.isOverdue(...)` breaks `-scheme CadenceMCPServer` while `-scheme Cadence` stays green — and the instrument that resolves receivers already exists and is already shared: `CadenceMCPServer.xcscheme`. This measurement is the argument for [[T-435]]'s own honest close, building that scheme in CI, rather than for a third text scan.**

- [T-493] **`iPadTodaySidePanel`'s kept prefix rests on a claim the code does not keep.**
  `iPadTodaySupportViews.swift` says all three kept types are built only by the two-pane host and "a
  compact width cannot reach any of them". True for two of the three. **False for `iPadTodaySidePanel`**:
  `iOSTodayView.swift:24` names it in an `@AppStorage` default — a stored-property initialiser evaluated
  at every width — and `iOSCompactTabShell`, `iOSTasksTabView` and `iOSSearchView` all construct that
  view at compact width. [[T-283]]'s test silently omitted the enum from its reachability check, which is
  why nothing said so. Either rename it or correct the comment.
  **Closed 2026-08-30 **by renaming, not by softening the comment**. `iPadTodaySidePanel` → `iOSTodaySidePanel` (5 references), value-preserving: the storage key was already the honest `ios.today.sidePanel` and the raw values are untouched, so nothing persisted moves. The argument for renaming: keeping the name required **three permanent pieces of machinery** — a carve-out paragraph, a by-name exclusion inside the sweep's detector, and a dedicated test recording the exception — to preserve four characters, and "iPad-only, except when it isn't" is not a meaning. **The general guard was cheap and precise, so it was built**: `everyIPadPrefixedTypeIsBuiltOnlyFromAWidthGatedHost` **derives** every `iPad`-prefixed declaration from source rather than reading a hand-typed list — which is exactly how [[T-283]] lost this one — and it immediately turned up a fourth uncovered type, `iPadMacStyleRootShell`, which passes but whose passing was not previously known. **Scope stated in the test's own doc**: it catches a *name* against a *gate*, so [[T-352]]'s family (prose inventing a mechanism for something that names no symbol) is still a read, not a guard.**

- [T-86] **Agents building into the shared DerivedData can crash a running Mac app.** On 2026-08-17
  the user hit "Cadence quit unexpectedly" — `EXC_BREAKPOINT` on the main thread, five seconds after
  launch. **Not app code:** the whole backtrace is `dyld` → `libSystem_initializer` →
  `_libsecinit_appsandbox`, i.e. App Sandbox setup failing *before `main()` runs*, and the app
  bundle had vanished from `Build/Products/Debug/` by the time it was inspected — a concurrent agent
  clean build wiped it under the running process. A fresh build into a private `derivedDataPath`
  launched and stayed up. Two agents had already reported `build.db is locked` from the same
  contention. **Mitigation:** every agent brief should require a private `-derivedDataPath`, which
  most already do ad hoc; worth making standing in `AGENTS.md`. Nothing to fix in the app.
  **Closed 2026-08-30. The contention itself cannot be removed — the shared DerivedData is one mutable directory by design — so what was removed is the **exposure**, and it was larger than the ticket knew: **the private-path rule was prose only, and the repo's own runbooks violated it in five invocations** (README build *and* test, apple-release-readiness build *and* test, the distribution archive). Anyone following the README was building into the shared DerivedData. Two measurements sharpen it: a read-only `xcodebuild -showBuildSettings` **also** creates a shared entry with `Logs/`, `SourcePackages/` and `PIFCache`, so "it was only a query" is not a defence; and the entry is keyed to the **project path**, so an unflagged run from the repo root shares the exact entry the user's Xcode uses. Now enforced by `CadenceBuildInvocationHygieneTests`, which sweeps every markdown fence and shell script, plus `scripts/xcb.sh`, which supplies a private path, refuses a shared one, and reports leakage afterwards. **Known hole, declared**: the guard matches a bare `build`/`test` token, so a script assembling its action in a variable would not be classified as a build action.**

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
  **Closed 2026-08-30 **with a detector, because a preflight is impossible.** Measured: `lsof` on `Cadence.xcodeproj/project.pbxproj` returns **nothing** while a real `xcodebuild` holds it — an `NSFileCoordinator` claim is not an open fd — so any `lsof` preflight would report "clear" every time, which is worse than having none. The only observable is the stalled process's own stack, so `scripts/xcb.sh` runs a watchdog that samples its own child when the log stops growing and CPU sits at zero, printing `T-117 CONFIRMED: blocked in NSFileCoordinator` or the top frames of whatever else it is stuck in. **It never kills anything.** The hazard stops being silent, which is all this ticket had downgraded itself to asking for.**

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
  **Closed 2026-08-30 **as not reproducible — and the prime suspect is disproven, not merely unreproduced.** `git archive --format=tar HEAD` runs in **0.06s** for a 13.4 MB / 910-file tree (~220 MB/s), verified to `~/Desktop`, to `/private/tmp`, and under concurrent disk load; the ticket's ~25 min for 15 MB is a 20,000x discrepancy. The blamed `filter.lfs.required=true` is **still set**, `git-lfs` is **still absent**, and `~/.gitconfig` is unchanged since 2026-05-08 — byte-identical to the original measurement — so it cannot have been the cause. Also ruled out: the protected-`~/Desktop` theory (same APFS volume as `/private/tmp`, detached file provider), security software (0 system extensions), and repo shape (2 packs, 3.8 MB, `unpack_trees` at 0.006s). **The original numbers were real**: every sampled size is an exact multiple of the 10240-byte tar record, implying ~1.6s of per-file stall across 910 files. The mechanism is no longer observable (the unified log retains ~1 day) and was almost certainly a transient per-file check on the host. No maintenance was run and none is needed. **The workaround it justified is now retired** — see the closure note below.**

- [T-507] **iOS saved links throw away the shared persistence helper's failure signal** (Codex, P2,
  measured). `iOS/iOSListSupportViews.swift:687` calls `try? CadenceSavedLinkPersistence.insert(...)`
  then clears the title, clears the URL and closes the add form **regardless**; `:699` does the same for
  delete. The helper (`Shared/CadenceSavedLinkPersistence.swift:35-45`) already commits and rolls back
  correctly — the caller discards the answer. **macOS is already right**: `LinksView.swift:109-114`
  catches insert failure and leaves the form open, `:125-130` catches delete. Mirror it, add an iOS
  `actionError` notice near the saved-links section, and pin so iOS cannot reintroduce `try?`. Same
  shape as [[T-470]]/[[T-471]].
  **Closed 2026-08-30. iOS `addLink` catches and leaves the form open with an `actionError`, mirroring `LinksView.swift:109-114`; `delete(_:)` reports too, **even though the rule cannot see it** — its mutation leaves `noSwallowedSaveIsFollowedByADismissOrACompletionHandler` silent, confirming the ticket's note that the report half is blind to a swallow with nothing after it. The `reportExemptions` entry is deleted in the same change, and the mutation that restores the `try?` kills that guard — proof the deletion was live rather than cosmetic.**

- [T-509] **Saved-link URL normalisation mangles an uppercase scheme, on both platforms** (Codex, P3,
  measured). `macOS/Views/LinksView.swift:99` and `iOS/iOSListSupportViews.swift:677` both test
  `hasPrefix("http://")`/`hasPrefix("https://")` **case-sensitively**, so `HTTPS://example.com` becomes
  `https://HTTPS://example.com`. Two hand-rolled checks, one defect, twice — [[T-374]]'s shape. One
  shared normalisation helper read by both, pinned on lowercase, uppercase, mixed case, leading/trailing
  whitespace and scheme-less input.
  **Closed 2026-08-30. One `CadenceSavedLinkURL` in `Shared/` — which the macOS test target compiles, so **both platforms' rule is actually executed** rather than asserted by scan — read by both add forms, absorbing trim, blank-check and scheme so the guard cannot be spelled two ways. **It deliberately does not re-case what the user typed**: `HTTPS://example.com` stays as typed, because the defect was *guessing at a missing scheme*, not casing. `ftp://` remains treated as scheme-less, pinned as existing behaviour rather than quietly changed.**

- [T-516] **Tests are stranding `UserDefaults` plists in the real app container, and it is live.**
  [[T-480]] fixed `withTemporaryDefaults` to derive its suite name from `#function`, but four files still
  roll their own `UUID()` suite name and bypass it. **Measured in the app's own container: 7,727
  preference plists, 316 written in the last 48 hours** — bare `<UUID>.plist`,
  `cadence.tests.external-write.<UUID>`, `cadence.tests.privacy-reset.<UUID>` and
  `com.haoranwei.Cadence.tests.t15.<UUID>`, totalling ~30 MB and growing every run. Sites:
  `CalendarDateMemoryTests.swift:24,174,299,427,459,492` (bare UUID, and `freshDefaults` never removes
  the domain), `CadenceExternalWriteReconcileTests.swift:76,107,134`,
  `CadencePrivacyDataResetSurfaceTests.swift:130`, `CadenceAccentPaletteTests.swift:324`. Each should
  call `withTemporaryDefaults(_:)`. Pin it in [[T-485]]'s shape — no test file may pass a
  `UUID()`-derived suite name to `UserDefaults(suiteName:)` — since the helper's whole point is that the
  file count is bounded at one per test forever. **The existing 7,727 are the user's to delete**; do not
  remove files from that container without asking.
  **Closed 2026-08-30. Four files routed through `withTemporaryDefaults`; `CalendarDateMemoryTests`' `freshDefaults(_ name: String = UUID().uuidString)` and its `removePersistentDomain(forName: defaults.description)` — **which named a suite that has never existed** — are both gone. The helper gained a generic `opening:` overload so a `UserDefaults` *subclass* double can use it, which a default argument could not do. **The rule is wider than the ticket asked, and each widening was forced by a measurement**: three of the four sites passed the suite name **positionally** into a local helper, so a rule reading only the literal `suiteName:` argument would have named **one file of four**; the helper's own `scope` argument is covered too, because routing through the helper and then handing it a `UUID()` scope looks like the fix and leaks identically. **Not measured**: the container's file count — the existing ~7,700 files are untouched and are the user's to remove.**

- [T-527] **macOS Saved Links has four icon-only buttons and zero accessible labels** (Codex, P3; source
  measured, VoiceOver inferred). `macOS/Views/LinksView.swift` contains **4 `Image(systemName:)` buttons,
  0 `.accessibilityLabel` and 0 `.help`** — verified. The header add button (`:34-40`), the row open-link
  button (`:219-228`) and the row delete button (`:230-235`). Same shape as [[T-472]], which established
  that the durable half is naming the parameter `accessibilityLabel` rather than `help`, since a
  parameter called `help` is what tells the next author the string is tooltip-only. Neither T-472 nor
  [[T-484]] covered this file. **Claim only that the label is set** — nothing has launched the app.
  **Closed 2026-08-30, folded into [[T-509]]'s change because it was cheap. New `cadenceControlLabel(_:)` beside `CadenceIconButton`, applied to the header add, row open and row delete buttons. **Correction to the audit**: the file has 4 `Image(systemName:)` but only **3 are buttons** — the fourth is `LinkRow`'s leading decorative glyph, sitting beside the title and URL it would otherwise repeat, and it is deliberately left alone. The inventory is pinned at 4 icons / 3 labels so the next author has to re-decide rather than drift. **Claim is only that the label is set**, in the shape SwiftUI reads it; nothing launched the app.**

- [T-506] **macOS note export can silently fail *after* the user picks a destination** (Codex, P2,
  measured). `macOS/Services/NoteExportService.swift:39,46` write markdown and PDF bytes with `try?`;
  a failed write is swallowed and no UI state records it, so the user picks a folder, sees nothing, and
  has no file. **Three correct patterns already exist** — `iOS/iOSNoteExportMenu.swift:82-85` reports
  `fileExporter` failure, and both data-export sections
  (`macOS/Views/SettingsDataSafetySection.swift:118-126`, `iOS/iOSDataExportSettingsSection.swift:79-87`)
  report theirs. Return/report the error through the macOS caller, then pin it. **Note this is a file
  write, not a `save()`** — see [[T-508]].
  **Closed 2026-08-30, **and there were two silent failures, not one**: the writes used `try?`, *and* a PDF that failed to render left through a bare `guard … else { return }`. Both meant a user who had already chosen a destination got no file and no message. The **service** reports rather than the caller, because the note action picker calls `dismissPicker()` *before* `export` and the write happens later still inside the save-panel completion — by the time there is anything to report, the caller has no sheet left. New shared failure vocabulary in `CadenceNoteExportSupport`, adopted by iOS too. [[T-508]] deliberately excluded `write(to:)` from the `try? save()` rule, so this shape is swept separately — **and that sweep confirmed these two were the only swallowed writes in `Cadence/`.****

- [T-514] **`iOSTaskPlacementBreadcrumb` is the third instance of the display/save split, and the
  worst-reading one.** Found while closing [[T-488]]. `iOSTaskDetailSheet.loadContainerSelection()` sets
  `"area:<id>"` from the task's real area and `selectedArea` resolves against unfiltered `areas`, but the
  breadcrumb (`iOS/iOSTaskDetailComponents.swift:106`) resolves against `activeAreas` and falls through
  to **"Inbox"**. So **a task in a completed or archived list claims to be in the Inbox**, and
  `iOSContainerChoicePopover` offers only active lists so it cannot be moved out.
  `iOSTaskRowActionViews.swift:500-504` feeds the same popover. **Not a `CadencePickerSupport` drop-in** —
  it is a grouped three-way Inbox/Area/Project control, so it needs `selectable(_:selectedID:)` applied
  to both arrays plus the breadcrumb reading unfiltered.
  **Closed 2026-08-30, **observed on a simulator rather than inferred**. On `b8ad9b6` a task in the archived area "Old Ops" showed breadcrumb **"Inbox"** and a picker offering **only "Inbox"** — no row for where the task actually was; after, "Old Ops" and a checked "Old Ops" row. All four `iOSContainerChoicePopover` call sites take the unfiltered arrays and the control narrows itself via `selectable(_:selectedID:)` on **both**; the breadcrumb resolves through the same existence-not-activity resolver the save already used. `Project` is a `CadencePickable` now, so the rule is stated once for its third type — the mutation swapping its offerability to Context's `!isArchived` kills three tests by name. The row context menu's Move to List had the same hole and took the same narrowing.**

- [T-519] **`iOSFocusView`'s detail pane says "Today tasks will appear here" while they are already
  appearing beside it.** With nothing selected it draws "Ready when you are / Today tasks will appear
  here." — but the tasks appear in the **list pane next to it**, and this shows at regular width while
  that pane is full. A false statement in the common case. The house pattern for a detail pane with no
  selection is "Select an item from the list." (`iOSFeatureComponents:529`) / "Select a note". Needs a
  wording decision.
  **Closed 2026-08-30, **and the ticket's stated case is the rarer of two**. Because `selectedItem` falls back to `pickItems.first`, the branch is reached either with nothing ready — and then the picker pane *beside* it was showing the shared focus sentence at the same moment, so **the page made two differently worded promises about itself**, which is the common case — or with a chosen subject deleted while the picker still lists others, which is the ticket's falsehood. Branch one now says the shared sentence; branch two uses the house `iOSFeatureEmptyDetail`. "Today tasks will appear here." retired app-wide. See [[T-533]] for the same defect in its original form on Goals and Habits.**

- [T-521] **A shared component tells macOS VoiceOver to double tap.** `CadenceNotesListSupport`'s folding
  month header sets `.accessibilityHint("Double tap to expand")`, and it is a shared component with
  `.onHover` — so on macOS VoiceOver reads a gesture that is not its activation gesture. Same family as
  [[T-472]]/[[T-484]] but a *hint* rather than a missing label.
  **Closed 2026-08-30 **with the weaker claim kept honestly.** Hint reworded to state the outcome ("Expands to show this month's notes."), matching `CadenceStartupIssueBannerModel`, the app's other shared expand/collapse control; premise verified rather than assumed — `NotesFoldableListColumn` places this header on four macOS Notes pages plus the iPad pane and the iPhone list. **The announcement itself is still not measured**: the agent launched a debug build and found it vends **no AX window tree** (System Events sees only `AXMenuBar`, zero windows, via both a direct `exec` and `open -n --env`), and it refused to enable VoiceOver because that means changing the user's system settings. So the claim stays "the hint is set", as in [[T-472]]/[[T-484]].**

- [T-526] **The iOS Lists empty state points a fresh user at a section that is not on screen** (Codex,
  P3, measured). `iOS/iOSListViews.swift:301` and `iOS/iOSListsRegularPane.swift:41` both say "Create an
  area or project here, or **restore one from Archived**." unconditionally — but the Archived section is
  only drawn when `!archivedAreas.isEmpty || !archivedProjects.isEmpty` (`iOSListViews.swift:256`). On a
  fresh or fully emptied store there is nothing archived, so the copy names a section the user cannot
  see. **The correct pattern is already in the same app**: `iOSSettingsView.swift:307-311` does not
  mention archived restore. Make the clause conditional on the same predicate that draws the section,
  in both shells, and pin the first-launch wording.
  **Closed 2026-08-30. `activeListsSubtitle(hasArchived:)` is a function now, in the shape `isNarrowedToEmpty` already uses, so a call site cannot take the sentence without answering the question. Both shells hold the predicate once as `hasArchivedLists`, read by **both** the empty state and the section that draws — the two-independent-copies shape that caused the drift is gone, and a test pins the expression appears exactly once per file.**

- [T-528] **DECIDE: the default-tag seed reads "store is empty" as "this user has never had tags."**
  (P2, measured.) `TagSupport.seedDefaultTags` has **no latch** — verified, zero `UserDefaults`/`hasSeeded`
  references in the file — and `PersistenceController.swift:87` runs it on **every** launch. Its only
  signal is whether a tag with each default slug is present. Two reachable symptoms from one cause:
  **Rename — reachable today, one device, no CloudKit at all.** macOS Settings > Tags has a pencil on
  every row, and `SettingsTagsSection.saveEdits` writes `tag.slug = TagSupport.slug(for: name)`. Rename
  `bug` to `Defect` and the **next launch re-seeds `bug` beside it**: eight tags where the user curated
  seven, the old name back in the `#` picker and every tag filter.
  **Archive — reachable on a reinstall or a second device.** The store opens before CloudKit lands, so
  the seed mints an *active* `bug` while the user's archived, recoloured one is in flight; when it
  arrives `mergeTagMetadata` resolves `target.isArchived && source.isArchived` (`TagSupport.swift:314`)
  with the fresh row as target, so the answer is `false`. **A tag the user archived comes back, active,
  in the seed's colour, and syncs that to every device.**
  **The sharp framing: this sits twelve lines from code that argues the opposite.**
  `DataIntegrityRepairService`'s own doc comment refuses an orphan sweep precisely because
  `performStartupMaintenance` runs with no gate on sync state and "it is the *empty* store that would
  delete the most". Three of the four startup passes are written to be inert against a store that is
  empty only because sync has not landed; **the fourth inserts because of it.**
  Pinned by `renamingADefaultTagBringsTheOriginalBackOnTheNextLaunch` and
  `theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet`, which encode *current* behaviour and
  go red the moment the seed learns to tell the two stores apart. Options: a `UserDefaults` seeded-latch,
  a sync-state gate, or seed-on-demand. `mergeTagMetadata`'s `&&` is **not** independently wrong — an
  active duplicate legitimately un-archives — so do not "fix" it there.
  **Closed 2026-08-30 **by seed-on-demand, and confirmed by looking before the fix**: launched a private-store build, renamed `bug` to `Defect` exactly as `SettingsTagsSection.saveEdits` writes it, relaunched — **7 tags in, 8 out**, `bug` back beside `Defect`. The seed lost every unprompted caller (`performStartupMaintenance`, both Settings > Tags `.onAppear`s, and `CadenceMCPStorePreparation.prepare`, `stepCount` 4→3); `TagSupport.seedDefaultTags` is behaviourally unchanged and still reached from the "Add Defaults" controls that already ship. **Rejected with reasons: the `UserDefaults` latch fixes the rename only** — on a second device there is no latch and no data by construction, so it is absent exactly when it would need to fire, and it is invisible to the MCP server, a separate process opening the same store. **The sync-state gate is not reachable**: the only signal is a notification SwiftData does not expose, it never fires when iCloud is signed out, and the fallback reintroduces the race. `mergeTagMetadata`'s `&&` untouched — an active duplicate legitimately un-archives, so the bug was minting the duplicate. **Cost accepted, stated plainly: a new user's first `#` picker says "No tags"** until they type a name or press Add Defaults — see [[T-532]], which is the macOS half of that.**

- [T-529] **`clearMissingEventLinks` writes where its sibling only reports.** (P3, code path measured,
  the race inferred.) `CalendarLinkedTaskSupport.swift:21-32` runs unattended on every
  `EKEventStoreChanged` (`macOSRootStateSupport.swift:59`, `SchedulePanelDataSupport.swift:28`), fetches
  every `AppTask`, clears `calendarEventID` wherever `event(withIdentifier:)` returns nil, and saves. Its
  only guard is `isAuthorized` — so **"EventKit has not loaded this event yet" and "this event is gone"
  are the same answer.** The neighbouring surface takes the opposite posture: `CadenceCalendarLinkHealth`
  only *reports* a dead link and hands the user a re-pick, and
  `withoutCalendarAccessNothingIsReportedMissing` exists for exactly this false positive.
  **Reachability checked before filing**: `AppTask.calendarEventID` is documented as having no current
  writer, so a new TestFlight tester cannot hit this — it is reachable **only from stores written by an
  earlier build**. But those values are exactly what the reader is kept for, and the clearing is silent,
  irreversible and CloudKit-propagating.
  **Closed 2026-08-30 **by requiring evidence, not by converting the sweep to a reporter.** `CalendarEventLookup` gains `hasLoadedCalendars`, and `canTrustLookupMisses` is that conjoined with `isAuthorized` — so a store that has produced no calendars, which is exactly the state an `EKEventStoreChanged` from a permission grant leaves you in, no longer reads as "every event is gone". The question is split out as `missingEventLinks(in:calendarManager:)`, which reports and writes nothing, so the sibling's posture is reachable from the same rule. **Residue left deliberately**: one account still syncing while others have loaded leaves `allCalendars` non-empty, so a link into that account is still clearable on a miss — per-source evidence is not cheap in EventKit, and no current writer produces a non-empty `calendarEventID`.**

- [T-512] **Two functions build the labels [[T-505]] just declared, and no literal sweep can see them.**
  `iOSListDeletionSupport.swift:40` and `iOSListWindDownSupport.swift:85` are near-identical `name`
  properties returning `"Untitled \(kind.noun)"` / `"Untitled \(noun)"`, where `noun` is
  `"Area"`/`"Project"`/`"Context"` — so **at runtime they produce exactly `defaultAreaName`,
  `defaultProjectName` and `defaultContextName`.** Renaming any of those three constants leaves these
  two behind, silently. This is the [[T-500]] shape (a duplicated *function*) doubled by the sweep's own
  stated exclusion: interpolated literals are dropped by the harvest regex **by construction**. Both
  files' comments already claim they use "the same 'Untitled …' fallback" as each other — the claim is
  true and nothing holds it true.
  **Closed 2026-08-30 — **and the fix is the smaller half**. Both builders read the constants now, but the shape is held by `noSourceFileBuildsAPlaceholderLabelByInterpolation`, whose needle is **derived** from `defaultCompactTitle` rather than spelled, so renaming the family **re-points the rule instead of emptying it**. A mutation renaming `defaultAreaName` turns four tests red — the property the ticket said nothing held. Putting the mapping on `CadenceListDeletionKind` in `Shared/` was load-bearing: it is what let the macOS test target **evaluate** the labels rather than only scan for them.**

- [T-513] **Two copy defects [[T-505]] deliberately did not launder.** (1) `iOSFeatureDetailViews.swift:83`
  labels an untitled **milestone** `"Untitled Goal"` — inside `iOSEditorSection(title: "Milestones")`,
  iterating `milestones` — while `iOSTaskDetailSheetSections.swift:65,77` and
  `iOSTaskRowActionViews.swift:395` say `"Untitled Milestone"` for the same kind of row. (2)
  `"Untitled task"` is lower-cased at `SchedulePanelComponents.swift:88` and
  `macOSRootSupportViews.swift:527` (and as a `TextField` placeholder at
  `iOSTaskDetailComponents.swift:72`) against `defaultTaskTitle`'s capital. **Both change what a user
  reads and neither is decidable from the literal**, so both were left visible rather than folded into a
  constant — which would have frozen the drift under a fix that looks like cleanup.
  **Closed 2026-08-30. (1) fixed: the milestone row said `defaultGoalTitle` inside a "Milestones" section iterating `milestones` — the residue was the wrong **constant**, since [[T-505]] had already de-literalised the line. (2) **decided rather than deferred**: the two `Text(...)` sites are labels over a *value*, and 18 other surfaces render that value as "Untitled Task", so they read `defaultDisplayTitle` now. `iOSTaskDetailComponents.swift:72` is a `TextField` **prompt** — a different piece of copy, and every other title prompt in the app is a noun phrase — so it stays, recorded with its reason. See [[T-539]].**

- [T-515] **The rest of the "Untitled …" family, below [[T-505]]'s ≥2-files rule.** `"Untitled List"`
  (`TaskBundlePickerSupportViews.swift:179,211` — 2 sites, one file), `"Untitled subtask"`
  (`MarkdownTaskEmbedDrawingSupport.swift:429,511` — 2 sites, one file), `"Untitled Column"`
  (`iOSColumnWindDownSupport.swift:50` — 1 site). Real but weaker: **a constant with one call site is a
  name, not a de-duplication.** Recorded so the omission is a decision rather than an oversight.
  **Closed 2026-08-30 **by declining to widen the rule**. A constant with one call site is a name, not a de-duplication, and **no repetition threshold ever reaches `"Untitled Column"`'s single site** — so widening was the wrong instrument for the case that motivated the ticket. Replaced with the sweep's **dual**: `everyPlaceholderLabelInTheAppIsDeclaredOrRecorded` requires every `"Untitled …"` in all three targets to be declared or listed with a reason, keyed by **site** so a recorded label cannot spread. The existing sweep asks "is a declared constant re-typed?"; this asks "is every label declared?" — together there is no way left to produce one without reading a constant or writing down why not.**

- [T-520] **`CadenceTodayPresentationSupport.emptyScheduleHint` asks for a tap, from `Shared/`.** It ends
  "…tap an hour to schedule one." and lives in `Cadence/Shared/`, but has exactly **one** reader,
  `iOSTodaySchedulePanel`. Correct today, wrong the moment a Mac surface picks it up. Move it to an
  iOS-only constant or reword it. [[T-528]]'s `noMacReachableCopyAsksForATouchGesture` sweep covers
  `Cadence/macOS/` only and structurally cannot see this one.
  **Closed 2026-08-30 — **it was never actually shared**. macOS's `SchedulePanel` draws no empty state at all, so the sentence had one reader and was correct only because no Mac surface had picked it up yet. Moved to `Cadence/iOS/iOSSchedulePanelCopy.swift`, wording unchanged, deliberately outside `#if os(iOS)` so the macOS target pins the value rather than reading source. **The gap is closed generally**: `noDesktopCopyAsksForATouchGesture` is now `noMacReachableCopyAsksForATouchGesture` and walks `Cadence/Shared/` too — a shared folder's copy must be true on the desktop whether or not the desktop reads it yet. It was the only live offender there.**

- [T-522] **Converge `"List not found"` and its subtitle, then delete the allowlist entry.** They are
  duplicated in `ListDetailView.swift` and `iOSRootSidebar.swift` because
  `CadenceDeletedSelectionGuardTests.theMacMissingListStateReusesTheSentenceIOSAlreadyShips`
  **deliberately pins them as matching literals**, so converging means rewriting that suite's assertion
  to read the constant instead. Doing so removes the single entry in `CadenceEmptyStateAuditTests`'
  `emptyStateDuplicateAllowance`.
  **Closed 2026-08-30, **allowance and its staleness check both deleted**. `missingListTitle`/`missingListSubtitle` read by both views; the glyph stays a literal because a symbol name is a picture, not a sentence. `theMacMissingListStateReusesTheSentenceIOSAlreadyShips` was **rewritten rather than removed** — it asserts convergence, which is what pinning matching literals was standing in for. `noEmptyStateSentenceIsSpelledInTwoFiles` is unconditional now and the tree has zero duplicates.**

- [T-523] **`iOSGoalAttachListsSheet` branches on an untrimmed query.** It is the one *correct*
  filter-aware empty state in the app, but a whitespace-only query still reports "No matching lists".
  One line: `CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: query, filterNarrows: false)`.
  **Closed 2026-08-30, and the behavioural reason is sharper than the ticket's: `GoalLinkPresentation.candidateGroups` **trims before matching**, so a whitespace query returns the whole library — meaning the only reader `query.isEmpty` could mislead was one with **no lists at all**, greeted on a first run with "No matching lists / Nothing matches that search."**

- [T-525] **`GoalTimelineView`'s first-run subtitle overstates what is required.** "Create a goal, then
  set its date range." — but a goal with no end date still gets a roadmap row, rendered "No date", so
  creating one is sufficient. Copy deliberately preserved as-is by the empty-state work rather than
  reworded under a change that looked like cleanup.
  **Closed 2026-08-30, **premise verified by running rather than reading**. `rows` is built from `GoalMissionGrouping.groups`, which reads no date at all, so one undated goal already leaves the empty state — it draws a rail row with a "No date" chip; only the *bar* needs both dates. New copy names a button this page's own toolbar draws, pinned by regex, and the old sentence is a `cadenceRetiredCopy` entry so it is swept app-wide rather than only here.**

- [T-532] **macOS tag pickers give a fresh store no route to the default set.** The direct consequence of
  [[T-528]]'s seed-on-demand decision, and a parity gap: `TaskTitleInlineTagPicker.swift:40` and
  `TagPickerPopoverViews.swift:114` both render a bare `"No tags"`, while
  `iOSTaskDetailComponents.swift:400` offers **"Add Default Tags"** in exactly that state. So a brand-new
  macOS user meets "No tags" with no affordance — they can type to create inline or go to Settings, but
  **the iOS pattern is the better one and macOS should match it.** Worth doing before a TestFlight build
  if T-528's decision stands.
  **Closed 2026-08-30. Both macOS pickers ask one `TagPickerPlaceholder.resolve` and render one row, offering **Add Default Tags** — iOS's wording — when the catalogue is empty. **The old condition read the *filtered* list**, which is why one sentence covered two unrelated states; `TaskTitleInlineTagPicker` is handed `hasActiveTags` now rather than inferring it, and the mutation reverting that inference kills a test by name. Two truths fixed in passing: a query that matched nothing says "No matching tags" (tags exist, so "No tags" was false), and the restore row no longer draws "No tags" beneath itself. **The seed call is in a Button action and nowhere else** — [[T-528]]'s `noUnpromptedCodePathSeedsTheDefaultTags` gains this file, and the mutation adding an `.onAppear` beside it kills that guard, so it demonstrably still bites. **Cost stated: the offer is click-only**, as the sentence it replaces was.**

- [T-533] **Goals and Habits detail panes have [[T-519]]'s defect in its original form.**
  `iOSFeatureViews.swift:225` and `:398` draw "Select an item from the list." **unconditionally**, while
  the `listPane` beside them shows "No goals yet" / its habits equivalent on a fresh store. **At iPad
  regular width a new user sees "Select an item from the list." next to a list with no items.** Same
  one-line fix shape as `unselectedDetail`; not covered by the T-519 test, which is scoped to
  `iOSFocusView`.
  **Closed 2026-08-30, **observed on an iPad Pro simulator before and after** — "No goals yet" beside "No goal selected / Select an item from the list.", then both panes saying the chooser's own sentence. **The ticket's fix shape was right but its analogy was wrong**: [[T-519]] needed `if pickItems.isEmpty` because its picker can be full with nothing selected, and these two panes **cannot reach that state** — `selected` falls back through the whole collection, so `nil` means the collection is empty, which is the same `count == 0` the chooser already draws its empty panel on. A copied guard would have been a branch with a dead side. Both fallback expressions are pinned so that stops being true loudly. Copy is now one `iOSFeatureEmptyState` per screen read by **both** panes.**

- [T-534] **The macOS container picker is the other half of [[T-514]].**
  `ContainerPickerFilterSupport.groups` (`macOS/Views/ContainerPickerSupportViews.swift:26-31`) filters
  `$0.isActive`, so a task in an archived or completed list gets a popover with **no row for where it
  is**. Milder than iOS — `ContainerPickerBadge.label` already resolves unfiltered, so the *name* is
  right and only the correction affordance is missing. Same fix shape: `selectable(_:selectedID:)`,
  which needs the picker to learn the current selection. **Also visible in the same function and
  unmeasured**: the grouping is `contexts.compactMap { … $0.context?.id == context.id }` and
  `Area.context` defaults to `nil`, so **a context-less area appears in no group at all.**
  **Closed 2026-08-30, **and the ticket's unmeasured second defect is the larger half**. Headline took the [[T-514]] shape: `groups` learns a **required** `selection:` and narrows both arrays through `selectable(_:selectedID:)`; mutations neutering the areas and the projects halves kill *different* tests, so the fix demonstrably reaches both. **The context-less defect is real — there is no fallback bucket in this control** (the body draws Inbox then `ForEach(groups)` and nothing else) **but the app already ships one**: `CadenceSidebarLists.sections` gives these models an "Other" section on iPad, and its doc comment already named the macOS gap. The bucket reuses that constant, keyed on the *offered* context set, which also catches a list whose context was never handed to the picker. **The reachability is asymmetric and that is the sharp part**: iOS offers "None" unconditionally in every mode and writes it; macOS's create sheet requires a context and its edit sheet has **no context control at all** — so the Mac inherits by sync a list it can neither file into nor correct. **Not observed on screen**, and deliberately: a debug build vends no AX tree, so there is no way to open the popover and a screenshot would be zero evidence. See [[T-538]] for the sidebar, which is worse.**

- [T-537] **`clearMissingEventLinks` fetches every `AppTask` before its guard.**
  `CalendarLinkedTaskSupport.swift:77-84` builds a full `FetchDescriptor<AppTask>` on **every**
  `EKEventStoreChanged` and only then reaches `canTrustLookupMisses`. Hoisting the guard above the fetch
  is one line.
  **Closed 2026-08-30, guard hoisted above the fetch. [[T-529]]'s `hasLoadedCalendars` reasoning untouched and the array overload still guards, so this is the early check rather than the only one. **Pinned as source order, not behaviour, and deliberately**: the fetch is `modelContext.fetch` and no fake can count it. The assertion is scoped to that overload's own body and was validated against unmodified source first. The mutation removing the guard kills **only** that test — all six neighbouring behaviour tests stay green, which is what shows the change moved *when* the question is asked and not what it answers.**

- [T-462] *(narrowed 2026-08-30, measured by replaying all 210 revisions of the file: the gap is **200, not 284**. All 200 are recoverable verbatim, but that is ~33k tokens onto a file whose purpose is to be cheap to search — and **87.5% were removed by bookkeeping commits that changed no Swift**, so each entry's SHA would need its own bisect: 200 investigations for a file half of which would be blank. **Do not backfill.** The cheap half is done — 32 entries reading `(title not recovered)` were unsearchable and all 32 titles were recovered from the file's own revisions (the earlier reconstruction had searched commit *messages*), and the header count, which had never been true at any revision, now reads the real 177. Residue: [[T-501]].)* **`docs/TODO_DONE.md` had no `T-4xx` entry at all until `ca06ad1`+1.** Eighty-five tickets
  closed in this session were removed from Open and never archived, and the same gap runs back to
  T-01 — **284 in total**. Today's 85 are now reconstructed from git history; the older 199 are not.
  Either backfill them the same way or state that the archive begins at this session and stop
  implying otherwise.
  **Closed 2026-08-31 — **the last residue was one sentence, and it is now in the file.** Everything else measured as genuinely done: the header count is truthfully 177, all 32 `(title not recovered)` placeholders are gone, and [[T-501]] fixed the five wrong SHAs. What remained was the ticket's *other* branch: the archive silently implies completeness. Measured coverage is a **hard cliff, not diffuse thinning** — 96% of T-300..399 is accounted for, against **10–13% of T-1..199**, with 211 unaccounted ids below T-300 and 39 above it. Yet the header instructs *"Search here before filing anything that sounds familiar"*, which below ~T-200 **cannot work**: a search returns nothing whether or not the ticket was closed — precisely the re-filing failure the header exists to prevent. The header now states where the archive begins and that a miss below ~T-200 is not evidence a ticket is new.**

- [T-518] **The MCP plugin runner rebuilds into a path it may be executing from.**
  `plugins/cadence-mcp/scripts/run-cadence-mcp.sh` defaults `DERIVED_DATA_PATH` to the repo-local
  `.codex-build` and then `exec`s `$DD/Build/Products/Debug/CadenceMCPServer`. A rebuild into that path
  while another plugin process is running the binary is [[T-86]] for the MCP server. **The warm reuse
  looks deliberate** — the script's own comment says so — so this is a flag for a decision rather than
  a defect to fix blind.
  **Closed 2026-08-30 — **the premise does not reproduce, and the mechanism explains why.** `otool -L` shows the binary links only `/usr/lib` and `/System/Library`: the SPM dependencies are **statically linked** and there is no `.dylib` or `.framework` under `Build/Products/`, so the image is self-contained at `exec`. All three failure modes tested twice: **rebuild while a server is live** — the link *replaces the file* (inode changed) and the live process kept answering `tools/list` correctly; **`xcodebuild clean` under a live server** — the binary is deleted from disk and the process is entirely unaffected; **concurrent rebuilds into one path** — both exit 0, no `build.db` lock. **None of corrupt / fail / silently-stale.** This differs from [[T-86]] because the app is a `.app` bundle whose dyld loads frameworks and resources lazily from paths under `Build/Products/`; this target is one self-contained executable. Keep the warm reuse. Residual, real but not what the ticket feared: `set -euo pipefail` means a failed build exits before `exec`, so a broken binary is never run.**

- [T-524] **65 string literals are duplicated across two or more files under `Cadence/`** — measured,
  beyond empty states. The Settings sections duplicate ~15 between
  `iOSCalendarSettingsSection`/`SettingsListManagementSections` and
  `iOSNotificationsSettingsSection`/`SettingsNotificationsSection`, and the recurrence/calendar-scope
  alerts duplicate 4 across three files each. **The [[T-374]] sweep cannot see any of them, because no
  constant exists yet** — that sweep catches a *shared constant re-typed*, not copy that never became
  one. Same convergence job as [[T-528]] at roughly 7x the size.
  **Closed 2026-08-30 across two agents. **Settings half**: 13 literals converged into 13 constants across 5 view files, all now inside the [[T-374]] sweep's harvest — three of six mutation kills came from that sweep rather than the new tests. **Alerts half**: 4 recurrence/calendar-scope sentences, 6 call sites, one `CadenceRecurrenceScopeCopy`. **The divergence check found four drifts behind byte-identical literals**: the macOS connect menu passed its name to `.help` where iOS used `.accessibilityLabel` (fixed — an icon-only Menu named only by a tooltip is [[T-472]] two screens outside the sweep that guards it); the macOS access card draws an **amber warning triangle for the not-yet-asked state** where iOS draws a neutral glyph (iOS is right, filed); the macOS work-hours subtitle names "Weekly calendar views" when the highlight is per day-column **and also appears in the Schedule panel** (filed); and macOS's empty-calendar row has no subtitle against iOS's two-line row (filed). **Exclusions are as load-bearing as the conversions**: `"Apple Calendar"` is one literal for **at least two concepts** across 7 files, so declaring it would create 7 offenders at once. See [[T-543]]–[[T-547]].**

- [T-536] **Two iOS sheets still hand-spell the container token arithmetic.**
  `iOSCalendarQuickCreateSheet.swift:53-65,417-422` and `iOSTaskDetailSheet.swift:48-65` re-derive
  `dropFirst(5)`/`dropFirst(8)` and the untitled-name fallback instead of
  `CadenceTaskComposerSupport.selection(fromToken:)` / `containerName(for:areas:projects:)`. **Not a
  defect** — both already resolve against unfiltered arrays — but it is the [[T-374]] near-copy those
  helpers now exist to remove, and the detail sheet's private members even share the helpers' names.
  **Closed 2026-08-30, **and the divergence check found one**. Two of the sites were equivalent, but `iOSCalendarQuickCreateSheet.containerTitle` tested `name.isEmpty` while the shared helper **trims first** — so a whitespace-only list name rendered as a *blank tile* there and "Untitled Area" on every other surface, and a padded name kept its padding. **Latent, not live**: both list editors normalise on write, so no user could reach it — but adopting the helper closes it in the strictly-correct direction. A **fourth site the ticket did not name** (`CreateGoalSheet.attachInitialList`) was converged too, which is what let the guard assert "exactly the declaring file" instead of carrying an exemption list that would rot.**

- [T-540] **The duplicate-copy audit cannot see any filter-aware empty state.** Found by [[T-522]]'s own
  agent. `CadenceEmptyStateAuditTests`' regex matches a literal placed **directly** after
  `message:`/`title:`/`subtitle:` — so copy behind a `?:` branch is invisible, **and every filter-aware
  empty state in the app is written in exactly that shape.** Two live examples: `"No goals yet"` and
  `"No matching goals"` are spelled in both `GoalsView.swift` and `GoalTimelineView.swift`. Same family as
  the vacuous detectors this session keeps finding, and inside [[T-524]]'s scope.
  **Closed 2026-08-30 — **measured before converging, which is the whole point.** The reader now takes the *whole argument expression* after `message:`/`title:`/`subtitle:` rather than a literal sitting directly after the colon, and matches the label only at the call's top level. Re-measured over `Cadence/`: the old reader saw **11 distinct empty-state literals and 0 duplicates**; the widened one sees **25 and 2** — **14 newly visible, 0 lost, 0 false positives.** Nothing to refuse. The old regex was wrong a second way too, proven by a failing test: it harvested `icon: symbol(for:title:"unused")` as a *title*. The 2 duplicates were `"No goals yet"`/`"No matching goals"`, **byte-identical — one edit from the drift two other pairs were already found in, and nothing in the app could have reported it.** The two *subtitles* stay apart deliberately and are pinned as values: the list has a search field and status picker, the roadmap has one popover button labelled *Filter*, so each sentence is true of its own toolbar.**

- [T-542] **Three exact near-copies of `CadenceTaskComposerSupport.container(of:)` remain.**
  `TasksPanelComponents.swift:371-373`, `SchedulePanelComponents.swift:35-37`,
  `TaskEmbedFieldEditorPopover.swift:244-246` each spell the same three-line task-to-selection getter.
  [[T-534]] added the shared accessor and used it at the new site only, to keep that diff reviewable.
  **Not a defect** — all three are correct — but it is the [[T-374]] near-copy the helper now exists to
  remove, same family as [[T-536]].
  **Closed 2026-08-30. All three getters were logically identical to `container(of:)` — area tested before project in each — so this was pure convergence with no divergence to report. The wiring half of the guard is what catches a *differently-spelled* near-copy: a mutation rewriting one site in different words is killed by the wiring assertion while the shape sweep stays silent, which is [[T-161]]'s rule made mechanical rather than asserted.**

- [T-548] **The duplicate sweep covers 2 of the app's 5 empty-state components, and the other 3 have
  drifted.** `componentNames` lists only `EmptyStateView(` and `iOSEmptyPanel(`;
  `iOSFeatureEmptyState(`, `iOSFeatureEmptyDetail(` and `CadenceInlineEmpty(` are invisible. Measured:
  adding them surfaces **2 more duplicates, and unlike [[T-540]]'s these have already drifted** —
  `"No goals yet"` in 3 files (macOS *"Create a goal for an ongoing direction, then nest milestones inside
  it."* vs iOS *"Create a direction, then nest milestones and habits underneath it."*) and `"No habits
  yet"` in 2. macOS's Goals page **does** show habit counts under a goal, so its sentence is *incomplete
  rather than false*. Choosing the true sentence per platform is a copy decision — **and
  `theGoalsAndHabitsDetailPanesNeverNameAListWithNoItems` pins the iOS spelling at exactly one occurrence,
  so any convergence must edit that test in the same change.**
  **Closed 2026-08-31. **The component set is derived, not listed** — every `struct` under `Cadence/` whose name carries `Empty` or `Placeholder`, harvested through `codeOnly`. Adding names was rejected as the weak fix: the list is exactly what went stale. **2 → 23 components, 0 false positives**, measured *before* converging: HEAD saw 23 literals and **0** duplicates; widened saw 47 and **2**. Both predicted duplicates were live (`"No habits yet"`, `"Select a note"`), plus the `"No goals yet"` **retype** a file-counting sweep structurally cannot see. **Three fail-closed guards** so an uncovered component is a failure rather than a silence — including a *second, structural* derivation (a `View` with glyph + headline + subtitle, `…Row` subtracted **as a rule with zero allowlist entries**) that fails when the two derivations disagree. **M1 reproduces the ticket mechanically**: with the hardcoded two restored, the three coverage guards go red while `noEmptyStateSentenceIsSpelledInTwoFiles` stays **green**. Titles converged; **subtitles reported, not picked** — Goals is a *three-way* split (macOS list, macOS roadmap, iOS) and macOS's is **incomplete rather than false**, since its Goals page does show habit counts.**

- [T-552] **`-only-testing:` with a suite name that does not exist is a green run over zero tests.**
  Measured 2026-08-31: `-only-testing:CadenceTests/<NoSuchSuite>` returns `Executed 0 tests`,
  `** TEST SUCCEEDED **`, `EXIT=0`, **with no warning and no diagnostic**. It takes a *suite* name, not a
  *file* name — and **42 of 256 test files declare more than one suite while 15 declare none matching
  their own basename**, so any run scoped by filename against those exercises nothing and reports
  success. The batch-8 agent nearly filed a false "this sweep is blind" finding from exactly this: the
  same mutation re-scoped to the real suite name killed a test. Rule added to the runbook (assert the log
  contains the test you mutated, not just the exit code); **the durable fix would be a guard that every
  test file declares a suite matching its basename, or a runner that refuses a zero-test run.**
  **Closed 2026-08-31 **by a runner that refuses, not a naming rule.** `scripts/xcb.sh` now exits **4** on a `test` run that executed no test, with a diagnostic naming the filter; `check-test-log <log>` applies the same check to an existing log — verified by hand: real green log → 0, zero-test log → 4. **The basename guard was rejected on measurement**, and the numbers are the argument: **486 of 3750 tests live outside their file's basename suite**, so making `-only-testing:<basename>` *valid* would convert today's **loud zero into a quiet subset** — a run that passes, looks normal, and silently skipped most of the file. It also cannot catch a typo and leaves [[T-465]]'s wrong-sibling case untouched. **The ticket's own figures did not reproduce**: actual is 257 files, 33 multi-suite, **14** basename-mismatched — 13 of them multi-suite, so "rename the 15" was really "rename one, restructure thirteen". The detector counts per-test result lines and **deliberately not** the `Executed N tests` summary, because a run that dies before any test never prints that line — keying on it would read total silence as a full run.**

- [T-553] **Three more absence sweeps whose needle nothing can witness.** Same shape as the blind sweep
  batch 8 fixed, smaller blast radius — each needs a `CadenceScanInstrument` with a literal fixture:
  `CadenceColumnWindDownSurfaceTests.iOSWindsDownAColumnThroughTheSharedServiceFromOnePlaceOnly`
  (`$draft.isArchived`/`$draft.isCompleted`, **0 occurrences repo-wide**),
  `CadenceBundleInspectorHostTests.theBundleHostAsksTheOneSharedRuleAboutTheTwoFactsItCanSee`
  (`CadenceTaskInspectorPresentation`, comment-only), and
  `CadenceSharedBoardChromeTests.theMonthGridsWeekdayRowHasNoSizeKnobLeft` (`weekdaySymbolSize`,
  comment-only). Also: `CadenceSidebarCountMetricsTests` spells its needle **twice** (sweep at `:507`,
  self-check at `:545`), so a typo in the sweep's copy alone is invisible — one-constant fix. And
  `noSettingsPaneStillPaintsUnderTheSystemSeparator` is dead weight, strictly subsumed by its
  line-break sibling which counts the walk and has a detector test.
  **Closed 2026-08-31. All three sweeps go through `CadenceScanInstrument` with literal fixtures and non-vacuous walks; two also pin that the comment-blanking reader genuinely differs from a raw read. `CadenceSidebarCountMetricsTests`' needle collapsed to one constant read by both the sweep and its self-check. `noSettingsPaneStillPaintsUnderTheSystemSeparator` **deleted** as a strict subset of its line-break sibling, with its positive `CadenceRowDivider` table moved into the survivor. **Proved both ways**: blinding each detector kills it with `.blind`, and planting each needle as live code makes each sweep name the planted file. The instructive one is the tint needle — **the blinded sweep still passes, because it inherently cannot detect its own blinding, while the witness reading the same constant fails.** That asymmetry is the entire fix.**

- [T-510] **Release packet and review notes disagree about which platforms ship** (Codex, P3, measured
  doc drift, **not a runtime bug**). `docs/app-store-submission-packet.md:13` says *Platforms: macOS*,
  while `docs/app-review-notes.md:8` says Cadence targets macOS **plus iOS/iPadOS from one app target**,
  and the project lists `iphoneos iphonesimulator macosx`. If the next submission is Mac-only the packet
  should say so explicitly; if it includes iOS/iPadOS, the packet and its readiness tests need updating.
  **Decide before submitting, not after.**
  **Closed 2026-08-31 **by the user's decision: macOS only for 1.0.** Neither document was factually wrong — `app-review-notes.md` described the *build* accurately while the packet mirrors an App Store Connect *field*, which is a per-submission choice. The packet, the SKU (`cadence-macos`), the reviewer script and `apple-release-readiness.md` are all macOS-shaped and self-consistent, so **the packet stands and the review notes' iOS/iPadOS claims are the ones to narrow**. The project genuinely builds `iphoneos iphonesimulator macosx` with complete iOS icons — that stays true and simply is not what is being submitted. Revisit when iOS ships: [[T-535]] records that nothing in the release gate ever compiles the iOS surface.**

- [T-538] **The macOS sidebar drops a context-less list entirely — worse than [[T-534]]'s picker.**
  `SidebarContextSection` derives rows from the relationship (`(context.areas ?? []).filter(\.isActive)`,
  `macOS/Views/SidebarComponents.swift:96-97`), iterated per `Context`, and `sidebarListItem(contextID:)`
  takes a **non-optional** id. So a list with `context == nil` is not merely un-grouped — **it is invisible
  in the macOS sidebar.** iPad draws the same region through `CadenceSidebarLists.sections` and gives it
  "Other". Same cause, same fix shape and same iOS-creates/macOS-inherits reachability as T-534's second
  defect: iOS offers "None" unconditionally, macOS can neither create nor correct that state.
  **Closed 2026-08-31. `SidebarView.listSections` buckets flat `@Query` results through a new generic overload of `CadenceSidebarLists.sections`, which the flattened iPad spelling is now **implemented as** — one bucketing rule rather than two. `sidebarListItem(contextID: UUID)` is gone; the two model→`Item` initialisers moved into a shared `CadenceSidebarListsBridge` that reads `area.context?.id`. **The non-optional was the whole defect and it was never a narrowing**: the optional was *discharged by the iteration* — `ForEach(contexts) { $0.areas }` never constructs the nil case, so no compiler diagnostic could exist. That is the real shape here: **traversal-derived rendering silently defines its own domain, and its blind spot is exactly the rows where the relationship is nil.** `keepingEmptyContexts` is the one legitimate platform difference and is load-bearing — the macOS header carries the "+" that opens `CreateListSheet`, the only route to a list in a given context there. **A second defect fell out: lists inside an archived context were equally invisible on the Mac** and now land in "Other" too. Ten of eleven new tests killed by at least one of eight mutations (the eleventh is unkilled and declared as such). **Create half confirmed on an iPhone simulator** (`ZCONTEXT IS NULL` in the store); **macOS render not confirmed by eye and not claimed** — `screencapture` refuses this app's window, the debug build vends 0 AX windows, and a frontmost-guarded capture aborted when focus moved.**

- [T-549] **`CalendarRecurrenceEditScope` cannot be shared while `CalendarManager.swift` is one
  `#if os(macOS)`.** `iOSCalendarEventEditSheet` privately re-declares it — same cases, raw values, labels
  and `EKSpan`s, byte for byte — and until [[T-524]] **nothing pinned either copy**, which is the state
  [[T-200]] found the *task* scope enums in. The real fix is moving the enum to `Cadence/Shared/`, which
  deletes the private copy outright; `thePhonesPrivateCalendarScopeEnumMatchesTheMacOne` holds the line
  meanwhile and **should be deleted as part of that move**. Note the pin asserts the `EKSpan` mapping too,
  not just the labels — equal words over a wrong span would **destroy a series** while passing a
  label-only check.
  **Closed 2026-08-31. `CalendarRecurrenceEditScope` moved to `Cadence/Shared/` verbatim — cases, raw values, labels and the `EKSpan` mapping all preserved — and `private enum iOSCalendarRecurrenceEditScope` is deleted, 5 references repointed. **`thePhonesPrivateCalendarScopeEnumMatchesTheMacOne` was replaced rather than merely deleted**: it existed only because the duplication did, but dropping it outright would have left the `EKSpan` mapping unpinned, and **equal labels over a wrong span would destroy a recurring series while passing a label-only check**. Two successors took its place. No MCP or widget build needed, established by reading the target source lists rather than building speculatively: each pulls three files from `Shared/` and **zero** from `macOS/`, and neither list contains the moved file.**

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

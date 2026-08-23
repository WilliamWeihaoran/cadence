# Cadence Agent Guide

This file is the first stop for coding agents. `CLAUDE.md` has a longer product and feature history; this file is the compact working map.

## Project Snapshot

Cadence is a native SwiftUI productivity app with a fully built macOS surface, shared SwiftData models, CloudKit sync, Apple Calendar/EventKit integration, and a large, actively-developed iOS/iPadOS surface (not a stub — see `Cadence/iOS/AGENTS.md`).

Primary target:
- `Cadence.xcodeproj`
- scheme: `Cadence`
- platform: macOS

Useful build command (run from the repo root; the private `-derivedDataPath` is the
non-negotiable below, not a suggestion):

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ build
```

Tests **must** be scoped to `CadenceTests`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ -only-testing:CadenceTests
```

Both flags are repeated in `Cadence/AGENTS.md` and `Cadence/macOS/AGENTS.md`, which are the guides
an agent actually reaches for. They printed the bare command for a long time while this file called
the private path non-negotiable — a rule that lives only in the guide nobody is standing in is a
rule that gets copied around.

An unscoped `test` run also pulls in `CadenceUITests`, which cannot launch headless and aborts
the whole run. The failure reads like a broken suite rather than a harness problem — do not
conclude "tests can't run here" from it.

**Writing a test that reads source files as text? Read "Source-Scanning Tests: The Two Ways They Go
Wrong" in `Cadence/Shared/AGENTS.md` first.** Those tests caught several real regressions in one day
and produced every defective assertion a verifier found in the same day; the substring trap,
comment-stripping, non-vacuity, and "mutate what you claim to pin" are all written up there, once.

**Warning baseline: 0 on macOS, 0 on iOS.** It was three until `651694b` (`MarkdownLinkSupport`
was itself a main-actor isolation warning and went with the `nonisolated` pass), then two —
`SchedulingService` and `SettingsNotificationsSection` — until T-96 cleared both. Neither was a
bug: the first was a `guard let task` whose body had been emptied when the three scheduling
assignments moved into `TaskCreationDraft`, the second an `await MainActor.run` wrapper that was
already on the main actor and discarded `NSWorkspace.open`'s `Bool`. The baseline is now zero, so
**any** warning is a regression introduced by the change in hand.

**The baseline covers all three schemes** — `Cadence`, `CadenceWidgets` and `CadenceMCPServer`.
It used to be measured only on `Cadence`, and `CadenceMCPServer` sat at two warnings underneath it
unnoticed, because the run that checked that scheme read its *exit status* and never grepped its
output. Exit 0 says nothing about warnings. Grep the log, and grep it with **no path filter**: a
main-actor isolation regression this session surfaced under synthesized macro paths and slipped
past a `grep "/Cadence/"` entirely.

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models. Read this before changing persistence or relationships.
- `Cadence/Services/` - 50 shared services (`ls Cadence/Services/*.swift | wc -l`): schema, migrations, notifications, widget support, the list/context delete cascades (`CadenceListDeleteHelpers.swift`), the 27 `Markdown*` parsing/mutation files (25 of them named `*Support.swift`; re-count when you add one), plus `AI/` and `MCPReadOnly/`. Note the markdown *logic* lives here, not in `macOS/Editor/`.
- `Cadence/Shared/` - design tokens (`Theme.swift`), shared components, date/time utilities, hover styling, and cross-platform presentation/query support (`Cadence*Support.swift`).
- `Cadence/macOS/` - main product surface. Most active work happens here.
- `Cadence/macOS/Views/` - macOS feature screens and support views (167 `.swift` files at the time of writing; re-count with `ls Cadence/macOS/Views/*.swift | wc -l` rather than trusting this figure).
- `Cadence/macOS/Services/` - macOS-only managers for focus, calendar, hotkeys, task creation, hover state, task deletion, scheduling, note export, Apple account. **Not** reminders, **not** the privacy data reset, and since `c84732e` **not the list/context delete cascades**: `RemindersManager`, `PrivacyDataResetService` and `ListDeleteHelpers` are all cross-platform and live in `Cadence/Services/` (`CadenceRemindersManager.swift`, `CadencePrivacyDataResetService.swift`, `CadenceListDeleteHelpers.swift`), each leaving a tombstone under its old unprefixed name. That is **three** tombstones, not the two this line used to imply, and there is no longer a fourth: the `CalendarVisibilityPreferences.swift` tombstone was deleted outright by `6f71a70` once no file of that base name existed anywhere to collide with. Details in `Cadence/macOS/Services/AGENTS.md`.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor bridge (11 files since the T-105 split). High risk; preserve NSTextView behavior carefully.
- `Cadence/iOS/` - large, real iOS/iPadOS surface covering Today, Calendar, Tasks, Focus, Goals, Habits, Notes, Lists, Search and Settings (93 `.swift` files at the time of writing; re-count with `ls Cadence/iOS/*.swift | wc -l`). iPhone runs a four-tab bottom bar (`iOSCompactTabShell`); iPad keeps its sidebar. Do not assume feature parity with macOS. **Adding a task surface here: read "The Task Inspector Is Presented By A Host, Never By A Row" in `Cadence/iOS/AGENTS.md` first** — a row that owns a `.sheet` presenting the inspector is a shipped bug, four times over, not a style choice.
- `CadenceWidgets/` - widget extension. Compiles a subset of app sources (models, `Theme.swift`, `Cadence*WidgetSupport.swift`) directly into the extension target.
- `CadenceMCPServer/` and `plugins/cadence-mcp/` - MCP server/plugin surfaces. Separate integration boundaries with their own build and verification procedure — read `CadenceMCPServer/AGENTS.md` before changing shared models or services that they compile.
- `CadenceTests/`, `CadenceUITests/` - test targets. `CadenceTests/` is a flat directory of 177 `.swift` files at the time of writing; **look for an existing file before adding one**, and re-count with `ls CadenceTests/*.swift | wc -l` instead of trusting this number. It is the figure the guides cite when they tell you to reuse a test file, so an undercount is what produces duplicate suites — it read "~140" through 158, 164, 167, 171 and now 177.
- `docs/` - support, privacy, and App Review notes (the public site + submission material).

## Scoped Guides

Read the nearest scoped `AGENTS.md` before editing under that tree:

- `Cadence/AGENTS.md` - app-wide source rules.
- `Cadence/Models/AGENTS.md` - SwiftData relationship and persistence rules.
- `Cadence/Services/AGENTS.md` - service/migration boundaries.
- `Cadence/Shared/AGENTS.md` - shared UI/utilities rules.
- `Cadence/iOS/AGENTS.md` - iOS surface boundary (large, real UI — not a stub; parity with macOS is not guaranteed).
- `Cadence/macOS/AGENTS.md` - macOS feature architecture.
- `Cadence/macOS/Services/AGENTS.md` - macOS manager/service boundaries.
- `Cadence/macOS/Editor/AGENTS.md` - AppKit-backed markdown editor cautions.
- `Cadence/macOS/Views/AGENTS.md` - view splitting and current feature map.
- `CadenceMCPServer/AGENTS.md` - **the** MCP boundary account: what the target compiles, why app→MCP coupling is silent, what the write path can do, and how to verify. The other guides point here.
- `plugins/cadence-mcp/AGENTS.md` - the plugin wrapper and the smoke test that is the MCP router's only coverage.

Do not add an agent guide to every folder by default. Add one when a subtree has unique rules, high churn, or a boundary that agents repeatedly misunderstand.

## Non-Negotiable Patterns

These four are restated by the user more often than anything else. They are enforced by the
code, and every one of them has been violated by a shipped change at least once.

- **No hardcoded colours.** Every colour comes from `Theme.*`, or from a user-owned
  `colorHex` on a list/calendar/habit/tag/section. No `Color(hex:)` literals, no bare
  `.white`/`.black`/`.gray` — `Theme` has named tokens for foreground-on-colour, scrims,
  shadows and borders precisely so call sites stop inventing their own. This includes the
  `CadenceWidgets` target, which has `Theme.swift` in its Sources phase so it can comply.
- **Page headers do not describe the page you are already on.** A subtitle under "Notes"
  saying "Write and organize your notes" is noise; the `subtitle` parameter is gone. Search
  result rows, empty states, and picker rows *keep* their subtitles — those say something the
  screen does not. There is now **one** header view per platform to enforce that in:
  `DesktopPageHeader` and `iOSPageHeader`. This bullet used to name `CommitmentPageHeader` and
  `CadenceSettingsHeader` beside `DesktopPageHeader`, which was accurate until `5aa11dc` and is
  now misleading in the direction that costs: both are name-only wrappers, so a header change
  landed three times was landed twice too often. See `Cadence/Shared/AGENTS.md` for the wrapper
  list and for why `CadencePageHeaderSurface` has a third `.desktop` tier rather than reusing
  `.regular`.
- **One hover/selection layer at one radius.** Stacked hover backgrounds at mismatched radii
  have shipped independently in the task inspector, group headers, tab bars, sidebar rows,
  and the notes action menu. If a row already has a `rowBackground`, do not add a second
  `.background()` on another layer.
- **Prefer one shared component over near-copies.** The three kanban boards and the two
  estimate pickers each drifted apart before being unified. `KanbanCard`,
  `CadenceBoardColumnHeader` and `KanbanColumnScroll` are now shared by the list board, the
  All Tasks board, and the Calendar Board — parameterize them, never fork them. **The header's
  name is `CadenceBoardColumnHeader`**, and there is no `BoardColumnHeader`: three guides spelled
  it that way in five places, which reads as a macOS type when it is a `Shared/Components/` one
  that iOS's list kanban, Calendar Board and month agenda render too. `KanbanCard` and
  `KanbanColumnScroll` really are macOS-only, so this bullet is a statement about the three *macOS*
  boards plus a shared header, not a cross-platform trio.
- **Build into a private `-derivedDataPath` whenever another build may be running.** The shared
  DerivedData is a single mutable directory: a clean build deletes `Build/Products/`, and anything
  launched from there dies in `libsecinit` before `main()` with an `EXC_BREAKPOINT` that looks like
  an app crash and is not. It also produces `build.db is locked` failures that look like flaky tests.
  Every failure mode it causes is **misattributed by default** — it never says "another build is
  running", it says whatever the half-deleted directory happened to look like when you read it. On
  2026-08-18 it reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt
  `SourcePackages`, which read as a broken checkout and briefly made a correct agent report look
  wrong. Rule: a build failure you cannot explain is a private-`derivedDataPath` re-run before it is
  a finding. Note `-derivedDataPath` requires `-scheme`; it is rejected with `-target` alone.
  **It isolates the build, not the test host's container.** A macOS `xcodebuild test` run launches
  `Cadence.app`, which uses the one app-group container at `~/Library/Containers/com.haoranwei.Cadence/Data/`
  no matter where DerivedData points — so two simultaneous macOS test runs corrupt each other. Check
  for another run first and wait it out; see `docs/TODO.md` T-236 for the measurement and the tell.
  **Match the pattern carefully.** `pgrep -f "xcodebuild test"` matches *any* process whose command
  line contains that string — including the shell running your own wait loop, so
  `until ! pgrep -f "xcodebuild test"; do sleep 10; done` never exits, and a plain
  `grep xcodebuild` over `ps aux` reports your own grep as a hit. Match the binary path —
  `pgrep -f "Developer/usr/bin/xcodebuild test"` — or capture the PID when you launch and wait on
  that.
- **Never create a simulator device; launch the macOS app only through the wrapper.** Two recurring
  leaks the user has had to clear by hand.
  *Simulators:* agents kept running `simctl create` and naming devices after themselves
  (`Cadence-T195-Agent`, `…-iPad`, …). A created device **persists in the pool with all its data**
  after `simctl shutdown`, so shutting it down is not cleanup — the Devices directory went 3.8 GB →
  7.7 GB in one batch, and enough booted devices push the load average past 40 and kill other agents
  on a 600 s watchdog. Share one existing **stock** device, boot it only if
  `xcrun simctl list devices booted` is empty, and never `erase`, `shutdown` or `delete` it: another
  agent is probably mid-run on it.
  **On a shared device, an app vanishing to the Home screen is an *external* termination until the
  log says otherwise.** `xcrun simctl privacy <udid> grant|revoke|reset <service> <bundle-id>` kills
  a *running* app by design — tccd logs
  `Terminating com.haoranwei.Cadence[<pid>] because access to the kTCCServiceReminders service
  changed` and launchd_sim logs `exited with exit reason (namespace: 11 code: 0x0) - OS_REASON_TCC`.
  It writes **nothing** to `~/Library/Logs/DiagnosticReports`, raises no exception, and truncates
  the app's own log mid-sentence, so it reads exactly like a `SIGKILL`-shaped SwiftUI crash. Another
  agent running it lands on *your* session with no warning. That misread cost T-267 a top-priority
  crash ticket against a date picker that was never at fault. One command settles it before you
  start bisecting a view:
  `xcrun simctl spawn <udid> log show --last 5m --style compact --predicate 'process == "tccd" OR process == "launchd_sim"' | grep -E "Terminating|OS_REASON"`.
  The `sender_pid` on the preceding `TCCAccessSetInternal` is CoreSimulatorBridge when a host
  `simctl` call caused it. `frontboard(10) code:force-quit` and `runningboard(15)` (an
  `installcoordinationd` reinstall) are the other two external kills that look like crashes here.
  *The macOS app:* launching it is legitimate — macOS is the primary surface and some things can only
  be confirmed by looking. Launching the **shipping configuration** is not: it opens the user's real
  CloudKit-backed app-group store as a *second writer* while their own copy may be running, and such
  instances have hung and needed a force-quit, one of them for 15 hours. Use
  `./scripts/run-macos-app.sh start <path/to/Cadence.app> <id>`, which sets
  `CADENCE_LOCAL_STORE_ONLY=1` (no CloudKit, and `CadenceAppDelegate` skips
  `registerForRemoteNotifications()`) and `CADENCE_UI_TEST_STORE_ID=<id>` (store redirected to
  `$TMPDIR/CadenceUITestStores/<id>/`), refuses to start if the user's own Cadence is running, and
  records the PID. **Pair every `start` with a `stop <id>` in the same turn** — `stop` is idempotent,
  escalates to `kill -9` if the app hangs, and removes the private store.
  `./scripts/agent-cleanup.sh` reports these leaks and `--apply` reclaims them; a `SubagentStop` hook
  runs it automatically. It deliberately spares scratch directories touched in the last 30 minutes
  and **never** touches a `Build/Products/Debug/Cadence.app` process while any `xcodebuild` is alive,
  because that path also matches xcodebuild's own **test host** and killing it mid-suite reads as a
  flaky test. Treat the hook as a safety net, not a licence to skip your own cleanup.
- **One directory per agent, and clean only inside it.** The scratchpad root is shared. Make
  **one** directory of your own under it — the session scratchpad path plus your PID, e.g.
  `.../scratchpad/agent-$$/` — put both your isolated source tree and your `-derivedDataPath`
  *inside* it, and let your `rm -rf` name that directory and nothing else. This said "use a
  PID-unique `-derivedDataPath`", and two agents read it as a unique *filename* under the shared
  root, then deleted each other's DerivedData mid-run with `rm -rf` on sibling paths — a
  unique name is not isolation if the cleanup step can still reach a sibling. Cleanup is also not
  optional: the scratchpad reached **64 GB** in one session and filled the user's disk. Delete your
  directory when you are done, and only yours.
- **Isolate the tree with `rsync`, not `git archive` — and restore HEAD by hand.** `git archive
  --format=tar HEAD` over the whole tree runs at about **5 KB/s** on this machine (sampled every 10s:
  1259520 → 1310720 → 1372160 → 1484800 → 1525760 → 1576960 bytes), i.e. ~25 minutes for a 15 MB
  working tree. Worse, it produces a **0-byte file** for the first minutes, so two invocations were
  killed at 2 and 3 minutes as apparent hangs — it looks like a broken repo and is not
  (`git rev-parse HEAD` is 0.018s; `git archive HEAD -- AGENTS.md` for one file is instant). Suspected
  but unconfirmed: a global `filter.lfs` with `required = true` while `git-lfs` is not installed
  (`-c filter.lfs.process= -c filter.lfs.required=false` did not help; the repo has no
  `.gitattributes`). See `docs/TODO.md` T-237.
  The working recipe, and **step 2 is not optional** — skip it and you silently verify another
  agent's in-flight code as if it were yours:
  1. `rsync -a --exclude '.git' --exclude '.codex-build' --exclude '.DS_Store' --exclude 'default.profraw' <repo>/ <tree>/` — a couple of seconds.
  2. Read `git status --porcelain`. For every path *another* agent modified or deleted, restore
     HEAD's bytes into the copy with `git show HEAD:<path> > <tree>/<path>`; for every path they
     added, `rm` it from the copy. Then check each one: `git show HEAD:<path> | shasum` must equal
     `shasum < <tree>/<path>`. This is the part `git archive` gave for free.
  3. `shasum` your own changed files into your scratchpad, so at report time you can prove what you
     tested is still what is on disk.
- **Poll for your own background results; never wait for a notification.** Completion notifications
  are delivered to the **main session**, not to subagents — so a subagent that "waits for the
  notification" simply ends its turn, and the task stops there with its work half done. Two agents
  stalled this way in one night, each having already written its code. Launch long work in the
  background and poll a marker file with a bounded loop:

  ```
  i=0; until [[ -f "$D/all.done" ]] || (( i >= 180 )); do sleep 10; (( i++ )); done
  cat "$D"/*.exit
  ```

  **The loop must be inside ONE tool call.** Polling with one call per check is the single most
  expensive mistake available here: an agent doing that made **1113 tool calls** in 68 minutes and
  still ended stalled, having produced nothing the ticket asked for. The loop above is one call that
  waits up to 30 minutes. The same applies to the lock — acquire, build and release in one
  invocation with a `trap`, not by re-checking from separate calls.

  Related: run a long build in the background against a log you poll rather than in the foreground —
  a 10-minute tool timeout will not survive a cold build of this project, and an agent was killed by
  exactly that. And acquire the test-host lock and run the build **in the same shell invocation**,
  because each command runs in a separate process (which is why the lock is a lease, not a liveness
  check).
- **Check the log says which tree it built.** An isolated tree can be deleted out from under a
  running build (see above); the failed `cd` then falls through to the live repo and the run reports
  **exit 0 against the wrong sources**. This happened on 2026-08-18 and was caught only by grepping
  the log for the path xcodebuild echoes. Confirm your isolated path appears in the log before
  trusting the result. `build.db is locked` and `unable to spawn swift-frontend` on a fresh private
  path are the same contention and clear on re-run.
- **Drag-and-drop CAN be driven on the iOS simulator.** This was recorded as impossible for a long
  time and the record was wrong; every "drag is verified by inference" caveat in this repo's history
  predates the recipe below. `UIDragInteraction`'s lift recognizer needs the touch **stationary for
  ~350ms before any movement** — measured, `itemsForBeginning` fires 326–349ms after `touchesBegan`.
  A `swipe`, or a `touch_path` that starts moving immediately, never lifts. 300ms also fails: the
  first move lands just before the threshold and breaks the recognizer's slop. Use:

  ```
  touch_path points:
    {x: srcX, y: srcY, dt_ms: 0}       // down
    {x: srcX, y: srcY, dt_ms: 600}     // stationary dwell — this is the lift
    ...steps of 10–30pt, dt_ms: 50...  // travel
    {x: dstX, y: dstY, dt_ms: 400}     // settle on the target
  ```

  `dt_ms` on point *N* is the dwell **before** moving to *N*. Coordinates are **points** (the
  `launch` reply states the device's, e.g. 420×912), **not screenshot pixels** — mixing them up is
  what produced the "tab bar swallows taps" folklore: a touch beginning within 4pt of an edge is
  synthesised as the OS home/app-switcher gesture, and an *incomplete* one leaves the app's window
  ~35pt short, so every bottom-anchored control moves up and taps aimed from an old screenshot miss.
  Nothing is swallowed. Only a relaunch clears it, so keep every point ≥8pt from all four edges.
  Proven end-to-end against real Cadence: a Calendar Board card dragged between day columns, with
  the resulting SwiftData change surviving a relaunch.
- **macOS UI *can* be screenshot- and event-verified from the agent shell.** Also long recorded as
  blocked on an ungranted accessibility permission, also wrong: `AXIsProcessTrusted`,
  `CGPreflightPostEventAccess`, `CGPreflightListenEventAccess` and `CGPreflightScreenCaptureAccess`
  all return true, System Events reads window geometry, and `screencapture -x` works. The symptom
  behind the old note is real but misdiagnosed — `count of windows` on an app with no open window
  returns 0 and indexing it errors `-1719 Invalid index`, which reads like a permission denial.
  **One genuine constraint remains:** posting `CGEvent`s drives the user's *physical* cursor, so a
  scripted macOS drag fights them for the pointer and can drop something somewhere unintended. Safe
  only when the machine is known idle; screenshots and reads are safe any time.
- **Verify and commit with nothing live in the tree.** When agents share a working tree, what you
  commit must be the bytes you tested — and the two ways of losing that are independent:
  - *The file list.* `git add <paths>` adds your paths **to whatever is already staged**, so another
    agent's `git mv` or `git rm` sitting in the index rides along. `c9d2d78` swept in a staged
    deletion of two view files whose callers were not yet committed, so **HEAD did not build for
    iOS** until the next commit — and no check caught it, because isolating with `git archive HEAD`
    reproduces HEAD's *tree*, not its index, so the deleted files were present everywhere you
    looked. `git commit --only <paths>` takes the paths and ignores the index, and fixes this half.
  - *The file contents.* `--only` does **not** fix the other half, and this guide claimed it did.
    `5aa11dc` used `--only` and still left HEAD unbuildable for three commits: the subset was
    verified and passed, a live agent then edited two of those files, and `--only` faithfully
    committed bytes that had never been compiled. A passing verification is a statement about a
    moment, not about a path list.

  So: get the tree quiet before you verify — other agents' in-flight files reverted, their new files
  out of the way — and commit immediately after, with `--only` naming your paths. If you cannot
  quiet the tree, checksum the exact files you tested (`shasum` them into your scratchpad) and
  confirm the digests are unchanged at commit time; re-verify if any moved. Also read
  `git status --porcelain` for staged entries you did not stage. Two failure modes here were mine
  rather than the tooling's, and both are cheap to repeat: classifying files by a filename pattern
  (`*Tag*`) that neither affected file matched, and treating a subset test as durable while agents
  were still writing.
- **iPhone and iPad are one style, not two.** They differ in *layout* — a tab bar against a
  sidebar, one pane against two — and should not differ in how a row, a chip, a header or a
  picker looks or behaves. So: a change asked for on one is a change to both unless it is
  genuinely shape-specific, and the default implementation is one view parameterised by size
  class rather than an `iPhoneFoo` beside an `iPadFoo`. When a request names only one of them,
  say which of the two it is and act accordingly rather than silently doing half.

- All persisted dates are `yyyy-MM-dd` strings unless an existing model says otherwise.
- Use `DateFormatters` and `TimeFormatters`; do not create ad hoc `DateFormatter()` instances in views.
- SwiftData/CloudKit to-many relationships must be optional arrays (`[Type]?`). Read optional relationships with `?? []`, and append by assigning a new array.
- macOS is the primary, most fully-featured app surface; iOS is large and actively developed but not guaranteed to be at full feature parity.
- Keep SwiftUI view roots thin. Prefer dedicated subview structs and support files over long computed `some View` fragments.
- Preserve shared hover behavior. Do not turn task/event/bundle hover states gray; preserve original color and use brightness/lift style treatments from shared hover helpers.
- Avoid broad refactors in markdown editor files unless you are intentionally working on editor behavior.
- **Review the MCP boundary when model or shared-service code changes** — build
  `CadenceMCPServer` on its own scheme into a private `-derivedDataPath`, grep the log, and change
  response DTOs on purpose or not at all. This line used to read "do not touch MCP server/plugin
  code unless the task explicitly asks for MCP work", which was wrong: that target compiles a
  hand-picked subset of app source under different concurrency settings, so about half the commits
  touching it are app-side model changes that had to reach in, and skipping it yields a broken
  target or a silently stale response schema. Full account in `CadenceMCPServer/AGENTS.md`; do not
  restate it elsewhere.
- Do not revert unrelated user changes.

## Risk Hotspots

Use extra caution in these areas:

- `Cadence/macOS/Editor/` - the AppKit/SwiftUI bridge: custom caret, drawing, slash commands, undo.
  **Read `Cadence/macOS/Editor/AGENTS.md` first** — it carries the per-file roles, the concurrency
  rules and the draw-order findings, and it is kept current. In short, T-105 split the 1,996-line
  `MarkdownEditorInteractionSupport.swift` into six: it now holds only the `CadenceTextView`
  subclass (843 lines), beside `MarkdownEditorLayoutManager` (`CadenceLayoutManager` and the six
  colour-and-geometry decoration passes), `MarkdownEditorTextViewDecorations` (the two passes that
  need view state), `MarkdownEditorDecorationGeometry` (the rect math — pure, and unit tested),
  `MarkdownEditorCoordinator` (the `NSTextViewDelegate`) and `MarkdownEditorTextEditDiff`.
  `MarkdownEditorSupport.swift` still holds styling, parsing and list rules.
  **The Swift 6 blocker here is gone.** `CadenceLayoutManager` is `nonisolated` throughout,
  `drawBackground(forGlyphRange:at:)` included; `Theme` and `MarkdownStylist`'s palette constants
  are `nonisolated` too, because a nonisolated `static let` cannot initialise from a main-actor one.
  A whole-module Swift 6 probe on the macOS app scheme went from exactly 1 error — that method — to
  **0**. Keep it that way, and do not "fix" a future isolation error here with
  `nonisolated(unsafe)`, `@preconcurrency import AppKit`, or by moving the view's hit-rect and hover
  caches into a nonisolated holder: that last one compiles, changes no z-order, and removes the
  diagnostic without removing the hazard. It is documented as rejected in the scoped guide.
  **`SWIFT_VERSION = 5.0` is now an open question rather than a constraint.** Nothing in `Editor/`
  blocks the flip; what remains is 10 Swift-6-mode *warnings* elsewhere in the app, unchanged by
  T-105 and none of them in editor files. Clearing those is the work a flip now needs.
- `Cadence/macOS/Views/Timeline*`, `SchedulePanel*`, `CalendarPage*`, `CalendarBoard*` - timeline coordinate math, drag/drop, EventKit, and schedule state.
- `Cadence/macOS/Views/TasksPanel*`, `TasksListView.swift`, `ListDetail*`, `Inbox*`, `Kanban*` - shared task surface behavior, grouping, sorting, drag reorder, completion animations. `TasksListView` is the single All Tasks + Inbox list; `AllTasksListView.swift` and `InboxView.swift` were merged into it and are gone.
- `Cadence/macOS/Services/CalendarManager.swift`, `SchedulingService.swift`, `TaskWorkflowService.swift`, deletion helpers - can affect SwiftData relationships and EventKit side effects.
- `Cadence/Models/` and `Cadence/Services/CadenceSchema.swift` - schema changes require migration and CloudKit awareness.

## Refactor Guidance

Good refactor targets are files that combine orchestration, state, row rendering, popovers, and domain operations. Split by responsibility:

- root view: state and orchestration
- support view file: reusable UI sections and rows
- state/support file: derived state, sorting, grouping, coordinate math
- service: persistence mutations, deletion flows, EventKit interactions, migrations

After structural refactors, run `git diff --check` and the macOS build command above.

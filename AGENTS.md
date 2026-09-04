# Cadence Agent Guide

This file is the first stop for coding agents. Keep it compact: `CLAUDE.md` is the Claude Code
startup router, and `docs/AGENTS_REFERENCE.md` preserves the former long root guide.

## Project Snapshot

Cadence is a native SwiftUI productivity app: a fully built macOS surface and a large real
iOS/iPadOS one, shared SwiftData models, CloudKit sync, EventKit, widgets and MCP support.

Primary target:

- Project: `Cadence.xcodeproj`
- Scheme: `Cadence`
- Platform: macOS

Build from repo root with private DerivedData:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ build
```

Tests must be scoped to `CadenceTests`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ -only-testing:CadenceTests
```

Scope unit runs to `CadenceTests` to keep them fast and deterministic — **not** because the UI target
cannot run. `CadenceUITests` **does** run on macOS since the one-time automation grant on 2026-08-31
(4 tests, 2 skipped behind `CADENCE_RUN_INTERACTIVE_UI_TESTS=1`). It launches a real `Cadence.app`, so
it MUST hold the test-host lock: run `scripts/xcb.sh <id> test -only-testing:CadenceUITests`, never a
bare `xcodebuild`. Warning baseline is zero; any new warning is a regression.

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models.
- `Cadence/Services/` - shared services, migrations, notifications, markdown logic, AI, MCP.
- `Cadence/Shared/` - theme tokens, shared components, date/time utilities, presentation helpers.
- `Cadence/macOS/` - primary desktop app surface.
- `Cadence/macOS/Views/`, `.../Services/` - feature screens; focus, calendar, hotkey, deletion, scheduling.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor bridge. High risk.
- `Cadence/iOS/` - large iOS/iPadOS surface, not a stub; parity with macOS is not guaranteed.
- `CadenceWidgets/` - widget extension; the `Cadence` scheme already builds it.
- `CadenceMCPServer/`, `plugins/cadence-mcp/` - separate MCP boundary.
- `CadenceTests/` - unit tests. Look for an existing file before adding one.
- `docs/` - shipped docs plus detailed agent references.

## Scoped Guides

Read the nearest scoped `AGENTS.md` before editing under that tree:

- `Cadence/AGENTS.md`
- `Cadence/Models/AGENTS.md`
- `Cadence/Services/AGENTS.md`
- `Cadence/Shared/AGENTS.md`
- `Cadence/iOS/AGENTS.md`
- `Cadence/macOS/AGENTS.md`
- `Cadence/macOS/Services/AGENTS.md`
- `Cadence/macOS/Editor/AGENTS.md`
- `Cadence/macOS/Views/AGENTS.md`
- `CadenceMCPServer/AGENTS.md`
- `plugins/cadence-mcp/AGENTS.md`

Long references, searchable only when needed:

- `docs/CONTEXT_INDEX.md` - small routing map by change type.
- `docs/AUDIT_BRIEF.md` - what an external audit report needs to be cheap to act on.
- `docs/{AGENTS,SHARED_AGENTS,IOS_AGENTS}_REFERENCE.md` - the detailed root, Shared and iOS guides,
  plus red-run history; `docs/CLAUDE_REFERENCE.md` - detailed product/feature history.

## Non-Negotiable Patterns

- No hardcoded colours. Use `Theme.*` or user-owned `colorHex`; no bare `.white`, `.black`, `.gray`,
  or `Color(hex:)` literals outside `Theme.swift`.
- Persisted dates are `yyyy-MM-dd` strings unless an existing model says otherwise.
- Use `DateFormatters` and `TimeFormatters`; do not create ad hoc `DateFormatter()` instances in views.
- SwiftData/CloudKit to-many relationships must be optional arrays (`[Type]?`). Read with `?? []`;
  append by assigning a new array.
- Page headers do not describe the page the user is already on. Search rows, empty states, and
  picker rows may keep subtitles.
- Use one hover/selection layer at one radius.
- Prefer one shared component over near-copies.
- iPhone and iPad share one style; they differ by layout, not by row/chip/header vocabulary.
- Do not revert unrelated user or agent changes.
- **Commit with `scripts/agent-commit.sh <id> -m <msg> <path>...`, not `git commit`** (T-679). The
  index is shared: it refuses a foreign staged path, commits a private one, then repairs the shared one.
  `HEAD-MOVED` (T-974) means a sibling landed while you were validating — nothing was committed,
  re-read `git show HEAD:<path>` and run it again. Before a batch closes,
  `scripts/agent-commit.sh check` must exit 0 (T-781).

### The `try? save()` rule

`try? modelContext.save()` is allowed **only** when the save commits nothing but in-place field
edits to objects the store already holds, and nothing after it tells the user it worked. A site
breaks the rule if any of three halves is true:

1. **Existence** — the function inserts or deletes, **in its own frame or one below**: a pending
   change travels up through every frame *handed* a `ModelContext` and stops at the first that was not.
2. **Report** — something **anywhere in the swallowed commit's own block** says it worked: `dismiss…()`,
   `is/show<X> = false`, `editing/selected/pending<X> = nil`, `presentedX = …`, `onSave(…)`, an
   `@AppStorage` write, **the answer itself** (`return true` from a `-> Bool`, a non-`nil` return from
   a `-> X?`), or **a rearrangement the user can see** (T-614): a row that stays where you dropped it
   outclaims a dismissed sheet, and a refused reorder reverts at next launch with nothing to retry — no
   text scan sees it, so pin per site; all seven do, via `CadenceOrderCommit` (T-868/T-869/T-870).
   A "swallowed commit" is `try?` on a `save()` **or** a `Cadence*Persistence` helper — the commit
   surface, not the method name — **one frame down included**.
3. **Commit reach** — the function inserts **or deletes** and reaches no commit at all. A declaration
   **handed** a `ModelContext` is exempt by rule; one that reached for an ambient context must commit.

All three are fixed the same way: commit through `CadencePendingChangePersistence` (`commitInsert` /
`commitDelete` / `commitEdit(in:undo:)`), `throws`, take `commit:`, and name the failure on screen.

Why it matters: one `ModelContext` app-wide, so a swallowed failure leaves the change *pending*, for
the next unrelated `save()` to take or `rollback()` to discard. Enforced by `CadenceSaveCommitDisciplineTests`.

## Build And Run Safety

- Build through **`scripts/xcb.sh <id> build|test`**, or pass a private `-derivedDataPath` yourself:
  it supplies one, refuses the shared path, takes `scripts/test-host-lock.sh` for `test`, names a
  silent T-117 stall, and **fails a run that executed 0 tests** (T-552 — a wrong suite name exits 0).
- The lock lives at **`${TMPDIR}/cadence-macos-test-host.lock`**, not `/private/tmp` — which reports
  the host free while a run is live. Ask `test-host-lock.sh status`; it prints the holder and queue.
- **It is FIFO (T-650), so release-and-re-acquire goes to the back.** For one lease across many
  runs, take it once and use `xcb.sh <id> raw test`, which skips the lock.
- **A dead owner pid does not mean a stale lock.** A `nohup`'d `xcodebuild` outlives the shell that
  took the lease, so the pid is routinely gone mid-run. It reclaims only on an expired lease **and**
  zero live test hosts; forcing it starts a second host on one app-group container (T-236).
- If `xcodebuild` sits at `Command line invocation` with 0% CPU, suspect a project-file lock before
  debugging Swift.
- Never create simulator devices. Use one existing stock simulator and `scripts/simulator-claim.sh`.
- Launch the macOS app only through `scripts/run-macos-app.sh start <Cadence.app> <id>`, and pair it
  with `stop <id>` in the same turn.
- Use one scratch directory per agent and clean only inside it.
- Isolate with `git archive HEAD | tar -x -C <dir>`: 910 files in 0.2s and already exactly HEAD, so
  no dirty-path restore step. `rsync` copies 8963 files / 464 MB and another agent's in-flight edits.
- Long build/test runs should launch and poll in one shell invocation.
- Confirm the build log names the tree you intended to test.

## Red-Run Triage

Before treating a red run as a code regression, check:

- Macro/plugin/load errors only, `build.db is locked`, or `unable to spawn swift-frontend`: concurrent
  builds. Re-run.
- Thousands of zero-second test failures and multiple `My Mac - Cadence (...)` host PIDs: concurrent
  macOS test hosts. Re-run under `scripts/test-host-lock.sh`.
    Keep `parallelizable = "NO"`; it also changes the log format, so serial-format failure greps
    silently match nothing. Measurements and reasoning: `docs/AGENTS_REFERENCE.md`.
- A few zero-second failures and one host PID: inspect the `.xcresult`; the test runner may have
  exited early.
- UI-test failures in an ordinary test run: the run was not scoped to `CadenceTests`.
- **`CadenceUITests` was never flaky — it cannot pass while the Mac's screen is locked (T-563).**
  `loginwindow` holds the foreground, so `app.launch()` fails ~60s in with *"Failed to activate
  application … (current state: Running Background)"*, on whichever line called it. Measured either
  side of one lock event: 40 launches before, zero failures; 100% after. `xcb.sh` refuses such a run
  and the tests skip themselves, so a red UI run **is** evidence again. Still re-run under the lock.
- Compile failures that name your file are real until proven otherwise.
- **Count test hosts with `pgrep -f '^/Applications/.*/xcodebuild test'`.** A loose
  `pgrep -f xcodebuild` matches any script whose own command text contains the word — including the
  poller asking. That hid a stranded lock for 29 minutes on 2026-08-29.
- **A warning count from a run that did not recompile the file is vacuous.** An incremental
  `xcodebuild test` reuses object files, so `grep -c warning:` returns 0 whether or not your change
  introduced warnings. Only trust a warning count from a run that actually rebuilt the file you
  edited — check the log for its `SwiftCompile`/`CompileSwift` line before quoting the number.
- **Count compile errors with `grep -cE '\.swift:[0-9]+:[0-9]+: error:'`, not `grep -c 'error:'`.**
  The loose pattern over-counts and discards good evidence quietly — why, in `docs/AGENTS_REFERENCE.md`.
- `sleep` is blocked in a **foreground** tool call (a poll loop there exits 0 having watched nothing);
  it works in a detached job or `Monitor` script, so `acquire` waits from a background runner.

## Risk Hotspots

- `Cadence/Models/` and `Cadence/Services/CadenceSchema.swift` - schema changes need migration and
  CloudKit awareness.
- `Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift` and `MarkdownEditorSupport.swift` -
  AppKit/SwiftUI bridge, custom caret/drawing/slash commands/undo.
- `Cadence/macOS/Views/Timeline*`, `SchedulePanel*`, `CalendarPage*` - timeline math, drag/drop,
  EventKit, schedule state.
- `Cadence/macOS/Views/TasksPanel*`, `ListDetail*`, `Inbox*`, `Kanban*` - task surfaces, sorting,
  grouping, drag reorder.
- `Cadence/macOS/Services/CalendarManager.swift`, `SchedulingService.swift`,
  `TaskWorkflowService.swift`, deletion helpers - mutations and EventKit side effects.
- Model or shared-service changes must review the MCP boundary; build `CadenceMCPServer` separately
  when relevant.

## Refactor Guidance

Keep SwiftUI roots thin: root view for state/orchestration, support views for rows/sections,
support/state files for derived state and geometry, services for persistence and side effects. Keep
edits scoped and run the relevant build/test command after structural changes.

## Subagent verification runbook

Coordinators: point subagents at `docs/SUBAGENT_RUNBOOK.md` rather than restating its rules.

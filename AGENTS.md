# Cadence Agent Guide

This file is the first stop for coding agents. Keep it compact: `CLAUDE.md` is the Claude Code
startup router, and `docs/AGENTS_REFERENCE.md` preserves the former long root guide.

## Project Snapshot

Cadence is a native SwiftUI productivity app with a fully built macOS surface, shared SwiftData
models, CloudKit sync, EventKit calendar/reminder integration, widgets, MCP support, and a large
real iOS/iPadOS surface.

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

Unscoped tests pull in `CadenceUITests`. It launches now (automation granted 2026-08-31) but flakes
on activation unless run via `scripts/xcb.sh`, which takes the test-host lock. Baseline: zero warnings.

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models.
- `Cadence/Services/` - shared services, migrations, notifications, markdown logic, AI, MCP.
- `Cadence/Shared/` - theme tokens, shared components, date/time utilities, presentation helpers.
- `Cadence/macOS/` - primary desktop app surface.
- `Cadence/macOS/Views/` - macOS feature screens and support views.
- `Cadence/macOS/Services/` - macOS-only managers for focus, calendar, hotkeys, deletion, scheduling.
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
- `docs/AUDIT_BRIEF.md` - what an external audit report needs to be cheap to act on. Hand it to
  anyone producing findings; the report that used it cost two greps to verify instead of a search.
- `docs/AGENTS_REFERENCE.md` - detailed root runbook and red-run history.
- `docs/SHARED_AGENTS_REFERENCE.md` - detailed Shared guide.
- `docs/IOS_AGENTS_REFERENCE.md` - detailed iOS guide.
- `docs/CLAUDE_REFERENCE.md` - detailed product/feature history.

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

### The `try? save()` rule

`try? modelContext.save()` is allowed **only** when the save commits nothing but in-place field
edits to objects the store already holds, and nothing after it tells the user it worked. A site
breaks the rule if any of three halves is true:

1. **Existence** — the function also calls `modelContext.insert(…)` or `modelContext.delete(…)`.
2. **Report** — something in the swallowed commit's own block, after it, dismisses or reports success:
   `dismiss()`, `is<Something> = false`, `presentedThing = …`, `onSave(…)`. A "swallowed commit" is
   `try?` on a `save()` **or** a `Cadence*Persistence` helper — the commit surface, not the method name.
3. **Commit reach** — the function inserts and reaches **no commit at all**. Halves 1 and 2 key on
   the *presence* of a swallowed save, so one that never commits passed both. A declaration **handed**
   a `ModelContext` is exempt by rule; one that reached for an ambient context must commit.

All three are fixed the same way: commit through `CadencePendingChangePersistence`
(`commitInsert` / `commitDelete` / `commitEdit(in:undo:)`), `throws`, take `commit:`, and let the
caller name the failure where the user is already looking.

Why it matters: one `ModelContext` app-wide, so a swallowed failure does not mean "it did not
happen" — the change stays *pending*, committed by the next unrelated `save()` from any screen or
discarded by the next `rollback()`. Enforced by `CadenceSaveCommitDisciplineTests`.

## Build And Run Safety

- Build through **`scripts/xcb.sh <id> build|test`**, or pass a private `-derivedDataPath` yourself:
  it supplies one, refuses the shared path, takes `scripts/test-host-lock.sh` for `test`, names a
  silent T-117 stall, and **fails a run that executed 0 tests** (T-552 — a wrong suite name exits 0).
- The lock lives at **`${TMPDIR}/cadence-macos-test-host.lock`**, not `/private/tmp`. `$TMPDIR`
  resolves under `/var/folders/...` here, so checking `/private/tmp` reports the host free while a
  run is live. Ask the script (`test-host-lock.sh status`); do not stat a path you guessed.
- **A dead owner pid does not mean a stale lock.** A `nohup`'d `xcodebuild` outlives the shell that
  acquired the lease, so the recorded pid is routinely gone while the run continues. The script
  reclaims only on an expired lease **and** zero live test hosts — that conjunction is deliberate.
  Never force the lock because the owner looks dead; that starts a second host against the same
  app-group container, which is the T-236 corruption the lock exists to prevent.
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
    **The 2026-08-28 reason here is stale**: it spawned 2 hosts then; on Xcode 26.6 it spawns **one**
    and parallelises in-process (re-measured 2026-08-31, twice). `parallelizable = "NO"` stays anyway —
    parallel still fails one test deterministically (a store assertion across a 60ms suspension in a
    `@MainActor` suite) and buys only 1.27x wall clock for ~9x the CPU. Do not re-enable per-invocation.
  It also changes the log format from `✘ Test name()` to `Test case 'Suite/name()' failed`, so
  failure greps written for the serial format silently match nothing.
- A few zero-second failures and one host PID: inspect the `.xcresult`; the test runner may have
  exited early.
- UI-test failures in an ordinary test run: the run was not scoped to `CadenceTests`.
- Compile failures that name your file are real until proven otherwise.
- **Count test hosts with `pgrep -f '^/Applications/.*/xcodebuild test'`.** A loose
  `pgrep -f xcodebuild` matches any script whose own command text contains the word — including the
  poller asking. That hid a stranded lock for 29 minutes on 2026-08-29.
- **A warning count from a run that did not recompile the file is vacuous.** An incremental
  `xcodebuild test` reuses object files, so `grep -c warning:` returns 0 whether or not your change
  introduced warnings. Only trust a warning count from a run that actually rebuilt the file you
  edited — check the log for its `SwiftCompile`/`CompileSwift` line before quoting the number.
- **Count compile errors with `grep -cE '\.swift:[0-9]+:[0-9]+: error:'`, not `grep -c 'error:'`.**
  A failing test whose message contains the word "error" — e.g. `Caught error: .notFound(...)` from
  a source scan — matches the loose pattern, so a genuine mutation kill reads as a build break and
  gets thrown away. The loose pattern only ever over-counts, so it never launders a bad result into
  a good one; it discards good evidence, which is quieter and easier to miss.
- `sleep` is blocked in a **foreground** tool call — a poll loop there burns every iteration instantly
  and exits 0 having watched nothing, reading like "the condition never fired". It **works** in a
  detached job and in a `Monitor` script (measured 2026-08-30), so `acquire` waits from a background runner.

Full incident details are in `docs/AGENTS_REFERENCE.md`.

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

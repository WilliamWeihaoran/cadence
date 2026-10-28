# Cadence Agent Guide

This file is the directory map and the non-negotiable patterns. **The rules you work under — build, test, mutation, lease, commit gate, safety, reporting — are in [docs/AGENT_BRIEF.md](docs/AGENT_BRIEF.md); read that first.** `CLAUDE.md` is the Claude Code startup router, `docs/SESSION_HANDOFF.md` is today's state, and `docs/AGENTS_REFERENCE.md` preserves the former long root guide. Keep this file compact: it is startup context, and every line here is paid for on every run.

## Project Snapshot

Cadence is a native SwiftUI productivity app: a fully built macOS surface and a large real
iOS/iPadOS one, shared SwiftData models, CloudKit sync, EventKit, widgets and MCP support.

Primary target: `Cadence.xcodeproj`, scheme `Cadence`, platform macOS.

**You invoke builds through `scripts/xcb.sh <id> build|test`, never by hand.** The two commands below are what it runs; they are here so the two load-bearing flags are readable, not as an invitation to type them. A build runs from the **repo root** with private DerivedData — agent shells reset their working directory between calls, so a relative `-project ../Cadence.xcodeproj` will not resolve, and the private path must appear in the log before a green run means anything:

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

Unit tests RUN here, re-measured 2026-10-06 (T-2049) — never read a harness failure as "tests can't run on this Mac". `CadenceUITests` runs too, but the macOS automation grant is per-SESSION, not a one-time switch: with `/var/db/com.apple.dt.automationmode/automation-enabled` absent, a cold UI run raises an owner-only Touch ID prompt and, unattended, dies ~70s later having executed 0 tests on *"Timed out while enabling automation mode"*. Ask `./scripts/xcb.sh check-automation`. **Never write the authorization database to get round the prompt** (T-1742, T-2049).
Zero **compiler** warnings, **enforced not asserted** (T-1147/T-1149): `xcb.sh` **exits 9** when a run that recompiled Swift has any and `.github/scripts/check-log.sh` fails CI the same way; tool notices count separately, a vacuous run never gates, and `CADENCE_ALLOW_WARNINGS=1` downgrades it to a report for `mutate.sh` alone. **Both counters are destination-AGNOSTIC and a macOS build is not** (T-1781): it compiles no `#if os(iOS)`, so its `0` says nothing about the iOS surface — the same tree with one injected iOS-only warning gave **2** on `generic/platform=iOS Simulator` (measured 2026-09-30). **A compile-task count is an ARCH count, not a floor** (T-1703): `generic/platform=iOS Simulator` builds arm64 **and** x86_64 while a concrete `platform=iOS Simulator,id=<udid>` and `platform=macOS` each build one, so generic is exactly **2x** the other two over a byte-identical file list. **~695 on a concrete iOS destination is NON-vacuous and must not be read as a failed build**, and no count distinguishes a macOS build from an iOS one — read the destination line, never the number. Both dated pairs: `docs/AGENTS_REFERENCE.md`, "The iOS compile-task count is an ARCH count, not a floor". CI's `ios-build` gates its own log the same way on every push, so an iOS-only warning reaches you AFTER the push; build iOS yourself when you touch `Shared/`, `Models/` or `Services/`. Pinned by `CadenceBuildInvocationHygieneTests.everyCompilingCIJobRoutesItsOwnLogThroughTheSameWarningGate`.
The `TestAction` pins **`TZ=UTC`** (T-1116): zones via `CadenceTestTimeZones`, never a shell `TZ=`.

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
- `docs/` - shipped docs plus detailed agent references. **Codex holds a write lease on some paths; before you edit one, ask `./scripts/codex-land.sh lease`, which parses the authoritative `lease` block, rather than opening `docs/CODEX_WORKTREE.md` — that file is two orders of magnitude larger than the block inside it. Read the doc itself only for a grant's reasoning or an instruction attached to a path.**
- `docs/TODO.md` is the ledger and is **large — never read or `rg` it whole.** Ask `./scripts/ledger-view.sh head T-NNNN` for an entry's first line and state, `show T-NNNN` for the whole entry once you need the history, and `brief` for the open list.

## Scoped Guides

Read the nearest scoped `AGENTS.md` before editing under that tree. Each says what is true of its
own subtree and routes up to here for the rest.

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

- `docs/AGENT_BRIEF.md` - the rules every agent works under; point briefs at it, never retype them.
- `docs/CONTEXT_INDEX.md` - routing map by change type; `docs/AUDIT_BRIEF.md` - the audit-report shape.
- `docs/{AGENTS,SHARED_AGENTS,IOS_AGENTS,MODELS_AGENTS,SERVICES_AGENTS,MCP_AGENTS}_REFERENCE.md` - the
  detailed root/Shared/iOS/Models/Services/MCP guides and red-run history; `docs/CLAUDE_REFERENCE.md`.

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
- **macOS and iOS are one app on two platforms** (owner ruling, [[T-8201]]). A surface may differ
  between them ONLY where the difference is forced by hardware or input: screen width, pointer vs
  touch, hover, right-click, keyboard shortcuts, or a presentation model one platform does not have.
  Anything that is only UI -- a card's anatomy, how a completed task reads, what an editor's sections
  look like, whether an animation plays -- is the SAME on both. Where the two have drifted, the fix is
  one shared component, not a second copy nudged closer by hand. A platform difference must be
  justifiable in one sentence naming the hardware or input constraint it answers; if it cannot be, it
  is drift and it gets unified.
- **v1 ships English-only** (T-1386). There is no `.strings`, `.xcstrings` or `.lproj` resource and
  `knownRegions` is `en`/`Base`; user-facing copy stays an English literal. T-18 is deferred scope,
  not an oversight. Pinned by `CadenceTests/CadenceAgentOperatingRuleTests`.
- Do not revert unrelated user or agent changes.
- **Commit with `scripts/agent-commit.sh`, never `git commit`** (T-679). Flags and refusals: `docs/AGENT_BRIEF.md`. What is local here is that the index is shared, so `HEAD-MOVED` (T-974) means a sibling landed while you were validating and nothing was committed; re-read `git show HEAD:<path>` and rerun. `agent-commit.sh check` must exit 0 before a batch closes (T-781).
- **Write your `docs/TODO.md` line AT COMMIT TIME, rebuilt on `git show HEAD:docs/TODO.md`** (T-679, T-1783). Not merely sequencing: that file is staged whole-file, so a sibling committing it will **silently revert prose you wrote early** — `git status` clean, your text simply gone, and *nothing in the declined-hunk ledger*. Measured 2026-09-30. There is no signal; only rewriting immediately before the commit is safe.
- **`.githooks/pre-commit` is not yours to arm** (T-780). Never run `git config core.hooksPath`, or
  teach a script to. Why, and why an armed hook still lets `agent-commit.sh` through:
  `docs/AGENTS_REFERENCE.md`, "Why the pre-commit hook ships inert".
- **A claim about what the test host can do must name the test that holds it** (T-1153) —
  `CadenceTestHostSandboxCapabilityTests`, or `CadenceGuardScriptSelftestTests` for a script in it.
  `CadenceTestHostEnvironmentPinTests` enforces that and pins T-1116's other half: the `TestAction`
  reaches `TZ` and `AppleLocale` and **cannot** reach a Language & Region switch, so a date/week/
  clock test that moves on one Mac is the machine.

### The `try? save()` rule

`try? modelContext.save()` is allowed **only** when the save commits nothing but in-place field
edits to objects the store already holds, and nothing after it tells the user it worked. A site
breaks the rule if any of four halves is true: **existence** (it inserts or deletes, in its own
frame or one below), **report** (something in the swallowed commit's own block says it worked — a
dismiss, a flag, a `@Binding` write, the answer itself, a visible rearrangement), **commit reach**
(it changes existence and reaches no commit at all), or **the callee's undo** (T-1299 — `try?` over
a helper that changes existence and reaches a raw `save()`). In `extension ModelContext` the
receiver is `self` and is left off (T-1301). All four are fixed the same way: commit through
`CadencePendingChangePersistence` (`commitInsert` / `commitDelete` / `commitEdit(in:undo:)`),
`throws`, take `commit:`, and name the failure on screen. There is one `ModelContext` app-wide, so
a swallowed failure leaves the change *pending* for someone else's `save()` or `rollback()`.
Enforced by `CadenceSaveCommitDisciplineTests`; each half argued in full, with T-614/T-664/T-996/
T-997, in `docs/AGENTS_REFERENCE.md`, "The `try? save()` rule".

## Build And Run Safety

The refusals themselves — never a bare `xcodebuild`, `-only-testing:` takes a SUITE, read the real `XCODEBUILD_EXIT=` line, which simulators you may touch, how to launch the app — are in `docs/AGENT_BRIEF.md`. What is local to this repository's runner:

- `scripts/xcb.sh` supplies a private `-derivedDataPath`, refuses the shared path, takes `scripts/test-host-lock.sh` for `test`, names a silent T-117 stall, and **fails a run that executed 0 tests** (T-552 — a wrong suite name exits 0).
- The lock lives at **`${TMPDIR}/cadence-macos-test-host.lock`**, not `/private/tmp` — which reports
  the host free while a run is live. Ask `test-host-lock.sh status`; it prints the holder and queue.
- **It is FIFO (T-650), so release-and-re-acquire goes to the back.** For one lease across many
  runs, take it once and use `xcb.sh <id> raw test`, which skips the lock.
- **A dead owner pid does not mean a stale lock.** A `nohup`'d `xcodebuild` outlives the shell that
  took the lease, so the pid is routinely gone mid-run. It reclaims only on an expired lease **and**
  zero live test hosts; forcing it starts a second host on one app-group container (T-236). **Never
  drive the lock from inside a test** (T-1152): there `pgrep` runs but is denied the process list, so
  it refuses and `status` prints `unknown` (`CadenceTestHostSandboxCapabilityTests` holds that).
- `xcodebuild` idle at `Command line invocation` with 0% CPU is a project-file lock, not Swift.
- Pair `scripts/run-macos-app.sh start <Cadence.app> <id>` with `stop <id>` in the same turn.
- **Mint and release scratch through `scripts/agent-scratch.sh`** (T-1094), never `rsync` and never `rm -rf`; the measurement behind that is `docs/SUBAGENT_RUNBOOK.md` §2.

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
- **`CadenceUITests` was never flaky — it cannot pass while the Mac's screen is locked (T-563),** and `xcb.sh` refuses such a run, so a red UI run **is** evidence. Measurements: `docs/AGENTS_REFERENCE.md`.
- Compile failures that name your file are real until proven otherwise. **A warning or red in a file you did not touch may be a sibling mid-mutation of the shared tree** (T-3071, T-3092): `git diff --stat` that file and re-run; mutations belong in a scratch tree or worktree, never the shared checkout (`docs/SUBAGENT_RUNBOOK.md` §4).
- **Count hosts with `pgrep -f '^/Applications/.*/xcodebuild( .*)? test(-without-building)?( |$)'`** — anchored, so
  the poller is not counted, and action-as-a-token, because `xcb.sh` puts the action **last** (T-1162, calibrated).
- **A quiet run is not a dead run. Ask `./scripts/xcb.sh run-state <id>` before you start a second one (T-2071).**
- **A count from a run that did not recompile is vacuous** — an incremental run reuses object files and
  returns 0 either way. `xcb.sh` prints `swift compile tasks: N`, says `!! VACUOUS-COUNT` at 0 (T-1147), and never gates on one.
- **Count errors and warnings `grep -cE '\.swift:[0-9]+:[0-9]+: (error|warning):'`**, never loosely: the loose form over-counts. Why, and the T-1147 measurement, in `docs/AGENTS_REFERENCE.md`.
- **Warnings need a SECOND anchored pattern, `grep -cE 'macro expansion [^ :]+:[0-9]+:[0-9]+: warning:'` (T-1516)** — a warning raised inside a macro expansion has **no `.swift:N:C:` prefix**, so the first pattern scores 0 on it. `xcb.sh` and `check-log.sh` gate on the sum and say `MACRO-EXPANSION-WARNING`; grepping a log by hand means grepping for both.
- `sleep` is blocked in a **foreground** tool call (a poll loop there exits 0 having watched nothing);
  it works in a detached job or `Monitor` script, so `acquire` waits from a background runner.

## Risk Hotspots

The four high-risk macOS families — `Timeline*`/`SchedulePanel*`/`CalendarPage*`, `TasksPanel*`/`ListDetail*`/`Inbox*`/`Kanban*`, `CalendarManager`/`SchedulingService`/`TaskWorkflowService` and the deletion helpers, and the AppKit editor bridge — are enumerated once in `Cadence/macOS/AGENTS.md`, "High-Risk Areas", beside the files. Two that are not macOS's to state:

- `Cadence/Models/` and `Cadence/Services/CadenceSchema.swift` - schema changes need migration and
  CloudKit awareness.
- Model or shared-service changes must review the MCP boundary; build `CadenceMCPServer` separately
  when relevant.

## Subagent verification runbook

Coordinators: point subagents at `docs/SUBAGENT_RUNBOOK.md` rather than restating its rules. Since T-1333 it is the mandatory rules alone and is budgeted like a guide; its incident narratives are in `docs/SUBAGENT_RUNBOOK_REFERENCE.md`, read on demand.

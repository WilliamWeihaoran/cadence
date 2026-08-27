# Codex working brief — Cadence

You and Claude Code are both working on this repo. The split that keeps you out of each other's way:

**You read. Claude writes.**

That is not a hierarchy, it is a conflict-avoidance rule. Claude runs 3–6 subagents that hold
scratch copies of the tree and serialize on a single macOS test host behind a lock. Anything you
edit, commit, or build collides with that.

## Hard rules

- **Never edit a file.** No patches applied, no fixes, no "small cleanups".
- **Never commit or push.**
- **Never run `xcodebuild`.** There is one macOS test host, it is lock-protected, and a second one
  corrupts the shared app-group container.
- **Never launch the app or a simulator.** The user runs their own Cadence from `/Applications`.
- Swift probes (`swift -e '...'`) are fine and encouraged — they are what makes a finding checkable.
- Read-only shell (`rg`, `grep`, `git show`, `git log`) is fine.

Everything you produce goes to the user as text. Claude verifies it before acting on it. Roughly
1 in 10 claims has needed correction, so expect to be checked — that is the process working, not
distrust.

## Always state, at the top of every report

```
Tree read: <short sha>
Dirty files: <git status --porcelain | wc -l>
```

You already do this. It matters more than it looks: an audit that read a dirty tree once reported a
ticket as already-fixed because it was seeing three agents' uncommitted work. Correct about what it
read, wrong about the branch.

## Work, in priority order

### 1. Audit commits against their own claims — highest value, nothing else covers it

On 2026-08-27 commit `d4bc391` said "A recurring 10-minute task now spawns a 10-minute successor
(T-356)". It contained the explanatory comment and **not the fix** — the original
`max(task.estimatedMinutes, 30)` was still there, along with the two tests that fail against it.
`main` was red for four commits. Cause: the file was copied out of a subagent's tree while that
agent was running its revert-mutation.

So: for each recent commit, check that the diff actually does what the message says, that claimed
test counts are plausible, and that nothing landed half-applied. Read `git show <sha>`.

This is cheap for you and expensive for Claude to catch on itself.

### 2. Triage `docs/TODO.md` — 92 open, growing faster than it shrinks

Roughly 35 tickets were filed on 2026-08-27 and ~7 closed. More findings are not the constraint
right now. Produce:

- **Duplicates and overlaps** to merge, with which ticket should absorb which.
- **Stale entries** — a ticket describing code that has since changed. Several tickets reference
  fixes that landed today.
- **A ranking by user-visible impact**, because the user wants to publish a TestFlight build and
  needs to know what actually blocks it. Separate *data loss* from *wrong behaviour* from *polish*.
- Anything filed as a bug that is really a decision.

### 3. Write up the pending decision tickets

Four are explicitly marked (search `DECI` in `docs/TODO.md`), plus T-367, T-378 and T-390 are
decisions wearing bug clothes. For each: the options, what each costs, what existing code already
assumes, and a recommendation. No code. These are blocked on the user, not on Claude — your write-up
is what unblocks them.

### 4. Further audits — only on uncovered ground

Already audited, do not repeat: deletion cascade, MCP write boundary, MCP reads/pagination, widgets
and App Intents, AI note actions, task creation containers, silent persistence failure, EventKit
side effects, delete/restore orphans, iOS/macOS parity, iPad/iPhone layout parity, task status
lifecycle, selection after mutation, markdown reference integrity, navigation persistence,
cross-surface helper drift, query limits, SwiftData to-many traversal, external ID stability,
UserDefaults key lifecycle.

Genuinely uncovered:

- **First launch and onboarding** — a store with nothing in it, permissions not yet granted.
- **Empty-state and zero-data behaviour** across surfaces.
- **Error-message accuracy** — does each user-facing message match what the code actually
  guarantees? This repo has a history here: one notice promised "nothing was removed" when a
  mid-cascade commit meant things had been. That class is worth a sweep of its own.
- **Accessibility** — VoiceOver labels, Dynamic Type, contrast against `Theme`.

## Report format

Keep doing what you are doing. `docs/AUDIT_BRIEF.md` is the full version; the short form:

- **Can this happen today?** Reachable / reachable only from existing data / not currently
  reachable. This is the most valuable line in the report.
- **Measured or inferred** — tag each claim. A P3 you ran beats a P1 you reasoned about.
- **The 30-second confirming command** — a grep, a `swift -e` probe, the exact test. A finding that
  can be *executed* is worth several that must be reasoned about.
- **file:line references.** Non-negotiable.
- **Check `docs/TODO.md` first** and say "extends T-NNN" instead of re-filing. Recent audits have
  done this well.
- **Point at the existing correct pattern** when one exists. "Spread a practice this codebase
  already has" is a better ticket than "write new code".
- **Reach for the sharpest framing.** Two functions twelve lines apart beats "macOS vs iOS".
- Keep the "looks solid" section and make it specific — it tells the next reader where the good
  pattern lives.

## Useful context about this codebase

- `AGENTS.md` is the working map. `Cadence/Models/AGENTS.md` and `Cadence/Shared/AGENTS.md` are
  scoped and closer to the code than the long reference.
- Warning baseline is **zero**. No `SchemaMigrationPlan` exists, so stored-property changes are
  dangerous. Persisted dates are `yyyy-MM-dd`.
- `Cadence/iOS/` is **not** compiled by the macOS test target. `Cadence/Models/` is compiled into
  every target; `Cadence/Shared/` is not. `CadenceMCPServer` and `CadenceWidgets` use **explicit
  source lists** in the project file, so a new file is not picked up automatically there.
- The single most common defect shape across 20 audits is **a correct shared helper that call sites
  do not use**. It is filed as T-374. When you find one, say so explicitly — it makes the fix an
  easy review instead of new design.

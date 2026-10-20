# Session Handoff

Written 2026-10-20 at `88fd2e80`. **This file is point-in-time state and nothing else.** Every
general rule it used to restate — build and test, the Codex lease, the commit gates, the safety
constraints, how the owner wants work reported — now lives once in
[docs/AGENT_BRIEF.md](AGENT_BRIEF.md), which is the first thing to read. Then this, then
[AGENTS.md](../AGENTS.md) for the directory map and the UI patterns. Do not bulk-read the repo.

If a rule and this file disagree, the brief wins; this one is a snapshot and snapshots rot.

---

## 1. What Cadence is, and where it lives

**Cadence** is a native SwiftUI + SwiftData productivity app: macOS primary, large iOS/iPadOS
surface, CloudKit `.private("iCloud.com.haoranwei.Cadence")`, widgets, EventKit, and an MCP server
boundary. Build 23 shipped. The owner does not write code — work is done by agents and verified
against the tree, never against an agent's report.

**The repo lives at `~/Developer/Cadence`.** It moved off `~/Desktop/Projects/Cadence` on
2026-10-19 (see `T-3245`) because Desktop is iCloud-synced, which produced conflict copies compiled
as real sources and `ETIMEDOUT` filesystem reads. If you see the old path anywhere outside
`docs/audits/` and `docs/TODO.md`, it is stale and worth fixing; those two are historical record and
are deliberately left alone.

## 2. Current state

- `main` at `88fd2e80`, **8 unpushed**. Count your own rather than trusting this line:
  `git rev-list --count origin/main..main`.
- **Many worktrees and many local-only branches.** `git worktree list` and
  `git for-each-ref refs/heads` give today's numbers; a count written here is wrong within the hour.
  What does not change: **most branches here have no counterpart on `origin`** — 64 of 71 at this
  writing, every `codex/*` and `post23/*` among them — so a destroyed one is gone permanently.
  Check with `git show-ref --verify refs/remotes/origin/<branch>` before you assume otherwise.
  Never reset, delete, rebase in place or force-push one, and **never delete a worktree** — each is
  a live session holding uncommitted work.
- `codex/unified-editors` still shows ahead of main even though T-3238 landed — its work was
  brought over without mutating the branch. That is intentional, not an oversight.
- **Work is scheduled by a single `cadence-keeper` routine.** The multi-agent batch runner it
  replaced is retired; there is no batch script in `scripts/` and nothing in the session scratchpad
  is a live runner any more. Entries filed "by the keeper" (for example `T-3256`) come from it.

### Open work

Read the live list with `./scripts/ledger-view.sh brief`; this table is what it said at
`88fd2e80`, and the lead token on an entry's own first line is the only authority.

| Ticket | State | What it is |
|---|---|---|
| `T-3244` | PARTIAL | `CadenceTests` now compiles and runs for iOS. The remaining half is the suites gated off the iOS leg. |
| `T-3256` | OPEN | One iOS full-run failure of `CadenceCommentSymbolClaimTests` that passed on rerun. See §3. |
| `T-3250` | OPEN | Doc residue the plans sweep could not fix from inside its own slice. |
| `T-3247` | PARTIAL | `run-macos-app.sh` can build, seed, capture a Debug window and quit only its own pid. |
| `T-3237` | PARKED | Four capture-card complaints from the owner. The open question is where tags go. |
| `T-3166` | PARTIAL | A covered calendar block drops its calendar-name row instead of clipping it. |
| `T-1364` | PARTIAL | Rows and inspector chips converted; calendar and settings next, blocked by the Codex lease. |
| `T-3214`, `T-3152` | PARKED | Awaiting owner steps. |

**Landed overnight, and no longer open:** `T-3241` (tree walks stop at a nested checkout),
`T-3240` (iPad Today draft), `T-3236` (macOS screenshot backlog). A brief that still lists one of
these is older than the tree.

`T-3242` (sweeps timing out under load) has **no formal entry on main** — it lives on
`claude/fervent-curran-f33a34`, unmerged, so `[[T-3242]]` links on main resolve to nothing until
that branch lands.

---

## 3. Known reds that are NOT yours

- **`T-3256`, and it is the live one.** `CadenceCommentSymbolClaimTests` failed once in a full
  `CadenceTests` run on the `Cadence-iPhone15` iOS destination and passed on rerun, scoped, on the
  same simulator. The failing run also logged `Restarting after unexpected exit, crash, or test
  timeout` and a 600 s simulator diagnostics timeout with four `xcb.sh` runs queued on the lock, so
  it reads as a host kill under contention rather than an assertion. If you see it, re-run scoped
  before filing anything; if it fails scoped on a quiet host, that is new and worth a ticket.
- **Nested worktrees no longer redden the tree-walking suites.** `T-3241` closed that
  (`CadenceSourceScan.isNestedCheckout`), and the four walks it fixed —
  `AgentContextBudgetTests`, `CadenceMisfiledSurfaceTests`, `CadenceMCPWriteFenceTests`,
  `CadenceBuildInvocationHygieneTests` — now prune `.claude/worktrees/`. **A red in one of these is
  therefore evidence again.** Do not dismiss it as the old worktree symptom, and do not "fix" it by
  editing `AGENTS.md`.
- The stale `CalendarPageView.swift.orig` earlier handoffs told you to leave alone is **gone**.
  Nothing untracked is owed an exemption today; anything in `git status` before you started is
  still somebody else's.

---

## 4. The two things that bite hardest in a shared checkout

Both are stated in full in [docs/AGENT_BRIEF.md](AGENT_BRIEF.md); they are repeated as *names*
here only because every incident this week was one of them.

- **A grant is sub-file scoped** (the Codex lease), and the fenced block says what *Codex* may
  write — admitting a local agent is prose beside it. Ask `./scripts/codex-land.sh lease`.
- **`agent-commit.sh` stages whole files.** If it refuses because a sibling staged a path, wait or
  use the `<path>=<content-file>` form. Never reset a sibling's work, and never `--commits-stale`.

Several sessions write this checkout at once, so re-read state rather than trusting a reading from
earlier in your own turn — including a sibling's report about another agent's dirty file, which is
a snapshot and not a current fact.

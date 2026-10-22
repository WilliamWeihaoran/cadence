# Session Handoff

Written 2026-10-22 at `9d1b0817`. **This file is point-in-time state and nothing else.** Every
general rule it used to restate — build and test, the Codex lease, the commit gates, the safety
constraints, how the owner wants work reported — now lives once in
[docs/AGENT_BRIEF.md](AGENT_BRIEF.md), which is the first thing to read. Then this, then
[AGENTS.md](../AGENTS.md) for the directory map and the UI patterns. Do not bulk-read the repo.

If a rule and this file disagree, the brief wins; this one is a snapshot and snapshots rot.

---

## 1. What Cadence is, and where it lives

**Cadence** is a native SwiftUI + SwiftData productivity app: macOS primary, large iOS/iPadOS
surface, CloudKit `.private("iCloud.com.haoranwei.Cadence")`, widgets, EventKit, and an MCP server
boundary. Build 24 shipped 2026-10-21 on macOS and iOS (`961971ec` bumped
`CURRENT_PROJECT_VERSION` to 24). **The next RC is due in 4-5 days and is judged by fewer visible
defects**, so prefer on-screen fixes over ledger or tooling work. The owner does not write code — work is done by agents and verified
against the tree, never against an agent's report.

**The repo lives at `~/Developer/Cadence`.** It moved off `~/Desktop/Projects/Cadence` on
2026-10-19 (see `T-3245`) because Desktop is iCloud-synced, which produced conflict copies compiled
as real sources and `ETIMEDOUT` filesystem reads. If you see the old path anywhere outside
`docs/audits/` and `docs/TODO.md`, it is stale and worth fixing; those two are historical record and
are deliberately left alone.

## 2. Current state

- `main` at `9d1b0817`, **0 unpushed** at this writing. Count your own rather than trusting this
  line: `git rev-list --count origin/main..main`.
- **Many worktrees and many local-only branches.** `git worktree list` and
  `git for-each-ref refs/heads` give today's numbers; a count written here is wrong within the hour.
  What does not change: **most branches here have no counterpart on `origin`** — 101 of 110 at this
  writing, every `codex/*` and `post23/*` among them — so a destroyed one is gone permanently.
  Check with `git show-ref --verify refs/remotes/origin/<branch>` before you assume otherwise.
  Never reset, delete, rebase in place or force-push one, and **never delete a worktree** — each is
  a live session holding uncommitted work.
- `codex/unified-editors` still shows ahead of main even though T-3238 landed — its work was
  brought over without mutating the branch. That is intentional, not an oversight.
- **Work is scheduled by a single `cadence-keeper` routine.** It reserves an id range per agent
  before handing it out (per `T-3320`; see the `T-33xx` keeper entries), so take ids only from a
  range you were given.

### Open work

Read the live list with `./scripts/ledger-view.sh brief` (112 active entries at `9d1b0817`); the
lead token on an entry's own first line is the only authority. For the RC, the entries that name a
**visible** defect or an unseen fix are the ones to start from:

| Ticket | State | What it is |
|---|---|---|
| `T-3259` | OPEN | No way to show the owner a macOS frame while his Cadence runs; several PARTIALs wait on it. |
| `T-3325` | OPEN | `T-3310`'s iPad Month deep-link fix unseen: two SpringBoard alerts block `Cadence-iPadPro11`. |
| `T-3207` | OPEN | Timeline hold/handle drag still not seen on screen, and needs the owner's yes. |
| `T-3311`, `T-3295`, `T-3232` | OPEN | Look questions for the owner: iPad month chip titles, plate luminance, glyph red. |
| `T-3252`, `T-3253`, `T-3160` | PARTIAL | Shippable per their SHIP-NOTEs; what remains is an on-screen look. |
| `T-3244` | PARTIAL | iOS `CadenceTests` failing population is zero; the last step needs `project.pbxproj`. |
| `T-3152` | PARTIAL | Widget iCloud entitlement landed; the readiness pin is the remainder. |

**Closed since the last handoff** (a brief that still lists one is older than the tree): `T-3256`,
`T-3250`, `T-3247`, `T-3237`, `T-3166`, `T-1364`, `T-3214`.

`T-3242` (sweeps timing out under load) now **has its formal entry on main**, OPEN, awaiting an
owner decision on which half to change.

---

## 3. Known reds that are NOT yours

- **`T-3256` is CLOSED** (2026-10-21) as a host kill under lock contention. For the record:
  `CadenceCommentSymbolClaimTests` failed once in a full
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
- An untracked `Cadence/macOS/Views/CalendarPageView.swift.orig` is **back** in the checkout as of
  2026-10-22 (the 10-20 handoff called it gone). It is not yours; leave it. Anything in
  `git status` before you started is still somebody else's.

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

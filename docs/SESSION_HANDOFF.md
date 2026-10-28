# Session Handoff

Written 2026-10-27 at `c258c14f`. **This file is point-in-time state and nothing else.** Every
general rule — build and test, the Codex lease, the commit gates, safety, how the owner wants work
reported — lives once in [docs/AGENT_BRIEF.md](AGENT_BRIEF.md), which is the first thing to read.
Then this, then [AGENTS.md](../AGENTS.md) for the directory map and the UI patterns.

If a rule and this file disagree, the brief wins; this one is a snapshot and snapshots rot.

---

## 1. What Cadence is, and where it lives

**Cadence** is a native SwiftUI + SwiftData productivity app: macOS primary, large iOS/iPadOS
surface, CloudKit `.private("iCloud.com.haoranwei.Cadence")`, widgets, EventKit, and an MCP server
boundary. The owner does not write code — work is done by agents and verified against the tree,
never against an agent's report.

**Build 25 shipped 2026-10-27 to internal TestFlight, macOS and iOS.** The RC is an internal
TestFlight build, not an App Store submission. `a749c0c2` (2026-10-26) bumped
`CURRENT_PROJECT_VERSION` 24 -> 25 on the app and widget targets; the test bundles still read 24
and the MCP server 1, and none of those ships. **The next upload needs a build number above 25.**
The upload itself is the owner's (Xcode Organizer); nothing in the tree records it, so the
shipped date is the owner's word, not a commit.

**Zero ledger entries are RC-blocking** (`a49454de` gave every active entry an RC-TRIAGE verdict;
`ledger-view.sh untriaged` lists the handful filed since). **POST-RC is now the live queue.** A
defect the owner reports from the TestFlight build outranks anything an agent would pick itself:
T-7550 (a finger could not scroll the iOS Today timeline) is the example, reported from build 25
and CLOSED the same day, seen on screen.

The repo lives at `~/Developer/Cadence` (moved off the iCloud-synced Desktop in T-3245). The old
path outside `docs/audits/` and `docs/TODO.md` is stale — and the shared checkout's own
`core.hooksPath` still points at it (T-4900).

## 2. Current state

- `main` at `c258c14f`, 0 unpushed at this writing; count your own with
  `git rev-list --count origin/main..main`. CI on `main` was green through `202cb725`.
- Worktrees and local branches are many (`git worktree list`, `git for-each-ref refs/heads`). At
  this writing all but one local branch has a remote-tracking counterpart — the exception is
  `claude/t6821-ios-ci`, a live agent's — but check with
  `git show-ref --verify refs/remotes/origin/<branch>` rather than trusting this line.
- `git status` at this writing shows seven dirty `Cadence/` Swift files, four dirty
  `CadenceTests/` files and the `CadenceWidgets` scheme. The iOS ones match T-2087's call sites
  (the dead overflow-caption plumbing, assigned in T-7640). They are not yours; leave them.
- Work is scheduled by the `cadence-keeper` routine, which reserves an id range per agent (latest:
  T-7640, T-7660). Take ids only from a range you were given.

### Open work

`./scripts/ledger-view.sh brief` is the live list (97 active entries at `c258c14f`); an entry's own
lead token is the only authority. Grouped by who can move it:

**Owner calls — wording, look or scope.** None is a defect; each waits on a yes/no.

| Ticket | What it is |
|---|---|
| `T-7290`, `T-7291` | AI draft sheet: should Return create; Mac and iOS AI sheets use different words. |
| `T-7210`, `T-7209`(b) | AI disclosure row wording; Delete Account copy under-lists what goes. |
| `T-7085`, `T-6984`, `T-7074` | Kanban "Column" vs "Section"; iOS Search "More" vs "Pages"; split Calendar setting. |
| `T-7257`, `T-7259`, `T-7260` | Links tab header; links not editable or reorderable; list order is Mac-only. |
| `T-7203`, `T-7182`(a) | Mac View-menu grouping and Cmd+O; the bundle-retirement slot hazard. |
| `T-1840`, `T-3226`, `T-1424`, `T-16` | Delete-account scope; restore-string measurement; ASC privacy answers; logo artwork. |

**On-screen checks that need an ATTENDED simulator session.** Scheduled runs cannot drive the
simulator, so these landed from source and wait for someone who can.

| Ticket | What it is |
|---|---|
| `T-7613` | iPad: swipe on a lifted block's edge band scrolls, hold-then-drag still resizes; re-check T-7550/T-7551. |
| `T-7163`, `T-7125`, `T-7195`, `T-7285`, `T-7315`, `T-7421` | Widget layout fixes, small and large tiles, not seen on a home screen. |
| `T-7151`, `T-6700`, `T-6711`, `T-1463` | iPad Templates two-column pane; root-shell top reserve; two iPad sightings. |
| `T-3325` | iPad Month deep link unseen: two SpringBoard alerts were blocking `Cadence-iPadPro11`. |
| `T-3259` (+ `T-3160`, `T-3167`, `T-3253`) | No way to show a macOS frame while the owner's Cadence runs; those wait on it. |

**Agent-actionable.**

| Ticket | What it is |
|---|---|
| `T-7641` | Extend the bare comment-claim sweep to `CadenceTests/` and `CadenceUITests/` (343 spans). |
| `T-2087` | Dead iOS overflow-caption plumbing — in flight (`deadplumb2238`). |
| `T-6821` (+ `T-6541`) | CI runs no iOS simulator test under Xcode 26.0.1 — in flight (`iosci2338`). |
| `T-7170` | `xcb.sh export-archive` never run with `release-testing`/ad-hoc. |
| `T-6410` | `docs/apple-release-readiness.md:15` still says iOS is "built, not distributed". |
| `T-4900`, `T-3264`, `T-3260` | Stale `core.hooksPath`; no full-target landing step; 337 view-body pins. |

The rest of the active list is SHIP-NOTE PARTIALs whose remainder is parked past the RC, or
long-lived owner questions; `ledger-view.sh head` says which.

**Closed since the last handoff** (a brief that still lists one is older than the tree): `T-3311`,
`T-3295`, `T-3232`, `T-3244`, `T-3242`, `T-7550`, `T-7551`, `T-7601`.

---

## 3. Known reds that are NOT yours

- None open at this writing: CI on `main` is green and no flake is ticketed as live.
- **A red in a tree-walking suite is evidence**, not the old nested-worktree symptom:
  `CadenceSourceScan.isForeignTree` (`CadenceTests/CadenceSourceScanSupport.swift`; T-3241, renamed
  and widened to scratch trees in T-3333) prunes any nested checkout. Do not "fix" one by editing
  `AGENTS.md`.
- Anything in `git status` before you started is somebody else's (see section 2).

---

## 4. The two things that bite hardest in a shared checkout

Both are stated in full in [docs/AGENT_BRIEF.md](AGENT_BRIEF.md); they are named here only because
most incidents are one of them.

- **A grant is sub-file scoped** (the Codex lease). Ask `./scripts/codex-land.sh held <path>`.
- **`agent-commit.sh` stages whole files.** If it refuses because a sibling staged a path, wait or
  use the `<path>=<content-file>` form. Never reset a sibling's work, and never `--commits-stale`.

Several sessions write this checkout at once, so re-read state rather than trusting a reading from
earlier in your own turn.

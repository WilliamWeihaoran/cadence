# Session Handoff

Written 2026-10-27 at `c258c14f`; section 2 rewritten 2026-10-29 at `e5a1da4b`. **This file is
point-in-time state and nothing else.** Every general rule — build and test, the Codex lease, the
commit gates, safety, how the owner wants work reported — lives once in
[docs/AGENT_BRIEF.md](AGENT_BRIEF.md), which is the first thing to read. Then this, then
[AGENTS.md](../AGENTS.md) for the directory map and the UI patterns.

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
`ledger-view.sh untriaged` lists those filed since). **POST-RC is now the live queue.** A
defect the owner reports from the TestFlight build outranks anything an agent would pick itself:
T-7550 (a finger could not scroll the iOS Today timeline) is the example, reported from build 25
and CLOSED the same day, seen on screen.

The repo lives at `~/Developer/Cadence` (moved off the iCloud-synced Desktop in T-3245). The old
path outside `docs/audits/` and `docs/TODO.md` is stale — and the shared checkout's own
`core.hooksPath` still points at it (T-4900).

## 2. Current state

- `main` and CI: `git fetch -q && git rev-list --count origin/main..main` for your unpushed count;
  `gh run list --branch main --workflow CI -L 5` for CI (a docs-only commit gets no CI run).
- Worktrees and local branches are many (`git worktree list`, `git for-each-ref refs/heads`). Before
  trusting a branch, check it has a remote counterpart: `git show-ref --verify refs/remotes/origin/<b>`.
- **Anything dirty in `git status` is a sibling's**, as are `scratchpad/<agent>/` dirs at the
  repo root; leave them. Work is scheduled by the `cadence-keeper` routine, which reserves an id
  range per agent; take ids only from a range you were given. The open reservations, and which
  agent holds each (match a dirty path to it with `head` on the tickets it names):

  ```sh
  git show HEAD:docs/TODO.md | sed -nE 's/^- \[(T-[0-9]+)\] \*\*OPEN[^)]*\) -- (ids T-[0-9.T-]+ reserved( for agent `[^`]+`)?).*/\1 \2/p'
  ```
- `T-8201` is a standing owner ruling: macOS and iOS are one app; a difference must name the
  hardware or input that forces it. Read it before any platform-specific change.

### Open work

`./scripts/ledger-view.sh brief` is the live list (139 active entries at `e5a1da4b`); an entry's
own lead token is the only authority, read with `head T-NNNN`. Grouped by who can move it:

**Owner calls — wording, look, scope or behaviour.** Each waits on the owner's yes/no, not on code.

| Ticket | What it is |
|---|---|
| `T-8044` | Should a timed task's Month chip show its start time and sort before untimed, both platforms? |
| `T-8243`, `T-8107`, `T-8104` | iOS chips lack due tint/marker; row menu hides dates; New Task date-chip glyphs. |
| `T-8101`, `T-8012`, `T-7985` | Mac list-picker checkmark; Focus "Best matches / 18"; Inbox Group: By List. |
| `T-7981`, `T-7941`, `T-7943` | Rollover banner traps tasks; iCloud card developer copy; iPad Lists double empty state. |
| `T-8162`, `T-8163`, `T-8164` | Event-notes merge: read-only re-append; Apple edits never win; embedded-task flag. |
| `T-7874`, `T-7931`, `T-8103`(b) | iOS Save forms drop drafts on kill; half-typed `#tag` sync window; scrim tap dismiss. |
| `T-7290`, `T-7291` | AI draft sheet: should Return create; Mac and iOS AI sheets use different words. |
| `T-7210`, `T-7209`(b) | AI disclosure row wording; Delete Account copy under-lists what goes. |
| `T-7085`, `T-6984`, `T-7074` | Kanban "Column" vs "Section"; iOS Search "More" vs "Pages"; split Calendar setting. |
| `T-7257`, `T-7259`, `T-7260` | Links tab header; links not editable or reorderable; list order is Mac-only. |
| `T-7203`, `T-7182`(a) | Mac View-menu grouping and Cmd+O; the bundle-retirement slot hazard. |
| `T-1840`, `T-3226`, `T-1424`, `T-16` | Delete-account scope; restore-string measurement; ASC privacy answers; logo artwork. |
| `T-7751`, `T-7681` | Agent Mac disk 95%+ full (owner frees space); App Review screenshot device choice. |

**On-screen checks that need an ATTENDED session.** Scheduled runs cannot drive the simulator,
and no run can show a macOS frame while the owner's Cadence runs (`T-3259`), so these landed from
source and wait for someone who can.

| Ticket | What it is |
|---|---|
| `T-7613` | iPad: swipe on a lifted block's edge band scrolls, hold-then-drag still resizes. |
| `T-8242`, `T-7872`, `T-7881`, `T-7951` | iOS: done-task look; background flush; commit ceiling; iCloud button wrap. |
| `T-7921`, `T-8204` | Half-typed `#tag` not minted (iOS and Mac); time the shortened completion animation. |
| `T-7163`, `T-7125`, `T-7195`, `T-7285`, `T-7315`, `T-7421` | Widget layout fixes, small and large tiles, not seen on a home screen. |
| `T-7151`, `T-6700`, `T-6711`, `T-1463` | iPad Templates two-column pane; root-shell top reserve; two iPad sightings. |
| `T-3325` | iPad Month deep link unseen: two SpringBoard alerts were blocking `Cadence-iPadPro11`. |
| `T-8211`, `T-8121`, `T-8081`, `T-8071` | Mac, blocked on `T-3259`: New Task panel; picker fixes; card menu; Kanban moves. |
| `T-8051`, `T-8031`, `T-8001`, `T-7991` | Mac, blocked on `T-3259`: note links; Focus chip; Today all-day band; Tasks pills. |
| `T-7911`, `T-7861`, `T-7831` | Mac, blocked on `T-3259`: sidebar list reorder; quit-time title and editor flush. |
| `T-3259` (+ `T-3160`, `T-3167`, `T-3253`) | No way to show a macOS frame while the owner's Cadence runs; those wait on it. |

**Agent-actionable.** "In flight" means a reservation names a live agent; check it before taking one.

| Ticket | What it is |
|---|---|
| `T-8182`, `T-8183`, `T-8187` | iPad board: long-press menu; list-kanban drag; stale comment — in flight (`T-8270`). |
| `T-8142`, `T-8143` | iOS timeline drop feedback; unreachable Calendar-page drop — in flight (`T-8300`). |
| `T-8203` | Port the completion animation to iOS; held until `iOSTaskViews.swift` is free. |
| `T-8184`, `T-8185`, `T-8186` | iOS list-kanban has no add affordance; slot token not a picker; re-measure clearance. |
| `T-8188`, `T-7710` | `simulator-claim.sh` cannot reclaim under an attached panel; three uncovered census shapes. |
| `T-8200`, `T-8180`, `T-8160` | Id reservations still OPEN: close each naming every id USED or RELEASED UNUSED. |
| `T-7170` | `xcb.sh export-archive` never run with `release-testing`/ad-hoc. |
| `T-4900`, `T-3260` | Stale `core.hooksPath` (owner-run config); 337 view-body pins. |

The rest of the active list is SHIP-NOTE PARTIALs whose remainder is parked past the RC, or
long-lived owner questions; `ledger-view.sh head` says which.

**Closed since the last handoff** (a brief that still lists one is older than the tree): `T-7641`,
`T-2087`, `T-6821`, `T-6541`, `T-6410`, `T-3264`.

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

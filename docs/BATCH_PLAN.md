# Overnight batch plan — 2026-10-18

Supersedes the 2026-10-17 plan. **Tracked in git on purpose**: the first copy lived in
`scratchpad/` and an agent deleted it during cleanup.

## Why this one has a mechanism and the last one did not

The 2026-10-17 plan listed five batches and only batch 1 ran. The coordinator is turn-based —
it acts when invoked and stops — and nothing drove batch advancement except being poked. Nine
hours of capacity went unused because a batch-1 agent was never launched after its dependency
cleared.

**A recurring scheduled task now advances this queue.** It fires regardless of whether the owner
is present, re-reads this file, and starts the next batch whose dependencies are met. If the
scheduled task is cancelled, this plan stops — that is the single point of failure and it is
named here deliberately.

## Standing rules

- 3 agents per batch, 2–3 tickets each, grouped by file locality so siblings cannot collide.
- Commit each agent's work as soon as it is green; never hold a batch for its slowest member.
- **The usage ceiling is suspended until 2026-10-18 14:06** by the owner. After that the 80/90
  rule applies again automatically.
- The session limit has fired **three times** in this run, killing agents mid-flight each time.
  Nothing was lost because work was backed up and resumed — keep doing both.
- **Local green is NOT the finish line.** This Mac runs Xcode 27, CI pins 26.0.1, and CI was red
  for 27 pushes while every local check reported green ([[T-3215]]). CI is the gate.

## Before any batch starts

Check these, because they move:
1. `git status` — a path dirty is a path someone is inside, lease or no lease.
2. `./scripts/agent-commit.sh check` must exit 0.
3. For any leased path: `git log --no-merges main..<branch> -- <path>`, then read the SHAPE of
   what comes back. `docs/CODEX_WORKTREE.md` carries six corrections to that check and the
   reason each failed.

## Batch A — the Block tail and the board

| agent | tickets | notes |
|---|---|---|
| `staleclaims` | the 6 fixable stale claims | Reword where the symbol is stale but the substance is live. Leave `TaskCreationService.swift`'s line — a live Codex agent holds it. |
| `blockchain` | T-3214 | The Block move chain reachable only from its own tests. Decide: goes with the `@Model`, or now. Retire the 5 test call sites in the same change if now. |
| `boardreconcile` | T-1478 | PARKED no longer — `CalendarPageBoardSupportViews.swift` was granted in `d1162e10`. Land PA-13's sibling. |

## Batch B — the information gaps

| agent | tickets |
|---|---|
| `macrowinfo` | T-1467 — macOS notes excerpt AND inline subtasks with checkboxes |
| `alldaycap` | T-1474 — cap `min(T, min(cap/2, 3))`, 6 iPhone / 8 iPad, macOS adopts the shared rule, multi-day fixture pins the span rule |
| `cascade47` | T-3193 — raise the cascade threshold to 47 minutes AND measure how often it then fires |

## Batch C — the broken guards

Three repo guards were found defective on 2026-10-17, each by an agent hitting it while doing
something else. All three are filed and none is fixed.

| agent | tickets |
|---|---|
| `claimguard` | T-3209 — the comment-claim detector. **Read the rewritten ticket**: the real hole is the existence guard at `:412`, not the `^[A-Z]` anchor, and the originally-prescribed fix does not work. |
| `mutateparam` | T-3212 — `mutate.sh` cannot baseline a parameterised test; `_ran()` needles `Test <name>()` with empty args |
| `menueffect` | T-3210 — the Mac context menu is pinned by parity, not by effect; no test invokes an action against a model |

## Batch D — the iOS halves, once their leases clear

| agent | tickets |
|---|---|
| `iosrowchrome` | T-3196 / T-3197 iOS halves — **needs `CadenceTests/CadenceCodexTaskRowTypographyTests.swift`**, request the grant first |
| `inlinepanel2` | T-1481 iOS half — the shared panel inline in the note |
| `capturland` | land `codex/capture-list-sections` once its calendar dependency clears |

## Batch E — the last two, and the build

| agent | tickets |
|---|---|
| `iosbackup` | T-1477 — iOS backup and staged restore. **Highest blast radius in the repo**: a staged restore overwrites a CloudKit-backed store on a device with no Finder fallback. Disposable stores only. |
| `widgetent` | T-3152 — widget iCloud entitlement; a signing-input change wanting its own diff and a two-device run |
| `build23` | bump `CURRENT_PROJECT_VERSION` 22 → 23 and archive — **ONLY if CI is green and the T-3215 crash is diagnosed** |

## Not in any batch

- **T-3168, the rail** — needs the owner's eyes. Three independent blocks have stopped a machine
  looking: the computing agent could not navigate, iOS had no fixture door (T-1483, landing now),
  and macOS window capture needs an Accessibility grant the coordinator may not make.
- **T-3125** — research the coordinator owes the owner on where name-merging fires.
- **T-3215's crash** — agent `cicrash` has it. It gates build 23 and nothing else should touch it.

## Run log

- 2026-10-18 (batch runner): launched **Batch A** — `staleclaims`, and `boardreconcile` carrying BOTH T-1478 and T-3214. `blockchain` not launched as a separate agent: T-3214 and T-1478 edit the same leased `CalendarPageBoardSupportViews.swift` and `CalendarBoardDayDropCommitTests.swift`, so two agents would collide; folded into `boardreconcile` (T-3214 first). Third slot left empty rather than pulling Batch B forward. Note for both: `CalendarBoardDayDropCommitTests.swift` and `CadenceTaskMutationSupport.swift` are leased with no explicit grant found — agents told to stop and park if needed. CI gate for Batch E not checked this run (E not reached).
- 2026-10-18 01:25 (batch runner): **launched nothing.** Batch A (`staleclaims`, `boardreconcile`) was launched by the previous run at ~01:22, three minutes earlier, and has no commits yet; with `cicrash` on T-3215 and an unknown worker inside the iOS calendar/markdown files (all dirty at 01:12, `iOSCalendarMonthViews.swift` staged) the live count is at or over 3. Batch B not pulled forward: `alldaycap` (T-1474) would land on those dirty iOS calendar files. CI gate (E): latest CI run on `f75a5d24` in progress, previous two failed — `build23` stays blocked.

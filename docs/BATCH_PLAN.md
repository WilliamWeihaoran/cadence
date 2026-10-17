# Batch plan — regenerated 2026-10-17

The first copy of this lived at `scratchpad/batch-plan.md` and was destroyed when agent `rowdue`
ran `rm -rf scratchpad` during cleanup, believing the shared directory was its own. It reported the
deletion itself, first and plainly. **This copy is tracked in git so the next cleanup sweep cannot
take it**, which is the actual lesson.

## Usage ceiling — SUSPENDED until 2026-10-18 14:06

The owner granted a 24-hour override at 2026-10-17 14:06: *"for the next 24 hours, you may ignore the 80/90%
token gate."* The standing rule in `feedback-usage-budget-ceiling` (wrap at 80%, pause at 90%) does
not gate work until then. **After 2026-10-18 14:06 it applies again automatically** — this is time-boxed, not
repealed, and nobody should have to remember that.

**What the override does and does not buy.** It stops the coordinator pausing EARLY. It does not
raise the hard session limit, and that limit is not a soft landing: on 2026-10-17 it fired about an
hour after the previous override and killed three agents mid-flight. Nothing was lost — all three
resumed with their context intact, and their uncommitted work was still in the shared tree — but
that was recoverable by luck of timing more than design. So while the override stands: keep the
restart backup current, prefer committing green work over holding it, and report the number when it
crosses rather than acting on it.

## Rules in force

- 3 agents per batch; 2–3 small tickets each, grouped by file locality so siblings cannot collide.
- Commit each agent's work as soon as it is green; do not hold a batch for its slowest member.
- The owner **overrode the usage ceiling** for this run: *"ignore the ceiling, start batch 1 when
  the agents finish."* It was at 78% when they said it, and the session limit was hit about an hour
  later, which cost three agents mid-flight. All three resumed with context intact and nothing was
  lost. Report the number when it crosses; do not pause on it.

## Status — what actually happened, not what was planned

Batches ran out of order while the coordinator was away. These landed:

| ticket | state | commit |
|---|---|---|
| T-1470 (PA-13) | **CLOSED**, 5/5 mutations killed, notice proven drawn by mutation | `749d67ad` |
| T-3170 eleventh pass (iOS Block surfaces) | PARTIAL, 1293 deletions | `042a5767` |
| T-3170 twelfth pass (macOS Block surfaces) | PARTIAL | `13d45076` |
| T-3196 / T-3197 | PARTIAL — macOS half only; iOS half lease-blocked | `c52f347c` |
| T-1481 | PARTIAL — Mac inline panel | `97514929` |
| T-3204 | CLOSED | `39eb8d55` |

## PARKED, and why — the lease is the single bottleneck

| ticket | blocked on | unblocked by |
|---|---|---|
| T-1476 / T-1473 | three leased search paths | **GRANTED** `63b024d6`; needs an agent restarted |
| T-3170 remainder | `iOSRootView.swift` + 10 leased Calendar/timeline paths | `iOSRootView.swift` **GRANTED** `67b41992`; the Calendar paths are not yet checked |
| T-1478 | `CalendarPageBoardSupportViews.swift` | **NOT a grant.** `codex/calendar-day-drop-commit` holds real unlanded work there (+23 −96). Blocked on LANDING that branch. |
| T-1475 | a leased `CadenceCodex*` census | parked on `heartbeat/t1475-ios-timeline-drag`; needs the census bumped |

## The check that matters before any further grant

**"Ahead of main" proves nothing** — 21 `codex/*` branches are ahead, because this repo lands a
branch by applying its files rather than merging, so a landed branch stays ahead for ever.
**`codex-land.sh review` proves nothing either** — it refuses on its first failing check, so an
inbox-id clash masks whether the content already landed.

Compare the branch's blob for the path against main's. Identical means landed and safe to grant;
differing means real unlanded work and a collision waiting to happen. `67b41992` records the table.

## Remaining queue

1. **Restart T-1476 / T-1473** — granted, and the owner has settled the open question: **persist the
   include-completed toggle on BOTH platforms** behind a new preference key. Note this changes
   shipped iOS behaviour, which today resets the flag every time the view is rebuilt — the ticket's
   claim that iOS "already remembers" it was the coordinator's error, corrected in `63b024d6`.
2. **Land `codex/calendar-day-drop-commit`**, which unblocks T-1478.
3. **T-3170's Calendar remainder** — run the blob check on the ten leased Calendar/timeline paths
   before asking for anything.
4. **T-1467** — macOS notes excerpt and inline subtasks. Unblocks the iOS half of T-3196.

## Not in any batch, deliberately

- **T-3168, the rail** — computed, mutation-proven, never seen. Needs the owner's eyes.
- **T-3125** — research the coordinator owes the owner on where name-merging fires.
- **T-3199 / T-3200** — UI-test AX tree and page routing. Worth doing only if the "never seen on
  screen" backlog is to be cleared by machine rather than by eye.
- **T-3152** — widget iCloud entitlement; a signing-input change wanting its own diff and a
  two-device run.

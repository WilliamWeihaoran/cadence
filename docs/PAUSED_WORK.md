# Paused work — 2026-08-28

Paused at the user's request. Nothing is lost: every agent tree is on disk and the repo's
working tree holds the staged-but-uncommitted batches. `main` is green at `859e270`.

## Repo state

- **`main` = `859e270`**, green (3106 tests, 274 suites, exit 0, 0 warnings).
- **The working tree is clean.** Everything unlanded lives in the agent trees below, not in the
  repo. An earlier attempt to stage the EventKit work aborted because a test run was live, so
  nothing was left half-applied.

## Agent trees on disk — complete, awaiting staging

| Tree | Tickets | State |
|---|---|---|
| `/private/tmp/cadence-status` | T-341, T-342, T-344, T-357 | Done. 8/8 mutations killed, 37/37 green. Residue filed as T-398 → **renumber to T-399** (collides with prefs). |
| `/private/tmp/cadence-prefs` | T-392, T-393, T-394, T-351 | Done. 7/7 mutations killed, 36/36 green. Keeps **T-398**. |
| `/private/tmp/cadence-eventkit` | T-389, T-390 | Done, 5/5 mutations killed, 32/32 green. **Not staged** — take its 8 source/test files, not `docs/TODO.md`. Stale-link residue still to file as **T-400**. |
| `/private/tmp/cadence-search` | T-377, T-378 | All six mutations killed; was in final verification. Owns **T-395**, **T-396**. |
| `/private/tmp/cadence-subtask` | T-387, T-338 | Green + failing-first + M1–M4 collected. M5/M6 supplementary, not run. |
| `/private/tmp/cadence-caps` | T-363, T-385, T-386 | Green at 80 tests; mutations not run. |
| `/private/tmp/cadence-visible` | T-343, T-349, T-397 | Code complete, both builds clean. Pipeline had not completed. |
| `/private/tmp/cadence-commit` | T-321, T-366 | Code complete, both builds clean. Verification not run. |
| `/private/tmp/cadence-order` | T-333, T-372a, T-373 | Queued on the lock; verification not run. |
| `/private/tmp/cadence-widget` | T-354, T-369, T-355 | Mid-implementation. Least complete. |

## Ticket ID allocation (uncommitted, so not visible in docs/TODO.md yet)

- **395, 396** — search agent
- **397** — status/delete-visibility agent (`iOSTaskDetailSheet` residue)
- **398** — prefs agent
- **399** — status-lifecycle agent's kanban cancelled-card residue (renumber from its 398)
- **400** — EventKit stale-link detection residue (not yet written)

Next free: **401**.

## Hazards to remember when resuming

- **Agent trees are snapshots and HEAD has moved.** Copying a tree wholesale reverts landed work —
  this happened four times today. Take only each agent's own files, or ask for a patch.
- **Two agents allocated the same ticket id twice.** With many agents filing against one
  `docs/TODO.md`, assign id ranges up front.
- **Not yet written down** (deferred because the context-budget test pins that file's length):
  a non-vacuity anchor must be a file where the needle can actually appear. A type calls its own
  members *unqualified*, so anchoring a qualified needle inside the declaring type reads zero for a
  reason that is not absence. Belongs in `Cadence/Shared/AGENTS.md`.

# Commit-to-Ticket Ledger Audit

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## CL-1: Six Modern IDs Have Commit History but No Formal Ledger Entry

**P3 / process integrity / measured history and document inventory. Reachable today in the committed documentation; not an app bug. Extends R33 and the known T-462 archival gap, with only the modern residual population proposed for repair.**

All **901 commits reachable from 4799e3c**, including reachable merge history, were searched for exact-spelled `T-<digits>` mentions in both subject and body. Formal entries are lines matching `^\s*- \[T-<digits>\]` in TODO.md or TODO_DONE.md. A mention elsewhere in prose does not count as a formal entry.

| Measurement | Result |
| --- | ---: |
| Unique IDs appearing in commit messages | 725 |
| TODO formal entries / unique IDs | 407 / 405 |
| TODO_DONE formal entries | 177 |
| Commit IDs absent from TODO alone | 343 |
| Commit IDs absent from both formal ledgers | 167 |
| TODO IDs absent from reachable commit messages | 23 |
| Missing-from-both IDs numbered 700 or higher | 6 |

The 700 cutoff is an explicit triage filter, not a claim about when ticket history became complete. All missing sets are in the adjacent JSON.

| Missing modern ID | Concrete reachable commit | Work described |
| --- | --- | --- |
| T-734 | f50fb4b | Slash suggestion leaves its own closing brackets behind. |
| T-752 | b3e1733 | Unknown-impact notice incorrectly names a direction. |
| T-768 | 561d901 | Calendar popover confirmation Delete behavior measurement. |
| T-849 | 0bf319d | NotePanel load failure spins without an answer. |
| T-879 | 3b56985 | Trailing swipe-edge regression coverage. |
| T-880 | 3b56985 | Focus timer answer/wiring regression coverage. |

`7bf2533` even explicitly records closing T-849/T-752 and splitting T-919 from T-768. Their absence from the current formal ledgers does **not** mean those fixes failed to land.

**30-second reproduction, from repository root:**
```sh
ruby docs/audits/2026-09-05/ledger-inventory.rb 4799e3c
git show 4799e3c:docs/TODO.md | rg -n '^\s*- \[T-(734|752|768|849|879|880)\]'
git show 4799e3c:docs/TODO_DONE.md | rg -n '^\s*- \[T-(734|752|768|849|879|880)\]'
```
The last two commands correctly return no matches (exit 1). See [commit-ledger-inventory.json](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/commit-ledger-inventory.json) for the full measured sets and evidence commits.

**Suggested fix:** Recover compact entries for these six IDs from their actual implementation/test commits and ticket revisions. Preserve the original classification; a coverage-only ticket must not be rewritten as a production bug. Use the existing explicit closed-entry pattern at [TODO.md:3150](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:3150), not guessed implementation dates or a removal commit as the fix SHA.

Then consider a lightweight **incremental** guard: newly introduced commit IDs must have a formal entry in TODO or DONE, or an explicit justified exception. Baseline the historical deficit rather than making every agent reconstruct 167 old tickets. A new-ID guard cannot determine whether two messages mean unrelated things; that remains review work.

**Acceptance checks:** all six IDs searchable as formal entries; cited SHAs actually contain the described work; existing historical exceptions do not block unrelated commits; duplicate entries are distinguished from distinct-work ID reuse; mentioning a ticket never automatically closes it.

## Important Non-Findings

- The five original R33 examples T-803/T-804/T-806/T-813/T-817 now have entries at [TODO.md:3150](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:3150) onward. They are not still missing.
- The large old archive deficit is already documented in T-462 at [TODO.md:6806](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:6806), explicitly with a **do not backfill** decision. This report does not reverse it.
- T-974 and T-781 each occur twice in TODO's formal-entry inventory. [TODO.md:2496](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:2496) explains that T-965 preserves declined hunks verbatim. These are known duplicate text, not measured unrelated-work ID reuse.
- The 23 IDs absent from commit messages are not automatically unimplemented: an implementation may omit the ticket ID, be uncommitted, or still be open.
- Exact spelling is preserved: T-01 is not normalized to T-1. The inventory measures the requested strings, not inferred ticket aliases.

## Limits

This scans every ancestor of the audited HEAD, **not** other unmerged branches, dangling commits, or remote-only history. No exhaustive semantic comparison of all 725 IDs' repeated uses was performed. Therefore R33's "any ID used for unrelated work" portion remains open; do not interpret this report as "none exist."

The inventory script only runs git show/log and parses text. It does not build, test, stage, or modify the repository.

## Looks Solid

The repaired T-803/804/806/813/817 entries preserve provenance. T-462 and T-965 explicitly retain historical uncertainty rather than pretending the ledger is complete. Those decisions make a bounded forward guard more useful than a noisy full-history gate.

## Patch Order

Recover the six modern entries, settle the desired incremental rule, then add its narrow guard and fixtures. Leave the legacy archive and known declined-hunk duplication to their existing work items.


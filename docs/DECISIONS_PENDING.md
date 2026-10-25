# Decisions waiting on you

Refreshed 2026-10-24 (later) by the coordinator. **Sections A and B are empty: every visible
defect and every data-edge item on this list has been answered.** What is left is section C —
three things only you can do, because they need your eyes or your hands, not a choice.

The reasoning behind each answer is in that ticket's own ledger entry, not here. This file is a
queue, not a record; `./scripts/ledger-view.sh head T-NNNN` is the record.

---

## A. Visible defects (ranked)

Empty. Twenty-two items, all answered on 2026-10-24.

## B. Rare, visible only on a data edge

Empty. Four items, all answered on 2026-10-24.

## C. Older, still open — owner actions rather than choices

- **T-4515** — you decided "look first": view Settings → Templates on the 11" iPad, docked
  landscape. One column reads fine → close as intended; reads badly → trim 4pt.
- **T-1117** — the five-minute EventKit check on your own Mac + iPhone
  (`docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`).
- **T-780** — the bare-commit hook is landed inert; arming it is
  `git config core.hooksPath .githooks`. Optional.

## Answered on 2026-10-24 (one line each; full reasoning is in each ticket's entry)

Implemented and closed the same day: T-5953 Cmd+N is New Task · T-5302 the capture panel keeps its
draft · T-5300 Cmd+K scrolls to and highlights the task · T-5832(b) "+ Section" under By-grouping ·
T-5882 the link key moves off Cmd+K · T-5883 the hotkey keeps ⌃Space and gets a name · T-5351 Month
days click and accept drops · T-6002 the dead sidebar rows are hidden · T-5174(b) the iOS sheets
refuse a swipe-down over typed text · T-6001 a Focus session survives eviction · T-5015(b) In
Progress is removed everywhere and the Mac row gains the repeat picker.

Decided, not yet built: T-5013 iOS half in flight · T-5307 inline tag row editor · T-5370 clamp Mac
task moves by duration · T-5151(b) the note link opens on the Notes page · T-5175 a typed tag is
added on dismiss · T-5356 a Week-header all-day chip opens its event · T-5060(b) the iOS Focus
checklist goes live, low priority · T-2090 drop the Completed toggle and port the Mac's foldable
"Completed" heading · T-5522 and T-5521 US spelling everywhere · T-4910 restore under "Name (2)" ·
T-4720 fix the weekly and meeting halves both.

Declined: T-5561 the Cmd+K ranking stays · T-3115 part (2), the tag slug stays as it is for v1 —
the slug is tag identity and changing it needs a migration.

Moot: T-5357, the "!" priority shortcut in an inspector title. `TaskDetailHeaderSection` has no
callers left after the subtasks-inspector landing and the inspector draws a plain `Text`, so the
bug is unreachable. The dead view and the two test suites still scanning it are T-6232.

## Resolved before 2026-10-24 (kept as one line each)

T-481 CLOSED declined (`7584c5f`, via T-1076) · T-352 `5ae916a` · T-487 `53e223c` · T-489 `2a8a70a` ·
T-491 `dcd110c` · T-497 answered `ab9e513` · T-4501 decided 2026-10-22 (13" iPad low priority; no
fix) · T-168 decided 2026-10-23 (Focus widget parked past RC) · T-5061's `.list` note link is no
longer a decision: T-3084 added `ListNavigationManager.open(…, listNoteID:)`, so it is plain work
(T-6092). Full reasoning for the closed ones is in this file's git history.

# Decisions waiting on you

Refreshed 2026-10-25 by agent `decisions2238` from `./scripts/ledger-view.sh brief` at `e084a8a7`.
Every item is an OPEN or PARTIAL ticket whose only remainder is yours. Each line: the question,
the options, **a recommendation**, the ticket. The reasoning is in the ticket
(`./scripts/ledger-view.sh head T-NNNN`); this file is a queue, not a record. "Code checked"
means the cited symbol was read at HEAD and still says what the ticket says.

---

## A. Things you would see in the app

1. **Resumed iOS Focus after a long gap** offers to log the whole gap (force-quit at night, 11 h
   in the morning). (a) pause when the gap passes a threshold, (b) cap the credited gap,
   (c) leave it, user resets. **(a)** — it is the Mac's lid-close rule. [T-6223] Code checked.
2. **Ends → After on a series past its 10th repeat**: the floor now seeds "15 of 15", which ends
   the series on the next completion. Seed `n+1`, `max(10, n+1)`, or leave. **`max(10, n+1)`** —
   keeps today's 10 for young series and never ends one by surprise. [T-6114] Code checked
   (`seededEndCount = 10` untouched).
3. **Old series still read "15 of 10"** (stored before the floor) in the Mac Repeat row and the
   iOS Ends row. Show "Ended", repair the count on open, or leave. **Show "Ended"** — the series
   has ended and the store stays untouched. [T-6191] Code checked (both rows pass the raw count).
4. **Mac "+ Section" on a list with no tasks** makes a section that is never drawn. Hide the row
   on an empty page, draw empty headings (and change iOS), or keep as parity. **Hide it** — same
   rule T-5832(b) applied everywhere else. [T-6201] Code checked.
5. **iPhone Tasks index can end up with no view rows** when the Mac hides both Today and All
   Tasks and the layout syncs. (a) phone shows them anyway, (b) every floor requires one of the
   two, (c) accept. **(a)** — phone-only and changes nothing on Mac or iPad. [T-6291]
6. **Settings → Templates on the 11" iPad, docked landscape**, is one column by 4pt. You chose
   "look first": one column reads fine → close; reads badly → trim 4pt. **Your look.** [T-4515]
   Code checked (split still starts at a 950pt pane).
7. **Mac Today inspector covers 10pt of the row's due chip** at the right of a wide window.
   Cover the source row, cover the list to the left, or no popover at that width. **Accept
   covering the row** — 10pt, cosmetic, and every other shape costs more. [T-1845]
8. **iOS task row: notes preview line or the note glyph?** Today it draws the preview.
   **Keep the preview** — it is what ships today and is more useful than a glyph. [T-2074]
9. **iOS calendar-block glyph is now the loudest red** on a rail-treated block (252,0,0). Cap
   the tertiary label tier's chroma like the rail, or leave. **Cap it** — the same re-solve keeps
   every contrast ratio. [T-3232]
10. **iOS timeline: drag a block sideways to another day** (the Mac can). Build or not.
    **Yes, after T-1475's drag is seen on screen** — it is parity. [T-3207]
11. **A `[[task]]` link to a just-created task** does nothing for a moment in every Mac note
    editor except `NotePanel`. Read the creation cache everywhere or keep. **Everywhere** — more
    links open and the store re-check stops a deleted one. [T-6781] **Done 2026-10-26: taken
    as recommended; the flag is gone and every editor reads the cache (T-6781 CLOSED).**

## B. Data edges (rare, nothing lost today)

12. **Merge-mode import** keeps the store's note for a day it already has and skips the
    archive's. Keep, or archive wins. **Keep** — it is what merge promises; overwrite takes the
    archive's. [T-4721]
13. **Two same-id tasks identical in every field** stay drawn twice. Add a per-row device token
    (schema change), add a user "merge duplicates" action, or leave. **Leave until after the RC**,
    then the user action — no migration. [T-6481]
14. **A block (`TaskBundle`) arriving by sync mid-session** hides its tasks until relaunch. Run
    retirement on sync, drop the `bundle == nil` filters, or document the window. **Document
    it** — nothing creates blocks any more, only old archives. [T-3213]
15. **Store backups inside iOS device backups**: exclude them or not. **Leave them included** —
    costs backup space only, and they are a recovery path. [T-3116] Code checked (no
    `isExcludedFromBackup` anywhere).
16. **Launch-time backups** (`.startup`/`.preRestore`) are raw copies, not `VACUUM INTO`. Switch
    or keep. **Keep** — they run before the store opens, and restores already check the SQLite
    header. [T-3044]
17. **The MCP write mode** opens the store with sync off. Mirror, refuse, or keep. **Keep** — it
    only exists behind `CADENCE_MCP_ENABLE_WRITES`, and the risk measured is latency. [T-3018]
18. **Widgets open the store with sync off.** Per-process mirroring, move the intents out of the
    app, or leave. **Leave, and fix the false comment at `CadenceStoreSupport.swift:198`** — the
    app mirrors the same store. [T-3227] Code checked: that comment says the widget has no
    container id; the entitlement now has one.
19. **Archive import field manifest** (format change). **After the RC.** [T-3019]
20. **Local-store-only guard on the store id** (developer launches only). **Leave** — T-3013's
    signing guard covers dev builds. [T-3015]
21. **"Records are arriving" in the sync notice** needs new plumbing. **Skip unless a tester
    asks.** [T-5500]

## C. Things only you can do (hands, not choices)

22. Five-minute EventKit check on your Mac + iPhone. [T-1117]
    (`docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`)
23. Turn on 24-Hour Time on the Mac, relaunch, say whether Cadence follows. [T-1163]
24. Restore a backup on a test account and see whether newer iCloud edits sync back in; that
    decides the backup note's wording. [T-3226]
25. `git config core.hooksPath .githooks`. Today it points at the deleted
    `~/Desktop/Projects/Cadence/.git/hooks`, so no hook runs (checked). [T-4900]
    **Ticket/code disagreement:** T-780 is CLOSED, but its own reopened text and the live
    config show the hook is not armed.
26. Fix your heartbeat task file `~/.claude/scheduled-tasks/cadence-heartbeat-resume/SKILL.md`:
    `:45` tells agents to create simulators and calls `7B642065…` your phone; `:32` uses one
    fixed xcb id for every run. Point both at `docs/AGENT_BRIEF.md`. [T-6351] [T-3071] [T-1920]
27. App Store Connect privacy answers: Name, Email, User ID → not collected. Public release
    only. [T-1424]
28. Logo: supply concept-A artwork (never committed) or approve a redraw; no name survived the
    screen. [T-16]
29. Two-device archive comparison on your own iCloud account. [T-2053]
30. Answer the per-session automation prompt when a UI run asks. [T-2049]

## D. Tooling and process (nothing a user sees)

31. **Push the 66 local-only branches to `origin`?** **Yes** — reversible, and removes the
    single-disk risk; delete nothing. [T-3275]
32. **CI Xcode pin: major or exact minor?** Today it takes the oldest 26.x on the image.
    **Exact minor** — the build is minor-sensitive and a loud red beats a silent toolchain
    move. [T-4742] Code checked (`assert-toolchain.sh:20,53`).
33. **Catching CI-only compile errors locally**: (b) install Xcode 26 beside 27, or (c) CI is
    the gate, push small. **(c)** — the one seen shape already has a lint. [T-3277]
34. **Unattributed commit: CI red or notice?** **Notice** — a red nobody can fix by editing is
    a gate that gets switched off. [T-2050] (unblocks T-1950)
35. **Refuse `--commits-stale` from agent ids?** **Yes** — the brief already forbids it; make
    the script agree. [T-3173]
36. **iOS-only unit suites run nowhere in CI.** (a) CI step on a simulator, (b) local rule,
    (c) accept. **(a)** — CI is the declared real gate. Either way fix
    `Cadence/iOS/AGENTS.md:23-24`, which still says `CadenceTests` cannot compile for iOS
    (checked). [T-6541]
37. **UI test for a deleted inspector header**: delete or repoint at the schedule panel.
    **Delete** — the views are gone and a repoint is new test design. [T-6602]
38. **Name every `Void`-returning `try?` save (47 sites)?** **No** — no defect behind it.
    [T-1990]
39. **Compile-time fingerprint for a sibling's mutation warning?** **No** — the two landed rules
    cover it. [T-3092]

---

Removed this pass because the ticket is CLOSED or the call is already made: every item in the
2026-10-24 "Answered" and "Decided, not yet built" lists (all now CLOSED), T-780 (replaced by
T-4900), T-4501 (you ranked 13" low priority; ships as is). Earlier history is in this file's
git log.

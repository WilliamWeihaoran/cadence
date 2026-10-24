# Decisions waiting on you

Refreshed 2026-10-24 by agent `dec1138` against `165e74fe` ([[T-6091]]). Every item below is an
OPEN/PARTIAL ticket whose remaining work is **your call**, re-checked against current source (not
the ticket prose). None has been seen on screen.

**How to answer:** reply with the ids and letters, e.g. `5953a 5302b 5357a …`, or `all defaults`.
**Default** is the agent's recommendation; taking all of them is a coherent set. Size is the work
once decided: XS < 1 h, S ≈ half a day, M ≈ a day. *Fence* = the file needs a Codex lease grant.

Ranked by how visible the defect is (how often a user meets it × how bad it is).

---

## A. Visible defects (ranked)

**1. T-5953 — Mac: Cmd+N opens a second Cadence window.** Off a Kanban column, Cmd+N falls through
to SwiftUI's File > New Window; Search, New Task and delete-confirm then draw in both windows.
(`macOSRootCommandEventSupport.swift:199`; no `.commands` anywhere in `Cadence/`.)
- a) Cmd+N = New Task everywhere; keep a "New Window" item with no shortcut (harness needs it).
- b) Strip Cmd+N from New Window; Cmd+N does nothing off a column.
- c) Leave.
- **Default a** — it is what every user reaches for Cmd+N to do. **S**.

**2. T-5302 — Mac quick-capture panel empties itself on click-away.** Clicking another app to copy
a link closes the panel; reopening it is blank. (`QuickTaskPanelController.swift:121`, fresh host
every open at `:48`.)
- a) Don't close on resign-key while the form has content.
- b) Close as now, but keep the draft and restore it on next open (clear on save/Esc).
- c) Both.
- **Default b** — panel still gets out of the way; nothing typed is lost. **S**. *Fence.*

**3. T-5357 — Mac inspector: "!" in a title silently resets priority.** Typing "Ship it!" in an
existing task's title drops it to Low and strips the "!"; even click-in/out does it on titles
ending in "!". iOS does not. (`SchedulePanelPopoverSupportViews.swift:106-108`.)
- a) No "!" shortcuts when editing an existing title (match iOS: drop the `priority:` binding).
- b) Keep shortcuts in the inspector.
- **Default a** — a shortcut for capture, not for editing someone's text. **XS**. *Fence.*
- **Probably moot:** `codex/subtasks-inspector` (being landed by `land1138` today) stops using
  `TaskDetailHeaderSection` and draws the inspector title as plain `Text`. Answer only if the
  editable title survives that landing.

**4. T-5300 — Mac Cmd+K: picking a task opens its list and stops.** No scroll, no highlight; a
completed result lands inside the folded Completed group. iOS opens the task.
(`macOSRootCommandActionSupport.swift:122`; `ListNavigationManager.Request` has no task id.)
- a) Open the list, expand Completed if needed, scroll to and select the row.
- b) Open the list and pop the task's inspector (`TaskDetailPopover`).
- c) Leave.
- **Default a** — reuses the existing deep-link reveal; keeps the user in context. **M**.

**5. T-5832(b) — Mac list "+ Section" does nothing visible under the default grouping.** Under By
Date (the Mac default), None and By Priority, a new section is created but never drawn.
(`ListDetailComponents.swift:141` draws the row under every grouping.)
- a) Show "+ Section" only under By List.
- b) Switch the tab to By List when a section is added.
- c) Leave.
- **Default a** — no control that appears to fail. **XS**.

**6. T-5013 — Empty headers over nothing.** (a) Mac Calendar Board's Overdue rail shows "Overdue 0"
over a ≥200pt empty column — its resting state for anyone who is caught up. (b) iOS Search with an
empty query on a narrowed scope shows the picker over blank space.
- a) Inline "Nothing overdue" (`CadenceInlineEmpty`, iOS vocabulary).
- b) Collapse the rail to its strip when empty.
- **Default a** — no layout jump when the count changes. Half (b) is decision-free (idle
  `CadenceInlineEmpty`); do it with this. **XS + XS**.

**7. T-6001 — iPhone/iPad: a running Focus session dies with the app.** If iOS evicts or the user
force-quits, the clock and unlogged minutes are gone. Mac banks on quit. (`iOSFocusView.swift:18`,
only `.onDisappear` banks.)
- a) Persist `{target, startedAt, accumulated}` and resume on next open.
- b) Bank a partial log on `scenePhase == .background` and restart clean.
- **Default a** — (b) would end the session every time the user glances at another app. **M**.
  *Fence.*

**8. T-5882 — Mac: Cmd+K inside a note opens Search instead of inserting a link.** The editor's
Cmd+K binding can never fire. (`macOSRootCommandEventSupport.swift:150`.)
- a) Let Cmd+K reach an editable markdown view; Search stays Cmd+K everywhere else.
- b) Keep Cmd+K = Search; move the link shortcut (e.g. Cmd+Shift+K).
- c) Leave; delete the dead mapping.
- **Default a** — Cmd+K = link is the universal editor convention. **XS**.

**9. T-5883 — Mac quick-capture hotkey is ⌃Space, unnamed anywhere.** It collides with macOS's
"previous input source"; with two input sources it either never fires or hijacks switching, and a
failed registration is only logged. (`GlobalHotKeyManager.swift:45-46`.)
- a) Keep ⌃Space; name it in Settings and show when registration failed.
- b) Change the default to ⌃⌥Space; name it + failure state in Settings.
- c) Make it user-configurable.
- **Default b** — avoids the system clash; (c) can follow post-RC. **S**.

**10. T-5351 — Mac Month view: clicking a day or "+N more" does nothing; days refuse a dropped task.**
Task chips now click/drag (landed); the cell does not. iOS month days are tappable.
(`CalendarPageMonthSupportViews.swift:328`, `:429`.)
- a) Click day / "+N more" opens that day in Day view; a day accepts a task drop (reschedules).
- b) Click selects the day only; no drop.
- c) Leave.
- **Default a** — chips already drag, so a drop target is the expected end of that gesture. **S**.

**11. T-6002 — iPhone: Settings → Sidebar Rows switches change nothing.** Hiding Calendar/Notes/Focus
on a phone has no effect (tabs and More are fixed). (`iOSSidebarLayoutSettingsSection.swift:54`.)
- a) On compact width list only the rows the phone honours (Today, All Tasks).
- b) Keep all rows; caption the card "Applies to iPad and Mac sidebars".
- **Default a** — controls that visibly do nothing read as bugs. **XS**. *Fence.*

**12. T-5174(b) — iOS creation sheets lose typed text on swipe-down.** New Task, New List, New
Context and Calendar quick-create. Edit sheets already refuse a dirty swipe.
- a) Refuse swipe while anything is typed (same guard as the edit sheets).
- b) Ask "Discard new task?" on swipe.
- c) Leave.
- **Default a** — one rule for every sheet. Check each iPad presentation first (T-3240). **S**.

**13. T-5015(b) — Mac task row shows no "In Progress" or repeat mark; iOS does.**
(`TasksPanelComponents.swift:6`; iOS `iOSTaskViews.swift:426`, `:459`.)
- a) Add both chips to the Mac row.
- b) Remove them from iOS.
- c) Leave.
- **Default a** — the Mac inspector now has Start/Stop; the row should show its result. **S**.

**14. T-5356 — iOS Week grid: all-day chips in the day header are untappable.** Timed blocks and the
single-day strip open the editor (landed); header chips sit inside the select-day `Button`.
- a) Chip tap opens the event; tap elsewhere in the header selects the day.
- b) Header tap selects the day; long-press a chip to open it.
- **Default a** — same gesture as every other event chip. **S**.

**15. T-5060(b) — iOS Focus notes: checklist circles look tappable and are disabled.**
(`iOSFocusView.swift:494` passes only `onOpenReference`.) Mac Focus notes are editable.
- a) Make checklist/embed toggles live (as in the task sheet).
- b) Keep read-only; draw the checklist as non-interactive.
- **Default a** — ticking items off during a session is the obvious use. **S**. *Fence.*

**16. T-5370 — Mac: a timed task can be dropped at 23:55 and drawn past midnight.** Events and iOS
clamp by duration; Mac task moves clamp the start only. (`TimelineDropInteractionSupport.swift:134`.)
- a) Clamp task moves by `estimatedMinutes`, like events and iOS.
- b) Keep start-only clamp.
- **Default a** — parity, and the block stays on the page. **XS**.

**17. T-5307 — iOS cannot rename, recolour or re-describe a tag.** Mac can (Settings, tag picker).
Porting the rules is decision-free; you pick where the editor lives.
- a) Inline row editor in Settings → Tags (mirrors Mac).
- b) Edit sheet from the tag row.
- **Default b** — a colour picker and text fields fit a sheet better on touch. **M**.

**18. T-5151(b) — Mac meeting-note sheet: clicking a `[[note]]` link does nothing.** Deliberate
no-op pending this call. (`EventNoteSupportViews.swift:87`.)
- a) Dismiss the sheet and open the note on the Notes page.
- b) Swap the sheet's content to the linked note.
- **Default a** — same route every other note link uses. **S**.

**19. T-5175 (tag half) — iOS task sheet: a tag typed but not added is dropped on popover dismiss.**
Subtask half landed (Save adds it).
- a) Add the typed tag when the popover dismisses.
- b) Clear it on dismiss.
- c) Accept.
- **Default a** — matches the subtask rule already shipped. **XS**.

**20. T-2090 — iPhone All Tasks spends a whole row on Sort / Completed.** Measured: neither shape fits
361pt without a new control.
- a) Leave two rows.
- b) Fold sort + completed into one icon menu in the header.
- **Default a for RC** — chrome only, and (b) is a new control plus a state hoist across three views.
  **M** if (b).

**21. T-5561 — Mac Cmd+K: list documents rank below that list's tasks.** Discovery works; ranking
only.
- a) Leave (Notes section last).
- b) List documents get their own section above Tasks.
- c) Whole Notes section moves above Tasks.
- **Default a** — nothing is broken, and (b)/(c) contradict your "not one section per kind". **XS**.

**22. T-5522 — "Sign in was canceled." vs "Cancelled" everywhere else.**
- a) Change that one string to "cancelled".
- b) Go US: "Canceled" at ~25 display sites; persisted raw value `cancelled` unchanged.
- **Default b** — the app standardised on US spelling (T-5003). **S**.

## B. Rare, visible only on a data edge

**23. T-4910 — Restoring an archived context whose name is now taken makes a pair the next launch
fuses.** (`iOSSettingsView.swift:536`, `SettingsView.swift:411`, MCP `update_context`.)
- a) Refuse the restore with a message. b) Restore under "Name (2)".
- **Default b** — the user cannot pick a name from a Restore button. **S**.

**24. T-3115(2) — Tags "C++", "C#" and "C" share slug `c` and merge.** (`TagSupport.swift:26-35`.)
- a) Slug keeps `+`/`#` as words. b) Accept for v1.
- **Default b** — slug is identity; changing it needs a migration, not an RC change. **M** if (a).

**25. T-4720 — Weekly/meeting notes still duplicate-merge on reset-then-import (daily is fixed).**
- a) Extend the import alias to weekly notes (meeting needs its own key). b) Leave.
- **Default a (weekly only)**. **S**.

**26. T-5521 — MCP tool descriptions/errors say "colour" (12 strings).** Not in-app; wire-visible.
- a) US-spell them. b) Keep.
- **Default a** — pre-1.0, nothing pins those strings. **XS**.

## C. Older, still open — owner actions rather than choices

- **T-4515** — you decided "look first": view Settings → Templates on the 11" iPad, docked
  landscape. One column reads fine → close as intended; reads badly → trim 4pt.
- **T-1117** — the five-minute EventKit check on your own Mac + iPhone
  (`docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`).
- **T-780** — the bare-commit hook is landed inert; arming it is
  `git config core.hooksPath .githooks`. Optional.

## Resolved since the last version (kept as one line each)

T-481 CLOSED declined (`7584c5f`, via T-1076) · T-352 `5ae916a` · T-487 `53e223c` · T-489 `2a8a70a` ·
T-491 `dcd110c` · T-497 answered `ab9e513` · T-4501 decided 2026-10-22 (13" iPad low priority; no
fix) · T-168 decided 2026-10-23 (Focus widget parked past RC) · T-5061's `.list` note link is no
longer a decision: T-3084 added `ListNavigationManager.open(…, listNoteID:)`, so it is plain work
(T-6092). Full reasoning for the closed ones is in this file's git history.

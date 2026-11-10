# Owner Sightings

The sightings **no agent transport can make**. Everything else in the owed-sighting stock an
agent can drive in an attended session; these nine need your hands on the keyboard, your mouse,
your permission grants or your API key.

They exist because the limit was **measured, not assumed** — each item below says which transport
was tried and how it failed. Do not let anyone schedule an agent slot on one of these again
without new evidence about the transport.

## How a slot uses this

You are not building or launching anything. An agent in the 8 PM slot:

1. claims the device with `./scripts/simulator-claim.sh`, builds from a clean tree, launches the
   app on a **private fixture store** (`CADENCE_UI_TEST_MODE=1`), and gets it to the screen the
   item names;
2. hands over and says "it's on Settings > Contexts, go";
3. you do the keystrokes or the gesture — usually under a minute each — and say what happened;
4. the agent records the verdict on that entry's **own first line** and commits it.

You never edit `docs/TODO.md`. Say what you saw; the session writes it down.

**Two devices, so two items can be live at once.** The iPad items share
`Cadence-iPadPro11`, so they go in one sitting with one build.

## Before a slot, prune this list

This file is a static list and the ledger is the authority. Print the items here that are **still
owed**:

```bash
comm -12 <(./scripts/sighting-plan.sh ids | sort) <(grep -oE '^### T-[0-9]+' docs/OWNER_SIGHTINGS.md | awk '{print $2}' | sort)
```

Anything in this file that the command does not print has been closed — skip it, and delete its
section. Read any item in full with `./scripts/ledger-view.sh head T-NNNN`.

---

## A. Keys an agent cannot send

Claude Code's simulator `press_key` is a **closed enum** — `return`, `delete`, `forward_delete`,
the four arrows, `home`, `end`, `page_up`, `page_down`, `select_all`, `undo`, `redo` — with **no
`escape` and no modifiers**. The `text` action types characters literally, so `\u001b` arrives as
six characters in the field. `xcrun simctl` has no key-injection subcommand, and the simulator's
own hardware keyboard belongs to the host Simulator app, which agents must not touch
(measured on T-11051, recorded in `Cadence/iOS/AGENTS.md`).

So: **you press these keys, with the Simulator window focused.**

### T-11051 — Escape discards a draft (iPad, 3 checks)

1. Settings > Contexts > New Context, type a name, press **Escape** — the sheet closes and no
   context is created. Repeat from Edit Context: the rename is discarded.
2. The list editor — sidebar New Area / New Project, then an open list's Edit — change the name,
   press **Escape**: the sheet closes, nothing saved.
3. Settings > Tags, tap a tag card's pencil, change the name, press **Escape** with the cursor in
   the Name field: the card returns to its display face with the **old** name. Tap the pencil
   again and confirm the draft was discarded.

If (3) does nothing while (1) and (2) work, a focused `UITextField` is swallowing Escape before
SwiftUI's `.onKeyPress` sees it — say so, and the tag card gets its own ticket. That is a real
finding, not a failed check.

### T-13282 — Cmd+N opens the composer unscoped (iPad)

Press **Cmd+N** on Today, on a list page, and in Notes with the editor focused. Each time the New
Task composer opens **unscoped** (no area/project pre-filled). Also: hold **Cmd** and confirm the
shortcut list shows "New Task" beside "Search"; Cancel and Add behave as they do from the `+`;
and Cmd+N over an already-open composer or inspector sheet does nothing harmful.

### T-12231 — Cmd+K into Search, then arrow keys (iPad half)

**Cmd+K** into Search, type, press **Down**. The first row takes the highlight **while the field
still has focus** — that is the unproven part. Then: Down/Up walk the rows and clamp at the ends,
Return opens the highlighted row, and Return on an "N more results" row reveals the rest.

If the field swallows Up/Down, the implementation needs a UIKit key command instead of
`.onKeyPress` on the `.searchable` host. Say which happened.

*(This entry's Mac half is Cmd+K to an off-screen event — see section D.)*

### T-10062 — Escape folds the "+ Section" row (iPad half of check 2)

On a list page, click **+ Section**, type a name, press **Escape** — the row folds back to
"+ Section" with nothing created; click **+ Section** again and the field is empty.

The Mac half of this check is section D. Check (1) of this entry — arrow keys and Return on the
Do-date roller and the Location panel — **is** agent-drivable (arrows and Return are in the enum),
so leave it to the agent and do only the Escape half.

---

## B. A gesture an agent cannot deliver

### T-8575 — the event sheet's swipe-down arms (iPhone)

Two separate walls, and the second is the one that matters:

- The fixture calendar is **read-only** — the sheet says `No writable calendars are available.` —
  so the commit semantics (the Notes (Events) row keeping the saved title, the well's debounced
  commit) cannot be exercised against it at all. You need a **writable calendar**, which means
  real Calendar access.
- The swipe-down itself is not reaching the sheet's dismissal. The control proves it: an injected
  460pt `touch_path` left a *modified* sheet open (which reads like the refusal the ticket wants),
  but the identical swipe on a **clean, unmodified** sheet also left it open. So every "it
  refuses" / "it closes" reading through that transport is unfalsifiable.

Do the four steps by hand on a sheet backed by a calendar you can write to, swiping with your
own finger on the trackpad.

### T-9722 — the All-day toggle on a macOS timeline draft (check 2)

A macOS timeline draft is created in exactly one way: a `DragGesture(minimumDistance: 8)` on the
day canvas (`TimelineDayCanvasSupportLayers.swift:25`). There is no click, long-press or menu
path to a draft, so with no draft there is no ghost to toggle, and none of the four teardowns
(Add, Cancel, outside click, canvas click) can be reached either.

That drag was measured dead: `XCUICoordinate.press(forDuration:thenDragTo:)` asked to move a
fixture event block **70.0pt** moved it **0.0pt** — frames byte-identical before and after.

So: **drag out a draft with your own mouse**, on macOS Today and on the Mac Calendar Week grid,
and check the All-day toggle on the ghost plus all four teardowns. In a
`scripts/run-macos-app.sh` build that an agent launched — never your shipping app, which is a
second writer on your real CloudKit store.

---

## C. A permission or a key only you hold

An agent may not request EventKit permission, open a real `EKEventStore`, or spend your OpenAI
key. These are not scheduling accidents; they are standing safety rules in `docs/AGENT_BRIEF.md`.

### T-9665 — the event note takes a tag (clause 2, iPhone)

**With Calendar access on**, open an event note from Notes > Events (the iPhone opens it in a
sheet), type ` #eventcheck`, Done — the Events row must show the chip.

Clauses (1) and (3) are already seen and closed; only this one is owed.

### T-9956 — the refused-Reminders buttons (item 1)

Needs a device whose **Reminders authorization is already DENIED** — reaching that state means
raising the EventKit prompt and answering it, which no agent may do, and
`CADENCE_UI_TEST_MODE` does not manufacture a refused authorization.

With Reminders refused: Settings > Reminders, and the Inbox's Apple Reminders row, each offer an
**amber "Open Settings" button with the filled gear** (`gearshape.fill`), and tapping it opens
Cadence's page in the Settings app.

The failure mode to avoid: with access *not yet asked*, both surfaces show `Allow Access` instead.
That is correct for that state and is **not** the thing this item asks about — a previous run
reported the wrong pair for exactly this reason.

### T-10222 — the AI draft's Return key (item 1)

**With your OpenAI key set**, open a note with a few action lines, run the AI task-draft action,
tap a draft's title, and press **Return** — on the on-screen keyboard and again on an iPad
hardware keyboard.

This is the only item on this list that costs real money. It is one call.

---

## D. Not on this list, but it needs you for one minute

These are **not** owner sightings — an agent can drive them end to end. They are blocked because
the macOS UI-automation grant is **per-session**, dies with every run, and only you, at the
keyboard, can answer the prompt. Arming it once at the start of a slot unblocks all of them:

- **T-9743** — the Mac Cmd+K palette having no scope chips.
- **T-9863** — the four Mac Sort surfaces.
- **T-10181** clause (3) — the Mac inline panel / inspector.
- **T-12231** Mac half — Cmd+K to a timed and an all-day event on a day not currently shown; each
  popover opens on its own block/chip after the jump, anchored correctly, with nothing opening in
  Today's pane or the timeline overlay.
- **T-10062** check (2), Mac half — the "+ Section" Escape fold in a `run-macos-app.sh` build.

The arming cost is one prompt. The yield is five items an agent then does without you, so **arm
it first**, before you spend a minute on anything in sections A–C.

Two things that end a Mac run, both now handled but worth knowing: the screen saver takes the
lock at `idleTime: 600` (`run-macos-app.sh` holds `caffeinate -d` for the life of the app it
launches, T-13541), and `xcb.sh` refuses outright while an automation prompt is outstanding — a
`check-automation` exit 0 with `outstanding=1` is **not** cleared.

---

## E. A real midnight — owner-only only until T-15200 lands

### T-14342 — an iOS task row's date label re-tints at midnight

This one is on the list for a different reason from everything above: not a key, a gesture or a
permission, but because **nothing can move the app's idea of today**. Measured on 2026-11-10:

- `DateFormatters.todayKey()` is `ymd.string(from: Date())` with no explicit time zone and **no
  env, launch-argument or fixture override anywhere in the tree**. `CadenceObservedDay.todayKey`
  reads the real clock, and `significantTimeChangeNotification` only invalidates — posting it
  cannot change what a row draws.
- `simctl` has no date/time subcommand, and the simulator follows the **host** clock. Moving that
  is a system setting that would also corrupt the sibling test host and CI parity, so no agent may.
- The simulator's Settings has **no Date & Time pane** at all.

So: leave the app open on a task list over a real midnight and watch the row re-tint. That is the
only route an attended session has today.

**It should not stay on this list.** T-15200 asks for a `CADENCE_UI_TEST_TODAY=YYYY-MM-DD` honoured
under `CADENCE_UI_TEST_MODE` only. Once that lands, this item and every future midnight-rollover
sighting become ordinary agent work — so check whether T-15200 is closed before you spend a night
on this.

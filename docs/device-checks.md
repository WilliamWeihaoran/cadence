# Checks that need a real device

The simulator cannot settle these. Each says what to do, what should happen, and what it means
if it doesn't.

---

## 1. Can you dismiss the keyboard in the Notes tab? ([T-55])

**Why it can't be checked here:** the simulator suppresses the software keyboard while a Mac
keyboard is attached, and that toggle lives in Simulator.app.

**Why it's in doubt:** the note editor's "Done" bar was removed (`64218d1`). That bar's only job
was to drop focus. What's left is drag-to-dismiss — dragging the note text downward should carry
the keyboard away, the way Apple Notes behaves. It has never been seen to work here.

**On the phone:**
1. Notes tab → Daily. Tap into the note body so the keyboard comes up.
2. Drag the *note text* downward.

- **Expected:** the keyboard follows your finger and goes away.
- **If it doesn't:** you are stuck with the keyboard up on that screen — the Notes tab hides its
  navigation bar, so there is no other affordance. Tell me and I'll add a nav-bar Done or
  tap-outside-to-dismiss. **Not** the old bar back.

**Only the Notes tab is at risk.** Every sheet-hosted editor (task detail, event notes, calendar
sheets) still has its own Done/Cancel above the keyboard.

---

## 2. Does double-tap work in the note editor? ([T-55])

**Why it can't be checked here:** the simulator tooling has no double-tap action, and two scripted
taps land outside iOS's ~350ms window — they register as two single taps.

**Why it's in doubt:** a gesture recogniser used to swallow every double tap. It is now gated so it
never begins on ordinary prose (`64218d1`), which should make the system behaviour reappear — but
that is reasoning, not observation.

**On the phone, in any note:**
1. Double-tap a plain word. → **Expected:** the word is selected.
2. Double-tap inside a rendered code block or table. → **Expected:** it reveals its markdown source.
3. Single-tap plain text. → **Expected:** the caret lands there.
4. Tap a `[[wiki link]]` or a task-embed card. → **Expected:** it opens.

Any of 1–4 failing is worth reporting; 1 and 2 are the untested pair.

---

## 3. Drag-to-create ([T-89])

**Why it can't be checked here:** neither simulator gesture API lifts a `UIDragInteraction`, so no
drop ever fires. This was confirmed against already-shipped drag code, so it is the harness rather
than any one change — but it means **every drag-to-create claim in this repo is inference from unit
tests, not something anyone has seen work.**

**On the phone:**
1. Long-press the `+` in the tab bar and drag it onto a task row. → **Expected:** the composer opens
   pre-filled with that row's list, section and dates.
2. Drag it onto a *group header* (e.g. "Due Today"). → **Expected:** same, seeded from the group.
3. Drag onto an **empty** group's header. → **Expected:** the same, and this is the case the feature
   was built for.
4. While dragging, a dashed "New task" ghost should open **between** rows and name what it will
   inherit — not highlight an existing task.
5. Tap the `+` normally afterwards. → **Expected:** opens the composer instantly, unseeded.

If a drag leaves the tab bar unresponsive, relaunch — that is a known side effect of an abandoned
drag in the simulator and worth knowing whether it happens on hardware too.

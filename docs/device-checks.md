# Checks that need a real device

Everything here has been pushed as far off-device as it goes; what is left is what a simulator or a
test genuinely cannot settle. Each item says what to do, what should happen, what it means if it
doesn't, and — new — **what is already settled**, so nobody re-checks something a test now holds.

Ordered by cost. Items 1–4 are a phone; item 5 is any iPad-width run. The whole list is about five
minutes.

---

## 1. Can you paste an image into a note? ([T-280])

**Why it can't be checked here:** `Cadence/iOS/` is inside `#if os(iOS)` and the test target builds
for macOS, so the one link nobody can evaluate is whether UIKit consults
`iOSMarkdownTextView.canPerformAction` when it builds the edit menu. That is the entire fix.

**Already settled off-device:** the rest of the chain, in `MarkdownImagePasteTests`. The override
dispatches to a handler, `makeUIView` assigns that handler unconditionally, and the coordinator it
reaches composes its insertion out of the same shared calls the macOS paste uses — which is why
`theMobilePasteWritesTheSameTextTheMeasuredMacOSPasteDoes` can measure macOS against a real
clipboard and speak for the phone. So if Paste fires at all, the picture lands.

**On the phone:**
1. Take a screenshot (Side + Volume Up) so the clipboard holds an image and nothing else, or copy a
   picture out of Safari.
2. Notes tab → Daily. Tap into the note body, then long-press to raise the edit menu.
3. → **Expected:** **Paste** is there and enabled.
4. Tap it. → **Expected:** the image appears on its own line, drawn as a picture rather than as
   `![](cadence-image://…)` text.

- **If Paste is absent or greyed:** the override is not being consulted and `canPerformAction` is
  the wrong seam on iOS — the answer is a `UIEditMenuInteraction` item or `buildMenu(with:)`, not a
  wider gate. Tell me and I'll move it.
- **If Paste is enabled and nothing happens:** the handler did not mint an asset. That is expected
  in the note *template* editor and the calendar event sheets, which refuse image insertion on
  purpose (T-421/T-422) — but in the Notes tab it is a defect.

---

## 2. Can you dismiss the keyboard in the Notes tab? ([T-55])

**Why it can't be checked here:** the simulator suppresses the software keyboard while a Mac
keyboard is attached, and that toggle lives in Simulator.app.

**Why it's in doubt:** the note editor's "Done" bar was removed (`64218d1`). That bar's only job was
to drop focus. What's left is `keyboardDismissMode = .interactive` — dragging the note text downward
should carry the keyboard away, the way Apple Notes behaves. It has never been seen to work here.

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

## 3. Does double-tap work in the note editor? ([T-55])

**Why it can't be checked here:** the simulator tooling has no double-tap action, and two scripted
taps land outside iOS's ~350ms window — they register as two single taps.

**Why it's in doubt:** a gesture recogniser used to swallow every double tap. It is now gated in
`gestureRecognizerShouldBegin` so it never begins on ordinary prose (`64218d1`), which should make
the system behaviour reappear — but that is reasoning, not observation.

**Already settled off-device:** *which* taps the recogniser claims. The gate is one call to
`MarkdownRenderedBlockDeletionSupport.renderedBlock(atUTF16Location:in:)`, filtered to `.code` — so
"does this location belong to the recogniser?" is a tested shared predicate, not a guess. What no
test can see is whether UIKit then hands the released touch to the text view.

**On the phone, in any note:**
1. Double-tap a plain word. → **Expected:** the word is selected.
2. Double-tap inside a rendered **code fence**. → **Expected:** it reveals its markdown source.
3. Single-tap plain text. → **Expected:** the caret lands there.
4. Tap a `[[wiki link]]` or a task-embed card. → **Expected:** it opens.

Any of 1–4 failing is worth reporting; 1 and 2 are the untested pair.

**A table is deliberately not on that list any more** (T-221). A double tap on a grid used to put
the caret in it and un-render it; a **single** tap now opens the cell under your finger, and the
source is a menu command. If double-tapping a table reveals source, that is a regression, not a
pass.

---

## 4. Drag-to-create ([T-89])

**This item shrank, twice.** It used to say every drag-to-create claim in the repo was inference,
because no simulator gesture API lifts a `UIDragInteraction`. That was already wrong when it was
written — [D-89] drove a real drag on the simulator, and the recipe is in `AGENTS.md` — and it is
now moot as well: since T-171 neither `+` uses the system drag at all. Both run one custom
`DragGesture` through `CadenceCapturePressResolver`, hit-testing against frames the targets publish
to `iOSNewTaskDropFrameRegistry` — all of which is ordinary code, and all of which is now tested.

**Already settled off-device**, in `CadenceCapturePaletteTests`, `CadenceTaskDropSupportTests` and
`CadenceTaskGroupDropSupportTests`: that a press which moves is a drag and a press which holds is a
palette; that the palette cannot bloom on top of a drag; that the smallest containing frame wins the
hit test and a point over nothing hits nothing; that a drop on a row takes the row's placement over
the button's own seed while a drop on nothing keeps it; and what caption a group header — including
an empty one — hands the ghost.

**What is left is the part no pure function can answer:** whether a real finger's event stream
actually drives those transitions, and whether the frames the registry publishes land where the eye
sees the rows.

**On the phone:**
1. Press the `+` in the tab bar and move immediately — do not hold. Drag onto a task row.
   → **Expected:** the composer opens pre-filled with that row's list, section and dates.
2. Press and *hold* the `+` without moving. → **Expected:** the capture palette blooms; sliding
   between its segments selects, and it does **not** turn into a drag under your finger.
3. Drag onto an **empty** group's header. → **Expected:** seeded from the group. This is the case
   the feature was built for, and the one where a published frame is most likely to be wrong.
4. While dragging, a dashed "New task" ghost should open **between** rows and name what it will
   inherit — not highlight an existing task.
5. Tap the `+` normally afterwards. → **Expected:** opens the composer instantly, unseeded.

If a drag leaves the tab bar unresponsive, relaunch, and tell me — that was a known simulator side
effect of an abandoned drag and it is worth knowing whether hardware does it too.

---

## 5. Do the note sheets still get regular width on an iPad? ([T-447])

**Why it can't be checked here:** it is not a device question so much as a *width* question — an
iPad-sized run of any kind settles it, simulator included. It is here because no scan can see it.

**Why it's in doubt:** `iOSNoteEditorSheetHeader` now reads `@Environment(\.horizontalSizeClass)`
itself rather than taking the flag from the sheet that hosts it (T-281). Nothing in `Cadence/`
writes that environment key — `nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader`
pins that — so the only thing left is whether SwiftUI re-derives it inside
`NavigationStack` → `HStack` → `.frame(width: 320)`. In theory a fixed frame does not change a scene
trait. In practice nobody has looked.

**On an iPad, both note sheets** — the event-note sheet (Calendar → an event → its note) and the
linked-note sheet (open a `[[wiki link]]` from inside a note):

- **Expected:** a 320pt rail on the left whose `Theme.surface` background runs the **full height of
  the sheet**, with a 24pt bold title and 20pt padding all round.
- **If the trait did not propagate:** the rail's background stops just under the title instead of
  filling the column, the title drops to 22pt and the padding to 18/14. The height is the
  unmistakable tell; do not try to judge 24pt against 22pt by eye.

Also worth one glance while you are there: on the event-note sheet, a note that saves while its
Apple Calendar mirror does not should show its failure line **under the title, inside that header
block**. The outcome is covered by `CadenceEventKitPlatformParityTests` and the position by
`theEventSheetKeepsItsCommitNoticeInsideTheHeader`; only the pixel is unseen.

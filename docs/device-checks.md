# Checks that need a real device

Everything here has been pushed as far off-device as it goes; what is left is what a test **and a
simulator** genuinely cannot settle. Each item says what to do, what should happen, what it means if
it doesn't, and **what is already settled**, so nobody re-checks something a test now holds.

Three items, eight steps, all on a phone. Under three minutes.

**Re-triaged 2026-09-02 ([T-561]).** It was five items and fifteen steps, written in August when
nobody could drive anything. Agents drive iPhone and iPad simulators now, so most of it is somebody
else's job — [Moved off this list](#moved-off-this-list) at the bottom says what went where and what
took it. Do not add an item back here without naming the simulator action that cannot perform it.

---

## 1. Can you paste an image into a note? ([T-280])

**Why neither a test nor a simulator can settle it:** `Cadence/iOS/` is inside `#if os(iOS)` and the
test target builds for macOS, so the one link nobody can evaluate is whether UIKit consults
`iOSMarkdownTextView.canPerformAction` when it builds the edit menu. That is the entire fix. A
simulator can long-press and screenshot the menu, but nothing in the simulator surface puts an
**image** on the device pasteboard, and an empty clipboard cannot enable Paste — so that run would
prove nothing either way.

**Already settled off-device:** the rest of the chain, in `MarkdownImagePasteTests` — the override
dispatches to a handler, `makeUIView` assigns it unconditionally, and the coordinator composes its
insertion out of the same shared calls the macOS paste uses, which is why
`theMobilePasteWritesTheSameTextTheMeasuredMacOSPasteDoes` can measure macOS against a real
clipboard and speak for the phone. So if Paste fires at all, the picture lands. **Which hosts may
offer it at all** is settled too, in `MarkdownImagePasteAffordanceTests`:
`theMobilePasteGateConsultsTheHostsImagePolicy` pins that the gate reads
`allowsMarkdownImageInsertion` *before* the pasteboard, and
`theMobileRepresentableThreadsTheHostsImagePolicyIntoTheTextView` the wire from host to view.

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
- **If Paste is enabled and nothing happens:** the handler did not mint an asset. That is a defect
  wherever you see it. **This bullet used to say the inert-Paste case was expected in the note
  template editor and the calendar event sheets; that is no longer true.** T-504 (`dc5da1e`) landed
  four hours after this checklist was last written, and a refusing host now advertises no bitmap
  type at all — so in those editors **Paste should be absent**, not enabled-and-inert
  (`MarkdownImagePasteAffordanceTests.aRefusingHostDoesNotOfferPasteForAScreenshot`, with
  `aRefusingHostStillOffersPasteForText` for the text pasting that must keep working, and
  `CadenceMarkdownImageInsertionScopeTests.theNoteTemplateEditorRefusesImageInsertion` /
  `theCalendarEventEditorRefusesImageInsertion` for the refusals themselves).

---

## 2. Can you dismiss the keyboard in the Notes tab? ([T-55])

**Why neither a test nor a simulator can settle it:** the simulator suppresses the software keyboard
while a Mac keyboard is attached, and that toggle lives in Simulator.app — which agents here are not
to touch. No keyboard, no keyboard-dismiss gesture.

**Why it's in doubt:** the note editor's "Done" bar was removed (`64218d1`); its only job was to
drop focus. What's left is `keyboardDismissMode = .interactive`
(`Cadence/iOS/iOSMarkdownEditor.swift:170`) — dragging the note text downward should carry the
keyboard away, the way Apple Notes behaves. It has never been seen to work here, and no test asserts
it, deliberately: the property being set is not the question, UIKit honouring it is.

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

## 3. Does a double tap work in the note editor? ([T-55])

**Why neither a test nor a simulator can settle it:** the simulator surface has no double-tap
action. `tap` is one touch, `touch_path` is one continuous drag, and two scripted `tap`s are two
tool round-trips — far outside iOS's ~350 ms window, so they land as two single taps.

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

Both are worth reporting; they are the untested pair, and they are all that is left of this item —
the single-tap steps that used to sit under it went to the simulator.

**A table is deliberately not on that list** (T-221). A double tap on a grid used to put the caret
in it and un-render it; a **single** tap now opens the cell under your finger, and the source is a
menu command. If double-tapping a table reveals source, that is a regression, not a pass.

---

## Moved off this list

Each left because something can settle it that could not in August. None is "probably fine" — each
is a queued simulator job, listed so the trail does not go cold.

- **Drag-to-create ([T-89], was item 4, five steps) — a simulator drives the gesture.** `control`'s
  `touch_path` drags a single finger along an arbitrary path *including long-press-then-drag* —
  every gesture the item asked for — and `attach` opens a live panel a person can watch the mid-drag
  ghost in; the composer that opens after the lift is a screenshot. Since T-171 neither `+` uses a
  system drag: both run one custom `DragGesture` through `CadenceCapturePressResolver`, hit-testing
  frames the targets publish to `iOSNewTaskDropFrameRegistry`. Transitions and seeds are pinned in
  `CadenceCapturePaletteTests`
  (`aPressThatMovesBeforeTheHoldIsADragImmediately`, `theHoldCannotOpenThePaletteOnTopOfADrag`,
  `theSmallestContainingFrameWinsAHitTest`, `aPointOverNothingHitsNothing`,
  `aDropOnARowSeedsThatRowsPlacement`, `aDropOnNothingSeedsWhatATapSeeds`),
  `CadenceTaskDropSupportTests` and `CadenceTaskGroupDropSupportTests`
  (`anEmptyColumnSeedsWhatTheFilledOneNextToItSeeds`,
  `theGhostOnASectionHeaderNamesTheListAndTheColumn`). What is left is only whether the frames the
  registry publishes land where the eye sees the rows — a look, not a phone. **The old item's
  pointer to a drag recipe "in `AGENTS.md`" was stale: there is no such recipe there.**

- **Both note sheets at iPad width ([T-447], was item 5) — a simulator settles it.** The item always
  conceded this is a width question, not a device one, and six stock iPad simulators already exist
  here, so nobody has to create one. The off-device half is done:
  `CadenceMisfiledSurfaceTests.nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader`
  pins that nothing in `Cadence/` writes the environment key, and the event sheet's commit notice is
  covered by `CadenceEventKitPlatformParityTests` for outcome and
  `theEventSheetKeepsItsCommitNoticeInsideTheHeader` for position. The tell is unchanged and binary:
  on the event-note sheet and the linked-note sheet, the 320pt rail's `Theme.surface` either runs the
  full height of the sheet or stops just under the title. Do not judge 24pt against 22pt by eye.

- **Single-tap caret, and tapping a `[[wiki link]]` or a task-embed card (was steps 3.3 and 3.4) — a
  simulator taps.** One `tap` and one screenshot each. Which target a location resolves to is
  already pinned by `MarkdownReferenceDisplaySupportTests`
  (`referenceRangesPointAtVisibleDisplayText`, `inlineSegmentsPreserveReferenceTargets`).

- **"The UI target is unreliable" is no longer a reason to route anything here.** `CadenceUITests`
  was never flaky ([T-563]) — it cannot pass while the Mac's screen is locked, and unlocked it
  reached the foreground in 20 of 20 runs, p50 0.91 s. The one live intermittency is [T-710], a
  seeded sidebar row missing at 5 s in 4 of 20 runs — a macOS test-timing question, not a phone one.

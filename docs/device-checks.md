# Checks that need a real device

Everything here has been pushed as far off-device as it goes; what is left is what a test **and a
simulator** genuinely cannot settle. Each item says what to do, what should happen, what it means if
it doesn't, and **what is already settled**, so nobody re-checks something a test now holds.

Two items, four steps, all on a phone. Under two minutes.

**Re-triaged 2026-09-02 ([T-561]).** It was five items and fifteen steps, written in August when
nobody could drive anything. Agents drive iPhone and iPad simulators now, so most of it is somebody
else's job — [Moved off this list](#moved-off-this-list) at the bottom says what went where and what
took it. Do not add an item back here without naming the simulator action that cannot perform it.

**The image-paste item came off later the same day ([T-280]).** Its whole premise — "nothing in the
simulator surface puts an **image** on the device pasteboard" — is false, and it was measured false
rather than argued away: `simctl addmedia` + Photos' own **Copy** does it. The item is settled, on a
simulator, and the recipe is in [Moved off this list](#moved-off-this-list).

---

## 1. Can you dismiss the keyboard in the Notes tab? ([T-55])

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

## 2. Does a double tap work in the note editor? ([T-55])

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

- **Pasting an image into a note ([T-280], was item 1, four steps) — a simulator settles it, and
  did, on 2026-09-02.** The blocking claim was that no simulator action puts an image on the device
  pasteboard. Two things are now measured. **`xcrun simctl pbcopy <udid> < file.png` does not** — it
  lands the bytes as *text*, and pasting them into a note inserted `âPNG IHDRxx…` as prose, which is
  exactly the false negative that claim would have produced. **`xcrun simctl addmedia <udid>
  file.png`, then Photos → long-press → Copy, does**: `UIPasteboard.general.hasImages` is true and
  nothing else is on it. With that clipboard, in a Pad note on iPad Pro 11-inch: **Paste appeared in
  the edit menu and inserted the picture on its own line, drawn as an image, not as
  `![](cadence-image://…)` text.** So UIKit *does* consult `iOSMarkdownTextView.canPerformAction`
  for `paste:` when it builds the menu, and `paste(_:)` is dispatched — the two links `#if os(iOS)`
  kept out of `CadenceTests`. The **discriminator**, same clipboard, same gesture, one tap apart: in
  the quick-create composer's *event* mode — a refusing host — the menu offered **AutoFill only, no
  Paste**, which is `MarkdownImagePasteAffordanceTests.aRefusingHostDoesNotOfferPasteForAScreenshot`
  and [T-504] seen on screen. Nothing but `allowsMarkdownImageInsertion` differs between those two
  text views, so Paste's presence in one and absence in the other cannot come from `super`.

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
  **Run 2026-09-02, iPad Pro 11-inch, portrait (834pt): there is no rail to judge.** Both sheets, and
  `iOSCalendarEventEditSheet` with them, drew their **compact** branch — header stacked above the
  editor, divider under it. They are presented with a plain `.sheet`, which on iPad is a form sheet
  measured at ~577 x 639pt, and UIKit hands a sheet that narrow a **compact** horizontal size class.
  So sheet and header agreed, which is the T-447 predicate not failing — but it agreed on *compact*,
  and the regular branch was never entered. Whether it is reachable at all on iPad is [T-731]; the
  simulator surface has no rotate action, so landscape is untested. Predicate two **did** land, and
  is width-independent: on a note attached to a read-only *US Holidays* event, typing put *"This note
  is saved, but Apple Calendar didn't take the change."* in `Theme.red` **under the title, inside the
  header block**, above the divider — `iOSNoteEditorSheetHeader`'s `accessory` slot, exactly where
  `theEventSheetKeepsItsCommitNoticeInsideTheHeader` says it belongs.

- **Single-tap caret, and tapping a `[[wiki link]]` or a task-embed card (was steps 3.3 and 3.4) — a
  simulator taps.** One `tap` and one screenshot each. Which target a location resolves to is
  already pinned by `MarkdownReferenceDisplaySupportTests`
  (`referenceRangesPointAtVisibleDisplayText`, `inlineSegmentsPreserveReferenceTargets`).

- **"The UI target is unreliable" is no longer a reason to route anything here.** `CadenceUITests`
  was never flaky ([T-563]) — it cannot pass while the Mac's screen is locked, and unlocked it
  reached the foreground in 20 of 20 runs, p50 0.91 s. The one live intermittency is [T-710], a
  seeded sidebar row missing at 5 s in 4 of 20 runs — a macOS test-timing question, not a phone one.

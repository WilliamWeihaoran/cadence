# Cadence — task list

The running record of work: open, in progress, done, cancelled. Started 2026-08-16.

**Format.** One line per item: `- [id] Title — note`. Ids are stable and never reused, so a
cancelled or done item can still be referenced later. Done items keep their commit sha, because the
commit message is where the *reasoning* lives; this file is only the index.

**Rule (set 2026-08-17).** *Every* request the user makes lands here the moment it is made, whether
or not work starts on it — under **In progress** if it is being worked now, otherwise under the
right Open section. An item moves to **Done** only when the code behind it is committed (or
otherwise verified), not when it is written.

**Target devices** (set 2026-08-16). Build and verify for these three only; anything that exists
solely to serve other hardware is dead weight and should be removed rather than maintained:

| Device | Points | Notes |
|---|---|---|
| iPhone 15 (base) | 393 × 852 | compact width, the only phone shape that matters |
| iPad Pro 11" | 834 × 1210 portrait · 1210 × 834 landscape | pane = window − 188pt sidebar → **646** portrait, **1022** landscape |
| MacBook Pro 14" | 1512 × 982 | the macOS surface |

Both iPad panes matter to Today's layout: 646pt portrait falls **below**
`CadenceTodayLayoutSupport.twoPaneMinimumWidth` (761), so portrait is one column and landscape is
two. The three-pane floor of 1022pt that this note used to cite is gone with the layout itself
(T-06).

---

## In progress

_Nothing in flight._

## Where findings come from

This file is authoritative. Two other documents hold *findings*, not tracked work:

- [`refactor-phases-4-6.md`](refactor-phases-4-6.md) — 153 findings from a read-only audit at
  `249b475`, **two weeks stale**. A good hunting ground; verify each finding against current code
  before filing it, because several have been overtaken.
- [`TODO_DONE.md`](TODO_DONE.md) — everything shipped, with SHAs. **Search it before filing**;
  tickets have been re-reported here more than once.

## Open — decided, not started

- [T-847] **`Theme.dim` fails the body-text contrast floor on every surface.** Measured by an outside
  audit (R30 in `docs/CODEX_REQUESTS.md`) against all four backgrounds: **4.12 / 3.84 / 3.59 / 3.40**.
  WCAG wants 4.5 for body text; `dim` clears only the 3.0 large-text/control floor. This is the
  widest-spread quality defect found in the run — and note that [[T-672]] has just converged eleven
  search-field clear buttons onto `Theme.dim`, so the population is growing, not shrinking. **Premise
  correction that matters:** Cadence has no light appearance — `Theme.preferredColorScheme` is fixed
  to dark — so these are the only numbers that exist, not half of them. Decide whether `dim` is a
  large-text-and-controls-only token and enforce that, or raise it.
- [T-848] **The accent palettes and the Markdown highlight fail even the 3:1 floor.** Cadence: blue
  2.75, red 2.78, green 2.08, amber 1.90, purple 2.72, teal 1.98. Glacier is worse — amber **1.54**,
  teal 1.75. Highlighted Markdown text measures **1.48:1** (`Theme.swift:314-316`;
  `MarkdownEditorSupport.swift:219-221`), which is close to unreadable. User-chosen accents are a
  design decision, but a shipped default that no one can read is not.
- [T-843] **"Block" has drifted back to "Bundle" in 11 live UI literals across 9 files.**
  `TaskBundle.defaultDisplayTitle` says Block and iOS block creation agrees, but Focus and macOS
  creation/edit/delete still say `Bundle`, `Bundle tasks`, `Bundle Focus`, `Log Bundle Session`,
  `Bundle title`, `Delete Bundle?` and `Delete Bundle`: `CadenceFocusBundleSupport.swift:163`,
  `iOSFocusView.swift:500`, `FocusChromeSupportViews.swift:120`,
  `FocusBundleTaskSupportViews.swift:20`, `FocusLogSessionPopovers.swift:163`,
  `FocusSidebarSupportViews.swift:155`, `QuickCreateChoicePopover.swift:248,355`,
  `TimelineBundleBlock.swift:62`, `TimelineBundleBlockSupportViews.swift:71,203`. Reachable through
  ordinary Block creation, editing and Focus. **[[T-567]] is closed and does not cover this** — it
  centralised only the untitled fallback. Fix: shared user-facing Block vocabulary beside
  `defaultDisplayTitle`, product words only (leave Settings' technical `Bundle ID` alone), plus a
  source scan for `Bundle` in UI literals outside an explicit exemption.
- [T-844] **Four count strings are ungrammatical at 1.** "1 selected tasks"
  (`FocusLogSessionPopovers.swift:166`), "1 tasks" (`FocusSidebarSupportViews.swift:156`),
  "Collapsed, 1 notes" (`CadenceNotesListSupport.swift:692`), "1 milestones / 1 habits"
  (`iOSFeatureViews.swift:184-190`). One shared pluralisation helper; test 0, 1 and 2.
- [T-845] **The two Markdown editors disagree on capitalisation.** iOS says `Bulleted List`,
  `Code Block`, `Note Link`; macOS VoiceOver says `Bulleted list`, `Code block`, `Note link`. The
  shared vocabulary already exists at `MarkdownSlashCommandCoreSupport.swift:34-50`. Have the core
  own sentence-case titles and both adapters read them — do not build a second case table.
- [T-846] **Reminders demands access before the user has chosen.** `.notDetermined` says "Reminders
  access required" (`CadenceRemindersPresentationSupport.swift:91-97`), where Calendar and
  Notifications correctly use a neutral `Connect …` offer and reserve `… access required` for after
  a denial. Reachable on the first visit to Reminders settings. Give it the same two-title model.
- [T-849] **The note panel draws an unlabelled failure.** `NotePanel.swift:80-99,113`;
  `loadOrCreateCoreNotes` swallows. Make it throwing or return a typed result, and keep loading.
- [T-851] **Milestone Momentum is the only widget whose reload calculation is unshared.** Its three
  sibling support types already share one. Widgets ship inside the submitted binary, so a timeline
  that never reloads is a shipped defect. Reuse a shared policy that accepts ready/empty intervals.
- [T-852] **Nothing has ever proved `CadenceMCPServer` compiles.** It uses an explicit Sources list,
  so the app scheme cannot see it break, and it has been outside every green run of this project.
  An outside audit confirmed its membership and schema check out but stated plainly it cannot
  determine the target compiles without building it. Somebody must build it.
- [T-850] **iOS calendar quick-create branches on only one denied state.**
  `iOSCalendarQuickCreateSheet.swift:342-357` should consume the shared Calendar authorization
  presentation. Real, but iOS is not the v1 distribution channel — **parked behind macOS work.**

- [T-809] **Two sweeps outside [[T-808]]'s product-tree boundary are still unpinned.** The R19
  audit counted them; `CadenceRealTreeSweepManifest.txt` deliberately does not, because its rule is
  "walks Swift source under `Cadence`/`CadenceWidgets`/`CadenceMCPServer`" and neither does.
  `CadenceInPlaceEditFlushCommitTests/themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse`
  enumerates `CadenceTests` (the discard-site harvest), and
  `TodayAndInboxNamingTests/noAgentFacingDocSpellsARetiredIPadName` enumerates agent-facing docs.
  Both have the same hole the manifest closed for the other 240: delete the `@Test` and nothing goes
  red. Wanted: either widen the manifest with a second, separately-rooted section (test-target and
  docs sweeps), or a small sibling manifest — but **not** a looser rule on the product one, whose
  three conditions are each load-bearing and witnessed.

- [T-795] **The icon-only-button suite is red on HEAD independent of T-674, for a reason worth
  fixing before the next agent reads its output as a regression.** Measured 2026-09-04 against an
  unmodified HEAD (`8bec9eb`) in an isolated `git archive` tree, twice: `CadenceIconOnlyButtonAccessibilityTests`
  fails two different ways that are really one cause. First, its ledger still lists five files
  [[T-673]]'s own commit (`a3068e3`) already cleaned —
  `Sheets/CreateTaskSheet.swift`, `Views/GoalsSupportViews.swift`, `Views/HabitsSupportViews.swift`,
  `Views/QuickCreateChoiceSupportViews.swift`, `Views/TasksPanelSupportViews.swift` — so
  `theUnnamedIconButtonLedgerStatesHowManySitesEachFileStillHas` reports a stale ledger. Second, and
  less obvious, `theIconOnlyButtonDetectorSeesABareGlyphAndLeavesALabelledOneAlone`'s own
  non-vacuity witness for "the detector still reaches the desktop tree" is
  `Views/TasksPanelSupportViews.swift` — the same file T-673 just named, now clean, so the fixture
  no longer proves what its own comment claims. [[T-792]] tracks a *different* T-673 residue (the
  raw `Text` beside two glyphs); this is the ledger/witness staleness itself, filed separately so it
  does not get lost inside T-792's narrower scope.

- [T-796] **A `Menu` whose whole label is a bare `Image(systemName:)` is invisible to both the
  icon-only-`Button` sweep and [[T-674]]'s new icon-only-`.onTapGesture` sweep — neither keys on
  `Menu`.** Measured 2026-09-04: four sites, four files, have no accessible name at all —
  `Views/ListNotesViewSupportViews.swift:20`, `Editor/MarkdownEditorView.swift:432`,
  `iOS/iOSCalendarSettingsSection.swift:348`, `iOS/iOSCalendarBundleDetailSheet.swift:352`. A fifth,
  `iOS/iOSMarkdownAccessoryViews.swift:632`, already carries `.accessibilityLabel("More
  formatting")` and is clean — proof the shape is fixable the same way, not a reason the other four
  were missed. Not folded into T-674: that ticket's population was fixed at 10 sites in 9 files
  before this was found, and a `Menu` label is a third control shape after `Button` and
  `.onTapGesture`, wide enough to want its own sweep rather than a fourth ad hoc fix.

- [T-797] **`CreateContextSheet.ColorGrid`'s swatches share `IconGrid`'s exact defect one struct up
  — a bare `.onTapGesture` with no `Button`, no accessible name — and [[T-674]]'s new
  `CadenceIconOnlyTapGestureAccessibilityTests` correctly does not fire on them.** The detector
  keys on `Image(systemName:)`; a swatch draws a `Circle().fill(Color(hex:))`, no `Image` at all, so
  the two are different shapes by the letter of what the rule checks even though a sighted user
  meets them as siblings in the same sheet. Deliberately left rather than folded in: `IconGrid`'s
  fix names the icon by its SF Symbol identifier (`"Select \(icon) icon"`, matching the sibling iOS
  grids' own `.accessibilityLabel(icon)` convention); a swatch has no symbol name to borrow; it
  needs a decision on what a colour's own name is (`Theme`'s own token name, when the hex matches
  one? the raw hex string otherwise?) before it can take the same fix shape.

- [T-792] **A goal's linked-list and task-contributor rows now announce a normalised title;
  the visible `Text` beside them still reads it raw.** Found while landing [[T-673]] and
  deliberately left — fixing it would have been a copy change to a display the ticket was not
  about. `Views/GoalsSupportViews.swift`'s `GoalLinkedListRow` draws `Text(link.title)` and
  `GoalTaskContributorRow` draws `Text(task.title)`; both rows' detach buttons now read
  `.accessibilityValue(…)` through `CadenceTitleNormalization.display` /
  `TaskTitleSupport.displayTitle` with a real fallback, so an area, project or task with a blank
  *name* (not `nil` — `GoalListLink.title` only falls back to `"Missing List"` when both
  relationships are unset, per [[T-751]]) now announces "Untitled Area" / "Untitled Project" /
  "Untitled Task" while the row beside it draws an empty line. Same family as the other
  untitled-row tickets ([[T-505]], [[T-513]], [[T-687]]); the fix is routing both `Text`s through
  the same call the accessibility value already makes.

- [T-771] **Two words for one bucket, and a third that means something else.** The catch-all over
  "lists no offered context owns" is called **"Other"** by `CadenceSidebarLists.ungroupedTitle` —
  read by the macOS sidebar, the iPad sidebar and `ContainerPickerFilterSupport.groups` — and
  **"No Context"** by the two goal-attach surfaces (`CreateGoalSheet`'s initial-linked-list picker
  and `GoalLinkCandidateGroup.title`, which is both platforms' goal sheet). Same rows, same rule,
  two words. Separately, the macOS context picker's own none-row says **"No context"**, which is a
  *different* idea — an unset field on the thing being edited, not a bucket of leftovers — and must
  stay distinct whichever way the first two go. Converging "Other" and "No Context" is a
  user-visible copy change, so it needs a decision rather than a refactor; both current values are
  pinned by `CadenceContextlessListSurfaceTests` so whichever way it goes has to be written down.
  Filed by [[T-683]], which did the mechanical half and left this.

- [T-768] **The two macOS event deletes still report through the global alert, and the reason is
  reasoned rather than measured.** Residue of [[T-658]], which moved Save and quick-create to an
  inline notice on the popover holding the draft and deliberately left Delete where it was.
  The argument for leaving it: both deletes leave through `DeleteConfirmationManager`, whose
  `DeleteConfirmationOverlay` (`macOSRootSupportViews.swift:614`) covers the whole window, so
  pressing its Delete button is a click outside a transient `NSPopover` and closes the editor before
  EventKit answers — an inline notice would have nothing to draw on, and suppressing the alert for
  it would turn a reported failure into a silent one. There is also no draft to lose: nothing was
  typed.
  **Two things are worth doing.** (1) `presentRefusable(…)` already exists for exactly this shape
  (T-376: the overlay stays open and says the delete was refused), and it is the surface that asked
  the question, so it beats a global alert — but it takes a fixed `failureNotice: String` and an
  `attempt: () -> Bool`, so it cannot carry `CalendarWriteFailure.message`. Widening it to a typed
  refusal is the work. (2) **Measure the premise.** "The overlay closes the popover" is AppKit
  reasoning about `NSPopover.behavior == .transient`, not an observation: `run-macos-app.sh` refuses
  while the user's own Cadence is running, which it was for the whole of that batch. If the popover
  in fact survives, `deleteOutcome(for:)` is a three-line addition and Delete joins Save.

- [T-759] **Two `SchedulingActions.createTask` overloads no longer have an app caller.** Found while
  landing [[T-655]] and deliberately left. `createTask(title:dateKey:startMin:endMin:in:)` had none
  before that ticket; `createTask(title:…containerSelection:…in:)` lost its last one when
  `CalDayColumn` moved to `insertTask`. Both are still reached from `TaskBundleTests`
  (`noSchedulingEntryPointEverGivesATaskACalendarEventID` enumerates them as "scheduling entry
  points"), so deleting them means deciding what that test is enumerating now — entry points the app
  has, or entry points that exist. They are also what keeps the *name* `createTask` pending on
  `SchedulingActions` in the commit index, which costs nothing today and would matter to the next
  caller. The decision is delete-and-retitle-the-test, or keep-and-say-why in a doc comment; the
  wrong answer is leaving two production functions with no production caller and no note.

- [T-760] **The shared "two tasks become a block" mutation commits through a swallowed save, and
  iOS still relies on it.** Found while landing [[T-655]].
  `CadenceTaskMutationSupport.addTask(_:to:modelContext:)` ends `try? modelContext.save()`, and
  `insertBundle(from:adding:modelContext:)` calls it twice after `modelContext.insert(bundle)`. So
  the block is committed by a save nobody can hear refuse — which is also why half 3 never reported
  the three `formBundle` callers: the name *does* reach a commit, just not one that answers.
  T-655 gave macOS's `TimelineDayCanvas` a committing wrapper on top
  (`SchedulingActions.insertBundle(from:adding:in:commit:)`), so a refusal there is un-inserted,
  restored and named. **iOS is not fixed**: `iOSCalendarTimelineViews.formBundle` and
  `iOSCalendarBoardView.formBundle` still call the shared mutation directly and report nothing, so
  the same drag has two behaviours on two platforms — the parity gap [[T-190]] exists to prevent.
  The fix is the swallow itself: give `insertBundle(from:adding:)` a `commit:` and let `addTask`
  stop saving on its own behalf, then let the three canvases share one answer. That makes
  `arefusedDropOfATaskOnATaskLeavesNoBlockAndBothTasksWhereTheyWere` able to read the *store* rather
  than the context, and turns `theSharedTwoTaskBlockMutationCommitsThroughAswallowedSaveOfItsOwn`
  red — which is the signal to come back and strengthen it.

- [T-761] **The [[T-656]] class's remaining members, in components and files that batch could not
  reach.** Counted while landing T-656/[[T-727]] and named rather than left implicit.
  (a) **`iOSTaskDetailSheet`'s time picker.** `scheduledStartSelection`'s setter reaches
  `CadenceTaskDateEditing.setScheduledTime` → `CadenceTaskMutationSupport.setScheduledTime`, which
  ends `try? modelContext.save()`, and `iOSTaskDetailSheetSections` closes the popover on the tap.
  Exactly T-656's shape; the setter lives in a file another agent owned that batch, so it was
  reported rather than edited. The committing form it needs already exists.
  (b) **`iOSTaskRowEstimateChip`.** The same shape on a *different* component:
  `EstimatePickerPopoverContent`'s value binding forwards to
  `CadenceTaskMutationSupport.setEstimatedMinutes`, which swallows, and the popover's own closure
  sets `showPicker = false` unconditionally. That component was outside T-656's census and should
  get the same two-form treatment rather than a third spelling.
  (c) **The row context menu's repeat submenu** discards `iOSTaskRecurrenceSelection.select`'s new
  answer. It no longer leaves the rule *pending* — the commit and its undo are real now — but a
  refused rule is still silent there, and a `Menu` has the same no-surface problem
  `iOSTaskMoveFailureAlertModifier` solves for the list move. The same alert would do it.

- [T-741] **A legacy list note whose body still reads `# Untitled` is re-titled `Untitled` on its
  next content commit, and cleared again on the next launch.** Found while closing [[T-733]] and
  deliberately left. `MarkdownNoteTitleSync` writes the first line of the body to `title` for `.list`
  and `.permanent` notes, so a row created before T-733 — whose body genuinely says `# Untitled`,
  because that is what the old seed wrote — gets the word back the first time its body is committed.
  `DataIntegrityRepairService.repairStoredDefaultNoteTitles` then clears it on the following launch.
  **Nothing is damaged and nothing loops without a user in it**: the H1 rule is working as designed
  (the body really does say `Untitled`), the pass is idempotent, and each cycle needs a fresh content
  commit. What it costs is one extra store write per launch for those rows, and a title that flickers
  back to the stored word between an edit and a relaunch.
  Three ways out, and the choice is a judgement about the user's own text: (a) leave it — the body is
  the user's document and the title is only following it; (b) have the load-time pass also rewrite a
  body whose *entire* first line is `# Untitled` to `# `, which edits `content` and is a much bigger
  claim than editing `title`; (c) teach `MarkdownNoteTitleSync` to treat an H1 equal to the retired
  default as "say nothing", which is a special case in the one place the repo has been careful to
  keep general. Not obvious; wants a decision, not an edit.

- [T-740] **`Document.title` still defaults to the stored word `"Untitled"`** —
  `Cadence/Models/Document.swift:7` and `:16`, the same shape [[T-733]] removed from `Note`.
  Not user-visible today and that is why it was left: `Document` is a **legacy migration source
  only** (`Cadence/Models/AGENTS.md`, "Notes: One Live Model, Five Legacy Ones"), `Area.documents`
  and `Project.documents` survive as relationship declarations for cascade deletes, and no UI builds
  on it. So there is no field for the word to sit in front of.
  It is worth a decision rather than a silent leave for two reasons. It is now the **only** stored
  `"Untitled"` default in the app, so the shape T-733 removed is one file from coming back by
  imitation; and `CadenceSharedConstantReuseSweepTests.everyPlaceholderLabelInTheAppIsDeclaredOrRecorded`
  names `Document.swift` as one of its two witnesses, so anyone reading that test finds a live
  example of the pattern being pointed at approvingly. Changing it is **not** free: removing a stored
  property's default has no migration behind it, and the rows are exactly the pre-merge ones the
  migration reads. Either change it with the same load-time pass T-733 used, or write down here why
  a legacy source keeps it.

- [T-739] **`#expect(x == 0.5 * 1.6)` fails where `#expect(x == retired * 1.6)` passes, for the same
  numbers.** Measured 2026-09-03 while writing [[T-496]]'s suite, in `CadenceTests` on macOS:
  `#expect(adopted == 0.5 * 1.6)` recorded *"Expectation failed: (adopted → 0.8) == (0.5 * 1.6 →
  0.8)"* — both sides printing `0.8` — while `#expect(adopted == 0.4 * 2)` and `#expect(adopted ==
  0.8)` in the same test body passed. Binding the retired value to a `let` first
  (`let retiredWeekday: CGFloat = 0.5; #expect(adopted == retiredWeekday * 1.6)`) passes, and that is
  the spelling the pre-decision suite had been green on for weeks.
  **A standalone `swiftc -Onone` binary disagrees with the test target**: reproducing the same
  declarations (`static let kerningRatio: CGFloat = 0.08`, a `Size` enum, `ratio * size`) and printing
  `bitPattern` gives **one identical bit pattern** for `ratio * size`, `0.5 * 1.6`, `0.4 * 2` and
  `0.8`. So the difference is something about how the `#expect` macro evaluates a
  literal-times-literal operand, not about `Double`.
  Not diagnosed, and deliberately not guessed at in the test's doc comment. It matters beyond
  typography: every suite here that checks arithmetic with an inline `a * b` of two float literals is
  resting on this, and the failure mode is a red run that looks like a real regression in whatever
  the numbers are about. Cheapest next step is a two-test fixture in `CadenceTests` that pins both
  spellings and their `bitPattern`s, which turns this from a story into a measurement.


- [T-718] **The unqualified half of [[T-565]] is measured and guarded by nothing.**
  A backticked span shaped like a call — `` `foo(_:)` ``, `` `bar()` `` — with no type in front of it
  is invisible to the qualified rule, and that is the spelling [[T-647]]'s defect actually used:
  `insertSubtask` and `deleteSubtask`, named in a comment about a file that has neither, both
  declared elsewhere in the tree. **Measured: 24 distinct call-shaped spans whose base name is
  declared nowhere at all** — `regularInspectorWidth(for:)`, `kanbanColumnHeaderPadding()`,
  `readSelection(from:)`, `taskDropHandler(scopeTasks:dropKey:)`, `splits(width:sides:)` and twenty
  more. Roughly half are AppKit/UIKit/SwiftUI symbols a comment is entitled to mention
  (`reloadInputViews()`, `validateMenuItem(_:)`, `unregisterForRemoteNotifications()`), which is why
  this did not land with the qualified rule: the exclusion it needs is a framework allowlist, and an
  allowlist of SDK names is a thing that rots.
  T-647's *own* spelling — a name absent from the file the sentence is about but present elsewhere —
  is a harder third rule and needs "the scope the sentence implies", which no arithmetic here can
  read. Do the repo-wide-absence half first and say plainly that it is the weaker half.
  **DECLINED for this batch, 2026-09-04 — the repo-wide-absence half was attempted and the allowlist
  problem is worse than the ticket's own estimate.** Two independent replications of "declared
  anywhere in the tree, as any of func/var/let/case/typealias/struct/class/enum/actor" over the same
  five source roots landed on **54** distinct offending base names, not 24 — a first pass keying only
  on `func` declarations (ignoring closure-typed `var`/`let` properties invoked as calls, e.g.
  `onSave()`, `onDone()`) found **139**. The count moved by more than 5x between two reasonable
  readings of "declared", before an SDK allowlist even enters it — `rollback` alone (a real
  `ModelContext` method, called at 24 sites) would need its own exclusion on top of the AppKit/UIKit
  list T-718 already named. That is a second allowlist, of stdlib/framework member names this repo
  calls constantly, layered on the first. Landing a guard on numbers this unstable would be asserting
  a floor over arithmetic that has not settled, which is exactly what this repo's own rule against a
  numeric floor over a shrinking population is about. Left open rather than closed: the underlying
  gap is real and the measurement above is evidence for the next attempt, not a dead end.

- [T-765] **Two callers still write out an undo `CadenceTaskFieldSnapshot` can now do for them.**
  [[T-701]] put `title` and `order` in the snapshot, which was the entire reason
  `CadenceNoteTaskEmbedEditing.rename` and `CadenceTaskMutationSupport.moveToContainer` each restore
  their fields by hand — the doc comment on each said so, and both now say it in the past tense. The
  near-copies are what T-701 was about, so the ticket is not finished while they stand; it was split
  because folding them in is a behaviour change and a file move, not a field addition.
  `rename` needs `CadenceNoteTaskEmbedEditing` marked `@MainActor` (the shared unit is, and four
  SwiftUI callers would inherit it) and gains a wind-down reconcile on its failure path that it does
  not do today. `moveToContainer` lives in a file another agent owned during the T-701 batch, and its
  undo also restores nothing outside the sixteen, so it is a straight substitution — do that one
  first. `toggleSubtask` stays hand-written either way: `Subtask.isDone` is not a field of `AppTask`
  and the snapshot is not about it.


- [T-780] **Nothing makes an agent *use* `scripts/agent-commit.sh`.** [[T-679]] is fixed in the sense
  that the incantation is now a script that refuses the four measured failures — but the instruction
  to call it is prose in `AGENTS.md` and `docs/SUBAGENT_RUNBOOK.md`, which is exactly the shape T-679
  was filed about (`git add <specific paths>` was also prose, was also followed, and was also
  insufficient). A bare `git commit` still works and still sweeps a sibling's staged hunk. Candidate:
  a repo-checked-in `core.hooksPath` with a `pre-commit` that refuses a commit staging paths the
  caller did not declare, with an escape hatch for the user's own commits. Not done here because a
  hook changes the user's git configuration, which is their call, not an agent's.

- [T-781] **A declined hunk that is never re-committed is still caught by nothing automatic.**
  `agent-commit.sh` records what a `path=<content-file>` reconstruction declined and refuses the
  *next* commit of that path unless it carries them (`DECLINED-HUNK-LOST`) — the Batch M failure
  where m3 correctly declined m4's work, m4 committed without it, and HEAD stopped compiling. But if
  nobody commits that path again, no commit-time check ever fires. The backstop is
  `./scripts/agent-commit.sh status`, and reading it is a habit, not a mechanism. Candidate: have
  `scripts/xcb.sh` print outstanding records at the end of every run, so the listing lands in front
  of whoever is already looking at a build log.

- [T-782] **An App-Sandboxed test host cannot run the `/usr/bin` developer shims, and nothing says
  so.** Measured 2026-09-03 while wiring [[T-719]]: `Cadence.app` is sandboxed, so a `Process` spawned
  from `CadenceTests` inherits the sandbox, and there `/usr/bin/git` and `/usr/bin/python3` — both
  xcrun shims — fail with *"xcrun: error: cannot be used within an App Sandbox"*, exit 1, nothing on
  stdout. Separately, zsh writes here-document temp files to `$TMPPREFIX`, which **zsh itself sets to
  `/tmp/zsh` at startup** (so it is never empty and a `[[ -z $TMPPREFIX ]]` guard never fires); the
  sandbox denies that write and the script dies with `can't create temp file for here document`
  before its first line runs. Both are fixed inside `scripts/mutate.sh` and `scripts/agent-commit.sh`
  and both are in `docs/SUBAGENT_RUNBOOK.md`, but nothing stops the next script a test shells out to
  from repeating either. `/bin/echo` runs fine, so a naive "can I spawn at all?" probe says yes and
  proves nothing.

- [T-720] **`TaskRecurrenceRule.shortLabel` is a copy of `label` with one arm changed.**
  `Cadence/Models/ModelEnums.swift` — `label` returns Never/Daily/Weekly/Monthly/Yearly and `shortLabel`
  returns None/Daily/Weekly/Monthly/Yearly. Four of the five arms are byte-identical, so four strings are
  spelled twice in one file and only `.none` actually differs; there is nothing "short" about the second
  spelling. Found while choosing mutation needles for [[T-530]] — `return "Daily"` occurs three times in
  that file, twice of them here. Decide whether `shortLabel` earns its existence at all; if it does, it
  should derive from `label` and override the one arm rather than re-type the other four.

- [T-714] **A refused column rename still has one path with nowhere to appear.**
  Residue from [[T-645]], same family as [[T-646]]. The rename now commits at `onSubmit`, at the name
  field losing focus, and from every other control in the popover — all while the popover is up. The
  path left is: type a name, then dismiss the popover without touching anything else. The edit is not
  lost (one `ModelContext`, so the next commit anywhere takes it), but a refusal at that moment has no
  surface, which is the shape [[T-646]] was about.
  Two candidate answers, both real work: make the dismissal itself a commit that can refuse to close,
  or route the flush's notice to the column header the way [[T-646]] routes the commit ones — that
  second one is nearly free now, but `CadenceInPlaceEditFlush.failureNotice` ("They're still here")
  reads oddly on a column rather than beside the field it is about.
  **Also unverified by observation:** the focus-loss trigger is a `@FocusState` `onChange`, and
  whether clicking a colour swatch in a macOS popover actually moves focus off the `TextField` was
  reasoned, not seen. `onSubmit` covers Return regardless, and every other control commits, so the
  worst case is that this path is wider than described.


- [T-698] **The Mac's goal pickers spell `CadenceEmptyStateCopy.goalsTitle(isNarrowed:)`'s body
  inline, three times in one file.** `macOS/Views/GoalPickerViews.swift` declares
  `var emptyText: String = "No matching goals"` on both pickers (lines 13 and 89) and then draws
  `Text(searchQuery…isEmpty ? "No goals yet" : emptyText)` (line 137) — which is
  `isNarrowed ? "No matching goals" : "No goals yet"`, the shared function's body, re-typed. Found
  by [[T-555]]'s widened harvest, which is the first thing in the repo able to see it: the constant
  is spelled as a `static func`, so the sweep walked past it until now. [[T-550]] deleted this
  argument at the call sites that passed it explicitly (`CreateGoalSheet` and
  `HabitsFormSupportViews` are clean), and left the two *defaults* behind, because nothing was
  looking at defaults. The fix is to take `isNarrowed` and call the function, which also makes
  [[T-689]]'s third case land in one place rather than three. **It will turn T-550's own guard
  red, correctly**: `CadenceEmptyTitleFallbackSweepTests` asserts the picker still declares
  `var emptyText: String = "No matching goals"`, which is the line this ticket deletes — retire
  that half of the assertion in the same change rather than working around it. Ledgered in
  `cadenceStaticFuncConstantLedger`, so the sweep fails the moment the entry stops describing the
  file.

- [T-699] **"No lists yet" has three spellings and no home.** `CadenceListsSummary.eyebrow(…)`
  returns it as the fallback branch of a summary line, `iOSRootSidebar.emptyListsRow` types it as a
  bare `Text`, and `iOSGoalAttachListsSheet` types it as
  `isNarrowedToEmpty ? "No matching lists" : "No lists yet"`. The third one names the shape of the
  fix: that is `goalsTitle(isNarrowed:)` and `habitsTitle(isNarrowed:)` with the noun changed, so
  the answer is a `CadenceEmptyStateCopy.listsTitle(isNarrowed:)` beside them, read by the sheet and
  by the sidebar, with `eyebrow`'s fallback reading it too. Note the sidebar is **not** a call site
  for `eyebrow` — a row is not a summary line — which is the point: the words never had a constant
  of their own, only a function's fallback branch, and that is precisely why nothing flagged the
  second and third copies. `"No matching lists"` is declared nowhere at all and so is invisible to
  the sweep in either direction; the ticket owns both halves. Found by [[T-555]]; both live sites
  are ledgered in `cadenceStaticFuncConstantLedger`.


- [T-689] **The Goals screen says "No goals yet" when every goal is completed.** Both surfaces draw
  `CadenceEmptyStateCopy.goalsTitle(isNarrowed: false)` whenever the active count is zero, so a user
  with five finished goals and none in flight reads "No goals yet". [[T-541]] made the detail pane
  agree with the list rather than contradict it, so the two panes now say this together — the
  inaccuracy is one sentence, not a disagreement. `isNarrowed: true` ("No matching goals") is not
  the fix either: the Goals page carries no search field and no status picker, so there is no filter
  to try differently. It needs a third case for "every goal is done", which is a copy decision of
  the same shape as `activeListsSubtitle(hasArchived:)`.
  **CLOSED 2026-09-03 (`663bc13`) — re-measured first, and the premise had narrowed: macOS already
  said "No matching goals"** (`GoalStatusFilter` defaults to `.active`, and `narrowsResults` is true
  for everything but `.all`), so only `iOSFeatureViews.iOSGoalsView` still had the defect.
  `CadenceEmptyStateCopy.goalsTitle` gained `allComplete: Bool = false` (default keeps the Mac's two
  call sites untouched); the Goals empty state moved from a `static let` to a computed `var` reading
  this instance's own `goals`/`activeGoals`, and now reads the user-decided title **"All goals
  complete"** with subtitle "Nothing in flight. Add another when you're ready." exactly when `goals`
  is non-empty and `activeGoals` is not. Checked the one open question — whether macOS's `.all`
  filter shares the defect — and it does not: `.all` matches every `GoalStatus`, so a done goal
  still renders as a row under it instead of being hidden, and the empty branch is unreachable with
  goals present. 4 tests updated/added in `CadenceEmptyStateAuditTests`; 2 mutations, both killed.

- [T-690] **A paused or cancelled project reaches no Settings lifecycle section, so it cannot be
  reopened or deleted there.** `SettingsView.swift` and `iOSSettingsView.swift` both hand
  `SettingsListsSection`/`iOSListsLifecycleSettingsSection` exactly four groups —
  `filter(\.isDone)` and `filter(\.isArchived)` for areas and projects — while `ProjectStatus` has
  five cases. `.paused` and `.cancelled` projects are excluded from every active surface by
  `filter(\.isActive)` and from Settings → Lists by these four filters, leaving search as the only
  way to reach one. Found while adding [[T-557]]'s dormant-link card, which *does* list all four
  inactive states because it reads `CadenceListSearchLifecycle`. Same file, same family:
  `SettingsListManagementSections.lifecycleCard` spells `statusLabel: area.isDone ? "Completed" :
  "Archived"` inline — the exact collapse `CadenceListSearchLifecycle` was written to end, and it
  would label a cancelled project "Archived" the moment one reached the card.
  **CLOSED 2026-09-03 (`663bc13`).** `CadenceListLifecycleSectionCopy` gained `pausedProjects`
  ("Paused Projects") and `cancelledProjects` ("Cancelled Projects"), in the same
  `"<status> <plural noun>"` voice the existing six use, read off `CadenceListSearchLifecycle`. Both
  `SettingsListsSection` (macOS) and `iOSListsLifecycleSettingsSection` (iOS) gained the matching
  groups and now filter projects by `.status == .paused` / `.status == .cancelled`. The project row's
  inline `project.isDone ? "Completed" : "Archived"` collapse is gone, replaced by
  `CadenceListSearchSupport.lifecycle(of: project).statusLabel` — the mapping this ticket named as
  already existing — and `primaryLabel` moved from `isDone ? "Reopen" : "Unarchive"` to
  `isArchived ? "Unarchive" : "Reopen"` for the same reason: a done/paused/cancelled project is not
  being "unarchived". **Did not build [[T-703]]'s composer**: kept eight plain literals rather than
  a `sectionTitle(_:of:)` function, because an interpolated title (`"\(status) \(noun)"`) is
  invisible to `cadenceSharedStringConstants` by construction — exactly the protection [[T-546]]
  exists for — and a composer built from finished-string `switch` cases would only trade eight named,
  self-documenting constants for one function with the same eight branches while inviting invalid
  pairs the current per-type design can't express (there is no `.paused` `Context`, no `.cancelled`
  `Area`). Left as recorded prose in `CadenceSettingsSectionCopy.swift` and the test suite rather than
  half-building it. 2 tests updated (renamed to reflect sixteen call sites, not twelve), 1 new
  assertion added; 3 mutations, all killed.

- [T-777] **T-694's Calendar pane still owed its offer title** (see below). **CLOSED 2026-09-03
  (`663bc13`), same commit as T-690** — handed off mid-run once T-694's Notifications half landed
  and needed `SettingsListManagementSections.swift`. `CadenceCalendarSettingsCopy.accessRequiredTitle`
  ("Calendar access required") is retired; `connectOfferTitle` ("Connect Apple Calendar") takes its
  place in the not-denied branch on both `SettingsListManagementSections.calendarAccessCard` (macOS)
  and `iOSCalendarSettingsSection` (iOS), moved together in one change as
  `bothCalendarSettingsSurfacesReadEveryConvergedCalendarString` requires. `accessDeniedTitle`
  ("Calendar access denied") is untouched. New test
  `theCalendarAccessCardDrawsOneTitlePerStateOnBothSurfaces` mirrors T-694's Notifications one, with
  a regex rather than a literal `.contains` because the Mac wraps the ternary onto three lines where
  the phone keeps it on one. 2 mutations, both killed.

- [T-691] **The broken-calendar-link row draws no title for an unnamed list.**
  `CadenceCalendarLinkHealth.missingLinks` passes `area.name` / `project.name` straight into
  `CadenceMissingCalendarLink.name`, so an untitled area's row is a blank line above its summary —
  the [[T-577]] class. [[T-557]]'s `dormantLinks` passes
  `CadenceTitleNormalization.display(_:fallback:)` instead, so the two rows in the same settings
  section now differ in a way that is deliberate on one side and an oversight on the other.
  **Not a duplicate of the [[T-609]] sweep**: that one hunts the inline
  `x.isEmpty ? "Untitled" : x` ternary, and this site has no fallback at all — there is no ternary
  for a sweep of that shape to see.
  **CLOSED 2026-09-03 (`4cbd2fd`).** `missingLink` now reads
  `CadenceTitleNormalization.display(_:fallback:)` for both the area and the project name, the
  same call `dormantLinks` already made — an unnamed active list's broken-link row draws
  "Untitled Area"/"Untitled Project" instead of a blank line. Reproduced through T-624's evidence
  gate (`observedCalendarIDs` containing the dead identifier), so the failing-first test exercises
  the actual guarded path rather than a shortcut around it. Pinned by
  `CadenceCalendarLinkHealthTests.anUnnamedActiveListsBrokenLinkRowStillHasSomethingToPutOnIt`;
  2 mutations (area site, project site), 2 killed.

- [T-447] *(narrowed 2026-08-30: both landings reviewed. T-281 is a faithful but visually inert extraction — the two headers were already byte-identical before it. T-283's renames are correct and complete. Defects found and filed separately as [[T-492]] and [[T-493]]. Predicate two is effectively answered off-device already: the commit outcome is covered in `CadenceEventKitPlatformParityTests` and its position by `theEventSheetKeepsItsCommitNoticeInsideTheHeader` — only the pixel is left. Predicate one is narrowed by `nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader`: **nothing in `Cadence/` writes that environment key**, so only SwiftUI's own re-derivation inside NavigationStack -> HStack -> .frame remains device-only. That residue belongs with T-55 / T-280.)*
  *(**PREDICATE TWO SETTLED 2026-09-02, observed; PREDICATE ONE CANNOT BE POSED AS WRITTEN.**
  Two: on a note attached to a read-only subscribed event, typing produced *"This note is saved,
  but Apple Calendar didn't take the change."* in red, **under the title, inside the header block,
  above the divider** — `iOSNoteEditorSheetHeader`'s `accessory` slot, exactly where
  `theEventSheetKeepsItsCommitNoticeInsideTheHeader` puts it. A read-only subscribed calendar is
  the cheapest reproduction of a failed EventKit mirror and is worth knowing.
  One: **there was no rail to judge.** At 834pt, `iOSLinkedNoteEditorSheet`,
  `iOSEventNoteEditorSheet` **and** `iOSCalendarEventEditSheet` all drew their **compact** branch.
  The sheet measures ~577 x 639pt — a plain `.sheet` is a form sheet on iPad, and UIKit gives one
  that narrow a compact horizontal size class. So sheet and header **agreed**, which is what this
  predicate was checking — but they agreed on *compact*, and the 24pt-title / 20-20-padding /
  full-height-rail branch was never entered. See [[T-731]].)* **Nothing rendered the two iOS surfaces [[T-281]] and [[T-283]] changed.** Both landed on
  source-scan evidence plus four green scheme builds (`Cadence` macOS, `CadenceWidgets`,
  `CadenceMCPServer`, `Cadence` for `generic/platform=iOS Simulator`) — which is all
  `CadenceTests` can offer, since `Cadence/iOS/` is inside `#if os(iOS)` and the test target builds
  for macOS. No simulator ran: both booted devices were held by live agents, and
  `scripts/simulator-claim.sh` correctly refuses to reclaim one.
  Two predicates a device answers and a scan cannot. **One:** `iOSNoteEditorSheetHeader` now reads
  `@Environment(\.horizontalSizeClass)` itself instead of taking the flag from its sheet. That is
  the same trait either way *in theory* — a `.frame(width: 320)` does not change a scene trait — so
  the regular-width rail on both note sheets should still draw the 24pt title, the 20/20 padding and
  the full-height rail. If the trait does not propagate into that rail the title drops to 22pt and
  the padding to 18/14, which is visible and which no scan can see. **Two:** the event sheet's
  commit-failure notice still appears under the title, inside the header block, when a note saves
  but its Apple Calendar mirror does not.
  Cheap: one iPad-width run of each note sheet, one iPhone-width run of Today and Inbox.















- [T-168] **iOS Focus mode: widgets and a landscape timer.** Two halves.
  *(a)* A widget showing the running timer plus what is being worked on, and a second showing the
  task list — exact split is a design call, make a good one rather than shipping two widgets that
  say the same thing. Two constraints to design around, both real: **WidgetKit timelines cannot
  tick**, so a live count needs `Text(timerInterval:)` (the system animates it without waking the
  extension) or ActivityKit for a Live Activity on the lock screen and Dynamic Island — a timeline
  that reloads every second is not an option. And **`FocusManager` is `#if os(macOS)` only**
  (`macOS/Services/FocusManager.swift`); iOS focus lives in `iOSFocusView.swift` with no shared
  state object, so session state is in-memory and a widget process cannot see it. Persisting focus
  state to the app-group store is the prerequisite, not a detail. Existing widgets to match:
  `CalendarSnapshotWidget`, `HabitCheckInWidget`, `MilestoneMomentumWidget`, `TodayTasksWidget`.
  *(b)* iPhone **landscape** layout for the running timer and its tasks. The compact shell
  (`iOSCompactTabShell`) is built around a portrait tab bar; landscape focus wants the timer large
  and the chrome gone, which is a different shape rather than the same one rotated.






- [T-122] *(rechecked 2026-08-30 at `a1556ae`: **do not flip, and the reason is now measured on both platforms.** macOS Swift 6 builds but costs **10 warnings** in 6 files against a zero-warning baseline — a flip that produces warnings is not done, so macOS fails on its own merits even setting iOS aside. **Step (1) is now solved**: the one blocking error was an erased `KeyPath` table, fixed with `& Sendable` — one word, **no `nonisolated(unsafe)`** — verified on macOS Swift 6, iOS Swift 5, macOS Swift 5 and the export suite, and it is the only `static let ... KeyPath<` in the app, so that is complete rather than a sample. Landed; inert under Swift 5. Steps (2)-(4) untouched.)* **Flip `SWIFT_VERSION` to 6.0 — now an open question rather than a blocked one.** `D-95`
  *(measured 2026-08-31, timeboxed probe in an isolated `git archive HEAD` tree; nothing landed.
  **This ticket's "611 -> 0" no longer holds: it is 775 -> 6.** The suite grew. Naive flip of
  `CadenceTests` to 6.0 = 775 strict errors / 0 crashes, all one root cause — a nonisolated `@Test`
  calling app API that is MainActor by default (472 static-method calls, 119 properties, 68 static
  properties, 49 in `#expect` autoclosures, 27 key paths, the rest instance/init/default-value).
  Adding `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to `CadenceTests` collapses that to **6 errors +
  1 warning in 3 files**: `TemporaryDefaultsSupport.swift` (4, the `CadenceSourceScan` helpers),
  `CalendarDateMemoryTests.swift` (2, a `UserDefaults` subclass whose overrides now differ in
  isolation from what they override), `MarkdownTableHostedEditingTests.swift` (1 warning).
  **`CadenceWidgets` is free today: 0 errors, 0 warnings.** The **app target is still a don't** — it
  builds clean (0 errors) but throws **10 warnings** against a zero-warning baseline, each a real
  design question about where a callback runs: 3 x `TimelineDropInteractionSupport.swift`,
  3 x `QuickTaskPanelController.swift`, and one each in `CalendarManager.swift`,
  `CadenceMCPRefreshCoordinator.swift`, `CalendarBoardDayColumnSupportViews.swift`,
  `CadenceRemindersManager.swift`. Estimate: widgets free, tests an afternoon, app 2-3 days.
  Caveat recorded rather than hidden: the tests probe was a **compile** measurement only. No scoped
  test run was done, and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every `@Test` main-actor,
  which is a behavioural change to the suite. Budget a full `CadenceTests` run before believing it.
  Step (1) is confirmed landed: `CadenceDataExportService.swift:228` is now
  `[String: any KeyPath<CadenceArchive, Int> & Sendable]`.)*
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  cleared the last macOS error, so nothing in the app's source blocks it. What remains: 10
  Swift-6-mode *warnings* elsewhere in the app (byte-identical before and after T-105, none in
  editor files), and on iOS the toolchain bug in [T-115] — swift-frontend crashes in IRGen once the
  diagnostics are gone, which is not app code. So macOS could plausibly flip first; iOS cannot until
  the toolchain moves. `CadenceMCPServer` has been on 6.0 all along.

  **MEASURED 2026-08-26 against `36be8ba` and re-confirmed on `ea77271`, Xcode 26.6 / Swift 6.3.3.
  Recommendation: do not flip anything yet — flip nothing before the two items in "what a flip
  needs" below are done, and never flip iOS while [T-115] stands.** Every number below is one
  `xcodebuild` run into a private `-derivedDataPath` over an `rsync`-isolated tree, exit status read
  on the xcodebuild line, diagnostics counted from the log with **no path filter** and attributed to
  a target by the `(in target 'X' from project 'Cadence')` line above them.

  | Target | Swift 5 today | Swift 6 (`SWIFT_VERSION=6.0` override) |
  |---|---|---|
  | `Cadence` (macOS) | 0 errors, 0 warnings | **0 errors, 10 warnings** |
  | `Cadence` (iOS Simulator) | 0 errors, 0 warnings | 0 errors, 1 warning — **but swift-frontend crashes, no build** ([T-115]) |
  | `CadenceWidgets` | 0 errors, 0 warnings | **0 errors, 0 warnings** |
  | `CadenceMCPServer` | already 6.0: 0 errors, 0 warnings | already 6.0 |
  | `CadenceTests` | 0 errors, 0 warnings | **611 errors** |
  | `CadenceUITests` | 0 errors, 0 warnings | 0 errors, 5 warnings |

  Notes on how those were obtained, because two of them are not what a single run reports.
  - A Swift 6 build of the app **stops at `EmitSwiftModule` on two errors in one file** —
    `Cadence/Services/CadenceDataExportService.swift:228`, `nonisolated static let
    recordCountsByEntityName: [String: KeyPath<CadenceArchive, Int>]`, because `KeyPath` is not
    `Sendable`. That file postdates `D-95`, so **the app's Swift-6 error count is not a fixed
    quantity that T-105 drove to zero — it regressed to 2 the moment ordinary new code was written
    under Swift 5.** Nothing else in the app module errors: with that one declaration changed to
    `nonisolated(unsafe)` **in the scratch copy only**, the whole macOS app module compiles.
  - The per-target error counts were then taken with `SWIFT_COMPILATION_MODE=wholemodule`, because
    the default batch mode surfaces **one failing batch at a time** — the first Swift 6 run of
    `CadenceTests` reported 18 errors in one file and stopped, and the module actually holds 611.
    Any future count of this debt must be taken whole-module or it is a lower bound.
  - The 10 macOS app warnings are the same 10 this ticket has always claimed, and they are in five
    files: `Services/CadenceRemindersManager.swift` (1 — the only cross-platform one, and the iOS
    build's single warning), `macOS/Views/TimelineDropInteractionSupport.swift` (3),
    `macOS/Services/QuickTaskPanelController.swift` (3), `macOS/Services/CalendarManager.swift` (1),
    `macOS/Services/CadenceMCPRefreshCoordinator.swift` (1),
    `macOS/Views/CalendarBoardDayColumnSupportViews.swift` (1). All are ordinary main-actor
    isolation, none is in `macOS/Editor/`.

  **`CadenceTests`' 611 errors are one build setting, not 611 problems.** The app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `CadenceTests` and `CadenceUITests` do not. So under
  Swift 6 every `@Test` function is nonisolated by default and every call into the app's
  main-actor-by-default API is an error — 365 of the 611 are literally "call to main actor-isolated
  static method 'X' in a synchronous nonisolated context". Adding
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to the test target takes `CadenceTests` from **611
  errors to 0**, measured. It also takes `CadenceUITests` from 0 to **11**, all of the form
  "main actor-isolated instance method 'setUpWithError()' has different actor isolation from
  nonisolated overridden declaration" — `XCTestCase` overrides, a handful of `nonisolated` keywords.
  That asymmetry is the whole shape of the problem: the two test targets want opposite defaults.

  **What a flip needs, in order.** (1) Fix `CadenceDataExportService`'s key-path table — and note
  `nonisolated(unsafe)` was only a probe, not a proposal. (2) Clear the 10 app warnings; they are
  real isolation questions in scheduling, panel and EventKit callbacks, not cosmetics, and the
  zero-warning baseline is worth more than the language mode. (3) Set the test targets' actor
  isolation deliberately and re-measure — and consider that making every `@Test` main-actor is a
  behavioural change to the suite, not just a compile fix. (4) iOS stays on 5.0 until [T-115]'s
  compiler crash clears, whatever macOS does.

  **A partial flip is available and is the recommendation *when* the above is done, not now.**
  `SWIFT_VERSION` is per-target, `CadenceMCPServer` has been 6.0 beside 5.0 targets all along
  without splitting anything, and `CadenceWidgets` compiles under Swift 6 today with 0 errors and 0
  warnings. So "two dialects" is already the status quo and costs nothing new. What a macOS-only
  flip *would* split is the app target itself — one module built two ways per platform — which is
  the one combination worth refusing: `Cadence/Shared/` and `Cadence/Services/` compile into both,
  so an isolation fix accepted by the macOS flip would still have to satisfy the iOS Swift 5 build,
  and a regression introduced on the iOS side would be invisible until [T-115] cleared. Flip
  `CadenceWidgets` and (after step 3) `CadenceTests` if a partial flip is wanted early; leave the
  app target alone until both platforms can move together.



  **Re-checked 2026-08-24 under 14 concurrently-building agents: not reproduced, and the tell is now
  in `AGENTS.md`.** Live `ps` found no bare `xcodebuild` pinned at 0% CPU; every process that looked
  stalled at a glance was a `test-host-lock.sh acquire` wait (T-236's mutex, working as designed —
  `sleep 10` in a loop, not a hang) or a polling wrapper shell around one. The user's Xcode was not
  running at all, so one of the two confirmed claimants from the original report was simply absent
  tonight — consistent with the mitigation ("quit Xcode when a batch of agents is running") rather
  than with the mechanism having gone away. Two processes stranded the same night — an `xcodebuild
  test` at 3h14m against a suite that normally runs ~15 minutes, and a runner script at 4h30m — were
  both killed before anyone captured a `sample`, so neither can be attributed to this ticket by
  evidence; that would be a third confirmation resting on inference, which is exactly the shape T-119
  warns against. The runner script fits `58e20a4` ("agents stall by launching a background job and
  returning," the same night, four other agents confirmed) far better than it fits a project-file
  deadlock: a wrapper script outliving the agent that launched it, with no one left to read its
  `DONE` file, is that failure's signature, not this one's. Downgrading the open half of this ticket
  accordingly: the mechanism from the original two `sample` captures stands and the mitigation stays,
  but there is nothing further to *fix* here — this is a recognition guide, not open work. See
  `AGENTS.md`'s new bullet (after the T-236 test-host mutex entry) for the exact tell command.

- [T-115] *(re-confirmed 2026-08-30 at `a1556ae`: **still blocked, and the toolchain never moved** — Xcode 26.6/17F113, the same build the original measurement used, so there was nothing new to test against. The frontend abort reproduces in **both** compilation modes with a byte-identical stack. **Two conflicting reports from this session are now explained and neither was flaky**: the "IRGen abort in `iOSTaskRowActionViews.swift`" was a **mis-attribution** — that file never appears on an `IRGenRequest` or `While emitting` line and is not even a `-primary-file` of the crashing invocation; the crashing file is `iOSCalendarView.swift`. And the "clean, no abort" run was a **Swift 5** build, so it never tested this condition.)* **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  *(re-measured 2026-08-31: **premise still reproduces, byte-for-byte. Not disproved.** Toolchain
  unchanged at Xcode 26.6 / 17F113, so there was nothing new to test against. iOS Simulator build with
  the app at `SWIFT_VERSION=6.0` + `SWIFT_COMPILATION_MODE=wholemodule`: **0 errors, 0 warnings,
  2 `please submit a bug report` crashes**, BUILD FAILED, exit 65. Crash signature matches the ticket:
  `IRGenSILFunction::visitFullApplySite` -> `SyncCallEmission::setArgs` -> `SmallVectorBase::grow_pod`
  -> `report_at_maximum_capacity`, while emitting the `String` `@isolated(any)` reabstraction thunk
  `@$sSSScA_pSgIeAghgg_SSIeAghn_TR` — exactly the thunk this ticket predicted for whole-module mode.
  Nothing to fix in Cadence; recheck on the next Xcode bump. **Textbook case of the strict-error trap:
  the error count on that build is 0 and it is a total failure.**)*
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

  **STILL REAL — reproduced 2026-08-26 on the installed toolchain (Xcode 26.6, Apple Swift version
  6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)), twice, in two compilation modes.** This was worth
  re-testing rather than inheriting: the toolchain had not moved, and it has not. Recipe:
  `-scheme Cadence -destination 'generic/platform=iOS Simulator' SWIFT_VERSION=6.0 build` over an
  isolated tree, with `CadenceDataExportService`'s key-path table made `nonisolated(unsafe)` in the
  scratch copy so the module gets past `EmitSwiftModule` (see [T-122]). The iOS module is then
  **diagnostically clean — 0 errors, 1 warning** — and swift-frontend aborts anyway:

  ```
  4.	While evaluating request IRGenRequest(IR Generation for file ".../Cadence/iOS/iOSCalendarView.swift")
  5.	While emitting IR SIL function "@$s7Cadence0A19CalendarMonthDetailOScA_pSgIeAghyg_ACIeAghn_TR".
  ```

  which `swift-demangle` reads as `reabstraction thunk helper from @escaping @isolated(any)
  @callee_guaranteed @Sendable (@unowned Cadence.CadenceCalendarMonthDetail, @guaranteed
  Swift.Actor?) -> () to @escaping @isolated(any) @callee_guaranteed @Sendable (@in_guaranteed
  Cadence.CadenceCalendarMonthDetail) -> ()` — the `(any Actor)?` reabstraction thunk this ticket
  named. Two details the earlier write-up did not have:

  - **It is not one unlucky type.** Under `SWIFT_COMPILATION_MODE=wholemodule` the same abort fires
    on a *different* thunk, `@$sSSScA_pSgIeAghgg_SSIeAghn_TR` (the `String` one). Whatever is wrong
    is general to `@isolated(any)` thunk emission for this module, not to `CadenceCalendarMonthDetail`,
    so "find the one call site and rephrase it" is unlikely to be a workaround.
  - **The stack names the failure**, and it is an assertion, not a segfault:
    `IRGenSILFunction::visitFullApplySite` → `SyncCallEmission::setArgs` →
    `llvm::SmallVectorBase<unsigned int>::grow_pod` → `report_at_maximum_capacity` →
    `llvm::report_fatal_error` → `abort`. An LLVM `SmallVector` exceeding its maximum capacity while
    setting call arguments. Worth quoting verbatim in any bug report filed against the toolchain.

  Control confirmed in the same session: the identical tree on Swift 5 builds the iOS target to
  `** BUILD SUCCEEDED **`, exit 0, 0 errors, 0 warnings — so this is the language mode, not the
  sources. macOS emits IR for the same shared modules with no trouble, so it is iOS-only.
  Recheck on the next toolchain bump; there is nothing to fix in Cadence.


  **Mitigation shipped 2026-08-18** — the rule is standing in `AGENTS.md`. Left open because the
  underlying contention still exists and this keeps producing *new* disguises: the same day it
  reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt `SourcePackages`,
  which read as a broken package checkout and briefly made a correct agent report look wrong. The
  standing rule now says an unexplained build failure is a private-path re-run before it is a
  finding. Close this only if the contention itself is removed.

- [T-55] *(rewritten 2026-08-30 as `docs/device-checks.md`, 5 items, ~5 minutes. **Two of the three original items were materially stale**: the drag-to-create item claimed no simulator API can lift a `UIDragInteraction`, which was already wrong when written and is now moot since neither `+` uses system drag; and the double-tap item told you to double-tap a table expecting source, when since [[T-221]] a table is not revealable that way — so following the old checklist would report a pass as a failure. Now includes the [[T-447]] size-class residue with a **binary tell** rather than a pixel judgement: if the class fails to propagate, the rail's `Theme.surface` stops under the title instead of filling the sheet.)* **Three things need a real phone, not a simulator** — written up as a checklist in
  `docs/device-checks.md` (keyboard dismissal, double-tap, and drag-to-create per [T-89]).
  Original note:
  1. **Can a phone still dismiss the keyboard in the Notes tab?** The Done bar was the dedicated
     affordance and it is gone. `keyboardDismissMode = .interactive` remains, so dragging the note
     down should carry the keyboard off — Apple Notes behaves this way — but it was never seen to
     happen: both simulators suppress the software keyboard while the Mac's hardware keyboard is
     attached, and that toggle lives in Simulator.app, which is off limits. The Notes tab is the
     exposed case because it hides its navigation bar; every sheet-hosted editor has its own
     Done/Cancel above the keyboard. If it sticks, the answer is a nav-bar Done or tap-outside, not
     the bar returning.
  2. **Double tap on plain text, and on a code block or table.** The `shouldBegin` gate makes the
     prose case true by construction, but neither case was observed: the simulator tooling has no
     double-tap action and two scripted taps fall outside UIKit's ~350ms window.

- [T-16] **Redesign the logo.** Currently the app mark in the sidebar header and the app icon.
- [T-17] **Expand the target device list.** Directly reverses [T-08]; anything deleted as
  "unnecessary for the three targets" would need reinstating, so [T-08] should be done in a way that
  is easy to read back out of git history. Backlogged.

  **Axis decided 2026-08-24, still backlogged.** The user's answer: *more iPhone and iPad sizes* —
  not a lower OS floor and not a new platform family. Both of those are explicitly out of scope, so
  do not touch `IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` or add a
  `TARGETED_DEVICE_FAMILY` entry on the strength of this ticket. **The user will name the exact
  devices and OS versions when they want this done — do not start it before then.**
  Investigated 2026-08-24 without changes. `TARGETED_DEVICE_FAMILY = "1,2"` on every target already,
  so any iPhone or iPad can install today; nothing at the build level blocks it and **no
  `project.pbxproj` edit is needed for this axis**. T-08 removed no device-specific code — it deleted
  width clamps unreachable at the three targeted sizes (`inspectorMaxWidth` 430, two 540 inspector
  caps, a 760 task cap) and replaced them with proportion-pinning tests, so there is nothing to
  reinstate. The whole cost is layout auditing: the current breakpoints (Goals' inspector gate at
  901, Today's 761/841/900/928 bands, the Calendar Board's rails, the Settings templates card) were
  tuned and tested against three screen profiles only. D-155, b1239e0 and 8b73c78 each found a real
  defect at a width nobody had measured, so expect more of that shape rather than a settings flip.

- [T-18] **Chinese localisation.** Backlogged. Nothing is localised today: user-facing strings are
  hardcoded English at the call site, and `DateFormatters` uses fixed formats. Two known hazards
  already documented in this repo — `Calendar.current` is not Gregorian everywhere (a `yyyy-MM-dd`
  storage key becomes `2569-…` under a Buddhist calendar), and weekday symbol arrays are indexed by
  weekday number rather than by `firstWeekday`. Both bit us before; both get worse with a second
  locale.
  **Scoped 2026-08-24; no code changed.** Measured with
  `python3 count_strings.py` (comment-stripped regex over `Text(`/`Label(`/`Button(` &c., the
  `.navigationTitle`/`.help`/`.accessibilityLabel` modifiers, `return "…"` display copy, and
  labelled `title:`/`message:`/`subtitle:` arguments): **~2,000 hard-coded call sites, ~1,233 unique
  strings, ~4,660 English words** across `macOS` (848) / `iOS` (707) / `Shared` (271) /
  `Services` (188) / `Models` (68). Infrastructure is **zero** — no `.strings`, `.xcstrings` or
  `.lproj` anywhere, `knownRegions = (en, Base)`, zero `NSLocalizedString` / `String(localized:)` /
  `LocalizedStringKey`. 250 of the unique strings carry `\(…)` interpolation, and 57 do English
  pluralisation inline as `\(n == 1 ? "" : "s")` — those are the restructuring cost, not the
  translation cost. `CadenceTests` holds **342** `== "Capitalised copy"` assertions that pin English
  literals; they are the loudest thing a translation breaks.
  **Storage boundary (do not cross):** `DateFormatters.ymd`, every `dateKey`, `weekKey`, and
  `TaskSectionDefaults.defaultName = "Default"` are storage. The last one is the sharp edge — it is
  the default value of the persisted `AppTask.sectionName` *and* the subject of
  `TaskSectionConfig.isDefault`'s `caseInsensitiveCompare`, so it is a display string that is also a
  comparison key. Translating it silently orphans every existing task's column.
  Two latent defects found while scoping, both **already wrong today** and neither Chinese-specific:
  - `DateFormatters.longDate` / `shortDate` / `fullShortDate` / `dayOfWeek` / `monthAbbrev` are the
    only fixed-format formatters in the file that are **not** locale-pinned, while `monthYear`'s doc
    comment states pinning as the repo's rule. Verified against Foundation: on a `zh_Hans_CN` device
    `"EEEE, MMMM d"` already renders `星期一, 八月 24` and `"EEE"` renders `周一` — half-translated
    output beside English chrome, which is the exact outcome `monthYear` was pinned to prevent.
  - `MonthCalendarPanel` (`Shared/Components/CadenceDatePicker.swift`) hardcodes
    `["Su","Mo","Tu","We","Th","Fr","Sa"]` and derives its leading blanks from
    `component(.weekday,…) - 1`, i.e. Sunday-first unconditionally — it ignores `firstWeekday`. Its
    sibling `CadenceScheduleSupport.weekdaySymbols` rotates by `firstWeekday` over
    `calendar.shortWeekdaySymbols`, and its doc comment records that exact skew shipping in Germany
    and Saudi Arabia. So the two shared month grids already disagree in Monday-first regions, and on
    a Chinese device the iOS grid reads `周日 周一…` while the macOS picker reads `Su Mo…`.
  Not a hazard after all: the `Calendar.current`-is-not-Gregorian storage risk this ticket names is
  contained — `%04d-%02d-%02d` key derivation exists in exactly two files and both route through
  `DateFormatters.storageCalendar`, and `zh_Hans_CN` is Gregorian and Sunday-first anyway.
  Also out of scope by decision: `CadenceMCPServer` / `Services/MCPReadOnly` strings are a
  machine-facing protocol surface and must stay English.

  **The two date defects are fixed and pushed (`c09f67d`); the rest stays backlogged.** Six
  fixed-format formatters are now locale-pinned — `dayNumber` was the sixth, missed by the original
  count and the same class, since numerals follow the locale too. And both month grids read one
  function, `CadenceScheduleSupport.weekdaySymbols` / `leadingBlankCount`, with language pinned and
  **week start honoured from `firstWeekday`** — that is a real preference, not a language one.
  Three mutations killed at 0 compile errors each; 2480 passed / 0 failed.
  **This inverts when localisation actually happens**, and both doc comments say so: the pins come
  off and the fixed patterns must become `setLocalizedDateFormatFromTemplate` or `Date.FormatStyle`,
  because idiomatic zh is `8月24日` rather than a translated `MMMM d`.

- [T-274] **Importing a Cadence archive.** [[T-19]] shipped the export and deliberately stopped
  there: an unverified restore is worse than none, because it invites the user to trust it.
  `CadenceDataExportService.decode` already returns a `CadenceArchive`, and
  `CadenceDataExportSurfaceTests.theArchiveRoundTripsThroughJSON` proves encode → decode → equal, so
  the *parsing* half is done and tested. What is not decided, and what makes this a design ticket
  rather than a loop over twenty arrays:
  1. **CloudKit.** The store is `.private("iCloud.com.haoranwei.Cadence")`. An import is not a local
     write — every row inserted is uploaded to every other device, so "restore my backup" on one
     device is "push 4,000 rows at the others" from theirs. A restore has to state whether it
     targets the syncing store at all, or whether it goes through the `CADENCE_LOCAL_STORE_ONLY`
     path and asks the user to re-enable sync afterwards.
  2. **Identity.** Records carry their original `id`s. Re-inserting them means the merge policy
     decides which copy of a row wins, and nothing in the app currently reasons about that. The
     three plausible modes — replace the store, merge by id, import as copies with fresh ids — have
     different answers and only one of them can be the default.
  3. **Referential integrity.** Relationships are stored as id references, so an import is a
     two-pass rebuild: insert every row, then wire every reference. A reference to a row the archive
     does not contain (a hand-edited file, or an archive from a newer `formatVersion`) has to fail
     loudly rather than silently produce an orphan — `DataIntegrityRepairService` is the repair pass
     for stale relationships, not a substitute for validating input.
  4. **The legacy note models.** `DailyNote` / `WeeklyNote` / `PermNote` / `EventNote` / `Document`
     are exported because a pre-migration archive is the only copy of them. Importing one into a
     store where `NoteMigrationService` has already run would re-create rows that were already
     folded into `Note`, i.e. duplicate every note. The importer has to run the migration after the
     insert, or refuse those tables when the destination has already migrated.
  Do **not** ship this behind a confirmation and call it verified. The bar is a test that imports an
  archive into a container and asserts the graph came back — every foreign key resolved, counts
  equal, and a second import of the same file changing nothing.

- [T-481] **DECIDE: one top-level suite per test file?** Raised and deliberately *not* landed while
  closing [[T-465]]. It would provably stop the sibling-suite risk surface from growing and has zero
  false positives — but it imposes a new authoring rule that **32 existing files already break**, so it
  is a decision, not a fix. Options: adopt with those 32 allowlisted; adopt and split them; decline and
  keep the periodic `scripts/test-suite-index.sh` read that T-465 settled on.







- [T-491] **The iPad capture palette's scrim stops at the detail pane.** Found while closing [[T-282]].
  `iPadMacStyleRootShell` clips `detail()` and the capture host is inside it, so an open palette **dims
  the page and leaves the sidebar bright**; on iPhone the shell-level host dims everything including the
  tab bar. The scrim's `.ignoresSafeArea()` is a no-op inside that clip. Placement-vs-capability
  judgement, so it needs a decision rather than a fix.




















- [T-511] **Does a plain-text drag reach the macOS note editor at all?** Residue from [[T-495]], which
  disproved the clobbering mechanism. **Not answerable headless** — an offscreen `NSTextView` registers
  no drag types under any sequence tried, which is either the real behaviour or an artifact of a test
  host with no display server. **One manual drag settles it**: open a note on macOS, drag a text
  selection from another app onto the editor, watch for the insertion caret following the pointer. If it
  fails, the fix is a **deliberate registration of the text types — not** a union with
  `acceptableDragTypes`, which would re-advertise bitmaps at a refusing host and undo half of [[T-478]].
























- [T-531] **macOS UI tests need a one-time system authorisation that no agent can grant.** Measured
  2026-08-30 in integration run r31: `CadenceUITests` fails at launch with *"The test runner failed to
  initialize for UI testing. (Underlying Error: Authentication canceled. System authentication…)"*. The
  tests themselves are well built — they isolate their store per run with `CADENCE_LOCAL_STORE_ONLY`, a
  fresh `CADENCE_UI_TEST_STORE_ID` and reset flags — so this is purely the macOS automation-permission
  gate, which requires the user's password. **The integration runner now defaults the UI stage off**
  (`run-ui` as arg 2 enables it) so batches are not blocked. Once authorised, turn it on and it becomes
  the third gate alongside the unit suite and the MCP build.

















  **Escalated 2026-08-31 by the batch-8 verification pass — this is live at HEAD with the suite green,
  not hypothetical.** `componentNames` is `["EmptyStateView(", "iOSEmptyPanel("]`, and
  `Cadence/iOS/iOSFeatureViews.swift` contains **zero occurrences of either** — verified — so that whole
  file is invisible to `noEmptyStateSentenceIsSpelledInTwoFiles`. It reaches `iOSEmptyPanel` one hop away
  through `iOSFeatureEmptyState` → `iOSFeatureEmptyDetail.body`, whose call carries only identifiers.
  Three live consequences: **`"No habits yet"` is spelled in two files** (`HabitsView.swift:158` and
  `iOSFeatureViews.swift:411`), byte-identical, with their subtitles **already diverged**;
  **`"No goals yet"` is re-typed at `iOSFeatureViews.swift:221` after [[T-540]] converged it** into
  `CadenceEmptyStateCopy.goalsTitle` — and `noCallSiteRetypesASharedStringConstant` cannot see that
  either, because it harvests `static let` and `goalsTitle` is a `static func`; and `"Select a note"` is
  spelled in `NotesView.swift` (via a fourth entry point, `NotesEditorPlaceholder`) and
  `iOSListNotesView.swift:271`. **The suite already names `iOSFeatureEmptyState` at lines 820 and 890
  without adding it to `componentNames`** — so this is an unnoticed gap between two same-session tickets,
  not a recorded decision. [[T-533]]'s guard checks within `iOSFeatureViews.swift`; T-540's checks the two
  macOS goals files; neither crosses.



- [T-551] **[[T-495]]'s verdict holds but one supporting clause did not reproduce — and it is the one that
  made [[T-511]] look like a formality.** The batch-8 pass re-measured on a real offscreen
  `CadenceTextView` built by the suite's own fixture. **Reproduced exactly:** registration-never-called
  gives `registeredDraggedTypes == []` at every step, and `acceptableDragTypes` carries the legacy TIFF
  and PNG names with `importsGraphics = false` — so the "unioning would undo half of [[T-478]]" argument
  is sound and the closure stands. **Did not reproduce:** "AppKit's own re-registration unions rather
  than replaces — toggling `isEditable` yields 22 types". Measured **3** after an `isEditable` toggle,
  **3** after `isRichText = true`, **3** after `importsGraphics = true`; a refusing host stayed at **1**.
  The construction is offscreen with no window, which may be why `updateDragTypeRegistration` never
  fires — so the clause is **unverified rather than disproved**. But if it is false, the editor advertises
  3 types where AppKit would have offered 19 text-ish ones, which makes **T-511 a live question rather
  than a formality**. Re-read this before T-511 is closed cheaply.





- [T-554] **R1 refused: the resolve-for-display / resolve-for-save split cannot be made unrepresentable
  in Swift — the sweep holding it is derived instead.** Investigated 2026-08-31 as the first refactor
  target, on the evidence of four independent bugs ([[T-446]], [[T-488]], [[T-514]], [[T-534]]).
  **The abstraction would not have prevented three of them.** All three narrowed the array *at the call
  site*, before any helper was reached — and Swift cannot express "this array is the whole collection", so
  `Resolver(areas.filter(\.isActive), selectedID:)` **reproduces T-488 exactly and compiles**. Every
  candidate shape has such an initializer. The invariant a resolver would add **already holds** given the
  same two arguments; what is missing is *argument agreement*, which is not a type property. T-534 was
  already closed the compile-forced way, by making `selection:` non-defaulted. **What shipped instead**:
  the four sweeps holding those fixes named six and four hardcoded paths, so a fifth surface in a new file
  was swept by nobody — both the control set (44 `View` types taking a whole list array) and the
  picker-surface file set are derived from the tree now. Mutation A is the evidence: pre-filtering at a
  macOS call site kills **only** the new sweep while all four pinning tests stay green. **Recorded as a
  closed investigation so the abstraction is not proposed again without new evidence.**

- [T-562] *(RESOLVED 2026-08-31 — **this ticket's premise was wrong, and the wrong half was mine.**
  Not a regression, not a never-worked, and not a sidebar defect at all. `testLaunchesToTodayWithSeededSidebarLists`
  **passes about 4 runs in 5**: 5 runs measured (working tree @5ae916a pass 7.4s; isolated `git archive HEAD`
  pass 7.1s, FAIL 15.9s, pass 5.8s). The one failure was at `CadenceUITests.swift:74` —
  `wait(for: .runningForeground, timeout: 10)` inside `launchApp` — so the app never reached the
  foreground and no sidebar query was ever made. The originating run's xcresult shows the same thing:
  `CadenceUITestsLaunchTests` **also** failed, at its identical foreground wait, and both tests ran
  3-5x slower than normal. That exonerates the seeder, the sidebar data path and the identifier.
  **All three hypotheses killed, H2 by direct measurement:** a 0.3s process poller caught the launch —
  pid 98099 was `…/Build/Products/Debug/Cadence.app/Contents/MacOS/Cadence` (confirmed via `lsof` txt)
  carrying the test env vars. XCUITest launches the freshly built debug app, **not**
  `/Applications/Cadence.app`. The identical-bundle-id hazard does not apply to this target.
  H1 died to archaeology: the row's accessibility chain is byte-identical from `2d3a82f` (where the
  test and the identifier were both introduced) to HEAD.
  **Root cause was process, not code, and it was the orchestrator's:** the originating run was a bare
  `xcodebuild`, which takes **no test-host lock**, while another agent's hosts were live. `scripts/xcb.sh`
  acquires the lock (`xcb.sh:183`); bare `xcodebuild` does not. Standing rule now: **run UI tests as
  `scripts/xcb.sh <id> test -only-testing:CadenceUITests`.** Superseded by [[T-563]] for the residual flake.)*
  ~~**The first-ever UI test run fails: no seeded sidebar list is visible.**~~ Measured 2026-08-31,
  immediately after the user granted the macOS automation authorisation that [[T-531]] was blocked on.
  `Testing started` now reaches real tests, so the gate is open and T-531's blocker is cleared.
  `testLaunchesToTodayWithSeededSidebarLists` finds `sidebar.destination.today` but then fails at
  `CadenceUITests.swift:23` after five retries over 5s waiting for `sidebar.list.area.alpha-area`.
  The other two UI tests skipped (they need `CADENCE_RUN_INTERACTIVE_UI_TESTS=1`).
  **Do not assume this is a regression.** `CadenceUITests.swift` was last touched in `0dc7d3a`, long
  before batches 1-10, and the target has been dark that entire time -- so this test may never have
  passed. Establish that first; "it never worked" and "we broke it" need different fixes.
  What is already ruled out: the identifier is derived, not typed
  (`SidebarSupportViews.swift:353` builds `sidebar.list.\(kind.accessibilityFragment).\(slug(label))`,
  and "Alpha Area" slugs to `alpha-area`); there is no `DisclosureGroup`/collapsed section around the
  row; the seeder inserts all three lists under a context and does `try? modelContext.save()`
  (`CadenceUITestSupport.swift:29-44`); `prepareAppState` is wired at `macOSRootView.swift:102`.
  **Leading hypothesis, and it is cheap to test: the identical bundle id.** `/Applications/Cadence.app`
  is `com.haoranwei.Cadence` **build 16** -- the same id XCUITest launches ("Open com.haoranwei.Cadence").
  The runner may be attaching to the user's installed release app instead of the freshly built debug
  one. Confirm which binary actually launched before theorising further.
  Second hypothesis: the lists are seeded but never reach the sidebar's data source -- adjacent to
  [[T-558]] and [[T-559]], though note these seeded lists *do* have a context, so it is not the
  context-less path those tickets describe.
  Safety, already checked: the user's real store was NOT written -- `~/Library/Containers/com.haoranwei.Cadence/`
  Application Support is still dated 2026-08-19, untouched by the run. The per-run
  `CADENCE_UI_TEST_STORE_ID` isolation held. Keep it that way.

- [T-710] **The seeded sidebar rows are sometimes not there 5s after launch, and nobody has timed them.**
  Found while measuring [[T-563]], and it is the *only* thing left in `CadenceUITests` that is
  genuinely intermittent. 2026-09-02, 20 runs with the screen unlocked and the app confirmed in the
  foreground: **4 failed at `CadenceUITests.swift:23`**, `sidebar.list.area.alpha-area` absent after
  `CadenceUITestBounds.sidebarRow` (5s). The other 16 passed. `sidebar.destination.today` on the line
  above passed every time, so the window was up and the accessibility tree was live — it is the
  *seeded* rows specifically.
  **Do not raise the bound to make this go away.** Nobody knows yet whether the rows are late or
  never arrive, and those need opposite fixes: the failing runs stop at line 23 (`continueAfterFailure
  = false`), so no run has ever asked whether the row shows up at 6s or at all. The measurement is
  cheap and it is the whole ticket — re-run with that wait widened to 60s *and instrumented*, and
  read the distribution. If they arrive late, the bound moves and the comment on `sidebarRow` gets
  its number. If they never arrive, this is a seeding or `@Query` refresh bug and the bound is
  irrelevant. `CadenceUITestSupport.seedDataIfNeeded` inserts under `onAppear` and commits with
  `try? modelContext.save()`, which is one of the places to look if it turns out to be the latter.
  Note the batch that would have measured this was consumed by the locked screen — the instrumented
  tree is gone, so budget a rebuild. **The screen must be unlocked for the run to mean anything.**

- [T-584] *(**premise CORRECTED 2026-08-31 — this ticket, written by the coordinator, overstated the
  defect in two ways.** (1) **It is not an unnoticed bug; it is a recorded decision.**
  `CadenceTodayLayoutSupportTests.swift:142` `everyInspectorWidthTheTargetIPadsProduceFallsBackToOneNotesColumn`
  already asserts this exact outcome over these exact devices, and `:167`
  `theInspectorFloorWasNotRaisedToFitTwoNotesColumns` costs out the alternative. T-177 chose the
  one-column fallback **on purpose**; the behaviour it replaced was a 39pt editor. (2) **"Never a note"
  is literally false** — `iOSNotesView.open(_:)` (`:498-509`) routes `.oneColumn` at regular width to
  `presentedNote`, so a note *is* readable.
  Also corrected: the widest reachable rail is **545.4pt** (13" landscape, sidebar folded), not the 483
  the ticket claimed. It changes nothing — a 601 rail needs a 1505 pane, which no iPad produces — so
  `.oneColumn` at every shipping width still holds.
  **The real complaint, which survives and is still worth fixing:** the rail is an index, and reading a
  note means a `fullScreenCover` that blanks a 1366pt iPad. The Events tab uses `.sheet`, so it is a
  form sheet rather than a blank-out — the two paths already disagree.)*
  **AWAITING USER DECISION — four options costed, agent recommends option 1.**
  **1. A one-column *editor* mode in the rail** (recommended). At regular width with a note selected,
  render the editor in the pane with a return-to-list control instead of presenting a cover. Mostly
  reuse: `editorPane` exists standalone (`iOSNotesView.swift:363-388`) and `iOSNoteEditorCover`
  (`:622+`) is already a complete editor. Work: a third branch in `content`; `open(_:)` stops setting
  `presentedNote` at regular width; `showsHeaderTemplateMenu` (`:146`) must become true in the editor
  state or the header silently drops three controls; `iOSNoteEditorCover` needs an injected dismiss.
  **Must be applied to `iOSListNotesView` too** (`:173-175`, same split, same cover) or the two notes
  surfaces diverge. Takes nothing from the task column; fixes every narrow regular-width host.
  **2. Lower `twoColumnMinimumWidth`** — dead end. Even at macOS's `columnIdealWidth` of 224 the floor
  is 545, which only 13"-landscape-folded clears, so the rail would gain and lose its editor on
  rotation. This is T-177's 39pt editor with a bigger number.
  **3. Raise `inspectorPaneFloor` to 601** — refuted in-repo: `twoPaneMinimumWidth` becomes 1042 and a
  13" portrait iPad loses the task column that is the page's subject, to make room for a notes index.
  **3b.** Give the inspector the notes floor only when the pane can afford it (>=1042). Works
  arithmetically, but the split appears and disappears with sidebar folding and the switcher reflows
  the task column.
  **4. Route the rail's Notes half through a different component** — e.g. today's daily note, edited
  directly, no index. Arguably the best *product* answer and it sidesteps width entirely, but it
  removes browse-all-notes from the rail and leaves other narrow hosts index-only.
  **Nobody has looked at this on a device.** The whole analysis is arithmetic and source reading. Before
  committing, capture the rail at 1366 and at 836 on a simulator.
- [T-669] **`CadenceTaskQuerySupport.sortTasks` re-implements two of `TaskOrdering.precedes`'
  branches, and the equality is now proved.** Found by [[T-640]]. `.doDate` is fourteen lines that
  step through exactly what `.date` + `.ascending` does, and `.priority` is the same shape against
  `.priority` + `.descending`; `.listOrder` already delegates its tie-break. This was left alone
  because T-640's brief was the sentinel, not the comparator — but the ticket ended up **asserting**
  the equivalence, pair-by-pair over every ordered pair of a tie-heavy set, in
  `TaskOrderingTests.everyMigratedMacOSTodaySortModeAgreesWithItsRetiredComparator`.
  So the replacement is mechanical and already covered: have the two branches call
  `TaskOrdering.precedes` and the test goes from proving they agree to being unfalsifiable, which is
  the signal to delete it or narrow it to `.listOrder`.
  This is the shared comparator every iOS surface sorts through, so it is not a passing edit; do it
  as its own change and re-run the iOS Today suites.

- [T-670] **Two `priorityRank` spellings are out of reach of the test that claims to name every
  one.** Found by [[T-639]]. `TrackingDeleteHelpersTests.priorityRankIsOneOrderingSharedByEveryCaller`
  says its point is that it "names **every** spelling a test can reach" — true, and the reachable set
  is two. `CadenceTodayWidgetSupport.priorityRank` (`Services/CadenceTodayWidgetSupport.swift:200`)
  and `GoalContributionSummary.priorityRank` (`Models/GoalContributionSummary.swift:205`) are both
  `private static func` forwarders to `TaskPriority.rank`, so the loop cannot see them and neither
  can any other test.
  Harmless while they forward. The failure mode is the one that ticket exists for: someone re-grows a
  hand-written switch inside a `private` forwarder, and the guard that was written to catch exactly
  that is structurally unable to. Either drop them for `priority.rank` at the four call sites, or
  make them internal so the loop can name them — the second is cheaper and keeps the local spelling.

- [T-680] **Three `allTasks` parameters are threaded into section views that never read them.**
  Found during [[T-608]]. `TasksPanelCompletedSectionView.allTasks`
  (`Cadence/macOS/Views/TasksPanelSectionViews.swift`), `ListTasksGroupSectionView.allTasks` and
  `ListTasksCompletedSectionView.allTasks` (`Cadence/macOS/Views/ListDetailSupportViews.swift`) are
  stored properties no body mentions. Swift does not warn on an unread stored property, so all three
  are invisible: `TasksPanel.swift` and `ListDetailComponents.swift` hand over the whole task array
  on every render for nothing. Deleting them touches four files and no behaviour.
  Not done inside T-608, which was scoped to the row block, and [[T-564]] is queued over two of the
  same call sites.

- [T-681] **Today's section header carries `List` row modifiers inside a `LazyVStack`.** Found during
  [[T-608]]. `TasksPanelIntentSectionView`'s header chains `.listRowBackground(Color.clear)` and
  `.listRowSeparator(.hidden)`, but `TasksPanel` draws its sections in a
  `ScrollView { LazyVStack(pinnedViews: .sectionHeaders) }`, where both are no-ops. (The same two
  modifiers *are* load-bearing inside `TaskListDisplayRow`, whose other caller
  `ListDetailComponents` really does use a `List` — so this is not a case for deleting them there.)
  Harmless, but it is chrome asserting the container is something it is not, and it is the kind of
  line the next section view copies. Check `TasksPanel`'s overdue card stacks for the same shape.

- [T-619] **The two platforms' timed grids draw different hour ladders.** macOS `CalendarVisualStyle`
  0.36/0.30 at 0.95/0.85pt against iOS's 0.46/0.20 at 0.5pt. Out of scope for [[T-595]]/[[T-596]], which
  were iOS-internal and have now made iOS self-consistent. This is the cross-platform half, and it is a
  design call: near-identical numbers that differ by a hair usually mean nobody chose, but a Mac
  hairline and a Retina hairline are genuinely different physical things, so do not assume they should
  match before checking.

  **STOPPED HERE 2026-09-04, deliberately, rather than guessed.** Briefed to "match perceived
  weight, derive the value per platform, pin the derivation" — a mechanism, not a target number —
  and the number is the part still missing. Measured as opacity times line width (a rough
  ink-per-line proxy, since neither platform varies only one axis): macOS's major/minor ladder is
  0.36×0.95 / 0.30×0.85 = 0.342 / 0.255, a minor:major ratio of 0.746; iOS's is 0.46×0.5 / 0.20×0.5
  = 0.230 / 0.100, a ratio of 0.435. Those two ratios are the actual disagreement — not the raw
  numbers, which were never going to match given `iOSCalendarHairlineMetrics.width`'s own doc names
  a real reason (a 2x/3x-screen hairline) macOS's 0.95/0.85 does not share.
  Deriving iOS's opacities from macOS's by holding ink-per-line equal — `opacity_iOS =
  (opacity_mac × width_mac) / width_iOS` — lands at 0.684 major / 0.510 minor, roughly double and
  2.5× today's 0.46 / 0.20. That is exactly the kind of large, unverified swing this repo's own
  filed text warns against ("do not assume they should match before checking"), and checking means
  looking at a rendered screen, which this agent's brief does not authorize (no app launch, no
  simulator). So the mechanism is scoped but the anchor is not: whoever closes this needs either a
  rendered comparison to pick the target ratio, or an explicit number from the user the way T-675
  got `0.35`. Filing it back rather than landing an arithmetic guess on a screen a user looks at
  daily.

- [T-623] **Hard list deletion walks only the local replica.** VERIFIED 2026-09-01 from CXT-018.
  **RE-SIZED AND RE-SEVERED 2026-09-03**, after both blocking claims were checked against source
  rather than inherited. The mechanism is real and unchanged. **The severity is lower than filed,
  the proposed short-term fix is unimplementable *and* mis-aimed, and the durable fix is far larger
  than the "under 2 days" it was sized at.** Parked deliberately — recommendation at the end.
  **Mechanism, re-confirmed.** `CadenceListDeleteHelpers.swift:39-105`, `:107-130`, `:132-159` —
  the ranges this ticket carried (`:39-74`, `:98-115`, `:118-138`) are pre-[[T-620]] and no longer
  point at the cascades. Each one builds its whole tree from local to-many arrays
  (`context.areas ?? []`, `area.tasks ?? []`) with no gate on sync state, so a child row that has
  not imported is not in the array, is not deleted, and arrives later with its owner gone.
  **The import gate does not exist, and would be the wrong fix if it did.** Re-measured over
  `git archive HEAD`: `NSPersistentCloudKitContainer`, `eventChangedNotification`,
  `hasCompletedInitialImport`, `initialImport`, `didFinishImport` — **zero hits** across `.swift`,
  `.md` and `.plist`, outside this ledger quoting itself. The only CloudKit-facing code in the app
  is `CadenceCloudAccountProbe` (`CKContainer.accountStatus`, pinned to one file by
  `onlyOneFileInTheAppTalksToCloudKitDirectly`) and `CadenceSyncHealth`; neither knows anything
  about records. **And the deeper objection**: the race is not only "the first import has not
  finished". It is equally "a peer wrote a child after my last sync" — B adds a task to an area
  while A deletes it. At the moment A deletes, A's import *is* complete, so no import-completion
  signal can close that case. A gate would buy a delete-blocking modal and still leave the common
  one open.
  **The durable fix, measured rather than described.** 13 of the 21 `@Model` types in
  `CadenceSchema` are children a list cascade reaches — `Area`, `Project`, `Pursuit`, `Goal`,
  `Habit`, `HabitCompletion`, `GoalListLink`, `AppTask`, `Note`, `Document`, `SavedLink`,
  `Subtask`, `FocusSessionLog` — carrying **29 to-one owner edges** between them. A tombstone
  reaper has to match on those edges, so that is 29 new raw-id stored properties plus one new
  `@Model` for the tombstone.
  - *The schema mechanics are the cheap part.* A new optional/defaulted attribute and a new entity
    are both lightweight; no `SchemaMigrationPlan` is needed, and none would be legal for this
    anyway — the same argument `repairStoredDefaultNoteTitles` already writes down.
  - *The write side is the expensive part.* **215** owner assignments in app source (`context` 62,
    `area` 61, `project` 54, `goal` 16, `bundle` 12, `parentTask` 8, `task` 5, `parentGoal` 4,
    `habit` 3, `pursuit` 2) and **425** more in `CadenceTests` each have to keep a raw mirror in
    step, or be funnelled through setters that do not exist yet.
  - *A literal soft-delete flag is worse again.* **243** `@Query` and **70** `FetchDescriptor`
    sites would each have to filter it. Tombstone-plus-reaper avoids that, and is the only version
    worth costing.
  - *And it repairs nothing already in flight.* The rows at risk are precisely the ones whose
    relationship is nil locally, so there is nothing to backfill a raw id **from**. The reaper only
    ever matches rows written by a build that has the property, on a device that has it — so it
    starts working after every device in the container has upgraded. That is a multi-release
    rollout, not a change with a day count.
  - *Precedent, and an armed one.* [[T-390]] declined a stored-property change to **two** models on
    exactly the no-`SchemaMigrationPlan` ground, and
    `CadenceEventKitPlatformParityTests.aListsCalendarLinkStoresTheIdentifierAndNoCompanionMetadata`
    goes red if anyone reverses it. This is that same change at 13 models and 29 properties.
  **There is no cheap third option, because the honest one is already done.** "Report what the
  cascade could not reach" needs the same signal the gate needs and does not have it — the cascade
  cannot enumerate what is not in the replica. So the residue was traced row-type by row-type
  instead, and **five of the six survivor kinds are already inert at every read site**:
  - `GoalListLink` — every consumer already drops a target-less row:
    `GoalLinkPresentation.links(of:)`, `GoalContributionSummary.swift:114`,
    `CadenceReadService.swift:1144`. `link.tasks` returns `[]`, so the percentage is unmoved too.
  - `HabitCompletion` — no production `FetchDescriptor<HabitCompletion>` exists outside
    `DataIntegrityRepairService`, and its one pass already does
    `guard let habit = completion.habit … else { continue }`. Every other read is through
    `habit.completions`.
  - `SavedLink` — `LinksView.swift:17-23` and `iOSListSupportViews.swift:590` filter by owner id.
  - `Note` — the list-note surfaces filter by `note.area?.id == area.id`
    (`CadenceNotePlanningSupport.swift:172-175`).
  - `FocusSessionLog` — `.nullify` on all three owners *by decision*, and
    `CadenceFocusLedger.reconcile` skips a subject-less row outright. Already carried by [[T-744]].
  - `AppTask`, `Area`, `Project` — the visible kinds, and the recoverable ones. An owner-less task
    is in Inbox (`area == nil && project == nil`); a context-less area is in the unfiled group. The
    user can see them and delete them.
  So the real residue is a storage leak plus some rows in Inbox: the same *leak, not loss* bias
  [[T-620]] chose on this very file, reached from the other side.
  **The T-433 framing in the original filing is wrong.** T-433's rule is that a count may not
  *over-promise* — may not report less loss than actually occurs. Here the count and the cascade
  read the same local arrays, so they agree exactly and the count is never lower than what is
  taken. What is over-promised is *completeness*, by `cascadeSentence` and by `isEmpty`'s "nothing
  else is filed here" — and the one uncertainty sentence the app owns cannot say it, because
  `unknownImpactNotice` is worded *"may remove **more** than the counts below show"*. That is the
  opposite direction. [[T-752]].
  **Recommendation: park it. Do not gate the delete, and do not ticket the rewrite as proposed.**
  The gate is unimplementable and aimed at the rarer half of the race; the durable fix is a
  13-model / 29-property / 215-call-site change that repairs no existing data and only begins
  working a release after every device has it. The cost being carried meanwhile is recoverable rows
  in Inbox after a delete that raced a peer. Re-open when the model graph is being changed for some
  other reason and this can ride along. Residue: [[T-751]], [[T-752]].

- [T-624] **A device-local EventKit calendar identifier is stored in CloudKit.** VERIFIED 2026-09-01
  from CXT-020 — mechanism confirmed; **the ping-pong premise is the one unmeasured link in the set.**
  `Area.swift:39` and `Project.swift:25` persist a bare `EKCalendar.calendarIdentifier` on synced
  models; `CadenceCalendarLinkHealth.swift:130` declares a link dead purely from *this device's* live
  set, and both platforms' repairs write straight back to the same synced field.
  **Whether the same iCloud calendar carries different identifiers on this user's Mac and iPhone was
  NOT measured** — the verifier had one machine and deliberately did not touch EventKit, which would
  have triggered a TCC prompt on the user's Mac. Apple documents the identifier as local, which makes
  it plausible. **This is the finding that turns entirely on that unmeasured fact.**
  Outcome if true: each device shows the other's good link as broken and each repair invalidates the
  other. No content lost; a repeating false alarm.
  **Guard worth knowing:** `CadenceEventKitPlatformParityTests` **fails if a second `linkedCalendar*`
  property appears** — the repo has already armed itself against the alternative branch. The suggested
  device-local preferences map needs no stored property.
  **NARROWED 2026-09-01 in `892b866`, and deliberately left open.** The half that is a *defect*
  rather than a premise is fixed, and fixed **without depending on the unmeasured fact**:
  `CadenceCalendarLinkHealth.missingLinks` now takes an `observedCalendarIDs` set and reports a link
  dead only for an identifier **this device has itself seen alive**. The record is
  `CadenceCalendarLinkObservations`, device-local in `UserDefaults` — **no stored property**, so
  T-390's `SchemaMigrationPlan` block and the parity guard above are untouched. Under one shared
  identifier space every device observes every linked calendar and [[T-400]]'s report is exactly what
  it was; under device-local ones the device with no evidence stays quiet. **Either way a repair on
  one device can no longer invalidate another device's link**, which is the whole ping-pong.
  **Why it stays open.** Nobody has measured whether the identifiers really differ across this user's
  devices, and nobody here could: it needs an EventKit call on the user's own Mac, which raises a TCC
  prompt. *If* they differ, a link made on one device still does not **function** on the other —
  `CadenceEventNoteSupport` matches `calendarID` exactly — it now merely fails quietly instead of
  offering a repair that overwrites the good side. Making the link portable is T-390's
  companion-metadata branch and is still blocked on a `SchemaMigrationPlan`.
  **Accepted cost, recorded so the next reader does not file it as a regression.** The observation set
  starts empty and only ever learns *live* identifiers, so a link that is **already** dead the first
  time this build runs is never reported again. Seeding the set from every currently-linked id would
  bring that row back and defeat the gate for exactly the cross-device case, so it is not done.

- [T-626] **iOS omits the background mode CloudKit silent-sync needs — latent, and BLOCKED ON iOS
  DISTRIBUTION. Do not implement this until that changes.** VERIFIED 2026-09-01 from CXT-016;
  all three source facts re-verified 2026-09-01 while closing [[T-652]].
  **The gate, plainly.** iOS is built but not distributed: `docs/apple-release-readiness.md` contains
  no occurrence of "iOS", "iPhone" or "iPad" — the two channels are the Mac App Store and Developer
  ID. So the impact on any shipping build today is **zero**, and the ticket's whole cost is a
  regression risk in the bundle that *does* ship.
  **The defect is broader than filed: iOS does not register either.** `CadenceAppDelegate` is
  `Cadence/macOS/Services/CadenceAppDelegate.swift`, installed by `@NSApplicationDelegateAdaptor`,
  and there is **no `UIApplicationDelegateAdaptor` anywhere in the repo**. It is the sole caller of
  `registerForRemoteNotifications()`, which
  `CadenceLaunchWiringTests.onlyTheRegistrarAsksAppKitToRegister` pins to that one file. On iOS,
  Cadence neither declares the capability nor registers for it.
  **Why it cannot be done by accident, and what to do when it can be done.** One app target, one
  `Cadence/Info.plist` (`INFOPLIST_FILE` names it in Debug and Release alike), so `UIBackgroundModes`
  added for iOS also ships in the **macOS** bundle — and the
  `#expect(info["UIBackgroundModes"] == nil)` it would break is a *deliberate* App Store
  review-hygiene check, not an oversight. That test
  (`AppStoreReviewReadinessTests.appInfoPlistContainsReviewReadyPrivacyKeys`) now **says so in its
  own doc comment**, including the instruction for the day iOS ships: satisfy the assertion's
  *intent* — "the macOS bundle declares no background mode" — by splitting the plist per platform or
  conditionalising the key, and re-point the `#expect`. Deleting the line removes the check rather
  than satisfying it.
  **The same change also closed the hole that made the guard bypassable.** `GENERATE_INFOPLIST_FILE
  = YES`, so the shipped plist is that file merged with the target's `INFOPLIST_KEY_*` build
  settings — and ticking Background Modes in Xcode's capability editor writes
  `INFOPLIST_KEY_UIBackgroundModes` into `project.pbxproj` and never touches `Cadence/Info.plist`.
  The mode would have shipped with the `nil` assertion still green. The test now reads
  `project.pbxproj` too. Residue from that reading: [[T-665]].



- [T-642] **NARROWED 2026-09-03 by measurement. The alert is *not* invisible — the sheet is
  dismissed to make room for it and does not return.** Both halves of the original ticket are
  disproved, and both disproofs are the point of keeping this open.
  **Driven**, on a booted iPhone 17 Pro simulator (iOS 26.5), against a build of this tree whose
  `CadenceTaskStatusEditing.toggleCompletion` refuses every commit, so every circle tap records a
  refusal on `CadenceTaskSettleFailureCenter`:
  - *Positive control.* Ticking a task row's circle on Today shows `iOSRootView`'s alert —
    *"Couldn't Update Task / Couldn't save these changes. Nothing was changed."*
  - *The claim under test.* Ticking the circle **inside `iOSTaskDetailSheet`** shows the **same
    alert**. The premise — "a view that is already presenting cannot present again", therefore the
    alert never reaches those two surfaces — is **wrong** for `.alert` on iOS 26. What actually
    happens is that SwiftUI **dismisses the presented sheet in order to present the root's alert**,
    and the sheet does not come back when the alert is dismissed. The user is told; the user loses
    the sheet they were working in.
  **The fix this ticket recommended is disproved, not merely unchosen.** The nearer-host pattern —
  a second `.alert` inside the sheet, bound to the same `CadenceTaskSettleFailureCenter.settleFailed`
  — was built in a minimal SwiftUI app with the identical modifier order (alert on the root, then
  the host that presents the sheet) and driven on the same simulator. It is **strictly worse**: the
  sheet is still dismissed **and** neither alert renders, so the message is lost entirely. Do not
  mount a second alert on that flag.
  **`iOSCalendarBundleDetailSheet` was not driven** — reaching it needs a bundle to exist, and the
  seeded store has none. It is presented only by `iOSBundleInspectorHost`, from the same root, in
  the same modifier order, which is a reason to *expect* the same behaviour and is not evidence of
  it. Drive it before claiming it.
  **So what is left to decide** is the real symptom above, with two options already eliminated. A
  third shape is needed: an inline notice inside the sheet, the way `TaskEmbedFieldEditorPopover`
  shows `CadenceInlineFailureNotice`; or a centre that records *which* surface should own the
  sentence, so the shell stays quiet while a sheet is up. The store is correct under all of these —
  `commitSettle` puts the status, the timestamp and the successor back before anything is recorded,
  so the circle re-draws open on its own — which is why this is a "where was I" defect and not a
  data one. **Nothing in `Cadence/iOS/` was changed for this reading.**

- [T-657] **The save-commit detector cannot see a success report handed *sideways* one frame down.**
  Found while landing [[T-636]](b), and it is the reason three of [[T-648]]'s four sites are not in
  the ledger. Half 2 already follows the **swallow** one frame down (`indirectReportOffenders`,
  [[T-566]]); it does not follow the **report**. `NotePanel.toggleEmbeddedSubtask` /
  `renameEmbeddedTask` and the `ListNotesSupportViews` and `NoteEditorPane` copies of both answer
  `Void`, swallow the commit, and then call `refreshEmbeddedTask(task)` — whose whole body is
  `editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(task)` plus a redraw.
  That is the identical claim `iOSMarkdownEditingSurface` makes by *returning* the same value, and
  the detector sees the iOS one and not the macOS three.
  Two pieces are needed and neither is free, which is why this is a ticket rather than part of
  T-636(b): a base spelling for "assign freshly built render info into something the view draws"
  (the app's only name for it today is the `MarkdownTaskEmbedRenderInfo` type itself, which is one
  ticket's worth of vocabulary), and a **report**-one-frame-down index over same-file callees whose
  bodies are nothing but a report. Measure the false-positive cost of the second before shipping
  it: the block window is what keeps half 2 honest, and following calls out of it widens that
  window. Until then the three macOS sites are recorded in T-648's prose only.

- [T-654] **The block focus timer banks its minutes over a swallowed save, then clears the clock.**
  Found while landing [[T-636]](c), which fixed the single-task door beside it.
  `iOSFocusView.logBundleSession` calls `CadenceFocusSupport.logElapsedSeconds(_:across:)` →
  `CadenceFocusBundleSupport.distributeMinutes`, which writes `AppTask.actualMinutes` and the
  container's `loggedMinutes` with `+=` for every ticked member, then runs
  `try? modelContext.save()` and `resetTimer()`. Same defect and same fix as (c): the accumulators
  make *"the next fetch corrects it"* false, and the reset destroys the only copy of the seconds.
  **No half of the rule could see it**, which was the interesting part: nothing was inserted or
  deleted, and `resetTimer()` is not in half 2's success vocabulary. macOS's bundle timer commits
  through the same helper and belongs in the same pass.
  **[[T-621]] changed that half of the sentence (2026-09-03).** Banking a session inserts a
  `FocusSessionLog` row now, so half 1 finds both sites unaided: `CadenceFocusSupport.endSession`
  and `iOSFocusView.logBundleSession` are held in `existenceExemptions` naming this ticket, and
  `FocusView.bundleTimerControls` joined `timerControls` in `commitReachExemptions`. Fixing this
  means deleting those three names in the same change. The ledger also **downgrades the
  consequence**: a refused save leaves the row pending rather than destroying the minutes, and
  `CadenceFocusLedger.reconcile(in:)` puts the counter back once it lands. Still a defect — the
  reset still throws away the seconds the user is watching — but no longer an unrecoverable one.

- [T-651] **CLOSED 2026-09-03 (`34c0f4e`).** Three of the four sites now commit.
  `KanbanCardMetaSupportViews.swift`'s `KanbanTagPickerPopover.body` and
  `MarkdownEditorView.createInlineTag` both called `TagSupport.resolveTags` from an ambient
  `ModelContext` and committed nothing; both now go through
  `TagSupport.committedTag(named:in:commit:)`. `createInlineTag`'s *report* half — the swallowed
  save followed by `return .tag(tag)`, the suggestion the editor writes into the note — needed a
  second change: its remaining in-place edit (un-archiving the tag, bumping `updatedAt`) now goes
  through `CadencePendingChangePersistence.commitEdit(in:undo:)` instead of a bare `try?`, so
  nothing in the function swallows a commit at all. `CadenceNotePlanningSupport.update` is the
  third — it now calls a new `TagSupport.syncNoteTagsFromMarkdownCommittingInsertions`
  (`Cadence/Shared/CadenceInlineTagCreation.swift`) instead of the raw `syncNoteTagsFromMarkdown`;
  `update`'s signature is unchanged, so none of its nine callers moved.
  **The fourth, `NoteEditorPane.noteTagsBinding`/`.persistEditorContentIfNeeded`, is untouched, as
  directed** — it inserts rows on the debounced-autosave path, and the T-497 caret decision
  ("the edit is in-place on an object the store already holds, so there is nothing to un-insert")
  does not cover an insert. `NoteEditorPane.body`'s own, differently-attributed exemption (it
  reaches the same `syncNoteTagsFromMarkdown`, pinned by
  `CadenceInlineTagCommitSurfaceTests.theNoteEditorPanesBodyExemptionIsTheTagSyncNotASubtask`) was
  never one of the four named sites and is also untouched.
  Mutations M1–M3 (`scripts/mutate.sh`) reverted each of the three fixes in turn; all three were
  KILLED by `CadenceSaveCommitDisciplineTests` (`noSwallowedSaveCommitsAnInsertOrADelete` /
  `noSwallowedSaveIsFollowedByADismissOrACompletionHandler`).
  **Residue**: [[T-762]] — the `NoteEditorPane` debounced-autosave undo question this ticket left
  open on purpose.

- [T-653] **CLOSED 2026-09-03 (`34c0f4e`).** Re-measured before acting, nine batches on: all three
  claims still held. `seedDefaultTags` still has no launch caller —
  `PersistenceController.performStartupMaintenance` still says so in its own comment, and
  `CadenceFirstLaunchEmptyStoreTests` still holds it there. Its four callers are still exactly
  `SettingsTagsSection`, `iOSSettingsTagsSection` (`iOSTagsSettingsSection`), `TagPickerSupportViews`
  (`TagPickerPlaceholderRow`) and `iOSTaskDetailComponents` (`iOSTaskTagPickerPopover`).
  `deduplicateTags`'s only app caller is still `seedDefaultTags`, passing `save: false`.
  All four buttons now call a new `TagSupport.seedDefaultTagsCommitting(in:commit:)`
  (`Cadence/Shared/CadenceInlineTagCreation.swift`), which runs `seedDefaultTags(saveChanges: false)`
  and commits the whole cascade — the insert **and** the dedup merge's delete, together — through
  `CadencePendingChangePersistence.commitDelete(in:commit:)`, so a refusal rolls both back rather
  than leaving a half-seeded, half-merged table. Each button shows the refusal inline
  (`CadenceInlineFailureNotice`), the way `SettingsTagsSection.createTag` already does for the
  sibling action beside it.
  The `existenceExemptions["Cadence/Services/TagSupport.swift"]` comment no longer calls
  `seedDefaultTags`/`deduplicateTags` "launch-time maintenance with no user watching and nothing to
  report to" — that stopped being true when [[T-528]] removed the launch caller. It now says the two
  raw declarations stay exempt because they are still handed a `ModelContext` whose caller commits,
  and names `seedDefaultTagsCommitting` as that caller.
  `syncAllNoteTagsFromMarkdown`'s entry and rationale are untouched — `PersistenceController` still
  passes `saveChanges: false` and only `CadenceMCPStorePreparation.prepare` (the MCP boundary) lets
  it save.
  Two new behavioural tests in `TagSupportTests` pin the wrapper directly. The rollback one caught
  itself first: a mutation removing `commitDelete`'s rollback **survived** the initial version of
  `arefusedSeedCommitRollsBackBothTheInsertAndTheMerge`, because reading a second context cannot
  tell "rolled back" from "never reached the store" apart — both look identical from outside the
  context that held the refused change. Fixed to save the same context again after the refusal,
  which is what an unrelated autosave would do; that version was KILLED (M5) as intended.
  `CadenceFirstLaunchEmptyStoreTests.seedCallOffsets` now keys on
  `TagSupport.seedDefaultTagsCommitting(` rather than the raw name; its four-file caller list is
  unchanged. Mutations M4–M6 (`scripts/mutate.sh`): M4 reverted one button to the raw seed call and
  was KILLED by `noUnpromptedCodePathSeedsTheDefaultTags`'s caller-list assertion; M5 and M6 broke
  the wrapper's rollback and its commit respectively and were both KILLED by the two new
  `TagSupportTests`.

- [T-762] **`NoteEditorPane`'s debounced-autosave tag writes are still the one open piece of
  [[T-651]]'s family, left there on purpose.** `noteTagsBinding`'s `Binding<[Tag]>` setter and
  `.persistEditorContentIfNeeded` both write tags through `TagSupport.setTags(named:on:in:)` /
  `syncNoteTagsFromMarkdown(_:in:)` — an ambient `ModelContext`, no commit — on the path that fires
  a few seconds after the user stops typing, not on an explicit Save.
  The question T-497 answered for in-place field edits does not answer this one: T-497's decision
  ("the edit is in-place on an object the store already holds, so there is nothing to un-insert")
  is about a field write, and `resolveTags`/`setTags` **insert** a `Tag` row when the markdown names
  one that does not exist yet. An insert has something to un-insert, so the caret question is live
  again: what does undoing a `Tag` insert mean when it happened three keystrokes ago, under a caret
  that has since moved, on a debounce timer the user never asked to fire? `commitInsert`'s per-row
  undo is built for a discrete action (a button press) with a clear "before" to restore to, not for
  a live document that has kept moving since the row was minted.
  Not started here. Whoever picks this up should read `CadencePendingChangePersistence.commitEdit`'s
  doc on why `rollback()` is unavailable, and decide whether the answer is "no undo, name the
  refusal and leave the tag pending" (matching T-497's in-place answer) or something that actually
  reasons about the insert.

- [T-661] **The portable export carries a device-local calendar identifier.** Found while landing
  [[T-624]]'s evidence gate; not fixed, and it is a decision rather than a bug.
  `CadenceArchiveArea` and `CadenceArchiveProject`
  (`Cadence/Services/CadenceDataExportService.swift:289` and `:327`) copy `linkedCalendarID` straight
  into the archive. That field is an `EKCalendar.calendarIdentifier`, which Apple documents as local
  to one device, so an archive restored on a different machine carries a link naming a calendar that
  machine never issued — the same shape as T-624, one layer out, and with the same blocker: a
  *portable* link needs the title/source T-390 declined to store, which needs a `SchemaMigrationPlan`.
  T-624's gate does not reach this: it makes the imported link silent rather than falsely repairable,
  which is the right failure but is not portability.
  **The cheap half is a sentence, not code** — either say in the export docs that calendar links do
  not survive a cross-device restore, or drop the field from the archive rather than shipping a value
  that cannot mean anything on the other side. Neither has been decided. Note the import side is
  unsettled anyway ([[T-274]]), so this is not urgent.

- [T-664] **The `try? save()` rule's report vocabulary has no spelling for "the surface filled
  itself in".** Found — and then *measured* — while fixing [[T-652]].
  `CadenceSaveCommitRule.successReport` is a closed list of **dismissals**: `dismiss…()`,
  `is/show<X> = false`, `editing/selected/pending<X> = nil`, `presented<X> =`,
  `on(Save|Done|Complete|Commit)(`, plus `return true` from a `-> Bool` and a non-`nil` answer from
  a `-> X?`. That is exactly why [[T-497]] caught `TagPickerPopoverViews.saveEdits` and `.archive`
  — both end `editingTag = nil` — and did not catch `.restore`, which reports by **appending to a
  bound selection and blanking a search field**: `selectedTags.append(tag)`, `query = ""`. A
  surface that stays open and merely *fills in* is invisible to the rule.
  **Measured, not inferred.** Restoring the pre-fix `restore` as a mutation and re-running
  `CadenceSaveCommitDisciplineTests` left that suite **green**; only the new hand-written pin
  failed. And a scan of `Cadence/` at `4f74ff9` for the shape — a swallowed `save()` in a
  declaration that also `\w+.append(`s and also assigns `= ""` — found **exactly one** site, and it
  was `restore`. After the fix it is zero.
  **So this is a guard to add, not a backlog to work**, and its whole cost is false positives:
  `.append(` and `= ""` are far commoner than any dismissal, and the `pending<X> = nil` spelling
  already needed a `cancel()` discriminator to be worth two of them. Measure the false-positive
  count *before* widening; if the plain spelling costs more than it finds, scope it (a `@State` /
  `@Binding` target, or `= ""` only in a block that also appends).

- [T-665] **Four Info.plist keys are declared twice, in the file and in build settings.** Found
  while closing the review-hygiene half of [[T-626]]. The app target sets
  `GENERATE_INFOPLIST_FILE = YES` **and** `INFOPLIST_FILE = Cadence/Info.plist`, and then spells
  `CFBundleIconName`, `ITSAppUsesNonExemptEncryption`, `NSCalendarsFullAccessUsageDescription` and
  `NSRemindersFullAccessUsageDescription` as `INFOPLIST_KEY_*` build settings **as well as** in
  `Cadence/Info.plist`. Two sources of truth for four shipped values, and the usage strings are
  long sentences that App Review reads — editing one copy and shipping the other is a quiet way to
  ship the wrong words.
  **Which copy wins was not measured**, deliberately: the finding is the duplication, and the fix
  (pick one home per key — the file, where the other five of its nine keys already live alone) does
  not depend on
  the answer. `AppStoreReviewReadinessTests.appInfoPlistContainsReviewReadyPrivacyKeys` reads the
  **file**, so today it is asserting over the copy that may not be the one that ships.


- [T-672] **CLOSED 2026-09-04 (`7e58fc6c`) — one `CadenceSearchFieldClearButton`, and there were
  eleven copies, not ten.** `Cadence/Shared/Components/CadenceSearchFieldClearButton.swift` is the
  control now; the ten ledgered pickers call it, and so does an **eleventh** copy no accessibility
  ledger could see — `FocusPickerSupportViews`' clear button already carried
  `.cadenceControlLabel("Clear search")`, so it was clean under every naming rule and still a
  near-copy. A ticket filed as a naming finding was a duplication finding, and the duplication is
  what was counted.
  **The three differences, re-measured before deciding.** Tint: five drew `Theme.dim`, five
  `Theme.dim.opacity(0.5)`, one `0.55` — `Theme.dim` wins, being the plurality, the tint the
  `magnifyingglass` at the other end of all eleven rows already draws, and a named ramp rather than
  the one-off opacity `Cadence/Shared/AGENTS.md` rules out. Weight: ten default, one `.semibold`;
  default wins. Size: **kept as a required parameter**, because it is the one difference that was
  chosen — in nine of the eleven rows the clear glyph is drawn at exactly the size of that row's
  own leading glyph (11 in the compact pickers, 12 in the popovers), and the two that differ are
  the two whose leading glyph is emphasised (Cmd+K's 18pt `command` clears at 16, the focus
  picker's 13pt semibold magnifier clears at 12). No default, the [[T-674]] shape: the twelfth call
  site states its scale or fails to build.
  **Focus was the real question and it was not a design difference.** Four restored focus and
  seven did not — the split the ticket describes as four-of-ten is four-of-eleven, and one of the
  four is Cmd+K, which restores focus inside `GlobalSearchInteractionSupport.clearQuery` rather
  than at the button. Clicking a SwiftUI `Button` takes key focus off the `TextField` beside it, so
  the seven left the user typing into nothing after a clear; `NSSearchField`'s own clear button
  keeps focus. So the component **always** restores it and `focus` is required, which is a visible
  change at seven sites and the reason two of them — `GoalTimelineFilterPopover` and
  `TaskBundleTaskPickerPanel` — grew the `@FocusState` they never had.
  Ten entries left `knownUnnamedIconButtonSites` (31→21 sites, 24→16 files, measured over T-672
  alone). `CadenceSearchFieldClearButtonTests` pins the **call sites**: the app-wide sweep asserts
  the only file that spells the control out is the component's own, which is what a rule on the
  component alone would miss. Failing-first on an isolated HEAD tree named all eleven offenders,
  and six mutations — a call site respelled by hand, the name dropped, the focus restore dropped,
  a `.focused` binding dropped, one glyph size drifted, the opacity tint restored — were all
  killed. Follow-ups: [[T-789]], [[T-790]], [[T-791]].

- [T-675] **The app has three row-separator weights and only one of them is named.** Found while
  closing [[T-618]], which named the 0.35 one as `Theme.rowSeparator` over four agreeing sites. The
  other two are in `Cadence/macOS/Views/GoalTimelineSupportViews.swift`: a goal row's bottom rule
  `:252` and a bar's bottom edge `:113` draw `Theme.borderSubtle.opacity(0.55)`, while three 1pt
  rules doing the same job — `:85`, `:213`, and the iOS row `iOSListSupportViews.swift:10` documents
  as the same idiom — draw plain `Theme.borderSubtle`. So one file draws two of the three weights,
  eleven lines apart in one case.
  **This is a decision, not a hoist**, which is why T-618 stopped at the four that agreed. 0.35, 0.55
  and 1.0 over the same near-black border on the same surface are three visibly different rules
  between two rows; picking one is a look at the screen, and a mechanical sweep onto
  `Theme.rowSeparator` would be exactly the unreviewed visual change T-617 and T-618 both refused.
  Decide the weight, then name the survivors on `Theme` beside `rowSeparator` and `rule`.

- [T-688] **Two fallback strings that disagree with the family, and neither is decidable from the
  literal.** Found while sweeping [[T-609]] and deliberately left, because T-609's rule was "route
  through the trim, change no copy":
  (1) `iOSTaskRowActionViews.swift:373` labels a blank-titled goal `"Goal"`, where
  `CadenceTitleNormalization.defaultGoalTitle` is `"Untitled Goal"` and `:410` in the *same file*
  already reads `defaultMilestoneTitle` — so the same nested goal reads two ways depending on which
  chip you are looking at.
  (2) `TimelineDayCanvas.swift:247` names a blank quick-created task `"New Task"`, and
  `CadenceEventTitleSupport`'s header already argues the opposite case in writing: `"New Event"` was
  retired for `"Untitled Event"` because an event created last year is not new but is still untitled.
  The argument applies here unchanged, and this one is **stored**, not drawn.
  Both are copy decisions. Neither is a de-duplication.

- [T-695] **The area lifecycle row's `"No context"` fallback is the project row's un-converged twin.**
  `SettingsListManagementSections.lifecycleCard` and `iOSSettingsTemplateAndListSections.lifecycleCard`
  each write `subtitle: area.context?.name ?? "No context"` inline, byte-identical, a dozen lines above
  the *project* branch that reads the shared `CadenceListSettingsCopy.parentSubtitle(contextName:areaName:)`
  — [[T-577]] converged the project half of that row and left the area half at both call sites. The sweep
  cannot see it either: `"No context"` is **10 characters**, under `cadenceSharedStringConstants`'
  twelve-character floor, so however many surfaces spell it the reuse sweep catches none of them —
  `CadenceReadService` (4 sites), `iOSFeatureComponents.swift:452` and both settings cards spell it today.
  Same shape as `CadenceTitleNormalization.defaultCompactTitle`, which the placeholder ledger unions in
  by hand for exactly this reason. Found while hoisting [[T-546]]'s six section labels out of those two
  functions.

- [T-696] **Both work-hours subtitles describe a band that is not drawn two days a week.**
  `CalendarWorkHoursPreferences.shouldShowHighlight(on:)` is `!calendar.isDateInWeekend(date)`, and both
  `TimelineDayCanvas` and `iOSCalendarTimelineViews.workHoursBand` gate on it — so a Saturday or Sunday
  column carries no amber band at all. macOS now says "Calendar and Timeline day columns gently highlight
  9:00 AM – 5:00 PM." and iOS "Calendar day columns gently highlight …"; both read as unconditional.
  Left out of [[T-544]] deliberately: [[T-524]]'s `bothWorkHoursRowsReadOneWorkdayBoundaryTitle` pins the
  shared tail `gently highlight \(workHoursLabel).` on **both** surfaces, so adding "on weekdays" changes
  two sentences and that pin — a second copy decision rather than the correction T-544 was. The behaviour
  is pinned meanwhile by `CadenceSettingsSectionCopyTests.theWorkHoursBandIsSuppressedAtTheWeekendOnBothSurfaces`.

- [T-697] **"Workday boundary" decides more than the band, and Settings mentions only the band.** The two
  `calendar.workHours.*.v1` keys also feed `CadenceScheduleSupport.readyScheduleSlots` — the "Ready to
  Schedule" chips on iPad's Timeline pane (`iOSTodaySchedulePanel.readyScheduleContext`) propose start
  times inside the work window and leave it only when the window is full — and
  `CadenceScheduleSupport.initialTimelineHour`, the hour a non-today calendar column opens at
  (`iOSCalendarTimelineViews.swift:470`). Both are iOS-only today, and iOS is the surface with the
  *shorter* subtitle: a user narrowing the window to move where suggestions land has nothing on the
  settings row that says the control does that. Found while making the macOS sentence true in [[T-544]].

- [T-692] **`calendar.source?.title` answers two different things on the same platform.** Settings →
  Calendar falls back to `CadenceAppleCalendarNaming.unnamedAccountTitle` ("Apple Calendar") when a
  calendar's account has no name; `Cadence/macOS/CadenceCalendarPicker.swift:31` reads the *same*
  `cal.source?.title` for the *same* absence and falls back to `"Other"`, which is also the label it
  groups those calendars under. So the Mac tells a user "Apple Calendar" on one screen and "Other" on
  another about one fact. [[T-547]] split the concepts and hoisted each; it deliberately did **not**
  decide this, because "Other" is a grouping bucket as well as a fallback and collapsing the two is a
  copy decision. Under the sweep's 12-character floor, so nothing will find it again by machine.

- [T-693] **macOS prints a blank calendar name where iOS prints a fallback.**
  `Cadence/macOS/Views/CalendarEventPresentationSupport.swift:73` and `:198` both set
  `calendarTitle = event.calendar?.title ?? ""`, and that string is *displayed*. iOS reads the same
  property at `iOSBoardCards.swift:77` and `iOSSearchView.swift:640` and falls back to
  `CadenceAppleCalendarNaming.unnamedCalendarTitle`. Same nil, same slot, two answers — and the Mac's is
  an empty line. Distinguish from the three `?? ""` sites that are **search haystacks** and correct
  (`CadenceCalendarEventSearchSupport.swift:29`, `iOSSearchView.swift:616`,
  `iOSCalendarEventEditSheet.swift:101`): those feed a matcher, not a label. Found while hoisting
  [[T-547]]; not fixed there because it is a behaviour change on a surface that ticket did not touch.
  **CLOSED 2026-09-03 (`4cbd2fd`).** Both display sites now read
  `CadenceAppleCalendarNaming.unnamedCalendarTitle` instead of `""`, matching iOS. Failing-first
  reproduced with an unsaved `EKEvent(eventStore:)` never assigned a calendar — `event.calendar ==
  nil` with no TCC prompt, since nothing is saved or fetched. Pinned by
  `CadenceTests.aTimedEventWithNoCalendarDrawsTheSharedFallbackNotABlankTitle` and
  `anAllDayEventWithNoCalendarDrawsTheSharedFallbackNotABlankTitle`; 2 mutations, 2 killed.

- [T-694] **The calendar access card's *title* still reads as a fault in the state that is not one.**
  [[T-543]] fixed the glyph and the sentence: before anybody is asked, both surfaces now draw a neutral
  `calendar.badge.plus` in `Theme.blue` over "Allow Cadence to show events and connect Apple calendars to
  areas or projects." The title above it still says **"Calendar access required"**, which is the last part
  of the card phrased as a demand rather than an offer — and the same string also heads the *denied* card,
  where it is right. Not folded into T-543: `CadenceCalendarSettingsCopy.accessRequiredTitle` is shared by
  both surfaces and pinned by value in two tests, and the notification pane's
  `CadenceNotificationSettingsCopy.accessRequiredTitle` is the same shape one screen over — so rewording it
  is a house-wide copy decision, not the tail of a glyph fix.
  **PARTIALLY CLOSED 2026-09-03 (`4cbd2fd`) — Notifications pane only.** User decision: two titles,
  one per state, demand phrasing reserved for denied. `NotificationManager` gained `isDenied`
  (mirroring `CalendarManager.isDenied`); both Notifications panes now draw the new
  `CadenceNotificationSettingsCopy.connectOfferTitle` ("Connect Notifications") before anyone has
  been asked and keep `accessRequiredTitle` ("Notification access required") for the denied state.
  **The Calendar pane's half is not done**: its card is in `SettingsListManagementSections.swift`,
  owned by another agent this batch, and the cross-platform copy-scan test
  (`bothCalendarSettingsSurfacesReadEveryConvergedCalendarString`) requires macOS and iOS to read
  the same constants, so an iOS-only edit would have broken that test rather than fixed the ticket.
  Residue filed as [[T-777]].
  **FULLY CLOSED 2026-09-03 (`663bc13`) — Calendar half via [[T-777]].** Both panes now move
  together; see T-777 below for the shape.

- [T-777] **T-694's Calendar pane still owes its offer title.** The Notifications pane split is
  done (see T-694, closed above): `CadenceNotificationSettingsCopy.connectOfferTitle` before
  asking, `accessRequiredTitle` kept for denied. The Calendar pane needs the same shape —
  `CadenceCalendarSettingsCopy` gains a `connectOfferTitle` ("Connect Apple Calendar"), and
  `SettingsListManagementSections.calendarAccessCard` (macOS) and `iOSCalendarSettingsSection`
  (iOS) both move their not-denied branch onto it, leaving `accessDeniedTitle` ("Calendar access
  denied") for the denied branch exactly as today. Both files must move together in one change:
  `CadenceSettingsSectionCopyTests.bothCalendarSettingsSurfacesReadEveryConvergedCalendarString`
  scans both surfaces for the same constants and fails if only one is edited.

- [T-703] **The six lifecycle section titles should become a composer now that [[T-555]] has landed —
  and the reason they are six literals is a constraint that no longer exists.** [[T-546]] hoisted
  `"Active Contexts"`, `"Archived Contexts"`, `"Completed Areas"`, `"Archived Areas"`,
  `"Completed Projects"` and `"Archived Projects"` to `CadenceListLifecycleSectionCopy` and
  deliberately **did not** build a `sectionTitle(_:of:)` composer. Its reason, recorded in `f6c3073`:
  `cadenceSharedStringConstants` harvested `static let` only, so an interpolated title would be
  invisible to the reuse sweep and a seventh site could re-type the literal with nothing to catch it.
  **`aca2a49` closed exactly that gap** — the harvest now reads a `static func` that picks between
  finished strings, flags zero formatters, and is pinned by a positive and a negative fixture. So the
  objection is spent, and the composer is now the better shape twice over: the titles already follow
  one rule (`"<status> <plural noun>"`, with the status word taken from `CadenceListSearchLifecycle`,
  pinned by `everyLifecycleSectionTitleFollowsTheStatusThenNounRule`), and **it is how [[T-690]]'s
  `.paused` and `.cancelled` projects get section titles at all** — today they reach no lifecycle
  section on either platform and can only be found through search.
  Note the interaction before starting: a template whose product is *assembled* is deliberately outside
  the harvest, because no call site can re-type an interpolated value verbatim. A composer that picks
  between finished strings stays inside it; one that interpolates a noun does not. Which of those you
  build decides whether the sweep still guards these six.
  **Considered and declined while closing [[T-690]], 2026-09-03.** `pausedProjects`/
  `cancelledProjects` were added as two more plain literals, not as the tail end of a composer. The
  "it is how T-690's titles get made at all" framing above turned out not to force the composer: two
  more `static let`s did the same job with no interpolation risk. A composer built the safe way (a
  `switch` returning finished strings, per this ticket's own closing note) would not have shrunk
  anything — the same eight branches, moved from eight declarations into one function — and would
  have made an invalid pairing constructible (`.paused` + `Context`, `.completed` + `Context`) that
  the current one-constant-per-real-case shape cannot express. Left open in case a future caller
  actually needs runtime composition rather than a fixed set; not needed by T-690.

- [T-704] **[[T-560]]'s leak was cleaned and its mechanism closed, but never reproduced — so it is not
  known to be fixed.** Two instrumented runs on 2026-09-02 (21 tests, 19 of them building and saving
  through an in-memory `ModelContainer` in the *unfixed* shape, plus a third of 40 tests after the fix)
  created zero `<app container>/tmp/<UUID>/inMemory_store_ckAssets` directories. **The leak is not
  dormant, though — it just never fires on the run doing the measuring.** 34 directories appeared
  between 18:23 and 19:15 on 2026-09-02, *after* the residue was purged, in two identical cycles of
  3 / 10 / 4 spaced 41 minutes apart: the signature of another agent re-running a fixed trio of suites,
  one directory per test. Not correlated with UI-test activity (`CadenceUITestStores` was busy
  17:35-18:16 and again from 20:14, the leak fell entirely between them).
  So something gates whether CloudKit mirroring initialises — an iCloud or network state, a
  `NSPersistentCloudKitContainer` setup path taken only sometimes, or simply a tree that predates
  `b31d0b9` — and it is not established. **The measurement is one line:**
  `ls -1 ~/Library/Containers/com.haoranwei.Cadence/Data/tmp | wc -l` before and after a run.
  The decisive observation is cheap and someone will make it for free: once `b31d0b9` is in every
  agent's archive tree, that trio either stops leaking or it does not. If the count climbs again with
  `CadenceTestStore` everywhere, the cause is somewhere other than `cloudKitDatabase` and
  `CadenceInMemoryStoreHygieneTests` is guarding the wrong thing — **and the 3 / 10 / 4 burst sizes are
  the best lead there is**, because they name the suites: find the three whose test counts are 3, 10
  and 4 in the tree that leaked.

- [T-705] **Nothing prunes an orphaned shared-DerivedData entry, and the judgement [[T-517]] said no
  script should make unattended is now mechanical.** T-517 declined to automate the cleanup because
  "one of the fourteen is the user's own Xcode entry" and telling them apart needed a human. Two
  discriminators now do it without one. **The cheap one:** an entry that has an `info.plist` carries
  `WorkspacePath`, so it is an orphan exactly when that path does not exist — no hashing required.
  **The one for entries with no `info.plist`** (all 13 of T-517's were in that state): Xcode's
  directory suffix is MD5 of the absolute project path, split into two big-endian `UInt64`s, each
  rendered as 14 base-26 letters most-significant digit last. Hash every `Cadence.xcodeproj` that
  exists and an entry matching none of them is unattributable to any live tree. Both were used to clear
  T-517 and both were positively controlled against the known-live entry first. A
  `scripts/xcb.sh audit --prune` built on them would refuse to touch an entry it could attribute, which
  is stricter than the human judgement it replaces. **Not done here because `scripts/xcb.sh` was being
  edited by another agent at the time** — this is a one-file change to a file with a live sibling, not a
  hard one.

- [T-706] **`/private/tmp/cadence-uitest-auth` is a 1.4 GB DerivedData directory, not an authorization
  store — and ~2.7 GB of other agent debris is still in `/private/tmp`.** The name has been read as
  "the one-time macOS UI-test automation grant, re-granting needs the user's password", and three
  briefs have carried that warning. **It is a `-derivedDataPath` output and nothing else**: `Build/`,
  `Logs/`, `ModuleCache.noindex`, `SDKStatCaches.noindex`, `SourcePackages/`, `TestResults/`, and an
  `info.plist` whose only two keys are `LastAccessedDate` (2026-08-31T04:52:39Z) and `WorkspacePath`
  (the user's real repo). macOS automation and accessibility grants live in the TCC database, not in a
  build directory, and UI-test runs since have used entirely different DerivedData paths. **Left in
  place anyway**, on the asymmetry: the downside of being wrong is the user's password, the upside is
  1.4 GB of temp space, and an agent was live in `CadenceUITests` at the time. Someone should confirm
  and delete it. The rest of `/private/tmp` is ordinary session debris nobody named — `a2-*`, `b1c-*`,
  `base_*.swift`, `bf`, `ff.log`, `TODO.backup.md`, `.old.swift`, `.void`, `dry1.sh` — plus live
  sibling scratch trees (`cadence-g2`, `cadence-g3`, `cadence-g4-scan`, `cadence-integ10`) that must
  **not** be swept while their agents are running.

- [T-707] **The iOS build reaches CI only if a human ticks a box, and CI does not run.**
  From [[T-535]]. `.github/workflows/ci.yml` has an `ios-build` job filed under T-535's name, but it
  is gated on `github.event_name == 'workflow_dispatch' && inputs.run_ios`, and the file's own header
  says "PROPOSAL. Nothing runs until Actions is enabled on this repository." So the only iOS gate that
  actually executes today is the third verification command in `docs/apple-release-readiness.md`, run
  by whoever is doing a release. The workflow already states the blocker for doing better — a per-job
  `paths:` filter does not exist, so running it automatically on pushes that touch `Cadence/iOS/`
  needs a cheap ubuntu `changes` job emitting an output the `if:` reads, or a third-party
  paths-filter action and the supply-chain surface that brings. **Decide it rather than leaving it in
  a comment**, and note the cost the file records: ~6-10 billed runner-minutes per iOS run.

- [T-709] **`CadenceBuildInvocationHygieneTests` sweeps `.md` and `.sh`, and CI is `.yml`.**
  From [[T-535]]. `scannedPaths()` appends a file only when it `hasSuffix(".md")` or `hasSuffix(".sh")`,
  so `.github/workflows/*.yml` is outside the walk entirely — and those files contain `xcodebuild`
  invocations. **There is no live offender**: every invocation in `ci.yml` goes through
  `scripts/xcb.sh`, which supplies a private `-derivedDataPath` itself. The gap is that nothing would
  notice a future workflow step calling `xcodebuild` directly. The `xcodebuild` in a YAML `run:` block
  is shell, so `shellText(at:)` would need a third branch (a script is shell throughout, markdown only
  inside fences, YAML only inside `run:` blocks) — the extraction is the work, not the walk.

- [T-722] **Drag-to-create has never been observed, and the simulator can now do the gesture.**
  Was item 4 of `docs/device-checks.md`; it left that list in [[T-561]] because `control`'s
  `touch_path` drags a single finger along an arbitrary path *including long-press-then-drag*, which
  is every gesture the item asked for, and `attach` opens a live panel to watch the mid-drag ghost
  in. Since [[T-171]] neither `+` uses a system drag: both run one custom `DragGesture` through
  `CadenceCapturePressResolver`, hit-testing frames the targets publish to
  `iOSNewTaskDropFrameRegistry`. **Everything computable is already pinned** in
  `CadenceCapturePaletteTests`, `CadenceTaskDropSupportTests` and `CadenceTaskGroupDropSupportTests`
  -- but `iOSNewTaskDropFrameRegistry` itself is referenced by **no test**, and whether the frames it
  publishes land where the eye sees the rows is the whole remaining question. Five things to see:
  (1) press the `+` in the tab bar and move immediately, drop on a task row -- the composer opens
  pre-filled with that row's list, section and dates; (2) press and *hold* without moving -- the
  palette blooms, sliding between segments selects, and it does **not** turn into a drag; (3) drop on
  an **empty** group's header -- seeded from the group, which is the case the feature was built for
  and the one where a published frame is most likely to be wrong; (4) mid-drag a dashed "New task"
  ghost opens **between** rows and names what it will inherit, rather than highlighting an existing
  task; (5) a plain tap afterwards opens the composer instantly, unseeded. If an abandoned drag
  leaves the tab bar unresponsive, say so -- that was a known simulator side effect and it is worth
  knowing whether it still happens. Belongs with the queued simulator batch alongside [[T-447]].
  **CLOSED 2026-09-03.** Driven on iPhone 17 Pro / iOS 26.5; **all five predicates pass.** The
  frames `iOSNewTaskDropFrameRegistry` publishes land where the eye sees the rows: a drop on a task
  row seeded the composer with that row's list, section **and** date; a drop on an **empty** column
  header — the case most likely to publish a wrong frame — seeded list and section correctly. Press
  and hold still blooms the arc, sliding onto a segment highlights it without converting to a drag,
  and lifting in the dead zone does nothing. The mid-drag ghost opens **between** rows and names
  what it inherits, never highlighting the existing task. A plain tap and a drop on nothing both
  open unseeded. **The abandoned-drag tab-bar freeze did not reproduce** in five drags.
  **The one thing [[T-561]]'s triage did not know:** a `touch_path` is **atomic** — down, move and
  lift in one call — so nothing mid-gesture can be screenshotted from the tool, which only ever
  sees the end state. The ghost and the bloomed palette were captured with a background
  `xcrun simctl io <udid> screenshot` loop running across the gesture. **That recipe is now in
  `docs/device-checks.md`**; without it the next agent reports "the ghost could not be seen".

- [T-723] **Two note-editor taps have never been observed, and together they are one simulator
  session.** Were steps 3.3 and 3.4 of `docs/device-checks.md`; they left the phone list in
  [[T-561]] because both are single taps, which `control`'s `tap` performs. Single-tap plain text --
  the caret lands there. Tap a `[[wiki link]]` or a task-embed card -- it opens. Which target a
  location resolves to is already pinned by `MarkdownReferenceDisplaySupportTests`
  (`referenceRangesPointAtVisibleDisplayText`, `inlineSegmentsPreserveReferenceTargets`), so the
  residue is one tap and one screenshot each. The *double*-tap pair deliberately stayed on the device
  list: the simulator surface has no double-tap action at all.
  **CLOSED 2026-09-03.** Both taps observed on iPhone 17 Pro / iOS 26.5.
  **Caret: measured, not eyeballed** — tapped mid-line, then typed `@@@`, and the characters landed
  at the tap rather than at the end of the text. **Wiki link:** one tap on a rendered `[[Notepad]]`
  opened the linked-note sheet with its backlink present. **Task embed:** one tap opened Edit Task
  from both spellings — the standalone card and the same reference drawn inline.
  Found [[T-734]] on the way, which is the reason this was worth driving rather than reasoning.

- [T-728] **The collapsed rail's slot has no asserted relationship to the label it holds.**
  `collapsedRailLabelSlotHeight = 96` is a constant; the rotated `UNSCHEDULED` run measures **88pt at
  the loosest [[T-496]] candidate** (83 at the tightest). Measured 2026-09-02.
  **The reason this needs a test rather than a comment: rotation is a render transform, so an overhang
  cannot fail layout.** A longer rail name, a heavier weight or a tracking change would push the run
  past the slot and nothing would go red — it would simply draw over its neighbour. A macOS test can
  measure the advance (`NSAttributedString.size()` and `ImageRenderer` agreed exactly today) and assert
  it against the constant with real headroom.

- [T-729] **The collapsed rail's slot width is derived from the wrong figure.** It is
  `.frame(width: CadenceBoardColumnHeaderMetrics.labelSize)` — the **point size, 10** — while the
  rotated line is **13pt tall**, so the glyph run overhangs the frame about 1.5pt each side. Harmless
  at today's 60pt rail and not a visible defect; wrong as a derivation, because a font's line height is
  not its point size and the two only coincide by accident. Found while measuring [[T-496]].

- [T-730] **macOS visual verification is unavailable whenever the user's own Cadence is running, which
  is most of the time.** Measured 2026-09-02: `scripts/run-macos-app.sh start` refused with exit 3 —
  *"REFUSING: the user's own Cadence is running. Do not add a second writer."* — against an app that had
  been up since 31 August. **The refusal is correct**; the alternative is a second writer on the user's
  real store, which has hung an instance for fifteen hours. But it means every "screenshot the Mac app"
  ticket is unrunnable in the common case, and an agent discovers this only after a full build.
  Two fallbacks exist and neither is sanctioned in writing yet: **`XCUIScreenshot` under the test-host
  lock** (the UI target runs since [[T-563]], launches its own copy against a private store, and is the
  only route that captures real app chrome), and an **offscreen `ImageRenderer` harness** transcribing
  the draw site's modifier chain (exact for type, tracking and advance; cannot tell you the components
  are wired together as the source says). Recorded in `docs/SUBAGENT_RUNBOOK.md` today; what is open is
  whether to build the first one properly.


- [T-731] **The `isRegularWidth == true` branch of the iOS editor sheets is dead on the iPad anyone
  has measured, and the two checks that would settle it outright are out of tooling reach.**
  OBSERVED 2026-09-02: at 834pt, `iOSLinkedNoteEditorSheet`, `iOSEventNoteEditorSheet` and
  `iOSCalendarEventEditSheet` all rendered **compact**; the sheet measures ~577 x 639pt, and a plain
  `.sheet` is a form sheet on iPad, which UIKit hands a compact horizontal size class. Re-checked
  2026-09-03: **all four presentations are still plain `.sheet`** — `iOSSearchView` ×2,
  `iOSNotesView`, `iOSCalendarMonthAgendaViews`, `iOSCalendarInspectorView`,
  `iOSCalendarEventEditSheet` and `iOSMarkdownReferenceSupport` — with **no `.presentationSizing`
  and no `.presentationDetents` anywhere under `Cadence/iOS/`**. So the 320pt rail, the 24pt title
  and `iOSEditorSheetMetrics.gutter(isRegularWidth: true)` are unreachable there, and the pixel half
  of [[T-492]] / [[T-283]] is moot.
  **Landscape and a 13-inch iPad are still NOT observed, and this is why rather than a shrug**
  (2026-09-03): `xcrun simctl` has no rotate — `simctl ui` offers only appearance, increase_contrast
  and content_size, and `simctl status_bar` only time/network/battery — the simulator control
  surface has no rotate action either (`button` is HOME/LOCK/SIRI/SIDE_BUTTON/APPLE_PAY), and the
  host Simulator app, which does have Device → Rotate, is off limits. Every 13-inch iPad in the
  fleet is **shut down**, `simulator-claim.sh boot` starts iPhones only by design, and the
  one-device rule stands. The one route left is a UI test on an iOS Simulator destination setting
  `XCUIDevice.shared.orientation`: `CadenceUITests` does list `iphonesimulator` in
  `SUPPORTED_PLATFORMS`, so it is possible, and it was judged too much scaffolding for a decision
  ticket. **Whoever settles this should take that route.**
  **One measurement settles both at once**: the sheet's width against the host's. If a 577pt sheet
  stays 577pt in a 1194pt landscape host, the presentation is a fixed size and no iPad reaches
  768pt; if it scales, the branch is alive on the big iPads only — which is the *worst* outcome,
  because the layout would then turn on a device threshold nobody wrote down.
  **RECOMMENDATION, reasoned rather than observed, and deliberately not acted on**, because changing
  how a sheet presents is a visible design change: **give these three editors the wider presentation
  rather than deleting the regular branches.** Three reasons. (1) The app already set this
  precedent — `iOSNotesView` and `iOSListNotesView` present their own note editor as a
  `.fullScreenCover`, so "a note editor on iOS is not a form sheet" is a decision this codebase has
  taken once already. (2) `iOSCalendarEventEditSheet.regularFormLayout` needs
  `primaryColumnMinWidth 340 + groupSpacing 16 + secondaryColumnMinWidth 360` = **716pt of content**
  before gutters, which no form sheet on any iPad will hand it; `.presentationSizing(.page)` is the
  smaller change and probably still would not clear it in portrait, which is precisely the
  device-dependent outcome above. (3) Deleting the branches throws away [[T-281]] / [[T-283]] /
  [[T-492]] and buys nothing a wider presentation does not also buy.
  So: full-screen on iPad for these three, then re-measure — **not** `.page`, and **not** a deletion.

- [T-732] **`docs/device-checks.md`'s keyboard-dismiss item rests on a premise that is false on this
  fleet.** It says the simulator suppresses the software keyboard while a Mac keyboard is attached.
  OBSERVED 2026-09-02: the full software QWERTY came up unprompted in Cadence's new-task composer on
  the claimed iPad. If the keyboard is available, the `keyboardDismissMode = .interactive` check is a
  downward `touch_path` on the note text — a simulator job, not a phone one.
  **This is the same shape as [[T-280]]'s premise, which was also false and also load-bearing**: an
  item stayed on the hardware list for weeks because of an untested claim about the tooling rather than
  about the app. Re-triage before anyone carries it to a device.

- [T-742] **CLOSED 2026-09-03 by the coordinator.** [[T-621]] wrote and tested
  `CadenceFocusLedger.reconcile(in:)` and could not wire it, because
  `Cadence/Services/PersistenceController.swift` belonged to a sibling agent in the same batch —
  the file-ownership rule working, at the cost of one line. Both owners finished, so it is wired
  now, in `performStartupMaintenance` beside the integrity repair and folded into `changedStore`.
  **One correction to the line this ticket prescribed:** `reconcile(in:)` answers `Bool`, not a
  count, so the `changedStore` term is the answer itself and not `> 0`. Caught by the compiler
  on the first build, which is the cheap end of the T-565 class — a ticket describing an API it
  did not re-read.
  Safe at launch by the same argument the repair above it uses, and the comment says so: the pass
  only ever raises and is a pure function of the counter and the ledger rows, so a launch racing
  the first CloudKit import computes a total that is too low and leaves the counter alone.
  macOS build green, 0 errors, 0 warnings.

- [T-743] **Merging two duplicate lists strands the surviving list's focus ledger.**
  `DataIntegrityRepairService.mergeArea` / `mergeProject` reconcile `loggedMinutes` with
  `max(target, source)` and re-point the duplicate's tasks, notes, documents, links and goal links —
  but `Area.focusSessions` / `Project.focusSessions` are new with [[T-621]] and are not in that list.
  So the duplicate's `FocusSessionLog` rows keep pointing at a row that is about to be deleted, and
  the survivor's counter can no longer be explained by its own rows.
  **The consequence is bounded by the only-ever-raise rule**: `reconcile` cannot lower the survivor,
  so nothing is destroyed — the ledger is merely blind to the merged half, and future sessions
  rebuild from the surviving counter. Still worth re-pointing, and it is a two-line addition beside
  the re-points already there. Same shape as [[T-621]]'s own note that a new to-many on an existing
  model has to be walked by everything that walks the old ones.

- [T-744] **Nothing collects a `FocusSessionLog` whose subject was deleted.**
  [[T-621]] gave the three focus counters `.nullify` delete rules on purpose: deleting a task has
  never decremented its list's `loggedMinutes`, and a cascade would have started doing exactly that
  the next time `reconcile(in:)` ran. The cost is that deleting a task or a list leaves its rows
  behind with every subject reference `nil`.
  They are inert — `reconcile` skips a row with no subject, and `CadencePrivacyDataResetService`
  deletes them with everything else — so this is storage and CloudKit records, not wrong numbers.
  It is also **exactly the orphan sweep [[T-328]] argues `DataIntegrityRepairService` must not
  grow**: "this row has no subject" is indistinguishable from "its subject has not synced yet", and
  the emptier the store the more it would delete. So the honest options are a sweep gated on
  something that knows sync finished, or a user-initiated pass — not four more lines in the startup
  repair. Filed so the boundary is written down rather than rediscovered.

- [T-745] **`CadenceDefaults` covers `@AppStorage` and the calendar memory, and nothing else.**
  [[T-735]] routed every `@AppStorage` through `defaultAppStorage` on the scene and pointed
  `CadenceCalendarDateMemory` at the same store, which is what the incident ran through. It does not
  reach the direct `UserDefaults.standard` calls in the service layer:
  `NotificationManager.reconcile`'s `notificationsEnabled` read, `DataIntegrityRepairService`'s
  `dataIntegrityRepair.lastReport.v1`, `MarkdownNoteSupport`'s `NoteTemplateLibrary.storageKey`,
  `PursuitToGoalMigration`'s completion flag, `PersistenceController`'s pending/failed-restore
  records, and `CadenceUITestSupport.resetUserDefaults`. Most already take a `defaults:` parameter
  defaulted to `.standard`, so the change is mechanical — but `PersistenceController.swift` is a hot
  file and `NotificationManager` cannot exist in the command-line target, so it wants doing
  deliberately rather than as a sweep.
  Second gap, same family, cheaper to state than to fix: **an app started by tapping its icon on the
  simulator carries no launch arguments**, so it is back on the device-wide domain. Both are written
  down in `CadenceDefaults`'s doc comment; this ticket is the decision about whether to close them.

- [T-746] **CLOSED 2026-09-03 as not-a-defect — the contradiction was already gone when it was
  filed.** The claim was that `AGENTS.md` and `CLAUDE.md`, both always-read, give opposite
  instructions about `CadenceUITests`: one saying it was never flaky, the other saying it flakes
  about 1 run in 4 and a red run is not evidence.
  Checked rather than taken: **`4b447ff` ([[T-563]]) rewrote both files in the same commit**, and
  it landed *before* the agent that filed this started. `AGENTS.md:156` and `CLAUDE.md:84` now say
  the same thing. The only surviving "about 1 run in 4" is inside `CLAUDE.md`'s explanation of
  **how that misreading arose** — the activation failure is attributed to whichever line called
  `app.launch()`, so it read as an intermittent timeout — and both files end on *a red UI-test run
  **is** evidence of a regression again*.
  Worth keeping the entry rather than deleting it: a sentence that recounts a superseded belief
  reads like the belief when skimmed, which is the [[T-565]] class one level up. If it is misread
  a second time, that is the argument for moving the history out of the always-read file.

- [T-747] **`scripts/xcb.sh` writes every run under one id to the same log path, so a batch deletes
  its own evidence.** The log is `${TMPDIR}cadence-xcb-<id>.log`, overwritten per invocation. A
  runner that makes three `xcb.sh j4 test …` calls in sequence — which is the shape the runbook asks
  for, one script, one lock, several runs — ends holding only the last one's log. The postflight
  counters go to stdout and survive, but they are aggregates: measured 2026-09-03, a run reported
  `warnings: 23` and by the time the count was queried the log naming those 23 was gone, so the
  number could not be attributed to a file — and "a warning count from a run that did not recompile
  the file is vacuous" is already a rule in `AGENTS.md`, which this makes unverifiable after the
  fact. The counters are the summary; the log is the evidence, and it is the evidence that gets
  deleted. Cheapest fix is a per-invocation suffix with the documented path kept as a symlink to the
  newest.

- [T-736] **A column being renamed draws as empty until the rename commits.** Filed while landing
  [[T-713]], and it is the visible cost of the decision that ticket took rather than a defect in it.
  `KanbanListSectionSupportViews.sortedTasksForSection` groups the board by
  `resolvedSectionName.caseInsensitiveCompare(section.name)`, and [[T-645]] writes the *config's*
  name on every keystroke while [[T-713]] moves the *cards* only at the commit point — so from the
  first character until Return or focus leaving the field, the column the user is typing into has no
  cards in it. They come back on the commit.
  This is strictly better than what it replaced: before [[T-713]] the column also emptied, from the
  second keystroke, and **never** refilled, because the cards were stranded on a name no column had.
  Transient is not free, though, and the fix is not "move sooner" — that is the bug. Candidates: group
  the board by the column's `uuid`-stable identity for the duration of an open editor, or have the
  editor publish the name the cards are still under so the column can draw them.
  **Not observed.** Reasoned from the two call sites; nobody has watched a rename being typed.

- [T-737] **The editor's Archive and Mark-Completed settle on the *config's* name, so pressed
  mid-rename they settle nothing.** Same family as [[T-713]] and **not** introduced by it — the
  config's name has advanced per keystroke since [[T-645]].
  `TaskContainerLifecycleService.tasks(in:area:project:)` filters on
  `resolvedSectionName.caseInsensitiveCompare(section.name)`, and `toggleSectionArchive` /
  `saveSection` both hand it `section` — the live config. Type two characters into the name field and
  press Archive without committing: the flag flips and `cancelRemainingActiveTasks` walks a name no
  card carries, so the column archives with its stack untouched. `editSnapshot(settling:)` takes the
  same walk, so the undo for a refused commit snapshots zero cards as well.
  Whether it is reachable in practice turns on the open question in [[T-714]] — whether pressing a
  button in a macOS popover moves focus off the `TextField` and fires `onNameCommitted` first. That
  is still unverified by observation, so this is real until someone looks.
  [[T-713]] gave the column a `filedCardName` for exactly this question; the fix is probably to hand
  the lifecycle walk a config wearing that name. Not folded in because it is the completion and
  archive paths, which four suites pin.

- [T-738] **Every keystroke of a column rename rewrites the container's whole section blob.** Noticed
  while reading for [[T-713]]. `applySectionEdits` runs per character and calls
  `applySectionConfigEdits`, which assigns `sectionConfigs = merged(...)` **unconditionally** — unlike
  `mutateSectionConfigs`, which guards on `merged != current`. The guard would not help here anyway,
  since each keystroke genuinely is a change.
  So renaming a column to a ten-character name rewrites `sectionConfigsRaw` ten times and dirties the
  `Area`/`Project` ten times, and each is a CloudKit record push. [[T-645]] chose the per-keystroke
  *write* deliberately, so the board's header tracks the field; nothing about that choice required the
  write to reach the persisted blob every time. Candidate: keep the header on the field's own value
  and let the blob take the name at the commit point, which is where the cards go since [[T-713]].
  **Not measured.** No CloudKit traffic was observed; this is read off the two write paths.

- [T-751] **The thing that keeps [[T-623]] cheap is an accident, and nothing pins it.** [[T-623]] is
  parked because a child row that outlives a list cascade is inert at every read site — but each of
  those filters was written for an unrelated reason and none of them names partial deletion.
  `GoalLinkPresentation.links(of:)` filters `area != nil || project != nil` to avoid a cosmetic
  "Missing List" row; `GoalContributionSummary.swift:114` filters the same way to keep
  `linkedListCount` honest; `CadenceReadService.swift:1144` mirrors it for the MCP DTO;
  `DataIntegrityRepairService.repairDuplicateHabitCompletions` skips a habit-less completion only
  because it groups by `habit.id`; `LinksView` and `iOSListSupportViews` filter saved links by owner
  id because that is how a per-list panel is built at all.
  Remove any one of them for a good local reason and [[T-623]] silently becomes a visible-corruption
  bug — a "Missing List" contributor inside a goal's percentage, a phantom saved link — with no test
  going red and a parked ticket saying it does not matter.
  The ask is one suite that asserts the inertness *as the invariant it now is*: an owner-less
  `GoalListLink`, `HabitCompletion` and `SavedLink` in a store, and every surface that could show
  one showing nothing. Same shape as `CadenceInMemoryStoreHygieneTests` — the property is already
  true, and the test is what stops it quietly stopping.

- [T-752] **The app's one "these counts may be wrong" sentence hard-codes which way it is wrong.**
  `CadenceNoteDeletionSummary.unknownImpactNotice` is *"Couldn't check everything this delete
  touches. It may remove **more** than the counts below show."* Both delete confirmations read it,
  and `bothDeleteConfirmationsShareOneUnknownImpactSentenceAndOneRow` pins that there is exactly one
  of it and one row for it — deliberately, so a second wording cannot appear.
  That is right for the case it was written for (a failed fetch, which only ever moves the loss
  upward), and it leaves the app with nothing to say in the opposite case. [[T-623]] is exactly the
  opposite case: the delete removes *less* than the user was led to expect, and `isEmpty`'s "nothing
  else is filed here" is the strongest claim on that screen and the one most able to be wrong.
  Nobody should discover this by writing a second sentence and finding a test in the way. Either the
  notice becomes directionless ("Couldn't check everything this delete touches"), which costs the
  one thing its own doc comment argues for — *"There is no wording of 'something went wrong' that
  stops a user reading '0 embedded images' as 'no images'"* — or the type grows a direction and the
  one-sentence rule becomes a one-sentence-per-direction rule.
  **Not actionable on its own**, and filed as a constraint rather than a defect: whoever picks up
  [[T-623]] or any successor hits this before they write a line of UI.

- [T-754] **41 more sites spell `Theme.radiusControl` (10) as the bare literal `cornerRadius: 10`,
  plus one more named constant that does the same** (`kanbanColumnCornerRadius` in
  `KanbanBoardSupport.swift`, sitting right next to the `kanbanCardCornerRadius` [[T-616]] just
  converted). Found while sweeping [[T-616]]'s "7" — unlike that ticket, no naming decision is
  needed here: `Theme.radiusControl` already exists and already means 10. This is a plain hoist, not
  a "should this be a step in the scale" question, and it was left alone because converging 41 call
  sites onto a shared token is its own review, not a rider on a "7" ticket. `Theme.radiusCard` (18)
  and `Theme.radiusPanel` (22) were checked the same way and have **zero** bare-literal sites —
  10 is the only tier still leaking.

- [T-755] **A `*Radius: <n>` sweep pattern will false-positive on `CadenceWidgets/WidgetChrome.swift`'s
  `elevationRadius`.** Found and caught by `CadenceRadiusControlCompactSweepTests` mid-development
  ([[T-616]]): a first-draft detector matched any identifier ending in `Radius`, and `elevationRadius`
  matched the "7" case at one of its four widget-size tiers. It is a `shadow(radius:)` **blur**
  radius, not a corner radius, and scales 5/6/7/8 across the four sizes — real scatter, a deliberate
  per-tier value, not "one origin copied N times." The shipped detector requires `cornerRadius`
  (bare or as a `*CornerRadius` name) or `radius`/`xRadius`/`yRadius` exactly, which does not match
  `elevationRadius` — but the next person writing a radius sweep by hand, rather than reusing
  `CadenceRadiusControlCompactSweepTests`' pattern, can make the same near-miss. Filed so the
  distinction (corner radius vs. shadow blur radius, both spelled `*Radius`) is written down
  somewhere other than a test's inline comment.

- [T-748] **An orphaned `acquire` still takes the lock with nobody left to run under it.**
  [[T-650]] made it wait its turn instead of jumping the queue, which is strictly better and not the
  fix: `pkill -f 'run-batch-<tag>.sh'` does not match the runner's `test-host-lock.sh acquire ...`
  child, so the orphan keeps waiting, reaches the head, records its own already-dead pid as the
  owner and strands the lock for the full 2700s lease. `docs/SUBAGENT_RUNBOOK.md` documents the
  manual cleanup, which means it keeps happening. The candidate fix is four lines and was
  deliberately not landed in [[T-650]]: at the moment of `mkdir`, refuse if `$PPID` is dead, because
  a waiter whose parent is gone has nothing to hold the lock *for*. It was left out because three
  sibling agents were mid-run against the live lock, and a new refusal on the acquire path is
  exactly the change you do not ship into that. Land it on a quiet tree, with a selftest trial: a
  waiter whose parent is killed must decline the lock rather than take it.

- [T-749] **`scripts/simulator-claim.sh` has the unfairness [[T-650]] just removed from the test-host
  lock.** Its wait loop is `sleep 5; (( waited += 5 ))` with no queue and no ageing - the same shape,
  and the same consequence: a 16-minute claim wait was measured in the same batch that produced the
  65-minute test-host starvation. There is now a working pattern to copy one file over, ticket
  directory and all, including the parts that are easy to get wrong (the queue must live outside the
  claim it guards, the prune must be liveness-and-age, a pruned live waiter must re-file under its
  original stamp). Not urgent while only one simulator is in play, and cheap the day two are.

- [T-786] **`scripts/mutate.sh` cannot verify a mutation against a `@Test("...")` display-named
  test.** Found while fixing [[T-667]]. `FAILED_SWIFT_TESTING = re.compile(r"✘ Test
  ([A-Za-z0-9_]+)\(\)")` and `classify_run`'s `missing = [t for t in tests if ("Test %s()" % t) not
  in log and ("%s]" % t) not in log]` both assume a test's function name appears literally in the
  log; for a `@Test("...")` case it never does (swift-testing prints only the quoted display name),
  so a `tests=` plan naming one always reports `TEST-ABSENT` even when the test genuinely ran and
  passed or failed. `SUITE-ABSENT`'s `if suite not in body` has the same blind spot for a suite
  carrying a `@Suite` display name. Affects `ListDetailPageTests`, `RootModalKeyDispositionTests`,
  `MarkdownTableMobileEditingTests`, and any display-named case in `CadenceTaskComposerLayoutTests.swift`
  — 52 tests across 5 files. `scripts/test-suite-index.sh --labels` now carries the exact
  function-name → display-name mapping this needs; `classify_run` would have to resolve each
  planned test/suite name through it before checking presence. Not fixed here: this sits inside
  `mutate.sh`'s verdict logic, which carries its own extensive `selftest`, and reworking it under
  this batch's time budget risked the load-bearing tool rather than the finding. `TEST_RESULT`
  itself (the aggregate zero-test count) is already fixed the same way as `xcb.sh`'s.


- [T-783] **[[T-687]] part (2), refiled: the same untrimmed ternary on a `name`, 7 live sites.**
  T-687 part (1) is closed — the 27 constant-fallback title sites are routed and swept. Part (2) is
  not, and is scoped out of that sweep by construction: `CadenceEmptyTitleFallbackSweepTests`'
  needles capture `[A-Za-z0-9_.]*[Tt]itle`, so an identifier ending `name`/`Name` is invisible to
  both of them. The seven measured by T-609: `GoalsSupportViews.swift:434` and
  `TaskBundlePickerSupportViews.swift:320` (`task.containerName` → "Inbox"),
  `CadenceSearchCandidateSupport.swift:60` (→ "Inbox"), `GoalListLinkHelpers.swift:103` (→ "No
  Context"), `iOSCalendarEventEditSheet.swift:395` (→ "Unknown calendar"), `iOSRootSidebar.swift:776`
  (`item.name` → "Untitled"), and `iOSColumnWindDownSupport.swift:50`, which is the
  trimmed-test/untrimmed-return spelling on `config.name`. `iOSSettingsContextSection.swift:78` is
  the correct hand-spelling and is the control. Re-measure before sweeping: the `name` family has
  its own real-value fallbacks the way the title family did.

- [T-784] **CLOSED 2026-09-03.** A stale needle, not a regression, and the code was correct the
  whole time. `noCalendarSurfaceStillSpellsTheNewEventFallback` required
  `onCreateEvent?(CadenceEventTitleSupport.storedTitle(title)` to be **adjacent**, and
  [[T-658]] reflowed that call across several lines to capture the returned
  `CalendarWriteFailure?`. The needle now tolerates the break.
  **Adjacency was never the claim** — which function wraps the title is. A regex that pins
  formatting alongside the thing it means to pin goes red on a change that preserves
  everything it asserts, which is the [[T-565]] class in a test rather than a comment.
  Found twice independently: by the merged-HEAD pass and by an agent running a full suite,
  which is the argument for fixing it rather than teaching people to ignore it.

- [T-785] **Two scans left reading wider than they now need to, both unblocked by [[T-668]].**
  (1) `MarkdownNoteSupport.resolved(_:with:)` holds the last two constant-fallback ternaries in the
  app — `override.title.isEmpty ? template.title : override.title` and the `subtitle` twin — and is
  the one measured exemption in `CadenceEmptyTitleFallbackSweepTests`. They fall back to the
  *template's* own value rather than to a placeholder, and both sides are **stored** strings, so
  trimming there rewrites what a user saved. Decide the override-merge semantics, then either route
  them or say in the exemption why they stay.
  (2) `CadenceDeleteConfirmationCommitTests` scans `CadenceTaskMutationSupport.swift` whole because
  the pre-T-668 reader could not read `deleteTasks`. It can now, and `CadenceSourceScan.declarationBody`
  is the call. It is not a mechanical swap: the needle there spans `processPendingChanges()` **and**
  the gate, which is a claim about adjacency, so narrowing it needs the ordering claim restated
  rather than the span shrunk.

- [T-789] **The icon-only detector's positive witness is a file the ledger is emptying.**
  `CadenceIOSControlAccessibilityTests.theIconOnlyButtonDetectorSeesABareGlyphAndLeavesALabelledOneAlone`
  asserts the detector `fires(on:)` `Cadence/macOS/Views/TasksPanelSupportViews.swift` — T-637's
  half of the test, the one that proves the widening reached the desktop tree. That file is only a
  witness while it still holds an unnamed icon-only button, and [[T-673]] is removing its last two.
  Measured 2026-09-04 in the shared checkout mid-batch: with T-673's and [[T-674]]'s edits in the
  tree the assertion is already red, and it is red for the *right* reason — the file got fixed.
  The `including:` witness in the sweep above is fine (it is a claim about the **walk**), so only
  the `fires(on:)` line needs re-pointing, at a literal fixture rather than at a file the next
  ticket will clean. This is the [[T-161]] shape one layer out: a detector self-check that a
  *successful* fix turns red.

- [T-790] **The search field itself is the next near-copy, four rows deep.** Found closing
  [[T-672]], which unified the clear button and left the row around it duplicated.
  `ContainerPickerSupportViews`, `TasksPanelSupportViews`, `TaskTitleInlineTagPicker` and
  `TildeContainerPicker` each spell the same row by hand: an 11pt `magnifyingglass` in `Theme.dim`,
  a `.plain` `TextField` at 12pt in `Theme.text` bound to a `@FocusState`, the shared clear button,
  and `.padding(.horizontal, 12).padding(.vertical, 8)`. `CadenceCalendarPicker`,
  `CadenceContextPicker` and `GoalPickerViews` draw a 12pt variant of the same thing with a
  `Theme.surfaceElevated` background and a radius-8 clip. Seven rows, two shapes.
  Not folded into T-672 deliberately: the clear button is one control with one behaviour, and a
  search **row** carries a placeholder, a submit action, arrow-key handling and an escape hatch
  that differ per picker — which is a parameter list to design, not a hoist to perform.

- [T-791] **A named copy is invisible to a naming ledger, so `knownUnnamedIconButtonSites`
  understates duplication by construction.** [[T-672]] was filed over ten sites and found eleven:
  the eleventh already had `.cadenceControlLabel("Clear search")`, so no rule keyed on a missing
  name could see it, and a fix that trusted the ledger would have left one hand-spelled copy of the
  control it was consolidating. The two remaining follow-ups are the same shape — [[T-673]]'s
  "remove this row" glyphs and [[T-674]]'s icon-button helpers are both idioms that plausibly
  appear elsewhere *with* a label. Before either closes, sweep for the **shape** rather than for
  the gap: the population a duplication ticket has to fix is not the population an accessibility
  sweep reported.


- [T-798] **The five App Store screenshot candidates still do not exist, and the only thing missing
  is an unlocked screen.** Everything else landed: `docs/screenshots/seed-screenshot-data.py` drives
  a built `CadenceMCPServer` against a throwaway `CADENCE_MCP_STORE_URL` and seeds 27 presentable
  tasks (timed across today, spread over the next four weeks, two already completed, eight tags) plus
  a markdown daily note, a weekly note and a permanent note — measured 2026-09-04, `list_tasks`
  answers `totalCount=25` open with the two done excluded. `docs/screenshots/flatten-for-app-store.py`
  turns a window capture into an alpha-free RGB PNG at one of Apple's four accepted macOS sizes, and
  `docs/screenshots/README.md` carries the procedure. What could not be done is the capture itself:
  the Mac's screen was locked for the whole session (`CGSSessionScreenIsLocked=Yes`), and a locked
  screen defeats **both** capture routes, not just the documented one. Measured: the app launched by
  `scripts/run-macos-app.sh` reaches its run loop and creates a real 1046x649 `CGWindow` named
  "Cadence", but `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly` cannot see it, AX reports
  `count of windows = 0`, `set frontmost to true` silently does nothing, `screencapture -o -l<id>`
  answers `could not create image from window`, and ScreenCaptureKit — which *does* find the window
  in `SCShareableContent` — fails `SCScreenshotManager.captureImage` with
  `SCStreamErrorDomain Code=-3811`. That is the same T-563 condition `scripts/xcb.sh` refuses UI runs
  under, so the fix is "run this while the Mac is unlocked", not code. Remaining work is one command
  per angle plus the Kanban angle's manual list creation, which the README spells out.

- [T-799] **Nothing in `CadenceMCPServer`'s write surface can create a context, an area or a
  project, which is why the Kanban screenshot angle cannot be seeded and has to be clicked.**
  `CadenceMCPToolDefinitions.swift` exposes `create_task`, `update_task`, `schedule_task`,
  `complete_task`, `reopen_task`, `cancel_task`, `bulk_cancel_tasks` and `append_core_note` and
  nothing else that writes; `create_task` takes a `containerId` but has no way to mint one, and its
  `sectionName` is rejected unless the section already exists on the target list. Kanban columns are
  `TaskSectionConfig` values stored on `Area`/`Project` (`Cadence/Models/AppTask.swift`), so a board
  cannot exist without a container a tool can create. Filed as a note on the MCP surface's shape
  rather than a request: adding container writes is a real decision (they cascade into task
  ownership and section normalisation), and the screenshot work only needs it once.

- [T-868] **Two more reorders swallow the save that [[T-614]] just decided.**
  `TasksPanelSupport.reorderTask` (`Cadence/macOS/Views/TasksPanelSupport.swift`) and
  `SidebarComponents.reorderList` (`Cadence/macOS/Views/SidebarComponents.swift`) each renumber
  `order` across a dragged list inside `withAnimation` and end in `try? modelContext.save()` —
  character for character the shape `SettingsView.moveContext` had. **Deliberately not swept in with
  T-614**, which was the decision plus one site; each of these wants its own failing-first test.
  The fix shape is settled: `CadencePendingChangePersistence.commitEdit(in:undo:)` over a captured
  `[Int]` of the previous orders, and the sentence where the user is already looking. Note the real
  work is the second half — Settings had a notice surface to reuse and the sidebar has none.

- [T-869] **Two reorders reach no commit at all, which is the worse half of the same audit.**
  `ListDetailComponents.reorderTask` writes `t.order = i` across the list and stops;
  `Cadence/macOS/Views/ListDetailComponents.swift` contains no `save()` and no persistence call
  anywhere in it. The Kanban card drop is the same shape: `KanbanBoardSupport.reorder` renumbers and
  returns, and neither caller — `KanbanListColumnView.moveTask`, `KanbanSectionColumnView.moveTask` —
  commits. **`KanbanListColumnView.handleTaskDrop` then answers `true` over it**, which is already in
  half 2's vocabulary; it is invisible only because there is no swallowed commit in the frame for the
  detector to hang it on. Half 3 does not see them either — it fires on insert and delete, not on a
  field write. So both rely on autosave, which is the thing [[T-327]] measured the cost of.

- [T-870] **The Kanban *column* reorder commits nothing either, one layer further in.**
  `KanbanListSectionSupportViews.reorderSection` → `CadenceSectionConfigMerge.reorderSectionConfigs`
  → `mutateSectionConfigs`, which merges, assigns `sectionConfigs` and returns. Dragging a column is
  as visible a rearrangement as dragging a row, and this ordering is a **blob on the container**
  rather than an `order` field — so the `\.order` sweep that found [[T-868]] and [[T-869]] cannot
  find it, and neither will the next one. Check for other blob-stored orderings before assuming this
  is the last. [[T-358]] is not a defence: last-writer-wins is about the *merge*, not about whether
  the write is ever committed.

- [T-871] **"A rearrangement the user can see" is a rule clause no detector can enforce.**
  [[T-614]] added it to `AGENTS.md`'s half 2 and left `CadenceSaveCommitDisciplineTests` alone on
  purpose: half 2 matches a vocabulary of *spellings*, and a row staying where it was dropped has
  none. Checked before changing anything — the narrowing reclassifies no existing exemption and the
  suite is green unchanged — so this is a gap, not a regression. The open question is whether a
  narrow instrument earns its keep: *a declaration that writes `\w+\.order = ` inside a loop and
  reaches a swallowed commit or none* would have found every site in [[T-868]] and [[T-869]] on its
  own, and is a far smaller vocabulary than half 2's. It would not have found [[T-870]], which is the
  argument against believing it. Sibling of [[T-657]] — the same honest limit of a text scan.

## Done

- [T-614] **CLOSED 2026-09-04 — a visible rearrangement *is* a success report, and both platforms
  now say so.** The user's decision. It is written into `AGENTS.md` rather than into a pane, because
  it narrows the standing rule: `try? save()` is permitted only when **both** halves hold — the save
  commits nothing but in-place field edits, **and** nothing after it tells the user it worked. "It is
  only an `order` field" answers the first condition and ignores the second. **A row that stays where
  you dropped it is the strongest success claim this app can make**, stronger than the dismissed sheet
  the rule already counts, and the failure mode is exactly what the rule exists to catch: a silent
  revert at next launch with nothing to retry.
  macOS's `SettingsView.moveContext(_:before:)` now matches [[T-581]]'s iOS treatment —
  `commitEdit(in:undo:)` puts every `order` back on refusal, `@Query(sort: \Context.order)` re-sorts
  the pane to the store, and a `CadenceInlineFailureNotice` names it under the detail header. Pinned by
  `CadenceOrderReassignmentTests.theMacOSContextDropReportsARefusedReorder`; 4 mutations, 4 killed.
  **"Only when the rearrangement survives a redraw" was rejected deliberately.** That is a judgement
  an agent must make per site, which is how this became underdetermined in the first place. Do not
  reintroduce it.
  **The narrowing changes nothing the four detectors accept, and that was checked before touching
  them.** Half 2 is a vocabulary of *spellings* — `dismiss…(`, `is/show<X> = false`, `return true`
  from a `-> Bool` — and "a row stayed where you dropped it" has none, so no exemption is
  reclassified, no entry was added or removed, and `CadenceSaveCommitDisciplineTests` ran green
  unchanged. The unenforceability is filed as [[T-871]], not smuggled into the suite.
  [[T-583]]'s recorded reasoning is corrected in place; `archiveContext`/`restoreContext` keep their
  `try?` and that half of T-583 stands. The new sentence paid for itself: the guide is still 199 by
  `wc -l`, and what it spent was "Full incident details are in `docs/AGENTS_REFERENCE.md`" — the
  fourth pointer to that file inside one section. **Neither raw `xcodebuild` block was touched**;
  they are `CadenceBuildInvocationHygieneTests`'s positive control, which ran green.
  Residue: [[T-868]], [[T-869]], [[T-870]] — the other reorder sites, audited and **deliberately not
  swept in with the decision**.

- [T-612] **CLOSED 2026-09-04 — label-only dimming, which is the user's call between the two branches
  this ticket named.** `iOSCalendarMonthCompactDayCell`'s numeral reads
  `Theme.dim.opacity(CadenceCalendarDayBadge.outOfMonthLabelOpacity)` now and the whole-cell
  `.opacity(isCurrentMonth ? 1 : 0.5)` is gone.
  **The label's value does not move.** The old pair multiplied to exactly the 0.50 the token holds, so
  the contrast floor is untouched and no third value was invented; what changes is that the today ring
  and the item dot stop being faded with it, and that two layers no longer have to keep multiplying to
  the right answer. **No plate was added** — the other branch — because this cell sits on the grid's
  single `Theme.surface` and has none to move, unlike the full-size cell [[T-568]] fixed that way.
  Pinned by `iOSCalendarMetricsTests.theCompactMonthCellDimsItsLabelAndNotTheWholeCell`, scoped to the
  one struct so the agenda row's own `Theme.dim` twelve lines up cannot vouch for it; 2 mutations, 2
  killed. Built for `generic/platform=iOS Simulator`, 0 warnings, log names the file.

- [T-813] **CLOSED 2026-09-04 — the last-resort bootstrap `fatalError` is a terminal recovery
  screen, sha `0371b19`.** `PersistenceController.container` is now optional; the final catch in
  `makeRecoveryContainer` — CloudKit failed, on-disk recovery failed, in-memory failed — records a
  `CadenceStartupTerminalFailure` and returns `nil` instead of trapping. `CadenceTerminalRecoveryView`
  explains the failure in plain language and offers an export, trying the primary store's own file
  read-only with CloudKit off before the recovery directories. It never takes
  `@Environment(\.modelContext)` or `@Query` — no context is injected into that branch at all — so
  the surface that exists because every store failed cannot itself touch a store. An outside census
  (R22) found no other user- or sync-reachable crash site in the app: 19 `try!` all source-literal
  regexes, 16 force unwraps guarded or literal-backed, 89 computed array subscripts all range-derived
  or guarded. This was the only one left.
- [T-817] **CLOSED 2026-09-04 — a guard that mutation testing proved could not fail, removed rather
  than pinned, sha `0371b19`.** The first mutation run reported M1 SURVIVED: a `fileExists` check in
  `openFirstAvailableReadOnlyStore` had no observable effect, because `allowsSave: false` against a
  missing store already refuses to create one — [[T-311]]'s measured asymmetry, pinned by
  `CadenceSharedStoreWriteGateTests`. The redundant guard and its unused `fileManager` parameter were
  deleted instead of writing a test that could only pretend to distinguish them. Re-run: 4/4 killed.
- [T-803] **CLOSED 2026-09-04 — the App Store packet had no description, keywords or copyright,
  sha `fad8d50`.** Apple requires all three for the version and the field list at
  `docs/app-store-submission-packet.md:7-24` carried none. Description is ~1,900 of the 4,000
  characters, every claim traced to a file that implements it; keywords are 99 of 100. It says
  "sync across your Macs", not "your devices", because `docs/apple-release-readiness.md:11` records
  that the iOS build is distributed on no channel and claiming iOS sync would be a metadata lie.
- [T-804] **CLOSED 2026-09-04 — the copyright line is drafted and flagged as inferred, sha
  `fad8d50`.** `© 2026 Haoran Wei` is derived from the bundle id and the git author, not from any
  legal record the repository holds. **This is the one metadata field the repo cannot settle**; the
  user confirms or corrects the legal name and year in App Store Connect.
- [T-806] **CLOSED 2026-09-04 — the release checklist's test command took no host lock, sha
  `fad8d50`.** `docs/apple-release-readiness.md:94` ran a bare `xcodebuild test` while its own
  `:103-109` — pinned verbatim by `AppStoreReviewReadinessTests` — requires the lock. Fixed with the
  documented `acquire`/`trap release` idiom. **Deliberately not switched to `scripts/xcb.sh`:** the
  bare invocation is intentional there, it is the positive control for
  `CadenceBuildInvocationHygieneTests`, and wrapping `xcb.sh test` in an outer `acquire` deadlocks
  against its own lease. The coordinator's brief said "require xcb.sh" and was wrong; p2 read the
  literal text and did not follow it. Second time this block has caught a coordinator paraphrase.

- [T-808] **CLOSED 2026-09-04 — the 216 unpinned product-tree sweeps are pinned by one generated
  manifest, sha `7761d2b0`.** An outside audit (R19 in `docs/CODEX_REQUESTS.md`) measured 216
  `@Test` functions that walk `Cadence/`, `CadenceWidgets/` or `CadenceMCPServer/` and **0** of them
  pinned: delete any one and the ledgers, parsers and fixtures beside it all stay green while an
  app-wide sweep silently stops happening. `CadenceTests/CadenceRealTreeSweepManifest.txt` now names
  them — **240 entries at HEAD** — and `CadenceTestTargetHygieneTests` fails three ways on it: a
  manifest name that is no longer declared, a sweep the scan finds that is not listed, and a listed
  name the scan no longer classifies.
  - **Generated, not typed.** `CadenceRealTreeSweepScan` derives the list from the target's own
    source: a `@Test` counts when its body plus every declaration it transitively names contains a
    walk (`swiftFiles(`, `enumerator(atPath:`, `.sweep(`, …), a product-root path literal, and
    Swift-source evidence. `scripts/real-tree-sweep-manifest.sh <id> --write` reruns it and rewrites
    the file from what it computed, lifted out of the `xcodebuild` log between two banners — so the
    classifier exists once, in Swift, where a test can fail on it. `scripts/test-suite-index.sh`
    could not produce this: it answers *which suite declares a test* and has no notion of reach.
  - **Why 240 and not 216.** 214 of the audit's 216 are on the manifest; 26 more sweeps it missed
    are too (whole suites: `CadenceTildeContainerPickerTests`, `CadenceSearchFieldClearButtonTests`,
    `CadenceCapturePaletteTests`, plus nine in `CadenceEmptyStateAuditTests`). Two audit entries are
    deliberately **not** on it, and both fall outside the audit's own stated boundary:
    `CadenceInPlaceEditFlushCommitTests/themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse`
    walks `CadenceTests`, not the app, and `TodayAndInboxNamingTests/noAgentFacingDocSpellsARetiredIPadName`
    walks agent-facing docs. [[T-809]] tracks pinning those. The audit's list also still spelled
    `CadenceIOSControlAccessibilityTests`, renamed by [[T-678]] four commits earlier — four of its
    216 names needed remapping by hand, which is the argument for generating this rather than typing
    it, in one line.
  - **Proved by mutation, not by reading.** `scripts/mutate.sh` against a `git archive HEAD` tree:
    deleting either of two manifest lines is KILLED, and deleting a whole swept `@Test`
    (`WidgetSupportTests/theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles`) is KILLED.
  - **What it does not do:** it never asks what a swept rule *asserts*. The suites remain the
    behavioural authority; over-inclusion (a detector self-check that shares a file with a sweep)
    costs nothing but a pinned name, while under-inclusion is the failure it exists to prevent.

- [T-678] **CLOSED 2026-09-04 — the icon-only accessibility suite is named for what it sweeps, sha
  `9fc8e9bf`.** [[T-637]] widened `CadenceIOSControlAccessibilityTests`'s walk from `Cadence/iOS/` to
  all of `Cadence/` and left the file's iOS-only name stated as a known mismatch rather than risk a
  rename mid-batch. Renamed to `CadenceIconOnlyButtonAccessibilityTests`, struct and file, once the
  tree holding the ledger quieted down. The suite's `including:` witness is unchanged —
  `Cadence/macOS/Views/TasksPanelSupportViews.swift` — since the widening was always enforced by the
  walk, not by the name. Counts were taken from HEAD at commit time rather than from when the ticket
  was picked up, per the batch's own caution that the ledger would move underneath it.

- [T-716] **CLOSED 2026-09-04 — nine stale comment claims corrected, a tenth found live, sha
  `4bd86f7e` (nine) and `c8fbddf0` (tenth).** The live half of [[T-565]]'s ledger. Each comment now
  names the symbol it actually meant, and `CadenceCommentSymbolClaimTests.staleClaims` is empty:
  - `CadenceDataExportPresentation.swift`: `PrivacyDataResetOutcome.statusMessage` →
    `.accountAndDataStatusMessage`.
  - `CadenceNoteFolderSupport.swift`: `ListNotesView.normalizedFolderPath` →
    `NoteFolderSheet.normalizedFolderPath`, the type that actually declares it (a `private var` on
    `NoteFolderSheet` in `ListNotesListSupportViews.swift`).
  - `CadenceTaskDropSupport.swift`, both `showsSectionChip` references: **neither comment invented a
    rule — both misnamed a real one.** The inbox-guard comment now names
    `CadenceTaskComposerSupport.showsSectionRow`, whose own guard clause (`container != .inbox`) is
    exactly the sentence it sits beside; the default-section comment now names
    `CadenceTaskInspectorSupport.showsSectionSegment`, the half of the rule about a lone `Default`
    section not being worth a chevron.
  - `iOSTaskInspectorMetrics.swift` and `CommitmentSharedViews.swift`: both "see also"
    `CadencePageHeaderMetrics.iconSize` references now point at `.tileGlyphRatio`, the ratio
    `iconSize`'s default was computed from before the identity tile — and `iconSize` itself — was
    dropped from page headers.
  - `AINoteActionReviewTests.swift`: `DataIntegrityRepairServiceTests.duplicateDailyNotesAreMerged` →
    `.duplicateCanonicalNotesAreMergedWithoutDroppingContentOrTags`, the real test pinning that a
    merged note keeps both its area and its project.
  - `CadenceCancelledTaskReachabilityTests.swift`: the cited `CadenceTodayRolloverSurfaceTests` test
    now carries the `InTodayRolloverSurface` suffix it gained when test names became unique across
    suites.
  - `TimelineMetricsTests.swift`: `CalDayColumn` has no `onDropTaskAtMinute` — it is
    `TimelineDayCanvas`'s; the comment now says `CalDayColumn` wires `TimelineDayCanvas
    .onDropTaskAtMinute` to `SchedulingActions.dropTask`.
  - `MilestoneMomentumWidget.swift`: `TodayTasksWidgetView.statusPresentation` → the real declaration,
    `CadenceTodayWidgetTask.widgetStatus(for:)`, a private extension method in
    `TodayTasksWidgetView.swift`.
  **A tenth landed after the ledger was written and before this closed**:
  `CadenceRowSubjectAccessibilityTests.swift` named `` `ContainerPickerBadge.accessibilityValue(label)` ``
  as if it were a declared member; it is a call site inside `ContainerPickerBadge`'s own body. Spelled
  as two separate backticked spans now — `` `ContainerPickerBadge` `` and `` `.accessibilityValue(label)` ``
  — neither of which parses as a `Type.member` claim.

- [T-717] **CLOSED 2026-09-04 — the file-qualified exclusion narrowed to single-public-type files,
  sha `4bd86f7e` (fix + narrowing), `ff98a3f7` (fixture bug found by mutation testing).** The
  exclusion used to suppress any claim whose member is declared anywhere in a file named after the
  claimed type — right for a `private` helper sharing a file (`NotesView.swift`,
  `SettingsTagsSection.swift`, both eight and six nominal types respectively, all but the eponymous
  one `private`) and wrong for two types that are *both* public (`DateFormatters.swift`,
  `CadenceCalendarDayBadge.swift`, two apiece, neither `private`). Narrowed to: exclude only when the
  file declares exactly one **top-level, non-private** nominal type
  (`SymbolIndex.publicNominalTypesByFileBaseName`, gated by `isPrivatelyDeclared` and
  `isTopLevelDeclaration` — the latter needed because `NotesView` nests a non-`private` `NotesPage`
  enum, which would otherwise have falsely counted as a second public type and broken the
  `NotesView.NotesDateJumpButton` exclusion the ticket said must survive).
  Measuring the newly-uncovered population surfaced **five** genuine misattributions, all corrected
  rather than ledgered since each was a one-line fix: `AppTask.swift`'s
  `GoalContributionSummary.summary(for:)` → the real owner, `GoalContributionResolver` (a third type
  in `GoalContributionSummary.swift`, found only because the narrowing stopped excluding it);
  `MarkdownEditorView.createAssets` / `.createInlineTag` (two test files) → `MarkdownEditor`, which
  declares both; `CadenceCalendarDayBadge.markedDayLabel(date:hasItems:)` →
  `CadenceCalendarDayAccessibility`; `DateFormatters.timeString` → `TimeFormatters`.
  **A mutation caught a hole in the new test's own fixture**: `scripts/mutate.sh` on the narrowing
  guard itself first reported SURVIVED — `theFileQualifiedExclusionStopsAtASecondPublicTypeButNotAtAPrivateOne`
  built its `SymbolIndex` from a file path that did not match the claimed type's name, so the
  file-qualified branch in `offendingSpans` never ran and every assertion passed regardless of the
  mutation. Fixed by naming the fixture path after the claimed type, matching the real convention;
  the same mutation is now KILLED. `sha ff98a3f7`.

- [T-674] **CLOSED 2026-09-04 — ten icon-only controls now say something, and four helpers can no
  longer ship one that does not, sha `a79dd92c`.** From [[T-637]]. `TimelineZoomControl`'s inline
  `minus`/`plus` and the picker's back chevron carry `.cadenceControlLabel(…)` directly, having no
  shared helper to carry it for them: "Zoom out"/"Zoom in" (matching `CalendarToolbarZoomControl`'s
  own words for the same concept) and "Back to all lists". `SidebarComponents`' add-list `plus`
  reads "Add list to \(title)" from the section title already in scope;
  `KanbanColumnSupportViews`' column-editor `ellipsis` reads "Edit column".
  **The four private helpers all gained the same required parameter, in the same change**, per
  T-611's compile gate rather than a per-call-site sweep: `HabitsFormSupportViews.stepButton` (now
  "Decrease"/"Increase \(title.lowercased())" — the stepper names what it increments, not its
  glyph), `GoalTimelineView.timelineNavButton` ("Earlier"/"Jump to today"/"Later" — navigation, not
  a stepper), `SettingsSupportViews.actionButton` ("Rename"/"Archive"/"Delete \(context.name)"),
  and `FocusBundleTaskSupportViews.focusRowIconButton` ("Move up"/"Move down"/"Remove from
  bundle"). `Sheets/ListEditorSupportViews.ListEditorIconCell` — the site that set the fix shape —
  had `var accessibilityLabel: String? = nil`; it is now `let accessibilityLabel: String`, no
  default, and its one silent call site (the icon strip's per-glyph cell) now passes the SF Symbol
  name itself, matching the sibling iOS icon grids' own `.accessibilityLabel(icon)` convention
  (`iOSListEditorViews.swift`, `iOSTrackingEditorComponents.swift`) rather than inventing a fourth
  spelling. The dead `ListEditorOptionalControlLabel` wrapper the optional made necessary is gone.
  **A coordinator addendum, same day: `CreateContextSheet.IconGrid`'s per-glyph cell drew a `ZStack`
  mutating `selected` from a bare `.onTapGesture`** — no `Button`, no accessible name, invisible to
  the `Button`-keyed sweep by construction. Converted to a `Button` with `.cadenceControlLabel("Select
  \(icon) icon")` and `.accessibilityAddTraits(.isSelected)` when current. Measured before
  converting, not assumed: exactly one site in the whole tree combines `Image(systemName:)` with a
  nearby `.onTapGesture` and no enclosing `Button`/`Menu` (246-character gap); the nearest look-alike
  (`iOSCalendarBundleDetailSheet`'s `Menu` trigger) sits at 511. `CadenceIconOnlyTapGestureAccessibilityTests`
  (4 tests) bans the shape outright — a straight `#expect(offenders.isEmpty)`, not a ledger, since
  the found population was one and the fix removed it — and pins the 300-character window against
  the three nearest real look-alikes (`CalendarPageMonthSupportViews.swift`, `LinksView.swift`,
  `iOSCalendarBundleDetailSheet.swift`) rather than leaving the measurement a comment.
  Deleting a call site's name argument fails the build, confirmed with `scripts/mutate.sh`: five
  mutations, one per required-parameter helper (`ListEditorIconCell`, `stepButton`,
  `timelineNavButton`, `actionButton`, `focusRowIconButton`), each `INVALID (DID-NOT-COMPILE)` with
  exactly 1 compile error — the whole argument for the compile gate over a sweep. Build: 0 compile
  errors, 0 warnings across the `Cadence`, `CadenceWidgets` and `CadenceMCPServer` schemes (all
  three rebuilt the touched files). `CadenceIconOnlyButtonAccessibilityTests`'s own ledger and
  witness were independently confirmed stale on unmodified HEAD before this landed — filed as
  [[T-795]] rather than fixed here, since fixing someone else's suite is not this ticket's fix
  shape.
  **`Views/TaskBundlePickerSupportViews.swift` is shared with [[T-672]]'s clear-button migration**
  (`7e58fc6c`, landed mid-batch): the first reconstruction (`a79dd92c`) was built against a scratch
  copy taken before that commit landed, and while it carried this ticket's own back-chevron label
  correctly, it silently reverted the clear-button migration in the same file. Caught by re-diffing
  the just-landed HEAD against the live working tree rather than trusting the reconstruction file,
  and corrected in a second commit, `12077cf3`, before either was reported here.
  Residue: [[T-795]] (the icon-button suite's own stale ledger/witness), [[T-796]] (an icon-only
  `Menu` label is a third unnamed-control shape), [[T-797]] (`ColorGrid`'s swatches share the exact
  defect `IconGrid` had, one struct up, and need a naming decision before they can take the same
  fix).

- [T-673] **CLOSED 2026-09-04 — all eight remove/complete glyphs hand their row's own subject down,
  the two circles read the shared completion-state label, sha `a3068e3c`.** From [[T-637]]. Six
  `xmark` removals now pair `.accessibilityLabel("Remove")` / `"Detach"` with `.accessibilityValue(…)`
  reading the row's own title — a draft subtask (`Sheets/CreateTaskSheet.swift`,
  `Views/QuickCreateChoiceSupportViews.swift`'s two subtask/task rows), a goal's linked list and its
  task contributor (`Views/GoalsSupportViews.swift`, both), a saved subtask
  (`Views/TasksPanelSupportViews.swift`). The two completion circles (the saved subtask's toggle and
  `Views/HabitsSupportViews.swift`'s habit toggle) read
  `CadenceTaskCompletionState.accessibilityActionLabel` now, same as [[T-594]]'s task row and
  [[T-611]]'s iOS circle, rather than spelling their own state — a `Subtask`/`Habit` has only the two
  states `.done`/`.todo` maps to, no mid-fill states to model.
  **Every title routes through the existing normalisation rather than being interpolated raw**:
  `TaskTitleSupport.displayTitle` for a subtask/task subject, `CadenceTitleNormalization.display` for
  a goal's linked area/project (keyed on which relationship is set) and a habit — so an untitled row
  announces the same placeholder it already renders instead of a blank line.
  No site needed a judgement call; all eight had a genuine subject to hand down.
  `CadenceRowSubjectAccessibilityTests` (9 tests) pins each site by source shape — the value is the
  row's own property, not a passed constant, which a naive "label exists" test would have let
  through. Failing-first against the pre-fix tree (0 tests exist there; the suite itself is the new
  material). `scripts/mutate.sh`, 7 mutations, **all KILLED, none survived**: a hardcoded constant
  swapped in for the subject at each of the 8 sites (one mutation covers both `SubtaskRow` sites at
  once via `count: 2`), one dropped `.accessibilityValue` entirely, one reverted the habit circle to
  hand-spelling its own state instead of reading the shared label. Build: 0 compile errors, 0
  warnings (both counts from a run that recompiled every touched file).
  **`Views/TasksPanelSupportViews.swift` is shared with [[T-672]]** (o1's `CadenceSearchFieldClearButton`
  landed at `7e58fc6c` while this was in flight, in the same file); committed as a
  `path=<content-file>` reconstruction of HEAD plus only this ticket's hunk, refused once as
  `REMOVES-HEAD-LINES` (the legitimate `Text(TaskTitleSupport.displayTitle(…))` → `Text(displayTitle)`
  collapse) and re-run with `--removes 1`.
  Residue: [[T-792]] — the visible title text beside two of these glyphs (`GoalLinkedListRow`,
  `GoalTaskContributorRow`) still reads its title raw, so an untitled one now announces the
  placeholder VoiceOver expects while drawing a blank line beside it.

- [T-679] **CLOSED 2026-09-03 — committing out of a shared checkout is a script now, not a rule.**
  `scripts/agent-commit.sh <id> -m <message> <path>[=<content-file>]...`. It refuses `FOREIGN-STAGED`
  (the shared index holds a path you did not name — Batch D, where d1's `git rm` landed in `91d533c`
  instead of `5b0c2b8`, and Batch M's stale `docs/TODO.md` blob), assembles the tree in a private
  `GIT_INDEX_FILE`, commits it by plumbing, and then **repairs the shared index** and verifies your
  paths are clean against the new HEAD — the Batch M residue where a correct private-index commit left
  the shared index 274 deletions behind HEAD, so the next agent's commit would have reverted it. The
  `<path>=<content-file>` form is the reconstruction form for a file a sibling is also editing;
  `git commit -- <path>` is still wrong there and the runbook says why.
  **The declined-hunk case is catchable, and it is caught.** A reconstruction whose content differs
  from the worktree is by construction declining something; those lines are recorded, and the **next**
  commit of that path is refused as `DECLINED-HUNK-LOST` unless it carries them or clears the record
  with `--accept-declined <path>`. That is Batch M's fourth failure exactly, where m3 correctly
  declined m4's in-flight hunk, m4 committed without it, and HEAD stopped compiling on a required
  parameter one composer never passed. What it cannot do is notice a path nobody commits again —
  filed as [[T-781]].
  `./scripts/agent-commit.sh selftest` induces every refusal against a throwaway repository (32
  checks), including a positive control proving the private-index pattern *without* the repair really
  does leave the shared index dirty. Pinned by `CadenceGuardScriptSelftestTests` ([[T-719]]).
  Mutations M1–M3, M5, M7 (`scripts/mutate.sh`): disabling `FOREIGN-STAGED`, deleting the shared-index
  repair, and stopping the declined-hunk refusal from firing were each KILLED. Using it at all is
  still a rule rather than a mechanism — [[T-780]].
  **Two amendments the same day, both from its own first real use, both on `docs/TODO.md`.**
  (1) "Declined" was first computed as *worktree lines the staged blob does not have*, which counts
  every line the commit deliberately **deletes**: this ticket's own ledger move recorded 179 of them,
  most of them the three tickets it was closing. A line can only be a sibling's in-flight work if the
  commit being replaced did not have it either, so the version at `HEAD` is a third input now.
  `mode 3c` is that shape — the worktree keeps a line the reconstruction drops — and reverting the
  third input makes it, and only it, fail.
  (2) **A reconstruction built on a stale `HEAD` silently reverts a sibling's landed work**, and that
  happened twice within the hour, both on `docs/TODO.md`: `169d594` dropped three of a sibling's open
  tickets, `820aa98` restored them and in doing so dropped this ticket's own three closing entries.
  Nothing in the tool noticed, because deleting a line is a legitimate thing for a commit to do. So
  it is said out loud instead: `REMOVES-HEAD-LINES` refuses any commit whose staged content drops
  lines `HEAD` has unless `--removes <exact count>` names how many — the same shape as `count:` in
  `scripts/mutate.sh`, where the point is not the number but looking at what is going. `mode 4b`
  induces it (undeclared, wrong count, exact count); deleting the guard makes exactly those four
  checks fail and the other 28 pass.
  (3) A line count is the wrong unit for a ledger. `docs/TODO.md` lost three of a sibling's tickets
  inside one, and the agent who caught it did so by diffing the **ticket-id sets** against the parent
  commit. That is `LEDGER-IDS-LOST` now: a commit of a `TODO.md` that no longer carries a `- [T-n]`
  entry `HEAD` had is refused with the ids named, and `--drops-ids <exact,sorted,list>` retires them
  deliberately. `mode 4c` induces it — a reconstruction that keeps T-101, adds T-103 and loses T-102 —
  and with the guard deleted the same commit is refused only as *"removes 1 line(s)"*, which is
  character for character how the three real ones went missing. An append-only edit needs no flag.

- [T-719] **CLOSED 2026-09-03 — `CadenceGuardScriptSelftestTests` runs both guard scripts' selftests
  on every `CadenceTests` run.** 5 tests. Two shell out (`./scripts/mutate.sh selftest`,
  `./scripts/agent-commit.sh selftest`) and fail on a non-zero exit; **exit 0 is not enough**, so each
  run must also name every refusal it claims to induce and print a `checks: N passed, M failed` tally
  derived from the checks that actually ran — a count a selftest gutted to `return 0` cannot produce.
  `theCheckerRejectsASelftestThatAssertsNothing` runs that reading against four stubs (silent,
  headers-but-no-checks, a lost mode, a red exit) so the reading is not vacuous, and a source scan —
  `xcb.sh`'s own pinning shape — asserts each refusal is still in the script body *and* still induced
  in its selftest. Mutation M4 (bypass `mutate.sh`'s own `NEEDLE-ABSENT` guard) KILLED, plus two
  weakening pairs settled by control: M5→M6 (dropping the tally reading survives only alongside M5's
  violation, so `tally.failed != 0` is load-bearing) and M7→M8 (dropping a refusal from the required
  list). 6 killed, 2 survived-as-evidence, 0 inconclusive; baseline green over 5 tests, 0 Swift warnings.
  **Two sandbox facts fell out of it, both measured.** The test host is App-Sandboxed, so the
  `/usr/bin` xcrun shims for `git` and `python3` refuse to run and both scripts now probe for a working
  binary; and zsh sets `$TMPPREFIX` to `/tmp/zsh` itself at startup, so `mutate.sh`'s here-document
  died before its first line under the sandbox and no `[[ -z ]]` guard could ever have noticed.
  Written up in [[T-782]] and `docs/SUBAGENT_RUNBOOK.md`.

- [T-787] **CLOSED 2026-09-03 — `show_outstanding`'s `local path` no longer empties `$PATH`.** Found
  by another agent using the tool live. Renamed to `declined_path`, with the reason in a comment naming
  the whole family (`path`, `cdpath`, `fpath`, `manpath`, `status`, `argv`, `options`). The selftest now
  asserts the backstop listing really prints and that nothing in it died `command not found`; reverting
  the rename by hand makes both of those checks fail and the rest pass, which is how a diagnostic that
  failed silently got a guard.

- [T-668] **CLOSED 2026-09-03 — one brace matcher, and the answer to "how many of the 83 read a
  different span" is measured at zero.** The copy is gone from `FocusPickerPlayControlTests`:
  `cadenceFunctionBody` lives in `CadenceTests/CadenceSourceScanSupport.swift` now and is a wrapper
  over a new `CadenceSourceScan.declarationBody(_:in:)`, which `functionBody(named:)` is *also*
  written in terms of — `declarationBody("func \(name)(", in: source)` is the whole of it. So the
  [[T-644]] balancing is one implementation, not two.
  **The arbitrary declaration prefix was load-bearing, so deleting the helper was never available.**
  Counted over the tree: of the 83 pre-existing call sites, 38 pass a `func`-shaped prefix, **40
  pass something `func <name>(` cannot express** — `var body: some View` (7), `Group` (3),
  `struct <X>: View`/`: ViewModifier` (9), `.onChange(of: …)` (3), `if phase != .active`,
  `static var live: Self`, `private var options: CadenceTaskViewOptions` (2),
  `shouldChangeTextIn range: NSRange,` — and 5 compute the prefix at run time. Two parameter lists
  can now stand between the prefix and the body and both are balanced: the one the prefix left
  **open** (`"static func rollOver("`) and the one that **begins** right after a prefix that stopped
  at the name (`"static func handleCommandKeyEvent"`).
  **The measurement.** An instrumented build computed the old span and the new one at every call and
  printed both: a full `CadenceTests` run made **96 invocations, 92 distinct (site, declaration)
  pairs, all 19 files reached**, and **0 of the 83 pre-existing sites read a different span**. The
  ticket's warning that some of them might be reading a default closure today is measured false —
  the change is inert exactly as T-644 was. The one divergence in the tree is the site this ticket
  unblocked: `CadenceTodayRolloverSurfaceTests.theRollCommitsThroughThePendingChangeUnit`, narrowed
  from the whole file back to `rollOver(`'s body (old span 15 characters — ` try $0.save() ` — new
  span 271).
  Failing-first: the new fixture asserts `cadenceFunctionBody("static func rollOver(", …)` does not
  contain `try $0.save()`; against the unmodified reader that call throws `.tooShort`, because the
  default closure it returns is 15 characters against the 40-character floor.
  Mutations, all KILLED: **M1** stops collecting the prefix's own unclosed parenthesis (the
  pre-T-644 defect exactly) — killed by
  `theDeclarationBodyReaderSkipsADefaultedClosureInAnOpenParameterList` **and**
  `theFunctionBodyReaderSkipsADefaultedClosureInTheParameterList`, which is the two entry points
  being one reader; **M1b**, the same mutation scoped to `CadenceTodayRolloverSurfaceTests`, killed
  by `theRollCommitsThroughThePendingChangeUnit`, so the narrowing is load-bearing rather than
  cosmetic; **M2** drops the second balancing, killed by the same fixture's `"static func rollOver"`
  (prefix-at-the-name) assertion.
  Residue: [[T-785]] part (2) — `CadenceDeleteConfirmationCommitTests` can be narrowed now, but its
  needle is a claim about adjacency and is not a mechanical swap.

- [T-687] **CLOSED 2026-09-03 (part 1) — the constant-fallback ternary is swept, 25 sites routed and
  the 2 that are not are named line by line.** Part (2), the same shape on a `name`, is refiled as
  [[T-783]]; it was never in this batch's scope and the sweep says out loud that it does not cover
  it.
  Independently re-measured before anything was changed: **27 sites in 15 files**, the same
  distribution the ticket recorded, found by widening T-609's needle from a string *literal* between
  the `?` and the `:` to an identifier.
  **The 27 are not uniform, and the split is not quite the one the ticket predicted.** 22 are
  ordinary placeholder fallbacks that [[T-505]]/[[T-513]] had already de-literalised — they read the
  right constant and still drew a blank line for a title of spaces. Of the five the ticket flagged
  as falling back to a real value, **two are not defects at all**: `LinksView.swift:102` and
  `iOSListSupportViews.swift:696` test `CadenceTitleNormalization.normalized(newTitle)`, a value that
  is *already trimmed*, so `.isEmpty` there is correct. (The ticket named 102 and 797 and missed 696,
  which is the same shape as 102.) A third, `iOSListSupportViews.swift:797` (`iOSLinkRow`), is a
  genuine draw-site fallback to `link.url` and is routed with its fallback unchanged. So 25 sites
  were routed and 2 remain.
  Every routed site keeps the exact fallback expression it already had — T-609's standing decision,
  held: what changed is the trim and nothing else. The two survivors are
  `MarkdownNoteSupport.swift:85`/`:86`, `resolved(_:with:)`'s override-merge, which falls back to a
  *template's* stored value rather than a placeholder; they are a measured exemption pinned by
  `theOverrideMergeExemptionIsStillExactlyTheTwoLinesItWasMeasuredAs` (exact pair, not a file-level
  pass) and owned by [[T-785]].
  Instrument: `constantTitleFallbackInstrument`, whose negative witness is T-609's *literal*
  spelling, so a detector matching both would make either result unattributable.
  Mutations, both KILLED: **M3** types `iOSFeatureViews.swift:175` back as the untrimmed ternary
  against the constant — invisible to T-609's own sweep, which is the whole ticket — killed by
  `noSurfaceHandSpellsAnEmptyTitleFallbackAgainstAConstant`; **M4** changes one of the two exempted
  lines, killed by `theOverrideMergeExemptionIsStillExactlyTheTwoLinesItWasMeasuredAs`.
  Found on the way: `CadenceSharedConstantReuseSweepTests.theMilestoneRowsAllNameAMilestone` pinned
  the *old ternary spelling* of the milestone row, so it went red on a change that preserved its
  claim. Needle updated to the call, with an added `milestone.title.isEmpty ?` absence assertion so
  it also fails if the row goes back.

- [T-700] **CLOSED 2026-09-03 — the harvest reads a computed `static var` now, and the duplication it
  was hiding is gone.** `cadenceStaticComputedVarBodies(in:)` is the third half of
  `cadenceSharedStringConstants()`, brace-matched the same way `cadenceStaticFunctionBodies(in:)` is,
  with the one guard a property needs that a function does not: an `=` between the name and the next
  brace means the declaration is **stored**, and taking it would adopt the *next* declaration's body.
  **Before/after, measured over `Shared/` + `Models/` (173 files):** 198 constants harvested → **200**.
  The two new ones are exactly what the ticket named — `version` = `"CFBundleShortVersionString"` and
  `build` = `"CFBundleVersion"`, both in `Cadence/Shared/AppStoreReviewReadiness.swift` — and they
  brought exactly two offender hits with them, both in `Cadence/Services/CadenceDataExportService.swift`,
  which is in neither `CadenceMCPServer`'s nor `CadenceWidgets`' source list, so the T-499 target
  boundary does not forgive them.
  Fixed rather than ledgered: `currentAppVersion()` reads `CadenceAppBuildIdentity.version`/`.build`.
  The `bundle:` seam it dropped was never passed by any caller, and **the two copies had already
  drifted** — the export fell back to `"0"` for the short version where both About screens fall back
  to `"1.0"`, which is the disagreement `CadenceAppBuildIdentity`'s own doc comment predicted.
  `CadenceAppBuildIdentity` is `nonisolated` now, because the export service is a `nonisolated enum`
  and reading a main-actor property from it is a warning against a zero baseline.
  The widening is pinned on fixtures rather than on the tree, since the tree is the thing it exists
  to let change: a positive, a stored-declaration negative, and a walk of every Swift file in all
  three shipped targets plus `CadenceTests` for the crash-safety reason `cadenceStaticFunctionBodies`
  records.
  Mutations, both KILLED: **M5** re-types `"CFBundleVersion"` in the export service, killed by
  `noCallSiteRetypesASharedStringConstant` — nothing fired on that line before this widening;
  **M6** deletes the `=` refusal from the reader.
  **M6 SURVIVED on its first run, and that is the finding.** In the first fixture a
  `static func vended()` stood between the stored `static var all` and the next brace, so the *`func`*
  refusal caught it and the `=` refusal was never the discriminator — a guard with no test, in a
  reader written for exactly this class of defect. `theComputedVarHarvestRefusesAStoredDeclarationOnTheInitializerAlone`
  is the source where `=` is the only thing refusing it (a stored `var` followed by an `init`, with
  no `func`, `var` or `}` between), and M6 re-run against it was KILLED.

- [T-685] **CLOSED 2026-09-03 — a refused iOS list-editor save now puts the child projects' tasks
  back too.** `iOSListEditorSheet.save()`'s area branch snapshotted `area.tasks ?? []`, which is the
  tasks filed *directly* in the area. The `reassignTasks` it then runs cascades by design
  ([[T-340]]): an area's move also re-points the tasks of every child project whose own `context` is
  `nil`, because those read their context through the area. Those tasks were written and never
  snapshotted, so a refused save restored the area's own fields — name, description, icon, colour,
  context — and left the child projects' tasks pointing at the context the save had not landed. Now
  both branches ask `CadenceTaskMutationSupport.inheritedContextTargets` for the set the
  reassignment actually reaches, which is what the two macOS editors already do; the project branch
  is behaviourally identical (nothing inherits from a project) and is respelled so neither branch
  re-derives the set.
  **Proven behaviourally, not by spelling.** `theIOSListEditorsAreaUndoSetRestoresACascadedChildProjectsTasks`
  reads which of the two sets the `.editArea` branch *names* out of the editor's source — `save()` is
  private to a SwiftUI `View` — then snapshots that set, moves the area, runs the real cascade and
  restores. Before the fix the cascaded task was still in the new context after `restore()`. 8
  mutations, 8 killed (2 re-spelled after a reflow); iOS-simulator build clean, 0 warnings.

- [T-684] **CLOSED 2026-09-03 — the `~` panel can no longer highlight a row it will not draw.**
  [[T-534]]'s *first* defect, on the last list-offering surface that had not learned it.
  `TildeContainerPickerSupport.flatContainers` filtered on `$0.isActive` and took no `selection:` at
  all, while `TildeContainerPicker` **is** handed a selection for its checkmark — so a draft already
  filed in an archived or completed list got a panel with no row for where it is, and the one
  correction the user needed was the one row missing. Now
  `flatContainers(query:contexts:areas:projects:selection:)`, narrowed through `pickableAreas` /
  `pickableProjects` exactly as `ContainerPickerFilterSupport.groups` does, so the two macOS list
  pickers cannot drift on the rule. Both composers pass the same value to the rows and to the
  checkmark, and that agreement is itself pinned.
  **Measured before and after:** over the 10 selections the panel's own fixture can hold, 3 were
  rows it would check and not draw (an archived area, an archived project, and an archived list with
  no context at all — [[T-558]]'s trailing bucket needed the rule too). After: 0.
  `selectedAreaID` / `selectedProjectID` are applied inside the `flatMap` closure rather than handed
  over as unapplied references — a main-actor-isolated method as a value in a nonisolated context is
  a warning, and the baseline here is zero.

- [T-683] **CLOSED 2026-09-03 — the mechanical half landed; the wording did not.** `CreateGoalSheet`'s
  initial-linked-list picker was the sixth instance of the context fold: a catch-all keyed on
  `$0.context == nil`, right for a list that belongs to no context and wrong for one whose context
  exists and was not offered — the ordinary state of a list under an archived context. It now asks
  `CadenceSidebarLists.isOffered(_:among:)`, the same question [[T-534]], [[T-538]] and [[T-558]]
  each converged on. Latent before and latent after — `allContexts` is an unfiltered `@Query`, so
  nothing was being dropped — fixed anyway, because "latent" here names the caller nobody has
  written yet. Its ledger line in `CadenceContextlessListSurfaceTests.knownContextDerivedListSites`
  moves from "the known remaining instance" to "correct by the offered set"; the count stays 2 and
  the file total stays 27 across 9 files.
  **The three heading spellings are deliberately untouched.** "Other"
  (`CadenceSidebarLists.ungroupedTitle` — both sidebars and the container picker) and "No Context"
  (this sheet and `GoalLinkCandidateGroup.title`, the two goal-attach surfaces) are the same bucket
  under two words; "No context" — the macOS context picker's own none-row — is a different idea, an
  unset *field*, and must not be folded in with them. Converging the first two is a user-visible copy
  decision that nobody has made, so it was not made here. Both live values are asserted as the
  strings they are (`theGoalSheetsCatchAllHeadingIsStillItsOwnWord`), and converging them fails that
  test rather than passing quietly — mutation M7 is the evidence.
  Residue: [[T-771]].

- [T-658] **CLOSED 2026-09-03 (`b29e9a9`) — a refused macOS calendar save keeps the popover, the
  draft and all of it; only Delete still leaves through the alert.** iOS was the shape to copy and
  now is copied for the two paths that cost the user typing.
  **The rule is a value now, not a habit.** `CadenceCalendarWriteOutcome` (`.committed` /
  `.refused(notice:)`) and `CadenceCalendarEventEditingSupport.saveOutcome(for:)` say the thing the
  macOS call sites were not saying: a refusal and a success are *different decisions about the
  editor*, not two ways of closing it. `CalendarManager.report(_:into:onCommitted:)` applies one to
  a surface, and clearing `lastWriteFailure` is part of reporting rather than tidy-up — on macOS an
  alert raised over a popover dismisses that popover, so leaving the global alert armed would have
  re-created the loss inline reporting exists to stop.
  **Five sites, and the quick-create callback un-narrowed.** `CalendarBoardEventCard` and
  `TimelineEventBlock` each report twice: the rejected write, and the branch where the edited range
  cannot be formed at all — which closed the popover in *silence*, with EventKit never asked. That
  second one was not in the ticket. The create callback answers `CalendarWriteFailure?` from
  `SchedulePanelShellViews` down through `TimelineDayCanvas`; `QuickCreateChoicePopover`'s own
  callback stays `Void` on purpose, because the canvas is the frame that dismisses it, so the canvas
  is where the decision belongs and the popover reads the answer back as a binding — the shape
  `TaskBundleDetailPopover` records for its own notice (T-628).
  **Delete is deliberately not on this path**, and there is no `deleteOutcome` to tempt anyone: both
  deletes leave through `DeleteConfirmationManager`'s full-window overlay, which closes the transient
  popover before EventKit answers, and they have no draft to lose. Pinned as an exact-zero, not
  assumed. 6 mutations, 6 killed — including the silent-range branch and the alert handover.
  Residue: [[T-768]].

- [T-708] **CLOSED 2026-09-03 (`481c21c`) — dismissal is a parameter of the notice, because the
  callers genuinely want two things.** All 49 `CadenceInlineFailureNotice` call sites were read
  first, which is what decided it.
  **Forty-three sit beside the control that failed** — Save, Create, Restore, Delete, Seed — and are
  cleared by the next press of that control. Checked rather than assumed: every one of the four call
  sites with no `= nil` anywhere in their own file takes its notice as a passed-in `let` or
  `@Binding` and the owner clears it. An ✕ next to a Save button the user is about to press again is
  chrome that says nothing, so those keep the bare sentence and look exactly as they did.
  **Six are in a markdown editing surface**, where the failing act — paste an image, tick an embedded
  task — is not what the user does next. They go back to typing, and typing never reaches the door
  that set the notice, so the red sentence sat under the toolbar for the rest of the session. Those
  six pass `onDismiss` and draw an ✕. The ticket named the two `imageFailureNotice` sites; the four
  `embeddedTaskFailureNotice` ones in the same editors are the same case under a different name and
  were fixed with them rather than left to be re-filed.
  Both forms draw one `sentence` view, so the component still cannot grow a second spelling of red
  text — pinned, and mutating it apart is one of the 3 mutations, 3 killed.

- [T-655] **CLOSED 2026-09-03 (`793c3f6`) — the last two canvases commit what they create, and
  each names its own refusal.** The rest of [[T-636]](e). `SchedulingActions.createTask` and
  `createBundle` insert into a context they were handed and commit nothing, which is correct —
  that signature is this repo's statement that the caller owns the unit of work — and neither
  remaining caller was doing so. `CalDayColumn` owns **two** units of work (drag out a range and
  name a task; drag out a range and tick tasks into a block) and committed neither;
  `TimelineDayCanvas` owns one (drop a task on a scheduled task) and dropped the answer on the
  floor. Both `commitReachExemptions` entries are gone.
  **The overload trap the ticket warned about is real, and it bit nothing because the warning was
  followed.** The commit index resolves a call by *name* and vouches for a name only when every
  overload of it on that type commits, so `SchedulingActions.insertTask(…)` and
  `insertBundle(from:adding:in:commit:)` were added beside their non-committing siblings rather
  than folded into them — the same answer T-636(e) gave when it added
  `insertBundle(title:…adding:in:commit:)`. Both siblings stay; both still have test callers.
  **A finding recorded rather than rounded up.** `insertBundle(from:adding:)` cannot promise the
  store holds no block after a refusal: `CadenceTaskMutationSupport.addTask` ends
  `try? modelContext.save()`, so the shared mutation commits the pair before this frame's commit is
  asked. In the app the two are the same `save()` and refuse together; in a test they are not. What
  the frame owns either way is asserted, and the swallow is pinned by
  `theSharedTwoTaskBlockMutationCommitsThroughAswallowedSaveOfItsOwn`, so the day it goes the
  stronger claim replaces this one. 7 mutations, 7 killed — including restoring the
  `TimelineDayCanvas.body` exemption, which is the evidence half 3 really did stop reporting it.
  Residue: [[T-759]], [[T-760]].

- [T-656] **CLOSED 2026-09-03 (`23c45a9`) with [[T-727]] — the class was counted before it was
  fixed, and it is four sites out of thirty-seven.** Every call site of `CadenceChoicePopoverList`
  (33, counting its `iOSChoicePopoverList` typealias) and `iOSContainerChoicePopover` (4) was read.
  **Thirty-three set a draft field on a sheet**, where the write cannot be refused and closing on
  the tap is what picking *means*. Four commit: the task row's repeat, milestone and list chips, and
  `iOSTaskDetailSheet`'s time picker.
  **The shape.** Each component keeps its ordinary initialiser and gains a committing one taking the
  current *value* — not a `Binding` — plus `select:`; the row hands the value to `select` and closes
  only if it answers `true`, drawing `failureNotice` under the rows otherwise. Taking a value is the
  load-bearing half: a writable binding beside a `select` closure is two write paths, and a mutation
  hidden in a binding's setter is exactly what neither half of the `try? save()` rule could follow.
  Three of the four adopted it; the fourth is [[T-761]], in a file another agent held this batch.
  The census is pinned as an exact per-file table rather than a floor, and the defect as a
  `CadenceScanInstrument` detector whose nearest negative is a `Binding` forwarding to a preference
  write. 6 mutations, 6 killed. Residue: [[T-761]].

- [T-727] **CLOSED 2026-09-03 (`23c45a9`) — same commit, same shape, and the caller split survived
  it.** The ticket's own condition was that whoever took it took [[T-656]] too and picked the
  spelling once; that is what happened. The three draft callers
  (`iOSCreateTaskSheetSupportViews`, `iOSTaskDetailComponents`, `iOSCalendarQuickCreateSheet`) are
  untouched and still self-dismiss, which the ticket was right to insist on. The fourth,
  `iOSTaskRowActionViews`, takes the committing form, so [[T-702]]'s alert on the row is now the
  **context menu's** only — a `Menu` closes itself and cannot be told not to — and the list chip
  reports inline in a picker that stays open, which is what the Mac's kanban picker has done since
  T-497. That deletes one of the two shapes T-702 had to keep.

- [T-701] **CLOSED 2026-09-03 - `title` and `order` are in the snapshot, and the set is now pinned
  from three directions.** Adding the two fields was not measurably wrong, so the ticket's preferred
  fix is the one that landed. The `order` worry did not survive being checked:
  `CadenceTaskMutationSupport.nextContainerOrder` *reads* the destination's siblings and *writes*
  only the moved task, so putting that one value back is the whole undo - which is exactly what
  `moveToContainer`'s hand-written restore already did, one field at a time.
  **Failing-first, red for the right reason.** A caller that writes `title`, `priority` and `order`
  through `CadenceTaskFieldEditCommit.commit` over a refused save: `(task.title -> "Ship the beta")
  == "Ship the fix"` and `(task.order -> 41) == 3` both failed while `priority` came back, which is
  the "restores part of any edit" sentence as an assertion.
  **The stated boundary came too, because the omission was silent rather than wrong.** `init` and
  `restore(to:)` were two lists nothing held level, so the new
  `thefieldSnapshotCapturesAndRestoresTheSameSixteenFields`
  harvests both and requires each to be the same sixteen, named individually rather
  than counted - a count would let one field drop out while another arrived. The type's doc now says
  which fields are deliberately outside (`notes`, `actualMinutes`, `calendarEventID`, `createdAt`,
  the `recurrenceEnd*`/`recurrenceSource*` group, `goal`, `bundle`, and the to-manys) and why.
  Mutations, isolated tree, all four `KILLED` by name: dropping `task.title = title` and dropping
  `task.order = order` each fell to both behavioural tests *and* the scan; adding a seventeenth
  `task.calendarEventID = ""` to `restore(to:)` fell to **the scan alone**, which is the evidence the
  symmetry check earns its place - no behavioural test observes that field.
  4121 tests, 0 failures, 0 warnings over a run that recompiled `CadenceTaskFieldEditCommit.swift`.
  Residue: [[T-765]] - the two hand-written near-copies can now be folded onto the shared unit, which
  is what T-701 was ultimately about.

- [T-725] **CLOSED 2026-09-03 - `@discardableResult` stays, and now has an expiry date instead of an
  argument.** Decided against removal. `_ =` compiles, so removing the attribute converts a silent
  discard into a visible one and stops there, while
  `everyProductCallerOfMoveToContainerGuardsOnTheAnswer` already requires a literal `guard` at every
  product call site - strictly stronger than "the answer is spelled out", and enforced where the
  defect lives. Five `_ =` in tests buy nothing that scan does not hold.
  What the attribute *did* lack was any statement of who it is for.
  `themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse` harvests every
  `CadenceTaskMutationSupport.moveToContainer(` under `CadenceTests/`, classifies each by the text in
  front of it (`(`, `!`, `=`, `guard`, `return` = consumed; anything else = discarded), and requires
  exactly the five discarders the ticket named - `TaskContainerAssignmentTests` x4 and
  `CadenceTaskContextInheritanceTests` x1 - plus exactly 8 consuming calls as the non-vacuity half.
  So the attribute is kept for a named, shrinking set: when the last of the five goes, the test goes
  red and the attribute has no beneficiary left to justify it. Mutation: `_ =` at the
  `CadenceTaskContextInheritanceTests` site, `KILLED` by that test.
  `CadenceTaskMutationSupport.swift` itself was untouched - it belonged to another agent for the
  batch, and the decision needed no edit to it.

- [T-650] **CLOSED 2026-09-03 (`743ddcf`) - the lock is a FIFO now, and the ordering was shown
  rather than claimed.** A waiter files a ticket in `${LOCK}.queue` named by a microsecond arrival
  stamp, and only the ticket at the head may call `mkdir`; everyone else stands aside. So "next"
  means "waiting longest", not "whose 10-second sleep happened to end first". The queue lives
  outside the lock directory on purpose - `release` does `rm -rf "$LOCK"`, which would delete the
  queue of everyone waiting on it - and `status` now prints it, holder first.
  **The trial is the ticket's own sentence.** `test-host-lock.sh selftest` queues w1..w3 behind a
  held lock and starts w4 *at the instant of release*. With no queue, w4's very first `mkdir` lands
  on a free lock while the other three are still asleep, so the newest arrival is served first -
  deterministically, which is why this discriminates where evenly staggered waiters do not: with a
  1.2s stagger inside a 10s poll, phase order and arrival order agree by accident and the unfair
  lock passes. Against `git show HEAD:scripts/test-host-lock.sh`, three runs of three:
  `w4 w1 w2 w3`. Against the new one, three of three: `w1 w2 w3 w4`.
  **Both safety properties are in the same selftest, and were re-proven, not reasoned about.** An
  expired lease whose owner pid is dead is still NOT reclaimed while a test host is live (the
  conjunction is what stops a second host against the one app-group container), and the same lock
  *is* reclaimable once that host is gone. A waiter killed with SIGKILL - no trap can run - does not
  hold its place: the next waiter prunes the ticket and takes the lock. The prune is
  liveness-**and**-age, because a stopped process is indistinguishable from a dead one and just as
  bad for the head of a queue; a live waiter whose ticket is pruned re-files it under its original
  arrival stamp, so pruning can never cost anyone their place.
  **Mutation-tested by hand**, since `mutate.sh` drives Swift suites by name and there is no Swift
  here: removing the head-gate fails only the ordering trial, widening the live-host conjunction
  fails only the no-reclaim trial, disabling the prune fails only the killed-waiter trial. Each
  mutation was confirmed landed by byte comparison against a `cp` backup.
  **The price is stated in the header where the escape hatch is**: release-and-re-acquire no longer
  wins, so a mutation batch of a dozen short runs interleaves with siblings instead of monopolising
  the host. One lease across many runs is still `xcb.sh <id> raw test`, verified end to end under a
  held `k1-lease` - three consecutive `raw test` runs, none of which acquired anything and none of
  which deadlocked, with the lock still recorded to `k1-lease` after all three. Poll halved to 5s:
  with a FIFO that interval is handoff latency, not a race window.
  **Confirmed on the real lock, not only in the harness.** A sibling (`xcb-k3`) arrived 20s into
  that held lease, queued behind it for 35s rather than racing for it, and was served on release;
  and three waiters filed 4s apart against the real `${TMPDIR}` lock were listed in arrival order by
  `status` and served `A B C`. An earlier full-suite run showed two real siblings (`xcb-integfix`,
  `xcb-k3`) queued behind it in arrival order, which is the shape that used to be invisible.
  Residue: [[T-748]], [[T-749]], [[T-750]].

- [T-621] **CLOSED 2026-09-03 (`db1e9c6`) — focus minutes are a ledger of sessions now, and the
  counters are repaired from it rather than replaced by it.** The three `+=` sites wrote CloudKit-
  synced scalars, so two devices that each banked a session kept one: each read the same starting
  value, each wrote its own sum, and the record that arrived second won. `GoalContributionSummary`
  folds `actualMinutes` into an hours-mode goal, so the loss showed up as wrong goal progress.
  **`FocusSessionLog` is one row per increment**, carrying `minutes` and `previousMinutes` — the
  counter's value immediately before that increment, on the device that wrote it. Rows merge;
  counters do not.
  **The counters stay, deliberately.** Around twenty surfaces read them (duration labels, timeline
  blocks, task embeds, the inspector, the export archive, the MCP task detail, goal progress) and
  they are what moves before any sync. Making the ledger the only reader would have meant rewriting
  every one of them in the same change, and one missed would show a user their logged time
  vanishing — worse than the defect.
  **There is no backfill, and that is the answer to the hard part.** The legacy total the ledger
  inherited is `min(previousMinutes)` across a subject's rows: the first row ever written recorded
  the counter as it stood before the ledger existed, and each device's own `previousMinutes` only
  climbs from there, so the minimum is that number no matter how many devices wrote in what order.
  The correction is therefore `max(counter, min(previousMinutes) + Σminutes)` — **a pure function of
  the counter and the rows**, so running it twice lands on the same number. That matters because
  this project has no `SchemaMigrationPlan` and so no run-once hook to hang a backfill on: the pass
  is meant to run on every launch on every device, for ever. It **only ever raises**, so a store
  that has received a fraction of CloudKit's rows is a no-op rather than a loss — the conservatism
  `DataIntegrityRepairService`'s doc comment demands of an unattended startup pass, and the `max`
  merge rule this repository had already chosen for this very field.
  **Two application points.** `CadenceFocusLedger.bank` raises the subject it is about to write to,
  so a task you focus again heals itself with no sweep and no fetch; `reconcile(in:)` is the
  store-wide pass for the ones you never open again. **The launch hook is not landed** — its one
  line belongs in `PersistenceController.performStartupMaintenance`, which was another agent's file
  this batch. [[T-742]].
  **Banking inserts now, so it takes a `ModelContext`.** The first spelling reached
  `task.modelContext` and `CadenceSaveCommitDisciplineTests` half 3 caught it: on the macOS timer's
  path nothing committed at all. The context is threaded through `CadenceFocusSupport`,
  `FocusManager.startFocus`/`commitElapsed`/`endSession` and their call sites, which is the rule's
  own statement that the caller owns the unit of work.
  **Surfaces reached, all four `Cadence/Models/AGENTS.md` requires:** `CadenceSchema`,
  `PrivacyDataResetService`, the export archive (`CadenceArchiveFocusSessionLog` plus its table and
  both surface suites' probes), the MCP read surface (`CadenceTaskDetail.focusSessionCount` and the
  plugin smoke test's key set), and the markdown-source classification.
  **A side effect worth recording: the ledger made [[T-654]] visible to the rule.** That ticket's
  most interesting claim was that *no half of the rule could see it* — nothing was inserted or
  deleted. Banking is an insert now, so half 1 finds `CadenceFocusSupport.endSession` and
  `iOSFocusView.logBundleSession` on its own; both are held in `existenceExemptions` naming T-654,
  and `FocusView.bundleTimerControls` joined `timerControls` in `commitReachExemptions`. The ledger
  also downgrades the consequence: a refused save leaves the row *pending* rather than losing the
  minutes, and the next reconcile puts the counter back.
  Pinned by `CadenceFocusSessionLedgerTests` (15 tests). **Mutation-tested**, eight mutations, eight
  killed by name — the baseline as a `max`, no baseline at all, a reconcile allowed to lower, `bank`
  without the raise, `previousMinutes` recorded after the increment, the list counter left without a
  row, a row inserted but never linked, and a refused completion leaving its row behind.

- [T-733] **CLOSED 2026-09-03 (`517982e`) — the stored default is gone and the rows that hold it are
  cleared at load.** `Note.title` defaulted to the literal `"Untitled"`, which made the word stored
  text rather than a placeholder: `createPermanentNote` interpolated it into the seeded body, the
  editor put the caret after the heading, and typing `Target` produced `UntitledTarget`. The default
  is empty now in all three places that carried it — the stored property, the initializer parameter,
  and `NoteMigrationService.createPermanentNote` — and `Note.displayTitle`'s existing per-kind
  fallback does the naming (`"Notepad"` for `.permanent`, the date key for `.daily`, `"Untitled"` for
  `.list`). Those five fallback strings are untouched: [[T-609]]'s standing decision is that each
  draw site keeps its own copy, and this was the stored model default, a different thing.
  **`CadenceListNoteFiling.seededContent` lost its `"Untitled"` substitution in the same change, and
  that is not a widening.** The branch was unreachable while the model default was the same word.
  Dropping the default is exactly what would have made it fire, and `MarkdownNoteTitleSync` reads the
  first line of the body — so a seeded `# Untitled` would have re-titled every new list note
  `Untitled` on its first commit and the load-time pass would have cleared it again on the next
  launch, forever. `"# \n\n"` is still an H1, so it is still the rename control from the first
  keystroke; it is just empty, and an empty H1 is the one case `MarkdownNoteTitleSync` deliberately
  says nothing about.
  **A data edit at load, not a schema change**, because a property default is applied by the
  initializer and never reaches a row already on disk. There is no `SchemaMigrationPlan` in this
  project and this needs none — no column is added, removed or retyped.
  `DataIntegrityRepairService.repairStoredDefaultNoteTitles` sits beside the out-of-range-habit-
  reminder pass and adds one counter, `defaultNoteTitlesCleared`.
  **Idempotent by construction rather than by a marker, which is what makes "no migration hook"
  fine.** The predicate is "this title is exactly the retired default" and the edit makes it the
  empty string, which is not that literal — so a second run matches nothing, the counter stays 0,
  `changed` stays false and no save is taken. There is no "already migrated" flag to get out of step
  with the store, so a second launch, a second device, and a row that arrives from CloudKit *after*
  the pass ran all reach the same fixed point; every device writes the same empty string, so it
  cannot ping-pong. Asserted as *no second write* rather than "the title is still empty" — the run
  that cleared it twice would satisfy that too — and a third pass is asserted as well, because a
  fixed point has to be a fixed point rather than an alternation.
  **Safe under partial sync** for [[T-328]]'s boundary: the predicate reads one scalar on the row in
  front of it, so no record arriving later can turn a false positive into a true one; a half-synced
  store simply sees fewer `Note` rows.
  **The accepted cost, stated because the user was told it and accepted it: this also clears a title
  someone typed as "Untitled" on purpose.** The store cannot tell that note from one the old default
  named — same bytes, no provenance on the field — so no predicate separates them.
  `theMigrationAlsoClearsATitleAUserTypedOnPurpose` pins it so nobody narrows it later believing it
  was an oversight. What such a user loses is small and visible: a `.list` note reads `Untitled`
  either way, a notepad note reads `Notepad`, and retyping the title restores it.
  **The literal is frozen in the pass and is deliberately *not* `CadenceTitleNormalization
  .defaultCompactTitle`.** That constant is the app's display placeholder and is free to be renamed;
  this is a historical value, the exact bytes a retired initializer wrote, and a migration that
  stopped matching them because a display string was reworded would silently stop migrating.
  **Did any note legitimately hold the title? Not measurable from here, and not claimed.** Nothing
  in the repository's fixtures or the shipped code writes `"Untitled"` to `Note.title` except the
  retired default, so every row this pass can reach in a *test* store is a default. The user's real
  store was not read — the runbook forbids touching `~/Library/Containers/com.haoranwei.Cadence/` —
  so "no note legitimately held it" is an inference about the code, not an observation of data.
  Nine tests in `CadenceStoredNoteTitleDefaultTests`; failing-first was established by reversion
  mutations rather than by a pre-fix run, and all nine mutations were **KILLED** with the killing
  tests named: the property default (M1), the initializer default (M2), the factory default (M3),
  the seeded heading (M4), the pass not called (M5), the pass matching rows it already cleared
  (M6, the idempotence mutation — killed by `runningTheMigrationTwiceIsAnEmptySecondPass`), the
  predicate trimming (M7), the counter not reaching `changed` (M8), and clearing to a space instead
  of empty (M9).

- [T-496] **CLOSED 2026-09-03 (`ef8cb53`) — 0.08em everywhere, and the two literals are gone rather
  than retyped.** The user took the decision. `CadenceBoardColumnHeaderMetrics.labelKerning` and
  `CadenceCalendarWeekdayHeaderMetrics.labelKerning` each read
  `labelSize * SectionEyebrowLabel.kerningRatio` now, so the ratio is what is shared and the size
  stays each file's to state. The board column header's tracking doubled (0.4 → 0.8) and the weekday
  label's gained 60% (0.5 → 0.8); the ~50 `SectionEyebrowLabel` sites and the 9pt compact tier did
  not move at all.
  **Retyping both as `0.8` would have been the same defect one value later** — three independently
  editable constants that happen to agree, with `kerningRatio` read by one file again — which is why
  no file may state the number.
  **What the rewritten `CadenceUppercaseLabelTrackingTests` asserts, and why it is a derivation
  rather than three agreeing literals.** The value assertions (`== 0.8` three times) are explicitly
  *not* the claim; they pin what a reviewer looked at. The claim is three identities that re-derive
  each tracking from the size in front of it and the one ratio, plus
  `everyUppercaseTrackingReadsTheOneRatioRatherThanRestatingIt`, which reads both declarations as
  source and requires each to *name* `SectionEyebrowLabel.kerningRatio`. **Mutation M12 is the
  evidence**: flattening the board tracking to a hand-typed `0.8` that agrees with both siblings
  passes every value assertion in the suite and was **KILLED by that source test alone**. M13 is the
  same flattening on the weekday header. M10 and M11 revert the two literals and are killed by the
  value assertions as well, which is the failing-first half.
  The literal-ban needle is anchored to the *declaration* (`letlabelKerning:CGFloat=0.`) rather than
  to the digits, because `CadenceBoardColumnHeader.swift` legitimately carries
  `accentRuleOpacities = [0.85, 0.45, 0.16]` and a bare `!contains("0.8")` reads the whole file —
  the runbook's "a regex turned loose on a body" rule, one file over.
  The 4-of-6 citation graph is still asserted, including the two edges that do not exist.
  Change the ratio and all three move together; that is a decision, and the suite passes through it.

- [T-452] **CLOSED 2026-09-03 (`ef8cb53`) — closed with [[T-496]], and the ticket's own word was
  backwards.** The capture was done on 2026-09-02 and its numbers are restated here rather than left
  in the retired open entry: all eight labels rendered at 1x and 3x, before against after, each
  pre-[[T-284]] value recovered from the conversion commit `96b5583`. **None of the six was tightened — every one was loosened.**
  0.45, 0.54, 0.54, 0.60, 0.60 and 0.70 all went to 0.72, and the two that carried no tracking at all
  gained 0.72. A reviewer told to look for tighter labels would have been looking for the wrong
  thing, and that correction is the thing worth carrying forward from this ticket.
  At native size the six are indistinguishable from before — `AIActionsSupportViews` is a literal 0pt
  change — so the judgement T-284 recorded is not observable on them. **The two that gained tracking
  are the visible win**: `AREAS` and `PROJECTS` were set solid and cramped and now read as labels.
  Those two were defects and are fixed. No defect was found anywhere in the eight; nothing crowds,
  clips or overflows. Captured offscreen, not in-app — `scripts/run-macos-app.sh` refuses while the
  user's own Cadence is running (see [[T-730]]).
  T-496 landing makes the remaining ask moot in the direction that matters: the compact tier and the
  two 10pt roles now derive from one ratio, so there is no second number left for a screenshot pass
  to arbitrate.


- [T-726] **CLOSED 2026-09-03 (`eb54eae`) — the sheet's `onAppear` no longer writes to the store.**
  `applyContainerSelection` asks `CadenceTaskMutationSupport.isAlreadyInContainer` one frame above
  the commit — the same question `assignContainer` already asks internally, asked where it can stop
  the commit being reached at all. Not a suppressed notice: the notice was right, the move under it
  was not.
  **The open path loses no write**, which is the half of this ticket that wanted deciding rather
  than assuming: `loadContainerSelection()` has already run `normalizeSectionForCurrentContainer()`
  before the `onChange` fires, and Done flushes through `CadenceInPlaceEditFlush`. The early return
  sits **below** the `isRestoringContainerSelection` guard, so [[T-702]]'s restore still consumes
  its flag.
  Failing-first was red for the right reason — the guard absent, and the ordering assertion — then
  three mutations, each killed by name. **M1** reverts the guard. **M2** keeps the guard but moves
  it below the commit, where it is present and useless; the scan's ordering assertion kills that
  too, which is why the assertion is worth its line. **M3** pushes the guard down into
  `moveToContainer` itself, killing the new behavioural test
  `reassertingTheCurrentContainerStillReachesTheCommit` — and M3 is the argument for *where* the
  guard went: a re-assert really does reach the commit, so the caller is the frame that has to
  decline.
  Residue: [[T-745]]. [[T-725]] and [[T-727]] were not touched and are still open.

- [T-735] **CLOSED 2026-09-03 (`53453b3`) — mechanical rather than documentary, and demonstrated on
  a device.** `simulator-claim.sh launch` passes `-CadenceSuiteName <id>`; `CadenceDefaults` reads
  that argument domain into a per-agent suite; the scene applies it with `defaultAppStorage`, so all
  126 `@AppStorage` sites follow; and `CadenceCalendarDateMemory` — plain storage, so the scene
  redirect does not reach it — defaults to the same store. With no such argument
  `CadenceDefaults.store` **is** `UserDefaults.standard`, so nothing here reaches a user's device.
  **Observed 2026-09-03 on the claimed iPhone 17 Pro**, whose shared domain still held the incident
  itself: `ios.calendar.selectedDateKey = "2026-08-17"`, `anchorDateKey = "2026-07-26"`,
  `viewMode = "Month"`, `presentation = "Timeline"`, `ios.compact.selectedTab = "notes"`. Same
  private store, one launch apart, differing only by the argument: **without** it the app opened on
  Notes; **with** it, on Tasks/Today, and the Calendar tab opened on **Sep 3 in Week view**.
  Afterwards `com.haoranwei.Cadence.agent.j4.plist` held only my own tab, and
  `com.haoranwei.Cadence.plist` still held all five of the other agent's keys, unchanged. The
  reinstall did not clear them, which is the claim script's own point about the app-group store, one
  domain over.
  Five mutations, all killed by name: both wirings, the launch argument, the id sanitiser, and one
  suite shared by every agent — isolated from the device-wide domain and *not* from each other,
  which is the half that actually cost the twenty minutes.
  Not covered, and said so in the doc comment rather than left to be discovered: an icon-tap launch
  carries no arguments, and the service layer's direct `UserDefaults.standard` reads are still
  shared. Both are [[T-745]].

- [T-713] **CLOSED 2026-09-03 (`fba681a`). The cards move once, at the commit point, and neither
  ruled-out repair was taken.** `applySectionEdits` ran on every keystroke and ended with
  `moveTasks(from: base.name, to: trimmed)` against a `base` frozen by [[T-358]] and never advanced,
  so only the *first* keystroke found any cards: `Doing` → `Doingxy` moved them to `Doingx`, then
  looked for cards still called `Doing` and found none. The config, matched by `uuid`, reached
  `Doingxy`, and `resolvedSectionName` falls back to Default only for an **empty** name — so the
  cards were filed under a column name that existed nowhere.
  **The decision was the commit point [[T-645]] created**, and it holds: `applySectionEdits` writes
  the blob and moves nothing, `commitSectionEdits` applies, moves and then flushes, so the rename and
  the cards it re-points reach the store as one commit and a refusal leaves them agreeing rather than
  stranded apart. An intermediate name never touches a card.
  **`editorBase` is still assigned in exactly one place** — pinned as a count, because advancing it is
  the one-line repair this ticket named and refused. Nothing about `AppTask` changed either.
  **The move is `KanbanSectionStateSupport.moveCardsToStoredName`, and every part of its shape is a
  guard.** Its source is `filedCardName`, where the cards actually are, because Return-type-more-pick-
  a-colour is one session with two commit points and by the second the cards have left the name the
  popover opened with; that is a second piece of `@State`, `editorFiledCardName`, which advances while
  `editorBase` stays frozen for the merge. Its destination is read back **out of the container** by
  `uuid` and must equal the name the caller typed, so a rename the apply declined — empty, or
  colliding — moves nothing. Deliberately not `CadenceSectionConfigMerge.sectionNameMoves`, which
  diffs whole arrays for what a *save* implied and would send this list's cards to Default behind a
  colour press if another device had removed the column.
  **`deleteSection` walks `filedCardName` too**, which is not tidying: a column typed into and then
  deleted without committing had a config saying `Doingxy` over cards saying `Doing`, so the delete
  found nothing to move and stranded the whole stack. Reachable from keystroke two before this change;
  deferring the move would have made it reachable from keystroke one.
  Pinned by `CadenceKanbanColumnLifecycleSurfaceTests.theRenameCommitFilesEveryCardUnderTheNameTheStoreTook`,
  `.aRenameTheStoreRefusedLeavesEveryCardWhereItWas`,
  `.aColourPressStillCannotWriteAStaleNameOverARenameFromAnotherDevice`,
  `.theRenameMovesItsCardsOnceAtTheCommitPointRatherThanPerKeystroke` and
  `.theOldPerKeystrokeRenameStrandsTheColumnsCardsUnderANameNoColumnHas`, the last of which drives the
  *old* policy out of shipped API, asserts the strand, and passes on both sides of the fix by design.
  **Nine mutations, all killed**, including the defect restored two ways, the ruled-out `editorBase`
  advance, and — the one that makes [[T-358]]'s guarantee a measurement rather than a claim —
  un-freezing the field-level diff in `CadenceSectionConfigMerge.applyingChangedFields`, killed by
  the colour-press test.
  **Residue:** [[T-736]] the column draws empty while the rename is being typed, [[T-737]] the archive
  and completion controls still settle on the config's name, [[T-738]] the blob is rewritten per
  character.

- [T-280] **CLOSED 2026-09-02 (`0b3f2d2`) — settled affirmatively on a simulator, and the item's
  own blocking premise was wrong.** `docs/device-checks.md` said no simulator action can put an
  image on the device pasteboard. **It can**: `simctl addmedia`, then Photos → long-press → Copy,
  puts a real PNG on `UIPasteboard.general` and nothing else. `simctl pbcopy` does **not** — it
  lands a PNG as *text*, and Paste then inserts `\x89PNG IHDR…` as prose, which is exactly the
  false negative the old claim would have produced. Both kept in the doc as a trap.
  **The predicate, observed:** with a real PNG on the clipboard and the caret in an iPad note, the
  edit menu read `Paste | Select | Select All | AutoFill`, and Paste **inserted the picture drawn
  as an image**, not as `![](cadence-image://…)` text. So UIKit does consult
  `iOSMarkdownTextView.canPerformAction` for `paste:` when building the menu, and `paste(_:)` is
  dispatched.
  **The discriminator is what makes that proof rather than coincidence**, because "Paste appeared"
  alone is consistent with `super` offering it. Same clipboard, same gesture, one tap apart: the
  quick-create composer in **Event** mode — a refusing host — offered **AutoFill only, no Paste**.
  Nothing but `allowsMarkdownImageInsertion` differs between those two text views, so `super`
  cannot explain Paste in one and not the other. That is [[T-504]]'s
  `aRefusingHostDoesNotOfferPasteForAScreenshot` on screen.
  The ticket's own instruction was right: *"do not close this by reading the diff — a correct
  `paste(_:)` override that was never dispatched is exactly how the macOS bug survived."* It was
  tapped.

- [T-565] **A shared guard against the T-333 / T-337 / T-352 class: comments asserting machinery the
  code no longer has.** Three tickets this week were the same defect — prose naming a mechanism that
  does not exist, which is worse than a missing mechanism because it stops the next reader checking.
  Proposed by the T-352 agent, which was asked to report rather than build it.
  The instrument already exists: `CadenceScanInstrument`, plus the `strippingComments`-vs-raw pairing
  that ticket's third test uses to prove a sentence lives in a comment. A sweep would pin a small
  registry of **retired mechanism phrases** (`SceneStorage`, `todayDateSections`,
  `SidebarStaticDestination`, ...) as absent from comments in files where they are also absent from
  live code — i.e. flag prose asserting machinery no live line in the same file references.
  **Keep the registry hand-curated.** A fully automatic version would fire on legitimate tombstones,
  which this repo uses deliberately and well — 22 of them survive [[T-487]] on purpose. The value is
  in catching the *claim*, not the *memorial*.
  Use `strippingComments`, never `codeOnly` — `codeOnly` blanks string literals too, which is what
  made an earlier copy scan permanently and silently green.
  **CLOSED 2026-09-02 (`9bbc267`).** Built as a *name-resolution* rule rather than a phrase registry,
  after measuring both. `CadenceCommentSymbolClaimTests` sweeps every Swift file in all five targets
  and flags a backticked `<Type>.<member>` in a **comment** whose type is nominal-declared here and
  whose member is declared neither on any type of that name nor in a file named after it. Population,
  measured: 23,256 backticked spans in comments, 2,123 of them qualified by a repo-declared root, **39
  that resolve to nothing**. Before this there were **zero** — no test in the repo read prose for
  symbol existence at all.
  **The registry idea was tried and dropped.** A hand-curated list of retired phrases only ever
  catches phrases someone thought to add; the arithmetic version catches the *shape*, and the
  tombstone problem this ticket warned about turned out to be solvable by ledgering rather than by
  curation. 30 of the 39 are memorials or counterfactuals and are marked as such; **9 are live stale
  claims** and belong to [[T-716]]. The split cannot be derived — no arithmetic tells a memorial from
  a claim — so it is recorded per entry, in both directions, and a new offender or a repaired one
  turns the suite red.
  **Four exclusions, each pinned by the case it exists to let through**: an SDK-rooted claim
  (`ModelContext.save()`) cannot be checked at all; a `commit*` glob names a family; `Theme.swift`
  parses as `<Type>.<member>` and is a path; and `<FileBaseName>.<symbol>` is this repo's spelling
  for a fileprivate type — that last one also swallows a real confusion, filed as [[T-717]].
  **What it cannot see, stated rather than found later.** Prose with no symbol in it — [[T-563]]'s
  entire ticket was a wrong premise carried in English for days, and nothing here would have fired on
  it. Unqualified names (24 distinct, measured, [[T-718]]). And claims about *behaviour* rather than
  existence: [[T-555]]'s `static let`-only sentence and [[T-625]]'s two-device merge both name symbols
  that still resolve.
  A third reader was needed and is now shared-shaped: `codeOnly` blanks comments **and** literals and
  `strippingComments` blanks only comments, so neither hands back the prose. `partition` splits source
  three ways in one traversal, its code half pinned equal to `CadenceSourceScan.codeOnly` on the four
  inputs that separate a correct lexer from a plausible one, and every non-blank character of forty
  real files asserted to belong to exactly one of the three halves.
  Seven mutations, six killed — including one that caught a real detector bug before it landed: a
  member pattern without a backtick reads `static var` + a backtick-escaped keyword as undeclared and
  accuses two correct comments. The survivor is the weakened ledger comparison, reported as
  *inconclusive* and settled by its pair, per the runbook's rule.

- [T-686] **CLOSED 2026-09-02 (`ff7bb14`).** Fixed as written — one line, no copy changed, the
  fallback still "Untitled" and now trimmed before it is tested. **The ticket's prediction held and
  was measured rather than assumed:** HEAD's unmodified test file, run against the fixed source,
  fails with `(hits → []) == (sitesLeftForAnotherOwner → ["Cadence/macOS/Views/TasksPanelComponents
  .swift"])`, so deleting the entry really is part of the fix rather than a tidy-up after it.
  **What the entry's deletion cost, and what replaced it.** `hits == [one path]` was self-proving:
  blinding the reader emptied the hits and the equality went red for free. `hits.isEmpty` is not —
  a blinded reader satisfies it without reading anything, which is exactly what mutation M8 did to
  the neighbouring trimmed-test sweep during [[T-609]] and survived. So the reader is asserted
  before the result is believed, the way that neighbour already does it, and mutation M2 (swap
  `strippedSourceReader()` for a `codeOnly` one) now kills this test on that assertion. M1 (the
  ternary returns) kills it on the sweep. With this closed, the inline spelling is **0 sites**
  across all three targets and the sweep asserts an empty set rather than a remainder.

- [T-702] **CLOSED 2026-09-02 (`9a1dc68`).** All three guard, and the four callers of
  `moveToContainer` now say one sentence — `CadenceTaskFieldEditCommit.saveFailureNotice`, the one
  the kanban picker already showed.
  **Premise correction, and it changed the fix.** The ticket says each of the three is driven by a
  `@State` token the user just changed. That is true of `iOSTaskDetailSheet.applyContainerSelection`
  and **not** of the two in `iOSTaskRowActionViews`: the row's menu checkmarks read `task.area` /
  `task.project` directly and its popover's selection binding is a computed `currentToken`, so both
  self-correct on the restore. What those two were actually reporting is the *dismissal* — a `Menu`
  closes itself, and `iOSContainerChoicePopover.choiceRow` sets `isPresented = false` in the same
  statement that picks the list. So the picker shut over a move that did not happen, which is the
  same claim by a different mechanism and is **not** fixable the way the kanban site is: that
  dismissal belongs to a shared component with three other callers, not to these two.
  **So two shapes.** The sheet stays open and reports inline, into the notice slot it already draws
  (one notice per surface, [[T-646]]'s decision, rather than a second flag the two could disagree
  through). The row raises `iOSTaskMoveFailureAlert` — an alert for the reason
  `iOSTaskDeleteFailureAlert` records one action over, and **one** modifier for both affordances,
  because the chip and the context menu are two ways to make one move. The only new copy is the
  title, `CadenceTaskMutationSupport.moveFailureAlertTitle`.
  **The restore re-enters and is guarded.** Putting `containerSelection` back fires `onChange`
  again; unguarded, the second pass re-commits the refused move and clears the notice the first set.
  The flag is raised only when the token will actually change, so it cannot outlive its own
  `onChange` and swallow the user's next pick — mutation M9 deletes that condition and is killed.
  **Pinned as a set:** `everyProductCallerOfMoveToContainerGuardsOnTheAnswer` walks `Cadence/` and
  names the four surfaces exactly rather than asserting a floor. Against unmodified source it named
  the discarding sites precisely — `iOSTaskRowActionViews.swift (2 of 2)`,
  `iOSTaskDetailSheet.swift (1 of 1)`. Residue: [[T-725]], [[T-726]], [[T-727]].

- [T-715] **CLOSED 2026-09-02 (`ad51f30`). Both, and they are about different things.**
  **The default goes**, for the ticket's own reason and [[T-564]](b)'s: both call sites pass
  `dropKey:`, and a defaulted argument nothing supplies is the half most likely to be wrong the day
  somebody reaches for it. Deleting it costs the existing callers nothing and makes the next one say
  `dropKey: nil` out loud, which is a claim about its group rather than an argument it forgot.
  **The `nil` arm stays, and "exercised by nothing" was true only of the tests** — that is the
  premise correction. `CadenceTaskDropSupport.dropKey(forGroup:)` answers `nil` for
  `.todayDate(.overdue)`, `.todayDate(.pastDo)` and `.completion`, so every row drop inside Today's
  Overdue, Past-do and Completed groups already takes that arm in the shipping app. It is live
  behaviour, and the asymmetry with `handleSectionDrop` is what makes those drops an ordinary
  reorder instead of [[T-591]]'s silent accept.
  So it is characterised: `arowDropIntoAGroupWithNoKeyReordersAndAssignsNothing` asserts a keyless
  drop reorders and assigns nothing, **paired** with the same coordinator taking a key, because
  "assigned nothing" is worthless from a coordinator that calls nothing; and
  `thegroupsThatOfferNoDropKeyAreTheOnesARowDropOnlyReorders` pins the three groups that reach it.
  That test **passes against unmodified source, correctly** — it describes behaviour this change
  does not alter — so its teeth are mutations M4 (the arm invents a key) and M5 (the arm stops
  reordering), each of which kills it. M3 (the default returns) kills the source pin.

- [T-530] **A stale mutation needle reads as a surviving mutant.** Found by the T-516 agent, on itself.
  Its `assert old in s` went stale when it renamed a function; Python raised, the zsh runner had **no
  `set -e`**, so the mutation silently never applied and the run reported `EXIT=0` — which reads exactly
  as *"the mutant survived"*. **Closed 2026-09-02 in `180ac76`.** The rule was re-proved four more times
  after it was written, each a different quiet failure, so it is `scripts/mutate.sh` now rather than a
  paragraph agents are told. **Five modes, each induced deliberately, both in `mutate.sh selftest` (46
  checks, no build) and end-to-end against `HabitFrequencyLabelTests` / `Cadence/Models/ModelEnums.swift`
  in an isolated tree.** (1) *Stale needle* → `NEEDLE-ABSENT`. (2) *A self-check that passes when it
  should fail*: the check was `old in text`, so a replacement **containing its own anchor** —
  `return "Daily"` → `return "Daily" + "!"` — read as a failed apply, the restore was skipped, and the
  next mutation ran on a doubly-mutated tree. The runner compares **bytes with the `cp` backup**, and
  re-reads each file against its baseline *before* mutating (`NOT-PRISTINE`), so a stranded edit voids
  the next verdict instead of surviving it. In the trial that mutation is correctly `KILLED` by
  `theFullLabelIsUnchanged`. (3) *An ambiguous needle* → `NEEDLE-AMBIGUOUS`, with every occurrence's
  line number named; `return "Daily"` really does occur three times in `ModelEnums.swift` (308, 318,
  459). (4) *A mutation that never compiled* → `DID-NOT-COMPILE`, and the two failures that print **no**
  `.swift:line:col: error:` line at all → `TOOLCHAIN-CRASH` and `NO-TESTS-RAN`. (5) *A survival that
  argues nothing* ([[T-560]]'s pairing rule, mechanised): a mutation with any hunk under `CadenceTests/`
  is inferred to be a weakening, and an unpaired one reports **`INCONCLUSIVE`**, never SURVIVED. Paired
  with the violation the tight form catches, the same weakening reports `SURVIVED` **and names the
  control that was killed**. `KILLED` additionally requires a failing test line and names the tests.
  **Isolation is now the default rather than the discipline**: with no `--tree` the runner builds its own
  `git archive HEAD | tar -x` copy, so a `kill -9` strands the mutation in a scratch directory instead of
  the user's checkout; `--in-place` is required to mutate the repository and says so loudly. It also
  takes the test-host lock **once** per batch (`xcb.sh raw test` per mutation), refuses the batch if the
  **unmutated** suite is not green over a non-zero test count, and calls the **tree's own** `xcb.sh` —
  the repository copy derives `-project` from its location and would test a different tree than it
  mutated. Runbook section: *"A mutation runner that cannot report a survivor it did not earn"*.

- [T-561] **Re-triage `docs/device-checks.md` now that simulator use is established.** The checklist was
  written when nobody could drive anything. Since then agents have driven iPhone simulators successfully —
  [[T-514]]'s before/after and [[T-538]]'s create half both came from one. Several of its 15 steps may now be
  coverable without hardware. **Two genuinely are not**: pasting an image needs a real clipboard, and the
  keyboard-dismiss gesture cannot be exercised because *"the simulator suppresses the software keyboard while
  a Mac keyboard is attached"*. Establish which of the rest a simulator can cover and shorten the list.
  **Closed 2026-09-02 in `151afb2`.** 5 items / 15 steps to 3 items / 8 steps, and one survivor was materially stale.** Removals, each with what took it. **Drag-to-create (item 4, five steps)**: `control`'s `touch_path` drags a single finger along an arbitrary path *including long-press-then-drag* -- every gesture the item asked for -- and `attach` opens a live panel to watch the mid-drag ghost in; everything computable was already pinned in `CadenceCapturePaletteTests` (`aPressThatMovesBeforeTheHoldIsADragImmediately`, `theHoldCannotOpenThePaletteOnTopOfADrag`, `theSmallestContainingFrameWinsAHitTest`, `aPointOverNothingHitsNothing`, `aDropOnARowSeedsThatRowsPlacement`, `aDropOnNothingSeedsWhatATapSeeds`), `CadenceTaskDropSupportTests` and `CadenceTaskGroupDropSupportTests`. Refiled as [[T-722]]. **Both note sheets at iPad width (item 5)**: the item always conceded this is a width question rather than a device one, and **six stock iPad simulators already exist here**, so nothing has to be created -- that residue is [[T-447]]'s, which is open and should be routed to the simulator batch rather than to a phone. **The single-tap caret and wiki-link steps (3.3, 3.4)**: one `tap` each, refiled as [[T-723]]. **Survivors, and why nothing else reaches them**: no simulator action puts an *image* on the device pasteboard, and an empty clipboard cannot enable Paste (item 1, [[T-280]]); the simulator suppresses the software keyboard while a Mac keyboard is attached and the toggle lives in Simulator.app (item 2); and there is **no double-tap action** -- `tap` is one touch, `touch_path` one continuous drag, and two scripted taps are two tool round-trips, far outside iOS's ~350ms window (item 3). **Two staleness findings fixed in passing.** Item 1's failure bullet said an enabled-but-inert **Paste** was *expected* in the note-template editor and the calendar event sheets; [[T-504]] (`dc5da1e`) landed **four hours after** this checklist was last written and a refusing host now advertises no bitmap type at all, so Paste should be **absent** there -- following the old bullet would have reported a defect as expected behaviour (`MarkdownImagePasteAffordanceTests.aRefusingHostDoesNotOfferPasteForAScreenshot`, `CadenceMarkdownImageInsertionScopeTests.theNoteTemplateEditorRefusesImageInsertion`). And item 4's pointer to a drag recipe *"in `AGENTS.md`"* was **stale -- there is no such recipe there, and there has not been**; it went with the item. Separately, [[T-563]] removed a whole routing argument: "the UI target is unreliable" is no longer a reason to send anything to hardware, and the one live intermittency is [[T-710]], a macOS test-timing question.**

- [T-560] **The test target leaks a directory into the user's real app container on every run.**
  **Closed 2026-09-02 in `b31d0b9`. Residue cleared and the mechanism closed — but the leak was not
  reproduced on the day it was fixed, and that is stated plainly because this ticket's causal
  attribution was its strongest part and it did not survive re-measurement.**
  **Residue.** 3,652 directories deleted from `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/`
  (measured 3,268 when the ticket was filed, 3,656 when this started — it had kept growing). Every one
  was confirmed in a single pass to hold exactly one child named `inMemory_store_ckAssets` and for that
  child to be empty; nothing else was touched. The five non-UUID neighbours — `CadenceTestsHostStore`,
  `CadenceUITestStores`, `TemporaryItems`, `com.haoranwei.Cadence.savedState`, `.LINKS` — are all live
  and were left alone.
  **Mechanism.** The thirteen suites each declared their own `makeContainer()`, and all thirteen spelled
  it `ModelConfiguration(isStoredInMemoryOnly: true)` — leaving `cloudKitDatabase` at its default, so a
  CloudKit mirroring delegate attached to a throwaway store. The test target was the only place in the
  repository doing that: the two in-memory configurations in the shipped app
  (`PersistenceController`'s recovery fallback and `CadenceModelContainerFactory.makeInMemoryContainer`)
  already passed `cloudKitDatabase: .none`. They now call one `CadenceTestStore.container()`, and
  `CadenceInMemoryStoreHygieneTests` holds the invariant **repository-wide**, so a fourteenth suite
  cannot reintroduce the spelling — which is the failure this ticket's brief predicted, a Batch C agent
  having already shipped one new suite with the neighbouring defect.
  **What did not hold.** The ticket read 3,176 -> 3,264 over six runs as ~13-15 per run matching the 13
  sites. Finer evidence argues for something stronger, not weaker: the directories arrive in bursts
  whose sizes are exactly the test counts of the suites being run (3 = `MobileTaskSortStabilityTests`,
  10 = `CadenceScheduleOrderingTests`, 4 = `CadenceModelContextRefreshTests`, that triple repeating
  through 2026-09-01), i.e. one per **container**, not per run. But two instrumented runs on 2026-09-02
  covering 21 tests — 19 of them building *and saving through* an in-memory container in the unfixed
  shape, including `CadenceScheduleOrderingTests` itself — created **zero** directories. A third run
  after the fix, 40 tests over five suites, also created zero. **Meanwhile the leak went on happening
  on other agents' runs**: 34 directories appeared between 18:23 and 19:15 that evening, after the
  purge, in two identical cycles of 3 / 10 / 4 spaced 41 minutes apart. So the burst-size evidence is
  confirmed on fresh data and the fix is still unproven — it has never been observed either failing or
  succeeding on a run that was going to leak. So the fix is correct on its own terms (a unit test has
  no business attaching a mirroring delegate) and is the only mechanism that fits the residue, and it
  is **not** demonstrated to be the fix. [[T-704]] carries the open question and the way to settle it.

- [T-517] **~1.7 GB of shared DerivedData belongs to scratch trees that no longer exist.**
  **Closed 2026-09-02 in `b31d0b9`.** 13 of the 14 entries removed, 1.68 GB (3.5 GB -> 1.8 GB).
  **The judgement this ticket said no script should make unattended turns out to be mechanical.**
  Xcode's DerivedData suffix is a pure function of the absolute project path: MD5 of the path, split
  into two big-endian `UInt64`s, each rendered as 14 base-26 letters **most-significant digit last**.
  That was verified as a positive control *before* it was trusted — it reproduces
  `Cadence-cfagpqwpaaoeixfvenakmzkidwtg` from `/Users/williamwei/Desktop/Projects/Cadence/Cadence.xcodeproj`,
  which is the one live entry. Every `Cadence.xcodeproj` on the machine was then hashed (8 of them,
  including four sibling agents' scratch trees) and **none matched any of the 13**, so each was
  attributable to a path that no longer exists. Three independent checks agreed, and all three had to:
  none of the 13 had an `info.plist` at all (so no `WorkspacePath` to strand), none had
  `Build/Products` — each held only `Logs/` and 129 MB of `SourcePackages/`, so the T-86
  wipe-under-a-running-app mechanism could not apply — and `lsof +D` reported zero open files under
  every one.
  That shape is also the ticket's other half: `Logs/` + `SourcePackages/` and no `Build/` is the
  signature of an `xcodebuild` invocation carrying **no** `-derivedDataPath`, which resolves packages
  into the shared root. The documented surface is already closed —
  `CadenceBuildInvocationHygieneTests` requires a private path on every invocation in this
  repository's markdown fences and shell scripts, and `scripts/xcb.sh` refuses the shared root and
  reports a leak afterwards. What remains uncovered is an *ad hoc* command typed outside both, and
  nothing prunes an entry once it appears: [[T-705]].
  Also cleared from `/private/tmp`, each identified before deletion, ~32 MB: `final-Cadence.log`,
  `final-CadenceMCPServer.log`, `final-CadenceWidgets.log` and four `orphan-build-*.log` (xcodebuild
  logs from 2026-08-29 — each names its own private `-derivedDataPath` on its first line);
  `head_CadenceTaskMutationSupport.swift` (a snapshot of an older revision of
  `Cadence/Shared/CadenceTaskMutationSupport.swift`, which has 30 revisions in git, so nothing unique
  was in it); two `Cadence_2026-08-30_*.sample.txt` (`sample` output from a debug build at
  `/private/tmp/*/Cadence.app`, **not** `/Applications`); and `cadence-swift-module-cache` (30 MB,
  zero open files).
  **`/private/tmp/cadence-uitest-auth` was deliberately left in place, and it is not what its name
  says it is** — see [[T-706]]. The rest of `/private/tmp` is in that ticket too.

- [T-647] **CLOSED 2026-09-02 (`e9fbafa`).** Re-attributed, not deleted — the exemption is a real
  finding and only its explanation was wrong.
  Premise verified: `NoteEditorPane.swift` contains no `insertSubtask` and no `deleteSubtask` at all,
  and its only subtask symbol, `toggleEmbeddedSubtask`, is a field edit. **What `body` actually
  reaches is one qualified call, in `.onAppear`:**
  `TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)`, which resolves the note's frontmatter
  tags and mints any `Tag` row that does not exist yet, down through `TagSupport.resolveTags` into
  `resolution` — every frame of which was handed its context, so the pending insert travels up to
  `body`, which reached for the ambient one and commits nothing. So the entry belongs with the other
  two `NoteEditorPane` entries beside it: it is the [[T-631]] tag family, not [[T-634]]'s subtask one.
  **It is an identification rather than a guess, and that is asserted.** `body` makes **exactly one**
  qualified call in total, and no declaration in the file takes a `: ModelContext` parameter — so the
  rule's unqualified candidate set is empty and its qualified one has a single member. Pinned by
  `CadenceInlineTagCommitSurfaceTests.theNoteEditorPanesBodyExemptionIsTheTagSyncNotASubtask`, which
  also *runs* the chain rather than reading it: a note whose frontmatter names an unknown tag gets one
  minted, pending, with the store never asked to take it. The strongest evidence is a mutation —
  deleting that one call makes `body` stop being an offender, which is what "this is the cause" means.

- [T-646] **CLOSED 2026-09-02 (`e9fbafa`).** The column header draws the notice while the editor is
  closed, so a refusal reaches the surface the user is actually looking at.
  `columnFailureNotice` is `showEditor ? nil : saveFailureNotice` — **one flag read through two
  surfaces, not a second flag.** A second `@State` would need its own clearing rules and could
  disagree with the popover's about whether the last write landed; reading the existing one through
  `showEditor` is also what keeps a single refusal from being reported twice at once. While the
  popover is up it is the popover's; the moment it closes the column takes it over.
  **It fixes more than the deferred completion the ticket named.** Two of the three routes into
  `toggleSectionCompletion` — the header glyph and Cmd+Return over the hovered column — never open a
  popover at all, so their refusals had nowhere to appear either. All three report now.
  The notice is `CadenceInlineFailureNotice` in `headerDetail`, directly under the line that said
  "Completing…", rather than a 9pt near-copy matching the countdown: this is a failure and should not
  be quieter than the thing it answers. Pinned by
  `CadenceKanbanColumnLifecycleSurfaceTests.aRefusedColumnCompletionIsReportedOnTheColumnOnceThePopoverIsGone`,
  including the ordering — a notice drawn above the countdown it answers is a killed mutation.
  The ticket's other option, "the countdown holds the editor open", was refused: a 2.5-second modal
  the user cannot dismiss is a worse answer than a line on the column.

- [T-645] **CLOSED 2026-09-02 (`e9fbafa`).** All three writes commit, and the popover closes on the
  commit rather than on the tap.
  **The design question was the rename, and the answer is a commit *point* plus a different failure
  contract.** `saveSectionChanges` is split: `applySectionEdits()` is the per-keystroke write, so the
  board's header still tracks the field, and `commitSectionEdits()` is the commit — raised from the
  name field's `onSubmit`, from the field losing focus, and from the colour and due-date controls,
  all of which land while the popover is still on screen to carry a notice. It commits through
  `CadenceInPlaceEditFlush`, **not** `commitEdit(in:undo:)`: the caret is in the field, and restoring
  the model would delete what the user typed in order to tell them it had not saved — the decision
  [[T-497]] tier 3 recorded. The other two are discrete presses with nothing under a caret, so both
  take `commitEdit` with a real undo: `clearSectionDueDate()` puts `editorHasDueDate` back with the
  blob, and `deleteSection()` answers `false` so its caller keeps the popover open.
  **The delete's snapshot is a second one on purpose.** `editSnapshot(settling:)` hands over
  `TaskContainerLifecycleService.remainingActiveTasks` — the column's *open* half — and a delete moves
  its **whole** stack into Default. `editSnapshotMovingTasks(outOf:)` snapshots
  `KanbanSectionStateSupport.tasksMoving`, the same walk `moveTasks` performs rather than a second one
  that agrees today; the finished card is the assertion that separates them.
  Pinned by `CadenceKanbanColumnLifecycleSurfaceTests.theColumnEditorsOtherThreeWritesReachACommit`,
  `.theColumnRenameCommitsAtTheEndOfTheEditRatherThanPerKeystroke` and
  `.aRefusedColumnDeleteRestoresTheColumnAndEveryCardItWasMoving`, plus two new entries in
  `CadenceEditorSaveCommitSurfaceTests.saveSurfaces`.
  **Residue, filed rather than folded in:** [[T-713]] — the per-keystroke apply strands the column's
  cards after the first character — and [[T-714]], the one dismissal path a refusal still cannot
  reach.

- [T-564] **CLOSED 2026-09-02 (`e9fbafa`). The decision was to collapse, and both halves landed.**
  Held since [[T-487]] because both halves are design calls, and held again until [[T-608]] had
  finished rewriting the same three functions.
  **(a) `TasksPanelMode` is gone.** The case for keeping it was that a written-out `switch mode` in
  `TasksPanelDerivedState.init`, `isEmptyState` and `TasksPanel.taskSections` forces a future second
  mode to be *answered*. The case against wins: a one-case enum is an abstraction with no cases to
  distinguish, and whoever reintroduces a Today / All Tasks split will design it against the surfaces
  that exist then — `TasksPageView` is the All Tasks page now and has never built one of these panels
  — rather than filling in a `case` left open years earlier. `isEmptyState(for:)` is a property,
  `taskSections(derived:)` — a forwarder whose whole body was the `switch` — is deleted, and
  `TasksPanel.init` no longer takes a `mode:` nobody passed.
  **(b) `TasksPanelDropCoordinator.taskDropHandler` is deleted**, and `sectionDropHandler`'s doc now
  records that its sibling went and why. The pair was symmetric in shape and not in use: the
  `Optional` return is the point of the surviving half — a group with no `dropKey` gets `nil`, so its
  header has no drop target rather than one that refuses everything — while both row drops spell
  `coordinator.handleTaskDrop(...)` inline, because a row hands over its own section's `scopeTasks`
  at the point of the drop and has no `Optional` to express.
  **Neither half turned out load-bearing**, and the ticket's own caveat about [[T-591]] is spent:
  `TasksPanelSupport.dropAssignments(forDropKey:)` splits on `CadenceTaskDropSupport.separator`, so
  the compound-key bug is genuinely fixed and the restructure could not hide it.
  Pinned by `CadenceTodayUnificationTests.theTasksPanelNoLongerCarriesAModeWithOneCase` and
  `.theDropCoordinatorKeepsOnlyTheHalfItsCallersUse`. The second is the shape a deletion needs:
  absence is asserted beside two **exact** presences read by the same scan over the same files —
  `sectionDropHandler(` three times, `.handleTaskDrop(` twice — so a scan that read nothing cannot
  pass, and the row-level decision is shown to still be shared rather than merely gone.

- [T-563] **`CadenceUITests` flakes on app activation, ~1 run in 5.**
  **Closed 2026-09-02 in `4b447ff`. There is no flake and there never was — the rate was an artefact
  of not knowing what the condition was.** `CadenceUITests` cannot pass while the Mac's screen is
  locked. `loginwindow` owns the foreground, the launched app stays `Running Background`, and
  XCUITest's activation gives up ~60s later with *"Failed to activate application … (current state:
  Running Background)"*. That failure is raised **inside `app.launch()`** and reported on whichever
  line called it, so `wait(for: .runningForeground, timeout: 10)` on the next line never runs at all.
  **The ticket's own instruction not to reach for a timeout bump was right, and for a stronger reason
  than it knew: raising that number could not have changed a single run.**
  Measured 2026-09-02, 32 runs / 44 launches under the test-host lock, either side of one lock event
  at 17:48:12. **Before it:** 20 runs, 40 launches, **zero** activation failures — the app was already
  `.runningForeground` the instant `launch()` returned 40 times out of 40, worst 3.12s, median 0.91s,
  p95 1.26s, and not one intermediate `.runningBackground` observation. **After it:** every run, both
  tests, ~61s each, **100%**, always the same message. So the historical "~1 in 5" is the duty cycle of
  the user's screen lock, not a property of the code — which is exactly why it never reproduced on
  demand and why [[T-562]] spent a ticket exonerating a sidebar that was never involved.
  Landed: `CadenceUITestEnvironment.requireAnUnlockedScreen()` skips the suite with the reason named,
  from `setUpWithError` in both classes so no test can forget; `scripts/xcb.sh` refuses a
  `CadenceUITests` run while locked **before** taking the test-host lock, and its zero-test diagnostic
  now recognises a screen that locked *mid-run* instead of blaming the `-only-testing:` filter;
  `CadenceUITestBounds` names every wait in the target and marks each measured or not — **no value
  changed**, only who can defend it. `CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1` exists so the guard and
  the skip can be exercised; it makes the tests skip, not pass.
  Two things this did **not** settle. The residual intermittent failure is
  `sidebar.list.area.alpha-area` missing after 5s, 4 runs in 20 with the screen unlocked — filed as
  [[T-710]], deliberately without touching its bound. And the lock event was a single natural one on
  one machine, not an induced A/B: the 40-launch clean half and the 100% dirty half are each large,
  but the assignment to halves was time, so a second cause that switched on at 17:48 is not excluded
  by this data alone. The `Failed to activate` message and `loginwindow` holding the front are direct
  observations; the causal link between them is textbook macOS behaviour, not something measured here.

- [T-535] **Nothing in the release gate ever compiles the iOS surface.**
  **Closed 2026-09-02 in `56244bc`.** The premise held and the framing was slightly off: this was never
  "the gate forgot to ship iOS". iOS is deliberately built and not distributed — Mac App Store and
  Developer ID are the channels, one `INFOPLIST_FILE` serves both platforms, and
  `app-store-submission-packet.md` is macOS-only on purpose. The defect is narrower and worse. **The
  gate could not tell you the iOS tree still compiles**: `CadenceTests` builds for macOS, so it never
  compiles `Cadence/iOS/` at all, and a break in roughly half this repository survived every check the
  release process runs.
  `docs/apple-release-readiness.md` gains a third verification command
  (`-destination 'generic/platform=iOS Simulator' … build` — no simulator, no booted device) and a
  Release Position bullet saying iOS is built, not distributed, so the command is not read as a fourth
  channel. **Pinned rather than written down, in the suite the gate itself runs**: the gate's third
  command is `-only-testing:CadenceTests/AppStoreReviewReadinessTests`, so
  `theReleaseVerificationCommandsCompileTheIOSSurfaceAsWellAsMacOS` executes *because* someone ran the
  gate, and it also asserts the command still names this suite. `CadenceBuildInvocation` gained a
  `destination` reader — the token list cannot hold `generic/platform=iOS Simulator`, which tokenises
  into two — and it skips malformed input rather than trapping.
  **The lock question, answered rather than assumed:** the two `build` actions need nothing; the `test`
  action must take `scripts/test-host-lock.sh` when anything else may be running a macOS test, because
  the private DerivedData path isolates the build and not the app-group container. Bare `xcodebuild`
  with a private path stays — `AGENTS.md` permits it, and the new line is swept by
  `CadenceBuildInvocationHygieneTests` like the others.
  What no test can pin is that a human ran the commands. Residue: [[T-707]] (the CI iOS job is
  manual-only and CI does not run), [[T-709]] (the invocation sweep cannot see `.yml`).

- [T-649] **A partly-failed image insertion says nothing about the part that failed.**
  **Closed 2026-09-02 in `1ca8174`.** [[T-629]]'s notice covered a refused *commit*, which is
  all-or-nothing because `commitInsert` un-inserts the whole batch. Everything lost *before* the commit
  was silent: `try? await item.loadTransferable(type: Data.self)` for a photo the picker cannot vend,
  and the `compactMap`s over `MarkdownImageAssetService.createAsset` for anything
  `normalizedImageData` cannot decode. All three doors now count what they were handed and report what
  they lost, through the **same** `imageFailureNotice` — one door, one place to look. The two sentences
  cannot contradict each other, because a batch that lost items before the commit still commits its
  survivors and a batch whose commit was refused has no survivors; both door scans now assert the file
  declares exactly one such `@State`, so a second notice cannot be added beside the first.
  `CadenceMarkdownImageInsertionNotice.notice(attempted:accepted:)` is shared and unconditional, which
  is what lets the arithmetic be tested rather than scanned — the iOS doors are behind `#if os(iOS)`
  and this macOS test target never compiles them. Returning `nil` when nothing was lost is
  load-bearing, not tidiness: assigning the result is how a clean insertion *clears* a notice an
  earlier failure left on screen.
  Two things the ticket did not anticipate. The empty exits — `guard !assets.isEmpty else { return [] }`
  — were the same defect with the count at its maximum, and were silent too; they carry the refusal
  sentence now. And `allowsImageInsertion` is deliberately left alone: a door closed by configuration
  did not lose the user's pictures and has nothing to say. Residue: [[T-708]] (the notice has no
  dismissal and no auto-clear, on either platform, and that predates this ticket).

- [T-497] *(**re-scoped 2026-08-31 by [[T-566]]: it is 4 sites, not 2.** The widened
  save-commit detector follows a call one frame down, which the old pattern structurally could not —
  it needed a literal `try?` at the call site. The 2 new sites are
  `iOSMarkdownReferenceSupport.swift` `body` (a third instance of "flush an in-place edit, then close",
  blocked on the same undecided question as the original two) and
  `KanbanCardMetaSupportViews.swift` `select` (popover closes over a swallowed `moveToContainer`; not
  blocked on anything, just out of scope then). Both carried as exemptions with reasons.)* **Tier 3 of the condemned `try? save()` sites — 2 left of the original 12.**
  **Tier 1 and Tier 2 closed 2026-08-30** (7 sites, each exemption entry deleted with its fix, pinned by
  `CadenceTagAndNoteCommitSurfaceTests` — 3 behavioural, 5 source-shape, 10 mutations all killed by
  named tests). Two things that tiering did not predict: `openEventNote` **could not un-insert blindly**,
  because `noteForEditing` returns an existing note as often as it creates one, so a naive
  `commitInsert(of:)` would have deleted a note the user already had; and the notice it reports through
  **did not exist at regular width** — `iOSCalendarEventEditSheet.regularFormLayout` carried
  `readOnlyNotice` but not `actionErrorNotice`, so on iPad *every* failure that sheet reports was
  invisible, including refused EventKit saves and deletes predating that work. Both fixed.

  **Remaining: `iOSSearchSupportViews` (note editor Done) and `iOSTaskDetailSheet.finishEditingAndDismiss`.**
  Both are "flush an in-place edit, then close", and both are **blocked on a decision**, not on work:
  what does undo mean for a field the user is still looking at and still has focus in? Tier 2's inline
  row editors were the easy half — they hold their drafts in `@State`, so restoring the model does not
  fight a caret. These two do. Answer it once and both fall out. Written up in
  `docs/DECISIONS_PENDING.md`.

  The three genuine non-defects keep their exemptions: `TagSupport.seedDefaultTags`/`deduplicateTags`
  (launch-time, idempotent, both already take a save flag) and `CadenceUITestSupport.seedDataIfNeeded`
  (no user). See [[T-503]] for the hole this work found in the rule itself.

  **Closed 2026-09-02 in `ab9e513`. The decision was to stop asking the question.** All four sites
  landed: the three "flush an in-place edit, then close" surfaces (`iOSSearchSupportViews`'s note
  editor Done, `iOSTaskDetailSheet.finishEditingAndDismiss`, `iOSMarkdownReferenceSupport`'s Done)
  plus `KanbanCardMetaSupportViews.select`, which was never blocked on anything.
  **Undo was the wrong repair for the three, not a hard one.** The edit is in-place on an object the
  store already holds, so there is nothing to un-insert — and restoring the model under a live caret
  would delete what the user typed *in order to tell them it was not saved*. The rule was broken
  here only because closing **claims** it worked. `CadenceInPlaceEditFlush.flush(in:commit:)` commits
  and answers and deliberately touches nothing else; the surfaces stay open, keep the text, and name
  the refusal inline, so a second Done can still land it. The kanban picker is the other shape and
  keeps the ordinary repair: it holds no draft, so
  `CadenceTaskMutationSupport.moveToContainer` commits through `commitEdit(in:undo:)` and answers
  `Bool`. **Its undo is written out rather than taken from `CadenceTaskFieldSnapshot`**, which does
  not carry `order` — `assignContainer` sends a genuine move to the end of its new list, so a
  restore that reset the relationships and left the order would move the task inside the list it
  never left. That snapshot gap is [[T-701]].
  **Fixing the task sheet uncovered a fifth frame, and the rule's own detector is what found it.**
  With the literal `try?` gone from `finishEditingAndDismiss`, half 2's one-frame-down index stopped
  subtracting it and flagged it immediately: `applyDates()` → `CadenceTaskDateEditing.setPlanningDates`
  → `CadenceTaskMutationSupport.setPlanningDates`, which ended `try? modelContext.save()`. So the
  sheet could commit honestly and still be closing over a swallow one frame below. Both wrappers
  flush and answer now, and the dismissal is one condition over both — an exemption would have been
  accepted by the rot test and would have been a lie.
  Pinned by `CadenceInPlaceEditFlushCommitTests` (10 tests: 6 behavioural, 4 source-shape).
  Failing-first is real — the three source-shape tests were run against unmodified source and all
  three failed; the behavioural six could not be, because their unit did not exist, so they are
  covered by mutation instead. Nine mutations, each killed by a named test. The five exemption
  entries were deleted in the same change, and a mutation that puts one back fails the rot test.
  **Not observed on screen**: a debug build vends no AX window tree, so a screenshot would be zero
  evidence.

- [T-648] **A note's embedded task card repaints over a swallowed save, in four editors.** VERIFIED
  while fixing [[T-629]] in the same file. `NotePanel.toggleEmbeddedSubtask` / `renameEmbeddedTask`,
  `ListNotesSupportViews`' and `NoteEditorPane`'s copies of both, and
  `iOSMarkdownEditingSurface.toggleEmbeddedSubtask` each mutate the task, run
  `try? modelContext.save()`, and then hand back fresh `MarkdownTaskEmbedRenderInfo` — which is exactly
  what repaints the rendered card inside the note. **This is [[T-366]] again**, the defect
  `TaskEmbedFieldEditorPopover` was fixed for: the card shows values the store does not hold and nothing
  else on screen disagrees. `CadenceTaskFieldEditCommit.commit` is the existing unit and the popover
  already calls `onChanged()` only below its `catch`, so the fix is mechanical.
  **The rule catches one of the four now.** [[T-636]](b) widened `successReport` to the Optional
  half of "the answer is the report", so `iOSMarkdownEditingSurface.toggleEmbeddedSubtask` — which
  answers `MarkdownTaskEmbedRenderInfo?` and returns `.task(task)` over the swallowed commit — is
  flagged and **ledgered against this ticket** in `reportExemptions`. The three macOS copies answer
  `Void` and hand the same render info **sideways** instead, through `refreshEmbeddedTask` one
  frame down; the detector still cannot see that spelling, which is [[T-657]]. Fixing any of the
  four means deleting the matching ledger line in the same change.

  **Closed 2026-09-02 in `ab9e513`.** Seven declarations across the four editors, all through one new
  unit: `CadenceNoteTaskEmbedEditing.toggleSubtask(_:in:commit:)` and `.rename(_:to:in:commit:)`,
  each answering `false` with the task exactly as it was found. Every caller now repaints only below
  the refusal and names it with `CadenceTaskFieldEditCommit.saveFailureNotice` in a
  `CadenceInlineFailureNotice` under the editor — under it rather than over the card, because the
  card is drawn by the text view and there is nothing in SwiftUI's tree to attach a notice to at the
  point of the refusal.
  **`CadenceTaskFieldEditCommit` is deliberately not the unit.** `CadenceTaskFieldSnapshot` carries
  neither `title` nor a subtask's `isDone`, so a rename routed through it would have restored the
  priority the `!!!` shortcut moved and kept the title that moved it — half of an edit nobody made.
  Both undos are written out instead; the snapshot gap is filed as [[T-701]].
  **On [[T-657]]: this does not make it cheaper, it makes it unwitnessed.** The three macOS pairs
  were its only known true positives, and they are gone — so the two pieces T-657 needs (a base
  spelling for "assign freshly built render info into something the view draws", and a report-one-
  frame-down index) cost exactly what they cost before, but nothing in the repo would now demonstrate
  the new half earns its window. What *did* get cheaper is the false-positive measurement T-657 asks
  for, which can now be taken against a clean tree.
  Pinned by `CadenceNoteTaskEmbedCommitTests` (8 tests: 5 behavioural, 3 source-shape), with the
  seven declarations named one by one rather than counted — six of the seven are invisible to
  `CadenceSaveCommitDisciplineTests`, so a count is the one thing that could not say which drifted.
  Failing-first is real: both source-shape tests were run against unmodified source and failed, 28
  issues between them. Five mutations, each killed by a named test. The iOS ledger line was deleted
  in the same change. **Not observed on screen.**

- [T-555] **CLOSED 2026-09-02 (`aca2a49`).** The harvest reads a `static func` now, and the
  constant-versus-template line it needed turned out to be a line the rule already drew. A
  `static func` vending a string is a **constant** when it picks between finished strings
  (`goalsTitle(isNarrowed:)`) and a **template** when it assembles one
  (`markedDayLabel(date:hasItems:)`) — and nothing in the signature separates those two, because
  nothing needs to: *the literal does*. A template's product is built at run time, so no call site
  can re-type it verbatim, so it is not the defect this sweep can act on. That is exactly what the
  stored half has always meant by writing its pattern as `"([^"\\]{12,})"`, where the `\\`
  exclusion rejects an interpolated value before anything else looks at it. Widening is therefore
  the existing rule applied to a second declaration form, not a second rule — and it flags **zero**
  formatters: `countedDayLabel`, `timelineDayLabel`, `relativeDate`, `durationLabel`,
  `placementCaption`, `dropKey` and the rest all drop out on their own.
  **It has to be a lexer, and that is the finding.** Turned loose on a *body* instead of an
  initializer the same regex stops being anchored and pairs quotes that do not belong together.
  Measured: it harvests `"has scheduled items"` — a fragment *nested inside*
  `markedDayLabel`'s `"\(dayName(date)), \(hasItems ? "has scheduled items" : emptyPhrase)"`;
  `") receive this session's time."`, the tail of another interpolated literal; and
  `" : String(format: "` out of `DateFormatters.timeString`, which is a span of **Swift code**
  running from one literal's closing quote to the next one's opening quote. Only the third looks
  wrong at a glance, which is the argument for the lexer rather than against it — the first two
  read as plausible copy and would have shipped as offenders. `cadencePlainStringLiterals(in:)`
  scans left to right and treats an interpolated literal as opaque, insides included; all three
  artefacts are pinned absent **by name**, and the naive regex is a killed mutation (M2).
  **Measured against `HEAD`, twice, not against the checkout** — a sibling's untracked
  `CadenceAppleCalendarNaming.swift` was adding hits of its own while this was written, and
  counting them would have credited them here. Harvest **133 → 175** constants (42 new, from 19
  declarations, all in `Shared/`). Flagged offenders **0 → 4**, in three files: `GoalPickerViews`
  spells `goalsTitle(isNarrowed:)`'s body inline, and `"No lists yet"` has two more spellings on
  the phone. **Ledgered rather than swept** — [[T-627]]'s model, and three sibling agents were
  editing these surfaces. `cadenceStaticFuncConstantLedger` is exact in both directions and
  neither direction is a floor: the sweep fails on an offender nobody listed, and
  `everyStaticFuncConstantOffenderIsLedgeredAndEveryLedgerEntryIsStillReal` fails on an entry that
  has stopped being one, so an entry cannot outlive its fix. Fixes are [[T-698]] and [[T-699]];
  [[T-700]] is the blind spot this did **not** close.
  **Eight mutations, eight kills, each by a named test.** Blinding the interpolation skip (M1) and
  the naive regex (M2) both trip the instrument's `overreaching` guard; deleting the
  bodiless-declaration guard (M3) is caught by a protocol-requirement fixture; deleting a ledger
  entry (M4) and re-pointing one at a file that does not type it (M5) fail opposite directions of
  the ledger; disabling the widening outright (M6) is the red-without-it proof; and taking the
  first `{` after the function *name* instead of after the parameter list (M7) is [[T-644]]'s
  original defect re-tested in the half of the harvest that did not exist when it was found —
  33 declarations in `Shared/` carry a `commit:` default closure that would become the "body".
  M8 narrows the wide-corpus reader test to one folder and is caught by its own non-vacuity
  witnesses, so the corpus claim is not a sentence.
  **A crash report came back from an integration run this suite could not reproduce**, and the
  answer to it is the eighth test. `EXC_BREAKPOINT` in `cadenceStaticFunctionBodies(in:)`, on the
  line forming the span between a parameter list and a body brace — which implies
  `parameters.upperBound > body.lowerBound`. **`CadenceSourceScan.matchedRange`'s contract is not
  the finding**: it searches for the brace *from* the closing parenthesis, so the pair is ordered
  structurally, and re-running the real Swift over 2288 `static func` declarations in 852 files
  plus twelve adversarial shapes (an unbalanced paren, brace or quote inside a default literal, a
  bodiless declaration, a grapheme cluster before the name) never inverted it once. The corpus that
  crashed is gone — a sibling's in-flight file, most likely, since three were staging into the
  checkout while this ran. So the fix is not a workaround for a known input: the walk **refuses**
  to form an unorderable span instead of asserting it, and `bothNewReadersSurviveEveryFileInTheProduct`
  runs both new readers over every Swift file in all three shipped targets rather than the two
  roots the harvest uses. That is the generalisable part — **a trap in a source-scan helper is a
  dead test host, not a test failure**, and a crashed host emits no `error:` lines and no `✘ Test`
  line, so it reads as "nothing happened". Both halves are in `docs/SUBAGENT_RUNBOOK.md` now.
  **The one thing left imprecise on purpose:** the fixture comment in
  `CadenceSettingsSectionCopyTests.everyConvergedSettingsStringIsHarvestedByTheSharedConstantSweep`
  still says the harvest "reads `static let x = "…"`" and names `goalsTitle` as the gap. That half
  is stale now; the other half (an interpolated title is still invisible) is not. Left alone
  because a sibling agent held that file in the same batch.

- [T-543] **Settings > Calendar's access card says two things and draws two glyphs.** macOS drew an amber
  `exclamationmark.triangle.fill` in **both** states — including not-yet-asked, which is the state a fresh
  install is in — beside a button offering access, so the card contradicted itself.
  **Closed 2026-09-02 in `4a2c00e`.** The Mac now draws the phone's ternary
  (`calendarManager.isDenied ? "exclamationmark.triangle.fill" : "calendar.badge.plus"`, tinted
  `Theme.amber : Theme.blue`), and the not-yet-asked sentence converged on the phone's into
  `CadenceCalendarSettingsCopy.accessRequiredDetail` — the phone's because it names what this card gates
  (showing events, connecting a calendar to an area or project) rather than the writing path a reader on
  this screen is not using. The **denied** sentence stays at each call site on purpose: it names where the
  reader has to go, and that is a different place on each platform. The hand-rolled `HStack` is now
  `CadenceSettingsNoticeRow`, the row Notifications and Reminders already draw, which is what took this
  file's private near-copies to zero. Pinned by `theCalendarAccessCardDrawsOneGlyphPerStateOnBothSurfaces`
  — **exact** glyph counts per file, not `contains`, because presence is what was already true and a
  second unconditional triangle beside the fix would satisfy a looser check. Mutations M1 (glyph
  unconditional) and M2 (tint unconditional) each died on that test; M3 (macOS re-types its old sentence)
  died on `bothCalendarSettingsSurfacesReadEveryConvergedCalendarString`; M4 (the shared sentence quietly
  shortened) died on `theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell` **and** on
  `everyConvergedSettingsStringIsHarvestedByTheSharedConstantSweep`, which is a test this ticket did not
  write. **Residue filed as [[T-694]]**: the title above it still says "Calendar access required".
  **Not observed on screen** — a debug build vends no AX window tree, so this is a source and value claim.

- [T-545] **macOS's empty-calendar row is a one-liner where iOS is two.**
  **Closed 2026-09-02 in `4a2c00e`, and the ticket's premise was stale.** It said macOS "cannot converge
  without a two-line row, and its three sibling empty rows all share the one-line house style" — but
  [[T-600]](b) had already moved four of them onto the two-line `CadenceSettingsNoticeRow` with shared
  copy. The calendars card was simply *missed*, because it is the one empty state that is not "you have
  made none yet": access has been granted and EventKit answered with nothing. So there was no design
  decision left to make. Both surfaces read `CadenceSettingsEmptyStateCopy.appleCalendarsTitle` /
  `appleCalendarsSubtitle`, macOS draws the same row as its four siblings, and the stray full stop went
  with it — the title/subtitle punctuation loops in
  `theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell` now cover this pair, which is what killed
  mutation M7. Added as the fifth entry of `bothSurfacesOfEveryEmptySettingsCardReadOneTitleAndOneSubtitle`
  (M5 and M6 died there), and `theFourEmptySettingsCardsAreDrawnOnTheSharedNoticeRow` is renamed
  `theEmptySettingsCardsAreEachDrawnOnTheSharedNoticeRow` and expects **exactly 4** notice rows in
  `SettingsListManagementSections.swift`, up from 2 — with the two shapes they replaced named
  individually, because an aggregate that totals four cannot tell you the four are where you left them.

- [T-547] **`"Apple Calendar"` is one literal serving at least two concepts across 7 files.**
  **Closed 2026-09-02 in `4a2c00e`. Three concepts, not two — and the split came before the hoist.**
  A single shared constant for two meanings is the defect, not the fix: it would have made a reword of the
  phone's sheet heading silently reword what the Mac prints when EventKit hands back an unnamed account.
  `Cadence/Shared/CadenceAppleCalendarNaming.swift` declares three constants, byte-identical today and
  free to diverge tomorrow:
  **`integrationSectionTitle`** — the label over the controls that talk to EventKit:
  `iOSCalendarQuickCreateSheet.swift:341`, `iOSCalendarEventEditSheet.swift:390`,
  `iOSCalendarInspectorView.swift:88`, `ListEditorSupportViews.swift:424`.
  **`unnamedCalendarTitle`** — the fallback for `event.calendar?.title`, printed where a calendar's own
  name goes: `iOSBoardCards.swift:77`, `iOSSearchView.swift:640`.
  **`unnamedAccountTitle`** — the fallback for `calendar.source?.title`, printed where an account name
  goes: `iOSCalendarSettingsSection.swift:653`, `SettingsListManagementSections.swift:519`.
  Eight sites, seven files. Guarded by `CadenceAppleCalendarNamingTests`: exact per-site counts **by
  concept** (a total of eight would stay green while a site drifted from one concept to the other), plus a
  `CadenceScanInstrument` sweep proving the declaration is the only file under `Cadence/` that types the
  literal. The two mutations that matter are the **concept swaps** — M9 pointed a board card at
  `unnamedAccountTitle` and M11 pointed the settings row at `integrationSectionTitle`; both compile, both
  died on `everySiteReadsTheConstantForTheConceptItMeans`, which is the evidence that the *split* is
  guarded rather than only the de-duplication. M8 and M10 (either kind re-typing the literal) each died on
  three tests, one of them the standing `noCallSiteRetypesASharedStringConstant` sweep, which the three
  constants now feed. **The ticket's sibling cases are untouched and still open**: `"Allow Access"` (12
  sites) and `"Open Settings"` (13). **Two divergences found while splitting are filed rather than fixed**:
  [[T-692]] (`source?.title` falls back to "Other" in `CadenceCalendarPicker`) and [[T-693]] (macOS
  displays `event.calendar?.title ?? ""`, an empty line, where iOS shows the fallback).

- [T-544] **CLOSED 2026-09-02, `8bb52ea`.** The Mac said "Weekly calendar views gently highlight …" and
  no part of it was true. The band is `TimelineWorkHoursHighlightLayer`, drawn inside `TimelineDayCanvas`
  once per **day column**, and only where a caller passes `showWorkHoursHighlight: true` — exactly two do:
  `CalDayColumn`, the Calendar page's day column, and `SchedulePanelTimelineViewport`, the panel the app
  titles **Timeline** since [[T-602]] and not a calendar view at all. "Weekly" was wrong a second way: the
  Calendar page draws day columns at Week *and* 2 Weeks, and its Month presentation draws neither a column
  nor a band. It now reads "Calendar and Timeline day columns gently highlight …". [[T-524]]'s pin that the
  two subtitles stay *different* is kept and now has a reason: mobile draws the band on the Calendar's day
  columns and nowhere else — iPad's Timeline pane reads the same two preference keys but spends them on
  `ReadyScheduleContext`'s slot suggestions ([[T-697]]). The new test is the sentence's **evidence, not its
  echo**: it sweeps `Cadence/macOS` through `CadenceScanInstrument` and asserts the call-site set *exactly*
  plus one occurrence per file, so a third surface switching the band on fails there instead of making the
  sentence stale again. Failing-first against unmodified source: 3 tests red, 27 issues. Two mutations
  (subtitle reverted; the Schedule panel's `showWorkHoursHighlight` flipped to `false`) each killed named
  tests; a third, deleting the weekend gate, killed the behaviour pin. Residue filed as [[T-696]] and
  [[T-697]].

- [T-546] **CLOSED 2026-09-02, `f6c3073`.** Six labels, twelve call sites, now
  `CadenceListLifecycleSectionCopy`. They are six plain `static let` literals rather than one
  `sectionTitle(_:of:)` composer **on purpose**: an interpolated title is invisible to
  `cadenceSharedStringConstants`, which harvests `static let x = "…"` only, so a composed title would leave
  a *seventh* surface free to re-type the literal with nothing to catch it — the recorded gap behind
  `CadenceEmptyStateCopy.goalsTitle`. The six are registered with the harvest, so
  `noCallSiteRetypesASharedStringConstant` guards them from here. **Room for [[T-690]] is in the rule, not
  in an unused function**: every title is `"<status> <plural noun>"` with the status word taken from
  `CadenceListSearchLifecycle`, which already carries all five spellings, and a test pins each of the six
  against it — so `pausedProjects`/`cancelledProjects` are two more constants whose wording is already
  decided rather than two more copy decisions. Failing-first is real *and* is about the call sites: the pin
  asserts each file reads each name an **exact** number of times (once where it draws that group, zero
  where it does not), so it stayed red against unmodified source **with the enum already declared** —
  a value-only assertion would have been green there. Four mutations (a macOS call site re-typed, an iOS
  call site re-typed, a constant's value changed, two call sites swapped) each killed named tests. Residue
  filed as [[T-695]].

- [T-558] **`TildeContainerPickerSupport.flatContainers` drops every context-less list — the fifth instance
  of this shape.** `macOS/Views/TildeContainerPicker.swift` was `for context in contexts { areas.filter
  { $0.context?.id == context.id } … }`, so a list with `context == nil` matched no iteration and was never
  appended — and that function is the only source of rows for the `~` list-search panel on both macOS
  composers, so a context-less list was one no task could be filed into from the Mac at all.
  **Closed 2026-09-02 in `3c90473`. The trailing bucket is keyed on the *offered* contexts, not on
  `context == nil`, so an archived context's lists land there too — and the fifth instance is the part worth
  the work, so the membership rule itself moved to `CadenceSidebarLists.isOffered(_:among:)` and the three
  surfaces that each asked it their own way now read it: this panel, `ContainerPickerFilterSupport` (private
  copy deleted) and `GoalLinkPresentation.candidateGroups` — **which was keyed on `context == nil` and is a
  sixth instance, fixed here rather than filed**, latent only because every caller passes an unfiltered
  context query. Failing-first is real: the four new tests ran against unmodified source and all four failed
  on the missing bucket. Five mutations (bucket deleted / keyed on nil / bucket first / `isOffered` accepts
  nil / goal links keyed on nil) each killed a different named set. The fixture orders Garage at 5 rather
  than 0 on purpose — at 0 the "offer every context" and "offer only Work" results coincide, and a test that
  cannot tell them apart is green against the bug it exists for. **Not observed on screen**, deliberately:
  a debug build vends no AX window tree, so a screenshot would be zero evidence.**

- [T-559] **macOS can now see a context-less list but still cannot create or correct one.** `CreateListSheet`
  took a non-optional `let context: Context` and titled itself "in \(context.name)"; `EditAreaSheet` and
  `EditProjectSheet` had no context control at all.
  **Closed 2026-09-02 in `ed7347e`.** All three sheets draw a `ListEditorContextRow` over the existing
  `CadenceContextPickerList`, so the archive rule and T-446's "show the assigned one even when it is no
  longer offerable" rule are read rather than respelled; the sidebar's catch-all header gets a "+" that opens
  the sheet already on "No context". **The eyebrow's right-hand note is deleted rather than given a fallback
  string** — the ticket's real question was what it says with no context, and the answer is that it should
  never have been the thing saying it now that every list sheet carries a row that both states the context
  and sets it. `titleTrailing` had one caller and is gone. **Adding the control without T-293 would have
  shipped that bug a second time**: `AppTask.context` is a denormalized copy, so `applyEdits()` re-points the
  list's tasks, guarded on an actual change so a rename dirties nothing, over a new
  `CadenceTaskMutationSupport.inheritedContextTargets(area:project:)` — because the reassignment also cascades
  into child projects with no context of their own ([[T-340]]) and a snapshot taken from `area.tasks` alone
  cannot undo that half. **A `CadenceListEditSnapshot` de-dupe was written and then reverted**: the two
  overlapping task sets restore identically, so it was code with no observable effect and no mutation could
  have killed it. Three mutations (cascade dropped, sheets skip the re-point, catch-all loses its "+") each
  killed a different named test. **`CadenceContextlessListSurfaceTests` is the fifth-instance pin and is
  worth more than either fix**: it runs all four list-offering entry points over one fixture holding a
  context-less list of each kind *and* a list under an unoffered context, and carries a ledger of the 27
  sites in 9 files that derive lists from a context, each with a note on how it reaches the leftovers.
  **Not observed on screen**, same reason as T-558.

- [T-609] **CLOSED 2026-09-02 (`f09d739`).** Swept, and **re-measured rather than inherited**. The
  inline form `X.isEmpty ? "…" : X` where `X` is a title is **29 sites in 22 files**, and a second
  spelling the ticket did not name — `X.trimmingCharacters(…).isEmpty ? "…" : X`, which tests the
  *trimmed* value and returns the **untrimmed** one — adds **4 more in 2 files**. 32 of the 33 are
  fixed; the 29th inline site, `TasksPanelComponents.swift:55` inside `MacTaskRow`, was another
  agent's file for the whole batch and is [[T-686]].
  **Premise correction:** "25 across `Cadence/`, `CadenceWidgets/` and `CadenceMCPServer/`" is wrong
  about the spread. Both extra targets hold **zero** — `CadenceMCPServer`'s only `isEmpty ?` is
  `parts.isEmpty ? nil : parts`, and `CadenceWidgets/` has none at all. Every site is under
  `Cadence/`.
  **(a), decided before sweeping: no copy changed.** Each site passes its own fallback explicitly —
  "Untitled" (as `defaultCompactDisplayTitle`), "Untitled List", "Untitled subtask", "Missing Task",
  "New Task", "Event Note", "Goal", "Linked event note", "No context". T-569's decision to keep the
  compact wording stands; re-wording any of them is [[T-687]].
  **(b), decided before sweeping: one call does *not* fit all.** `TaskTitleSupport` lives in
  `Cadence/Shared/`, which neither extra target compiles, so the four sites in `Models/`, the widget
  service and the two event-note surfaces read `CadenceTitleNormalization.display` in
  `Cadence/Models/ModelEnums.swift` — the one tree all three targets build. `CadenceMCPServer` and
  `CadenceWidgets` were built on their own schemes: 0 errors, 0 warnings, and the log names the
  files that recompiled.
  Two sites are behaviourally reachable and both were red first: the Today widget row drew
  `"  Buy milk  "` untrimmed, and a meeting note's `# heading` wrote the padding into markdown.
  Pinned by `CadenceEmptyTitleFallbackSweepTests` — two `CadenceScanInstrument` sweeps over all
  three roots with a per-root witness, the `strippingComments`-vs-`codeOnly` reader pinned as its
  own test, and the one skipped site held as an **exact expected set** so fixing it goes red rather
  than silently widening. 8 mutations, all killed.

- [T-539] **CLOSED 2026-09-02 (`f09d739`).** The prompt says "Task title". Premise verified at
  `iOSTaskDetailComponents.swift:72`, unmoved. Its `cadenceUndeclaredPlaceholderLabels` entry is
  deleted and the list's count assertion is 3 — and the deletion was **forced, not chosen**:
  `everyUndeclaredPlaceholderLabelIsStillUndeclaredAndStillTyped` fails on an entry whose file no
  longer types the literal, which is that list working as designed. Pinned twice, once at the line
  and once over the tree: `everyTitlePromptInTheAppIsANounPhrase` harvests every
  `TextField("…", text: $…title)` prompt in `Cadence/` and fails on any phrased as a placeholder
  value, so "the only prompt phrased as a value" is now a claim a test can check rather than prose.

- [T-550] **CLOSED 2026-09-02 (`f09d739`).** Both arguments deleted. Premise verified:
  `GoalLinkPickerButton.emptyText` defaults to `"No matching goals"` at `GoalPickerViews.swift:89`
  and both call sites passed exactly that. The guard is over the tree, not the two lines — no file
  under `Cadence/` other than the declaration may spell `emptyText: "No matching goals"` — with the
  default itself asserted, so the test stops meaning anything the moment the default changes rather
  than quietly forgiving the argument.


- [T-541] **CLOSED 2026-09-02, `c1b0c9b`.** Filtered the fallback too, as decided. The Goals
  detail pane resolves through `GoalAssignmentRules.selectedGoal(id:from:)`, whose every rung is
  narrowed to `status != .done` — the unfiltered `?? goals.first` tail is gone, and the selected-id
  lookup no longer reaches through the whole collection either, so completing the goal you are
  looking at on iPad moves the pane instead of stranding it on a row that no longer exists. The
  deleted-out-from-under-you fall-through the old comment described is intact and now says so where
  it is testable; the retired half of that comment (a "No goal selected" copy that T-533 removed)
  went with it. `nil` from the rule is now **exactly** `activeGoals.count == 0`, the condition
  `iOSFeatureListPane` draws its empty panel on — an equality, where the pane's old comment claimed
  only an implication and the gap was the defect. Both sides therefore empty together, and the
  detail side's empty state is the chooser's own real one (`iOSFeatureEmptyDetail(matching:)` →
  `iOSEmptyPanel`, icon + title + subtitle), not a blank pane. Five behavioural tests in
  `GoalPresentationTests`, including why the second fallback rung is not dead code; the source-shape
  pin in `CadenceEmptyStateAuditTests` now pins the shared reader and bans `?? goals.first`. Six
  mutations, all killed. Residue filed as [[T-689]].

- [T-557] **CLOSED 2026-09-02, `72bced5`.** Surfaced in Settings, with the active-only policy
  untouched. `CadenceCalendarLinkHealth.dormantLinks(areas:projects:)` reports every **inactive**
  list — archived, completed, paused or cancelled — that still holds a `linkedCalendarID`, and both
  calendar settings surfaces draw a *Dormant Calendar Links* card for it whose one control is
  **Remove Link**. Archiving still keeps the link, so un-archiving restores it intact; what changes
  is that it is now visible and clearable without un-archiving first. `missingLinks` is unchanged
  and still narrows to active lists: an archived list's link is not missing, it is dormant, and the
  two sets are disjoint by construction. **It does not touch [[T-624]]'s evidence gate**: the
  detector takes no `liveCalendarIDs`, no `observedCalendarIDs` and no authorization flag, so it
  never judges an archived link against EventKit and cannot report one broken on a device that has
  never seen its calendar — pinned behaviourally over five evidence states and structurally over
  the function body. The row offers no re-pick for the same reason a re-pick was the T-624 clobber.
  The card renders **outside** the authorization branch, because whether an inactive list holds a
  link is a fact about this app's own store rather than a question for EventKit. `"Remove Link"`
  became `CadenceCalendarLinkHealth.removeLinkLabel` in the same change, since four rows now want
  those two words. Nine tests in `CadenceCalendarLinkHealthTests`; six mutations, all killed.
  Residue filed as [[T-690]] and [[T-691]].

- [T-608] **CLOSED 2026-09-02, `0d16896`.** The intent groups call `TaskListInteractiveRow` and the
  Completed group calls `TaskListDisplayRow` plus a `.draggable` — the shape
  `TasksListCompletedSectionView` already uses on All Tasks. `MacTaskRow` is now constructed at
  **exactly one site in the app**, inside `TaskListDisplayRow`.
  **It was not quite a copy, and the difference was a defect.** Today overlaid the drop indicator on
  the *unpadded* row and padded the result, so the 2pt bar was inset twice: 32pt from the pane's
  leading edge over a row whose content starts at 16. The shared row overlays the padded row. That
  is the one visible change.
  **The ticket's `opacity` premise was wrong.** It was declared on the *intent* section, not the
  Completed group, and `TasksPanel` — its only caller, since the commit that introduced it — never
  passed it. Dead from the day it shipped, so deleted rather than plumbed into a shared component.
  Two further differences were enumerated rather than assumed away: `TaskListDisplayRow`'s
  `.listRow*` modifiers are load-bearing for `ListDetailComponents` (a real `List`) and inert for
  `TasksPanel` (a `LazyVStack`); and `.draggable`/`.dropDestination` now sit outside the padding, so
  a row's drop target covers its own gutter, as on the other two surfaces.
  **[[T-564]] was not reachable and was not touched** — `TasksPanelMode`, its `switch`,
  `taskSections`, `doneTasks`, `isEmptyState` and `TasksPanelDropCoordinator` are all unchanged.
  Pinned by `CadenceTodayUnificationTests.todaysRowsAreTheSharedInteractiveRowAtThePanelsOwnInsets`,
  written so that "the shared row is called" is *not* enough: the shared row's default leading inset
  is the list detail's 52, so a converged call site that omitted the argument would move every Today
  row and still pass. 7 mutations, 7 killed, each by that test and no other. Residue filed as
  [[T-680]] and [[T-681]].

- [T-615] **CLOSED 2026-09-02, `d06be27`.** Decided the second way: the pane keeps "Today Timeline"
  and the hosted panel drops its heading. A page header does not describe the page the user is
  already on, and that does not stop at the outermost header — the second one is the one to drop,
  because the first is the one the user read. The panel's divider went with its header; the pane
  draws that rule itself, so keeping both left two hairlines with nothing between them.
  `SchedulePanelPresentation.hosted` is opt-in, and **that is the load-bearing half**: `SchedulePanel`
  has four hosts, and the other three — Today's schedule column (`TodayView.swift:34`), the focus
  screen (`FocusView.swift:306`), the focus sidebar (`FocusSidebarSupportViews.swift:68`) — have
  nothing above them naming the column, so an unconditional drop would have left three unnamed
  columns to fix one named twice. `theTimelinePaneNamesItselfOnceAndTheOtherHostsStillNameThemselves`
  names all four hosts one at a time and sweeps `Cadence/` through a `CadenceScanInstrument` for a
  fifth; the instrument's lookbehind is load-bearing, since `iOSSchedulePanel(` contains the needle.
  Three mutations, all killed: reverting the call site, inverting `drawsOwnHeader`, and — the pin
  that matters — silencing `TodayView`'s header instead.

- [T-617] **CLOSED 2026-09-02, `bf19c5d`.** One shared home, per-platform values:
  `CadenceTaskChipPadding` in `Cadence/Shared/CadenceTaskPresentationSupport.swift` states macOS's
  `4`/`2` and iOS's `9`/`7`, and both platforms read it — the macOS row's four chips and
  `iOSTaskAttributeChipSize.horizontalPadding`. Not a field on `CadenceTaskRowMetrics`, which would
  have been the second home this batch has been closing; not converged either, because nobody has
  compared the two chips on screen and no pixel moved here.
  **The ticket said five sites and it is four.** The row's own comment named the bundle badge as the
  fifth; the badge draws no background, so it has no plate and no inset. The four are the Cancelled
  pill, the do-date pill, the due-date pill and the estimate chip. The pin asserts each of the four
  *reads the shared name exactly once* over four non-overlapping regions, so a fifth chip spelled
  inline cannot pass a count that still adds up. Three mutations, all killed.

- [T-618] **CLOSED 2026-09-02, `695a9ea`.** `Theme.rowSeparator = borderSubtle.opacity(0.35)`, read
  by all four sites: `Shared/Components/CadenceFieldRows.swift`, `iOS/iOSTaskDetailComponents.swift`,
  `iOS/iOSTodaySchedulePanel.swift`, `iOS/iOSCalendarBundleDetailSheet.swift`.
  **The ticket said five, and the fifth is the finding.** `Views/FocusPickerSupportViews.swift:216`
  spells the same alpha as the *unhovered arm of a hover pair* — a card's resting border, not a rule
  between rows. Same number, different job; folding it in would have coupled a hover state to a
  separator weight. It is left alone and `theRemainingThirtyFivePercentBorderIsACardsRestingStrokeAndNotARule`
  pins that decision, so it reads as a judgement rather than a sweep someone forgot to finish.
  Two mutations, both killed: retuning the token, and reverting one call site.
  Filed [[T-675]] for what this turned up — two *other* row-separator weights, unnamed.

- [T-639] **CLOSED 2026-09-02, `5b0c2b8`.** Both helpers were dead: `taskPriorityRank` had no caller
  at all — `TaskOrdering.precedes` reads `priority.rank` directly, so the comment calling it "the
  spelling that drives every macOS task sort" was already false — and `taskSortPrecedes` had only the
  `TasksPanel` call [[T-606]] removed. The file itself was swept into `91d533c` by a concurrent agent's
  commit; `5b0c2b8` carries the rest.
  **Non-vacuity, since the evidence for a deletion is that a caller would have been caught.** The
  detector is the compiler over a full build of every target: a clean macOS build and a clean
  `generic/platform=iOS Simulator` build, both 0 errors and 0 warnings, with all six edited files
  confirmed recompiled. The *positive control* put one call to each symbol back into
  `TasksPanel.compareTasksForCurrentSort` — the exact site that held the last one — and the build
  failed 65 with `cannot find 'taskSortPrecedes' in scope` and `cannot find 'taskPriorityRank' in
  scope`. Restored, rebuilt clean.
  **The two referencing tests were different cases, which is why the ticket said to check.**
  `priorityRankIsOneOrderingSharedByEveryCaller` was *testing* the helper, as one of three rank
  spellings; the other two are live, so the dead third came out and the test stands.
  `macOSPrioritySortRanksALowPriorityTaskAboveAnUnprioritisedOne` was *using* it as the spelling for
  the comparator, so it needed the replacement the ticket predicted: same three assertions, now
  against `TaskOrdering.precedes`, no longer `#if os(macOS)`, renamed
  `prioritySortRanksALowPriorityTaskAboveAnUnprioritisedOne`. Mutation: swap `.low` and `.none` in
  `TaskPriority.rank` — killed by both, by name.
  `CadenceTargetSourceMembershipTests`' doc comments named the deleted file twice as the example of a
  non-member declaring a top-level `func`; both now name `CalendarPageMonthGridSupport.swift`, which
  the same comments already cite. The suite draws its witness from the live unreachable set rather
  than a literal name, so nothing in it broke — 6 tests green.
  Residue: [[T-670]].

- [T-640] **CLOSED 2026-09-02, `5b0c2b8`.** The private twin is gone, and **it was not the only
  survivor of that sweep**. Three literals were left, not one: `CadenceTaskQuerySupport.sortDateKey`,
  `CadenceCalendarPlanningSupport.railAnchorKey`, and — carrying the *other* spelling —
  `CadenceTaskRecurrenceWorkflowSupport.recurrenceSortKey` at `"9999-12-31"`, which is precisely the
  pair `TaskOrdering.noDateSortKey`'s own doc comment says would split undated work if one comparator
  ever met both. All three read `TaskOrdering` now.
  **Restoring the agreement is not asserting it**, so both halves are pinned, in `TaskOrderingTests`:
  `everyMigratedMacOSTodaySortModeAgreesWithItsRetiredComparator` runs all three retired macOS Today
  mappings over **every ordered pair** of the tie-heavy set (126 comparisons; pair-by-pair because two
  comparators can agree on one sorted permutation and still disagree on a pair), and
  `theNoDateSentinelLiteralIsSpelledOnceInProductionSource` sweeps `Cadence` + `CadenceWidgets` +
  `CadenceMCPServer` through `CadenceScanInstrument` and requires the literal in exactly one file,
  exactly once — the named file, not a floor.
  **Both are needed, and a mutation is the argument.** M2 replaced `dateSortKey` in the do-date branch
  with an inline `"9999-12-31"`: it compiled, it sorted identically, and the pairwise test **passed**.
  Only the literal count killed it. A divergent-but-equivalent spelling is behaviourally invisible,
  which is the whole finding, restated as an experiment.
  Mutations, all killed by name: M1 hand-spelled sentinel back into `railAnchorKey` → literal count.
  M2 as above → literal count only. M3 do-date comparison reversed, M4 timed-before-untimed flipped,
  M5 priority comparison reversed → all three killed by the pairwise test. 28 tests green across the
  three suites before mutation.
  Residue: [[T-669]].

- [T-637] **CLOSED 2026-09-02, `91d533c`.** The icon-only-button rule sweeps `Cadence/` instead of
  `Cadence/iOS/`, and `knownUnnamedIconButtonSites` is exact in both directions over all 565 files.
  **The 31/24 figure was re-measured rather than inherited** — it predated four batches that touched
  button surfaces — and it reproduced exactly: **31 sites in 24 files, 3 on iOS (unchanged) and 28 in
  22 macOS files**. Two independent readings agree: the suite's own sweep, and a line-numbered port of
  `unnamedIconButtonCount` run outside the test target, which returned the same 24 files with the same
  per-file counts and gave the line numbers the three follow-up tickets cite.
  **The widening is pinned by the walk, not by a comment.** The sweep's `including:` witness is now
  `Cadence/macOS/Views/TasksPanelSupportViews.swift`, so re-scoping the walk to `Cadence/iOS` throws
  `walkMissedItsWitness` before it counts anything — that is mutation **M4**, killed by
  `noIconOnlyButtonInTheAppIsLeftWithoutAnAccessibleName` and
  `theUnnamedIconButtonLedgerStatesHowManySitesEachFileStillHas`.
  **The count is not inflated by self-naming menu items**, which is what made T-611's original
  "1 label across 25 buttons" wrong. `aMenuItemSpelledAsALabelIsNotAnIconOnlyButton` pins the
  `Label(_:systemImage:)` case on a literal instead of on a file that can lose its menu; teaching the
  detector to count `Label(` (**M2**) kills it and three others.
  **A tooltip is not a name, and that is a fixture now too.** `aTooltipIsNotAnAccessibleNameForABareGlyph`
  fires on a `.help`-only glyph and stays quiet on `.cadenceControlLabel`. Accepting `.help` as a name
  (**M3**) kills it — and, measured, changes the ledger by **zero**: none of the 31 carries a `.help`
  in its modifier chain today, so the "same controls the tooltip ledger released" reading is about
  which controls they are, not about text still present at the site.
  All seven mutations were killed, each by a named test, in an isolated `git archive` tree under one
  lease: M1 blinded `namesItself` (6 kills), M2 counted `Label(` (4), M3 accepted `.help` (1), M4
  reverted the scope (2), M5 dropped a ledger line (3), M6 added a stale one for a clean file (3),
  M7 changed a count by one (2). M5 and M6 are the bidirectional check: an unlisted offender and a
  stale entry each fail, so a ledger that merely *contained* the offenders would not pass.
  **Ledgered rather than fixed, deliberately** — 24 files with three agents editing that set — and every
  site is attributed: iOS's 3 stay with [[T-611]]; macOS's 28 split into [[T-672]] (10 copies of the
  search field's clear button), [[T-673]] (8 row glyphs that never name their row) and [[T-674]] (10
  helpers and chrome, including one whose optional label parameter is the reason it has no label).
  Not done: the suite is still called `CadenceIOSControlAccessibilityTests` while carrying an app-wide
  rule. Moving 150 lines of brace-walking between two suites mid-batch was the larger risk; the file's
  header says so.

- [T-644] **CLOSED 2026-09-01, `d5e3460`.** `functionBody(named:)` balances the parameter list
  before it looks for the body, through a new `matchedRange(after:in:open:close:)` — `matchedBody`'s
  span rather than a second matcher, so there is still one brace walker. **The population was 33
  declarations, not "20+"**: measured by running both readers over every app source. **The blast
  radius was one test**, also measured rather than assumed — of the 36 files that call
  `functionBody(named:)`, only `CadenceTaskStatusEditingSurfaceTests.theSharedStatusHelpersStillReconcileNothing`
  read one of the 33, and it was the one carrying the local workaround. That workaround is gone; with
  the old reader and no workaround the test fails with *"toggleCompletion's body does not look like
  the status helper: try $0.save()"*, which is the failing-first proof. 48 of the 52 suites that read
  either reader re-ran green (593 tests); the other four are [[T-667]].
  Mutation: `Task { await NotificationManager.shared.cancel(taskIDs: [task.id]) }` at the top of
  `CadenceTaskMutationSupport.toggleCompletion` — invisible to the old reader, killed by
  `theSharedStatusHelpersStillReconcileNothing()`.
  Residue: [[T-668]] — `cadenceFunctionBody` in `FocusPickerPlayControlTests.swift` is a near-copy
  with the same defect and 83 call sites.

- [T-659] **CLOSED 2026-09-01, `d5e3460`.** The report search dropped `options: .backwards`, so the
  comparison anchors on the **first** occurrence; the `catch` end stays backwards, because the last
  failure branch is the strict end of that comparison.
  **The before/after was measured, not argued.** The same mutation — a `dismiss()` added above the
  `do`/`catch` in `CreateContextSheet.create`, the T-497 defect exactly — **survived** the old reader
  (`theContextCreatorClosesOnlyOnACommittedInsert()` passed) and is **killed** by the new one. A
  second mutation, `isEditing = false` above the catch in `SettingsTagsSection.saveEdits`, is killed
  by `theInlineTagEditorsCollapseOnlyOnACommittedEdit()`.
  All five calling suites and all 27 call sites re-ran green, **no pin went red**: no body in the app
  legitimately writes its report twice. The separating fixture is
  `CadenceSourceScanReaderTests.theOrderingReaderRefusesAReportWrittenOnBothSidesOfTheFailureBranch`,
  with per-suite copies in `CadenceTagAndNoteCommitSurfaceTests` and
  `CadenceCreateSheetCommitSurfaceTests`. `CadenceInlineTagCommitSurfaceTests.reportFollowsTheRefusal`
  stays: the two readers now ask the same question, and what separates them is the *marker* — a
  refusal **guard** rather than a `catch`.

- [T-625] **CLOSED 2026-09-01** (`c5d45b3`). A claim-accuracy narrowing, as filed: no product
  change, and the "columns as their own rows" fix was deliberately **not** attempted — it is a new `@Model`
  plus a migration of every existing JSON blob, and this project has no `SchemaMigrationPlan`.
  `CadenceSectionConfigMerge`'s opening paragraph now says what the type is — **a write-time merge
  and only a write-time merge** — and names the ordering in which two devices actually converge
  (the peer's blob already in `current` when the local save runs) versus the one in which nothing
  merges at all. The test section is `One store, one blob: stale-snapshot writes`, not
  `Two devices, one blob`.
  **The correction is asserted, not merely reworded**, which is the part that keeps it from rotting:
  `SectionConfigRoundTripTests.aPeersBlobLandingAfterALocalMergeReplacesItWholeBecauseNothingMergesOnImport`
  builds two genuinely separate `Area` replicas, lets each merge correctly against its own store,
  then lands B's `sectionConfigsRaw` on A the way CloudKit lands it — one whole string straight onto
  the stored property — and asserts A's rename is gone. It fails the day an import-side hook appears,
  which is the only way the narrowed prose can go stale.
  Re-verified while closing: `CadenceSectionConfigMerge.merged` has exactly two callers
  (`applySectionConfigEdits`, `mutateSectionConfigs`); all four of *their* callers are local editors
  saving; and the repo contains no `NSPersistentStoreRemoteChange` / `didChangeExternally` /
  `CKDatabaseSubscription` observer at all.

- [T-652] **CLOSED 2026-09-01** (`d4f6b52`). `TagPickerPopoverViews.restore(_:)` commits through
  `CadencePendingChangePersistence.commitEdit` with the same two-field (`isArchived`, `updatedAt`)
  undo `archive` already takes, and the chip and the cleared query now run only below the `catch`.
  **The failure sentence is the popover's, not the edit sheet's** — restore is pressed from the
  popover's own results list and that surface stays open over a refusal, while `editFailureNotice`
  is only ever rendered *inside* `TagEditSheet`. So it is a second `@State`, `restoreFailureNotice`,
  rendered under the list and cleared when the query moves on.
  **Failing-first**: the new pin failed with 7 issues against unmodified source, each naming the
  right absence (`try?` count 1 not 0, no `commitEdit`, 0 undo fields, no notice, both report halves
  above the catch, no inline notice on the popover).
  **Mutation-tested**, five mutations, five killed by
  `theTagPickerSelectsARestoredTagOnlyOnceTheStoreTookTheUnarchive` by name: the original swallowed
  save restored, the report hoisted above the commit, the shared notice replaced by a hand-typed
  sentence, the notice never rendered, and half the undo dropped.
  **Why T-497's sweep missed it is the interesting part, and it is a detector gap, not an
  oversight** — restoring the defect leaves `CadenceSaveCommitDisciplineTests` green, because the
  rule's report vocabulary has no spelling for a surface that stays open and fills itself in. Filed
  as [[T-664]] with the measurement.

- [T-636] **CLOSED 2026-09-01.** All five parts resolved across two batches: (a) `afff149`,
  (b) `a84aced`, (c) and (e) `7ca3c29`, (d) resolved downward. **Two of the five were not what the
  ticket said**, and both corrections came from an agent reading the source rather than the audit:
  (b)'s named gap was already closed, and the real gap was the other half of the same sentence;
  (d)'s two findings turned out to be outside the rule entirely. Residue: [[T-654]], [[T-655]],
  [[T-657]], [[T-658]], and [[T-643]].
  **(a) LANDED (`afff149`).** The real root under
  CXT-005 was not the note repaint (which is the 96-of-112 category the rule deliberately leaves
  alone) but `CadenceTaskMutationSupport.toggleCompletion:30-37` — **the app-wide completion spine —
  swallowing a save over a recurrence insert.** It throws and takes `commit:` now, settling through a
  shared `commitSettle` and restoring through `commitEdit`; `CadenceTaskStatusEditing` catches and
  records on `CadenceTaskSettleFailureCenter`, which `iOSRootView` names once for all six surfaces.
  `setStatus` is the same shape and is **still exempt** — see [[T-643]].
  **(b) LANDED 2026-09-01.** CXT-007's own sentence — `return true` from a `-> Bool` drop handler,
  by the repo's own words (`TasksPanelDropCoordinator:29-32`: *"a silent accept says the move
  happened"*) — **was already in `successReport`**: [[T-627]] gap 4 put it there, gated on the
  declaration's return type, and the two sites it found
  (`CalendarPageBoardSupportViews.unschedule`, `TasksPanelSupport.assignTask`) have been ledgered
  against this ticket since. The gate is load-bearing and stays: a `return true` inside a
  `removeAll { … }` predicate is not a report, and
  `returningTrueIsASuccessReportOnlyFromADeclarationThatAnswersBool` pins that, with a fixture that
  is exactly that shape. The one sub-case the gate does hide — a `return true` from
  a Bool-answering **closure** inside a `var body` — has **zero instances**: measured 2026-09-01,
  no `dropDestination` / `onDrop` / `performDrop` body in the app holds a swallowed commit.
  What was genuinely missing was the **other half of the same sentence**. `Bool` and `Optional` are
  the two return types in which a declaration can say *"it did not work"*, so they are the two in
  which the answer **is** the report — and the Optional spelling was outside the vocabulary.
  `successReport` reads it now: a `-> X?` that returns anything other than `nil` in the swallowed
  commit's own block. **37 flagged declarations became 39**, and both new ones are real:
  `iOSMarkdownEditingSurface.toggleEmbeddedSubtask` ([[T-648]]) and
  `MarkdownEditorView.createInlineTag` ([[T-631]]'s second half — the phantom tag is written into
  the note's text, not only into Settings › Tags). Scoped to the frame that *builds* the answer;
  one frame down it adds three sites and all three are forwards, recorded at the call site.
  **(c) LANDED 2026-09-01 (`7ca3c29`).** `CadenceFocusSupport.complete` throws and takes `commit:`; it
  settles through the shared `CadenceTaskMutationSupport.commitSettle` and restores the three
  accumulators `logElapsedSeconds` writes with `+=`, which is the half the rule's standing
  *"the next fetch corrects it"* does not cover — a fetch re-reads whatever the counter now holds,
  so a lost `+=` stays lost, and `actualMinutes` feeds an hours-based `Goal`.
  `CadenceTaskStatusEditing.completeFocusSession` records the refusal on
  `CadenceTaskSettleFailureCenter` **and answers `false`**, because `iOSFocusView.complete` has
  something to do with that answer the shared alert cannot: the elapsed seconds exist nowhere but
  the stopwatch, so `resetTimer()` over a refusal loses them for good.
  Pinned by `CadenceFocusSessionAndBlockCommitTests`. **Residue: [[T-654]]**, the block timer's own
  door onto the same accumulators. The general `+=` merge question stays [[T-621]]'s.
  **(d) RESOLVED DOWNWARD 2026-09-01 — both are non-defects under this rule.** Re-checked against
  the source rather than the report. CXT-012 and CXT-015 are EventKit writes, not `ModelContext`
  commits, so the `try? save()` rule does not reach them at all: there is no pending change, no
  single shared context, and nothing for a later unrelated `save()` to take. Nor are they silent —
  every failure path in `CalendarManager` (`createStandaloneEvent`, both `updateEvent` overloads,
  `deleteEvent`, `save(_:span:describing:)`) returns through `record(_:)`, which sets
  `lastWriteFailure`, and both macOS hosts mount the alert that presents it
  (`SchedulePanel.swift:180`, `CalendarPageView.swift:149`). The single deliberate exception —
  `updateEventNotes(calendarEventID:)` returning `.eventNotFound` unrecorded — carries its own doc
  saying why (a debounced flush would raise the modal on a loop) and reports inline instead.
  **The one real residue is lost draft text**, and it is a parity gap rather than a swallowed
  failure: iOS keeps the sheet open on a refused write, macOS closes the popover and discards the
  title, notes, calendar and time range. Filed as [[T-658]]; the CXT ids are closed here.
  **(e) LANDED 2026-09-01 (`7ca3c29`) for `SchedulePanel`; two sibling canvases remain as [[T-655]].**
  Confirmed as filed: `onCreateBundle` called `SchedulingActions.createBundle`
  (`context.insert(bundle)`, no save), added the ticked tasks, and let `finishDraftCreation()`
  dismiss the draft popover. `SchedulingActions.insertBundle(title:dateKey:startMin:endMin:adding:in:commit:)`
  is the committing unit now — the block **and** its membership as one insert, because committing
  the block first would store an empty one and leave the member edits pending — and it restores the
  five fields `addTask` writes on each member when the commit is refused. The `do/catch` lives in
  `SchedulePanel`, which is the frame that owns the unit of work, and the refusal is an alert on the
  panel: the popover is gone by the time the store answers.
  The event branch beside it was left alone, as filed — EventKit failures already travel through
  `CalendarManager.lastWriteFailure` to `.calendarWriteFailureAlert()`.
  **CXT-003 is CLOSED as not-a-defect, 2026-09-01** — re-checked and confirmed: `linkedCalendarID`
  is an in-place field edit on an object the store already holds, nothing inserts, deletes,
  dismisses or reports, and the macOS path is `do/catch` with a `print`, not a `try?`. It is the
  96-of-112 category the rule deliberately leaves alone. If it belongs anywhere it is under
  [[T-614]]'s open question, which is the user's to decide and is **not** started here.

- [T-631] **CLOSED 2026-09-01 (`0ddbbb7`).** All six inline "create tag" doors commit through
  `TagSupport.resolveTagsCommittingInsertions(named:in:commit:)` /
  `TagSupport.committedTag(named:in:)`, which live in
  `Cadence/Shared/CadenceInlineTagCreation.swift`. Pinned by `CadenceInlineTagCommitSurfaceTests`
  (11 tests: five behavioural against a real container with a throwing `commit`, six source scans).
  **Every line number in the ticket had drifted and every claim in it was correct.**
  **Only the rows a call *minted* are handed to `commitInsert`.** An undo that took the whole
  resolved set would delete a tag the user already had; a `rollback()` undo would take the note
  someone is typing behind the popover with it. Both have their own behavioural test.
  **A new file, and the reason is a target boundary.** `TagSupport.swift` compiles into
  `CadenceWidgets`, which has no `CadencePendingChangePersistence` — so the committing spellings
  cannot live beside `resolveTags`. `TagSupport.resolution(named:in:)` went from `private` to
  internal to bridge that, which is recorded on it.
  **`onCreateTag` answers `Tag?` now**, and the `?? Tag(name: name)` fallback is gone: it handed the
  picker an object the store had never been asked about, which the picker then drew as a chip.
  Failing-first, against unmodified source with the exemptions deleted: half 3's sweep named
  exactly the five ambient frames, the `NoteEditorPane` exemption diff named `createTag`, and all
  five new source scans were red.
  **Six mutations, all compiled, five killed on the first pass and the sixth *survived*** — the
  surviving one was worth more than the five kills, and is filed as [[T-659]]: the ordering reader
  searched backwards, so a report written both above and below the refusal passed it. Fixed here,
  still live in the shared `reportFollowsTheCatch` that five suites read.
  **Residue, all filed**: [[T-651]] (the four sites still ledgered against this ticket's family),
  [[T-652]] (`TagPickerPopoverViews.restore`), [[T-653]] (two stale `TagSupport` maintenance
  exemptions), [[T-659]] (the reader).


- [T-638] **CLOSED 2026-09-01 (`3cfd576`).** All eight read
  `CadenceTaskSurfaceOptions.moreLabel(hidden:)` now — the two markdown task-embed draw calls, both
  iOS board cards, the iOS task row, the iOS markdown preview, the kanban card, and the macOS
  timeline bundle block.
  **The sweep is the larger half of the change.** T-598 left the eight because they already agreed
  with the constant; what nothing could catch was a *ninth*.
  `CadenceSharedConstantReuseSweepTests` harvests non-interpolated `static let` strings only, and
  this line is interpolated by nature, so a new surface typing `"+\(n) more"` was guarded by no test
  at all — which is how eight copies came to sit beside a constant that already said it.
  `CadenceTaskSurfaceOptionsTests.onlyTheSharedHelperSpellsTheOverflowLine` walks `Cadence/` and
  `CadenceWidgets/` and allows the line in exactly one file, the one that declares it.
  **The exception the ticket named is real and needed no exception list.**
  `MarkdownRenderedBlockTruncation.overflowLabel(unit:)`'s `"+ 4 more rows"` and
  `iOSTodaySchedulePanel`'s `"+3 more in Today"` both continue past the word `more`, and the needle
  is anchored on the literal's closing quote, so neither can be swept up by a change to the file
  list. A mutation injecting both spellings into an untouched file leaves the sweep green.
  Failing-first: the sweep named exactly the six files holding the eight sites. **Four mutations,
  all compiled**: reverting one converted site, respelling `moreLabel` the spaced way, and injecting
  a thirteenth site into `TasksListView` were all killed; the two-neighbour control survived, as
  designed.

- [T-633] **CLOSED 2026-09-01 (`e96c3e9`).** Both iOS scope dialogs commit now, through
  `CadenceTaskFieldEditCommit.commit(_:alsoRestoring:in:)` — the unit macOS's
  `TaskEmbedFieldEditorPopover` already reaches this same dialog through, whose `alsoRestoring:`
  exists for exactly this edit. `recurrenceTargets(from:allTasks:scope:)` is what is passed as that
  list, so `.thisAndFuture`'s undo reaches every later occurrence rather than only the tapped one,
  and the list is the one the edit itself walks rather than a second derivation of it.
  `iOSTaskRowActionViews.applyPendingRecurrenceRule` left `reportExemptions` and the sheet's
  `applyPendingRecurrenceChange` left `indirectReportExemptions`; the second site was named in the
  ledger rather than in the ticket, and is the same defect one frame down.
  **The alert existed and needed a path — and a second sentence.** "Couldn't Update the Series" and
  the series-lookup notice moved to `CadenceRecurrenceScopeCopy`, where the dialog's own prose
  already lives, and `noSurfaceTypesARecurrenceScopeSentenceOutAgain` now pins six sentences instead
  of four. A refused *commit* reads `CadencePendingChangePersistence.editFailureNotice` instead:
  "Try again" is honest for a read that failed and not for a store that refused a write.
  Pinned by `CadenceRecurrenceScopeCommitTests`. **Residue: [[T-656]]**, the non-series path, whose
  report is a shared picker's `isPresented = false` in another file.

- [T-635] **CLOSED 2026-09-01 (`819fc2f`).** `rollOver` throws and takes `commit:`; both hosts write the
  `@AppStorage` dismissal **only on the success path** and store `rollFailureNotice` otherwise. This
  was the one false success in the T-627 ledger that outlives a rollback — a defaults write survives
  the redraw, the relaunch and, since the key is deliberately shared, the other device.
  **`commitDelete`, not `commitEdit`**: the roll reaches `deleteBundleIfFullySettled`, so a block
  whose last active member was carried away has no object left to hand back and `rollback()` is the
  only undo that makes it visible again.
  **The sentence lives on the shared banner**, which is still on screen precisely because the
  dismissal was not written. A notice owned by one host would be missing from the other — the
  macOS-only shape [[T-195]] spent a ticket undoing.
  **The ticket's line numbers had drifted and every claim in it was correct**: `TasksPanel` was
  354-362 rather than 331-334, `rollOverTaskToToday` 999-1015, `deleteBundleIfFullySettled`
  1033-1045.
  Failing-first: three source scans red against unmodified source for the right reasons (no
  `commitDelete`, no `try`/`catch` in either host, no `failureNotice` on the banner). **Four
  mutations, all compiled, all killed** — `try?` on the commit; `commitEdit`-with-an-empty-undo in
  place of `commitDelete`, which leaves the emptied block deleted; the banner's `failureRow` removed;
  and the iOS host naming the refusal with a literal of its own.

- [T-632] **CLOSED 2026-09-01 (`2177d1a`).** The kanban column editor commits before it closes.
  `saveSection` answers `Bool` and commits through `CadencePendingChangePersistence.commitEdit`
  under a `CadenceListEditSnapshot` undo; the archive closure is now `toggleSectionArchive()`, a
  named function, so `showEditor = false` is the last statement after a commit that returned rather
  than the first after a `try?`. A refused write draws `CadenceInlineFailureNotice` at the foot of
  the popover and leaves the popover open on the column that did not move.
  **The ticket's disproved sub-claim held up:** the settle is field edits only —
  `TaskContainerLifecycleService` routes through `settleWithoutAdvancingSeries`, which does not
  spawn a successor — so the undo is a snapshot and not an un-insert. That is also why the undo is
  not `modelContext.rollback()`: one `ModelContext` app-wide, and an edit's rollback is invisible
  until something refetches (T-402).
  **What the ticket did not say, and what shaped the fix:** `SectionCompletionAnimationManager`
  writes a *reopen* synchronously and defers a *completion* behind a 2.5-second countdown. Only the
  reopen could ever have been closed over, which is why the completion button is gated on the notice
  flag rather than on a return value — a completion has nothing to have failed at by the time the
  button returns. The deferred half's refusal still has nowhere to appear; filed as [[T-646]].
  The other three writes in the same popover reach no commit at all and are [[T-645]].

- [T-634] **CLOSED 2026-09-01 (`673dd13`).** Both task-detail subtask surfaces commit, and neither
  reports before the commit returns. macOS's `TaskDetailPopover.addSubtask` reached **no commit at
  all** and emptied the field anyway; the delete was an inline closure in `body` with the same
  problem; iOS cleared the field and *then* swallowed. All four now go through
  `CadencePendingChangePersistence.commitInsert` / `commitDelete`, and the report — the field
  emptying — happens only after. The macOS entries left `commitReachExemptions` and the iOS pair
  left `existenceExemptions` in the same change.
  **A second defect fell out of the fix, and it is measured rather than argued.** Neither shared
  commit unit is sufficient on its own here, and they fail in opposite directions:
  `commitInsert`'s undo deletes the row, but `insertSubtask` had also appended it to
  `task.subtasks` and the delete does not reach that array before the surface re-renders — a refused
  insert would have drawn a **phantom subtask that exists nowhere**. `commitDelete`'s `rollback()`
  un-deletes the row in the store but does not put it back on the array `deleteSubtask` edited — a
  refused delete would have **hidden a live subtask until the next launch**. Both are pinned by
  `arefusedSubtaskInsertLeavesAPhantomOnTheParentUntilTheCallerDropsIt` and
  `arefusedSubtaskDeleteLeavesTheRowMissingFromTheParentUntilTheCallerPutsItBack`, whose assertion
  order is load-bearing: reading the array *before* the repair is the whole measurement. The repair
  is one captured array per call site — `CadenceListEditSnapshot`'s idiom shrunk to its one field —
  and `bothSubtaskSurfacesPutTheParentsArrayBackOnARefusedCommit` keeps both platforms spelling it.
  The two sentences are `CadenceTaskInspectorSupport.subtaskAddFailureNotice` /
  `subtaskDeleteFailureNotice`, in the one file both surfaces already share; only the delete one
  promises "Nothing was removed", because only the delete side's undo makes that true.
  Residue filed: [[T-647]].

- [T-630] **CLOSED 2026-09-01 (`c15cace`).** Both `NoteActionSupport.move` helpers `throw` and commit
  through `CadencePendingChangePersistence.commitEdit(in:commit:undo:)`, and the three destination rows
  hand their move to one `moveNote` that dismisses only below the `catch`. The undo is a snapshot of
  `area`, `project` and `updatedAt` rather than `rollback()` — one `ModelContext` app-wide, so a refused
  move must not take the note somebody is typing behind the popover with it. `ModelContext?` became
  `ModelContext` in the same change: that optionality is the shape half 3 of the rule *exempts* while
  the body did what half 2 forbids, and both call sites already passed a non-optional `@Environment`
  value, so it only ever bought a second silent no-op.
  The refusal is a `CadenceInlineFailureNotice` on the Move page, which is still open because the row
  no longer closes it — the popover shutting was the whole (false) success signal.
  Pinned by `CadenceNoteMoveCommitTests`: three behavioural tests against a real container with a
  `commit` that throws, three source scans for the row ordering. The
  `indirectReportExemptions` entry is deleted in the same change.

- [T-629] **CLOSED 2026-09-01 (`24f9066`).** All three image doors — macOS `createAssets`, iOS
  `insertPickedImages` and `createPastedImageAssets` — commit through `commitInsert`, which un-inserts
  the whole batch when the store refuses, and write **no** `![…](cadence-image://…)` reference in that
  case. The batch rather than the first asset, because a multi-image paste writes one reference each.
  **It errs in the same direction as [[T-620]] deliberately.** That fix made the delete sweep a
  candidate-set delete because an asset whose owner has not synced yet is indistinguishable from an
  unreferenced one, and paid for it in leaked bytes. This pays the same way from the other end: a
  refused insertion costs the user the paste rather than leaving a token pointing at nothing. The
  shared invariant is that neither end leaves markdown referencing an asset the store does not hold.
  `[]` was already both platforms' refusal (`allowsImageInsertion`; `insertMarkdownImages` no-ops on an
  empty list), so a refused commit reaches the text layer as "there are no images", which is true. Both
  editors gained an `imageFailureNotice`, because neither has a sheet to close. `resizeImage` /
  `resizeImageAsset` keep their `try?` on purpose — an in-place field edit on a row the store already
  holds, reporting nothing, is what the rule still allows.
  Pinned by `CadenceMarkdownImageCommitSurfaceTests`; both `existenceExemptions` entries deleted, with
  `MarkdownEditorView` keeping `createInlineTag` because that is [[T-631]]'s shape.

- [T-641] **CLOSED 2026-09-01 (`1425fde`).** Fixed by the agent that shipped it, and it named its own
  mistake precisely: *"I checked the constraint for the source and not for the destination."*
  **It kept the call on the app side, after checking the closure rather than assuming.**
  `CadenceTaskMutationSupport` pulls `CadencePendingChangePersistence`, `NotificationManager` and the
  bundle helpers; `NotificationManager` is `@MainActor`, `@Observable`, `UserNotifications`-backed and
  drags the habit-reminder planning chain behind it — **a large source list added to a command-line tool
  with no notification centre and no business cancelling a reminder**, when the small explicit list is
  exactly the property the test protects. Re-spelling `detachRelationships` beside the pass was the
  other exit and is the drift this repo forbids.
  The seam is `CadenceForkedOccurrenceRemoval`, declared at file scope where it is consumed — **the same
  shape and the same reason as `CadenceListTaskSweep`**, which exists for precisely this "a piece of the
  cascade cannot be spelled where the cascade lives" problem. Decision stays in the service; removal
  moved to a new app-only file; `PersistenceController` supplies it; **`CadenceStoreMaintenance` supplies
  none, with a comment saying that is the process's answer rather than an omission** — a fork it leaves
  alone is collapsed by the app's next startup repair, whereas a fork it half-removed would not be.
  **Two things the seam's `nil` default could have hidden are now pinned:** that `nil` is *inert* rather
  than half-done (nothing removed, counter zero, `changed == false`, pointer untouched), and that the one
  call site where forgetting costs the user everything actually passes it — the default meant ~20
  existing callers did not change, leaving that site protected by nothing the compiler sees.
  **Verified against `-scheme CadenceMCPServer` directly**, and the split proven real: the MCP build
  compiled `DataIntegrityRepairService.swift` and did **not** compile the new remover.
  **Mutation N3 reintroduced the exact break and turned the guard red** — so the test catches this, not
  merely a rearrangement of it.

- [T-622] **CLOSED 2026-09-01 (`2437da7`, target-membership follow-up `1425fde`).** A forked series is
  collapsed back onto one occurrence. No stored property added — `recurrenceSeriesIDRaw` and
  `recurrenceOccurrenceIndex` were already written on every successor, so the fork was always
  identifiable and simply never collapsed. **The survivor is the lowest `id.uuidString` and nothing
  else**, because the rule must give the same answer on every device: a rule that reads local state
  (keep the completed one, keep the newest) is not a tie-break but a second fork, and each device
  would then delete the row the other kept. Work is protected by a removability test rather than by
  the choice of survivor — a row goes only if it still looks like the copy the spawn made. The
  predecessor is **re-pointed** at the survivor, not cleared, because a nil pointer respawns the fork.

- [T-620] **CLOSED 2026-09-01 (`9d38854`).** `deleteUnreferencedMarkdownImageAssets` is now a
  candidate-set delete: it considers only the assets the markdown *being deleted* referenced, and all
  four paths supply their own set. This is `DataIntegrityRepairService`'s own reasoning applied to the
  same model type from the other side — repair refuses to collect an orphaned `MarkdownImageAsset`
  because an unowned row is indistinguishable from one whose owner has not arrived, and the type has no
  relationship to `Note` or `AppTask` for CloudKit to order by. **The cost is a leak rather than a
  loss**, the direction this area already errs in. It is also the definition both confirmation sheets
  already promised, so the counts shown and the effect of the button stopped differing.

- [T-627] **CLOSED 2026-09-01 (`91fe8e4`).** All four gaps closed. **The flagged population went from
  7 declarations in 6 files to 56 in 43** — the 49 new ones **ledgered, not fixed**, nearly all naming
  the ticket that owns them (T-629..T-636). The ledger is exact in both directions, which is what makes
  the widening safe to land *before* the fixes.
  **Gap 1 is not one hop.** A pending existence change travels up through every frame *handed* a
  `ModelContext` and stops at the first that was not — **half 3's own exemption rule read forwards.** It
  terminates for free (chasing every callee would report every screen that transitively touches
  `TagSupport.resolveTags`) and reaches **four frames deep**, which the macOS completion spine needs.
  **The recursion guard was keyed on name alone, and that cost the biggest finding:**
  `TaskWorkflowService.markDone` forwards to `CadenceTaskRecurrenceWorkflowSupport.markDone`, a bare-name
  guard read that as self-recursion, **and the whole completion spine went quiet.** Keyed on type as well
  now.
  **Three measured costs, each pinned:** (i) reading the whole block exposed `context.isArchived = false`
  — a *model field* — above a swallowed save in four settings screens, so the flag spellings needed a
  `(?<![.\w])`-with-`self.` anchor; (ii) a `pending<X> = nil` the same declaration also `cancel()`s is a
  work item, not a screen — worth exactly two false positives; (iii) **the commit index publishes a name
  only when every overload agrees** — `SchedulingActions` has two `createBundle(...in:)` and only one
  commits, and letting it vouch for its sibling silenced two real findings.
  Half 3's exemption list is no longer empty **and the doc says why** — the signature rule never covered
  the population gaps 1 and 3 added. One entry is a **named false positive**
  (`CadenceWriteService.resolvedTags`) rather than a weakened rule. `AGENTS.md` restates the rule in the
  same eight lines; still 199/200.

- [T-628] **CLOSED 2026-09-01 (`79aa8f6`), and the detector confirms it** — the four ledger entries
  [[T-627]] filed for these sites went stale **in the same commit that fixed them**.
  **(a)** The boundary goes at `TaskCompletionAnimationManager.write`, the first frame not handed a
  context. `spawnNextOccurrenceIfNeeded` now returns the successor so `commitInsert` can un-insert it;
  status, `completedAt` and `recurrenceSpawnedTaskID` are snapshotted and restored, the circle re-draws
  open, and the failure is named. `rollback()` was **refused** for the reason `commitEdit`'s doc gives.
  **The inspector's Mark done was a second, un-funnelled path nobody had counted** — it reaches
  `markDone` without the manager, so it carries its own inline notice.
  **(b)** Complete / Unbundle / Delete all route through `CadenceTaskMutationSupport.deleteBundle` —
  T-322's throwing sibling, which iOS already used — rather than a fourth copy of the member loop;
  **`detachBundleMembers` is deleted.** All three throw and take `commit:`, both hosts **close only on
  success**, and the timeline hover-delete moved to `presentRefusable`.
  **A collateral pin moved and the pin was stale:** `noStatusIsAssignedDirectlyInTheAnimationManager`
  named the literal call spellings; its claim — one funnel, once per transition — is unchanged, the
  funnel just gained a committing spelling. Re-pointed, with the uncommitted spellings pinned at **zero**.
  Refusals are asserted through a **second `ModelContext` on the same container**, and the tests say why:
  `rollback()` un-deletes unconditionally but does not visibly undo a field edit, so the live
  `bundle.tasks` still reads empty while the store is correct throughout.


- [T-606] **CLOSED 2026-09-01 (`4f4ab61`).** macOS Today draws one Sort chip over iOS's named set;
  the Order chip is gone and direction folds into the modes.
  **The briefed hazard was disarmed by the audit, not by luck.** The preference lives in six
  `UserDefaults` keys and nowhere else — nothing on a SwiftData model, no reference from
  `CadenceMCPServer`, `CadenceWidgets`, the MCP DTOs, the export service or `PrivacyDataResetService`.
  **So no `SchemaMigrationPlan` is implicated and ZERO enum cases were removed** — five of the six macOS
  surfaces still speak the two-chip vocabulary.
  **Mapping proven from the comparators, not the labels:** `.date` sorts `scheduledDate`, which
  `AppTask.swift:227` calls *"the day this is time-blocked"* — the do date — and
  `CadenceTaskQuerySupport.sortDateKey` is **character-identical** to `TaskOrdering.dateSortKey`,
  `"9999-99-99"` sentinel included. Custom->List Order, Date+Asc->Do Date and Priority+Desc->Priority
  are exact. **Date+Desc and Priority+Asc have no iOS equivalent and genuinely re-order those users'
  rows** — neither was ever a default, and a test **asserts they differ** so the cost is recorded rather
  than buried.
  **macOS keeps `.doDate` as its default rather than iOS's `.priority`, deliberately.** macOS shipped
  Date+Ascending, so taking iOS's default would have silently re-sorted every user who never opened the
  chip. Adopting iOS's *named set* was the decision; adopting its *default* was not. **Do not "fix" the
  inconsistency.**
  New `todaySortMode` key wins when it decodes, else the retired `todaySortField` is mapped, else the
  default; retired keys are read but **never written or cleared**, so a rolled-back build still finds
  its preference.
  **A hygiene guard caught a real leak mid-work:** the first defaults test minted a suite from `UUID()`,
  which strands a preference plist in the app's own container on every run ([[T-516]]) — the container
  the brief forbids touching. Rewritten onto the shared `withTemporaryDefaults` helper. **The guard was
  right and the new test was wrong.**
  Ten tests; eight mutations, each confirmed applied *and* compiled, all killed by name. Two source-scan
  tests were killed by no mutation and **that is reported rather than claimed as coverage**.


- [T-603] **CLOSED 2026-09-01 (`e7e58fc`).** The square cell fill and the `radiusControl` ring are
  gone; a selected day is marked by the badge's solid circle alone — which
  `iOSCalendarMonthCompactDayCell` beside it already did. Today's 0.045 wash stays, because `isToday`
  is a different fact.
  **Premise correction: macOS's month grid has NO per-day selection state at all** —
  `CalendarPageMonthSupportViews` contains no `isSelected`; its plate change is in-month vs carried-day.
  The decision is unaffected (nothing on macOS had to move), but **"all three month surfaces agree" was
  wrong** — it is "the two iOS grids agree, and macOS has no opinion."
  An over-broad first assertion also matched `iOSCalendarMiniChip`'s plate and was narrowed to a window
  over the day cell — caught by the agent's own collateral pass, not by review.

- [T-604] **CLOSED 2026-09-01 (`dac9110`).** Both sheets moved to `style: .ruled`, so the "Schedule"
  group is one component across all three.
  **The scope grew beyond `style:` and the reason is sound — I verified it.** `.ruled` **draws no
  card**, and both pre-existing `.ruled` sheets frame their form in `cardPadding` inside
  `Theme.radiusPanel`. Converting `style:` alone would have left the two sheets' fields lying directly
  on near-black and the Schedule group *still* reading as two components. Each converted sheet gained
  quick-create's frame figure for figure. That is the section style's own structure, not the chrome the
  ticket excluded — **toolbars and buttons are untouched.**
  Two knock-ons fell out: the block title's `surfaceElevated.opacity(0.65)` well became the new plate on
  itself and was removed, and its literal `16`/`18` became the shared `groupSpacing`/`gutter` — identical
  values, nothing moves.

- [T-605] **CLOSED 2026-09-01 (`36c2809`).** Today's headings now draw the accent bar, the 14pt bold
  sentence-case title and the split "3 / 7" counts. **`TasksPanelIntentSectionHeader` was deleted, not
  rewritten** — its chevron and hover fill are the shared header's own, so keeping the wrapper would
  have meant **two hover layers at two radii**. macOS now has exactly one group header.
  The deliberate macOS/iOS divergence is recorded in **three** places — the section view's doc,
  `CadenceTaskGroupHeading`'s doc (which used to call itself "one heading for Today on both platforms"),
  and the test. **Do not re-file it as drift.**
  **A collateral pin moved and the pin was the stale half:** T-161's
  `bothPlatformsDrawTheSharedTaskGroupHeading` encoded exactly the arrangement this ticket reverses. It
  was replaced by a test asserting **0** call sites there — *the number was not bumped* — plus pins on
  `TaskListGroupHeader` at 2/2/1 across Today, All Tasks and Inbox, and a requirement that the deleted
  wrapper have no live mention.
  Accepted degeneracy, stated rather than hidden: inside "Overdue" the split reads flag-N over "0
  tasks" — not a new state, an all-overdue All Tasks group has read that since the header existed.


- [T-598] **CLOSED 2026-09-01 (`43c2294`).** New `CadenceStartTimeFieldRow` owns the label, glyph,
  tint and popover; all three sheets are one line each. **"Start" won** — the neighbours are
  "Date"/"Duration", so "Starts" was the only verb and "Time" the only label not saying *which* time
  next to a Date row setting the other half of the same instant. The word is a `static let` **inside**
  the component, not a `label:` argument, **because a parameter is how the app got three of them.**
  "Read-only" won on (b); unspaced `"+3 more"` won 9-3 on (c), hoisted to
  `CadenceTaskSurfaceOptions.moreLabel(hidden:)`.
  **Sweep-floor caveat, stated in the code as well as here:** only `"Nothing scheduled"` genuinely arms
  `CadenceSharedConstantReuseSweepTests`. `"Start"` is 5 chars, `"Read-only"` is 9 **and** a computed
  `switch` rather than a `static let`, and `"+\(n) more"` is interpolated and excluded by the harvest
  pattern. Those three are carried by hand-written guards, named in the doc comments **so the omission
  cannot read as coverage.**

- [T-601] **CLOSED 2026-09-01 (`239f031`).** (a) **premise partly disproved** — it was *not*
  `CadenceInlineEmpty` exactly; the hand-rolled version folded an `iOSActionButton` into the card, so no
  one-line substitution existed. Fixed the way the Board answers it. Note the sentence *had* to move to
  `CadenceEmptyStateCopy` in the same change — **the hand-rolled copy was invisible to
  `noEmptyStateSentenceIsSpelledInTwoFiles` precisely because it was not a component call.**
  (b) `hourLabel` deleted, asserted byte-identical to `TimeFormatters.timeString` for all 24 hours.
  **(c) The 0.76 was established as accidental, then removed.** It arrives whole in `19fbf8b`, a bulk
  refactor that never mentions it, where `rowTint` fed *two* consumers — this circle and a
  `strokeBorder(rowTint.opacity(0.22))`. `fcc8300` deleted that border with every hard card border in
  the app, **so the second consumer went in a sweep about elevation and the value survived because
  nothing in a de-bordering pass was looking at it.** Nothing names it; the same circle elsewhere
  already resolves through `CadenceTaskCompletionGlyph` to full-strength `Theme.dim`. Archaeology
  recorded in the file.

- [T-607] **CLOSED 2026-09-01 (`b09bc5f`).** **The evidence came back partly negative and that is the
  result.** The deleted-project case is **not** reachable through the app's own delete path —
  `deleteProject` cascades the list's tasks with it — and is **impossible on Inbox**, which has one
  `list:inbox` group. The live window is a stale `@Query` snapshot: a list deleted in another window
  mid-drag, or a CloudKit delete arriving before a re-render. **So this is a hardening, not a bug fix
  with a visible before/after.**
  `TasksListView` held a line-for-line copy of both drop handlers differing only in discarding
  `assignTask`'s answer. **The copy was deleted and both routed through the coordinator rather than the
  `return` being patched — because a view body has no test seam**, so the one-line fix the ticket
  described would have been a behaviour change no test could see. `taskDropHandler`'s currying pair
  untouched, leaving [[T-564]](b) undecided.

- [T-610] **CLOSED 2026-09-01** (`6bb6e6a`, `c821afb`, `adbf6ee`, `653d9eb`, `1401361`, `2bd0383`).
  **43 of 44 named across all 28 files**, ledger honest at 1. Each commit deletes its own ledger lines
  and moves the headline, so **every commit is green on its own** (44→36→31→23→17→10→1). Four `help:`
  parameters became `accessibilityLabel:` — T-472's durable half.
  **The one left is deliberate:** `FocusPickItemRow` is a *text* row, not an icon control — SwiftUI
  already names it from the title and detail line it draws. Its `helpText` is an action, so using it
  would make twenty rows announce the same four words; using the title would silently drop the
  scheduling line announced today. Naming it well needs a plain-text form of
  `CadenceTaskDetailLineLabel` in `Cadence/Shared/`. Argued in the ledger's own doc.
  **Colour swatches were not guessed:** two sites have no verifiable name, so it reused iOS's existing
  "Selected colour"/"Use this colour" rather than invent colour names, which
  `CadenceAccentPalettePresentation` says the repo deliberately refuses to do.
  **A collateral pin caught it being wrong:** its first `TimelineBundleBlock` label spelled
  `title.isEmpty ? "Untitled"` — exactly [[T-590]]'s defect. **The pin was right and the change was
  wrong**; fixed to `TaskTitleSupport.displayTitle`. It also repointed the detector's positive witness
  to read out of the ledger instead of naming a file it expected someone to clean.

- [T-611] **CLOSED 2026-09-01 (`e19921a`). Two premise corrections, and the second changed the design.**
  **(i) "1 label across 25 buttons" was misleading** — 24 of the 25 are context-menu items spelled
  `Label(text, systemImage:)`, which name themselves. The file has **zero icon-only buttons**, so the
  rule this ticket asked for does not reach it at all.
  **(ii) Its real gap is the [[T-594]] shape:** chips draw a *value* ("Tomorrow", "Weekly", "30m") and
  never say which field it belongs to — **the do chip and the due chip announce identically.** No rule
  about button labels can see that.
  So the fix is a **compile-time gate, not a third sweep**: `iOSTaskAttributeChip.field` is a `let` with
  no default, so the 8th chip **fails to build** rather than fails a test. The completion circle had a
  name but a *second spelling* ("Mark task todo" vs the shared "Reopen task"); it reads the shared
  action-keyed property now.
  The rule was still written first, in its **own** suite because [[T-610]] was rewriting the other
  file's ledger in the same tree, and **the sweep's iOS blindness is now measured** (0 offenders over
  105 files) rather than assumed. New ledger: 3 sites in 2 files. Follow-on: [[T-637]].

- [T-613] **CLOSED 2026-09-01 (`f2672e7`).** Premise fully confirmed — `git show 85809ff` deletes a
  bare `.cadenceCard()` directly above each of the three `.padding(cardPadding)` lines.
  **On iPhone:** All Tasks / Inbox group headers, rows **and the Apple Reminders strip** move 12pt left
  (28 -> 16) onto the page header's own gutter; a list's Tasks tab moves 8pt left (24 -> 16) and its
  bar-to-header gap tightens 24 -> 12. No background appears or disappears — there has been none since
  August.
  `cardPadding` **removed rather than zeroed** per [[T-587]]'s rule; `iOSInboxRemindersSection` loses a
  `metrics:` parameter it wanted for nothing else. `theGroupCardHasAnInsetAtBothWidths` — **written a
  fortnight after the card was deleted and structurally unable to see it** — replaced by a
  memberwise-init pin and a brace-matched call-site scan.


- [T-595] **CLOSED 2026-08-31 (`32dbe81`).** **This ticket's headline was wrong: it is not ten
  divergent weights.** Two of the reported ten are agreements the calendar already had and were left
  alone — the Board's 0.28 already matches macOS's Board, and the bundle sheet's 0.35 is the app's
  row-separator weight used across Shared, iOS and macOS. **Pulling either into the calendar's
  vocabulary would have broken an agreement to fix a phantom.** And the reported "1.0" is
  `Theme.borderSubtle` with no `.opacity` modifier at all — the absence of a weight, not a tenth one.
  `iOSCalendarHairlineMetrics` now states three: `dayEdge` **0.42** (0.30 had one site repo-wide
  against the others' two), `pinnedEdge` **0.65** (two of three lines already drew it, and they meet at
  the canvas corner), and the ladder's 0.46/0.20 beside a named `hourEmphasisInterval`.
  `CadenceCalendarWeekdayHeaderMetrics.bandHeight` = **22** over 36 — eight test call sites pin
  `gridRowHeight` against 22, and 36 spends 12pt of padding on a 12pt line. **Every line number in the
  ticket was stale.**

- [T-596] **CLOSED 2026-08-31 (`13c3fde`).** Today's timeline now reads the Calendar's hour ladder —
  0.5pt at 0.46/0.20, cadence included — on T-588's grounds, and because 0.5pt is a hairline where 1pt
  is two device pixels.
  **Premise correction:** `Theme.radiusControl - 3` is **not** "the repo's inner-pill idiom" — it stands
  at **2 sites against 55** bare `cornerRadius: 7`. The token spelling was taken anyway because hoisting
  literals is this batch's whole direction, and the other half of the claim does hold: zero hardcoded
  radii remain in the six scoped files. Split out as [[T-616]].
  Gutters are in `CadenceTodaySectionMetrics` and **none varies by layout**: 14 unchanged, top **12** as
  a stated tie-break on site count (9 vs 5), bottom **16 on evidence** — 16 carries the rationale, and
  `iOSTaskCollectionMetrics` gives All Tasks and Inbox that same 16 at *both* widths, so the app had
  already decided it does not ramp. The test pins against that type, not against the number.

- [T-597] **CLOSED 2026-08-31 (`7d5a5b0`).** Cancelled chip reads `secondaryFontSize` at 4/2.
  **Premise correction: three of the four siblings use 4/2, not four** — the bundle badge draws the
  shared font but has no chip padding at all.
  New `TasksPanelMetrics` states the gutter and both header insets; bottom **6** over 5 on site count
  (5 vs 1), and `todayRowLeadingInset` now reads the gutter its own doc already claimed to match.
  **Deliberate deviation from this ticket, and it was right:** it did *not* point these at
  `TaskListDisplayMetrics.headerHorizontalInset` (24) as instructed. That inset sits over rows indented
  52; the panel's rows start at 14, so a 24pt heading would be **indented 10pt from the rows it heads**
  — the exact defect `CadencePageHeaderMetrics` keeps its own gutter to avoid. A test pins that
  argument against both types, so it fails if the list detail's inset changes meaning.
  A collateral run caught the expected exact-count pin (`secondaryFontSize` reads 5 -> 6); updated with
  the reason, since the chip genuinely became a sixth reader.


- [T-599] **CLOSED 2026-08-31 (`102dbd6`).** Five strings hoisted to `CadenceSettingsSectionCopy` and
  registered with the shared-constant sweep, so a third surface typing any of them is a sweep hit —
  not two literals edited into agreement.
  **Two deviations from this ticket's recommendations, both better reasoned than the ticket:**
  (i) it also converged the *title*, which the ticket did not name — macOS had `"No active tags."` and
  iOS `"No active tags"`, and **iOS's full-stop-free form won because a title is not a sentence, and
  macOS's own four one-liners disagreed with each other about it** (`"No templates available"` vs
  `"No active contexts."`). (ii) Save took macOS's `"Save API Key"` rather than iOS's `"Save Key"`, so
  **Save and Delete name the same whole noun** — the ticket had only specified Delete.
  (b) is deliberately *partial*: only iOS's scope sentence is shared; macOS's "the note sidebar" clause
  stays macOS-only, pinned by a test that also asserts **the phone never grows those words**.
  **Left unconverged on purpose:** the Test button's in-flight label is still `"Testing..."` / `"Testing"`
  — at 10 characters it is under the sweep's 12-character floor, so a constant would arm nothing.
  Recorded in the constant's doc rather than silently skipped.

- [T-600] **CLOSED 2026-08-31 (`3d9f0b8`), in the required order.** (a) `iOSSettingsEmptyRow` deleted,
  `iOSSettingsEmptyInlineRow` moved into `iOSSettingsComponents.swift`; its two callers now pass `tag`
  and `square.stack.3d.up` instead of inheriting a hardcoded `tray`, and the 13/14pt, `dim`/`subdued`,
  6/4pt drift is closed. (b) All four macOS one-liners now draw the shared `CadenceSettingsNoticeRow`
  over nine strings in a new `CadenceSettingsEmptyStateCopy` — three were private `HStack`s and the
  templates one was a bare `Text` in no row at all. macOS's Inactive Lists card gains the eyebrow iOS
  had.
  **One pinned count moved and the agent judged it stale rather than bumping it blindly:**
  `theSevenPanesReadTheSharedFieldVocabulary` expected 1 `CadenceSettingsNoticeRow` in
  `SettingsRemindersSection` and now expects 2 — **because the second row replaced a private near-copy
  rather than adding a row**, and that pane already drew a notice row for its access verdict twenty
  lines up. The reason is in the test's comment. No other pinned count moved.


- [T-583] **CLOSED 2026-08-31 (`a4b03cd`).** The INFERRED half does **not** survive: autosave is on,
  but "eventually" is exactly what T-327 measured, so deleting the four neighbouring saves was the wrong
  branch. **And the case was stronger than the ticket knew** — macOS's *own*
  `SettingsTagsSection.swift:192-201` already had the `archive(_:)`/`restore(_:)` shape, so the contexts
  pane was deviating from its own platform, not merely from iOS.
  The two inline closures are now `archiveContext(_:)`/`restoreContext(_:)` beside `moveContext`, each
  doing the write plus the save, with the convention written down: **existence changes report, field
  edits commit quietly.** **CORRECTED 2026-09-04 by [[T-614]] — the `moveContext` half of this entry was
  wrong.** It recorded the reorder's swallowed save as deliberate on the grounds that `order` is a
  field edit and nothing after it reports success. The first is true; the second is not, and it is the
  half the rule turns on: a row that stays where you dropped it *is* the success report. The user
  settled it that way, `AGENTS.md` now says so, and `moveContext` commits through
  `CadencePendingChangePersistence` on both platforms. **The rest of this entry stands** — the
  "five spellings" argument was about `archiveContext`/`restoreContext`/`reopenArea`/`reopenProject`,
  which are genuinely the case the rule leaves alone and keep their `try?`.

- [T-602] **CLOSED 2026-08-31 (`1dd6c4a`).** `NOTES / <active tab>` and `SCHEDULE / Timeline` are now
  simply **Notes** and **Timeline**. `PanelHeader.eyebrow` is optional and unused; `NotePanel.headerTitle`
  — which restated the tab strip eight lines below it — is deleted.
  **Neither column had a second fact to promote** the way the task column had the date, so neither
  invented one. **And it is deliberately not "no header at all":** iPad *does* delete both, because
  `iPadTodayInspectorSwitcher` names the pane; macOS's three columns stand side by side with nothing
  else naming them, so one title each stays. "Timeline" over "Schedule" because that is the word the
  zoom control, the `Close timeline` label and iPad's switcher already use.
  **Cost stated as computed, not observed:** with no eyebrow the two titles sit ~14pt higher inside the
  unchanged 100pt band. The app was not launched.


- [T-579] **CLOSED 2026-08-31 (`4849cea`).** iOS Settings > Defaults now carries a "Default page" row
  over `ListDetailPage.allCases`, on the same shared value-row/popover vocabulary macOS uses, with
  macOS's one-time stale-value normalization brought across. Nothing removed from macOS; `ios.calendar.*`
  remains genuinely iOS-only.

- [T-580] **CLOSED 2026-08-31 (`87872f4`).** `.sync` retitled "iCloud Sync" — one string fixed both
  platforms: macOS no longer draws two rows about an account, iOS no longer says "Account" on a
  platform with none. **Both checks the ticket asked for came back clean:** the string is a label only,
  `rawValue` (`"sync"`) is what persists and decodes and was untouched, and the only test hits on the
  old title were `#require` *messages*, not assertions.

- [T-581] **CLOSED 2026-08-31 (`a95423e`).** iOS gained Move Up / Move Down in the context menu each
  row already had, greyed at the ends — **not `.onMove`**, which needs a `List` in edit mode and this is
  a card of rows. Index arithmetic is now shared (`CadenceOrderReassignment`) and macOS reads it too, so
  there is no second copy to drift.
  **It did not copy macOS's swallowed save.** macOS ends `moveContext` in `try? save()`, which is inside
  the letter of the rule but leaves a refused save as a rearrangement the next launch silently undoes.
  iOS commits through `CadencePendingChangePersistence.commitEdit(in:undo:)`, restoring every `order` on
  refusal so the card re-sorts to the store, with an inline failure notice. Both sides renumber over
  *every* context including archived ones — numbering only the visible slice hands them indices archived
  rows already hold, and a sort on ties is unstable.

- [T-568] **CLOSED 2026-08-31 (`4628fd7`).** User chose macOS's documented 0.50, one layer. Token now
  `CadenceCalendarDayBadge.outOfMonthLabelOpacity` in Shared (iOS cannot see `Cadence/macOS/`), read by
  both platforms, with the contrast maths beside it. The badge's second dim and the whole-cell
  `.opacity(0.52)` are gone; **following macOS's shape, the plate moves instead** — in-month
  `Theme.surface`, carried `Theme.bg` — with today's and the selection's washes drawn over it, so the
  today ring and the event chips are no longer faded. No third value invented.

- [T-572] **CLOSED 2026-08-31 (`321cafd`).** **The prerequisite was right and saved the ticket from
  shipping a bug twice.** macOS's label announced active+completed while its header drew active-only,
  so copying it to iOS would have exported the mismatch. Fixed macOS in the same change and gave
  neither side its own sentence: both read `CadenceBoardColumnAccessibility.dayColumnLabel`. macOS's
  `totalCount` had one reader and is deleted. Pinned as a value **and** as a call-site scan asserting
  the *argument* — a count-only scan would stay green if a sum were passed back in.

- [T-573] **CLOSED 2026-08-31 (`bd8da45`).** `.isSelected` added; all three cells now say what is on
  the day via `CadenceCalendarDayAccessibility`. **Label rule chosen deliberately:** count where a
  count is drawn, presence where only a dot is, both where two are. The agenda count *is* knowable and
  is deliberately not announced — stating a figure that is nowhere on screen is the mirror of the
  T-571 mismatch.
  **Premise did not reproduce:** `iOSCalendarTimelineViews:569` is **not** a third instance. That
  header carries no selection state by design — its doc says so, its background keys on `isToday`
  alone, and the grid passes it no `isSelected`. Adding the trait would announce a state the screen was
  deliberately changed to stop drawing. Exemption pinned by
  `theTimelineDayHeaderHasNoSelectedStateToAnnounce`.

- [T-587] **CLOSED 2026-08-31 (`2668841`).** **Git settled it:** `git log -S'drawsCard'` shows the card
  removed at this exact call site in `85809ff`, deliberately and five sites wide — *"macOS never drew
  one, so the rows now read the same on both platforms."* So the flag, the padding, the doc sentence and
  both tests were residue.
  **The padding was not inert residue.** Both hosts already inset the list 14pt, so compact drew its
  groups at 26 while the page header, options bar, rollover banner and past-due cards — siblings in the
  same `VStack` — stayed at 14. **Visible change on iPhone Today:** group headers and rows move 12pt left
  onto the same gutter as everything above them.
  The old test pair pinned `drawsCard` and `cardPadding` *to each other*, which is exactly why it
  survived the card's deletion — including the one whose own doc forbids "an inset with no fill behind
  it". Replaced by a memberwise-init equality pin, so a new per-layout field now fails to **compile**.

- [T-588] **CLOSED 2026-08-31 (`816329f`).** The row reads `iOSCalendarTimelineMetrics` for hour
  height, label size and trailing inset. **8 won over 9** because it is the value with a measurement
  behind it (`theHourLabelFitsTheNarrowRail`) and the one the Calendar rail already draws at both
  widths — taking 9 would have moved the surface that measured to match the surface that did not.
  **Extra finding:** all three literals sat behind a `rowHeight > 50` ramp with an unreachable lower
  branch — the same dead compact ramp this file's own header records deleting from `rowHeight` itself,
  still live three lines down. Collapsed with them.

- [T-590] **CLOSED 2026-08-31 (`0da8318`).** Line numbers had moved exactly as warned. **The sweep
  found a second instance the ticket did not list** — the same `title.isEmpty ? "task"` in
  `iOSCalendarTimelineViews`' clear-time control. Both now read `TaskTitleSupport.displayTitle`, and
  the app-wide rule is pinned: no accessibility label may spell its own empty-title fallback. Note both
  take the full "Untitled Task" where the block beside them draws compact "Untitled" — that spelling's
  stated reason is "a row with no width for the noun", **and a spoken label has no width.**

- [T-594] **CLOSED 2026-08-31 (`7aa7de9`).** All six named. Three value chips take
  `.accessibilityLabel` + `.accessibilityValue` (so "Do date, Tomorrow", not a bare "Tomorrow"); the
  container badge is named on the shared `ContainerPickerBadge`, so the composer and inspector
  breadcrumb inherit it; the completion circle keys on
  `CadenceTaskCompletionState.accessibilityActionLabel`, whose five branches mirror `handleTap()`
  — **mid-fill a second tap cancels, so a state reading would have been wrong.**
  **Sweep widened from one file to the app: 44 unnamed-tooltip sites in 28 files remain**, recorded as
  an exact per-file ledger so a new one fails *and* a stale entry fails. Split out as [[T-610]]; the
  iOS twin is [[T-611]].
  **A collateral run caught a real break** the scoped run would not have: `CadenceTodayUnificationTests`
  pins `TasksPanelComponents.swift` at exactly one `estimateLabel` call site and the new
  `.accessibilityValue` made it two. Fixed by having the chip read one property for both, **not** by
  raising the pinned number.


- [T-577] **CLOSED 2026-08-31 (`aac3679`).** Both gaps fixed. Titles now read
  `CadenceTitleNormalization.display(_:fallback:)` — **stronger than iOS's `.isEmpty` check**, which let
  a whitespace-only name through.
  **One judgement worth recording:** copying iOS's `"No parent list"` literally would have put a second
  inline copy in the repo — 2 sites in 2 files, exactly the threshold `CadenceSharedConstantReuseSweepTests`
  and [[T-505]] say must be declared. *The fix for a drift would have committed the defect that sweep
  exists to catch.* It is now `CadenceListSettingsCopy.parentSubtitle`, declared once and registered
  with the sweep so a third surface arms it.

- [T-578] **CLOSED 2026-08-31 (`dfce44a`).** Heading dropped rather than renamed — `iOSSettingsPageHeader`
  sits directly above it in both layouts and already reads "Notifications", so this matches macOS's
  `title: nil` exactly and does not read as orphaned.
  **Consequence caught in passing:** `theSettingsCopyScanReadsLiteralsRatherThanBlankingThem` used that
  exact heading as its **non-vacuity witness for the whole suite** — deleting it would have made every
  literal assertion in that suite silently vacuous. The witness moved to `"bell.fill"` with the reason
  recorded.

- [T-582] **CLOSED 2026-08-31 (`3a3538f`).** The Backups card now owns `backupStatusMessage`; the
  export-to-reset sharing is kept because that part was deliberate, and the doc comment asserting a
  pane-wide shared line was rewritten rather than left standing ([[T-565]]'s class).
  **The test asserts both directions on purpose** — no backup function reaches the shared line, *and*
  export/delete still do — because a one-directional assertion is satisfied by splitting the export
  pair too, which is the opposite fix.

- [T-570] **CLOSED 2026-08-31 (`9fa6ed7`).** Premise reproduced. **The ticket's caveat was real and the
  one-line fix would have been wrong.** Measured against the real window functions: Month never moves
  the selection with the grid (`keepSelectedDateInView` is gated on `isTimedGrid`), and a day carried
  from Aug 15 is inside the window at displayed months Jul/Aug/Sep but **outside** at Jun or Oct — so a
  bare `?? []` would have emptied a pane that has events in it. Fix is
  `visibleEventsByDate[selectedKey] ?? selectedDayEvents`, with a cached per-day fetch that runs only
  when the window cache lacks the day. **No EventKit query remains in `body`.** The timed grids
  provably cannot reach the fallback and that is now a test with a non-vacuity assert, not a claim.

- [T-571] **CLOSED 2026-08-31 (`a5aebd4`).** iOS changed to active-only, matching macOS. The reasoning
  is the ticket's open question answered: the count sits above the column's own list, that list is the
  active items, and finished work is behind the "Completed" toggle **which already carries its own
  count**. Summing them stated a total nothing on screen adds up to, counted the same task twice on a
  column showing both halves, and made a fully cleared day read as busy as an untouched one. It also
  matches every other board header in the app. iOS's `totalCount` had one reader and went with it.

- [T-586] **CLOSED 2026-08-31 (`f5bc288`).** The whole rail is `Theme.surface` — switcher strip and
  both halves — matching the task column across the divider, plus the `.ignoresSafeArea()` the schedule
  panel was missing.
  **Premise correction worth keeping:** the ticket blamed `iOSNotesView.swift:170`, but that line is not
  what you see — the notes header (`:265`) and sidebar (`:314`) each draw `Theme.surface` in front of
  it, so changing `:170` alone would have changed nothing on screen. That ruled out "move Notes to
  `Theme.bg`" as a scoped fix. `iOSNotesView` is a standalone page too, so the two rail-only views moved
  instead and it was left untouched.


- [T-585] **CLOSED 2026-08-31 (`d35470a`).** Premise reproduced, **plus one the ticket missed**: the
  day-end clamp (`lastStart`) was computed for 30 minutes too, so a 90-minute task could be offered
  23:30. New `ReadyScheduleContext` in `CadenceScheduleSupport` resolves the day once — one clock, one
  work window, one set of busy ranges — and each row derives its own start times from its own task's
  length.
  **On the once-per-pane tension the ticket flagged, the agent kept the half that is load-bearing and
  dropped the half that cannot be true.** "Every row offers the same times" is only honest while every
  task is the same length; with mixed lengths one answer for every row is wrong for all but one of
  them. The property that actually mattered — a filled slot leaves every row at once — comes from all
  rows reading the same live day, which the context carries. It also fixes a latent bug: per-row calls
  would each have taken their own `Date()`. An estimate-less task still resolves to 30 and its answer
  is bit-identical to before, pinned by `anEstimatelessTaskGetsTheSameSlotsTheOldSharedAnswerGave`.
  8 new tests; 3 mutations, each confirmed compiled.

- [T-589] **CLOSED 2026-08-31 (`35790d3`).** `quickCreateError` was cleared only by
  `selectQuickCreateStart` and `cancelQuickCreate` — both about the composer rather than the field — so
  the notice sat in red while you typed the title it was asking for. Now cleared on title change.
  **The `.onSubmit` half was deliberately NOT guarded, and the reasoning is in source.** The `+` button
  refuses *visibly* by greying out; Return has no such affordance, so guarding it would make the key do
  nothing at all — the inert-control-with-no-explanation failure T-470/T-471 went through this app
  removing. It would also have made "Add a title first." unreachable dead code. Return reports; the
  report now clears itself. `returnOnAnEmptyFieldStillReportsRatherThanDoingNothing` fails if someone
  later adds that guard. 3 new tests; 2 mutations, each confirmed compiled.


- [T-566] **CLOSED 2026-08-31 (`750be02`).** `updateBundle` now takes `commit:` and throws through
  `CadencePendingChangePersistence.commitEdit`; the Save button catches and alerts instead of
  dismissing, the shape the Delete button beside it has had since T-322. **The undo restores each
  member's `scheduledDate`/`scheduledStartMin`, not just the block's four fields** — moving a block
  moves its tasks, so a header-only undo would have left them on the day the store refused while the
  alert claimed nothing changed. That is the bug the obvious fix would have introduced.
  **Detector widened, and it re-scopes [[T-497]] from 2 sites to 4.** The new half indexes every
  declaration reaching a swallowed commit to a fixed point *across files*, keyed by callee name **and
  enclosing type**, then reports a success report in the same block. Two frames were required, not one:
  the button called `save()`, `save()` called `updateBundle`, and only the third frame held the `try?`.
  **Type-pairing was measured rather than assumed** — name-only resolution reports 17 sites where the
  paired rule reports 2, and one of the extras was read through and confirmed a genuine false positive.
  The 2 new sites are carried as exemptions with reasons.

- [T-567] **CLOSED 2026-08-31 (`5417b60`).** `canCreate` now requires a title for `.bundle`,
  spelled exactly as `.task` does, and the noun has one home: `TaskBundle.defaultDisplayTitle = "Block"`
  plus `storedTitle(_:)`, mirroring `CadenceEventTitleSupport`'s stored/display split (so a title of
  spaces no longer reaches the store either).
  **Premise correction: the ticket named 3 sites; there were 9 — and 3 of them *stored* the word
  rather than drawing it** (`SchedulingActions.createBundle`, `QuickCreateChoicePopover.create`,
  `TimelineBundleBlockSupportViews`'s `onSubmit`). A display-only fix would have left "Task Bundle" in
  the database. All 9 now read the constant or `bundle.displayTitle`.

- [T-569] **CLOSED 2026-08-31 (`f3d87e3`).** The four named sites now go through
  `TaskTitleSupport.displayTitle(_:fallback:)` with the compact fallback, so **the trim is the only
  thing that changed** — the copy stays "Untitled" rather than being promoted to `displayTitle`'s
  default "Untitled Task". Repo-wide remainder measured: **25 sites** still spell
  `title.isEmpty ? "..."` across `Cadence/`, `CadenceWidgets/` and `CadenceMCPServer/` (the ticket
  estimated ~20). Split out as [[T-609]].


- [T-574] **CLOSED 2026-08-31 (`54cc616`).** Premise reproduced exactly. `saveAPIKey` now throws
  `AISettingsError.emptyAPIKey` on an empty/whitespace draft instead of falling through to
  `removeAPIKey()`; macOS's Save button is additionally disabled and dimmed on a blank draft, matching
  what `iOSActionButton(isDisabled:)` already did. **Both halves were fixed deliberately** — a disabled
  button is not testable in isolation, and the credential loss lived in the manager, so fixing only the
  button would have left the hazard reachable from any other caller. `AIAPIKeySaveGuardTests` pins the
  stored key surviving `""`, `"   "` and `"\n\t "`, that `saveAPIKey`'s body never reaches the removal
  path, and that neither platform offers a live Save on a blank draft. Two mutations, three tests
  killed, each confirmed compiled.

- [T-575] **CLOSED 2026-08-31 (`e509ae2`).** macOS's one-click `confirmationDialog` replaced by
  `SettingsDataResetConfirmationSheet` behind `PrivacyDataResetConfirmation.authorizes` — **the shared
  gate now has two callers instead of one.** iOS untouched, so the guarded path was raised to meet the
  unguarded one rather than the reverse. The doc comment calling the split deliberate, and the matching
  sentence in `docs/app-review-notes.md`, were corrected rather than left asserting machinery the code
  no longer has — the exact defect class [[T-565]] exists to catch. `AppStoreReviewReadinessTests`' pin
  on "requires the word DELETE to be typed" still passes. One mutation, one test killed.

- [T-576] **CLOSED 2026-08-31 (`19fd461`).** Premise reproduced on **both** platforms. T-253's
  hook was **generalised rather than copied**: new `Cadence/Shared/CadenceAuthorizationLifecycle.swift`
  takes a refresh *closure* instead of a `RemindersManager`, because the two managers share no protocol
  and disagree on async-ness — but agree on *when*. That is the right seam. All four reminders call
  sites are unchanged; `notificationsAuthorizationLifecycle` is new on both platforms, so both panes now
  re-derive on appear **and** on foreground. Reminders file keeps a tombstone. Two mutations, three
  tests killed.

- [T-591] **CLOSED 2026-08-31 (`1f53aa8`).** Compound key now split on
  `CadenceTaskDropSupport.separator` and applied part by part; the parse extracted as the pure
  `TasksPanelSupport.dropAssignments(forDropKey:)`, testable with no `ModelContext`. **The half that
  mattered more:** `assignTask` reports whether anything resolved and `handleSectionDrop` returns it,
  so an unresolvable key now bounces the row instead of swallowing it. `handleTaskDrop` still returns
  `true` deliberately (the reorder ran either way) and says so. 8 tests; two mutations, **both
  confirmed compiled** — restoring the parse bug killed 6, restoring the unconditional `true` killed
  exactly 1, which is the attribution that matters: the silent-accept guard has its own test,
  independent of the parse. Follow-on filed as [[T-607]].

- [T-592] **CLOSED 2026-08-31 (`c39ff74`).** `isEmptyState` now also requires both past-due
  summary arrays empty, matching `iOSTodayTaskSections`, with iOS's reasoning carried into a comment.
  Mutation killed `theMacTodayIsNotEmptyWhileAPastDueCardIsOnScreen` alone; the test also asserts a
  genuinely empty day still reports empty, so the guard cannot be satisfied by never returning `true`.
  **One thing the ticket did not have:** macOS needs no rollover-notice clause, unlike iOS's guard —
  the banner's rows are `overdoTasks`, which `isEmptyState` already counted. The agent recorded that in
  the comment rather than copying a clause that would be dead here.

- [T-593] **CLOSED 2026-08-31 (`7dea6b5`).** All three sites — rows, Completed rows and the
  drop indicator — now read `TaskListDisplayMetrics.taskTrailingInset`, the sibling's own constant
  rather than a restated `12`. Leading stays 16, extracted as `todayRowLeadingInset` with a comment on
  why it differs from the shared 52. **Build-verified only, not looked at** — no test pins it and the
  app was not launched. Convergence proposed as [[T-608]], deliberately not done.


- [T-352] **CLOSED 2026-08-31 (`5ae916a`).** Premise confirmed and then *inverted*: no persistence was
  added, per the user's decision, because the defect was never a missing feature — it was a comment in
  `macOSRootSupportViews.swift` asserting a launch-restore mechanism that has never existed.
  `@SceneStorage` appears in **zero** of the 300+ files under `Cadence/`. Comment rewritten with a
  tombstone naming the claim it replaced. `CadenceRootSelectionLaunchContractTests` (3 tests) now pins
  both the code contract (the wrapper is read off the `selection` declaration by regex, so a *new*
  persisted `*selection*` property also fails) and the prose contract. Non-vacuity proven by two
  mutations that were **confirmed to compile** before their kills were believed.

- [T-487] **CLOSED 2026-08-31 (`53e223c`).** `.byDoDate` deleted along with every branch, helper, view
  and derived value that existed only to serve it: 4 section builders, 6 flat-section helpers, the
  frozen list/flat snapshot chain, 4 orphaned views, the grouping control, and
  `byDoDateBase{Tasks,SortedTasks}` — which were computed **unconditionally**, so every Today render
  filtered every task and fully sorted the result for a mode nothing could reach. Net -711/+151.
  Tests were retargeted rather than dropped. The first full run surfaced **2 genuine regressions**,
  which is evidence the source scans were reading this change rather than passing through it — one of
  them found a needle pinning two call sites as "two that must agree" where the second was inside a
  function whose own doc said *"Currently unreferenced"*. Green at 3719 tests, 0 warnings.
  **Deliberately not done, now [[T-564]]:** `TasksPanelMode` is single-case and was NOT collapsed, and
  `TasksPanelDropCoordinator.taskDropHandler` was left unreferenced rather than half a currying pair
  removed. Both are design changes the user has not seen.

- [T-556] **CLOSED 2026-08-31 (`3eb8237`).** Suite renamed to `CadenceControlAccessibilityLabelTests`
  to match its file. All four repo-wide mentions of the old name were checked and **none was an
  invocation**. The T-552 hazard was *demonstrated rather than asserted*: against one build, the old
  suite name ran **0 tests and xcodebuild called that a success**, while `xcb.sh`'s guard refused it
  with exit 4; the new name ran 12.

Moved to [`TODO_DONE.md`](TODO_DONE.md) on 2026-08-26 — 220 entries, with their reasoning and shipping SHAs intact.
The working list was ~82k tokens and two thirds of it was finished work. **Search the archive
before filing**: this list has had the same ticket re-reported more than once.

- [T-161] **Tests pin helpers, not wiring.** The T-149 verifier proved by mutation that reverting the
  `macOSRootCommandActionSupport` fix leaves all 1692 tests green, and the same holds for T-150 —
  nothing observes that `MarkdownEditorView` calls the shared functions. `D-113` closed this for the
  markdown indent formula by testing that the stylist *reads the shared metrics*, not merely that the
  numbers are right. Worth applying that pattern to the two search fixes, and treating it as the
  default shape for consolidation work: a test that passes when the call site is reverted has not
  pinned the consolidation.

  **Survey, 2026-08-25, against `6e1f1e0`.** Measured rather than estimated, because nobody had:
  **2,514 `@Test` functions, of which 154 read a `.swift` file as text**, spread over **32 of 189**
  test files. Of those 154, **73 assert nothing but that some text exists** and 81 also assert at
  least one value produced by a real call. So the source-scan population is ~6% of the suite — small
  — and it is concentrated where the risk is: iOS surfaces the macOS target cannot compile, plus a
  tail of macOS files where a value *was* available and nobody reached for it. The script is
  reproducible from the classification described here; it strips comments and masks string literals
  before matching, because `func select(` inside a needle literal otherwise reads as a declaration.

  **Partly shipped in `902b386`: three fixed, each with the blindness proved first** (pre-fix
  mutation → all green, post-fix same mutation → red, both at 0 compile errors). Six more
  whole-file needle counts, listed below, were recorded as remaining rather than fixed — this
  ticket stays open for those:
  - *macOS's settings rail was pinned one case at a time.* `SettingsCategoryGroup` was `private`, so
    `theSyncCategoryIsFiledInTheMacOSRail` and `theAboutCategoryIsFiledInTheRailAndRoutedToItsSection`
    each found `static let all: [SettingsCategoryGroup]` in the source text, sliced to the next
    `\n}`, and asked whether the slice contained `".sync"` / `".about"`. Deleting `.notifications`
    from the Connections group — Settings → Notifications unreachable on macOS — passed. The struct
    is `internal` now and `theRailFilesEverySharedCategoryExactlyOnce` states the general rule.
  - *Both edit sheets' wind-down was two whole-file counts.* `macOSStillWindsDownOnArchiveAndOnCompletion`
    asserted `cancelRemainingActiveTasks(` == 2 and `completeRemainingActiveTasks(` == 2 in
    `EditListSheet.swift`. **Swapping them** — archiving a list marks its leftovers *done*, completing
    one cancels them — leaves both counts at 2 and passed. The branch is a value now
    (`ListEditorLifecycleChoice.windDownOutcome`) over a new
    `TaskContainerLifecycleService.settleRemainingActiveTasks(…outcome:)`, and the surviving scan is
    scoped to `apply(_:)`'s brace-matched body instead of the file.
  - *T-240, closed in `902b386` — see Done.*

  **`cadenceFunctionBody(_:in:)` is now the one brace matcher in `CadenceTests`** — `cfa3b3b`'s
  `focusFunctionBody`, promoted to `internal` and renamed, read by `FocusPickerPlayControlTests`,
  `AppStoreReviewReadinessTests` and `CadenceListWindDownSurfaceTests`. Anything else scoping a scan
  to one function calls it rather than writing a second.

  **Second pass, 2026-08-26 against `36be8ba`: four of the six done, each proved by mutation**
  (apply → red on exactly the intended test, restore → green; 0 compile errors on every run, and
  for each one the *old* whole-file needle was grepped in the mutated file and found still present,
  which is the blindness proof stated mechanically rather than by re-running a deleted assertion).
  - *The two inspector-host suites.* The repo-wide dictionaries are kept — they are the right shape
    for "exactly N places in the whole app" — and the per-file half is now placement.
    `theHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule` (and its bundle twin) pin the panel to
    the `.stay` arm of `CadenceDetailPanelPresentation.resolveHeldSubject`; **swapping the `.stay`
    and `.close` arms** leaves `iOSTaskDetailSheet(` at one occurrence in one file, every old
    assertion green, and every row in the app opening nothing.
    `theRootAppliesTheHostAboveBothShellsRatherThanInsideOne` (and its bundle twin) slice
    `iOSRootView`'s `Group` and require the host, the bundle host and the startup banner to be
    applied *to* it, not inside it; **moving `.iOSTaskInspectorHost()` into the
    `horizontalSizeClass == .regular` branch** — iPad keeps the inspector, the iPhone's four tabs
    get dead taps — keeps the file count at exactly 1.
    `theNestedHostSitsOnTheSheetThatCarriesAWholePageOfRows` scopes the nested host to
    `iOSTodayOverdueListSheet`'s **`var body`**, and the reason is a measured one: the first draft
    scoped it to the *struct* and survived a mutation that moved the modifier onto a second computed
    property in the same struct. Struct-level was not enough; `var body` is.
  - *`CadenceTodayOverdueSummarySurfaceTests.theMacCardsHopTheNavigationManagerThroughTheSharedRequest`
    is behavioural now.* macOS's half is compiled by this target and nobody had reached for it: the
    test drives `TasksPanelSupport.openOverdueListSummary` / `openOverdueSectionSummary` against
    `ListNavigationManager.shared` and reads the request it is left holding. Two mutations that the
    old scan could not see: **swapping the `.area` and `.project` arms** of the private
    `open(_:listNavigationManager:)`, and **dropping `sectionName:`** from both hops so the board
    lands on whatever column it last showed. The one whole-file assertion kept is the *absence*
    (`if let projectID = summary.projectID`), which is the claim a scan states better than a call.
  - *`CadenceTodayRolloverSurfaceTests.theMacSpellingDelegatesToTheSharedMutation` is scoped and
    stated as an equality.* `cadenceFunctionBody` slices `SchedulingActions.rollOverTaskToToday` and
    the whole trimmed body must equal the one delegating call, so **any** added statement fails —
    proved with `task.scheduledStartMin = -1` appended under the delegation, which the old
    `contains(…)` cannot see.
  - *`55d696b`'s owed evidence is paid.* Forcing `CadenceTaskGroupHeadingMetrics.showsCapsule` to
    `true` fails `CadenceInboxRemindersSurfaceTests.onlyAnUnknownCountSuppressesTheCapsule`, exit 65
    at 0 compile errors. The behavioural test was load-bearing all along.

  **Still open, and the list is shorter than it was for one reason worth reading.**
  - `CadenceKanbanColumnLifecycleSurfaceTests.bothVisibleCompletionControlsSitInsideTheLifecycleGate`
    and `theKeyboardRouteAndTheConvergencePointBothRefuseDefault`. Both already assert *structure*
    with brace-adjacent regexes; what is unscoped is the pair of
    `section.supportsLifecycle` == 2 counts beside them. Not attempted here.
  - `CadenceListDetailTabStripMarginTests.theResetIsTheStripsAloneAndTheHostCompensatesForNothing`.
    Not attempted. Note while you are in the file: it declares a **second** declaration slicer
    (`declaration(named:in:)`, which slices to the next `\nstruct` rather than brace-matching), and
    `CadencePageHeaderMetricsTests` / `CadenceTodayUnificationTests` declare a **third** between
    them (`declarationBody(of:in:)`, twice, byte-identical). Three private near-copies of the thing
    `cadenceFunctionBody(_:in:)` was promoted to be.
  - `CadenceSharedBoardChromeTests.bothBoardsDrawTheSharedMetadataChip`. Not attempted.
  - `CadenceSharedTaskRowJobsTests.theRowsAnimatedPartsAreStillExtractedIntoTheirOwnSubViews` was
    **rewritten but is the one place a mutation did not survive on its own merits**, and that is the
    finding rather than the fix. It now asks each declaration for its own count —
    `TaskCompletionButton` 1, `TaskRowBackground` 1, `MacTaskRow` 0, `MacTaskRowEstimateChip` 0 —
    over `cadenceFunctionBody`, with the whole-file 2 kept as a no-fifth-reader guard. The mutation
    (the row observes the manager and hands it down to `TaskRowBackground` as a `let`) does turn it
    red, but it turns `CadenceTodayUnificationTests.theTaskRowStillDoesNotObserveTheCompletionAnimationManager`
    red too — that test has scoped `MacTaskRow` and `MacTaskRowEstimateChip` to their declaration
    bodies all along, so the bullet's stated gap ("cannot tell the two extracted sub-views from
    `MacTaskRow` growing one of its own") was already closed by a neighbour nobody had checked.
    The residue the new assertion adds — *both* observations in one sub-view and none in the other —
    could not be mutated into existence in code that compiles, because a view that uses `manager`
    has to obtain it and the only non-observing route needs a holder that is itself forbidden from
    observing. Recorded as unprovable rather than claimed as proved.
  **Closed 2026-08-29. `CadenceScanInstrument` validates a detector against a positive **and** a negative fixture in its *initializer*, so a blinded detector cannot reach a sweep; `sweep`'s `atLeast:`/`including:` are non-defaulted, so omitting the non-vacuity assertion is a compile error. Evidence: the same blinding mutation, both at 0 strict compile errors, left the bare-predicate sweep green and made the instrument-backed sweep fail with `does not fire on its own positive witness`. Also scanned the test target against itself: 13 shared names across 46 declarations -> 0 duplicates across 3,394 tests. The wrong-`struct` trap is not closed mechanically -- see [[T-465]].**

- [T-367] **Global Cmd+Z on the model context is either a feature or a hazard, and nothing says
  which.** P3, source measured, runtime behaviour not measured. The macOS root installs an
  `UndoManager` on the shared `ModelContext` and routes non-text Cmd+Z/Cmd+Shift+Z into it, while
  destructive copy elsewhere tells the user "This cannot be undone." Editor undo is correctly scoped
  to the text view. **Decide:** if global model undo is real, pin what it may undo; if not, remove
  the root fallback. Do not leave it undecided — the current state means neither the code nor the
  copy can be trusted.
  **Closed 2026-08-29 **as a removal, not a fix.** `modelContext.undoManager = UndoManager()` is gone from `macOSRootLifecycleSupport.handleAppear` and `case 6:` is gone from the Cmd-key table, so Cmd+Z falls through to `default: return event` and `NSTextView` keeps its own undo. Reasons: one shared `ModelContext` across every surface; destructive paths pair store writes with effects (EventKit, notifications, file removal) that no undo stack saw; the "This cannot be undone" copy already contradicted it. A headless measurement -- recorded as a bound, not as the app's behaviour, since there is no run loop -- had `canUndo` true while `undo()` left a deleted row deleted and removed an edited row rather than restoring its title.**

- [T-414] **`subGoalCount` and `habitCount` have the same naming defect [[T-388]] just fixed.**
  They report own-only numbers under names that read like totals. Left alone deliberately so the
  breaking wire change stayed one rename rather than three — but the DTO is now half-renamed, and a
  half-applied convention is worse than either end state. Close it before it ossifies.
  **Closed 2026-08-29. `subGoalCount`/`habitCount` -> `ownSubGoalCount`/`ownHabitCount`, matching [[T-388]]; arithmetic untouched. Wire-key test pins all four new keys present and all four old keys absent. Breaking bump 0.5.0 -> 0.6.0.**

- [T-415] **The MCP page slice still happens in memory.** From [[T-384]]: `taskSort` and
  `CadenceMCPOrdering` both end on `id.uuidString`, `UUID` is not `Comparable`, and `isDone` is
  computed — so `offset`/`limit` cannot be pushed into the store's sort descriptor and the rows are
  still materialised before being sliced. Reads are far narrower now, but the last hop is unchanged.
  **Closed 2026-08-29 as **a documented limit, not a fix** -- see `[X-09]` in the Cancelled section. The ticket's stated reason was wrong (`UUID` *is* `Comparable`), but three real blockers stand.**

- [T-433] **`CadenceListDeletionSummary` says its counts "mirror
  `ModelContext.deleteArea/deleteProject/deleteContext` exactly" and omits the image sweep all
  three of them run.** Found while fixing [[T-423]], which was the same defect one summary over.
  The struct counts tasks, notes, links, projects, areas, goals and habits; it has no `images`
  field at all, while every cascade it mirrors ends in `deleteUnreferencedMarkdownImageAssets`. So
  deleting an area holding twenty image-bearing notes destroys those `.externalStorage` bytes with
  the confirmation saying nothing about them — and the note confirmation beside it *does* say
  "N embedded images", so the two disagree about whether images are worth mentioning.
  The arithmetic is now available: `CadenceNoteDeletionSummary.forNote` reads it through
  `CadenceMarkdownSourceInventory.liveMarkdownTexts(in:excludingNoteIDs:)`, and the list version is
  the same call with every doomed note's id in the exclusion set. Two things to settle first,
  though, which is why this is filed rather than done: the list summaries are computed from model
  objects with **no `ModelContext` parameter** (`forArea(_:)`, `forProject(_:)`, `forContext(_:)`),
  so the signature has to change the way `forNote` already has; and the cascade counts are exact
  today, so adding a count that can be a floor means porting `hasUnknownImpact` across too, or the
  new number silently breaks the "may not over-promise" rule the whole file is built on.
  Fix the doc comment's "exactly" in the same pass either way.
  **Closed 2026-08-29. `CadenceListDeletionSummary` gains `images` and `hasUnknownImpact`; `forArea/forProject/forContext` now take `in modelContext:`; the doc comment's "exactly" is retired. The amber unknown-impact row is now one shared `iOSDeleteUnknownImpactRow` across both sheets.**

- [T-445] **`DataIntegrityRepairReport` is a synthesized `Codable`, so adding a counter makes the
  stored report undecodable.** Synthesized decoding does not apply property defaults for missing
  keys, so `lastReport.v1` written before a new field cannot be read after. `lastReport()` swallows
  it with `try?`, so nothing breaks — but the diagnostic is lost, and `repairAndRecordFailure`
  returns `nil` on exactly the launch that meant to hand back the last good report. **Second
  occurrence** — T-359 added the first counter, T-428 the second. One `init(from:)` using
  `decodeIfPresent` closes it. Not data loss; no user data lives in that key.
  **Closed 2026-08-29. `nonisolated extension DataIntegrityRepairReport { init(from:) }` with `decodeIfPresent(...) ?? 0` per counter; the four head fields stay `decode`. An extension rather than the struct body, so the memberwise init survives. `nonisolated` matters: the first spelling warned that the `Decodable` conformance crossed into main-actor code -- invisible to the MCP scheme, the one target without `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.**

- [T-287] **The `~` list-search panel is implemented twice on macOS.** From the [[T-123]] split.
  `CLAUDE.md` already records this as "a standing violation of the 'one shared component over
  near-copies' rule, recorded here so it is not mistaken for a deliberate split" — and it has never
  been a ticket, so it has stayed standing. `macOS/Views/QuickCreateChoicePopover.swift` carries
  `tildeFlatContainers` (288), `selectTildeContainer` (318), `selectTildeContainerItem` (324),
  `clampTildeHighlight` (416) and its own `TildeContainerItem`; `macOS/Views/TaskTitleEntryField.swift`
  carries the same five under the same names plus `TaskTitleTildeContainerItem`. They share
  `TildeContainerPickerRow` and nothing else — including the silent `normalizeSelectedSection()`
  that both must perform after a container change, which is the half most likely to be fixed in one
  copy only.
  Done: one panel — the container list, the highlight arithmetic, the selection and the section
  normalisation — read by both the title field and the drag-create popover, one item type, and a
  test that fails if either file re-declares `tildeFlatContainers`.
  **Closed 2026-08-29. The two copies had diverged and the difference was a **bug, not a distinction**: `TaskTitleEntryField` restored the literal `~query` on Escape and on backspace-at-empty, and `QuickCreateChoicePopover` had neither, so the only way out of the drag-create panel was to pick a list -- Escape fell through to the enclosing popover and discarded the draft. `TildeContainerPicker` is one panel, one item type, one `applySelection` carrying the section renormalisation, replacing ~400 lines across two hosts and following the `TaskTitleInlineTagPicker` precedent [[T-123]] set for `#` and never applied to `~`. A third open-coded `normalizeSelectedSection` in `CreateTaskSheet` went with it.**

- [T-372a] **`CadenceSearchMatcher.rank` is the one ordering left partial after [[T-372]].** Found
  while fixing T-372 and deliberately not fixed there: `rank` ends at score-then-title
  (`Shared/CadenceSearchMatcher.swift` lines 27-30), so two hits with the same score and the same
  title — two tasks called "Admin" in two contexts, a duplicated saved link — come back in fetch
  order. It is the *shared* matcher, so the MCP `search()` tool and the macOS/iOS search surfaces
  all inherit it, and closing it means threading an identity closure through every `rank` call
  site rather than the one-file change T-372 was. Scoped out to keep the MCP fix reviewable; the
  fix shape is the same `id` tail `CadenceMCPOrdering.precedes` now uses.
  **Closed 2026-08-29. The ticket was one revision stale: T-372 had already added the `identity` leg, but as an **optional** parameter that neither remaining caller passed, so `search_cadence` and `Cmd+K` both still stopped at title. `identity` is non-optional on both overloads now -- an optional tie-break is one the next call site silently declines. MCP ties on `entityType:entityId` (eleven scope loops over eight tables, so the type has to be in it); macOS on the category-prefixed result id. The pre-existing tie-break test **could not see a score/title swap** -- its fixture agreed on both tiers -- so the new one uses a fixture where every pair disagrees on exactly one tier while the tiers below point the other way.**

- [T-442] **The macOS note-template editor is a bare `TextEditor` while iOS gets the full markdown
  surface.** An unrecorded parity gap, and the reason T-421's fix is iOS-only: macOS never had an
  image door to close.
  **Closed 2026-08-29. `SettingsTemplatesSection`'s Body field is `MarkdownEditor(allowsImageInsertion: false)` rather than a `TextEditor` -- macOS's own shared surface, not a port of the iOS view, whose format toolbar and photos picker are phone chrome. **One flag reaches all four macOS image doors where iOS needed three guards**, because the panel, paste and drop all funnel through `onCreateMarkdownImages`. The `/image` refusal became `MarkdownSlashCommand.refusingImageInsertion`, now read by both platforms instead of open-coded twice ([[T-374]]). Also answered the inventory question: the template body **cannot** be a `CadenceMarkdownSourceInventory` case -- all seven cases are stored `String`s on `CadenceSchema` models reached by a `ModelContext` fetch, and a template body is JSON in `UserDefaults`. That is now a value assertion rather than prose.**

- [T-451] **`CadenceNotesListSupport` re-types the eyebrow's `0.8` as a literal.** Residue from
  [[T-284]]. The notes group header (`.kerning(0.8)`, line ~656) is *not* an eyebrow — it is bold,
  sentence-case, `Theme.text`, at 11/12pt — so folding it into `SectionEyebrowLabel` would be the
  size-decision-dressed-as-a-refactor that ticket refused twice. But 0.8 is the standard tier's own
  number, hand-typed, and it is now the only copy of it left outside `Theme`-adjacent metrics.
  Decide whether that header's tracking is its own decision (and say so beside it) or the eyebrow's.
  **Closed 2026-08-29. The heading reads `SectionEyebrowLabel.Size.standard.kerning`. It takes the tier's **setting**, not `kerningRatio x headerLabelSize`: the ratio was derived over 10/9pt uppercase runs and this heading is bold sentence-case at 11/12pt, so re-deriving would silently retrack it to 0.88/0.96 with nobody having looked -- the un-inspected change [[T-452]] is already open for. Value-preserving. The ticket's "only copy left" was off by one; see [[T-476]].**

- [T-463] **`CadenceTests/CadenceCalendarLinkHealthTests.swift` was a directory containing a file of
  the same name.** A staging error of mine, now flattened. It compiled and ran — the synchronized
  root group descends into it — which is why nothing caught it. Worth a guard: a `.swift` path that
  is a directory should fail the build, not quietly work.
  **Closed 2026-08-29. Already flattened by `193f257`; verified at HEAD as a plain file, no directory-shaped `.swift` anywhere, and `project.pbxproj` never referenced the path. Two pieces of residue closed it out: the doc comment on `cadenceRepoSwiftFiles(under:)` still asserted in the present tense that the directory exists, and the guard the ticket actually asked for did not exist -- every walk skipped the shape *silently*, which is how the original survived a whole session. `noSwiftPathInTheRepositoryIsADirectory` now reports it across 688 files in five source roots.**

- [T-464] **The list-editor row can now say "(Hidden)" but the picker still offers only visible
  calendars.** From [[T-441]]. So the row names the problem and the repair is in Settings. Putting
  hidden calendars in the picker is a second decision, left deliberately.
  **Closed 2026-08-29. [[T-441]] taught the row four verdicts but left the popover over `availableCalendars`, so the row could say "Team (Hidden)" over a menu with no Team in it and the only reachable move was "None" -- the silent overwrite T-441 exists to prevent, performed by the user instead of the code. The offer is now visible-plus-the-linked-one: exactly one hidden calendar can appear, and only because it is already stored, so no new hidden link can be made here. `CadenceCalendarLink` holds the three inputs once and answers both `rowState` and `pickableCalendars`, and `hiddenTitle(_:)` is the one spelling of "(Hidden)", so the two surfaces cannot form separate opinions or word it differently.**

- [T-465] **A test can be declared in the wrong `struct` and no assertion can catch it.** This is the
  one shape [[T-161]] did **not** close mechanically: a test that belongs to the calendar suite but
  is declared inside the deletion suite compiles, runs, and passes. Nothing can compare a test's
  location against its author's intent. `scripts/test-suite-index.sh` prints suite -> test names for
  review; the ask here is a periodic read of that output, not a guard. Filed rather than solved so the
  gap is written down instead of assumed closed by T-161.
  **Closed 2026-08-29 -- one arm mechanically, the other explicitly refused. **Closable:** a `@Test` past the last suite's closing brace is a free function, invisible to `-only-testing:`, so every mutation against it reads as a survivor -- and both `cadenceTestDeclarations` and `scripts/test-suite-index.sh` attributed it to the suite it had just escaped. Attribution is by suite **extent** now, held at zero by `noTestInTheTargetIsDeclaredOutsideEverySuite` through a `CadenceScanInstrument` sweep, no allowlist. **Not closable:** a test in the wrong *sibling* suite. Measured before deciding, so nobody re-derives it -- the best heuristic flags 13 tests on a clean target, all 13 hand-read as correctly placed, and catches 43.3% of 1,643 simulated misplacements (47.5% missed, 9.2% undecidable). Zero precision at under half recall is not a guard. That arm stays a periodic read of `scripts/test-suite-index.sh`. Known false-positive shape for the guard that did ship: `extension SomeSuite { @Test ... }`, of which the target has none -- widen the regex rather than allowlist a file.**

- [T-466] **`NoteMigrationReport` is [[T-445]] untouched.** Same synthesized-`Codable` shape: adding a
  counter makes every previously stored report fail to decode, so the history silently empties. T-445
  fixed `DataIntegrityRepairReport` with a `nonisolated extension` and `decodeIfPresent(...) ?? 0` per
  counter, plus a test that removes each key in turn. Apply the identical treatment here. Note the
  actor-isolation trap T-445 hit: the naive spelling warns only under
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which the MCP scheme does not set, so an MCP-only build
  reports zero warnings on broken code.
  **Closed 2026-08-29. `nonisolated extension NoteMigrationReport { init(from:) }` with `decodeIfPresent(...) ?? 0` for all fourteen counters; the four head fields stay `decode`. Impact was wider than the app: `CadenceMCPToolDefinitions.diagnostics` defaults `noteMigrationReport:` to `NoteMigrationService.lastReport()`, so an MCP client read *never migrated* instead of *unreadable*. The `nonisolated` trap was reproduced, not assumed -- dropping it warns that the `Decodable` conformance crosses into main-actor code, at 0 errors.**

- [T-482] **Free-function `@Test` was misattributed by both [[T-161]] parsers.**
  **Closed 2026-08-29, fixed as a prerequisite of [[T-465]].** `cadenceTestDeclarations` and
  `scripts/test-suite-index.sh` both used "nearest top-level type declared above", so a `@Test` outside
  every suite was reported as a member of the preceding suite — the index built to answer *"where did my
  test actually land?"* gave a confidently wrong answer for the single case it exists to catch, and
  `<file scope>` was unreachable in practice. **Did not affect**
  `everyTestFunctionNameInTheTargetIsUniqueAcrossSuites` (name uniqueness does not depend on suite
  attribution), and the target had zero such tests — a latent hole, not an active miss.

- [T-483] **`CadenceSourceScan.codeOnly` read a raw string's trailing backslash as an escape.**
  **Closed 2026-08-29, fixed as a prerequisite of [[T-465]].** On `#"photo\"#` the masker skipped the
  closing quote, ran to end of line and blanked live code — including the `{` opening the enclosing
  `for` body. Brace depth in `CadenceTests/MarkdownImageAssetServiceTests.swift` came out one short,
  which is why T-465's new guard first produced 11 false accusations. 45 test files use raw strings;
  exactly 1 desynced, because the desync needs a backslash immediately before the closing quote.
  **Did not affect** needle-counting scans, which is every existing scan — no shipped assertion changed
  verdict, and `scripts/test-suite-index.sh` output after both fixes is byte-identical to HEAD's.

- [T-435] **The target-membership guard matches capitalised identifiers, so a top-level `func` still
  slips through.** From [[T-409]]. It catches a type referenced across a target boundary, which is
  the shape `aaa0064` had, but a free function or an extension method declared in a non-member file
  is invisible to it. The honest close is building `-scheme CadenceMCPServer` in CI; the test is the
  cheap half.
  **Closed 2026-08-30. The hole was wider than filed: the declaration side matched only types and the reference side only capitalised identifiers, so a call like `monthStart(for:calendar:)` produces **no capitalised token at all** — the sweep read the line and saw nothing. The repo has 16 top-level `func`s, 14 non-private, none in either explicit-list target: every one invisible. Blindness proved directly rather than asserted — the same compiling mutation (an MCP file calling a free function it cannot compile) passes HEAD's guard at `EXIT=0`/0 errors and kills the widened one at `EXIT=65`/0 errors, naming the offending path. Driven through `CadenceScanInstrument` with a real unreachable free function as the positive witness. **Still open:** the ticket's own "honest close", building `-scheme CadenceMCPServer` in CI. Extension methods remain uncovered — see [[T-486]].**

- [T-436] **Two membership guards overlap and neither is redundant — say so before someone deletes
  one.** T-406's pins one symbol's build-phase membership *and* that the trim rule is spelled exactly
  once; T-409's covers every symbol across both explicit-list targets but does not check spelling
  counts. The widget half of T-409's guard is also a coverage demonstration rather than a kill: a
  real widget membership violation is a compile error under `-scheme Cadence`, so no compiling
  mutation can make that assertion fire.
  **Closed 2026-08-30 as documentation, both guards kept. They ask different *questions*, not different scopes: [[T-409]]'s asks reachability over the whole graph, [[T-406]]'s asks singularity and placement. Counting is outside T-409's vocabulary — a second declaration in a non-member file leaves the type reachable, so that sweep stays silent by design. Measured: re-forking the trim kills only `theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles` while all 6 membership tests and the behavioural trim pin stay green (two correct copies of a trim agree on every sample). Also recorded: `-scheme Cadence` builds `CadenceWidgets`, so a real widget violation is a compile failure before any test runs — that half is coverage, not a kill.**

- [T-469] **The iOS empty list detail names a control that is not on the screen** (Codex, P3, measured).
  `iOS/iOSListDetailView.swift:260` says "Add a task above or move one here from Inbox." There is no
  inline field above; the page uses the floating `+`. This repo has already made and fixed this exact
  mistake — `CadenceTodayPresentationSupport.emptySubtitle` says "Add a task with +..." and its comment
  records the retired "Add a task above" wording as the failure. Copy naming a control that does not
  exist is worse than no subtitle, and this is a *first* empty list. Fix the wording, consider one
  shared list-detail empty-state constant if the two surfaces should stay pinned, and add a source scan
  for the retired phrase.
  **Closed 2026-08-30. Same shared constants as [[T-473]]. The title deliberately avoids "yet" so it does not contain the retired "No tasks yet" as a substring.**

- [T-470] **iOS calendar quick-create swallows task-save failures and the button looks inert** (Codex,
  P2, measured). `iOS/iOSCalendarQuickCreateSheet.swift:542` guards on
  `try? CadenceTaskMutationSupport.insertScheduledTask(...)` and just returns, never writing the
  visible `actionError` notice — while the *same sheet* has a working red `actionErrorNotice` that its
  Event branch uses correctly (`:312`). The right pattern is already in
  `iOSCreateTaskSheet.create()`: catch, set `actionError = TaskCreationService.saveFailureNotice`,
  return before dismissing. Instance of [[T-322]]. Extend `CadenceCreateTaskCommitSurfaceTests` to
  cover this file.
  **Closed 2026-08-30. `createTask()` uses `do`/`catch` in the shape of `iOSCreateTaskSheet.create()`: a refused insert sets `actionError = TaskCreationService.saveFailureNotice` and returns before the reconcile and `dismiss()`. The `nil` answer — a title with nothing to make a task from, unreachable because `canCreate` requires a non-empty title — stays a silent return but no longer dismisses. That separation of *throw* from *nil* was not in the ticket.**

- [T-471] **iOS calendar quick-create dismisses as success when a bundle insert fails** (Codex, P2,
  measured). Worse than [[T-470]]: `iOSCalendarQuickCreateSheet.swift:595` does
  `_ = try? CadenceTaskMutationSupport.insertBundle(...)` and dismisses regardless, so the sheet closes
  as though a block was created. `CadenceTaskMutationSupport.swift:798` already does the right thing —
  it deletes the pending bundle and rethrows — and the caller throws that signal away. `dismiss()` must
  happen only after the `try` succeeds. Instance of [[T-322]].
  **Closed 2026-08-30. `dismiss()` is reachable only through the `try` succeeding; a throw sets the new shared `CadenceTaskMutationSupport.bundleSaveFailureNotice` ("Couldn't save this block.") and returns. The Block branch needed its own sentence — all five existing failure constants name an object this branch was not making, and a `TaskBundle` is a *block* in every user-facing string. Held beside the mutation that throws it, not spelled at the sheet, per that sheet's own rule against "a third spelling of 'that didn't work'". No "Nothing was created." clause: the create family does not carry one and the delete family does, and that asymmetry is now pinned.**

- [T-473] **The macOS list-detail Tasks tab still ships copy [[T-285]] retired** (Codex, P3, measured).
  `macOS/Views/ListDetailComponents.swift:68,103` says "Create a task to get started" while the actual
  affordance on that screen is the floating `+` bottom-right. T-285 removed exactly this wording from
  the macOS Tasks page and pinned it — but **the existing test only covers `TasksListView.swift`**,
  which is why this copy survived. Same family as [[T-469]] on iOS. Replace the subtitle with copy that
  names the reachable control, and widen the scan to `ListDetailComponents.swift`.
  **Closed 2026-08-30 by the repo-wide sweep rather than a second per-screen assertion. Reads `CadenceEmptyStateCopy.listDetail*`, shared with [[T-469]] so the two surfaces stay pinned to one sentence.**

- [T-474] **The iOS reset says the account was deleted, and iOS has no account** (Codex, P2; measured
  source plus a contradiction with a shipped doc). `iOS/iOSDataResetSettingsSection.swift:15,89`
  correctly explains that Sign in with Apple is macOS-only and "there is no account profile to clear
  here" — then, on success, prints the shared
  `PrivacyDataResetOutcome.statusMessage`: *"Cadence account and data were deleted."* The success
  message claims more than the action performed. The pre-action button on the same screen is already
  right ("Delete Cadence Data", not "Delete Account & Data"), and `docs/app-review-notes.md:23,36`
  distinguishes macOS account deletion from iOS data deletion — so the shipped notes and the shipped
  UI disagree. Keep one deletion sequence; split only the presentation sentence
  (`dataOnlyStatusMessage` / `accountAndDataStatusMessage`). Pin both, and assert the iOS success state
  does not contain "account". This is the error-message-accuracy class that
  [[T-374]]'s brief called out: a notice promising something the code did not do.
  **Closed 2026-08-30. `PrivacyDataResetOutcome` splits into `dataOnlyStatusMessage` (iOS) and `accountAndDataStatusMessage` (macOS); one deletion sequence, two presentation sentences. **The ticket found one instance and there were two** — the iOS *section label* was also "Delete Account & Data", the same claim one control earlier on the same screen, now "Delete Cadence Data". No live drawn string in that file names an account in any casing. No conflict with `AppStoreReviewReadinessTests` — its assertion reads the macOS pane, which keeps the wording — and `docs/app-review-notes.md` needed no edit: the shipped UI now agrees with it.**

- [T-475] **`TaskSectionConfig` is the third [[T-445]] shape and the first that loses real user data.**
  `Cadence/Models/AppTask.swift:9` — five defaulted properties (`uuid`, `colorHex`, `dueDate`,
  `isCompleted`, `isArchived`), persisted as JSON in `Project.sectionConfigsRaw` /
  `Area.sectionConfigsRaw`, decoded with `try?` at `Models/Project.swift:113` and
  `Models/Area.swift:112`. Adding a sixth property makes every stored section list undecodable; the
  getter then falls back to `sectionNamesRaw`, which keeps only the **names** — colour, due date,
  completion and archive state are silently dropped — and the setter rewrites `sectionConfigsRaw` from
  that degraded list on the next write, **making the loss permanent**. Unlike T-445 and [[T-466]] this
  is user data, and it is in `Models/`, which compiles into every target. Wants the `init(from:)`
  treatment plus a round-trip test *before* anyone adds a field. **Highest-priority open ticket.**
  **Closed 2026-08-30, **and the ticket's stated cause was already fixed**. `TaskSectionConfig.init(from:)` with `decodeIfPresent(...) ?? default` per field exists at HEAD, added by `7dddba8` — so "adding a sixth property makes every stored section list undecodable" was false when filed. The *second* half was real and is the half that loses data: `[TaskSectionConfig]` decoding is all-or-nothing, so one column with no `name`, a `null`, or a wrong JSON type drops the whole array to `sectionNamesRaw` — names only — and the setter writes that back permanently. Fixed with element-wise salvage (`StoredList` `.clean`/`.salvaged`/`.empty`): readable columns keep `uuid`/`colorHex`/`dueDate`/flags, unreadable ones recover by name. **No stored property added, removed or retyped** — the only model-file changes are an extension on the non-`@Model` `TaskSectionConfig` and two computed-property bodies.**

- [T-480] **`NoteMigrationServiceTests` leaves a fabricated migration report in the test host's
  `UserDefaults`.** 20 call sites reach `migrateIfNeeded` / `migrateAndRecordFailure`, each calling
  `record(...)` which writes `noteMigration.lastReport.v1`; only one test saves and restores it.
  `DataIntegrityRepairServiceTests` already guards this ("so a test run cannot leave a fabricated report
  behind for the app to read"), so the convention exists and this suite predates it.
  **Closed 2026-08-30, wider than filed: the suite pollutes **two** keys, not one — `noteMigration.lastReport.v1` and `dataIntegrityRepair.lastReport.v1`, measured before any change. The guard is a recursive `@Suite(.preservesTheStoredLaunchReports)` trait in the existing `TemporaryDefaultsSupport.swift`, and the one hand-rolled guard it made redundant is gone. Proved by hashing the whole stored value out of the test host's plist either side of a scoped run: guard removed → CHANGED, `isRecursive` false → CHANGED, as written → unchanged. See [[T-485]] for the three sibling suites that still leak.**

- [T-282] **The iPad's corner `+` carries the same palette, pointing the only way it can.**
  **VERIFIED 2026-08-26 — keep open. The value half is strongly pinned; the device run still has not
  happened.** Four mutations caught, including unifying the corner arc and weakening the drag arm,
  and the old system-drag path is gone with zero live references. Placement is pinned as
  *deliberately different* in both directions.
  Still outstanding, and it is the one thing the ticket was left open for: **nobody has driven an
  iPad.** The verifier was blocked all session — both booted simulators were held by live agents,
  and the claim script correctly refuses to reclaim a device with live operations on it.
  One specific risk only a device answers: `iOSCaptureRadialMenuOverlay`'s own comment says it sits
  at the **shell's** level so a palette is not clipped by a 46pt bar row — but on iPad the host is
  applied to the page's content, not the shell. The arc opens up-and-left so it probably clears.
  "Probably clears" is what a simulator run is for.
  From the [[T-73]] / [[T-170]] split, and the one genuine "control present at one width and absent
  at the other" that audit found. [[T-171]] had shipped the hold-for-palette gesture on
  `iOSCaptureRadialMenuButton`, whose **only** caller was `iOSCompactTabShell` — so holding the
  centre `+` on iPhone offered `CadenceCaptureAction`'s three segments (Task / Event / Note) and a
  drag onto a drop target, while the iPad's corner `+` (`iOSFloatingCreateTaskButton` →
  `iOSCircularAddButton` + `.iOSNewTaskDragSource`) tapped straight into `iOSCreateTaskSheet` and
  could capture nothing but a task. **Confirmed against the source before any of it was rebuilt.**
  The corner button now renders that same `iOSCaptureRadialMenuButton`.
  **What stayed different, deliberately, is the arc — and only the arc.** A button 50pt from the
  trailing edge cannot draw a semicircle: two of its three segments would be off the display. So
  `CadenceCapturePalettePlacement` gives `.bottomTrailing` a quadrant opening up and to the left,
  and a wider `layoutRadius` because three tiles packed into 90° instead of 180° would otherwise
  overlap — the tile width is published now so that claim is a test rather than a taste. The hold
  delay, the drag slop, the dead zone and the margins the outer and escape rings keep past the tiles
  are all the *same value*, asserted field by field.
  **The three outcomes do coexist on that button, and the reason is the reason T-171 gives.** The
  iPad's `+` carried a system `.onDrag`, and `UIDragInteraction`'s lift *is* a ~350ms long press —
  the same window the palette wants — so the two could never have shared a touch. It carries
  `CadenceCapturePressResolver`'s one `DragGesture` instead, exactly as the phone's does. Verified
  on a booted iPad simulator: press-and-move drags, press-and-hold opens the palette, and moving
  inside the radius slides between segments.
  **Two things went with it rather than being left beside it.** The system drag lost its last
  source, so `iOSNewTaskDragSource`, the drop target's `.onDrop`, `CadenceTaskDropPayload`,
  `CadenceTaskDropCoordinator` and `UTType.cadenceNewTaskDrag` are deleted — a sourceless second
  path into the same insertion ghost is how a comment ends up claiming "two mechanisms, on purpose"
  about one. And the three composers a finished press can ask for moved out of `iOSCompactRootShell`
  into `.iOSCaptureHost(_:)`, which both placements apply, because copying that routing to the iPad
  is the near-copy this repo keeps paying for.
  `iOSCircularAddButton`'s doc comment claimed the two buttons were "the same action in deliberately
  different *places*" while they were not. It now says which parts are shared (the face, the gesture,
  the composers, the feel) and which the placement chooses (the diameter, the corner inset, the arc)
  — and the `Button` wrapper of that name is gone, the name having moved down to the circle it
  always described.
  **Closed 2026-08-30 **from source, without a device**. The ticket's one open item was whether the palette is clipped. There *is* a clip — `iPadMacStyleRootShell` applies `.clipped()` to the detail pane and the capture host is inside it — and the arc clears it provably: every corner tile stays within 50pt of the button centre, the tightest sitting 54.5pt inside the page's trailing edge. Pinned by `theCornerPalettesTilesFitInsideTheButtonsOwnCornerInset`, arithmetic over the real shared metrics. **Take this out of the device-blocked group.** Two residues filed: the scrim does *not* clear the clip ([[T-491]]), and this ticket contradicts itself about whether an iPad was ever driven — the top says nobody has, the historical section describes a booted iPad simulator session.**

- [T-446] **Two "pick a context" controls with nothing shared underneath.** Residue from [[T-288]],
  which named `CadenceContextPicker` "the one with a live counterpart to converge on" and then had
  to move it instead. The move is correct and the convergence is still owed.
  What was found: the macOS control is keyboard-first — `onMoveCommand` (macOS/tvOS only), a search
  field that takes focus on appear, an arrow-driven `highlightIndex`, an `onSubmit` that commits it,
  and a hover wash on every row. None of that fires on iOS, and unfencing the file would have put a
  list with a permanently-raised keyboard in front of the next iOS reader. The two iOS sites
  (`iOSListEditorViews.swift:124`, `iOSTrackingEditorSheets.swift:167`/`:385`) already route through
  the `iOSChoiceRow` / `iOSChoicePopoverList` idiom, which is the touch answer to the same question.
  So the duplication is real but it is not a *view*: it is `sortedContexts`, the `localizedLowercase`
  filter, the `allowNone` "No context" row and the flattening — spelled once in
  `CadenceContextPickerList` and again, differently, at each iOS site.
  Done: one shared item model + filter (a `CadenceContextPickerSupport` beside the other
  `Cadence*Support` types), read by `CadenceContextPickerList` and by both iOS popovers, with the
  presentations left as the two they legitimately are. A test that fails if either platform
  re-derives the sort or the filter.
  **Closed 2026-08-30, **and the four spellings had diverged into a defect**. `Cadence/Shared/CadenceContextPickerSupport.swift` owns the sort, the archive rule, the unnamed fallback and the "none" row; the macOS list and all three iOS popovers read it, and the two presentations [[T-288]] refused to merge stay two. What the divergence actually was: `Context.isArchived` is excluded everywhere a context is *offered* — both sidebars, both settings panes, the MCP default — but only one of the four pickers filtered it, so **archiving a context did not stop you picking it fresh** on three surfaces. And the one site that did filter read its button label out of the *filtered* array while `save()` read the *unfiltered* one, so a project whose context had since been archived **displayed "None" and saved the archived context**. Also fixed: equal `order` resolved differently per platform (macOS broke ties on name, iOS relied on `@Query(sort:)` alone, which promises nothing among equal keys — and `order` defaults to 0, so every context created outside the reorder UI ties), and an empty name rendered three ways. Rule landed: hide what you could newly pick, never the one already assigned.**

- [T-449] **The last painted-under hairline is in `SettingsListManagementSections.swift`, and the
  sweep names it rather than allowing it.** Residue from [[T-286]]. That file was outside this
  batch, and it still carries the two-line `Divider().background(Theme.borderSubtle)` (calendar
  rows) plus a `.stroke(Theme.borderSubtle` well — the same two defects the other seven panes just
  lost. `noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak` skips exactly this one path by
  name, so the hole is one line of test source and closing it is one line of view source.
  **Closed 2026-08-30. Both calendar-row hairlines read `CadenceRowDivider(leadingInset: 44)`; the named exclusion is gone and the sweep scans all 15 settings panes. The exact-count pin for that file went 5 → 7, so reverting either site alone fails. **The ticket's second half is withdrawn**: the cited `.stroke(Theme.borderSubtle)` is a 28x28 menu glyph, not a typed-value well — `cadenceSettingsWell()` would force a min-height and 12pt of leading air, both wrong for a fixed glyph, and 28 other sites spell it the same way. See [[T-489]].**

- [T-450] **`SidebarTabEditorSheet.settingsPanelRow` is a fifth private settings row.** Residue from
  [[T-286]]. A title over a subtitle with a trailing accessory, on its own `cadenceCard` — which is
  `CadenceSettingsNoticeRow` minus the state glyph. It was left alone deliberately: inventing a
  glyph to reach the shared component would put a verdict on a sheet that reports none. Either the
  notice row grows an optional glyph or this row keeps its own spelling on purpose; it should not
  stay undecided.
  **Closed 2026-08-30. `CadenceSettingsNoticeRow.systemImage` is optional, `SidebarTabEditorSheet` reads the shared row, private `settingsPanelRow` deleted. [[T-286]]'s reason for keeping it was right about the glyph and wrong about the outcome: the private copy had already drifted to an **11pt subtitle where the other four say 12** — including the identity block twenty lines above it in the same sheet. Cosmetic divergence, but drift rather than decision, which is what settled the either/or.**

- [T-472] **The markdown toolbar has tooltips but no accessibility labels** (Codex, P2; source shape
  measured, the VoiceOver announcement itself inferred — the app was not launched). Every icon-only
  button in `macOS/Editor/MarkdownEditorView.swift` (`:203`, `:210`, `:333`, `:354`, `:375`) passes a
  good semantic string — "Bold", "Inline code", "Note link", "Task reference" — to `.help(...)` and
  nothing else, so assistive tech falls back to a symbol-ish or generic description. **The correct
  pattern already exists**: `macOS/Views/CadenceButtons.swift:109`, where `CadenceIconButton` applies
  `.accessibilityLabel(...)` *and* `.help(...)` from one string. Instance of [[T-374]]. Add the label
  to `MarkdownReferenceMenuButton`, `MarkdownToolbarButton`, and also `MarkdownToolbarTextButton` —
  the last one has visible `H1`/`H2` text, but the accessible name should be "Heading 1"/"Heading 2".
  Pin it with a source scan so a tooltip-only regression fails.
  **Closed 2026-08-30. All three markdown toolbar button types apply `.accessibilityLabel(...)` and `.help(...)` from one stored property — `CadenceIconButton`'s shape. **The durable half is the rename**: that property is called `accessibilityLabel` rather than `help` at all 19 call sites, because a parameter named `help` is what tells the next author the string is tooltip-only. Heading buttons are named "Heading 1"/"Heading 2" against visible `H1`/`H2`; `.accessibilityLabel` *replaces* a label's text rather than appending, so that is substitution, not double announcement. **What is verified is that the label is set** — nothing launched the app, so no claim is made about what VoiceOver announces. Ticket line numbers were one revision stale.**

- [T-477] **`SectionEyebrowLabel`'s doc comment names a type that does not exist.**
  `Shared/Components/SectionEyebrowLabel.swift:18` explains its `nonisolated` members by reference to
  "`CadenceEyebrowMetrics`' readers"; `rg CadenceEyebrowMetrics` returns exactly that one line in the
  repo. Stale prose from [[T-284]]'s conversion — the reasoning is still right, the name is not.
  **Closed 2026-08-30, **conclusion reversed on measurement**. Stripping `nonisolated` from all three `Size` members builds clean for the app *and* for `CadenceTests`, so the annotation is **not** load-bearing there: the target sets `SWIFT_APPROACHABLE_CONCURRENCY`, and every live `Size` reader is main-actor already. The static `SectionEyebrowLabel.fontSize` **is** load-bearing, for the `nonisolated struct CadenceTaskGroupHeadingMetrics` — which is the true statement the stale sentence was a corrupted copy of. Annotation kept, rationale corrected, and `theEyebrowDocOnlyNamesMetricsTypesThatExist` now stops this file's prose naming a type nobody can grep.**

- [T-478] **The macOS editor shows a copy cursor for an image drop it will refuse.**
  `MarkdownEditorView.updateNSView` calls `registerForDraggedTypes([.fileURL, .tiff, .png])`
  unconditionally and `CadenceTextView.draggingEntered` answers `.copy` for any image payload, so at a
  host with `allowsImageInsertion: false` ([[T-442]]) the cursor promises a capability the host has just
  declined, then `performDragOperation` falls through to `super`. The fallthrough is the safe direction,
  so this is cosmetic — but it is a control stating something untrue. Thread the flag into the
  representable.
  **Closed 2026-08-30. `allowsImageInsertion` now reaches the drop — the one image door [[T-442]] missed. `draggingEntered` delegates to `markdownImageDropOperation(for:)`, which returns `nil` (deferring to `super`) unless the host allows images *and* the pasteboard carries one, and `.tiff`/`.png` are registered only at an allowing host. `.fileURL` stays registered on both paths deliberately: it is not image-specific, and the operation rule already answers the dragged-image-file case. The verdict was split out of `draggingEntered` so it could be driven with a private `NSPasteboard`, since `NSDraggingInfo` is a protocol with a dozen members this decision does not read.**

- [T-484] **Visible settings toggles carry no accessible label** (Codex, P3; source measured, VoiceOver
  behaviour inferred). The visible row text says what the switch controls, but the control is
  `Toggle("", ...)` plus `.labelsHidden()`, so the switch's own semantic label is disconnected from the
  title beside it — `iOS/iOSNotificationsSettingsSection.swift:38,49`,
  `macOS/Views/SettingsNotificationsSection.swift:29,32`, `macOS/Views/SettingsSupportViews.swift:329`.
  **The correct pattern is already in the repo**: `iOS/iOSCalendarSettingsSection.swift:457` and
  `macOS/Views/SettingsListManagementSections.swift:332` pass a real label, e.g. `Toggle("Active", ...)`.
  Instance of [[T-374]]; same family as [[T-472]]. Do Settings > Notifications on both platforms first,
  then sweep. **Leave zero-size hidden keyboard-shortcut buttons alone** — different mechanism, not a
  defect. Pin with a source scan for a visible `Toggle("", ...)` not paired with an accessibility label.
  **Closed 2026-08-30, **and the ticket listed 3 of the 5**. The sweep found two more: the habit reminder row and the AI task-draft checkbox, alongside Notifications on both platforms and the sidebar-visibility row. `.labelsHidden()` stays — it hides the label from layout, not from the accessibility tree — and `SettingsSupportViews` **gained** it, because it was the one site without it, so a named toggle there would have drawn the row title twice. Zero-size keyboard-shortcut buttons are untouched and untouchable by construction: the rule keys on `Toggle("",` and they are `Button`s. Verified that the label is set; no VoiceOver announcement measured.**

- [T-322] **Decide the rule for `try? save()`, then sweep — there are 133 of them.** Measured, not
  estimated: `try? modelContext.save()` / `try? context.save()` appears **133 times** across
  `Cadence/`. [[T-319]], [[T-320]] and [[T-321]] are four of them; [[T-291]], [[T-298]], [[T-307]]
  and [[T-315]] are the same shape found by four earlier audits in unrelated code.
  **This is a convention, not a set of bugs, and it should not be fixed with a sed.** Many of the
  133 are probably fine — a save whose failure the user cannot act on, or a transient object. What
  is missing is a rule saying which is which, so the next one is written correctly instead of
  found by the ninth audit.
  Proposed shape, to be decided: a save is allowed to swallow its error only when nothing visible
  depends on it. Any save whose failure would let the UI **dismiss, navigate, or report success**
  must throw and be handled. Then triage the 133 against that rule rather than converting them all.
  Write the rule into `AGENTS.md` when it is decided — a rule an agent reads before writing the
  134th is worth more than fixing the first 133.
  **Closed 2026-08-30. The rule is in `AGENTS.md` under "The `try? save()` rule", both halves enforced by `CadenceSaveCommitDisciplineTests`. **112 live sites, not 133** — that figure predates eight earlier conversions, and 15 matches are tombstone comments quoting the retired line. **96 of 112 (86%) pass and should stay `try?`**; converting them would be 96 `do`/`catch` blocks buying nothing. 16 condemned, 4 fixed worst-first, 12 carried in exemption lists **by function name** with a test that fails when an entry goes stale *or* when a new offender hides beside an allowed one. **The proposed rule needed a second half.** "A save whose failure lets the UI dismiss or report success" is caller-local, so it cannot see a *helper* that swallows while its caller dismisses — which is what [[T-471]] was. The **existence** half (the function also `insert`s or `delete`s) catches that from one function, with no judgement. **And the cost was misstated**: this app has one `ModelContext`, so a swallowed failure does not mean the change did not happen — it stays *pending*, committed by the next unrelated `save()` from any screen or discarded by the next unrelated `rollback()`. Swallowing is a coin flip resolved on someone else's code path. Worst fix: `saveGoal`/`saveHabit` ended `try? save(); return resolved` and **all three callers read non-nil as success and dismissed** — create a goal, sheet closes, goal gone. Remainder is [[T-497]].**

- [T-374] **The most common defect shape in 21 audits is "a correct shared helper exists and call
  sites don't use it" — enforce it mechanically.** Synthesis, not a new defect. [[T-359]] (four
  open-coded habit toggles), [[T-362]] (eleven unreconciled date edits), [[T-364]] (creation paths
  bypassing `TaskCreationService`), [[T-365]], [[T-343]] all have that shape, and each was found by
  a human-scale read that will not repeat reliably. `CadenceCreateTaskCommitSurfaceTests` is already
  the right instrument. Extend that source-scan pattern to habit completion, task date/time
  mutation, and delete commit — **after** each shared wrapper exists, not before, or the test
  becomes a brittle census of scattered call sites.
  **Closed 2026-08-30 — **one sweep shipped, two families measured and refused.** Shipped: `CadenceSharedConstantReuseSweepTests`, every `static let` string constant in `Cadence/Shared/` harvested *from source* rather than hand-listed, swept over all 552 files under `Cadence/` through `CadenceScanInstrument`, two target boundaries subtracted by rule, one measured exemption. **28 raw hits, 22 true positives of 23 verdicts (96%)**, all 22 fixed. **Refused with numbers:** 80 numeric constants in `Shared/` produce **10,745 hits** and are *unattributable* — 11 distinct constants each equal `1`, 11 equal `8`, 11 equal `10`, so a hit cannot name which constant it should have read; and verbatim-line duplication yields 496 candidates topped by `.frame(maxWidth: .infinity, alignment: .leading)` in 72 files, which is SwiftUI idiom, not a helper. Both numbers live in the test so the claim can be re-run rather than trusted. One user-visible change: 16 fixed sites stop using `.isEmpty`, which the shared helper documents as the wrong guard, so a whitespace-only task title now reads "Untitled Task" instead of rendering blank. **The sweep caught its own author's mistake** — a first pass "fixed" 5 sites in files the MCP target compiles, turning the membership guard red; those are now subtracted by rule using that guard's own graph.**

- [T-453] **`CadenceWidgetDateSupport.storageCalendar(inheritingTimeZoneFrom:)` has no callers.**
  Found by a mutation that **survived**: re-pointing it to return the caller's calendar changed
  nothing, because nothing calls it. Its sibling forwards to `DateFormatters.dateKey(from:calendar:)`,
  which forces Gregorian itself — so the widget is correct and this is a dead pass-through left
  behind when [[T-301]] collapsed the hand-rolled copies. Delete it or give it the one caller it was
  written for.
  **Closed 2026-08-30, **and the interesting version was true**. Not dead on arrival: `b49b76e` added `storageCalendar(inheritingTimeZoneFrom:)` *with* two callers inside the same enum, and [[T-301]]'s collapse in `0e78c5b` rewrote both bodies to forward to `DateFormatters`, leaving an uncalled forwarding shim. Deleted; the Buddhist/Japanese/Islamic-calendar history it carried is already on `DateFormatters.storageCalendar`, with a tombstone pointing there. Guarded by a **census** rather than a name check — every `static func` in `CadenceWidgetDateSupport` must be reachable, counted two ways so an unqualified in-enum call is not miscounted as dead — so the next collapse that strands a member fails here instead of waiting for a survived mutation.**

- [T-467] **`CadenceCalendarPickerButton` collapses "hidden or read-only" into "No calendar"** — the
  [[T-441]] bug on a second surface. It renders `selected?.title ?? "No calendar"` by looking
  `selectedID` up in whatever `calendars` it was handed, and `TimelineEventBlockSupportViews.swift:195`
  hands it `calendarManager.writableCalendars` (active AND `allowsContentModifications`). Events are
  fetched from `availableCalendars`, which does not filter by writability, so an event on a subscribed
  read-only calendar should reach the timeline and print its calendar name in `calendarLabel` while the
  Calendar row directly beneath says "No calendar" — two contradictory readings in one card. Route it
  through `CadenceCalendarLink` ([[T-464]]), which now exists for exactly this. **Reachability narrowed by a second audit (Codex, 2026-08-29, measured source flow):** the *hidden*
  case is **not** reachable — the timeline fetch uses `availableCalendars`, which already excludes hidden
  calendars. The reachable case is an **active read-only / subscribed** calendar: the timeline shows its
  events, the detail picker is handed `writableCalendars` (`TimelineEventBlockSupportViews.swift:195`),
  `selected` comes back nil and the row renders "No calendar"
  (`CadenceCalendarPicker.swift:230,248`; `CalendarManager.swift:159,164`). So fix the read-only case and
  drop the hidden framing. The QuickCreate call
  site (`QuickCreateChoiceSupportViews.swift:203`) is a create flow with `allowNone: false` and is not
  affected.
  **Closed 2026-08-30, **reachability confirmed independently first**. Two audits had disagreed; the second was right. Measured from source: `fetchEvents`/`fetchAllDayEvents` build their EventKit predicate from `availableCalendars`, and `isActiveCalendar` consults visibility **only, never writability** — so a hidden calendar's events never reach the timeline and **the hidden case cannot be opened in this editor**. The live case is an active read-only/subscribed calendar. The fact that made the fix clean: `availableCalendars \ writableCalendars` is *exactly* the active read-only set, so `.readOnly` is always the true word for whatever the offer adds back. Routed through `CadenceCalendarLink` with a new `CadenceCalendarLinkExclusion` (`.hidden`/`.readOnly`) — calling a read-only calendar "(Hidden)" would be the same collapse one word further down. The picker list and button take the link rather than a set of ids, so the button's value and the menu it opens cannot word the same calendar differently.**

- [T-468] **macOS silent push registration has two launch callers** (Codex, P3, source drift measured;
  the duplicate-OS-call risk is inferred). `CadenceApp.swift:13` and
  `macOS/Services/CadenceAppDelegate.swift:10,27` both call the same registrar on a normal launch.
  `registerIfNeeded()` checks `isRegisteredForRemoteNotifications`, so it may collapse to one OS call
  depending on timing — the defect is that the launch wiring is duplicated while docs and history
  describe the AppDelegate as *the* registration site, which is how a future launch audit or an App
  Review explanation gets subtly wrong. Not a permission-prompt bug: the app still correctly avoids
  `requestAuthorization()` on cold launch. Pick one owner (probably the AppDelegate), delete the other
  call, and pin **exactly one production caller** with a source scan. Confirm:
  `rg -n "registerIfNeeded\(|registerForRemoteNotifications\(" Cadence/CadenceApp.swift Cadence/macOS/Services/CadenceAppDelegate.swift`
  **Closed 2026-08-30 **with its limit stated**. `CadenceApp.init()`'s call is gone; `applicationDidFinishLaunching` is the sole owner, pinned by a body-scoped scan. **No double OS registration was fixed or claimed** — `registerIfNeeded()` guards on `isRegisteredForRemoteNotifications`, which only turns true after a completed round trip, so the second caller *plausibly* fired a second registration, but nothing in a test host can observe that. Unproven either way, exactly as the audit had it. Three things are pinned: exactly one qualified caller and it is inside that method; the registrar is the only thing in the app calling AppKit's `registerForRemoteNotifications()`; and cold launch still calls no `requestAuthorization`. The scan reads comment-stripped source, which is load-bearing — the new tombstone comment names the call it no longer makes, and a raw scan would count it as the second caller.**

- [T-476] **The iOS template editor's `BODY` label is the last hand-typed letterspacing in the app.**
  `iOS/iOSSettingsTemplateAndListSections.swift:594` — a hand-rolled `SectionEyebrowLabel`, so the fix
  is the component, which changes the weight from bold to semibold, and no macOS test target can render
  an iOS view to check the result. `exactlyOneHandTypedLetterspacingIsLeftInTheApp` names this path;
  closing it turns that expected list into `[]`. Also the last piece of [[T-442]]'s parity gap — macOS's
  template Body label is already `CadenceSettingsField`'s eyebrow.
  **Closed 2026-08-30. `SectionEyebrowLabel(text: "Body")`; `exactlyOneHandTypedLetterspacingIsLeftInTheApp` is now `noHandTypedLetterspacingIsLeftInTheApp` with an expected list of `[]`, plus a direct read of the site — an empty sweep and a sweep that stopped reading the file look identical. Size, tint, uppercasing and 0.8 tracking are value-preserved and asserted. **The weight goes bold → semibold and that result is unverified**: no macOS test target can render an iOS view. Somebody has to look at it on a phone.**

- [T-479] **The iOS search surface never adopted `CadenceSearchMatcher.rank`.** Found while closing
  [[T-372a]]. `iOSSearchView` scores through the shared `matchScore`, then sorts each of its seven
  sections with a bare `.sorted { $0.score > $1.score }` (`:105,123,172,199,230,245,261`) — no title
  leg, no identity leg. That is **more** partial than the state T-372 found macOS in, so two iPhone
  results that merely tie on score come back in `@Query` order, and T-372a's fix does not reach them
  because they never call `rank`. The shape is `GlobalSearchIndexSupport.rankedResults` — one funnel per
  surface passing `title:` and `identity:` — not seven threaded closures.
  **Closed 2026-08-30. **`iOSSearchResult.id = UUID()` was the real blocker** — a per-construction UUID *is* a total order, but a different one on every recomputation, so adopting it as the identity leg would have produced exactly the nondeterminism the leg removes while looking like a fix. `id` is a stable `String`, non-optional in the memberwise init ([[T-372a]]'s rule one level down). Also **six sections, not the ticket's seven**: `:123` is an idle-suggestion sort on dueDate-then-order, a different shape. Spellings live in a shared `CadenceSearchIdentity`, adopted by macOS's nine literals too, so the fix did not author a tenth hand-typed `"task-\(uuid)"`. Two are decisions: events tie on the **occurrence-scoped** identifier, deliberately against a neighbouring file whose prior leg is the start instant (this one's is the score, and a week of one standup scores and titles identically); and goals/habits both navigate to `.feature(...)` — the page, not the entity — which is why `id` is stored rather than derived. Idle-branch windows are [[T-498]].**

- [T-494] **Three retired `iPad*` names survive in agent-facing docs.** `docs/IOS_AGENTS_REFERENCE.md:129,318`
  and `docs/CLAUDE_REFERENCE.md:1149` still name `iPadTodayScheduleViews` and `iPadTodayView`.
  [[T-283]]'s retired-name sweep covers `Cadence/**/*.swift` only, so these are unguarded and **will send
  the next agent to files that do not exist**. Widen that sweep to `docs/`.
  **Closed 2026-08-30, **and the free answer is "nothing else"**. Three names fixed across the two references; the retired-name list is now one constant read by both the code sweep and a new doc sweep, so a fifth name cannot be added to one copy only. The widened sweep walks the root guides, every scoped `AGENTS.md` and `docs/`, minus the two ticket ledgers — excluded **by rule**, because an archive entry describing a rename has to spell the old name. Checked both failure shapes repo-wide: the only absent identifiers left are four **tombstones** — sentences that exist to say a type never existed — which must stay, and one frozen audit snapshot whose citations were deliberately not rewritten, since that would make the snapshot describe a tree it was not taken from.**

- [T-119] **Not reproduced — and the obvious fix breaks scrolling.** Reported by the drag sweep as a
  Week-view task block opening the Edit Task sheet after a 700ms press and 250pt of travel. Five
  gesture variants on HEAD — vertical both ways, horizontal, single-jump, diagonal — all scrolled the
  grid and opened nothing. That matches the construction: the block is a plain `Button`, which does
  not fire when released outside its bounds, and the grid's scroll views claim the pan first.
  The fix was built anyway and **regressed scrolling**: a `simultaneousGesture(DragGesture(minimumDistance: 0))`
  on scroll content claims the touch, so a plain swipe starting on a block stopped scrolling where
  HEAD scrolls. Reverted, helper and tests deleted.
  Most likely the original observation was the grid scrolling 1:1 under the finger — 250pt relative
  to the screen, none relative to the control. **Left open only as a warning**, not as work: it joins
  T-89 and T-14 as an observation whose mechanism was misattributed, and it should not be "fixed"
  without a fresh reproduction.
  **Closed 2026-08-30 **as unreproducible, with the argument made exhaustive**. There are exactly five `taskInspector(` call sites in `Cadence/iOS/` and only two on a Week surface: a stock SwiftUI `Button` (`.iosPressable` is a bare `ButtonStyle` over `configuration.isPressed`, installing no recogniser) and an `onTapGesture`. **`onLongPressGesture` does not appear anywhere in `Cadence/iOS/`.** A better-fitting explanation than the ticket's own: the two **bundle** blocks carry a `.contextMenu` whose single item is "Edit Block", and press-drag-release onto it is the documented way to invoke a context menu — bundle blocks sit beside task blocks in the same column at the same title size. Under that reading the reverted fix was suppressing correct system behaviour, which is consistent with it having broken scrolling. **No test added**: pinning an absence for an unreproduced observation is the shape this ticket warns against.**

- [T-336] **DECISION NEEDED: should the iPhone `+` inherit the page you are on?** From the same
  **ANSWERED 2026-08-26 by the user, and superseded by [[T-337]].** The question was whether the
  iPhone `+` should inherit the page. The answer is **neither button should** — context comes from
  the *drop target*, not from the page you happen to be standing on. That resolves this ticket and
  reverses the iPad's current page-seed at the same time. Keep this entry only as the record of how
  the question was framed; the work is T-337.
  audit, and filed as a question rather than a defect because **the current behaviour is deliberate
  and test-pinned**, which the audit established rather than assumed.
  The iPad's page-corner `+` passes a seed — Today seeds today's date, a list detail seeds that
  list. The iPhone's centre `+` is deliberately unscoped, and `CadenceCapturePaletteTests` asserts
  it carries no `baseSeed`.
  So this is only a ticket if the wanted behaviour is: tapping `+` from iPhone Today or a list
  should inherit that context. Note it sits beside the rule the user set for [[T-282]] — placement
  may differ across widths, capability may not — and a seed is arguably capability rather than
  placement. **Ask the user before touching it**, and if the answer is "leave it", record that here
  and close, because the test currently pins the opposite of what a reader might assume.
  **Closed 2026-08-30 as **stale bookkeeping — it was already answered, shipped and pinned.** The user answered on 2026-08-26: neither button inherits; context comes from the drop target, not the page you are standing on. [[T-337]] shipped it. `iOSCaptureRadialMenuButton` has **no `baseSeed` property at all**, so filling it back in from a call site is a compile error rather than a convention, and three tests in `CadenceCapturePaletteTests` pin it — including that the only route from page to new task is `CadenceCaptureSeedResolver.seed(...)` reading the drop target.**


- [T-498] **iOS search's *idle* suggestion windows are cut from a partial order.** [[T-479]] fixed the
  `isSearching` branches; the idle ones take `prefix` straight off a partial order in four of six
  sections — `taskResults` sorts dueDate then `order` (per-list, so cross-list ties are routine) then
  `.prefix(8)`; `listResults`, `noteResults`, `progressResults` prefix straight off `@Query` order. On a
  partial order the **window itself** is nondeterministic, not just its arrangement: tied rows past the
  cut are dropped by fetch order, so *which eight* suggestions appear changes between reads. `pageResults`
  (catalog order) and `eventResults` (already total, [[T-373]]) are fine. The fix is a final identity leg
  on each idle comparator, **not** the score funnel — an idle list is deliberately chronological/manual
  rather than scored.
  **Closed 2026-08-30. Four idle sections cut their window through `CadenceSearchSuggestionWindow.take`, which completes each section's **own** comparator with a `CadenceSearchIdentity` leg and **detects** ties rather than declaring them — under a strict weak ordering two rows are equivalent exactly when neither precedes the other, so there is no `Key` type and no second closure a call site could let drift. Deliberately **not** the score funnel, and the reason is written down: with no query every row scores 0, so ranking would re-sort all four idle lists to alphabetical and destroy the chronological/manual order they exist to show. `pageResults`/`eventResults` untouched — exactly one `.prefix(8)` survives in the file and it is the events one. The membership mutation is the load-bearing one: a bare `prefix` over the same fixture returns two different **sets** depending on input direction.**

- [T-499] **The MCP server target re-types three user-facing fallbacks it cannot read.**
  `CadenceReadService.swift:814,843,1069,1251` and `NoteReferenceSupport.swift:113` spell
  `"Untitled Task"`/`"Untitled Context"` because `Cadence/Shared/` is not in the `CadenceMCPServer`
  source list. Real duplication, not reachable duplication — **the app and the MCP surface can drift on
  user-visible copy.** Fix by moving `TaskTitleSupport.defaultDisplayTitle` and
  `CadenceContextPickerSupport.untitledName` to `Models/` (the [[T-354]] boundary), or give the MCP target
  its own named constant. Currently subtracted by [[T-374]]'s sweep and pinned by
  `theSweepSkipsTheFilesTheMCPServerTargetCompiles`, which **fails when this is fixed**, so the
  subtraction gets deleted along with it.
  **Closed 2026-08-30 **by moving to `Models/`, not by an MCP-local constant** — that would be the drift relocated rather than removed. `Models/ModelEnums.swift` already hosts `CadenceTitleNormalization` and `TaskTitleShortcutParsing` for exactly this reason ([[T-354]]/[[T-406]]). Three labels moved, including `"Untitled"` at `NoteReferenceSupport.swift:122`, which the sweep could not see at 8 characters; the `Shared/` names stay as forwarders so no app call site changed. **The [[T-374]] subtraction was narrowed to a predicate rather than deleted** — its premise still holds for `Shared/`-only constants, so a flat deletion would re-arm a false positive nobody could fix; as a predicate it retires itself when a declaration moves, which it then did, and the five hits it had been hiding became ordinary offenders and were fixed. The harvest now walks `Cadence/Models/` too, or this move would have **silently dropped `"Untitled Task"` out of the sweep**; measured 0 pre-existing qualifying constants there, so no added noise.**

- [T-500] **Four near-duplicate title-fallback helpers.** `CadenceMCPServiceSupport.resolvedTitle`,
  `CadenceReadService.resolvedTitle`, `MarkdownTaskEmbedSupport.sanitizedReferenceTitle` and
  `NoteReferenceSupport.sanitizedReferenceTitle` are four re-implementations of
  `CadenceTitleNormalization.display(_:fallback:)`. A [[T-374]] instance its string sweep **structurally
  cannot see**: that sweep detects a duplicated literal, not a duplicated function.
  **Closed 2026-08-30, **and the divergence check changed the answer: the four are two.** `CadenceMCPServiceSupport.resolvedTitle` is character-for-character `CadenceTitleNormalization.display`, and `CadenceReadService.resolvedTitle` was already a private *forwarder* to it, not a fourth implementation — both deleted, 11 call sites now call `display`. The two `sanitizedReferenceTitle`s are byte-identical to each other and **not** re-implementations of `display`: they are `display` composed with a five-character markdown escape. **Collapsing all four as the ticket asked would have dropped the escaping that keeps `[[task:UUID|Read [ch. 3]]]` from ending two characters early.** Consolidated as `CadenceTitleNormalization.referenceDisplay`, which had to live in `Models/`: the MCP target compiles `NoteReferenceSupport.swift` and not `MarkdownTaskEmbedSupport.swift`, so the two halves had no other file they could both reach.**

- [T-488] **`iOSListEditorSheet`'s Area row has the defect [[T-446]] just fixed for Context.** Same file,
  one row down the same `Form`: `areaTitle` (`iOS/iOSListEditorViews.swift:83`) resolves against
  `areas.filter(\.isActive)` while `selectedArea` (`:510`), which `save()` uses, resolves against the
  unfiltered `areas`, and the popover offers only active ones. So editing a project whose area was since
  deactivated **shows "None" and saves the inactive area**. There is no shared support type for area
  picking to route it through — `CadenceContextPickerSupport` is the model to copy.
  **Closed 2026-08-30 **by generalising [[T-446]]'s list rather than copying it**. The two support types were diffed before choosing: everything was identical except offerability and the untitled label, so `CadencePickerSupport` is now generic over a `CadencePickable` and the Area and Context types are a typealias plus those two facts. **The offerability difference matters** — an area has three states, so copying Context's `!isArchived` rule would leave a *completed* area offerable; the mutation that swaps it in kills a test by name. `theAreaPickerSupportIsNotASecondCopyOfTheContextPicker` pins that exactly one file declares the rules, so the [[T-374]] near-copy cannot come back. `Project` is deliberately not conformed — nothing picks a project alone. Third instance of the split filed as [[T-514]].**

- [T-490] **`CadenceChoiceRow` defaults its `id` to `AnyHashable(title)`, and 32 call sites take the
  default.** Two options with the same displayed title collide into one `ForEach` identity in
  `CadenceChoicePopoverList`. [[T-446]] passed an explicit id at its three context sites; the other 32 in
  `Cadence/iOS/` still default. Either make `id` non-defaulted or derive it from `value`, which is
  already `Hashable`, rather than from the title.
  **Closed 2026-08-30, **more strongly than the ticket proposed**. Rather than making `id:` mandatory, the parameter is **removed** and identity is `AnyHashable(value)` as a computed property — checked across all 35 call sites, including the `["none"] + areas`, `[-1] + minutes` and `[nil] + goalIDs` concatenations, and `value` is already what `selection` compares against. That takes the decision away from authors instead of asking 35 of them to answer it.**

- [T-492] **`iOSNoteEditorSheetHeader` hand-spells the editor-sheet host gutter.** Residue from
  [[T-281]] — the fix that closed one duplication opened this one.
  `.padding(.horizontal, isRegularWidth ? 20 : 18)` is exactly
  `iOSEditorSheetMetrics.gutter(isRegularWidth:)`, which five surfaces read and whose own comment says it
  exists so that figure is stated once. Worse, T-281's `oneSharedViewOwnsTheNoteEditorHeaderRamp`
  **asserts the literal is present**, pinning the copy in place. Closing it is one line of view source
  plus removing the named exclusion in `noEditorSheetSurfaceSpellsTheHostGutterRampItself`. Worth doing
  for a second reason: `iOSEditorSheetMetrics` sits outside `#if os(iOS)` so `CadenceTests` can read it,
  so routing the header through it converts that ramp into a behavioural assertion.
  **Closed 2026-08-30. `iOSNoteEditorSheetHeader` reads `iOSEditorSheetMetrics.gutter(isRegularWidth:)`; the named exclusion is deleted so the allowlist is down to the file that defines the ramp. **The ticket's second reason is the one that paid**: [[T-281]]'s test listed the margin as the literal `isRegularWidth ? 20 : 18`, so it was *pinning the copy in place*. It names the shared call now and states the figure as a value, which `iOSEditorSheetMetrics` sitting outside `#if os(iOS)` makes possible — converting a source-shape assertion into a behavioural one. Proved by mutation rather than claimed: flattening `gutter` to `20 : 20` **never touches the header file's text** and the header's own test still fails, which the pre-T-492 version could not have done.**

- [T-495] **`MarkdownEditorView` replaces `NSTextView`'s dragged-type registration rather than adding to
  it.** `registerForDraggedTypes` sets the accepted-type list wholesale and `configure(_:context:)` has
  called it unconditionally since before [[T-478]], so the macOS note editor may accept only the types
  Cadence names — **plain-text and RTF drags into a note might silently do nothing**. **Not measured**: no
  drag was performed, and `NSTextView` re-registers `acceptableDragTypes` on its own at various points,
  which may already restore them. Cheap to settle by hand — drag selected text from another app into a
  note. If real, union with `super`'s types in `CadenceTextView.registerMarkdownDraggedTypes()`.
  **Closed 2026-08-30 **as not a defect, disproven by measurement.** On a real offscreen `CadenceTextView` built exactly as `makeNSView` builds it: with registration never called, `registeredDraggedTypes == []` at *every* step of the real sequence — so there was nothing for `registerForDraggedTypes` to displace; it adds 3 to an empty list. **AppKit's own re-registration unions rather than replaces**: toggling `isEditable` yields 22 types, `acceptableDragTypes`' 19 plus Cadence's 3. And the proposed union has a measured cost — `acceptableDragTypes` carries the legacy TIFF and PNG names **even with `importsGraphics` off**, so unioning would re-advertise bitmap drags at a refusing host and **undo half of [[T-478]]**. Residual, filed as [[T-511]]: whether a plain-text drag reaches the editor at all in the running app, which is not answerable headless and is not caused by Cadence's call either way.**

- [T-503] **The `try? save()` rule is blind to "insert and never commit at all."** Found by [[T-497]]
  while applying the rule. **Both halves key on the *presence* of a `try? ...save()`**, so a function
  that inserts and never commits passes both sweeps. Measured over 552 files: **21 declarations call
  `modelContext.insert(...)` and reach neither `save()` nor any `commit*`. Four of those also report
  success in the same function** — [[T-471]]'s defect with the save missing entirely rather than
  swallowed:
  `CreateContextSheet.create` (`insert; dismiss()`), `CreateListSheet.create` (same),
  `HabitsFormSheets.create` (`insert; scheduleReconcile; dismiss()`), and
  `TimelineEventBlockSupportViews.openEventNote` — **the exact macOS twin of the site T-497 just fixed
  on iOS, one platform behind, and worse: iOS at least attempted a save.** Cost is the one [[T-322]]
  measured: the row stays *pending* in the single `ModelContext`, committed by the next unrelated save
  from any screen or discarded by the next unrelated `rollback()`. Fix: route the four through
  `commitInsert`, then add a **third half** to the rule (a declaration that inserts must reach a
  commit), subtracting the 17 helper cases **by rule** — those are inserts whose *caller* owns the unit
  of work. Also add `presented[A-Z]\w* =` to half 2's vocabulary.
  **Closed 2026-08-30. **The 21 re-measured and confirmed at exactly 21.** Four sites routed through `commitInsert` — `CreateContextSheet.create`, `CreateListSheet.create` (which records *which* switch arm ran, so the undo cannot un-insert the wrong one), `HabitsFormSheets.create` (whose `scheduleReconcile` fetches the habit table back, so it would have scheduled a reminder for a row about to be un-inserted), and `TimelineEventBlockSupportViews.openEventNote`. **[[T-497]]'s trap does apply to the macOS twin**: `noteForEditing` forwards to the same shared function, so it returns an existing note as often as it creates one and a blind `commitInsert(of:)` would delete a note the user already had — pinned through the macOS *wrapper*, since a forwarder that dropped its `insert:` closure is how this platform could inherit the shape without the behaviour. **Half 3's exemption list is empty, and that emptiness is the claim**: 16 of 17 helpers subtract by signature (`: ModelContext` in the parameter list *is* "my caller owns the unit of work" — deliberately not bare `ModelContext`, since `commit: (ModelContext) throws -> Void` is a commit handed *in*), and the 17th owns its context and commits two hops away, so commit-reach follows same-file calls to a fixed point.**

- [T-504] **An enabled Paste that does nothing, at the four hosts that refuse images.** Symmetric on
  both platforms, confirmed by construction. iOS: `canPerformAction` returns `true` for any image-only
  pasteboard, but `createPastedImageAssets` returns `[]` when `allowsImageInsertion` is false, so
  `paste(_:)` falls through to `super.paste`, which does nothing on a view with
  `allowsEditingTextAttributes = false`. macOS: `readablePasteboardTypes`
  (`MarkdownEditorInteractionSupport.swift:101`) widens **unconditionally**, even though the same class
  already carries `allowsMarkdownImageInsertion` — `registerMarkdownDraggedTypes` and
  `markdownImageDropOperation` both consult it and this one does not. Affects the note-template editor
  on both platforms, the calendar event-edit sheet, and quick-create in event mode. One clause on
  macOS; thread the flag onto `iOSMarkdownTextView` for iOS.
  **Closed 2026-08-30, both platforms. macOS: `readablePasteboardTypes` returns `super`'s list unchanged when the flag is false — it was the only one of that class's three image doors not reading a flag its two neighbours already read. iOS: a new `allowsMarkdownImageInsertion` consulted in `canPerformAction` **before** `UIPasteboard.general.hasImages`, so a refusing host never raises the "pasted from" banner to answer a question it has already answered; set in `makeUIView` **and** `updateUIView`, the second being load-bearing because quick create flips `kind != .event` on a live text view. `paste(_:)` is left unguarded on purpose — its fall-through to `super.paste` is already correct and pinned. **The advertisement was the door.****

- [T-505] **Four "Untitled ..." labels have no declaration anywhere.** Found while closing [[T-499]].
  Unlike the three labels that one moved, `"Untitled Goal"`, `"Untitled Habit"`,
  `"Untitled Milestone"` and `"Untitled Note"` are re-typed with nowhere to read them from —
  `CadenceReadService.swift:901,915,1126,1155`, `CadenceHabitWidgetSupport.swift:200`,
  `CadenceMilestoneWidgetSupport.swift:284`, `CadenceNoteExportSupport.swift:107`,
  `AIActionService.swift:86`, plus ~a dozen iOS sites. **The sweep structurally cannot see them**: it
  reports a *shared constant* re-typed, and with no declaration there is nothing to compare against.
  T-499 makes the fix cheap — declare them beside the other three in `CadenceTitleNormalization` and the
  sweep picks them up automatically, since the harvest now reads `Cadence/Models/`. Spans all three
  targets.
  **Closed 2026-08-30. **The four labels were seven and the ~20 sites were 45**, in 20 files across all three targets — re-measured rather than inherited, under a stated rule (declare iff the literal appears at ≥2 sites in ≥2 files), which added `"Untitled Area"` (9), `"Untitled Project"` (8) and `"Untitled Reminder"` (2). **No line of the sweep changed** — [[T-499]]'s harvest already read `Models/`, so declaring the constants was the whole fix, and the sweep went from silent to naming all seven the instant a declaration existed. **Kept deliberately behaviour-preserving**: every site kept its own guard rather than being routed through `display(_:fallback:)`, because `display` trims and `isEmpty` does not — converting 45 sites would have been a silent behaviour change to whitespace-only titles smuggled in under a de-duplication. Residues filed as [[T-512]] and [[T-513]].**

- [T-508] **The `try? save()` rule keys on `save()` specifically, so it misses `try?` on commit helpers
  and file writes.** Distinct from [[T-503]] and found the same way — by two real defects it could not
  see. The sweep's patterns are `try? save()` and `try? modelContext.save()`, so
  `try? CadenceSavedLinkPersistence.insert(...)` ([[T-507]]) and `try? content.write(to:)` ([[T-506]])
  both pass all halves. **Widen the vocabulary to the commit surface rather than the method name**: any
  `try?` on a `CadencePendingChangePersistence.commit*`, on a `Cadence*Persistence` helper, or on a
  `Foundation` write whose failure the caller then reports success over. Measure the new hit count
  before shipping — the value of this rule so far has been that 86% of sites legitimately pass it.
  **Closed 2026-08-30 **with the measurement, and one carve-out**. Widened to the commit surface (`try?` on a `Cadence*Persistence` helper) and generalised `isPresented = false` to `is<Something> = false`. Measured over 552 files: **either half alone finds 0 new offenders; both together find exactly 1**, and that one is [[T-507]], now held in `reportExemptions` cross-referenced — whoever fixes it must delete the entry or the rot test fails. **`write(to:)` deliberately excluded**: measured at +0, and [[T-506]] is invisible not because of the needle but because nothing after that write reports success in source — the report is the *absence* of an error sheet. Out of the rule's shape, not hidden from it. Recorded in the rule so nobody re-derives it.**

- [T-501] **`docs/TODO_DONE.md`'s "Landed in" SHAs record where a ticket was *removed*, not where it
  shipped.** Found while applying [[T-462]]'s title recovery: T-285's entry reads "Landed in `0dd7258`",
  whose subject is *"Deduplicate docs/TODO.md"* — a bookkeeping commit that changed no Swift.
  [[T-462]]'s measurement explains why: **175 of 200 archived tickets were removed by commits that
  touched only `docs/TODO.md`.** So an unknown share of the 177 existing entries attribute a fix to a
  commit that did not contain it, which is worse than a missing SHA because it reads as authoritative.
  Establish how many are wrong before deciding whether to re-derive them.
  **Closed 2026-08-30 — **and the ticket's premise did not survive measurement. 5 of the 177 entries had a wrong SHA, not ~175.** I filed this by generalising one example (T-285 citing a "Deduplicate docs/TODO.md" commit); the generalisation was wrong. [[T-462]]'s 175/200 figure measured **removal** commits for the 200 tickets that were *never archived* — a different population. The archive mostly does not cite removal commits at all: 79 entries cite a deliberately different commit, and of the 85 that do cite their removal, 80 are large code batches that shipped the fix *and* closed the ticket together (the per-batch citation counts match the "N fixes" in each batch's own subject). **The bug was in T-462's reconstruction fallback, not in the archive's convention.** All five were recovered and corrected — T-284→`96b5583`, T-285/T-286/T-288→`b05869d`, T-361→`5d2c196` — plus six entries that had no SHA but did have code behind them, and T-279's entry, which still claimed "working tree, not committed" after `cb53c78` committed it. **The other 172 are deliberately not re-derived**: two independent channels corroborate them, and a blanket `git log -S` pass would replace correct attributions with first-touch SHAs, which for a symbol like `MarkdownHeadingRamp` lands on the wrong ticket entirely. Nine remaining SHA-less entries are correctly SHA-less — closed by splitting, audits that changed nothing, or shipped as `AGENTS.md`/`scripts/` changes where a docs SHA is the right answer.**

- [T-485] **Three sibling suites still leave fabricated launch reports in the test host's `UserDefaults`.**
  Demonstrated live by [[T-480]]'s own final run, which left `dataIntegrityRepair.lastReport.v1` =
  `{"source":"test"}` behind. `DataIntegrityRepairServiceTests` (11 call sites, 1 guarded test),
  `CadenceHabitCompletionDuplicateTests` (3, 0), `CadenceNoteFolderSurfaceTests` (1, 0). Each needs a
  one-line `@Suite(.preservesTheStoredLaunchReports)`. To make it durable rather than a one-off cleanup,
  a `CadenceScanInstrument` sweep asserting every suite that reaches `migrateIfNeeded`/`repairIfNeeded`
  carries the trait.
  **Closed 2026-08-30. Three siblings annotated and `DataIntegrityRepairServiceTests`' now-redundant hand-rolled guard deleted — T-480's precedent is one spelling of the guard, not two. **The durable half is the sweep**: `everyTestSuiteReachingALaunchReportWriterPreservesTheStoredReports` attributes the trait **per suite**, using the extent reader extracted out of `cadenceTestDeclarations` rather than a second copy. Failing-first named exactly the three files; three mutations killed by name, **one of them inside `CadenceScanInstrument`'s own constructor** ("does not fire on its own positive witness"). Leakage re-proved from outside the process with a **full-value** `sha256` of the test host's plist, not a truncated digest — guarded run unchanged, unguarded 407→416 bytes and a different hash — so detection was shown to distinguish guarded from unguarded *before* the green was trusted. The unguarded run left a fabricated report on the real app state and the snapshotted bytes were restored and re-verified.**

- [T-486] **Extension methods declared in non-member files are invisible to the membership guard.**
  [[T-435]]'s own text named this alongside free functions; only the free-function half is closed.
  Measured: **117** extension-method names are declared in files the MCP target does not compile. A crude
  dot-qualified probe surfaced 2 candidates and **both are false positives** — one resolves to a member
  file, one is inside a doc comment — so there is no live violation. A real check needs receiver-type
  resolution, a different instrument from the two in that file, which is why this is separate rather than
  a widening.
  **Closed 2026-08-30 **by refusal, with numbers.** Receiver-blind dot-qualified matching: 138 candidate names, **0 hits in the target** (the ticket's 2 candidates were an unstripped comment and a name resolving to a member file — both vanish under proper stripping). On a 558-file precision corpus, 73 instance-receiver hits of which **≥12 are provably ambiguous inside the repo alone** — `badges.count(for:)` resolves to a nested `func count(for:)`, not to `extension CadenceSidebarLayout` — with framework collisions unbounded without a type-checker. **The sound subset exists and provably adds nothing**: type-qualified `T.m(` is 100% precise, but 85 of 94 candidate pairs have a receiver the existing type guard already rejects, and the 9 with a reachable receiver are all *instance* methods (`Goal.isOverdue`, `Habit.isDone`, …) that can never be spelled `T.m(`. Net new detections: **0**. Widgets identical (90/7/0). **The residual hole is real and named** — a member file writing `goal.isOverdue(...)` breaks `-scheme CadenceMCPServer` while `-scheme Cadence` stays green — and the instrument that resolves receivers already exists and is already shared: `CadenceMCPServer.xcscheme`. This measurement is the argument for [[T-435]]'s own honest close, building that scheme in CI, rather than for a third text scan.**

- [T-493] **`iPadTodaySidePanel`'s kept prefix rests on a claim the code does not keep.**
  `iPadTodaySupportViews.swift` says all three kept types are built only by the two-pane host and "a
  compact width cannot reach any of them". True for two of the three. **False for `iPadTodaySidePanel`**:
  `iOSTodayView.swift:24` names it in an `@AppStorage` default — a stored-property initialiser evaluated
  at every width — and `iOSCompactTabShell`, `iOSTasksTabView` and `iOSSearchView` all construct that
  view at compact width. [[T-283]]'s test silently omitted the enum from its reachability check, which is
  why nothing said so. Either rename it or correct the comment.
  **Closed 2026-08-30 **by renaming, not by softening the comment**. `iPadTodaySidePanel` → `iOSTodaySidePanel` (5 references), value-preserving: the storage key was already the honest `ios.today.sidePanel` and the raw values are untouched, so nothing persisted moves. The argument for renaming: keeping the name required **three permanent pieces of machinery** — a carve-out paragraph, a by-name exclusion inside the sweep's detector, and a dedicated test recording the exception — to preserve four characters, and "iPad-only, except when it isn't" is not a meaning. **The general guard was cheap and precise, so it was built**: `everyIPadPrefixedTypeIsBuiltOnlyFromAWidthGatedHost` **derives** every `iPad`-prefixed declaration from source rather than reading a hand-typed list — which is exactly how [[T-283]] lost this one — and it immediately turned up a fourth uncovered type, `iPadMacStyleRootShell`, which passes but whose passing was not previously known. **Scope stated in the test's own doc**: it catches a *name* against a *gate*, so [[T-352]]'s family (prose inventing a mechanism for something that names no symbol) is still a read, not a guard.**

- [T-86] **Agents building into the shared DerivedData can crash a running Mac app.** On 2026-08-17
  the user hit "Cadence quit unexpectedly" — `EXC_BREAKPOINT` on the main thread, five seconds after
  launch. **Not app code:** the whole backtrace is `dyld` → `libSystem_initializer` →
  `_libsecinit_appsandbox`, i.e. App Sandbox setup failing *before `main()` runs*, and the app
  bundle had vanished from `Build/Products/Debug/` by the time it was inspected — a concurrent agent
  clean build wiped it under the running process. A fresh build into a private `derivedDataPath`
  launched and stayed up. Two agents had already reported `build.db is locked` from the same
  contention. **Mitigation:** every agent brief should require a private `-derivedDataPath`, which
  most already do ad hoc; worth making standing in `AGENTS.md`. Nothing to fix in the app.
  **Closed 2026-08-30. The contention itself cannot be removed — the shared DerivedData is one mutable directory by design — so what was removed is the **exposure**, and it was larger than the ticket knew: **the private-path rule was prose only, and the repo's own runbooks violated it in five invocations** (README build *and* test, apple-release-readiness build *and* test, the distribution archive). Anyone following the README was building into the shared DerivedData. Two measurements sharpen it: a read-only `xcodebuild -showBuildSettings` **also** creates a shared entry with `Logs/`, `SourcePackages/` and `PIFCache`, so "it was only a query" is not a defence; and the entry is keyed to the **project path**, so an unflagged run from the repo root shares the exact entry the user's Xcode uses. Now enforced by `CadenceBuildInvocationHygieneTests`, which sweeps every markdown fence and shell script, plus `scripts/xcb.sh`, which supplies a private path, refuses a shared one, and reports leakage afterwards. **Known hole, declared**: the guard matches a bare `build`/`test` token, so a script assembling its action in a variable would not be classified as a build action.**

- [T-117] **A project-file lock is a new disguise in the T-86 family — now confirmed twice.** Builds
  deadlock in `NSFileCoordinator` reading `Cadence.xcodeproj`, 20+ minutes at 0% CPU, with an empty
  derivedDataPath. A `sample` of a stalled process caught it in `_blockOnAccessClaim` on the project
  file, with a concurrent agent's `xcodebuild` holding it and the user's Xcode — open six days —
  also claiming it. **It produces no diagnostic at all**: the run simply sits at the "Command line
  invocation" line, which reads as a broken checkout. Distinct from DerivedData contention.
  Mitigations: quit Xcode when a batch of agents is running, and treat total silence as this rather
  than as a failure to be debugged.
  Related but *not* universal: one agent found a fresh private DerivedData could not start because
  package resolution is sandbox-blocked, and worked around it with
  `-clonedSourcePackagesDirPath` + `-disableAutomaticPackageResolution`. Recorded as situational
  rather than as a rule — my own fresh-DD runs this session resolved packages fine, so do not add
  those flags by default.
  **Closed 2026-08-30 **with a detector, because a preflight is impossible.** Measured: `lsof` on `Cadence.xcodeproj/project.pbxproj` returns **nothing** while a real `xcodebuild` holds it — an `NSFileCoordinator` claim is not an open fd — so any `lsof` preflight would report "clear" every time, which is worse than having none. The only observable is the stalled process's own stack, so `scripts/xcb.sh` runs a watchdog that samples its own child when the log stops growing and CPU sits at zero, printing `T-117 CONFIRMED: blocked in NSFileCoordinator` or the top frames of whatever else it is stuck in. **It never kills anything.** The hazard stops being silent, which is all this ticket had downgraded itself to asking for.**

- [T-237] **`git archive HEAD` over the whole tree runs at ~5 KB/s here; root cause unconfirmed.**
  Measured 2026-08-22 and worked around rather than fixed — `AGENTS.md` now prescribes
  `rsync` + `git show HEAD:<path>` restore instead. The workaround has a real ongoing cost: the
  restore step is manual, and an agent that skips it verifies another agent's in-flight code while
  believing it tested HEAD. That is worth removing, not just documenting.
  Evidence: one file (`git archive --format=tar HEAD -- AGENTS.md`) is instant; the whole tree
  sampled at 10s intervals gave 1259520 → 1310720 → 1372160 → 1484800 → 1525760 → 1576960 bytes,
  ~25 min for a 15 MB tree, and emits a **0-byte file** for the first minutes so it reads as a hang
  (two runs were killed at 2 and 3 minutes for that reason). The repo is healthy —
  `git rev-parse HEAD` is 0.018s.
  Prime suspect, **not confirmed**: a global `filter.lfs` with `required = true` while `git-lfs` is
  not installed (`git lfs version` → "not a git command"). Against that theory,
  `-c filter.lfs.process= -c filter.lfs.required=false` did not help, and the repo has no
  `.gitattributes`. Next steps: `git config --global --get-regexp '^filter\.'`, then try
  `GIT_TRACE=1 GIT_TRACE_PERFORMANCE=1 git archive HEAD > /dev/null` to see where the time goes, and
  test whether the slowness follows the global config into a scratch repo. Fixing it restores a
  one-command isolation step for every future agent.
  **Closed 2026-08-30 **as not reproducible — and the prime suspect is disproven, not merely unreproduced.** `git archive --format=tar HEAD` runs in **0.06s** for a 13.4 MB / 910-file tree (~220 MB/s), verified to `~/Desktop`, to `/private/tmp`, and under concurrent disk load; the ticket's ~25 min for 15 MB is a 20,000x discrepancy. The blamed `filter.lfs.required=true` is **still set**, `git-lfs` is **still absent**, and `~/.gitconfig` is unchanged since 2026-05-08 — byte-identical to the original measurement — so it cannot have been the cause. Also ruled out: the protected-`~/Desktop` theory (same APFS volume as `/private/tmp`, detached file provider), security software (0 system extensions), and repo shape (2 packs, 3.8 MB, `unpack_trees` at 0.006s). **The original numbers were real**: every sampled size is an exact multiple of the 10240-byte tar record, implying ~1.6s of per-file stall across 910 files. The mechanism is no longer observable (the unified log retains ~1 day) and was almost certainly a transient per-file check on the host. No maintenance was run and none is needed. **The workaround it justified is now retired** — see the closure note below.**

- [T-507] **iOS saved links throw away the shared persistence helper's failure signal** (Codex, P2,
  measured). `iOS/iOSListSupportViews.swift:687` calls `try? CadenceSavedLinkPersistence.insert(...)`
  then clears the title, clears the URL and closes the add form **regardless**; `:699` does the same for
  delete. The helper (`Shared/CadenceSavedLinkPersistence.swift:35-45`) already commits and rolls back
  correctly — the caller discards the answer. **macOS is already right**: `LinksView.swift:109-114`
  catches insert failure and leaves the form open, `:125-130` catches delete. Mirror it, add an iOS
  `actionError` notice near the saved-links section, and pin so iOS cannot reintroduce `try?`. Same
  shape as [[T-470]]/[[T-471]].
  **Closed 2026-08-30. iOS `addLink` catches and leaves the form open with an `actionError`, mirroring `LinksView.swift:109-114`; `delete(_:)` reports too, **even though the rule cannot see it** — its mutation leaves `noSwallowedSaveIsFollowedByADismissOrACompletionHandler` silent, confirming the ticket's note that the report half is blind to a swallow with nothing after it. The `reportExemptions` entry is deleted in the same change, and the mutation that restores the `try?` kills that guard — proof the deletion was live rather than cosmetic.**

- [T-509] **Saved-link URL normalisation mangles an uppercase scheme, on both platforms** (Codex, P3,
  measured). `macOS/Views/LinksView.swift:99` and `iOS/iOSListSupportViews.swift:677` both test
  `hasPrefix("http://")`/`hasPrefix("https://")` **case-sensitively**, so `HTTPS://example.com` becomes
  `https://HTTPS://example.com`. Two hand-rolled checks, one defect, twice — [[T-374]]'s shape. One
  shared normalisation helper read by both, pinned on lowercase, uppercase, mixed case, leading/trailing
  whitespace and scheme-less input.
  **Closed 2026-08-30. One `CadenceSavedLinkURL` in `Shared/` — which the macOS test target compiles, so **both platforms' rule is actually executed** rather than asserted by scan — read by both add forms, absorbing trim, blank-check and scheme so the guard cannot be spelled two ways. **It deliberately does not re-case what the user typed**: `HTTPS://example.com` stays as typed, because the defect was *guessing at a missing scheme*, not casing. `ftp://` remains treated as scheme-less, pinned as existing behaviour rather than quietly changed.**

- [T-516] **Tests are stranding `UserDefaults` plists in the real app container, and it is live.**
  [[T-480]] fixed `withTemporaryDefaults` to derive its suite name from `#function`, but four files still
  roll their own `UUID()` suite name and bypass it. **Measured in the app's own container: 7,727
  preference plists, 316 written in the last 48 hours** — bare `<UUID>.plist`,
  `cadence.tests.external-write.<UUID>`, `cadence.tests.privacy-reset.<UUID>` and
  `com.haoranwei.Cadence.tests.t15.<UUID>`, totalling ~30 MB and growing every run. Sites:
  `CalendarDateMemoryTests.swift:24,174,299,427,459,492` (bare UUID, and `freshDefaults` never removes
  the domain), `CadenceExternalWriteReconcileTests.swift:76,107,134`,
  `CadencePrivacyDataResetSurfaceTests.swift:130`, `CadenceAccentPaletteTests.swift:324`. Each should
  call `withTemporaryDefaults(_:)`. Pin it in [[T-485]]'s shape — no test file may pass a
  `UUID()`-derived suite name to `UserDefaults(suiteName:)` — since the helper's whole point is that the
  file count is bounded at one per test forever. **The existing 7,727 are the user's to delete**; do not
  remove files from that container without asking.
  **Closed 2026-08-30. Four files routed through `withTemporaryDefaults`; `CalendarDateMemoryTests`' `freshDefaults(_ name: String = UUID().uuidString)` and its `removePersistentDomain(forName: defaults.description)` — **which named a suite that has never existed** — are both gone. The helper gained a generic `opening:` overload so a `UserDefaults` *subclass* double can use it, which a default argument could not do. **The rule is wider than the ticket asked, and each widening was forced by a measurement**: three of the four sites passed the suite name **positionally** into a local helper, so a rule reading only the literal `suiteName:` argument would have named **one file of four**; the helper's own `scope` argument is covered too, because routing through the helper and then handing it a `UUID()` scope looks like the fix and leaks identically. **Not measured**: the container's file count — the existing ~7,700 files are untouched and are the user's to remove.**

- [T-527] **macOS Saved Links has four icon-only buttons and zero accessible labels** (Codex, P3; source
  measured, VoiceOver inferred). `macOS/Views/LinksView.swift` contains **4 `Image(systemName:)` buttons,
  0 `.accessibilityLabel` and 0 `.help`** — verified. The header add button (`:34-40`), the row open-link
  button (`:219-228`) and the row delete button (`:230-235`). Same shape as [[T-472]], which established
  that the durable half is naming the parameter `accessibilityLabel` rather than `help`, since a
  parameter called `help` is what tells the next author the string is tooltip-only. Neither T-472 nor
  [[T-484]] covered this file. **Claim only that the label is set** — nothing has launched the app.
  **Closed 2026-08-30, folded into [[T-509]]'s change because it was cheap. New `cadenceControlLabel(_:)` beside `CadenceIconButton`, applied to the header add, row open and row delete buttons. **Correction to the audit**: the file has 4 `Image(systemName:)` but only **3 are buttons** — the fourth is `LinkRow`'s leading decorative glyph, sitting beside the title and URL it would otherwise repeat, and it is deliberately left alone. The inventory is pinned at 4 icons / 3 labels so the next author has to re-decide rather than drift. **Claim is only that the label is set**, in the shape SwiftUI reads it; nothing launched the app.**

- [T-506] **macOS note export can silently fail *after* the user picks a destination** (Codex, P2,
  measured). `macOS/Services/NoteExportService.swift:39,46` write markdown and PDF bytes with `try?`;
  a failed write is swallowed and no UI state records it, so the user picks a folder, sees nothing, and
  has no file. **Three correct patterns already exist** — `iOS/iOSNoteExportMenu.swift:82-85` reports
  `fileExporter` failure, and both data-export sections
  (`macOS/Views/SettingsDataSafetySection.swift:118-126`, `iOS/iOSDataExportSettingsSection.swift:79-87`)
  report theirs. Return/report the error through the macOS caller, then pin it. **Note this is a file
  write, not a `save()`** — see [[T-508]].
  **Closed 2026-08-30, **and there were two silent failures, not one**: the writes used `try?`, *and* a PDF that failed to render left through a bare `guard … else { return }`. Both meant a user who had already chosen a destination got no file and no message. The **service** reports rather than the caller, because the note action picker calls `dismissPicker()` *before* `export` and the write happens later still inside the save-panel completion — by the time there is anything to report, the caller has no sheet left. New shared failure vocabulary in `CadenceNoteExportSupport`, adopted by iOS too. [[T-508]] deliberately excluded `write(to:)` from the `try? save()` rule, so this shape is swept separately — **and that sweep confirmed these two were the only swallowed writes in `Cadence/`.****

- [T-514] **`iOSTaskPlacementBreadcrumb` is the third instance of the display/save split, and the
  worst-reading one.** Found while closing [[T-488]]. `iOSTaskDetailSheet.loadContainerSelection()` sets
  `"area:<id>"` from the task's real area and `selectedArea` resolves against unfiltered `areas`, but the
  breadcrumb (`iOS/iOSTaskDetailComponents.swift:106`) resolves against `activeAreas` and falls through
  to **"Inbox"**. So **a task in a completed or archived list claims to be in the Inbox**, and
  `iOSContainerChoicePopover` offers only active lists so it cannot be moved out.
  `iOSTaskRowActionViews.swift:500-504` feeds the same popover. **Not a `CadencePickerSupport` drop-in** —
  it is a grouped three-way Inbox/Area/Project control, so it needs `selectable(_:selectedID:)` applied
  to both arrays plus the breadcrumb reading unfiltered.
  **Closed 2026-08-30, **observed on a simulator rather than inferred**. On `b8ad9b6` a task in the archived area "Old Ops" showed breadcrumb **"Inbox"** and a picker offering **only "Inbox"** — no row for where the task actually was; after, "Old Ops" and a checked "Old Ops" row. All four `iOSContainerChoicePopover` call sites take the unfiltered arrays and the control narrows itself via `selectable(_:selectedID:)` on **both**; the breadcrumb resolves through the same existence-not-activity resolver the save already used. `Project` is a `CadencePickable` now, so the rule is stated once for its third type — the mutation swapping its offerability to Context's `!isArchived` kills three tests by name. The row context menu's Move to List had the same hole and took the same narrowing.**

- [T-519] **`iOSFocusView`'s detail pane says "Today tasks will appear here" while they are already
  appearing beside it.** With nothing selected it draws "Ready when you are / Today tasks will appear
  here." — but the tasks appear in the **list pane next to it**, and this shows at regular width while
  that pane is full. A false statement in the common case. The house pattern for a detail pane with no
  selection is "Select an item from the list." (`iOSFeatureComponents:529`) / "Select a note". Needs a
  wording decision.
  **Closed 2026-08-30, **and the ticket's stated case is the rarer of two**. Because `selectedItem` falls back to `pickItems.first`, the branch is reached either with nothing ready — and then the picker pane *beside* it was showing the shared focus sentence at the same moment, so **the page made two differently worded promises about itself**, which is the common case — or with a chosen subject deleted while the picker still lists others, which is the ticket's falsehood. Branch one now says the shared sentence; branch two uses the house `iOSFeatureEmptyDetail`. "Today tasks will appear here." retired app-wide. See [[T-533]] for the same defect in its original form on Goals and Habits.**

- [T-521] **A shared component tells macOS VoiceOver to double tap.** `CadenceNotesListSupport`'s folding
  month header sets `.accessibilityHint("Double tap to expand")`, and it is a shared component with
  `.onHover` — so on macOS VoiceOver reads a gesture that is not its activation gesture. Same family as
  [[T-472]]/[[T-484]] but a *hint* rather than a missing label.
  **Closed 2026-08-30 **with the weaker claim kept honestly.** Hint reworded to state the outcome ("Expands to show this month's notes."), matching `CadenceStartupIssueBannerModel`, the app's other shared expand/collapse control; premise verified rather than assumed — `NotesFoldableListColumn` places this header on four macOS Notes pages plus the iPad pane and the iPhone list. **The announcement itself is still not measured**: the agent launched a debug build and found it vends **no AX window tree** (System Events sees only `AXMenuBar`, zero windows, via both a direct `exec` and `open -n --env`), and it refused to enable VoiceOver because that means changing the user's system settings. So the claim stays "the hint is set", as in [[T-472]]/[[T-484]].**

- [T-526] **The iOS Lists empty state points a fresh user at a section that is not on screen** (Codex,
  P3, measured). `iOS/iOSListViews.swift:301` and `iOS/iOSListsRegularPane.swift:41` both say "Create an
  area or project here, or **restore one from Archived**." unconditionally — but the Archived section is
  only drawn when `!archivedAreas.isEmpty || !archivedProjects.isEmpty` (`iOSListViews.swift:256`). On a
  fresh or fully emptied store there is nothing archived, so the copy names a section the user cannot
  see. **The correct pattern is already in the same app**: `iOSSettingsView.swift:307-311` does not
  mention archived restore. Make the clause conditional on the same predicate that draws the section,
  in both shells, and pin the first-launch wording.
  **Closed 2026-08-30. `activeListsSubtitle(hasArchived:)` is a function now, in the shape `isNarrowedToEmpty` already uses, so a call site cannot take the sentence without answering the question. Both shells hold the predicate once as `hasArchivedLists`, read by **both** the empty state and the section that draws — the two-independent-copies shape that caused the drift is gone, and a test pins the expression appears exactly once per file.**

- [T-528] **DECIDE: the default-tag seed reads "store is empty" as "this user has never had tags."**
  (P2, measured.) `TagSupport.seedDefaultTags` has **no latch** — verified, zero `UserDefaults`/`hasSeeded`
  references in the file — and `PersistenceController.swift:87` runs it on **every** launch. Its only
  signal is whether a tag with each default slug is present. Two reachable symptoms from one cause:
  **Rename — reachable today, one device, no CloudKit at all.** macOS Settings > Tags has a pencil on
  every row, and `SettingsTagsSection.saveEdits` writes `tag.slug = TagSupport.slug(for: name)`. Rename
  `bug` to `Defect` and the **next launch re-seeds `bug` beside it**: eight tags where the user curated
  seven, the old name back in the `#` picker and every tag filter.
  **Archive — reachable on a reinstall or a second device.** The store opens before CloudKit lands, so
  the seed mints an *active* `bug` while the user's archived, recoloured one is in flight; when it
  arrives `mergeTagMetadata` resolves `target.isArchived && source.isArchived` (`TagSupport.swift:314`)
  with the fresh row as target, so the answer is `false`. **A tag the user archived comes back, active,
  in the seed's colour, and syncs that to every device.**
  **The sharp framing: this sits twelve lines from code that argues the opposite.**
  `DataIntegrityRepairService`'s own doc comment refuses an orphan sweep precisely because
  `performStartupMaintenance` runs with no gate on sync state and "it is the *empty* store that would
  delete the most". Three of the four startup passes are written to be inert against a store that is
  empty only because sync has not landed; **the fourth inserts because of it.**
  Pinned by `renamingADefaultTagBringsTheOriginalBackOnTheNextLaunch` and
  `theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet`, which encode *current* behaviour and
  go red the moment the seed learns to tell the two stores apart. Options: a `UserDefaults` seeded-latch,
  a sync-state gate, or seed-on-demand. `mergeTagMetadata`'s `&&` is **not** independently wrong — an
  active duplicate legitimately un-archives — so do not "fix" it there.
  **Closed 2026-08-30 **by seed-on-demand, and confirmed by looking before the fix**: launched a private-store build, renamed `bug` to `Defect` exactly as `SettingsTagsSection.saveEdits` writes it, relaunched — **7 tags in, 8 out**, `bug` back beside `Defect`. The seed lost every unprompted caller (`performStartupMaintenance`, both Settings > Tags `.onAppear`s, and `CadenceMCPStorePreparation.prepare`, `stepCount` 4→3); `TagSupport.seedDefaultTags` is behaviourally unchanged and still reached from the "Add Defaults" controls that already ship. **Rejected with reasons: the `UserDefaults` latch fixes the rename only** — on a second device there is no latch and no data by construction, so it is absent exactly when it would need to fire, and it is invisible to the MCP server, a separate process opening the same store. **The sync-state gate is not reachable**: the only signal is a notification SwiftData does not expose, it never fires when iCloud is signed out, and the fallback reintroduces the race. `mergeTagMetadata`'s `&&` untouched — an active duplicate legitimately un-archives, so the bug was minting the duplicate. **Cost accepted, stated plainly: a new user's first `#` picker says "No tags"** until they type a name or press Add Defaults — see [[T-532]], which is the macOS half of that.**

- [T-529] **`clearMissingEventLinks` writes where its sibling only reports.** (P3, code path measured,
  the race inferred.) `CalendarLinkedTaskSupport.swift:21-32` runs unattended on every
  `EKEventStoreChanged` (`macOSRootStateSupport.swift:59`, `SchedulePanelDataSupport.swift:28`), fetches
  every `AppTask`, clears `calendarEventID` wherever `event(withIdentifier:)` returns nil, and saves. Its
  only guard is `isAuthorized` — so **"EventKit has not loaded this event yet" and "this event is gone"
  are the same answer.** The neighbouring surface takes the opposite posture: `CadenceCalendarLinkHealth`
  only *reports* a dead link and hands the user a re-pick, and
  `withoutCalendarAccessNothingIsReportedMissing` exists for exactly this false positive.
  **Reachability checked before filing**: `AppTask.calendarEventID` is documented as having no current
  writer, so a new TestFlight tester cannot hit this — it is reachable **only from stores written by an
  earlier build**. But those values are exactly what the reader is kept for, and the clearing is silent,
  irreversible and CloudKit-propagating.
  **Closed 2026-08-30 **by requiring evidence, not by converting the sweep to a reporter.** `CalendarEventLookup` gains `hasLoadedCalendars`, and `canTrustLookupMisses` is that conjoined with `isAuthorized` — so a store that has produced no calendars, which is exactly the state an `EKEventStoreChanged` from a permission grant leaves you in, no longer reads as "every event is gone". The question is split out as `missingEventLinks(in:calendarManager:)`, which reports and writes nothing, so the sibling's posture is reachable from the same rule. **Residue left deliberately**: one account still syncing while others have loaded leaves `allCalendars` non-empty, so a link into that account is still clearable on a miss — per-source evidence is not cheap in EventKit, and no current writer produces a non-empty `calendarEventID`.**

- [T-512] **Two functions build the labels [[T-505]] just declared, and no literal sweep can see them.**
  `iOSListDeletionSupport.swift:40` and `iOSListWindDownSupport.swift:85` are near-identical `name`
  properties returning `"Untitled \(kind.noun)"` / `"Untitled \(noun)"`, where `noun` is
  `"Area"`/`"Project"`/`"Context"` — so **at runtime they produce exactly `defaultAreaName`,
  `defaultProjectName` and `defaultContextName`.** Renaming any of those three constants leaves these
  two behind, silently. This is the [[T-500]] shape (a duplicated *function*) doubled by the sweep's own
  stated exclusion: interpolated literals are dropped by the harvest regex **by construction**. Both
  files' comments already claim they use "the same 'Untitled …' fallback" as each other — the claim is
  true and nothing holds it true.
  **Closed 2026-08-30 — **and the fix is the smaller half**. Both builders read the constants now, but the shape is held by `noSourceFileBuildsAPlaceholderLabelByInterpolation`, whose needle is **derived** from `defaultCompactTitle` rather than spelled, so renaming the family **re-points the rule instead of emptying it**. A mutation renaming `defaultAreaName` turns four tests red — the property the ticket said nothing held. Putting the mapping on `CadenceListDeletionKind` in `Shared/` was load-bearing: it is what let the macOS test target **evaluate** the labels rather than only scan for them.**

- [T-513] **Two copy defects [[T-505]] deliberately did not launder.** (1) `iOSFeatureDetailViews.swift:83`
  labels an untitled **milestone** `"Untitled Goal"` — inside `iOSEditorSection(title: "Milestones")`,
  iterating `milestones` — while `iOSTaskDetailSheetSections.swift:65,77` and
  `iOSTaskRowActionViews.swift:395` say `"Untitled Milestone"` for the same kind of row. (2)
  `"Untitled task"` is lower-cased at `SchedulePanelComponents.swift:88` and
  `macOSRootSupportViews.swift:527` (and as a `TextField` placeholder at
  `iOSTaskDetailComponents.swift:72`) against `defaultTaskTitle`'s capital. **Both change what a user
  reads and neither is decidable from the literal**, so both were left visible rather than folded into a
  constant — which would have frozen the drift under a fix that looks like cleanup.
  **Closed 2026-08-30. (1) fixed: the milestone row said `defaultGoalTitle` inside a "Milestones" section iterating `milestones` — the residue was the wrong **constant**, since [[T-505]] had already de-literalised the line. (2) **decided rather than deferred**: the two `Text(...)` sites are labels over a *value*, and 18 other surfaces render that value as "Untitled Task", so they read `defaultDisplayTitle` now. `iOSTaskDetailComponents.swift:72` is a `TextField` **prompt** — a different piece of copy, and every other title prompt in the app is a noun phrase — so it stays, recorded with its reason. See [[T-539]].**

- [T-515] **The rest of the "Untitled …" family, below [[T-505]]'s ≥2-files rule.** `"Untitled List"`
  (`TaskBundlePickerSupportViews.swift:179,211` — 2 sites, one file), `"Untitled subtask"`
  (`MarkdownTaskEmbedDrawingSupport.swift:429,511` — 2 sites, one file), `"Untitled Column"`
  (`iOSColumnWindDownSupport.swift:50` — 1 site). Real but weaker: **a constant with one call site is a
  name, not a de-duplication.** Recorded so the omission is a decision rather than an oversight.
  **Closed 2026-08-30 **by declining to widen the rule**. A constant with one call site is a name, not a de-duplication, and **no repetition threshold ever reaches `"Untitled Column"`'s single site** — so widening was the wrong instrument for the case that motivated the ticket. Replaced with the sweep's **dual**: `everyPlaceholderLabelInTheAppIsDeclaredOrRecorded` requires every `"Untitled …"` in all three targets to be declared or listed with a reason, keyed by **site** so a recorded label cannot spread. The existing sweep asks "is a declared constant re-typed?"; this asks "is every label declared?" — together there is no way left to produce one without reading a constant or writing down why not.**

- [T-520] **`CadenceTodayPresentationSupport.emptyScheduleHint` asks for a tap, from `Shared/`.** It ends
  "…tap an hour to schedule one." and lives in `Cadence/Shared/`, but has exactly **one** reader,
  `iOSTodaySchedulePanel`. Correct today, wrong the moment a Mac surface picks it up. Move it to an
  iOS-only constant or reword it. [[T-528]]'s `noMacReachableCopyAsksForATouchGesture` sweep covers
  `Cadence/macOS/` only and structurally cannot see this one.
  **Closed 2026-08-30 — **it was never actually shared**. macOS's `SchedulePanel` draws no empty state at all, so the sentence had one reader and was correct only because no Mac surface had picked it up yet. Moved to `Cadence/iOS/iOSSchedulePanelCopy.swift`, wording unchanged, deliberately outside `#if os(iOS)` so the macOS target pins the value rather than reading source. **The gap is closed generally**: `noDesktopCopyAsksForATouchGesture` is now `noMacReachableCopyAsksForATouchGesture` and walks `Cadence/Shared/` too — a shared folder's copy must be true on the desktop whether or not the desktop reads it yet. It was the only live offender there.**

- [T-522] **Converge `"List not found"` and its subtitle, then delete the allowlist entry.** They are
  duplicated in `ListDetailView.swift` and `iOSRootSidebar.swift` because
  `CadenceDeletedSelectionGuardTests.theMacMissingListStateReusesTheSentenceIOSAlreadyShips`
  **deliberately pins them as matching literals**, so converging means rewriting that suite's assertion
  to read the constant instead. Doing so removes the single entry in `CadenceEmptyStateAuditTests`'
  `emptyStateDuplicateAllowance`.
  **Closed 2026-08-30, **allowance and its staleness check both deleted**. `missingListTitle`/`missingListSubtitle` read by both views; the glyph stays a literal because a symbol name is a picture, not a sentence. `theMacMissingListStateReusesTheSentenceIOSAlreadyShips` was **rewritten rather than removed** — it asserts convergence, which is what pinning matching literals was standing in for. `noEmptyStateSentenceIsSpelledInTwoFiles` is unconditional now and the tree has zero duplicates.**

- [T-523] **`iOSGoalAttachListsSheet` branches on an untrimmed query.** It is the one *correct*
  filter-aware empty state in the app, but a whitespace-only query still reports "No matching lists".
  One line: `CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: query, filterNarrows: false)`.
  **Closed 2026-08-30, and the behavioural reason is sharper than the ticket's: `GoalLinkPresentation.candidateGroups` **trims before matching**, so a whitespace query returns the whole library — meaning the only reader `query.isEmpty` could mislead was one with **no lists at all**, greeted on a first run with "No matching lists / Nothing matches that search."**

- [T-525] **`GoalTimelineView`'s first-run subtitle overstates what is required.** "Create a goal, then
  set its date range." — but a goal with no end date still gets a roadmap row, rendered "No date", so
  creating one is sufficient. Copy deliberately preserved as-is by the empty-state work rather than
  reworded under a change that looked like cleanup.
  **Closed 2026-08-30, **premise verified by running rather than reading**. `rows` is built from `GoalMissionGrouping.groups`, which reads no date at all, so one undated goal already leaves the empty state — it draws a rail row with a "No date" chip; only the *bar* needs both dates. New copy names a button this page's own toolbar draws, pinned by regex, and the old sentence is a `cadenceRetiredCopy` entry so it is swept app-wide rather than only here.**

- [T-532] **macOS tag pickers give a fresh store no route to the default set.** The direct consequence of
  [[T-528]]'s seed-on-demand decision, and a parity gap: `TaskTitleInlineTagPicker.swift:40` and
  `TagPickerPopoverViews.swift:114` both render a bare `"No tags"`, while
  `iOSTaskDetailComponents.swift:400` offers **"Add Default Tags"** in exactly that state. So a brand-new
  macOS user meets "No tags" with no affordance — they can type to create inline or go to Settings, but
  **the iOS pattern is the better one and macOS should match it.** Worth doing before a TestFlight build
  if T-528's decision stands.
  **Closed 2026-08-30. Both macOS pickers ask one `TagPickerPlaceholder.resolve` and render one row, offering **Add Default Tags** — iOS's wording — when the catalogue is empty. **The old condition read the *filtered* list**, which is why one sentence covered two unrelated states; `TaskTitleInlineTagPicker` is handed `hasActiveTags` now rather than inferring it, and the mutation reverting that inference kills a test by name. Two truths fixed in passing: a query that matched nothing says "No matching tags" (tags exist, so "No tags" was false), and the restore row no longer draws "No tags" beneath itself. **The seed call is in a Button action and nowhere else** — [[T-528]]'s `noUnpromptedCodePathSeedsTheDefaultTags` gains this file, and the mutation adding an `.onAppear` beside it kills that guard, so it demonstrably still bites. **Cost stated: the offer is click-only**, as the sentence it replaces was.**

- [T-533] **Goals and Habits detail panes have [[T-519]]'s defect in its original form.**
  `iOSFeatureViews.swift:225` and `:398` draw "Select an item from the list." **unconditionally**, while
  the `listPane` beside them shows "No goals yet" / its habits equivalent on a fresh store. **At iPad
  regular width a new user sees "Select an item from the list." next to a list with no items.** Same
  one-line fix shape as `unselectedDetail`; not covered by the T-519 test, which is scoped to
  `iOSFocusView`.
  **Closed 2026-08-30, **observed on an iPad Pro simulator before and after** — "No goals yet" beside "No goal selected / Select an item from the list.", then both panes saying the chooser's own sentence. **The ticket's fix shape was right but its analogy was wrong**: [[T-519]] needed `if pickItems.isEmpty` because its picker can be full with nothing selected, and these two panes **cannot reach that state** — `selected` falls back through the whole collection, so `nil` means the collection is empty, which is the same `count == 0` the chooser already draws its empty panel on. A copied guard would have been a branch with a dead side. Both fallback expressions are pinned so that stops being true loudly. Copy is now one `iOSFeatureEmptyState` per screen read by **both** panes.**

- [T-534] **The macOS container picker is the other half of [[T-514]].**
  `ContainerPickerFilterSupport.groups` (`macOS/Views/ContainerPickerSupportViews.swift:26-31`) filters
  `$0.isActive`, so a task in an archived or completed list gets a popover with **no row for where it
  is**. Milder than iOS — `ContainerPickerBadge.label` already resolves unfiltered, so the *name* is
  right and only the correction affordance is missing. Same fix shape: `selectable(_:selectedID:)`,
  which needs the picker to learn the current selection. **Also visible in the same function and
  unmeasured**: the grouping is `contexts.compactMap { … $0.context?.id == context.id }` and
  `Area.context` defaults to `nil`, so **a context-less area appears in no group at all.**
  **Closed 2026-08-30, **and the ticket's unmeasured second defect is the larger half**. Headline took the [[T-514]] shape: `groups` learns a **required** `selection:` and narrows both arrays through `selectable(_:selectedID:)`; mutations neutering the areas and the projects halves kill *different* tests, so the fix demonstrably reaches both. **The context-less defect is real — there is no fallback bucket in this control** (the body draws Inbox then `ForEach(groups)` and nothing else) **but the app already ships one**: `CadenceSidebarLists.sections` gives these models an "Other" section on iPad, and its doc comment already named the macOS gap. The bucket reuses that constant, keyed on the *offered* context set, which also catches a list whose context was never handed to the picker. **The reachability is asymmetric and that is the sharp part**: iOS offers "None" unconditionally in every mode and writes it; macOS's create sheet requires a context and its edit sheet has **no context control at all** — so the Mac inherits by sync a list it can neither file into nor correct. **Not observed on screen**, and deliberately: a debug build vends no AX tree, so there is no way to open the popover and a screenshot would be zero evidence. See [[T-538]] for the sidebar, which is worse.**

- [T-537] **`clearMissingEventLinks` fetches every `AppTask` before its guard.**
  `CalendarLinkedTaskSupport.swift:77-84` builds a full `FetchDescriptor<AppTask>` on **every**
  `EKEventStoreChanged` and only then reaches `canTrustLookupMisses`. Hoisting the guard above the fetch
  is one line.
  **Closed 2026-08-30, guard hoisted above the fetch. [[T-529]]'s `hasLoadedCalendars` reasoning untouched and the array overload still guards, so this is the early check rather than the only one. **Pinned as source order, not behaviour, and deliberately**: the fetch is `modelContext.fetch` and no fake can count it. The assertion is scoped to that overload's own body and was validated against unmodified source first. The mutation removing the guard kills **only** that test — all six neighbouring behaviour tests stay green, which is what shows the change moved *when* the question is asked and not what it answers.**

- [T-462] *(narrowed 2026-08-30, measured by replaying all 210 revisions of the file: the gap is **200, not 284**. All 200 are recoverable verbatim, but that is ~33k tokens onto a file whose purpose is to be cheap to search — and **87.5% were removed by bookkeeping commits that changed no Swift**, so each entry's SHA would need its own bisect: 200 investigations for a file half of which would be blank. **Do not backfill.** The cheap half is done — 32 entries reading `(title not recovered)` were unsearchable and all 32 titles were recovered from the file's own revisions (the earlier reconstruction had searched commit *messages*), and the header count, which had never been true at any revision, now reads the real 177. Residue: [[T-501]].)* **`docs/TODO_DONE.md` had no `T-4xx` entry at all until `ca06ad1`+1.** Eighty-five tickets
  closed in this session were removed from Open and never archived, and the same gap runs back to
  T-01 — **284 in total**. Today's 85 are now reconstructed from git history; the older 199 are not.
  Either backfill them the same way or state that the archive begins at this session and stop
  implying otherwise.
  **Closed 2026-08-31 — **the last residue was one sentence, and it is now in the file.** Everything else measured as genuinely done: the header count is truthfully 177, all 32 `(title not recovered)` placeholders are gone, and [[T-501]] fixed the five wrong SHAs. What remained was the ticket's *other* branch: the archive silently implies completeness. Measured coverage is a **hard cliff, not diffuse thinning** — 96% of T-300..399 is accounted for, against **10–13% of T-1..199**, with 211 unaccounted ids below T-300 and 39 above it. Yet the header instructs *"Search here before filing anything that sounds familiar"*, which below ~T-200 **cannot work**: a search returns nothing whether or not the ticket was closed — precisely the re-filing failure the header exists to prevent. The header now states where the archive begins and that a miss below ~T-200 is not evidence a ticket is new.**

- [T-518] **The MCP plugin runner rebuilds into a path it may be executing from.**
  `plugins/cadence-mcp/scripts/run-cadence-mcp.sh` defaults `DERIVED_DATA_PATH` to the repo-local
  `.codex-build` and then `exec`s `$DD/Build/Products/Debug/CadenceMCPServer`. A rebuild into that path
  while another plugin process is running the binary is [[T-86]] for the MCP server. **The warm reuse
  looks deliberate** — the script's own comment says so — so this is a flag for a decision rather than
  a defect to fix blind.
  **Closed 2026-08-30 — **the premise does not reproduce, and the mechanism explains why.** `otool -L` shows the binary links only `/usr/lib` and `/System/Library`: the SPM dependencies are **statically linked** and there is no `.dylib` or `.framework` under `Build/Products/`, so the image is self-contained at `exec`. All three failure modes tested twice: **rebuild while a server is live** — the link *replaces the file* (inode changed) and the live process kept answering `tools/list` correctly; **`xcodebuild clean` under a live server** — the binary is deleted from disk and the process is entirely unaffected; **concurrent rebuilds into one path** — both exit 0, no `build.db` lock. **None of corrupt / fail / silently-stale.** This differs from [[T-86]] because the app is a `.app` bundle whose dyld loads frameworks and resources lazily from paths under `Build/Products/`; this target is one self-contained executable. Keep the warm reuse. Residual, real but not what the ticket feared: `set -euo pipefail` means a failed build exits before `exec`, so a broken binary is never run.**

- [T-524] **65 string literals are duplicated across two or more files under `Cadence/`** — measured,
  beyond empty states. The Settings sections duplicate ~15 between
  `iOSCalendarSettingsSection`/`SettingsListManagementSections` and
  `iOSNotificationsSettingsSection`/`SettingsNotificationsSection`, and the recurrence/calendar-scope
  alerts duplicate 4 across three files each. **The [[T-374]] sweep cannot see any of them, because no
  constant exists yet** — that sweep catches a *shared constant re-typed*, not copy that never became
  one. Same convergence job as [[T-528]] at roughly 7x the size.
  **Closed 2026-08-30 across two agents. **Settings half**: 13 literals converged into 13 constants across 5 view files, all now inside the [[T-374]] sweep's harvest — three of six mutation kills came from that sweep rather than the new tests. **Alerts half**: 4 recurrence/calendar-scope sentences, 6 call sites, one `CadenceRecurrenceScopeCopy`. **The divergence check found four drifts behind byte-identical literals**: the macOS connect menu passed its name to `.help` where iOS used `.accessibilityLabel` (fixed — an icon-only Menu named only by a tooltip is [[T-472]] two screens outside the sweep that guards it); the macOS access card draws an **amber warning triangle for the not-yet-asked state** where iOS draws a neutral glyph (iOS is right, filed); the macOS work-hours subtitle names "Weekly calendar views" when the highlight is per day-column **and also appears in the Schedule panel** (filed); and macOS's empty-calendar row has no subtitle against iOS's two-line row (filed). **Exclusions are as load-bearing as the conversions**: `"Apple Calendar"` is one literal for **at least two concepts** across 7 files, so declaring it would create 7 offenders at once. See [[T-543]]–[[T-547]].**

- [T-536] **Two iOS sheets still hand-spell the container token arithmetic.**
  `iOSCalendarQuickCreateSheet.swift:53-65,417-422` and `iOSTaskDetailSheet.swift:48-65` re-derive
  `dropFirst(5)`/`dropFirst(8)` and the untitled-name fallback instead of
  `CadenceTaskComposerSupport.selection(fromToken:)` / `containerName(for:areas:projects:)`. **Not a
  defect** — both already resolve against unfiltered arrays — but it is the [[T-374]] near-copy those
  helpers now exist to remove, and the detail sheet's private members even share the helpers' names.
  **Closed 2026-08-30, **and the divergence check found one**. Two of the sites were equivalent, but `iOSCalendarQuickCreateSheet.containerTitle` tested `name.isEmpty` while the shared helper **trims first** — so a whitespace-only list name rendered as a *blank tile* there and "Untitled Area" on every other surface, and a padded name kept its padding. **Latent, not live**: both list editors normalise on write, so no user could reach it — but adopting the helper closes it in the strictly-correct direction. A **fourth site the ticket did not name** (`CreateGoalSheet.attachInitialList`) was converged too, which is what let the guard assert "exactly the declaring file" instead of carrying an exemption list that would rot.**

- [T-540] **The duplicate-copy audit cannot see any filter-aware empty state.** Found by [[T-522]]'s own
  agent. `CadenceEmptyStateAuditTests`' regex matches a literal placed **directly** after
  `message:`/`title:`/`subtitle:` — so copy behind a `?:` branch is invisible, **and every filter-aware
  empty state in the app is written in exactly that shape.** Two live examples: `"No goals yet"` and
  `"No matching goals"` are spelled in both `GoalsView.swift` and `GoalTimelineView.swift`. Same family as
  the vacuous detectors this session keeps finding, and inside [[T-524]]'s scope.
  **Closed 2026-08-30 — **measured before converging, which is the whole point.** The reader now takes the *whole argument expression* after `message:`/`title:`/`subtitle:` rather than a literal sitting directly after the colon, and matches the label only at the call's top level. Re-measured over `Cadence/`: the old reader saw **11 distinct empty-state literals and 0 duplicates**; the widened one sees **25 and 2** — **14 newly visible, 0 lost, 0 false positives.** Nothing to refuse. The old regex was wrong a second way too, proven by a failing test: it harvested `icon: symbol(for:title:"unused")` as a *title*. The 2 duplicates were `"No goals yet"`/`"No matching goals"`, **byte-identical — one edit from the drift two other pairs were already found in, and nothing in the app could have reported it.** The two *subtitles* stay apart deliberately and are pinned as values: the list has a search field and status picker, the roadmap has one popover button labelled *Filter*, so each sentence is true of its own toolbar.**

- [T-542] **Three exact near-copies of `CadenceTaskComposerSupport.container(of:)` remain.**
  `TasksPanelComponents.swift:371-373`, `SchedulePanelComponents.swift:35-37`,
  `TaskEmbedFieldEditorPopover.swift:244-246` each spell the same three-line task-to-selection getter.
  [[T-534]] added the shared accessor and used it at the new site only, to keep that diff reviewable.
  **Not a defect** — all three are correct — but it is the [[T-374]] near-copy the helper now exists to
  remove, same family as [[T-536]].
  **Closed 2026-08-30. All three getters were logically identical to `container(of:)` — area tested before project in each — so this was pure convergence with no divergence to report. The wiring half of the guard is what catches a *differently-spelled* near-copy: a mutation rewriting one site in different words is killed by the wiring assertion while the shape sweep stays silent, which is [[T-161]]'s rule made mechanical rather than asserted.**

- [T-548] **The duplicate sweep covers 2 of the app's 5 empty-state components, and the other 3 have
  drifted.** `componentNames` lists only `EmptyStateView(` and `iOSEmptyPanel(`;
  `iOSFeatureEmptyState(`, `iOSFeatureEmptyDetail(` and `CadenceInlineEmpty(` are invisible. Measured:
  adding them surfaces **2 more duplicates, and unlike [[T-540]]'s these have already drifted** —
  `"No goals yet"` in 3 files (macOS *"Create a goal for an ongoing direction, then nest milestones inside
  it."* vs iOS *"Create a direction, then nest milestones and habits underneath it."*) and `"No habits
  yet"` in 2. macOS's Goals page **does** show habit counts under a goal, so its sentence is *incomplete
  rather than false*. Choosing the true sentence per platform is a copy decision — **and
  `theGoalsAndHabitsDetailPanesNeverNameAListWithNoItems` pins the iOS spelling at exactly one occurrence,
  so any convergence must edit that test in the same change.**
  **Closed 2026-08-31. **The component set is derived, not listed** — every `struct` under `Cadence/` whose name carries `Empty` or `Placeholder`, harvested through `codeOnly`. Adding names was rejected as the weak fix: the list is exactly what went stale. **2 → 23 components, 0 false positives**, measured *before* converging: HEAD saw 23 literals and **0** duplicates; widened saw 47 and **2**. Both predicted duplicates were live (`"No habits yet"`, `"Select a note"`), plus the `"No goals yet"` **retype** a file-counting sweep structurally cannot see. **Three fail-closed guards** so an uncovered component is a failure rather than a silence — including a *second, structural* derivation (a `View` with glyph + headline + subtitle, `…Row` subtracted **as a rule with zero allowlist entries**) that fails when the two derivations disagree. **M1 reproduces the ticket mechanically**: with the hardcoded two restored, the three coverage guards go red while `noEmptyStateSentenceIsSpelledInTwoFiles` stays **green**. Titles converged; **subtitles reported, not picked** — Goals is a *three-way* split (macOS list, macOS roadmap, iOS) and macOS's is **incomplete rather than false**, since its Goals page does show habit counts.**

- [T-552] **`-only-testing:` with a suite name that does not exist is a green run over zero tests.**
  Measured 2026-08-31: `-only-testing:CadenceTests/<NoSuchSuite>` returns `Executed 0 tests`,
  `** TEST SUCCEEDED **`, `EXIT=0`, **with no warning and no diagnostic**. It takes a *suite* name, not a
  *file* name — and **42 of 256 test files declare more than one suite while 15 declare none matching
  their own basename**, so any run scoped by filename against those exercises nothing and reports
  success. The batch-8 agent nearly filed a false "this sweep is blind" finding from exactly this: the
  same mutation re-scoped to the real suite name killed a test. Rule added to the runbook (assert the log
  contains the test you mutated, not just the exit code); **the durable fix would be a guard that every
  test file declares a suite matching its basename, or a runner that refuses a zero-test run.**
  **Closed 2026-08-31 **by a runner that refuses, not a naming rule.** `scripts/xcb.sh` now exits **4** on a `test` run that executed no test, with a diagnostic naming the filter; `check-test-log <log>` applies the same check to an existing log — verified by hand: real green log → 0, zero-test log → 4. **The basename guard was rejected on measurement**, and the numbers are the argument: **486 of 3750 tests live outside their file's basename suite**, so making `-only-testing:<basename>` *valid* would convert today's **loud zero into a quiet subset** — a run that passes, looks normal, and silently skipped most of the file. It also cannot catch a typo and leaves [[T-465]]'s wrong-sibling case untouched. **The ticket's own figures did not reproduce**: actual is 257 files, 33 multi-suite, **14** basename-mismatched — 13 of them multi-suite, so "rename the 15" was really "rename one, restructure thirteen". The detector counts per-test result lines and **deliberately not** the `Executed N tests` summary, because a run that dies before any test never prints that line — keying on it would read total silence as a full run.**

- [T-553] **Three more absence sweeps whose needle nothing can witness.** Same shape as the blind sweep
  batch 8 fixed, smaller blast radius — each needs a `CadenceScanInstrument` with a literal fixture:
  `CadenceColumnWindDownSurfaceTests.iOSWindsDownAColumnThroughTheSharedServiceFromOnePlaceOnly`
  (`$draft.isArchived`/`$draft.isCompleted`, **0 occurrences repo-wide**),
  `CadenceBundleInspectorHostTests.theBundleHostAsksTheOneSharedRuleAboutTheTwoFactsItCanSee`
  (`CadenceTaskInspectorPresentation`, comment-only), and
  `CadenceSharedBoardChromeTests.theMonthGridsWeekdayRowHasNoSizeKnobLeft` (`weekdaySymbolSize`,
  comment-only). Also: `CadenceSidebarCountMetricsTests` spells its needle **twice** (sweep at `:507`,
  self-check at `:545`), so a typo in the sweep's copy alone is invisible — one-constant fix. And
  `noSettingsPaneStillPaintsUnderTheSystemSeparator` is dead weight, strictly subsumed by its
  line-break sibling which counts the walk and has a detector test.
  **Closed 2026-08-31. All three sweeps go through `CadenceScanInstrument` with literal fixtures and non-vacuous walks; two also pin that the comment-blanking reader genuinely differs from a raw read. `CadenceSidebarCountMetricsTests`' needle collapsed to one constant read by both the sweep and its self-check. `noSettingsPaneStillPaintsUnderTheSystemSeparator` **deleted** as a strict subset of its line-break sibling, with its positive `CadenceRowDivider` table moved into the survivor. **Proved both ways**: blinding each detector kills it with `.blind`, and planting each needle as live code makes each sweep name the planted file. The instructive one is the tint needle — **the blinded sweep still passes, because it inherently cannot detect its own blinding, while the witness reading the same constant fails.** That asymmetry is the entire fix.**

- [T-510] **Release packet and review notes disagree about which platforms ship** (Codex, P3, measured
  doc drift, **not a runtime bug**). `docs/app-store-submission-packet.md:13` says *Platforms: macOS*,
  while `docs/app-review-notes.md:8` says Cadence targets macOS **plus iOS/iPadOS from one app target**,
  and the project lists `iphoneos iphonesimulator macosx`. If the next submission is Mac-only the packet
  should say so explicitly; if it includes iOS/iPadOS, the packet and its readiness tests need updating.
  **Decide before submitting, not after.**
  **Closed 2026-08-31 **by the user's decision: macOS only for 1.0.** Neither document was factually wrong — `app-review-notes.md` described the *build* accurately while the packet mirrors an App Store Connect *field*, which is a per-submission choice. The packet, the SKU (`cadence-macos`), the reviewer script and `apple-release-readiness.md` are all macOS-shaped and self-consistent, so **the packet stands and the review notes' iOS/iPadOS claims are the ones to narrow**. The project genuinely builds `iphoneos iphonesimulator macosx` with complete iOS icons — that stays true and simply is not what is being submitted. Revisit when iOS ships: [[T-535]] records that nothing in the release gate ever compiles the iOS surface.**

- [T-538] **The macOS sidebar drops a context-less list entirely — worse than [[T-534]]'s picker.**
  `SidebarContextSection` derives rows from the relationship (`(context.areas ?? []).filter(\.isActive)`,
  `macOS/Views/SidebarComponents.swift:96-97`), iterated per `Context`, and `sidebarListItem(contextID:)`
  takes a **non-optional** id. So a list with `context == nil` is not merely un-grouped — **it is invisible
  in the macOS sidebar.** iPad draws the same region through `CadenceSidebarLists.sections` and gives it
  "Other". Same cause, same fix shape and same iOS-creates/macOS-inherits reachability as T-534's second
  defect: iOS offers "None" unconditionally, macOS can neither create nor correct that state.
  **Closed 2026-08-31. `SidebarView.listSections` buckets flat `@Query` results through a new generic overload of `CadenceSidebarLists.sections`, which the flattened iPad spelling is now **implemented as** — one bucketing rule rather than two. `sidebarListItem(contextID: UUID)` is gone; the two model→`Item` initialisers moved into a shared `CadenceSidebarListsBridge` that reads `area.context?.id`. **The non-optional was the whole defect and it was never a narrowing**: the optional was *discharged by the iteration* — `ForEach(contexts) { $0.areas }` never constructs the nil case, so no compiler diagnostic could exist. That is the real shape here: **traversal-derived rendering silently defines its own domain, and its blind spot is exactly the rows where the relationship is nil.** `keepingEmptyContexts` is the one legitimate platform difference and is load-bearing — the macOS header carries the "+" that opens `CreateListSheet`, the only route to a list in a given context there. **A second defect fell out: lists inside an archived context were equally invisible on the Mac** and now land in "Other" too. Ten of eleven new tests killed by at least one of eight mutations (the eleventh is unkilled and declared as such). **Create half confirmed on an iPhone simulator** (`ZCONTEXT IS NULL` in the store); **macOS render not confirmed by eye and not claimed** — `screencapture` refuses this app's window, the debug build vends 0 AX windows, and a frontmost-guarded capture aborted when focus moved.**

- [T-549] **`CalendarRecurrenceEditScope` cannot be shared while `CalendarManager.swift` is one
  `#if os(macOS)`.** `iOSCalendarEventEditSheet` privately re-declares it — same cases, raw values, labels
  and `EKSpan`s, byte for byte — and until [[T-524]] **nothing pinned either copy**, which is the state
  [[T-200]] found the *task* scope enums in. The real fix is moving the enum to `Cadence/Shared/`, which
  deletes the private copy outright; `thePhonesPrivateCalendarScopeEnumMatchesTheMacOne` holds the line
  meanwhile and **should be deleted as part of that move**. Note the pin asserts the `EKSpan` mapping too,
  not just the labels — equal words over a wrong span would **destroy a series** while passing a
  label-only check.
  **Closed 2026-08-31. `CalendarRecurrenceEditScope` moved to `Cadence/Shared/` verbatim — cases, raw values, labels and the `EKSpan` mapping all preserved — and `private enum iOSCalendarRecurrenceEditScope` is deleted, 5 references repointed. **`thePhonesPrivateCalendarScopeEnumMatchesTheMacOne` was replaced rather than merely deleted**: it existed only because the duplication did, but dropping it outright would have left the `EKSpan` mapping unpinned, and **equal labels over a wrong span would destroy a recurring series while passing a label-only check**. Two successors took its place. No MCP or widget build needed, established by reading the target source lists rather than building speculatively: each pulls three files from `Shared/` and **zero** from `macOS/`, and neither list contains the moved file.**

- [T-489] **CLOSED 2026-09-03 (`2a8a70a`) - swept `.stroke` to `.strokeBorder` app-wide, wherever the
  shape is filled.** 83 sites converted: every `RoundedRectangle`/`Circle`/`Capsule` `.stroke` drawing a
  control/card/chip boundary, including a selection ring overlaid on a filled sibling shape
  (`SettingsTagsSection.swift`, `TagPickerPopoverViews.swift`) and an outline-only button with no
  separate fill (`TaskInspectorContentSupportViews.swift`'s `iconButton`) — both still "the shape is
  filled" in the sense the decision meant, since each bounds a control's rendered area rather than
  drawing a line-like decoration. Two sites deliberately left as `.stroke`, and documented as such:
  `TaskCompletionAnimationViews.swift`'s progress-ring track (line 23) and its `.trim`-ed arc (line
  27) have no companion fill at all — a stroke-only decoration, which is the ticket's own carve-out.
  Bare `Path`/`NSBezierPath`/`UIBezierPath` canvas drawing (the markdown editor's AppKit code and its
  iOS equivalents) and `Canvas`'s `GraphicsContext.stroke(Path, ...)` were left alone on the same
  ground: `.strokeBorder` is not a member of either type. `SettingsListManagementSections.swift`'s
  28x28 glyph well — the site that reopened this ticket from [[T-449]] — now reads
  `.strokeBorder(Theme.borderSubtle)`. `CadenceStrokeBorderSweepTests` sweeps the whole tree rather
  than a fixed file list and pins the two exceptions by exact line; `scripts/mutate.sh` confirms
  reverting the motivating site, and "helpfully" converting one of the two exceptions, are each
  KILLED.

- [T-616] **CLOSED 2026-09-03 (`2a8a70a`) - named the de-facto 7pt radius `Theme.radiusControlCompact`
  and swept every spelling onto it.** Measured 54 bare `cornerRadius: 7` call sites (one more than the
  ticket's 55 once one `NSBezierPath(xRadius:yRadius:)` pair and 3 `Theme.radiusControl - 3` sites — one
  more than the ticket's 2 — are counted separately), plus 3 *named* constants one level removed from a
  direct call site that were still the bare literal — `kanbanCardCornerRadius` (28+ call sites),
  `SidebarMetrics.appMarkCornerRadius`, and a private `TaskInspectorContentSupportViews.cornerRadius` —
  one more spelling of the same accidental copy. Defined `Theme.radiusControlCompact` as
  `radiusControl - 3`, the relationship the two pre-existing `radiusControl - 3` sites already assumed,
  so every site draws the identical `7` it drew before — no rendered pixel moved. Documented as
  descriptive of an existing copied value, not a new chosen tier: do **not** converge it onto
  `Theme.radiusControl` (10). `CadenceRadiusControlCompactSweepTests` sweeps the whole tree for both the
  bare-literal and `radiusControl - 3` spellings and pins that the token's own doc comment states the
  "descriptive, not chosen" framing; `scripts/mutate.sh` confirms reverting one converted site is
  KILLED. `iOSCalendarMetricsTests.theTodayTimelineDrawsTheSameHourLadder` — which had pinned the *old*
  `radiusControl - 3` spelling at this file's two sites — updated to expect the token instead.

- [T-643] **CLOSED 2026-09-03 (`db6abae`) — the completion spine's other door commits now, and the
  two halves of its switch undo differently.** `CadenceTaskMutationSupport.setStatus` throws and
  takes `commit:`. `.done` and `.cancelled` settle through the same `commitSettle` [[T-636]](a)
  gave `toggleCompletion`: `applyStatusCompletion` **returns** the successor it spawned now, so
  `commitInsert` has the one object it must un-insert, and a refusal also puts the status, the
  timestamp and `recurrenceSpawnedTaskID` back. The ticket's open question — what the
  `.todo`/`.inProgress` branch's undo is — resolves to an ordinary `commitEdit` over exactly the
  two fields that branch writes, `status` and `completedAt`, snapshotted before the transition:
  they insert nothing, so there is no successor to un-insert, and what the swallow left behind
  there was a row reading `.inProgress` over a store that still held the task done.
  `CadenceTaskStatusEditing.setStatus` catches and records on `CadenceTaskSettleFailureCenter`
  beside the toggle, and skips the reconcile on the failure path for T-636's reason: the transition
  has already been put back, so reconciling would retire a reminder for work that is still open.
  `Cadence/Shared/CadenceTaskMutationSupport.swift` leaves `existenceExemptions` entirely.
  `TaskEmbedFieldEditorPopover.content` stays in `indirectReportExemptions`, measured rather than
  assumed — `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` still finds it, and a
  mutation putting the deleted exemption back is KILLED by that same test.
  Six mutations, six KILLED, zero survivors: each undo removed, the successor swallowed again, and
  the wrapper's `record()` and its `return` each deleted.

- [T-721] **CLOSED 2026-09-03 (`3a38f80b`) — the postflight line calls the number what it is.**
  `tests_seen()`'s count is per-test RESULT LINES (right for the zero-test guard: a failing test
  prints two, `recorded an issue` and `failed after`) and not a test count. `scripts/xcb.sh`'s
  postflight now prints `test result lines:` instead of `tests executed:`, matching
  `scripts/mutate.sh`'s own wording. Nothing about the count changed.

- [T-660] **CLOSED 2026-09-03 (`3a38f80b`) — the cap's failure message now names both counts.**
  `AgentContextBudgetTests.expectLineCount` still counts
  `split(separator: "\n", omittingEmptySubsequences: false)` — one higher than `wc -l` on every
  newline-terminated file here, always by exactly one (pieces = newlines + 1, unconditionally) — but
  its `#expect` message now reads "N lines by this test's count (M by `wc -l`)" and states the limit
  both ways too, so an agent who reaches for `wc -l` sees the discrepancy instead of landing on it
  silently. `docs/SUBAGENT_RUNBOOK.md`'s cap bullet no longer tells you to check `wc -l AGENTS.md`
  and stop at 200; it says 199. [[T-750]] is a duplicate, closed alongside this.

- [T-750] **CLOSED 2026-09-03 (`3a38f80b`) — duplicate of [[T-660]].** Filed independently by a
  later batch after hitting the identical trap; no separate fix.

- [T-667] **CLOSED 2026-09-03 (`3a38f80b`) — the three suites were never unreachable; the counter
  that measured them was blind to a display name.** Re-measured before fixing, because a
  hand-eyeballed "0 tests" is exactly the evidence this repo has learned not to trust: real logs
  already sitting in this session's own scratch history (`cadence-xcb-t667b.log`, `-t667d.log`) show
  `-only-testing:CadenceTests/ListDetailPageTests` and
  `-only-testing:CadenceTests/MarkdownTableMobileEditingTests` — the plain type name, the very
  identifier the ticket said selected nothing — running and passing every one of their tests (9/9
  and 27/27, `✔ Suite "..." passed`). Confirmed live afterward for all three together, by type name,
  in one run: `✔ Test run with 42 tests in 3 suites passed after 2.313 seconds` — 9 + 27 + 6, exactly
  `RootModalKeyDispositionTests` included.
  **The actual bug:** swift-testing's console reporter prints `✔ Test "<display name>" passed` for a
  `@Test("...")` case instead of `✔ Test funcName() passed`, and `xcb.sh`'s `TEST_RESULT_PATTERN`
  (`scripts/mutate.sh`'s parallel `TEST_RESULT` too) matched only the bareword form — so a suite that
  ran and passed every case under a display name counted as zero. Re-running `xcb.sh check-test-log`
  against the historical `ListDetailPageTests` log: `0 test result(s)` before this fix, `9 test
  result(s)` after, same log, same bytes. Not scoped to these three: it was silent for any
  `@Test("...")` case in the target — 52 of them across 5 files.
  **Fix, in the order asked:** (a) no new spelling was needed — the plain type name already selects
  each suite; the ticket's "0 tests" was the counter's blind spot, not a selection failure.
  (b) `scripts/test-suite-index.sh` gained `--label`/`--labels` (the string swift-testing will
  actually print for a suite) and `list` mode now marks a display-named case with the quoted text to
  grep instead of its function name — the trap that produced the original reading
  (`grep '✔ Test <name>()'`, the exact spelling `docs/SUBAGENT_RUNBOOK.md` recommends) now has a
  documented way out, pinned in that same file. (c) `xcb.sh`'s postflight gained a second guard
  beside the aggregate zero-test check: for every requested `-only-testing:CadenceTests/<Suite>`, it
  resolves the suite's runtime label (one `--labels` call, not one per suite) and confirms a
  `Suite ... started` line for that label actually appears, catching a suite that contributed
  nothing inside a larger passing run regardless of cause. Proved twice: against a synthetic
  four-suite log first, and then live — the real run above, requesting the three real suites plus a
  fourth, nonexistent `ThisSuiteDoesNotExistT667`, correctly passed the three (42 test result lines,
  0 compile errors, 0 real warnings) and flagged only the fake one, exiting 6.
  `scripts/mutate.sh`'s `TEST_RESULT` is widened the same way (46/46 selftest checks still pass
  unchanged); its `FAILED_SWIFT_TESTING` capture and the `SUITE-ABSENT`/`TEST-ABSENT` name-matching
  are **not** fixed here — both need the same function-name → display-name resolution and sit inside
  verdict logic with its own selftest, riskier to touch under this batch than to file. Residue:
  [[T-786]].

## Cancelled

- [X-03] **[T-83] Remove the nav arrows from Month and Board** — filed and decided on a false
  premise, then found already delivered. `cf785a8` scoped the removal to the timed grids; `ecfc9a3`
  superseded it two hours later and removed the cluster from **all four** surfaces, saying so in its
  own message. My summary to the user reported the earlier scoping as the shipped state, so the user
  was asked to decide something already done. Nothing was changed. The lesson is cheap and worth
  keeping: **report the shipped state from the code, not from the decision you remember briefing.**

- [X-08] **[T-208] CLOSED, FALSE PREMISE — Today's Completed section cannot show three rows above a
  count of two, and neither can the surfaces it was re-scoped onto.** The ticket said the section
  lists cancelled tasks while the header's "N done" does not count them. Re-derived from the code at
  `902b386`, independently of the note `CLAUDE.md` already carried.

  **The two numbers a user reads at that section are both `.count` over the array the rows are
  drawn from, so rows and count are the same number by construction.**
  - macOS: `TasksPanel.completedSection(derived:)` hands `TasksPanelCompletedSectionView` its
    `tasks: derived.doneTasks`, and that view heads itself with
    `TasksPanelIntentSectionHeader(count: tasks.count)` — the same array it `ForEach`es. The
    column-header `· N done` is `CadenceTodaySummary.completedCount`, built by
    `CadenceTodayPresentationSupport.summary(completedTasks: derived.doneTasks)` as
    `completedTasks.count` — the same array again.
  - iOS: `iOSTodayTaskSections.groupStack` passes
    `CadenceTaskSurfaceOptions.completedRows(from: completedTasks)` to `iOSTaskGroupSection`, whose
    capsule is `count: tasks.count` over that same (row-capped) array.
  - `derived.doneTasks` in `.todayOverview` is `CadenceTaskQuerySupport.completedTodayTasks`, whose
    predicate is `isFinishedTask` — done **or** cancelled — so a cancelled task is in the rows *and*
    in both counts. Three rows show a count of three.

  **`completedTaskCount` — the `isDone`-only rule the ticket is really about — is not read by that
  section at all.** `CadenceTaskQuerySupport.completedTaskCount` has three call sites: the iOS
  Settings **Completed** metric tile (`iOSSettingsView.completedTaskCount` →
  `iOSLocalDataSettingsSection`) and the past-due kanban-column summary built in
  `CadenceTodayOverdueSummarySupport.summaries(...)`. (`TasksListView` declares a private
  `completedTaskCount` of its own for All Tasks / Inbox; it counts `isDone || isCancelled`, matching
  its own `completedTasks` array exactly. Three MCP DTO fields share the name over an inline
  `filter(\.isDone).count`.)

  **Neither of those is defective either, which is why this closes rather than being re-scoped.**
  The overdue column card (`CadenceTodayOverdueSectionCard`) draws "N open" from `openTaskCount`
  and "N done" from `completedTaskCount`, and a cancelled task is in neither — but the card states
  no total, and both labels are literally true of the numbers under them. The Settings tiles are
  the same shape: independent "Active tasks" and "Completed" tiles, no sum, both accurate. An
  omission with no claim attached is not the visible inconsistency the ticket was filed on.

  One correction to the note `CLAUDE.md` carried, which said the two overdue summary cards are
  macOS's: `CadenceTodayOverdueSummaryCards.swift` is in `Shared/Components/` and
  `CadenceTodayOverdueSectionCard` is rendered by `TasksPanel.overdueSectionsSection` **and** by
  `iOSTodayTaskSections`. If anyone ever does decide cancelled work should be visible on that card,
  it is one change for both platforms, not a macOS one.

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.

- [X-04] **The kanban header's `overdueCount > 0` guard is not a coverage gap** — a mutation batch
  reported it as "genuinely unpinned": deleting the `> 0` from `ListDetailSupportViews.swift:176`
  passes the whole suite, and no test names the view's own display rule. Both halves are true and
  the conclusion does not follow. `TasksPanelSupport.overdueCount(in:)` returns
  `count > 0 ? count : nil`, so **zero never reaches the view** — every call site into the header
  either goes through that producer or passes `nil` outright. The mutation is behaviourally inert,
  which is why it survived. The invariant it leans on *is* tested, at
  `TaskOverdueSupportTests.swift:120` (`overdueCount(in: [doneLate]) == nil`). Leave the guard.
  Recorded so the next agent neither "fixes" it nor re-files it — and as a reminder that a
  surviving mutation means *the tests cannot see this change*, which is a hole only when the
  change is one a user could ever observe.

- [X-05] **[T-267] CLOSED, NOT A BUG — the iOS month date picker never killed the app. `tccd` did.**
  The ticket read as the highest-priority open crash and the premise was false, so the correction
  matters more than the closure. Re-verified against `b1239e0` on the shared `iPhone 17 Pro`
  (`7B642065-…`, iOS 26.5), clean Debug build, **seven** day-cell taps across all three entry
  points — `iOSTaskComposerDateTile` (Do and Due), `iOSTaskRowDateChip` on a live Today row, and
  the task inspector's `CadenceDatePicker` — covering today's cell, a future cell, a **past** cell,
  and a cell in a **different month** (the one that really moves `viewMonth` and re-derives all 49
  months). Every tap set the date and left the app running. `MonthCalendarPanel`'s day `Button` is
  **not** the defect; do not "fix" the `selection` / `syncViewMonthToSelection()` / `isOpen = false`
  sequence on the strength of this ticket, and do not touch it lightly at all — it is
  `Shared/Components/`, macOS reads it from six call sites including the `Cmd+Shift+T`/`Cmd+Shift+D`
  hovered-date overlay.
  **What actually happened.** Every disappearance-to-Home in this simulator's log — ten of them
  across 2026-08-22, including the four consecutive ones at 12:50:44 / 12:53:17 / 12:55:02 /
  12:55:37 that are this ticket's "reproduced four times" — is the same line:
  `tccd: Terminating com.haoranwei.Cadence[<pid>] because access to the kTCCServiceReminders
  service changed`, followed by `launchd_sim: … exited with exit reason (namespace: 11 code: 0x0)
  - OS_REASON_TCC`. Each one is preceded by milliseconds with
  `tccd REQUEST: sender_pid=81487, function=TCCAccessSetInternal` (or `TCCAccessResetInternal`) —
  pid 81487 is **CoreSimulatorBridge**, i.e. a host-side `xcrun simctl privacy <udid>
  grant|revoke|reset reminders com.haoranwei.Cadence`. Changing a TCC grant for a *running* app is
  specified to kill it; nothing in Cadence can cause it. The msgIDs form one ascending series
  (`81487.2 … .16`) across the whole day, which is what an unrelated agent's repeated
  `simctl privacy` calls on a **shared** device look like from inside the app.
  **Demonstrated, not inferred.** With the picker open and no tap on the grid,
  `xcrun simctl privacy … grant reminders com.haoranwei.Cadence` from the host reproduced the exact
  reported symptom — app gone, Home screen, sheet state lost — and logged `msgID=81487.16` with the
  identical two lines. `auth_value` in the device's `TCC.db` was `2` before and `2` after, so the
  demonstration changed no state on the shared device.
  **The two "supporting" observations were both true and both misleading.** Nothing in
  `~/Library/Logs/DiagnosticReports` and no exception, because `OS_REASON_TCC` is not a crash and
  writes no report — the same reason the ticket's `SIGKILL`-shaped reading felt right. And the
  quick pills worked "every time" because they were not tapped during the seconds a `simctl
  privacy` call happened to land.
  **The lesson is the shared simulator, not the picker.** The root `AGENTS.md` simulator bullet now
  carries it: on a device several agents share, an app vanishing to the Home screen is an *external
  termination* until the log says otherwise, and
  `log show --predicate 'process == "tccd" OR process == "launchd_sim"'` settles it in one command.

- [X-06] **[T-179] CLOSED, EXTERNAL CONSTRAINT — `control action=detach` ignores the `udid` argument and
  closes every simulator panel.** Re-verified 2026-08-24: this is a bug in the iOS Simulator control
  tool itself (the `mcp__Claude_Code_iOS_Simulator__control` action), not in anything under this
  repo, so there is no code here that can fix it. An agent detaching its own device once closed
  three other agents' panels (iPhone 17e, iPhone 17 Pro Max, iPad Air 11-inch); no device or app
  state was altered and every closed panel could just re-`attach`, so the blast radius is annoyance,
  not data loss. The one mitigation available from this side of the boundary is documentation, and
  it is now in place: `AGENTS.md`'s simulator bullet states `detach` as global regardless of `udid`
  and tells agents to only call it when they have reason to believe no one else is attached. Closing
  rather than leaving open because there is nothing left to *build* — reopen only if the tool itself
  changes or a repo-side workaround (e.g. an attach-tracking convention) is actually designed.


- [X-07] **[T-257]** ~~**`HEAD` does not build from a clean clone.**~~ **Withdrawn — the premise is false, and
  following the instruction breaks the build.** `TaskContainerLifecycleService` *is* declared at
  `HEAD`, in the committed `Cadence/macOS/Services/TaskWorkflowService.swift:58`; the untracked
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift` is another agent's uncommitted
  **move** of that type — which is why `Cadence/macOS/Services/TaskWorkflowService.swift` shows as
  modified in the same `git status` the ticket was written from. So the committed call sites in
  `EditListSheet.swift` and `CadenceCancelledTaskReachabilityTests.swift` resolve fine, and a clean
  clone builds. What does *not* build is `HEAD` plus that one untracked file, which is exactly the
  isolation [[T-21]] was told to construct: measured on 2026-08-22, three errors — `invalid
  redeclaration of 'TaskContainerLifecycleService'` and two `has no member 'remainingActiveTasks'`
  against `HEAD`'s smaller version of the type. Dropping the file instead gave macOS TEST SUCCEEDED
  and an iOS BUILD SUCCEEDED. Do **not** `git add` it — that would commit half of somebody else's
  in-flight refactor. The general rule stands and is the one worth keeping: the project uses Xcode
  **file-system-synchronized groups** (6 `PBXFileSystemSynchronizedRootGroup` entries in
  `project.pbxproj`), so any `.swift` file under `Cadence/` is compiled by directory membership with
  no `project.pbxproj` change to show for it. An untracked file therefore silently joins every
  build, and restoring `HEAD` means **deleting** it, not keeping it.

- [X-09] **Push the MCP page slice into the fetch (was [[T-415]]).** Not doing it. The ticket's stated
  reason was false -- `UUID` *is* `Comparable` in Foundation, and `UUID() < UUID()` typechecks at
  `-target arm64-apple-macos14.0`. Three real blockers stand, each independently sufficient: both
  comparators lead on **computed** properties (`AppTask.isDone` off `statusRaw`, `Note.displayTitle`)
  that a `SortDescriptor` key path cannot reach; the title leg is `localizedCaseInsensitiveCompare`
  while `SortDescriptor` offers only numeric-aware `.localizedStandard`, so pushing it down changes
  the very order `offset` is defined against; and half the candidate lists are relationship edges
  ([[T-384]]) or cross-kind merges ([[T-383]]) with no `FetchDescriptor` to carry `fetchOffset`.
  Reopening would need a stored `Comparable` sort key on `AppTask`/`Note` reproducing today's order,
  plus a partial revert of T-384 -- a CloudKit migration, with no `SchemaMigrationPlan` in the repo,
  to remove one array slice from reads whose fetch is already bounded and asserted. The limit is
  documented on `CadencePage.paging` and in the MCP guide instead.

# Per-group verdicts on the 35 silent `try? save()` user commits, T-11614, 2026-11-05 (tree `887cd21f`)

Agent `savegroups2137`. Lock-free and read-only on source. **Nothing was built, run or seen on
screen.** `./scripts/xcb.sh check-automation` exited 13 (AUTOMATION-PROMPT-OUTSTANDING,
requests=1 granted=16 outstanding=1, testmanagerd pid 51557 live), so the notice code this file
specifies waits on a test run the owner has to unblock. Line numbers are at `887cd21f`.

**Question.** [[T-11614]] holds the (a-silent) group from `save-census-T-11581.md`: user commits
that end `try? save()` with no refusal notice. For each group: does a refused write need a notice
routed through the spine, or is it a quiet in-place field edit that AGENTS.md's rule allows?

**The spine, as the source has it.** Commits go through `CadencePendingChangePersistence`
(`Cadence/Shared/CadencePendingChangePersistence.swift`): `commitEdit(in:commit:refusing:undo:)`
(:145), `commitInsert`, `commitDelete`, `commitCascade`, `commitTypedContent` (:180). Only commits
that reach its private `perform` can be refused by `CADENCE_UI_TEST_REFUSE_COMMITS`. Built on it:

- `CadenceTaskFieldEditCommit.commit(_:alsoRestoring:in:reconciler:commit:apply:) -> Bool`
  (`Shared/CadenceTaskFieldEditCommit.swift:196`). It snapshots the task, applies the edit,
  commits and undoes on refusal. Its notice is `saveFailureNotice`, "Couldn't save this change."
- `CadenceInPlaceEditFlush.flush(in:commit:refusing:) -> Bool` (`Shared/CadenceInPlaceEditFlush.swift:47`).
  It commits with no undo, for a surface that stays open. Its notice is `failureNotice`.
- `CadenceListEditSnapshot(area|project, tasks:)` and `.restore()` (`Shared/CadenceListEditSnapshot.swift:61,82,73`).
  This is the list-level undo for `commitEdit`.
- Notices are drawn by `CadenceInlineFailureNotice(text:)` (`Shared/Components/CadenceInlineFailureNotice.swift:35`).
  On a closed menu they are drawn by the row's alert: `MacTaskRowContextMenu.ActionOutcome.refused(MacTaskRowMenuFailure)`
  with `MacTaskRowMenuOutcomeModifier` on the Mac, and `iOSTaskMoveFailureAlertModifier` /
  `iOSTaskRowRecurrenceFailureAlertModifier` on iOS (`iOS/iOSTaskRowActionViews.swift:1045-1077`).

**What a silent refusal actually does.** There is one `ModelContext` app-wide. A swallowed refusal
leaves the edit *pending*, so the screen keeps showing it. It then lands on the next unrelated
successful save, or it is lost to a `rollback()` or to quitting. The user is never told. A revert,
when it comes, shows up later and with no link to the gesture that caused it.

## The list against the code

All 35 are present at `887cd21f`. `rg 'try\? *([A-Za-z_.]+\.)?save\(\)'` over `Cadence/`, with
comments and the (b)/(c) sites set aside, finds exactly these and nothing new. Where the prose
and the code disagree, the code wins:

- **Six line numbers moved by +1.**
  - `iOS/iOSSettingsView.swift`: 543/557/562/567 are now **544/558/563/568**.
  - `iOS/iOSListViews.swift`: 450/455 are now **451/456**.
- **`CadenceNotePlanningSupport.update` is `CadenceCoreNoteSupport.update`.** It is
  `enum CadenceCoreNoteSupport` (:182), declared in `Shared/CadenceNotePlanningSupport.swift:261`.
- **`CadenceTaskMutationSupport.removeTaskFromBundle(_:modelContext:)` (:1198) has no caller in
  `Cadence/`.** Its only caller is `CadenceTests/TaskSameIDTwinDetachTests.swift:98`. The app's
  "remove from block" is `SchedulingActions.removeTaskFromBundle(_:keepOnBundleDate:)`
  (`macOS/Services/SchedulingService.swift:146`), a different function. So this site is **not a
  user commit**. Filed as [[T-11861]].
- **The ticket's "archive … in the iOS list views" is restore only.** `iOSListViews.swift:451,456`
  are `restore(_ area:)` and `restore(_ project:)`. Archive and complete there go through
  `windDownListUnlessConfirmationIsNeeded` and land in the wind-down group (G1).
- **The archive/restore/reopen sites were quiet on purpose.** That was recorded as convention
  T-583 in the doc comment on `macOS/Views/SettingsView.swift` `archiveContext` (:389-406). This
  verdict overturns it for the reason that comment itself gives for carving out `moveContext`
  ([[T-614]]: a rearrangement the user can see is a success report). The implementer must rewrite
  that comment, not just the code.

## The test I applied

The rule's letter passes all 35. `CadenceSaveCommitDisciplineTests` declines every one. So the
question is product, not compliance. **A site needs a notice when the gesture is a one-shot
command whose surface closes or whose row moves elsewhere** — a menu item, a swipe, a confirmed
sheet, an Archive/Restore button — because then nothing on screen can be checked against it later,
and T-614's visible-rearrangement reasoning applies. **A site stays quiet when it is a continuous
edit on a surface still open and still showing the value**: typing, a drag, a binding inside an
open popover. Undoing that would overwrite what the user is holding, which is why
`commitTypedContent` and `CadenceInPlaceEditFlush` exist. A second, independent trigger is
**platform drift**: where the twin surface on the other platform already reports, the silent side
is a defect ("one app, two platforms").

## Verdicts, ranked by how likely the owner is to notice a silent revert

| Rank | Group | Sites | Verdict |
|---:|---|---:|---|
| 1 | G1 iOS list and column wind-down | 3 | **Notice** |
| 2 | G2 row-menu and swipe date shortcuts | 7 | **Notice** |
| 3 | G3 archive, restore, reopen | 14 | **Notice** |
| 4 | G4 row-menu priority and section | 2 | **Notice** |
| 5 | G5 Kanban card tags binding | 1 | **Notice** (parity) |
| — | G6 due-date setter from pickers and keys | 1 | **Answer, notice where a surface exists** (do-date parity) |
| — | Q quiet in-place edits | 6 | **Quiet**, allowed |
| — | D dead helper | 1 | Not a user commit ([[T-11861]]) |

That is 3+7+14+2+1+1 = **28 that should report**, 6 that stay quiet and 1 that is dead. Total 35.

### G1 — iOS list and column wind-down (3): notice, first

- `iOS/iOSListWindDownSupport.swift:207`, `ModelContext.windDownList`
- `iOS/iOSColumnWindDownSupport.swift:127`, `windDownColumn`
- `iOS/iOSColumnWindDownSupport.swift:142`, `reopenColumn`

**Why first.** These run behind a confirmation sheet that counts N tasks. They file a whole list
or column away and cancel or complete every open task in it. A revert brings back a list the owner
archived, with all its tasks open again. It is also **drift**: the Mac twins already report.

- `macOS/Views/KanbanSectionColumnView.swift:850` `saveSection` and `:916` `toggleSectionArchive`
  commit through `commitEdit` + `CadenceListEditSnapshot` + `editFailureNotice` (T-632).
- `macOS/Sheets/EditListSheet.swift:195-217,448-467` does the same for a list's lifecycle row.

There is a report-half case as well: the editor's `save()` (`iOS/iOSListEditorViews.swift:801`; reached from `performListWindDown` :596) calls, at :907-909,
`windDownList(target)` and then `dismiss()` whatever the commit did.
`applyColumnWindDown` / `reopenColumn` (:689-704) then rewrite the draft rows as archived/open
after the swallow.

**Route.** Give each function `throws` and `commit: (ModelContext) throws -> Void = { try $0.save() }`.

- Take `let undo = CadenceListEditSnapshot(area|project, tasks: TaskContainerLifecycleService.remainingActiveTasks(…))`
  *before* the write. For an area, use `includingChildProjects: true`, which is the set
  `windDownList` settles. A column snapshots its container, as `KanbanSectionColumnView.editSnapshot(settling:)` does.
- Then call `try CadencePendingChangePersistence.commitEdit(in: self, commit: commit) { undo.restore() }`.
- `windDownListUnlessConfirmationIsNeeded` (:217) must forward the throw.

The hosts surface `CadencePendingChangePersistence.editFailureNotice`:

- `iOS/iOSListViews.swift:428` (Lists page). It has no notice slot, so it needs an alert, because
  it is a menu or swipe.
- `iOS/iOSRootSidebar.swift:730` (sidebar lists region), the same.
- `iOSListWindDownModifier` (`iOSListWindDownSupport.swift:254-260`), the confirmed path. Its
  sheet should stay up on a refusal.
- `iOS/iOSListEditorViews.swift`:
  - `save()` at :907, the confirmed-wind-down step: no `dismiss()` on a refusal. Set the existing
    `saveFailureNotice` (:85).
  - `applyColumnWindDown` (:689) and `reopenColumn` (:699): update the draft only on success, and
    set `saveFailureNotice` otherwise.

`CadenceSaveCommitDisciplineTests.theWindDownSettlesAreTheInPlaceSwallowTheWidenedNeedleDeclines`
(:470) pins `try? save()` in both files. It goes red **by design** and must be retired or
inverted in the same commit.

### G2 — row-menu and swipe date shortcuts (7): notice

All seven are in `Shared/CadenceTaskMutationSupport.swift`:

- `scheduleToday` :233, `scheduleTomorrow` :238, `scheduleNextWeek` :244
- `dueToday` :352, `dueTomorrow` :357, `dueNextWeek` :363
- `clearDueDate` :369

**Why this rank.** These are the highest-frequency writes in the group. Each one moves the row out
of the view it was in, so it is a visible rearrangement. The menu or swipe that issued it is gone.
A revert puts the task back on the wrong day.

**Route.** Each helper becomes `-> Bool` and takes `commit:`. Its body becomes
`CadenceTaskFieldEditCommit.commit(task, in: modelContext, commit: commit) { <the field write> }`.
That is `moveTaskToDate`'s shape (:289), because a closed menu has no field holding the value, so
the undo is right. Do not use `@discardableResult`; every caller must take the answer. The
`CadenceTaskDateEditing` wrappers (`Shared/CadenceTaskDateEditing.swift:74-98,192-225`) forward
both the answer and `commit:`, and still reconcile either way.

Callers and where the answer goes:

- **macOS row menu.** `macOS/Views/MacTaskRowContextMenu.swift:130,136,142,162,168,174,181`.
  Wrap each in `settle(...)`, returning `.refused(<new MacTaskRowMenuFailure case>)` with message
  `CadenceTaskFieldEditCommit.saveFailureNotice`. Add a case such as `.date` to the enum at
  :424-445 with a title like the iOS ones.
- **iOS row menu.** `iOS/iOSTaskRowActionViews.swift:617,623,629,649,655,661,668`. Set a row
  failure binding and raise an alert modeled on `iOSTaskMoveFailureAlertModifier` (:1048).
- **iOS swipe.** `iOS/iOSTaskRowActionViews.swift:22,30` (`iOSTaskRowSwipeActions.leading`). Same
  alert. The closure needs the row's failure binding passed in.
- **Same menus, already `-> Bool`, answer dropped.** `CadenceTaskDateEditing.clearScheduledDate`
  at `MacTaskRowContextMenu.swift:148` and in the iOS twin. Wire it in the same pass, or do-date
  and due-date disagree on one submenu.

### G3 — archive, restore, reopen in Settings and the iOS Lists page (14): notice

- `iOS/iOSSettingsTagsSection.swift:251` `archive`, `:257` `restore`
- `macOS/Views/SettingsTagsSection.swift:200` `archive`, `:206` `restore`
- `iOS/iOSSettingsView.swift`
  - `:544` `archive(Context)`, `:558` `restore(Context)`
  - `:563` `reopen(Area)`, `:568` `reopen(Project)`
- `macOS/Views/SettingsView.swift`
  - `:409` `archiveContext`, `:424` `restoreContext`
  - `:429` `reopenArea`, `:434` `reopenProject`
- `iOS/iOSListViews.swift:451` `restore(Area)`, `:456` `restore(Project)`

**Why.** Each one moves a row between the Active and Archived (or Done) sections. That is T-614's
visible rearrangement, and the next launch undoes it with nothing said. Settings already draws
inline notices on the same panes, so the work is mechanical. It ranks below G2 because these are
rare gestures.

**Route.** Capture the fields first, then
`try CadencePendingChangePersistence.commitEdit(in: modelContext) { <put them back> }`.

- Tag: `isArchived`, `updatedAt`.
- Context restore: `name` **and** `isArchived`, because `availableContextName` renames before the
  flag clears (T-4910).
- Area/Project: capture `statusRaw` rather than `status`, for the reason `CadenceListEditSnapshot`
  gives. `CadenceListEditSnapshot(area)` / `(project)` with no tasks is the existing type for it.

On a catch, set a **new** `@State lifecycleFailureNotice` to
`CadencePendingChangePersistence.editFailureNotice` and draw it with `CadenceInlineFailureNotice`
beside the pane's existing notices. Do not reuse `createFailureNotice`, which sits under the create
field.

- macOS `SettingsView` notices: :67-74.
- iOS `SettingsView`: `contextOrderFailureNotice` :420.
- Tag sections: :95-99 (macOS) and :142-146 (iOS).

`iOSListViews` gets the alert G1 adds to that view. Rewrite the T-583 paragraph at
`SettingsView.swift:389-406`.

### G4 — row-menu priority and section move (2): notice

- `setPriority` `Shared/CadenceTaskMutationSupport.swift:228`. Callers:
  `macOS/Views/MacTaskRowContextMenu.swift:100` and `iOS/iOSTaskRowActionViews.swift:587`.
- `moveToSection` `:374`. Callers: `MacTaskRowContextMenu.moveSection` :351-354 and
  `iOSTaskRowActionViews.moveSection` :761-764. Both carry a doc comment saying there is "nothing
  here to refuse".

**Why.** These are one-shot commands from the same closed menu that already reports recurrence,
move and duplicate. The answer from the next item down should not be the only one that goes
missing. Priority ranks lower than G2 because the row usually does not move. Section does
rearrange the row under another heading.

**Route.** The same as G2: `CadenceTaskFieldEditCommit.commit` returning `Bool`, then
`settle(.refused(...))` on the Mac and the row alert on iOS. Rewrite both "nothing here to refuse"
comments.

### G5 — Kanban card tags binding (1): notice, for parity

`macOS/Views/KanbanCardMetaSupportViews.swift:86` (`KanbanTagPickerPopover`). The same
`TagPickerPopover` on the inspector schedule panel already reports through
`TaskInspectorScheduleCommit.setTags(_:on:in:commit:) -> Bool`
(`macOS/Views/TaskInspectorContentSupportViews.swift:832`, caller
`macOS/Views/SchedulePanelComponents.swift:32-40`). So the board is the silent twin.

**Route.** Call that helper. Add `@State tagFailureNotice` to `KanbanTagPickerPopover` and draw
`CadenceInlineFailureNotice(text: CadenceTaskFieldEditCommit.saveFailureNotice)` under the
picker. Its undo restores `task.tags`, which the open popover's checkmarks then show truthfully.

### G6 — due-date setter from pickers and keys (1): answer, notice where a surface exists

`setDueDate` (:347) serves open date popovers and keyboard commands. `clearDueDate` (:369,
counted in G2) serves them too:

- `macOS/Views/KanbanCardView.swift:404,415`
- `macOS/Views/TaskEmbedFieldEditorPopover.swift:159,171`
- `macOS/Views/TasksPanelComponents.swift:600,611`
- `macOS/Services/HoveredTaskDatePickerManager.swift:82,93`
- `macOS/Views/macOSRootCommandActionSupport.swift:47,49,123`
- `iOS/iOSTaskRowActionViews.swift:278,287`

**Decided: mirror the do-date pair exactly.** `setScheduledDate` / `clearScheduledDate` (:260,
:326) already go through `CadenceInPlaceEditFlush.flush` and return `Bool` (T-1580). Give
`setDueDate` the same shape: flush, `-> Bool`, `commit:`. Then:

- Popovers that stay open show `CadenceInPlaceEditFlush.failureNotice` inline, and do-date gets
  the same.
- The keyboard commands and the hovered picker keep no new surface. A hover has no anchor to draw
  on, and the edit stays pending exactly as it does now.

`clearDueDate` serves both G2 (menu) and G6 (picker). Give it the menu shape from G2, because a
picker's "Clear" closes the popover. The picker callers then take the same `Bool`.

### Q — quiet, allowed by the rule (6)

| Site | Why it stays quiet |
|---|---|
| `Shared/CadenceTaskMutationSupport.swift:225` `normalizeCompletionState` | Its one caller is `iOS/iOSTaskDetailSheet.swift:403` `saveTask`, the repair every field observer of the open detail sheet fires through. The doc at :395-401 already argues that routing it would run once per keystroke. The sheet stays open and shows the values. |
| `iOS/iOSTaskDetailComponents.swift:639` `save` | The title field's save. The doc at :632-638 is right: an undo would overwrite the text under the caret. A refused keystroke stays pending for the next one. |
| `Shared/CadenceNotePlanningSupport.swift:261` `CadenceCoreNoteSupport.update` | This is typed content: binding setters per keystroke at `iOS/iOSNotesView.swift:928`, `iOS/iOSListNotesView.swift:511` and the Mac `NotePanel` flushes. Its tag inserts already commit through the spine (`Shared/CadenceInlineTagCreation.swift:131`). Its one-shot callers (template apply ×6 on iOS; `NotePanel.appendSummary` :369) land in an editor that is still open and showing the text, which is the same contract as `NoteEditorPane.appendSummary` → `commitTypedContent`. That path is silent by the T-4971 decision ("the four editors … stay silent"). **Optional:** spell the save `_ = try? CadencePendingChangePersistence.commitTypedContent(in:)` so the refusal switch can reach it. That changes nothing on screen. |
| `macOS/Editor/MarkdownEditorView.swift:236`, `iOS/iOSMarkdownEditingSurface.swift:702` image resize | A drag-resize of `displayWidth` that the image keeps showing. It is continuous and on an open editor. |
| `macOS/Views/KanbanCardView.swift:393` duration binding | A stepper binding inside an open popover that keeps showing the value. No sibling surface reports a duration binding. |

### D — not a user commit (1)

`Shared/CadenceTaskMutationSupport.swift:1205`, `removeTaskFromBundle(_:modelContext:)`. Nothing
in the app calls it (see above). Delete it, or move it next to its one test, under [[T-11861]].

## Close calls, flagged for the owner

1. **G3 overturns a recorded convention (T-583).** I decided it because T-614 already carved
   `moveContext` out of that same convention on exactly this reasoning. The owner may still prefer
   Settings toggles to stay quiet.
2. **G6, keyboard and hover date commands get an answer but no notice.** I decided this because
   there is no anchored surface to draw on, and the behaviour matches today's do-date keys. If the
   owner wants a toast spine for anchorless commands, that is new UI and a new ticket.

## Not verified

- **Nothing was built, run, mutated or seen on screen.** Every claim is read from source at
  `887cd21f`.
- I did not check whether any `CadenceTests` source scan other than the one named in G1 pins the
  `try?` spelling or the "nothing here to refuse" comments of G2–G5.
  `CadenceTaskDateEditingSurfaceTests`, `CadenceListWindDownSurfaceTests` and
  `CadenceSharedTaskRowJobsTests` name these files. The implementer should run them first and
  expect census-style reds.
- I took the callers of each helper from a symbol `rg`, not a compiler. A call spelled through a
  stored closure would escape it.

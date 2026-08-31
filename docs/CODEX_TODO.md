# Codex Todo Handoff

This file is a lightweight queue for Codex-found work that should be cheap for Claude or another
agent to verify and patch. Keep entries short, source-backed, and runnable. When an item is moved to
`docs/TODO.md` or fixed, mark it here rather than leaving duplicate live tickets.

Each open finding includes a suggested implementation and acceptance checks. These are handoff
guidance from a source audit, not a claim that the proposed patch has compiled; the implementing
agent should preserve the stated behavior while adjusting signatures to the current tree as needed.

## Repo Stamp

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files at audit time: `52`
- Audit mode: read-only; no build; no tests
- TODO checked first: `docs/TODO.md`

## Follow-up Audit Stamp

- Tree read: `1706226`
- Dirty files before appending CXT-004..CXT-006: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp

- Tree read: `1706226`
- Dirty files before appending CXT-007..CXT-009: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp 2

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-010..CXT-012: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp 3

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-013..CXT-015: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## iCloud Cross-Device Audit Stamp

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-016..CXT-022: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`
- External contracts checked: Apple Core Data with CloudKit setup/sync documentation and Apple
  EventKit identifier documentation

## Patch Order

1. Fix markdown image asset commit-before-reference.
2. Fix macOS note action move dismissal/save handling.
3. Fix calendar settings link save handling across iOS/macOS.
4. Fix task-composer tag creation so tag rows are not inserted before the user commits the task.
5. Fix embedded task-card quick edits so they commit before repainting.
6. Fix macOS kanban column editor save failures around lifecycle side effects and editor dismissal.
7. Fix boolean-returning drag/drop handlers so they return success only after the save lands.
8. Fix focus completion/session-ending helpers so timer reset/clear happens after a durable commit.
9. Fix iOS recurrence row edits so repeat changes keep their dialog/failure state until save succeeds.
10. Fix macOS task-status controls that mutate through `TaskWorkflowService` without an explicit commit.
11. Fix macOS bundle popover end actions so complete/unbundle/delete commit or report before closing.
12. Fix macOS calendar-event edit surfaces so typed EventKit write failures are not discarded.
13. Fix task-detail subtask insert/delete paths so existence changes commit or restore before UI state advances.
14. Fix Today rollover so the banner is dismissed only after the whole batch commits.
15. Fix macOS timeline event creation so the typed EventKit result reaches the still-open quick-create popover.

## iCloud Cross-Device Patch Order

1. Scope image cleanup to assets referenced by the records being deleted; stop global orphan
   collection from user-delete paths.
2. Make list/context deletion safe against an incomplete CloudKit replica, initially by refusing or
   soft-deleting when completeness cannot be established.
3. Enable iOS's `remote-notification` background mode and replace the test that currently forbids it.
4. Reconcile duplicate recurring successors by conceptual occurrence identity.
5. Move EventKit calendar-link resolution into device-local storage so one device cannot break
   another device's link.
6. Replace additive focus counters with an immutable synced session ledger and derived totals.
7. Either normalize kanban sections into synced rows or explicitly narrow T-358 to the
   already-imported stale-editor case; the current helper cannot merge two offline CloudKit writes.

## Open Findings

### CXT-001: Markdown image insertion can create asset rows, swallow the save, then insert markdown references

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. Both macOS and iOS create `MarkdownImageAsset` rows in the live
  `ModelContext`, run `try? modelContext.save()`, then continue as if those rows are durable.
- Not the old ticket: this is not the closed paste-door issue. That ticket was about advertising
  paste support when image insertion was disabled. This one is commit-before-reference after image
  insertion is allowed.

Risk:

- A failed save can leave the editor with markdown references to asset IDs whose rows were never
  confirmed durable.
- Because Cadence uses one app-wide `ModelContext`, those inserted asset objects can remain pending
  and later be committed by an unrelated save, or discarded by an unrelated rollback.

Exact spots:

- `Cadence/macOS/Editor/MarkdownEditorView.swift:160` - `createAssets` calls
  `MarkdownImageAssetService.createAssets/createAsset`, then line 166 swallows save.
- `Cadence/macOS/Editor/MarkdownEditorView.swift:184` - `chooseImages` passes those assets to
  `insertAssets`.
- `Cadence/macOS/Editor/MarkdownEditorView.swift:195` - `insertAssets` inserts markdown for those
  asset IDs.
- `Cadence/iOS/iOSMarkdownEditingSurface.swift:333` - `insertPickedImages` creates assets, line 344
  swallows save, line 349 inserts markdown.
- `Cadence/iOS/iOSMarkdownEditingSurface.swift:363` - `createPastedImageAssets` creates pasted
  assets and line 369 swallows save before returning them to UIKit.

Existing correct pattern:

- `Cadence/Shared/CadencePendingChangePersistence.swift:39` - `commitInsert(of:in:)` deletes
  inserted objects again when the commit is refused.
- `Cadence/macOS/Views/TimelineEventBlockSupportViews.swift:387` uses it before presenting an
  inserted note.

30-second confirming command:

```sh
rg -n "createAssets\\(|createPastedImageAssets|insertPickedImages|MarkdownImageAssetService\\.createAsset|try\\? modelContext\\.save\\(\\)|insertAssets\\(|applyCommandToDraft\\(\\.insertMarkdown\\(markdown\\)" Cadence/macOS/Editor/MarkdownEditorView.swift Cadence/iOS/iOSMarkdownEditingSurface.swift Cadence/Services/MarkdownImageAssetService.swift CadenceTests docs/TODO.md
```

Suggested fix:

- Commit new assets through `CadencePendingChangePersistence.commitInsert(of: assets, in:
  modelContext)`.
- On failure, do not insert markdown.
- For picker flows, show a small editor/accessory failure notice where possible.
- For paste/drop flows, return `[]` so the insertion path declines rather than creating broken
  references.

Acceptance checks:

- With an injected throwing commit, asset rows are removed again and the editor text is unchanged.
- With a successful commit, every inserted markdown asset ID resolves to a stored row.
- Source coverage requires both macOS and iOS image insertion paths to reach `commitInsert` before
  changing editor text; a bare `try? save()` in either creation body is red.

### CXT-002: macOS note action Move Note dismisses the picker before saving and swallows the move failure

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. In the macOS note action popover, moving a note to No List, Area, or
  Project closes the picker before persistence is known.

Risk:

- The popover disappears and the live model changes, but save failure is invisible.
- This is the field-edit-plus-success-report family, with `showsPicker = false` as the report.

Exact spots:

- `Cadence/macOS/Views/AIActionsSupportViews.swift:37` - `NoteActionSupport.move(_:toArea:)`
  changes `note.area`, clears `note.project`, updates timestamp, then line 41 swallows save.
- `Cadence/macOS/Views/AIActionsSupportViews.swift:44` - `move(_:toProject:)` does the same for
  project.
- `Cadence/macOS/Views/AIActionsSupportViews.swift:224` - No List dismisses picker before move.
- `Cadence/macOS/Views/AIActionsSupportViews.swift:239` - Area row dismisses picker before move.
- `Cadence/macOS/Views/AIActionsSupportViews.swift:256` - Project row dismisses picker before move.

Existing correct pattern:

- `Cadence/Shared/CadencePendingChangePersistence.swift:100` - `commitEdit(in:undo:)` is built for
  in-place edits whose save may fail.
- `Cadence/Shared/CadenceNoteFolderSupport.swift:205` - note creation already uses `commitInsert`;
  this move path is the nearby unpinned sibling.

30-second confirming command:

```sh
rg -n "NoteActionSupport\\.move|dismissPicker\\(\\)|try\\? modelContext\\?\\.save\\(\\)|note\\.area|note\\.project" Cadence/macOS/Views/AIActionsSupportViews.swift Cadence/Services/AI/AIActionService.swift CadenceTests docs/TODO.md
```

Suggested fix:

- Make `NoteActionSupport.move` throwing and require a non-optional `ModelContext`.
- Capture old `area`, `project`, and `updatedAt`.
- Commit through `CadencePendingChangePersistence.commitEdit(in:undo:)`.
- Dismiss only after success. On failure, keep the picker open or show an inline popover notice.

Acceptance checks:

- A refused commit restores `area`, `project`, and `updatedAt`, leaves the picker open, and exposes
  the failure notice.
- A successful move persists the destination and dismisses exactly once.
- A source test pins `NoteActionSupport.move` as throwing/non-optional-context and rejects
  `dismissPicker()` before the successful return.

### CXT-003: Calendar settings link changes mutate visible list state, then silently fail or only print on save failure

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. A user can toggle or repair a linked calendar for an Area/Project. The
  model field changes first; save failure is swallowed on iOS and only printed on macOS.

Risk:

- The settings UI can show the new calendar link even though persistence refused it.
- A later unrelated save or rollback can decide the final outcome.

Exact spots:

- `Cadence/iOS/iOSCalendarSettingsSection.swift:182` - `toggleCalendar` mutates
  `area.linkedCalendarID`.
- `Cadence/iOS/iOSCalendarSettingsSection.swift:187` - `toggleCalendar` mutates
  `project.linkedCalendarID`.
- `Cadence/iOS/iOSCalendarSettingsSection.swift:197` - `relink` mutates missing link targets.
- `Cadence/iOS/iOSCalendarSettingsSection.swift:207` - `saveCalendarLinks` uses
  `try? modelContext.save()`.
- `Cadence/macOS/Views/SettingsListManagementSections.swift:170` - same toggle shape on macOS.
- `Cadence/macOS/Views/SettingsListManagementSections.swift:195` - save failure is only
  `print(...)`.

Existing correct pattern:

- `Cadence/macOS/Views/SettingsTagsSection.swift:419` captures previous fields and commits through
  `CadencePendingChangePersistence.commitEdit`.
- `Cadence/iOS/iOSListEditorViews.swift:465` uses the same edit-commit pattern with an inline
  failure notice.

30-second confirming command:

```sh
rg -n "saveCalendarLinks|toggleCalendar\\(|relink\\(|linkedCalendarID|try\\? modelContext\\.save\\(|failed to save calendar links" Cadence/iOS/iOSCalendarSettingsSection.swift Cadence/macOS/Views/SettingsListManagementSections.swift CadenceTests docs/TODO.md
```

Suggested fix:

- Capture previous `linkedCalendarID`.
- Use `CadencePendingChangePersistence.commitEdit(in:undo:)`.
- Show an inline settings failure notice on both platforms.
- Keep hidden-calendar `UserDefaults` toggles separate; this finding is only Area/Project SwiftData
  links.

Acceptance checks:

- Injected refusal restores the exact previous `linkedCalendarID` and leaves a visible notice on
  both platforms.
- Success persists the new identifier and clears an older failure notice.
- Source coverage inventories every Area/Project link writer and rejects `try? save()` or print-only
  failure handling in those functions.

### CXT-004: Task composers can insert a new tag before the task exists, then leave that tag pending on cancel or failed task save

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. Several task-composer tag pickers call `TagSupport.resolveTags`, which
  inserts a missing `Tag` into the ambient `ModelContext`, before the user has committed the task.

Risk:

- If the user creates/selects a new tag and then cancels the composer, the tag row remains pending in
  the app-wide `ModelContext` and can be committed by a later unrelated save.
- If task creation later fails, `TaskCreationService.createTask` deletes only the task and subtasks
  it inserted. It does not include pre-created tags in the undo list, so a failed task save can still
  leave the tag pending.

Exact spots:

- `Cadence/macOS/Sheets/CreateTaskSheet.swift:486` - `createTag` resolves/inserts a tag from the
  ambient context.
- `Cadence/macOS/Views/InlineTaskComposerView.swift:251` - inline composer does the same before its
  eventual create.
- `Cadence/iOS/iOSCreateTaskSheet.swift:228` - iOS create-sheet `onCreateTag` resolves/inserts and
  selects the tag in draft state.
- `Cadence/Services/TaskCreationService.swift:145` - task creation commits only
  `insertion.inserted`.
- `Cadence/Services/TaskCreationService.swift:172` - `insertion.inserted` is `[task] + subtasks`,
  not any tags already inserted by the UI.

Existing correct pattern:

- `Cadence/macOS/Views/SettingsTagsSection.swift:170` and
  `Cadence/iOS/iOSSettingsTagsSection.swift:143` create real tag rows through
  `CadencePendingChangePersistence.commitInsert`.
- `TaskCreationService.createTask` already knows how to commit an inserted graph; the missing part is
  that tags are resolved outside that graph.

30-second confirming command:

```sh
rg -n "TagSupport\\.resolveTags\\(named: \\[name\\]|private func createTag\\(_ name|onCreateTag: \\{ name|createTask\\(|insertion\\.inserted|return \\(task, \\[task\\] \\+ subtasks\\)" Cadence/macOS/Sheets/CreateTaskSheet.swift Cadence/macOS/Views/InlineTaskComposerView.swift Cadence/iOS/iOSCreateTaskSheet.swift Cadence/Services/TaskCreationService.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Do not insert tags during task draft selection. Either keep a draft tag token until task creation,
  or move tag resolution into `TaskCreationService`.
- If task creation resolves new tags, return those inserted tags in the same inserted graph as the
  task and subtasks.
- On failed task creation, `commitInsert` should remove every row the user just caused to exist.

Acceptance checks:

- Creating a draft-only tag and cancelling leaves the tag table unchanged.
- A refused task commit removes the task, subtasks, and only the newly inserted tags; pre-existing
  tags remain untouched.
- A successful create stores one canonical tag and points the task at it on all three composer
  surfaces.
- Source coverage rejects ambient `TagSupport.resolveTags` calls from task-draft UI.

### CXT-005: Embedded task-card quick edits repaint notes over swallowed or missing commits

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. The embedded task card's quick checkbox/title paths mutate the task and
  refresh the rendered card without the commit discipline used by the full embed-field popover.

Risk:

- macOS repaints the embedded card after `try? modelContext.save()`, so a refused save still updates
  the visible note card.
- iOS embedded task completion returns updated render info without an obvious save in that function;
  the shared `CadenceTaskStatusEditing.toggleCompletion` mutates and reconciles notifications, but
  does not commit.
- Completion can spawn recurrence successors. A refused or missing commit path needs the same cleanup
  discipline as other task-field edits.

Exact spots:

- `Cadence/macOS/Views/NotePanel.swift:287` - `toggleEmbeddedTask` mutates task completion.
- `Cadence/macOS/Views/NotePanel.swift:294` - save is swallowed.
- `Cadence/macOS/Views/NotePanel.swift:295` - card render info is updated anyway.
- `Cadence/macOS/Views/NotePanel.swift:302` - `toggleEmbeddedSubtask` mutates a subtask.
- `Cadence/macOS/Views/NotePanel.swift:306` - save is swallowed, then line 307 refreshes the card.
- `Cadence/macOS/Views/NotePanel.swift:310` - `renameEmbeddedTask` mutates title/priority, line 315
  swallows save, line 316 refreshes the card.
- `Cadence/macOS/Views/ListNotesSupportViews.swift:344` - `toggleEmbeddedTask` repeats the same
  checkbox quick-edit path for list note cards.
- `Cadence/macOS/Views/ListNotesSupportViews.swift:351` - save is swallowed, then line 352 refreshes
  the editor's embedded-card map.
- `Cadence/macOS/Views/ListNotesSupportViews.swift:359` - `toggleEmbeddedSubtask` mutates a subtask,
  line 363 swallows save, line 364 refreshes.
- `Cadence/macOS/Views/ListNotesSupportViews.swift:367` - `renameEmbeddedTask` mutates title,
  line 372 swallows save, line 373 refreshes.
- `Cadence/macOS/Views/NoteEditorPane.swift:503` - `toggleEmbeddedTask` repeats the same pattern in
  the standalone note editor pane.
- `Cadence/macOS/Views/NoteEditorPane.swift:510` - save is swallowed, then line 511 refreshes.
- `Cadence/macOS/Views/NoteEditorPane.swift:518` - `toggleEmbeddedSubtask` mutates a subtask,
  line 522 swallows save, line 523 refreshes.
- `Cadence/macOS/Views/NoteEditorPane.swift:526` - `renameEmbeddedTask` mutates title, line 531
  swallows save, line 532 refreshes.
- `Cadence/iOS/iOSMarkdownEditingSurface.swift:380` - `toggleEmbeddedTask` mutates completion and
  returns new render info without a local save.
- `Cadence/iOS/iOSMarkdownEditingSurface.swift:386` - `toggleEmbeddedSubtask` mutates a subtask,
  line 392 swallows save, line 393 returns new render info.

Existing correct pattern:

- `Cadence/Shared/CadenceTaskFieldEditCommit.swift:78` exists for task embed-card edits: commit first,
  undo on failure, then repaint.
- `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift:429` uses that helper and calls `onChanged`
  only after a successful commit.

30-second confirming command:

```sh
rg -n "toggleEmbeddedTask|toggleEmbeddedSubtask|renameEmbeddedTask|MarkdownTaskEmbedRenderInfo\\.task\\(task\\)|try\\? modelContext\\.save\\(\\)|CadenceTaskFieldEditCommit\\.commit" Cadence/macOS/Views/NotePanel.swift Cadence/macOS/Views/ListNotesSupportViews.swift Cadence/macOS/Views/NoteEditorPane.swift Cadence/iOS/iOSMarkdownEditingSurface.swift Cadence/Shared/CadenceTaskFieldEditCommit.swift Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Route embedded task completion/title edits through `CadenceTaskFieldEditCommit.commit`.
- Repaint/return updated render info only when the commit succeeds.
- For subtask-only edits, use `CadencePendingChangePersistence.commitEdit(in:undo:)` or extend the
  task-field snapshot to include the touched subtask's `isDone`/title as needed.

Acceptance checks:

- Injected refusal restores task/subtask fields, removes any recurrence successor created by the
  attempted completion, and does not invoke the repaint callback.
- Success commits once, reconciles notifications where status changed, and repaints once.
- Source coverage requires every listed macOS and iOS quick-edit body to use the committed helper;
  the full field popover alone is not sufficient coverage.

### CXT-006: macOS kanban column lifecycle edits can close the editor over a swallowed save after mutating column state and tasks

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. The macOS kanban column editor toggles completion/archive, may settle
  tasks through `TaskContainerLifecycleService`, swallows the save, and then closes the editor.

Risk:

- Completing or archiving a column mutates `sectionConfigsRaw` and can mark/cancel active tasks.
- If save is refused, the editor still closes and the task/column mutations remain pending in the
  shared `ModelContext`.
- Notification reconciliation is part of the wind-down service path, so a refused save can also leave
  side effects needing a restoring reconcile.

Exact spots:

- `Cadence/macOS/Views/KanbanSectionColumnView.swift:389` - completion action calls
  `toggleSectionCompletion`.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:391` - completion action closes the editor.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:393` - archive action starts an in-place column
  edit.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:404` - archive can cancel remaining active
  tasks before save.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:406` - archive save is swallowed.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:407` - archive action closes the editor anyway.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:503` - `saveSection` writes section config and
  may complete/cancel active tasks.
- `Cadence/macOS/Views/KanbanSectionColumnView.swift:511` - `saveSection` swallows save.

Existing correct pattern:

- `Cadence/Shared/CadenceListEditSnapshot.swift:22` snapshots `sectionConfigsRaw`, which is the right
  raw stored field to restore for list/section edits.
- `Cadence/Shared/CadenceTaskFieldEditCommit.swift:101` documents why notification reconcile has to
  run again after restoring a refused task/date edit.
- `CadencePendingChangePersistence.commitEdit(in:undo:)` is the base commit shape.

30-second confirming command:

```sh
rg -n "showEditor = false|toggleSectionCompletion\\(|saveSection\\(|TaskContainerLifecycleService\\.(completeRemainingActiveTasks|cancelRemainingActiveTasks)|try\\? modelContext\\.save\\(\\)|sectionConfigsRaw|commitEdit" Cadence/macOS/Views/KanbanSectionColumnView.swift Cadence/Shared/CadenceListEditSnapshot.swift Cadence/Shared/CadenceTaskFieldEditCommit.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Snapshot the owning Area/Project section config raw value before mutation.
- Snapshot affected active tasks before lifecycle settle.
- Commit through `CadencePendingChangePersistence.commitEdit(in:undo:)`.
- Undo must restore both the section config and every task changed by the lifecycle service, then
  reconcile notifications again.
- Close `showEditor` only after a successful commit; keep or add a column-editor failure notice.

Acceptance checks:

- Injected refusal restores `sectionConfigsRaw`, every settled task's status/completion fields, and
  any recurrence side effects; the editor stays open with a notice.
- Failure triggers a restoring notification reconcile after model restoration.
- Success settles the intended tasks once, persists the column state, and closes the editor.
- Source coverage pins both completion and archive actions to the same committed path.

### CXT-007: Boolean-returning drag/drop handlers can report success after swallowing the save

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. A refused SwiftData save after these drops still leaves the drop caller
  holding `true`, while the live `ModelContext` contains task moves the store may not hold.
- Not the old ticket: T-607 is about accepting a section drop that resolved no assignment. This is a
  later failure mode: the assignment resolves and mutates, but the commit is swallowed.

Risk:

- The drop UI can animate or stop fallback handling because the handler returned success.
- The moved task remains mutated in the shared app context, so a later unrelated save can commit the
  move, or a later rollback can make the apparent drop disappear.
- Calendar rail drops can also remove a task from a bundle before the swallowed save.

Exact spots:

- `Cadence/macOS/Views/TasksPanelSupport.swift:253` - `assignTask` documents that its return value
  reports whether a drop landed.
- `Cadence/macOS/Views/TasksPanelSupport.swift:270` - `assignTask` returns `Bool`.
- `Cadence/macOS/Views/TasksPanelSupport.swift:290` - unresolved drops return `false`.
- `Cadence/macOS/Views/TasksPanelSupport.swift:291` - resolved drops swallow `modelContext.save()`.
- `Cadence/macOS/Views/TasksPanelSupport.swift:292` - resolved drops return `true` regardless of
  save failure.
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:313` - the unscheduled rail drop returns
  `Bool`.
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:319` - bundled tasks are removed from
  their bundle before the save.
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:323` - the planner clears the task's board
  placement fields.
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:325` - save is swallowed.
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:326` - the handler returns `true`.

Existing correct pattern:

- `Cadence/iOS/iOSCalendarBoardView.swift:233` explicitly documents a drag-save swallow that does
  not report success or dismiss UI. That is the allowed case.
- `CadencePendingChangePersistence.commitEdit(in:undo:)` is the right shape when a caller needs a
  success/failure answer.

30-second confirming command:

```sh
rg -n -U "try\\? modelContext\\.save\\(\\)\\s*\\n\\s*return true|assignTask\\(|handleRailDrop\\(|unschedule\\(|CalendarBoardPlannerSupport\\.apply|SchedulingActions\\.removeTaskFromBundle" Cadence/macOS/Views/TasksPanelSupport.swift Cadence/macOS/Views/CalendarPageBoardSupportViews.swift Cadence/iOS/iOSCalendarBoardView.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Snapshot the task fields, and for calendar rail drops also snapshot the bundle membership touched
  by `SchedulingActions.removeTaskFromBundle`.
- Commit through `CadencePendingChangePersistence.commitEdit(in:undo:)`.
- Return `true` only if the commit lands; on failure restore the task/bundle state and return `false`
  or surface a failure notice where the drop UI already has one.

Acceptance checks:

- A resolvable drop with an injected refused commit returns `false` and restores task dates,
  container fields, and bundle membership.
- A successful resolved drop returns `true`; an unresolved key still returns `false` without
  attempting a commit.
- Source coverage rejects `try? save()` followed by `return true` in every Bool-returning drop
  handler, including compound Today drop keys.

### CXT-008: Focus completion helpers reset or clear timers after swallowed focus-session commits

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. iOS focus completion and shared focus-session end paths log minutes and
  mark tasks done, swallow the save, then hand the UI a reset timer state.

Risk:

- Completing a focused task can log minutes and mark a recurring task done through the shared helper,
  then reset/adopt the next item even if the save is refused.
- Ending or switching focus through the shared subject-shaped helper can return a reset timer state
  after `try? modelContext.save()`.
- Because logged minutes roll up into project/area totals, a refused save here can make hours-mode
  goal progress appear to land without durable storage.

Exact spots:

- `Cadence/iOS/iOSFocusView.swift:652` - `complete(_:)` starts the iOS task-completion path.
- `Cadence/iOS/iOSFocusView.swift:653` - task completion calls `CadenceTaskStatusEditing.completeFocusSession`.
- `Cadence/iOS/iOSFocusView.swift:654` - the timer resets immediately after that helper returns.
- `Cadence/Shared/CadenceTaskStatusEditing.swift:87` - the status helper delegates to
  `CadenceFocusSupport.complete`.
- `Cadence/Shared/CadenceFocusPlanningSupport.swift:230` - `complete` logs elapsed time and marks
  the task done.
- `Cadence/Shared/CadenceFocusPlanningSupport.swift:233` - `complete` swallows the save.
- `Cadence/iOS/iOSFocusView.swift:665` - bundle completion starts the iOS bundle path.
- `Cadence/iOS/iOSFocusView.swift:670` - bundle completion swallows the save.
- `Cadence/iOS/iOSFocusView.swift:671` - bundle completion resets the timer anyway.
- `Cadence/Shared/CadenceFocusBundleSupport.swift:303` - `endSession` is the shared leave-session
  helper used by iOS close/disappear paths.
- `Cadence/Shared/CadenceFocusBundleSupport.swift:309` - it prepares a reset timer state before save.
- `Cadence/Shared/CadenceFocusBundleSupport.swift:322` - it swallows save.
- `Cadence/Shared/CadenceFocusBundleSupport.swift:323` - it returns the reset state.

Existing correct pattern:

- `Cadence/Shared/CadenceTaskFieldEditCommit.swift:93` documents the recurrence-spawn cleanup problem
  for task completion, including deleting successors created by a refused completion.
- `CadencePendingChangePersistence.commitEdit(in:undo:)` plus a task/list snapshot is the repo's
  current way to report a refused mutation without rolling back unrelated pending editor text.

30-second confirming command:

```sh
rg -n "private func complete\\(|private func logBundleSession|completeFocusSession|static func complete\\(|static func endSession\\(|logElapsedSeconds\\(|markDone\\(|try\\? modelContext\\.save\\(\\)|resetTimer\\(\\)|return reset" Cadence/iOS/iOSFocusView.swift Cadence/Shared/CadenceTaskStatusEditing.swift Cadence/Shared/CadenceFocusPlanningSupport.swift Cadence/Shared/CadenceFocusBundleSupport.swift Cadence/macOS/Services/FocusManager.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Make the focus completion/end helpers return whether the commit landed, or throw on refused saves.
- Snapshot touched tasks and parent list logged-minute totals before logging/marking done.
- If completion can spawn recurrence successors, clean those up on failure the same way
  `CadenceTaskFieldEditCommit` does.
- Reset/clear/adopt the next iOS focus target only after a successful commit; otherwise keep the
  timer state and show a focus failure notice.

Acceptance checks:

- Injected refusal restores logged minutes, task/list rollups, status/completion timestamps, and any
  recurrence successor, while preserving the running timer and selected subject.
- A failed bundle-session end restores every selected member touched by elapsed-time distribution.
- Success commits before timer reset/subject adoption and reconciles notifications exactly once.
- Tests exercise task completion, bundle logging, and plain session exit as separate branches.

### CXT-009: iOS recurrence row edits close their scope state before a swallowed save

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. Picking a repeat rule from an iOS task row mutates recurrence fields,
  and the series-scope path clears `pendingRecurrenceRule` before `try? modelContext.save()`.

Risk:

- A non-series task's repeat chip/context menu can show the new rule in memory even if the save is
  refused.
- A series task's scope dialog closes before the commit is known, so a refused save leaves no place
  for the existing "Couldn't Update the Series" style failure to land.
- `.thisAndFuture` can rewrite every later occurrence; a refused save needs to restore every touched
  occurrence, not just the row task.

Exact spots:

- `Cadence/iOS/iOSTaskRowActionViews.swift:341` - `iOSTaskRecurrenceSelection.select` is shared by
  the repeat chip and row context menu.
- `Cadence/iOS/iOSTaskRowActionViews.swift:353` - non-series path applies the recurrence rule.
- `Cadence/iOS/iOSTaskRowActionViews.swift:359` - non-series path swallows the save.
- `Cadence/iOS/iOSTaskRowActionViews.swift:807` - the row already has a recurrence failure alert for
  series lookup failures.
- `Cadence/iOS/iOSTaskRowActionViews.swift:814` - `applyPendingRecurrenceRule` handles the series
  scope dialog action.
- `Cadence/iOS/iOSTaskRowActionViews.swift:832` - series path applies the recurrence rule.
- `Cadence/iOS/iOSTaskRowActionViews.swift:838` - series path clears `pendingRecurrenceRule`, closing
  the scope state.
- `Cadence/iOS/iOSTaskRowActionViews.swift:839` - series path swallows the save.

Existing correct pattern:

- `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift:410` computes the recurrence target list
  before applying a rule.
- `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift:416` commits with `alsoRestoring: targets`.
- `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift:430` uses `CadenceTaskFieldEditCommit`.
- `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift:414` tests that a refused series recurrence
  edit restores every occurrence it touched.

30-second confirming command:

```sh
rg -n "iOSTaskRecurrenceSelection|applyPendingRecurrenceRule|applyRecurrenceRule\\(|pendingRecurrenceRule = nil|try\\? modelContext\\.save\\(\\)|TaskEmbedFieldEditorPopover|CadenceTaskFieldEditCommit|arefusedSeriesRecurrenceEditRestoresEveryOccurrenceItTouched" Cadence/iOS/iOSTaskRowActionViews.swift Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift Cadence/Shared/CadenceTaskFieldEditCommit.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Compute the recurrence targets before applying the row edit.
- Commit through `CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext)`.
- Clear `pendingRecurrenceRule` and close the scope dialog only after the commit succeeds.
- Reuse the existing row recurrence failure alert for save refusal, with copy that says the change was
  not saved rather than that the series lookup failed.

Acceptance checks:

- Injected refusal restores every occurrence touched by `.thisAndFuture`, leaves the pending rule/
  scope state available for retry, and shows the save-specific alert.
- A non-series refusal restores the single task and does not leave a pending recurrence mutation.
- Success clears pending state only after commit and applies the chosen scope exactly once.
- Source coverage requires both the chip path and context-menu path to reach the same committed
  helper.

### CXT-010: macOS task-status controls can mutate completion/cancellation without any explicit save

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. macOS task rows/cards and the inspector can mark tasks done/cancelled
  through `TaskWorkflowService`, which mutates and reconciles notifications but does not save.
- Not the old ticket: T-343/T-407 pinned the seven iOS status surfaces to route through
  `CadenceTaskStatusEditing`. The macOS inspector and animation manager are outside that list.

Risk:

- A macOS completion/cancellation can visibly settle a task, spawn a recurrence successor, and schedule
  notification reconciliation while the SwiftData context still has pending changes.
- The delayed animation manager makes this harder to spot: the visible fill finishes, then the model
  changes, but no commit boundary is reached.
- A later unrelated save can commit the status change, or a later rollback can discard work the UI
  already showed as done/cancelled.

Exact spots:

- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:50` - completion-circle toggle enters
  the manager.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:70` - completion starts a delayed task.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:81` - delayed completion writes `.done`.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:98` - cancellation-circle toggle enters
  the manager.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:131` - delayed cancellation writes
  `.cancelled`.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:163` - all status writes funnel here.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:169` - restore path calls
  `TaskWorkflowService.markTodo`.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:172` - done path calls
  `TaskWorkflowService.markDone`.
- `Cadence/macOS/Services/TaskCompletionAnimationManager.swift:178` - cancelled path calls
  `TaskWorkflowService.markCancelled`.
- `Cadence/macOS/Services/TaskWorkflowService.swift:6` - `markDone` mutates via recurrence workflow and
  schedules notification reconcile, but does not save.
- `Cadence/macOS/Views/TaskInspectorContentSupportViews.swift:306` - inspector action button starts an
  immediate status toggle.
- `Cadence/macOS/Views/TaskInspectorContentSupportViews.swift:308` - inspector restore path calls
  `TaskWorkflowService.markTodo`.
- `Cadence/macOS/Views/TaskInspectorContentSupportViews.swift:310` - inspector done path calls
  `TaskWorkflowService.markDone`.
- `Cadence/macOS/Views/TimelineTaskBlock.swift:69` - timeline task block reaches the animation manager.
- `Cadence/macOS/Views/KanbanCardComputedSupport.swift:69` - kanban card reaches the animation manager.
- `Cadence/macOS/Views/TasksPanelComponents.swift:584` - task panel row reaches the animation manager.
- `Cadence/macOS/Views/macOSRootCommandEventSupport.swift:149` - keyboard completion command reaches
  the animation manager.

Existing correct pattern:

- `Cadence/Shared/CadenceTaskStatusEditing.swift:54` and `:65` are the app-side status wrappers the
  iOS surfaces use.
- `CadenceTests/CadenceTaskStatusEditingSurfaceTests.swift:145` lists only the routed iOS status
  surfaces, which is why the macOS drift can survive those tests.
- `Cadence/Shared/CadenceTaskFieldEditCommit.swift:93` is the stronger pattern for task completion
  that may spawn recurrence successors and need cleanup on failure.

30-second confirming command:

```sh
rg -n "TaskCompletionAnimationManager|TaskWorkflowService\\.(markDone|markTodo|markCancelled)|TaskDetailActionsSection|CadenceTaskStatusEditing|routedStatusSurfaces|toggleCompletion\\(for:|manager\\.toggleCompletion|macOSRootCommandEventSupport" Cadence/macOS/Services/TaskCompletionAnimationManager.swift Cadence/macOS/Services/TaskWorkflowService.swift Cadence/macOS/Views/TaskInspectorContentSupportViews.swift Cadence/macOS/Views/TimelineTaskBlock.swift Cadence/macOS/Views/KanbanCardComputedSupport.swift Cadence/macOS/Views/TasksPanelComponents.swift Cadence/macOS/Views/macOSRootCommandEventSupport.swift Cadence/Shared/CadenceTaskStatusEditing.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Give macOS status surfaces a committing wrapper that can report failure, rather than calling
  `TaskWorkflowService` directly.
- For delayed animation writes, keep the pending state until the commit lands; if it fails, restore
  the task and cancel the visible completion/cancellation state.
- Include recurrence-successor cleanup and notification re-reconcile on failure, matching the
  `CadenceTaskFieldEditCommit` discipline.

Acceptance checks:

- Every macOS status entry point, including the inspector and root keyboard command, reaches one
  committed status wrapper rather than `TaskWorkflowService` directly.
- Injected refusal restores status/completion timestamps, removes any recurrence successor, runs a
  restoring reconcile, and returns the animation manager to its pre-action state.
- Success commits before the terminal animation state is published.
- Extend `CadenceTaskStatusEditingSurfaceTests` with the macOS inventory and a failing-commit test;
  direct `TaskWorkflowService.mark*` calls from UI files should be red.

### CXT-011: macOS bundle popover end actions close after complete/unbundle/delete mutations with no commit path

- Severity: P2
- Confidence: measured source / inferred runtime
- Can this happen today: yes. Both macOS bundle popover hosts call `SchedulingActions` end actions
  that mutate or delete the bundle, then clear selection/close the popover without committing.
- Not the old ticket: T-322 fixed the shared `CadenceTaskMutationSupport.deleteBundle` path used by
  iOS. These macOS popovers still call the older `SchedulingActions` path directly.

Risk:

- Completing a bundle marks unfinished member tasks done, detaches every member, deletes the bundle,
  and can spawn recurrence successors without a commit boundary.
- Unbundle/delete detach members and delete the bundle, then close the popover; the shared context
  keeps the changes pending.
- If a later save commits them, the bundle disappears long after the user action; if a later rollback
  discards them, the UI had already closed over work that did not land.

Exact spots:

- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:121` - calendar-board bundle popover
  complete action starts.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:126` - complete calls
  `SchedulingActions.completeBundle`.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:127` - complete closes the popover.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:130` - unbundle calls
  `SchedulingActions.unbundle`.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:131` - unbundle closes the popover.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:134` - delete calls
  `SchedulingActions.deleteBundle`.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:135` - delete closes the popover.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:123` - timeline bundle popover complete action starts.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:128` - complete calls
  `SchedulingActions.completeBundle`.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:129` - complete clears the selected bundle.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:132` - unbundle calls `SchedulingActions.unbundle`.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:133` - unbundle clears the selected bundle.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:136` - delete calls `SchedulingActions.deleteBundle`.
- `Cadence/macOS/Views/TimelineBundleBlock.swift:137` - delete clears the selected bundle.
- `Cadence/macOS/Services/SchedulingService.swift:165` - `completeBundle` begins the mutation.
- `Cadence/macOS/Services/SchedulingService.swift:169` - complete marks active tasks done.
- `Cadence/macOS/Services/SchedulingService.swift:177` - complete empties the bundle.
- `Cadence/macOS/Services/SchedulingService.swift:178` - complete deletes the bundle.
- `Cadence/macOS/Services/SchedulingService.swift:187` - `unbundle` begins.
- `Cadence/macOS/Services/SchedulingService.swift:189` - unbundle deletes the bundle.
- `Cadence/macOS/Services/SchedulingService.swift:207` - `deleteBundle` forwards to unbundle.

Existing correct pattern:

- `Cadence/Shared/CadenceTaskMutationSupport.swift:1050` exposes a throwing `deleteBundle`.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:1065` commits bundle deletion through
  `CadencePendingChangePersistence.commitDelete`.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:423` already has the user-facing delete failure
  sentence.

30-second confirming command:

```sh
rg -n "SchedulingActions\\.(completeBundle|unbundle|deleteBundle)|showPopover = false|selectedBundleID = nil|static func completeBundle|static func unbundle|static func deleteBundle|CadenceTaskMutationSupport\\.deleteBundle|bundleDeleteFailureNotice|commitDelete" Cadence/macOS/Views/CalendarBoardItemSupportViews.swift Cadence/macOS/Views/TimelineBundleBlock.swift Cadence/macOS/Services/SchedulingService.swift Cadence/Shared/CadenceTaskMutationSupport.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Move complete/unbundle/delete bundle endings onto shared throwing helpers, or give
  `SchedulingActions` committing variants that use `CadencePendingChangePersistence`.
- Close `showPopover` / clear `selectedBundleID` only after the commit succeeds.
- On failure, restore bundle/member state, undo any recurrence successor inserts, and show
  `bundleDeleteFailureNotice` or a new complete/unbundle-specific block failure notice.

Acceptance checks:

- Injected refusal for complete restores the bundle, member relationships/statuses, schedule fields,
  and any recurrence successors; the popover remains selected.
- Refused unbundle/delete leaves the original bundle and ordering visible with an operation-specific
  notice.
- Success commits the complete/unbundle/delete mutation before either host closes its popover.
- Source coverage inventories all six host actions and rejects direct non-committing
  `SchedulingActions` end calls.

### CXT-012: macOS calendar-event edit surfaces discard typed EventKit write failures

- Severity: P3
- Confidence: measured source / inferred runtime
- Can this happen today: yes. The macOS timeline and calendar-board event surfaces call EventKit
  writes whose return type is `CalendarWriteFailure?`, but ignore the returned failure.
- Narrow impact: `CalendarManager.record` still stores many failures on `lastWriteFailure`, so this
  is not necessarily fully silent. The local editing surfaces still close/clear state instead of
  using the typed failure the manager handed them.

Risk:

- The calendar-board popover closes after a refused save/delete, even though the manager can say why
  the write failed.
- Timeline drag/resize/delete paths also discard the typed result, so they cannot keep local mutation
  state or present operation-specific copy.
- The iOS event sheet already has the better shape: failure stays in the sheet and successful writes
  dismiss.

Exact spots:

- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:166` - board popover save callback starts.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:168` - save calls `calendarManager.updateEvent`.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:177` - save closes `showPopover` regardless
  of the returned failure.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:179` - delete callback starts.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:186` - delete calls
  `calendarManager.deleteEvent`.
- `Cadence/macOS/Views/CalendarBoardItemSupportViews.swift:187` - delete closes `showPopover`
  regardless of the returned failure.
- `Cadence/macOS/Views/TimelineEventBlock.swift:123` - timeline edit popover save calls
  `calendarManager.updateEvent`.
- `Cadence/macOS/Views/TimelineEventBlock.swift:132` - timeline edit popover clears selection after
  save.
- `Cadence/macOS/Views/TimelineEventBlock.swift:301` - timeline delete confirm calls
  `calendarManager.deleteEvent`.
- `Cadence/macOS/Views/TimelineEventBlock.swift:311` - timeline drag/resize calls
  `calendarManager.updateEvent`.
- `Cadence/macOS/Services/CalendarManager.swift:286` - desktop `updateEvent` returns
  `CalendarWriteFailure?`.
- `Cadence/macOS/Services/CalendarManager.swift:345` - desktop `deleteEvent` returns
  `CalendarWriteFailure?`.
- `Cadence/macOS/Services/CalendarManager.swift:378` - `record` stores the typed failure.

Existing correct pattern:

- `Cadence/iOS/iOSCalendarEventEditSheet.swift:570` checks `calendarManager.updateEvent`.
- `Cadence/iOS/iOSCalendarEventEditSheet.swift:584` writes
  `CadenceCalendarEventEditingSupport.saveFailureNotice(for:)` and returns on failure.
- `Cadence/iOS/iOSCalendarEventEditSheet.swift:592` checks `calendarManager.deleteEvent`.
- `Cadence/iOS/iOSCalendarEventEditSheet.swift:593` writes
  `CadenceCalendarEventEditingSupport.deleteFailureNotice(for:)` on failure.
- `Cadence/Shared/CadenceCalendarEventEditingSupport.swift:36` and `:41` hold the shared typed
  failure copy.

30-second confirming command:

```sh
rg -n "updateEvent\\(|deleteEvent\\(|showPopover = false|selectedEventID = nil|CalendarWriteFailure|lastWriteFailure|saveFailureNotice\\(for:|deleteFailureNotice\\(for:" Cadence/macOS/Views/CalendarBoardItemSupportViews.swift Cadence/macOS/Views/TimelineEventBlock.swift Cadence/macOS/Services/CalendarManager.swift Cadence/iOS/iOSCalendarEventEditSheet.swift Cadence/Shared/CadenceCalendarEventEditingSupport.swift CadenceTests docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Capture the returned `CalendarWriteFailure?` at every macOS event write call site.
- For popover edits, keep the editor open and show
  `CadenceCalendarEventEditingSupport.saveFailureNotice(for:)` or `deleteFailureNotice(for:)`.
- For drag/resize/delete gestures, either rely explicitly on `lastWriteFailure` and document why, or
  route through a small local handler that clears gesture state only after success.

Acceptance checks:

- A typed save/delete refusal keeps the relevant editor open and renders the shared operation plus
  cause; success alone closes/clears selection.
- Drag/resize refusal leaves the event at its last stored geometry after `CalendarManager` resets it
  and exposes one deliberate failure channel.
- Source coverage rejects discarded `updateEvent`/`deleteEvent` results in both macOS hosts.
- Existing iOS typed-failure behavior and shared failure copy remain unchanged.

### CXT-013: Task-detail subtask creation and deletion can advance the UI without a durable existence commit

- Severity: P2
- Confidence: measured source / inferred runtime failure
- Can this happen today: yes. The macOS `TaskDetailPopover` is presented from seven task surfaces;
  adding or deleting a subtask there never reaches a save. The iOS task detail does reach a save,
  but swallows it and clears the add draft before persistence is known.
- Code defect: the cross-file helper is correctly transaction-neutral, but these UI callers do not
  finish the transaction safely.
- Unpinned guard: the subtask parity tests require every caller to route through the helper, but do
  not require an ambient-context caller to commit the helper's insert/delete result.

Risk:

- macOS can show a newly added subtask or hide a deleted one while the change remains pending in the
  app-wide `ModelContext`; a later unrelated save or rollback decides its fate.
- iOS clears `newSubtaskTitle` after an insert even when the save is refused, and both insert/delete
  leave pending existence changes on the same failure.
- This is narrower than the broad `try? save()` audit: the mutation is an insert/delete hidden one
  call down, so the existing same-function existence scan cannot see it.

Exact spots:

- `Cadence/macOS/Views/SchedulePanelComponents.swift:103` - the delete confirmation calls the shared
  delete helper; its closure ends at line 109 with no commit.
- `Cadence/macOS/Views/SchedulePanelComponents.swift:147` - `addSubtask` calls the insert helper.
- `Cadence/macOS/Views/SchedulePanelComponents.swift:153` - the add draft is cleared; the function
  ends at line 154 with no commit.
- `Cadence/macOS/Views/ListNotesSupportViews.swift:140`, `NoteEditorPane.swift:261`,
  `NotePanel.swift:143`, `TimelineTaskBlock.swift:134`, `CalendarPageMonthSupportViews.swift:499`,
  `TasksPanelComponents.swift:158`, and `KanbanCardView.swift:130` present this popover.
- `Cadence/iOS/iOSTaskDetailSheet.swift:459` - iOS add begins.
- `Cadence/iOS/iOSTaskDetailSheet.swift:465` - iOS clears the draft before line 466 swallows save.
- `Cadence/iOS/iOSTaskDetailSheet.swift:469` - iOS delete calls the helper, then line 471 swallows save.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:610` - the shared insert helper intentionally
  leaves saving to its caller; line 623 inserts the row.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:657` - the shared delete helper intentionally
  leaves saving to its caller; line 663 deletes the row.
- `CadenceTests/CadenceSubtaskInverseParityTests.swift:455` - tests pin helper routing, not commit
  completion or a refused-save path.

Existing correct pattern:

- `Cadence/iOS/iOSSettingsTagsSection.swift:154` inserts a user-created row, line 156 commits through
  `CadencePendingChangePersistence.commitInsert`, and line 162 clears the draft only after success.
- `Cadence/Shared/CadencePendingChangePersistence.swift:39` and `:120` are the insert/delete commit
  spines; the subtask relationship arrays need to be restored alongside the row on failure.

30-second confirming command:

```sh
rg -n "TaskDetailPopover\(task:|private func addSubtask|private func deleteSubtask|insertSubtask\(|deleteSubtask\(|newSubtaskTitle = \"\"|try\? modelContext\.save\(\)|commitInsert|commitDelete" Cadence/macOS/Views/SchedulePanelComponents.swift Cadence/macOS/Views Cadence/iOS/iOSTaskDetailSheet.swift Cadence/Shared/CadenceTaskMutationSupport.swift Cadence/iOS/iOSSettingsTagsSection.swift CadenceTests/CadenceSubtaskInverseParityTests.swift docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Give subtask insert/delete a throwing committed spelling, or make each ambient UI caller commit
  through `CadencePendingChangePersistence` with explicit relationship restoration.
- Clear the add draft and close delete confirmation only after success.
- Put an inline failure notice in the still-open task popover/sheet.
- Extend the source guard so a helper handed `ModelContext` remains transaction-neutral, while an
  ambient-context UI caller is required to consume it through a commit path.

Acceptance checks:

- A refused insert leaves no stored or pending subtask, restores both relationship directions, keeps
  the typed draft, and shows a notice on macOS and iOS.
- A refused delete restores the row and both relationship directions before reporting failure.
- Success creates/deletes exactly one subtask and advances draft/confirmation UI only after commit.
- Extend `CadenceSubtaskInverseParityTests` with injected commit refusal and ambient-caller commit
  coverage, while preserving the transaction-neutral shared helper.

### CXT-014: Today rollover returns the dismissal key after a swallowed batch save

- Severity: P2
- Confidence: measured source / inferred runtime failure
- Can this happen today: yes. Pressing Roll Over on either platform mutates every offered task and
  assigns the returned day key to `@AppStorage`, hiding the banner for the rest of the day.
- Code defect: `rollOver` returns the success token unconditionally after `try? save()`.
- Unpinned guard: the existing test asserts the returned key and in-memory dates only; it has no
  injected failing commit that can distinguish success from refusal.

Risk:

- A refused save still hides the rollover banner on both iOS and macOS.
- The task rows remain changed in the shared live context, so they may look rolled over until an
  unrelated rollback, or be committed later by an unrelated save.
- The batch is not field-only: leaving a bundle can delete a fully settled bundle, so failure
  restoration must include relationship and existence changes.

Exact spots:

- `Cadence/Shared/CadenceTodayRolloverSupport.swift:90` - the batch mutation starts.
- `Cadence/Shared/CadenceTodayRolloverSupport.swift:98` - the batch save is swallowed.
- `Cadence/Shared/CadenceTodayRolloverSupport.swift:99` - `todayKey` is returned regardless.
- `Cadence/macOS/Views/TasksPanel.swift:331` - macOS rollover action begins.
- `Cadence/macOS/Views/TasksPanel.swift:333` - macOS writes the unconditional return to the
  dismissal preference.
- `Cadence/iOS/iOSTodayView.swift:152` and `:154` do the same on iOS.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:983` - each task leaves its old bundle and moves
  to today.
- `Cadence/Shared/CadenceTaskMutationSupport.swift:989` - rollover may call the conditional bundle
  delete; line 1028 marks that bundle deleted.
- `CadenceTests/CadenceTodayRolloverSurfaceTests.swift:229` - the batch test's title promises only
  the returned day key; line 239 calls the real non-injectable save path.

Existing correct pattern:

- `Cadence/Shared/CadencePendingChangePersistence.swift:100` commits an edit only after capturing an
  exact undo, and `:120` handles a delete refusal.
- `Cadence/Shared/CadenceTaskFieldEditCommit.swift:93` is the nearby example of making a multi-object
  mutation failure-injectable and restoring every touched task rather than trusting a live context.

30-second confirming command:

```sh
rg -n "static func rollOver\(|try\? modelContext\.save\(\)|return todayKey|rolloverNoticeDismissedDate = CadenceTodayRolloverSupport\.rollOver|rollOverTaskToToday|deleteBundleIfFullySettled|modelContext\.delete\(bundle\)|rollingOverABatchReturnsTheDayKey" Cadence/Shared/CadenceTodayRolloverSupport.swift Cadence/Shared/CadenceTaskMutationSupport.swift Cadence/macOS/Views/TasksPanel.swift Cadence/iOS/iOSTodayView.swift CadenceTests/CadenceTodayRolloverSurfaceTests.swift docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Make rollover throwing or return a typed success/failure result; accept an injected commit so the
  refusal path is testable.
- Snapshot every task's schedule and bundle membership plus any bundle that can be deleted, and
  restore exactly those objects on failure without rolling back unrelated editor work.
- Set `rolloverNoticeDismissedDate` only after success; otherwise keep the banner visible and show a
  compact failure notice on it.
- Add a failing-commit test that requires dates, relationships, bundle existence, and the dismissal
  result all to stay unchanged.

Acceptance checks:

- Injected refusal returns failure, leaves the dismissal preference untouched, keeps the banner
  visible, and restores every task/bundle field plus any conditionally deleted bundle.
- Success returns the dismissal key only after the batch is durable on both platforms.
- Existing rollover membership/order tests remain green; the new failure test proves no unrelated
  pending edit is rolled back.
- Source coverage rejects `try? save()` and unconditional `return todayKey` in the rollover body.

### CXT-015: macOS timeline event quick-create closes after discarding CalendarManager's typed failure

- Severity: P2
- Confidence: measured source / inferred EventKit refusal
- Can this happen today: yes. Drag a time range on the Schedule or Calendar timeline, choose Calendar
  Event, and submit. Authorization loss, a read-only/no-longer-writable calendar, or an EventKit save
  error returns a typed failure, but the quick-create popover closes anyway.
- Code defect: a `CalendarWriteFailure?` API is narrowed to a `Void` callback before it reaches the
  editor that owns the draft.
- Unpinned guard: manager tests pin the typed return and canvas tests pin title forwarding, but no
  source or behavior test requires the creation callback to preserve and consume the result.

Risk:

- The user loses the title, notes, selected calendar, and time-range draft while no event was made.
- `CalendarManager.lastWriteFailure` may later raise a global alert, but it cannot keep this editor
  open or preserve the draft; the local callback has already thrown away the result.
- This is distinct from CXT-012: that item covers editing/deleting existing events. This path creates
  a new event from the timeline quick-create popover.

Exact spots:

- `Cadence/macOS/Services/CalendarManager.swift:170` - `createStandaloneEvent` returns
  `CalendarWriteFailure?`; line 185 returns the EventKit save result.
- `Cadence/macOS/Views/SchedulePanel.swift:133` - Schedule supplies the creation callback; line 134
  discards the returned failure.
- `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:606` - Calendar supplies the sibling
  callback; line 607 discards the returned failure.
- `Cadence/macOS/Views/TimelineDayCanvas.swift:33` - the canvas callback type is `Void`.
- `Cadence/macOS/Views/TimelineDayCanvas.swift:261` - event creation invokes that callback.
- `Cadence/macOS/Views/TimelineDayCanvas.swift:263` - `finishDraftCreation()` closes and clears the
  draft unconditionally.
- `Cadence/macOS/Views/QuickCreateChoicePopover.swift:217` - submit dispatch starts; line 228 invokes
  the event callback with no result channel.
- `CadenceTests/CalendarManagerScenarioTests.swift:51` proves the manager can return a concrete
  creation failure, but no call-site test consumes it.

Existing correct pattern:

- `Cadence/iOS/iOSCalendarQuickCreateSheet.swift:588` captures the typed create result, line 596
  converts failure to shared copy, and line 600 dismisses only on success.
- `Cadence/Shared/CadenceCalendarEventEditingSupport.swift:36` already owns the typed save-failure
  notice used by the iOS creation sheet.

30-second confirming command:

```sh
rg -n "createStandaloneEvent|onCreateEvent|finishDraftCreation|CalendarWriteFailure|saveFailureNotice\(for:|private func createEvent" Cadence/macOS/Services/CalendarManager.swift Cadence/macOS/Views/SchedulePanel.swift Cadence/macOS/Views/CalendarPageMonthSupportViews.swift Cadence/macOS/Views/TimelineDayCanvas.swift Cadence/macOS/Views/QuickCreateChoicePopover.swift Cadence/iOS/iOSCalendarQuickCreateSheet.swift CadenceTests/CalendarManagerScenarioTests.swift CadenceTests/CadenceCalendarConsistencySurfaceTests.swift docs/TODO.md docs/CODEX_TODO.md
```

Suggested fix:

- Change the macOS event-create callback to return `CalendarWriteFailure?` (or a small result type)
  all the way from `CalendarManager` to `TimelineDayCanvas`.
- Keep the draft/popover open on failure and show
  `CadenceCalendarEventEditingSupport.saveFailureNotice(for:)` inside it.
- Call `finishDraftCreation()` only when the callback reports success.
- Add a call-site guard proving both timeline hosts forward the typed result and the canvas branches
  dismissal on it.

Acceptance checks:

- A `.notAuthorized`, `.noWritableCalendar`, `.invalidRange`, or `.saveFailed` result preserves the
  title, notes, calendar, and time-range draft and displays the shared typed notice.
- A nil result closes and clears the draft exactly once.
- Source coverage pins a non-`Void` result from both timeline hosts through `TimelineDayCanvas` and
  rejects unconditional `finishDraftCreation()` after event creation.
- The iOS quick-create sheet remains the parity oracle for operation/cause wording.

### CXT-016: iOS omits the background mode Apple requires for prompt CloudKit silent-sync delivery

- Severity: P2
- Confidence: measured source and vendor contract / runtime latency not measured
- Can this happen today: yes. Every iPhone/iPad build uses `Cadence/Info.plist`, which contains no
  `UIBackgroundModes`; a test explicitly requires that key to stay absent. The app has the APS and
  CloudKit entitlements, so foreground/periodic synchronization can still make this look intermittent
  rather than completely broken.

Risk:

- Changes made on another device may not import while Cadence is backgrounded on iOS, leaving
  widgets, reminders, and the first foreground screen stale until a later system sync opportunity.
- Settings can still show the account as available, so the missing delivery capability has no
  corresponding warning.

Exact spots:

- `Cadence/Info.plist:18-38` contains the iOS launch/orientation keys but no `UIBackgroundModes`.
- `CadenceTests/AppStoreReviewReadinessTests.swift:29-34` asserts `UIBackgroundModes == nil`, so the
  current test protects the omission.
- `Cadence/Cadence.entitlements:9-17` does include APS and CloudKit, proving this is the missing third
  capability rather than an app with no push/sync setup.
- `Cadence/Shared/CadenceSyncHealth.swift:157-191` labels an available-account/cloud-store state
  `Syncing`; it does not inspect background delivery configuration.

External contract:

- Apple, `Setting Up Core Data with CloudKit`, says Remote notifications Background Mode is required
  for CloudKit to silently notify the app when content is available:
  `https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit`
- Apple TN3163 names the same switch when a CloudKit notification is not forwarded to the app:
  `https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer`

30-second confirming command:

```sh
plutil -p Cadence/Info.plist; rg -n "UIBackgroundModes|remote-notification|aps-environment|icloud-services" Cadence CadenceTests Cadence.xcodeproj
```

Suggested fix:

- Add `UIBackgroundModes` with `remote-notification` to the app Info plist / target capability.
- Replace the `== nil` assertion with an exact containment assertion for `remote-notification`.
- Keep notification authorization prompts unchanged: silent CloudKit delivery does not require
  user-visible alert/sound/badge permission.
- Update release-readiness prose so it states the capability on iOS as well as macOS registration.

Acceptance checks:

- The built iOS app's resolved Info plist contains `UIBackgroundModes = [remote-notification]`.
- The macOS build remains warning-free and does not gain a user notification authorization prompt.
- On two devices, a saved marker on A produces a CloudKit import in B's logs while B is backgrounded;
  foregrounding B shows it without a second relaunch.

### CXT-017: A note or list delete can erase an image asset whose CloudKit reference has not arrived yet

- Severity: P1
- Confidence: measured source / inferred CloudKit arrival ordering
- Can this happen today: yes. CXT-001's current image path commits a `MarkdownImageAsset` before the
  editor inserts/saves the markdown reference, creating separate durable states. If another device
  imports the asset first, deleting any note, area, project, or context during that gap runs a global
  orphan sweep and propagates deletion of the asset back through CloudKit.

Risk:

- The later-arriving note/task markdown keeps `cadence-image://<id>`, but the asset row and its
  external bytes have already been deleted on another device.
- This is permanent user-data loss, not temporary stale UI; the delete is an ordinary synced write.

Exact spots:

- `Cadence/Shared/CadenceNoteActionSupport.swift:37-43` deletes one note, then invokes the global
  unreferenced-asset sweep.
- `Cadence/Services/CadenceListDeleteHelpers.swift:79`, `:113`, and `:136` invoke the same sweep from
  context/project/area deletion.
- `Cadence/Services/CadenceListDeleteHelpers.swift:230-247` fetches *every* asset and deletes every ID
  absent from the locally visible markdown inventory, including assets unrelated to the requested
  deletion.
- `CadenceTests/DataIntegrityRepairServiceTests.swift:257-271` already states the correct CloudKit
  premise: an unowned row is indistinguishable from one whose owner has not arrived.

Existing correct pattern:

- `CadenceNoteDeletionSummary.forNote` restricts its image count to assets the doomed note actually
  references. The mutation should use that same candidate-set shape rather than collecting unrelated
  pre-existing or not-yet-owned rows.

30-second confirming command:

```sh
rg -n "deleteUnreferencedMarkdownImageAssets|allAssets: assets|excludingNoteIDs|createAssets|try\? modelContext.save" Cadence/Shared/CadenceNoteActionSupport.swift Cadence/Services/CadenceListDeleteHelpers.swift Cadence/macOS/Editor/MarkdownEditorView.swift Cadence/iOS/iOSMarkdownEditingSurface.swift CadenceTests/DataIntegrityRepairServiceTests.swift
```

Suggested fix:

- Before deleting, collect image IDs referenced by the doomed notes/tasks/documents only.
- Fetch those candidate assets, subtract IDs referenced by surviving markdown, and delete only the
  remainder. Do not collect an asset the requested deletion did not make orphaned.
- Retire the global-GC behavior from user delete paths. A separate global collector must wait for a
  positive store-completeness signal; the repo currently has none, so leaking an uncertain orphan is
  the safe direction.

Acceptance checks:

- An unrelated `MarkdownImageAsset` with no locally visible reference survives every note/list
  deletion path.
- An asset referenced only by the record being deleted is still reclaimed.
- An asset referenced by doomed and surviving markdown stays.
- A partial-arrival fixture (asset present, owner absent) survives a different note/list deletion.

### CXT-018: Hard list deletion walks only the local replica and can strand descendants that arrive later

- Severity: P1
- Confidence: measured source / inferred CloudKit import ordering
- Can this happen today: yes, on a new/reinstalled/long-offline device. As soon as a context, area,
  or project appears it is deletable, but its relationship arrays may not yet contain every child
  record. The cascade deletes only the rows currently reachable from those arrays.

Risk:

- The parent deletion uploads before delayed tasks, notes, goals, habits, links, or projects arrive.
  Those rows can later import with nullified/missing ownership and survive outside the deletion the
  user confirmed.
- Some survivors become Inbox/Other rows; others are effectively orphaned or invisible. The
  confirmation counts also describe only the partial local graph.

Exact spots:

- `Cadence/Services/CadenceListDeleteHelpers.swift:39-74` materializes the context cascade entirely
  from `context.areas/projects/tasks/goals/habits` and their current inverse arrays.
- `Cadence/Services/CadenceListDeleteHelpers.swift:100-115` and `:120-138` do the same for project and
  area deletion.
- `Cadence/Models/Area.swift:47-53` and `Cadence/Models/Project.swift:32-38` use inverse relationships;
  no stable child-side raw owner ID or synced deletion intent remains after nullification.
- `CadenceTests/DataIntegrityRepairServiceTests.swift:264-271` explicitly says startup can race first
  sync and missing owners may simply not have arrived. The delete path has no equivalent guard.

Existing correct pattern:

- `DataIntegrityRepairService` refuses orphan collection under partial CloudKit state. The hard
  cascade needs the same epistemic rule; a complete local relationship array cannot be assumed.

30-second confirming command:

```sh
rg -n "func delete(Context|Area|Project)|Array\((context|area|project)\.|partial CloudKit|owner has not arrived|@Relationship" Cadence/Services/CadenceListDeleteHelpers.swift Cadence/Models CadenceTests/DataIntegrityRepairServiceTests.swift
```

Suggested fix:

- Short term: do not offer/execute hard list deletion while the device cannot establish that its
  initial CloudKit import is complete; fall back to archive, which is already represented on these
  models and is reversible.
- Durable design: make deletion a synced soft-delete/tombstone state first, hide matching records on
  every device, and purge only after each replica has had a chance to apply the intent. Preserve raw
  ancestor identity on children if a later purge must find records whose relationships nullified.
- Keep account-wide Data Safety reset separate; it has different semantics from deleting one list.

Acceptance checks:

- A fixture where the parent arrives before one child cannot hard-delete the parent and later expose
  the child as Inbox/Other.
- A deletion intent applied before and after child arrival converges to the same visible result.
- Confirmation copy/counts do not claim a complete cascade unless completeness is established.

### CXT-019: Two devices can complete one recurring task and permanently fork its successor chain

- Severity: P2
- Confidence: measured source / inferred concurrent-device merge
- Can this happen today: yes. Two offline devices can both see `recurrenceSpawnedTaskID == nil`, mark
  the same predecessor done, and create separate successor `AppTask` rows with fresh identities.
  The same-device duplicate-completion test cannot reach this because both calls share one object and
  the first call immediately fills the guard field.

Risk:

- Both successor rows survive because their object/UUID identities differ. The predecessor's scalar
  pointer can name only one, leaving the other as an unlinked member with the same series ID and
  occurrence index.
- Completing both successors can fork the series again, multiplying future work and notifications.

Exact spots:

- `Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift:127-137` guards only the local
  predecessor and constructs a fresh successor when its local pointer is nil.
- `Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift:251-276` gives both independently made
  successors the same conceptual `recurrenceSeriesID` / `recurrenceOccurrenceIndex`, but each starts
  as a fresh `AppTask`.
- `Cadence/Services/DataIntegrityRepairService.swift:300-340` repairs habit-completion duplicates but
  has no recurrence-occurrence collapse.
- `CadenceTests/TaskWorkflowRecurrenceTests.swift:229-265` covers rapid duplicate calls in one
  context, not two independently saved replicas.

Existing correct pattern:

- `CadenceHabitCompletionStore.collapseDuplicates` and the corresponding repair pass reconcile two
  independently minted rows that represent one conceptual habit/day. Recurring occurrences need the
  same create-on-many-devices posture.

30-second confirming command:

```sh
rg -n "recurrenceSpawnedTaskID == nil|let nextTask = AppTask|recurrenceSeriesIDRaw|recurrenceOccurrenceIndex|collapseDuplicates|duplicate.*recurr" Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift Cadence/Services/DataIntegrityRepairService.swift Cadence/Services/CadenceHabitCompletionStore.swift CadenceTests/TaskWorkflowRecurrenceTests.swift docs/TODO.md
```

Suggested fix:

- Define conceptual occurrence identity as normalized `(seriesID, occurrenceIndex)` (with a careful
  legacy fallback for rows missing series metadata).
- Add an idempotent reconciliation pass that chooses a deterministic survivor, merges user fields,
  repoints every predecessor pointer, and deletes duplicate occurrences.
- Run the reconciliation after remote imports/foreground refresh as well as startup; prevention at
  spawn time alone cannot solve two offline writers.

Acceptance checks:

- Merge two independently created index-1 successors for the same series and end with exactly one.
- The predecessor points to the survivor; tags/subtasks/container/date/status data are not silently
  discarded.
- Re-running reconciliation changes nothing, and distinct series or indices never merge.

### CXT-020: A device-local EventKit calendar identifier is stored in CloudKit and can ping-pong between devices

- Severity: P2
- Confidence: measured source and vendor contract / cross-device identifier mismatch inferred
- Can this happen today: conditionally. Apple defines `EKCalendar.calendarIdentifier` as a *local*
  identifier and warns that a full calendar sync can lose it. When Mac and iPhone resolve the same
  calendar under different local IDs, linking on either device writes its ID into the shared
  `Area`/`Project` record. Re-linking on the other device writes its own ID back and breaks the first.

Risk:

- Each device reports the other device's valid link as missing and asks the user to repair it.
- Repairing is itself a synced scalar write, so the last device to re-link wins and the devices can
  repeatedly invalidate one another.

Exact spots:

- `Cadence/Models/Area.swift:18-40` and `Cadence/Models/Project.swift:19-25` persist the raw EventKit
  identifier on CloudKit-synced models and describe it as opaque/permanent.
- `Cadence/Shared/CadenceCalendarLinkHealth.swift:25-40` treats absence from this device's local ID
  set as an exact broken-link verdict.
- `CadenceTests/CadenceEventKitPlatformParityTests.swift:340-364` pins the id-only synced model shape,
  but tests recreation on one store rather than two devices with different local IDs.

External contract:

- Apple documents `calendarIdentifier` as a local identifier and says a full calendar sync loses it:
  `https://developer.apple.com/documentation/eventkit/ekcalendar/calendaridentifier`

30-second confirming command:

```sh
rg -n "linkedCalendarID|calendarIdentifier|missingLinks|opaque, permanent|T-390" Cadence/Models/Area.swift Cadence/Models/Project.swift Cadence/Shared/CadenceCalendarLinkHealth.swift Cadence/iOS/iOSCalendarSettingsSection.swift Cadence/macOS/Views/SettingsListManagementSections.swift CadenceTests/CadenceEventKitPlatformParityTests.swift
```

Suggested fix:

- Store the resolved EventKit ID in a device-local `CadenceCalendarLinkPreferences` mapping keyed by
  `(list kind, list UUID)`, not on the synced model.
- For migration, adopt a legacy model ID only on a device where EventKit currently resolves it. Do
  not clear the synced legacy field from one device while another may still need to adopt it.
- If cross-device intent is desired, sync non-binding metadata separately and require explicit user
  confirmation before mapping it to a local calendar; never auto-bind by title alone.

Acceptance checks:

- The same list can map to `mac-calendar-id` and `phone-calendar-id` simultaneously without either
  write changing the other device's mapping.
- A full EventKit sync invalidates only the current device's mapping and shows one local repair.
- Existing legacy links that resolve locally migrate without silently rebinding by title/source.

### CXT-021: Focus minutes are read-modify-write counters, so concurrent devices lose sessions and can disagree on totals

- Severity: P2
- Confidence: measured source / inferred same-property CloudKit conflict
- Can this happen today: yes. Focus exists on macOS and iOS. If both devices start from 30 minutes
  and independently log 20 and 10 while offline, each writes an absolute scalar (50 or 40), not an
  additive event. One imported value must replace the other; 60 cannot be reconstructed.

Risk:

- A valid focus session disappears from `AppTask.actualMinutes` after sync.
- The same session also increments `Area.loggedMinutes` or `Project.loggedMinutes` as a separate
  record, so task and list totals can resolve from different winning writes and disagree.
- Hours-based goal progress reads these totals, turning a sync conflict into incorrect progress.

Exact spots:

- `Cadence/Shared/CadenceFocusPlanningSupport.swift:182-191` increments task and list scalars.
- `Cadence/macOS/Views/FocusSessionSupport.swift:32-47` repeats the same multi-record increments for
  manual log sessions.
- `Cadence/Shared/CadenceFocusBundleSupport.swift:235-257` distributes one session across several
  task/list scalar records.
- `Cadence/Models/AppTask.swift:226-230`, `Area.swift:40-41`, and `Project.swift:25-26` persist the
  denormalized totals; there is no immutable session model in `CadenceSchema`.

Existing correct pattern:

- Habit check-ins are separate `HabitCompletion` rows and their aggregate is derived/collapsed. A
  focus session is likewise an additive fact and should not be encoded only as a mutable total.

30-second confirming command:

```sh
rg -n "actualMinutes \+=|loggedMinutes \+=|var actualMinutes|var loggedMinutes|FocusSession.self" Cadence/Shared Cadence/macOS Cadence/iOS Cadence/Models Cadence/Services/CadenceSchema.swift docs/TODO.md
```

Suggested fix:

- Add an immutable `FocusSession` ledger row with ID, task/list identity, minutes, and timestamp;
  derive totals from sessions or maintain the scalar fields only as rebuildable caches.
- Give one user action one stable session ID so retries are idempotent, while different devices mint
  different rows whose minutes naturally add after CloudKit merge.
- Backfill one synthetic legacy session per existing task/list total or explicitly version the
  migration so old totals are not double-counted.

Acceptance checks:

- Two sessions created from independent contexts/devices both survive and aggregate to their sum.
- Replaying the same session ID does not double-count.
- Task, area/project, bundle, export, MCP, and hours-goal totals resolve from one ledger rule.

### CXT-022: T-358's “two-device” section merge works only after the remote edit is already local

- Severity: P2
- Confidence: measured source and test boundary / offline CloudKit outcome inferred
- Can this happen today: yes. The helper protects a stale editor when another edit has already
  arrived in the same model object before Save. If Mac and iPhone both save while offline, each
  writes a complete `sectionConfigsRaw` string without seeing the other; the helper is never called
  when CloudKit later chooses/imports the scalar value.
- Classification: the helper is correct for its actual input contract, but the test/comment claim is
  broader than the behavior pinned. This is not a request to delete the helper.

Risk:

- Different-column or different-field edits can still clobber after true concurrent/offline sync,
  despite the code and test saying the two-device case is fixed.
- Reviewers may reject the needed data-model work because the current test appears to prove it
  already exists.

Exact spots:

- `Cadence/Models/Area.swift:44-45` and `Project.swift:29-30` persist the entire column collection as
  one JSON string, which is one CloudKit field.
- `Cadence/Shared/CadenceSectionConfigMerge.swift:13-20` defines `current` as what the model has at
  local save time; it has no remote/base value at later import time.
- `CadenceTests/SectionConfigRoundTripTests.swift:144-193` performs both “device” edits sequentially
  against one `Area` instance. It proves stale-editor merging, not isolated replica convergence.
- `docs/TODO_DONE.md:183` records T-358 as “two devices editing different sections clobber each
  other” and closed.

Existing correct pattern:

- The helper's field-level `base`/`edited`/`current` merge is the right pattern for an editor whose
  remote change has landed. Preserve it for that case and narrow its claim unless the storage shape
  changes.

30-second confirming command:

```sh
rg -n "Two devices, one blob|twoStaleEdits|sectionConfigsRaw|applySectionConfigEdits|base:|edited:|current:" Cadence/Models Cadence/Shared/CadenceSectionConfigMerge.swift CadenceTests/SectionConfigRoundTripTests.swift docs/TODO_DONE.md
```

Suggested fix:

- Best fix: normalize columns into their own synced model rows with stable identity and scalar fields;
  keep order as an explicitly last-writer-wins concern or model it separately.
- Alternative: persist a local edit journal/base revision and run an explicit three-way reconciliation
  when a remote version arrives. This needs a real import signal and conflict UI for same-field edits.
- Until either exists, rename the test/docs to “stale editor after imported change” and document true
  offline writes as last-writer-wins. Do not leave a stronger closed claim than the implementation.

Acceptance checks:

- A test uses two isolated replicas/snapshots that save without seeing each other, then applies the
  reconciliation/import path and preserves different-field edits.
- Same-field conflicts have one stated deterministic/UI policy.
- The existing stale-editor tests stay green; narrowing the claim alone must not remove their guard.

## Checked But Not Filed

- `TagSupport.resolveTags(named:in:)` inserts, but it takes `ModelContext` as a parameter. The caller
  owns the unit of work, and `CadenceSaveCommitDisciplineTests` documents that exemption.
- `CadenceListNoteFiling.createNote` is already guarded with `commitInsert`.
- Known save-rule exemptions in `CadenceSaveCommitDisciplineTests` were not re-filed here.
- `Cadence/macOS/Views/KanbanCardMetaSupportViews.swift` `select` and
  `Cadence/iOS/iOSMarkdownReferenceSupport.swift` `body` are already named by T-497/T-566 and were
  not duplicated here.
- macOS/iOS context reorder disagreement is already open as T-614, so it was not duplicated here.
- iOS calendar board's bundle drag save swallow was used as a counterexample, not filed: the source
  documents that it reports nothing and dismisses nothing after the save attempt.
- Broad `CadenceTaskMutationSupport` `try? save()` usage was not filed as one mega-ticket. The useful
  items are the surfaces that report, dismiss, animate, or trigger side effects around those writes.
- CalendarManager's global `lastWriteFailure` means CXT-012 is about discarded typed/local failure
  handling, not about every EventKit failure being completely invisible.
- The widget/App Intent publish path already saves through throwing helpers, emits the external-write
  marker, and is pinned by `CadenceExternalWriteReconcileTests`; no widget persistence finding was
  filed in this batch.
- Notification reconciliation has several closed tickets and is already part of CXT-006/CXT-008/
  CXT-010. No standalone notification finding was added without a new reachable path.
- `AppTask.calendarEventID` still has no non-empty writer, so the old linked-task EventKit cleanup
  residue remains existing-data-only and was not re-filed.
- T-497 already owns the two flush-then-dismiss editors; they were not duplicated as new findings.

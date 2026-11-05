# Save-site census for T-11581, 2026-11-05 (tree `1fff0a49`)

Agent `savecensus0638`. **Question:** which `ModelContext.save()` calls outside
`CadencePendingChangePersistence` can `CADENCE_UI_TEST_REFUSE_COMMITS` (T-11512) refuse? The switch
refuses only commits that reach the spine's private `perform`. Line numbers are at `1fff0a49`,
before this ticket's edits.

**Method, measured.** I ran `rg -n --type swift '\.save\(\)' Cadence/` and dropped `//` comment
lines. That gives 184 lines, 7 of them inside the spine, so **177 lines outside it, in 84 files.** A
second pass, `rg '(^|[^.\w])save\(\)'`, found 3 more bare `try? save()` calls inside `extension
ModelContext`. That makes **180 sites**. For every `commit: … = { try $0.save() }` default, I read
the function body with a brace-matching script and looked for one of three things: a call into
`CadencePendingChangePersistence.`, a direct `try commit(x)`, or a forward of `commit: commit`. I
then checked each forwarding target the same way, one hop at a time, down to the spine. I did not
hand-read every one of the 60 forwarders. I verified their target families instead:
`CadenceTaskFieldEditCommit.commit`, `CadenceOrderCommit.commit`, `commitSettle`,
`distributeMinutes`, `toggleSubtask`, `addSectionConfig`, `resolveTagsCommittingInsertions`,
`moveToContainer`, `deleteTasks`, `setTags`, `createTask` and `CadenceInPlaceEditFlush.flush`.

The ticket guessed "about 60 lines across ~100 files". The 60 is right for **direct** calls. The
file count is not: those 60 sit in **28 files**, and all 180 sites sit in 84.

## Totals

| Group | Sites | Could not be refused before T-11581 | After |
|---|---:|---:|---:|
| `{ try $0.save() }` commit-closure defaults and arguments | 117 | 12 | 0 |
| Direct `.save()` calls | 60 | 60 | 59 |
| Bare `save()` in `extension ModelContext` | 3 | 3 | 3 |

The 12 closure sites:

- **3 called `commit:` themselves:** `CadenceAINoteSummary.append`,
  `CadenceFocusSupport.logSession` (bank-only branch) and `CadenceInPlaceEditFlush.flush`.
- **9 forwarded onto those:**
  - `CadenceTaskMutationSupport` `setScheduledDate` / `setScheduledTime` / `clearScheduledDate` /
    `clearScheduledTime`, which call `flush`
  - the four `CadenceTaskDateEditing` wrappers over them
  - `macOS/Views/FocusSessionSupport.swift:34`, which forwards to `logSession`

The two non-default flush callers, the iOS note editor and the Kanban column rename, are refusable
now too.

Classes over the **63 sites that are not a closure**. Every closure default is a parameter, and
only its consumer can commit:

- **(a) a real user commit with a refusal notice: 7.** 1 routed by this ticket, 6 filed.
- **(a-silent) a real user commit with no notice (`try?`, the rule's allowed swallow): 35.** No
  notice means nothing to sight. Filed as one group.
- **(b) seed, migration, recovery, repair or test support: must never refuse: 18.**
- **(c) other: 3.**

## Commit-closure defaults (117)

- **49 call the spine directly** (`commitInsert`, `commitEdit`, `commitDelete`, `commitCascade`,
  `commitTypedContent`). They were already refusable.
- **60 forward `commit:`** to a helper that reaches the spine, except the 9 listed under Totals.
  Those 9 reach a direct caller instead.
- **3 called their `commit:` directly. Routed by T-11581:**
  - `Services/AI/AINoteActionSupport.swift:88`, `CadenceAINoteSummary.append`: now `commitEdit` with
    the same two-field undo.
  - `Shared/CadenceFocusPlanningSupport.swift:545`, `CadenceFocusSupport.logSession`, bank-only
    branch: now `commitEdit` with the `BankedMinutes` restore.
  - `Shared/CadenceInPlaceEditFlush.swift:42`, `flush`: now `commitEdit` with an undo that does
    nothing, so the edit still stays pending. Every flush-based surface is now refusable.
- **3 store the closure** and run it later:
  - `Services/MCPReadOnly/CadenceWriteService.swift:689` and `:708` are **(c)**. This is the MCP
    server process. Its commits go through `commitInsert(…commit: commit)`. It never carries
    `CADENCE_UI_TEST_MODE`.
  - `macOS/Views/TaskNotesEmbedHandlers.swift:116` forwards to spine helpers.
- **2 pass `{ try $0.save() }` as an argument**, both into spine helpers:
  `macOS/Views/SchedulePanelComponents.swift:37` (`TaskInspectorScheduleCommit.setTags`) and
  `macOS/Views/TaskInspectorContentSupportViews.swift:774` (`CadenceTaskEditDraftCommit.save`).
- `Shared/TaskCompletionAnimationManager.swift:325` runs `try commit(context)` on closures that are
  always `TaskWorkflowService.commitMark*`, so it reaches `commitSettle`.

## Direct calls (60) and bare `save()` (3)

### (a) Real user commit with a refusal notice: 7

| Site | What | Disposition |
|---|---|---|
| `Shared/CadenceTaskMutationSupport.swift:1172` `insertScheduledTask` | iOS timeline draft create, `TaskCreationService.saveFailureNotice` | **Routed:** `commitInsert` |
| `Services/AI/AIActionService.swift:167` `applyTaskDrafts` | AI task drafts, the review sheets show `AIErrorPresenter` | **T-11611:** a refused save also leaves every inserted draft pending |
| `Services/CadenceArchiveImportService.swift:175` `apply` | user archive import, rolls back and throws | **T-11612:** route through the spine, or exempt it as a recovery path |
| `macOS/Views/NotesView.swift:684`, `macOS/Views/ListNotesView.swift:472`, `macOS/Views/EventNoteSupportViews.swift:308`, `iOS/iOSEventNoteEditorSheet.swift:258` | `save: { try modelContext.save() }` into `CadenceEventNoteSupport.commitNote`, `.notSaved` notice | **T-11613** |

### (a-silent) Real user commit, `try?`, no notice: 35

- `Shared/CadenceTaskMutationSupport.swift`: 12 sites, the quiet field setters.
  - `:225` `normalizeCompletionState`
  - `:230` `setPriority`
  - `:235`, `:241`, `:247` `schedule{Today,Tomorrow,NextWeek}`
  - `:349` `setDueDate`
  - `:354`, `:360`, `:366` `due{Today,Tomorrow,NextWeek}`
  - `:371` `clearDueDate`
  - `:376` `moveToSection`
  - `:1205` `removeTaskFromBundle`
- Archive, restore and reopen: 14 sites.
  - `iOS/iOSSettingsTagsSection.swift:251,257`
  - `macOS/Views/SettingsTagsSection.swift:200,206`
  - `iOS/iOSSettingsView.swift:543,557,562,567`
  - `macOS/Views/SettingsView.swift:409,424,429,434`
  - `iOS/iOSListViews.swift:450,455`
- Image resize: `macOS/Editor/MarkdownEditorView.swift:236` and
  `iOS/iOSMarkdownEditingSurface.swift:702`.
- `Shared/CadenceNotePlanningSupport.swift:261` `update`.
- `iOS/iOSTaskDetailComponents.swift:639` `save`.
- Card bindings: `macOS/Views/KanbanCardView.swift:393` (duration) and
  `macOS/Views/KanbanCardMetaSupportViews.swift:86` (tags).
- `extension ModelContext` wind-downs: `iOS/iOSListWindDownSupport.swift:207` and
  `iOS/iOSColumnWindDownSupport.swift:127,142`.

**T-11614** holds this group. Routing these through the switch would show a UI test a silent
revert, not a notice, so the question is per site: should it have a notice at all.

### (b) Must never refuse: 18

- Startup maintenance: `Services/PersistenceController.swift:617` (`performStartupMaintenance`).
- UI-test seeds:
  - `Services/CadenceUITestScenarioSeed.swift:312,370,444,480,520,580`
  - `Services/CadenceUITestSupport.swift:72` (`seedDataIfNeeded`)
- Tag seed, dedupe and launch markdown-tag sync: `Services/TagSupport.swift:159,185,345`.
- Repair: `Services/DataIntegrityRepairService.swift:370`.
- Migration: `Services/NoteMigrationService.swift:347`.
- iOS sample data:
  - `iOS/iOSSampleDataSupport.swift:301`
  - `Shared/CadenceTaskMutationSupport.swift:1144` (`insertTask`). Its only caller is the sample
    seed, which is why it was **left on its inline save** when `insertScheduledTask` was routed.
- Metadata backfills: `macOS/Views/NotesView.swift:673` and `macOS/Views/ListNotesView.swift:488`.
- Stale event-link repair: `macOS/Views/CalendarLinkedTaskSupport.swift:74`
  (`clearMissingEventLinks`).

### (c) Other: 3

- `Shared/CadenceModelContextRefresh.swift:18`: flushes pending work before it replaces a context.
  It is not a commit of its own.
- `Services/CadenceWidgetIntents.swift:108,183`: widget and App Intent writes. They run in the
  intent's process, which never carries the UI-test environment. The error goes to the intent
  system, not to an in-app notice.

## Not verified

- **Nothing was sighted on screen** under the switch.
- The 60 forwarders were checked by target family, not opened one by one.
- `save()` spelled through any other receiver name (for example a stored `context` property used
  without `.save()` on the same line) would escape both greps.

## Mutation plan, not yet run

`scripts/mutate.sh` refused its baseline with exit 13 (AUTOMATION-PROMPT-OUTSTANDING, T-2070).
An unanswered "Enable UI Automation" prompt is standing on this Mac, and while it stands no macOS
test run can work. The plan below has passed `--check`. Run it on a scratch tree that carries
this commit, for example:

```
./scripts/mutate.sh <id> <this-plan-saved-to-a-file>
```

Each mutation must come back KILLED.

```
# T-11581 (agent savecensus0638): four commits outside the spine now reach its refusing seam.

mutation: M1
file: Cadence/Shared/CadenceInPlaceEditFlush.swift
suite: CadenceUITestCommitRefusalTests
tests: anArmedInPlaceFlushAnswersFalseWithoutCommittingAndLeavesTheEditPending
expect: killed
note: the flush calls its commit itself again, so the switch cannot refuse it
--- old
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, refusing: refusing, undo: {})
--- new
            try commit(modelContext)
--- end

mutation: M2
file: Cadence/Services/AI/AINoteActionSupport.swift
suite: CadenceUITestCommitRefusalTests
tests: anArmedAISummaryAppendRefusesBeforeCommittingAndPutsTheNoteBack
expect: killed
note: the AI summary append ignores the refusal switch
--- old
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, refusing: refusing) {
--- new
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, refusing: false) {
--- end

mutation: M3
file: Cadence/Shared/CadenceFocusPlanningSupport.swift
suite: CadenceUITestCommitRefusalTests
tests: anArmedBankOnlyFocusLogRefusesBeforeCommittingAndUnbanksTheMinutes
expect: killed
note: the bank-only focus log ignores the refusal switch
--- old
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, refusing: refusingBank) {
--- new
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, refusing: false) {
--- end

mutation: M4
file: Cadence/Shared/CadenceTaskMutationSupport.swift
suite: CadenceUITestCommitRefusalTests
tests: anArmedScheduledInsertRefusesAndTakesTheTaskBackOut
expect: killed
note: the scheduled insert saves directly again, bypassing the spine
--- old
        try CadencePendingChangePersistence.commitInsert(of: task, in: modelContext, refusing: refusing)
--- new
        try modelContext.save()
--- end
```

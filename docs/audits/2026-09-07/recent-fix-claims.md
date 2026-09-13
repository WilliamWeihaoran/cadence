# Recent Fix Claim Audit

```text
Tree read: 4ad2178
Dirty files at initial capture: 22; excluded via clean git archive
Commits examined: a7184f2 and 7ae1c61
Mode: source/diff inspection only; no builds, tests, app, or simulator
```

## Result

**REASONED:** the main folder-move and tag-selection fixes are present. No evidence in these inspected paths of a comment-only fix or reverted mutation being landed. This is a narrow two-commit review, not certification of all recent commits or their reported test counts.

| Claim | Source Checked | Result |
| --- | --- | --- |
| Folder moves commit and restore raw previous path | CadenceNoteFolderSupport.swift:259-268 | Present; throws through commitEdit and restores the snapshot |
| Both note columns show the move refusal | ListNotesView.swift:388; iOSListNotesView.swift:340 | Present; shared mutation, catch, column notice |
| Importer uses non-committing folder operation | CadenceArchiveImportService.swift:591 | Present; no per-note commit introduced |
| Import holds exactly one commit for the whole document | CadenceNoteFolderMoveCommitTests.swift:249 versus NoteMigrationService.swift:260 | Too broad: its source test cannot see the later migration save; see ROI-01 |
| Tag selection/removal answers failure and restores selection | iOSTaskDetailComponents.swift:400,421,435,591 | Present |
| New notepad note is un-inserted on refused save | NoteMigrationService.swift:505-513 | Present; no blanket ModelContext rollback |

## ROI-05: A New Tag Can Persist Behind a "Nothing Was Changed" Notice

**P3 / error-message accuracy / REASONED; iOS-only implementation.** Extends T-1070's newly fixed `addTag` selection path, not a re-report of its swallowed Boolean. Per the release packet, iOS is not currently distributed; **not reachable through the released macOS tag UI on this evidence**.

**Can it happen in today's iOS code?** Yes, if creating a previously nonexistent tag succeeds and attaching it to the task then fails. No failure was induced here. This is a specific two-commit sequence, not a claim that toggling an existing tag has the same defect.

1. [iOSTaskDetailComponents.swift:614](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSTaskDetailComponents.swift:614) calls `TagSupport.committedTag`. [CadenceInlineTagCreation.swift:71](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceInlineTagCreation.swift:71) uses the existing committing insertion path, so a newly minted catalogue tag is already durable.
2. [iOSTaskDetailComponents.swift:622](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSTaskDetailComponents.swift:622) then calls `onCommit(previous)` to persist selection.
3. On refusal, `commitTags` restores only `task.tags`; it does not remove the previously committed tag. The catalogue change survives.
4. [CadencePendingChangePersistence.swift:70](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadencePendingChangePersistence.swift:70) supplies `Couldn't save these changes. Nothing was changed.` to this branch. The selection is restored, but "nothing" is too broad for the entire add-tag action.

**Not data loss:** the new tag survives and can be selected on retry. The typed name also remains. Do not undo a successful catalogue creation by globally rolling back the shared context or deleting a possibly existing tag.

```sh
git show 4ad2178:Cadence/iOS/iOSTaskDetailComponents.swift | sed -n '435,445p;610,630p'
git show 4ad2178:Cadence/Shared/CadenceInlineTagCreation.swift | sed -n '25,51p;71,82p'
git show 4ad2178:Cadence/Shared/CadencePendingChangePersistence.swift | sed -n '67,72p'
```

**Suggested fix:** keep the two-step behavior and use attachment-scoped wording, e.g. "Couldn't add this tag to the task. The task's tags were not changed." Do not claim a tag was newly created unless the helper returns that provenance; it can return an existing tag. Alternatively make mint-plus-attachment atomic as a deliberate larger change using the existing resolution snapshot pattern, but a new transaction abstraction is not necessary to correct the sentence.

**Test gap:** [CadenceInlineTagCommitSurfaceTests.swift:335](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceInlineTagCommitSurfaceTests.swift:335) checks the toggle's refusal wiring, and the sibling test covers removal. Neither proves an all-or-nothing create-plus-select action. Add a two-stage check: mint succeeds, attachment commit refuses, second context sees the tag but not the task relationship, and the message describes that result. Retain separate existing-tag, mint-refused, and success cases. Tests were inspected, not run.

## Looks Solid

**REASONED:** existing-tag toggles and chip removal restore the previous selection; folder moves restore only their own field; notepad creation deletes only its newly inserted note on refusal. Preserve these scoped undo patterns. The residual issues concern composite operations and the scope of their promises, not a reason to undo the recent fixes.

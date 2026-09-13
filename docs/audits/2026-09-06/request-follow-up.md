# Request Queue Follow-up

```text
Tree read: 5aac94d
Dirty files at initial capture: 8
Source examined: clean git archive at /private/tmp/cadence-requests-5aac94d
All workspace edits excluded from source conclusions; the live request queue is preserved.
Mode: source/history inspection and independent counting/arithmetic only.
No app launches, builds, Swift tests, simulator runs, or production edits.
MEASURED = command/count/arithmetic executed here.
REASONED = source-derived behavior, not a runtime reproduction.
```

## Findings First

1. **R33 / P2 / MEASURED: T-1043 has actually been allocated to unrelated work.** This is not merely a missing ledger entry. One entry closes the editor image-overlap fix; another opens a calendar-link evidence test gap. They also occur in different commit messages. Fix this bookkeeping before another agent closes the wrong request.
2. **R32 / P2 / REASONED: the App Store description overpromises settings sync.** The data models use private CloudKit; ordinary settings use device-local defaults. Remove the blanket settings promise, not the data-sync claim.
3. **R32 / test-only gap / MEASURED source mismatch:** the empty-store test's replay omits focus-ledger reconciliation even though its claimed production sequence includes it. This does not disprove the zero-workspace result, but it disproves exact replay equivalence.
4. **R38 / P3 / REASONED design candidate:** Create Goal places successive labels and controls as siblings in one 20pt stack. Interior labels are as close to the preceding control as to their own control. The same sheet already uses 6pt label/control groups for dates.

No production fix or TODO allocation was made. Existing tickets and previous reports remain authoritative for their already-filed scopes.

## R31: What Has Gone Stale

**REASONED source delta:** the retired Bundle UI population and four singular/plural sites are fixed, not open work. T-843 centralizes Block wording in TaskBundle; T-844 routes the four cited strings through `CadencePluralization.phrase`. Examples: `FocusLogSessionPopovers.swift:166`, `FocusSidebarSupportViews.swift:156`, `CadenceNotesListSupport.swift:692`, `iOSFeatureViews.swift:189`. Model/type names containing Bundle are not user-facing regressions.

**MEASURED arithmetic:** current dim is `#878791`, not the old `#71717a`. Against bg / recessed / surface / hover / elevated / highlight, respectively, its contrast ratios are **5.59 / 5.46 / 5.21 / 5.03 / 4.88 / 4.62**. All clear 4.5. Source: [Theme.swift:288](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Theme.swift:288). This retires the old T-847 population; it is not a new contrast finding.

**MEASURED arithmetic; REASONED interpretation:** the old accent numbers were for white text on an accent fill, not accents drawn on the dark page. Hue order below is blue, red, green, amber, purple, teal; palette definitions are `Theme.swift:58`, `:76`, `:93`.

| Palette | White on accent fill | Accent on bg |
| --- | --- | --- |
| Cadence | 2.75, 2.78, 2.08, 1.90, 2.72, 1.98 | 7.22, 7.17, 9.57, 10.45, 7.31, 10.04 |
| Ember | 3.23, 3.05, 2.11, 2.38, 2.64, 2.44 | 6.16, 6.52, 9.42, 8.37, 7.53, 8.16 |
| Glacier | 2.21, 2.50, 2.00, 1.54, 2.73, 1.75 | 9.02, 7.96, 9.97, 12.93, 7.28, 11.39 |

All 18 white/fill pairs fail 4.5, but **not** all fail 3.0. Do not reopen the entire accent palette: T-853 corrected the diagnosis, and T-855 carries the white-on-fill work. Foreground/background role and actual text size still determine individual call-site urgency.

**MEASURED arithmetic:** marker text `#fff4c2` on marker accent `#f6c343` at 0.38 over bg `#09090b` yields approximately `#635020` and **7.03**, not 1.48. **REASONED:** the current Theme supplies the composited fill to the layout manager; do not apply the alpha twice. See `Theme.swift:335-360` and `CadenceTests/CadenceContrastFloorTests.swift:169,215` (tests read, not run).

**REASONED:** Milestone Momentum now forwards to `CadenceWidgetReloadPolicy.recommendedReloadDate` at [CadenceMilestoneWidgetSupport.swift:122](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceMilestoneWidgetSupport.swift:122), including the empty-pool midnight clamp. T-851 is fixed. No widget timeline was run here.

Other recorded closures remain source-consistent: T-845 shared sentence-case formatter, T-846 distinct not-determined Reminders offer, T-852 separate MCP CI lane. A CI lane is not evidence of a successful build in this audit.

Confirm at the audited tree:

```sh
git show 5aac94d:Cadence/Shared/Theme.swift | sed -n '259,360p'
git show 5aac94d:Cadence/Services/CadenceMilestoneWidgetSupport.swift | sed -n '116,135p'
git show 5aac94d:CadenceTests/CadenceContrastFloorTests.swift | sed -n '257,290p'
```

## R32: Third Reading of the Four Claims

### Manifest

**MEASURED:** 253 entries, 253 distinct entries, and zero entries whose bare function name is absent from test sources. The request's 240 was an older snapshot. Relative to `7761d2b`, 14 names were added and one removed. A bare-name check does **not** establish suite-qualified ownership or execute the classifier.

**REASONED:** [CadenceRealTreeSweepScan.swift:25](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceRealTreeSweepScan.swift:25) still requires all three markers: a code-level walk, a product-root literal, and Swift-source evidence. The union through referenced declarations is lexical, not a compiler-resolved call graph. Markers are defined at 83 and the full-set condition is at 333. Fixed-file checks, test-tree-only walks, and documentation-only walks are intentionally excluded. Existing hygiene tests at `CadenceTestTargetHygieneTests.swift:877,910,945` check existence, classifier correspondence, and boundary controls. They were not run; **253 is a measured inventory, not a certified coverage total**.

```sh
git show 5aac94d:CadenceTests/CadenceRealTreeSweepManifest.txt | awk 'NF && $0 !~ /^#/ {n++} END {print n}'
git show 5aac94d:CadenceTests/CadenceRealTreeSweepScan.swift | sed -n '25,47p'
```

### Recovery and Empty Startup

**REASONED:** retain the earlier recovery correction: export constructs its own ModelContext after opening a read-only container. It does not require the failed ambient context. Literal "no model context on any path" is false; independence from the broken application's context is true. See the existing recovery report, including its export/fallback limitations.

**REASONED:** normal startup still seeds no Context, Area, or Project. This does not mean the app can never create an empty daily note while rendering Today. A workspace fixture and a useful automatically opened note are different populations.

**MEASURED source mismatch, not a failing test run:** [CadenceFirstLaunchEmptyStoreTests.swift:612](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift:612) replays migrations, tag sync, integrity repair, and save, but omits `CadenceFocusLedger.reconcile`. The sequence assertion at 58 expects it in production. That assertion checks production, not that this replay calls every expected operation. This is **correct-looking startup code with an incomplete test replay**, not evidence that startup creates phantom workspaces.

Suggested fix: add the existing reconciliation call to the replay, or expose one shared startup operation list/helper without broadening runtime behavior. Pin replay/production correspondence, not just the production string sequence. Validate both an empty store and an existing focus-log store. No matching replay-omission ticket was found in TODO/TODO_DONE.

```sh
git show 5aac94d:CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift | sed -n '43,60p;610,621p'
```

### Description Claims

**REASONED: p2's universal claim is false.** [app-store-submission-packet.md:60](/Users/williamwei/Desktop/Projects/Cadence/docs/app-store-submission-packet.md:60) includes settings in its sync promise. [CadenceDefaults.swift:58](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceDefaults.swift:58) resolves ordinary launches to `UserDefaults.standard`; [SettingsView.swift:12](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsView.swift:12) stores notification enablement, default list page, sidebar choices, and note-template overrides in AppStorage. A source search found no `NSUbiquitousKeyValueStore` bridge. In contrast, `PersistenceController.swift:179` explicitly configures the model store's private CloudKit database.

**Can this happen today?** Yes: the submitted description can promise a second Mac will inherit sidebar/template preferences which these writers keep local. This is a copy/contract defect, not proof that model sync is broken.

Suggested replacement: **"Your tasks, notes, habits, and goals sync through your own private iCloud account across your Macs."** Do not silently implement a new preference-sync subsystem to rescue one word of marketing copy. No matching settings-sync-copy ticket was found in the ledgers.

The other description paragraphs were traced to these existing implementations. This table is **REASONED implementation correspondence**, not network, privacy, release, or end-to-end certification:

| Packet lines | Implementation and important boundary |
| --- | --- |
| 42-45: native Mac planning/tasks | macOSRootView/RootDetailContent; CreateTaskSheet; AppTask; TasksPanel. Existing list membership is optional. |
| 48: Apple Calendar | CalendarManager.swift:62 permission entry; :260/:287 updates; :345 deletion; calendar timeline alongside Cadence tasks. TCC responses were not exercised. |
| 51: Reminders | CadenceRemindersManager.swift:130 separate access; :191 incomplete predicate; :222 completion action; :238-241 completion-only write. The prose's "never edits" must be read with its explicit completion exception. |
| 54: notes/Markdown | NotesView.swift:90/:185/:289 daily/weekly/notepad pages; MarkdownStylist and editor reference rendering. Feature existence does not establish flawless layout; R39 already found that distinction. |
| 57: habits/goals | HabitsFormSheets.swift:48 and CreateGoalSheet.swift:88; Habit/Goal models and check-in/link helpers. No starter workspace is required to save a title. |
| 60: private data sync | PersistenceController.swift:179 supports private CloudKit for models. **Settings clause contradicted above.** No static code read can prove an operational "never sees data" guarantee about every external system. |
| 63: widgets | Existing task/calendar/habit/milestone widget support and extension implementations. Reload behavior is separate from feature existence. |
| 66: optional AI | AIActionService.swift:82-90 builds context from the chosen note's whole content, title, and container name. Say "a note you choose" if the existing wording could imply only highlighted text is sent. Provider use requires explicit user actions/key configuration; no provider call was made. |
| 69: privacy/account/reset | Settings account/data-safety paths exist. The earlier batch-02 privacy-reset report documents failure handling gaps; existence of a reset button is not proof of deletion succeeding under every failure. Absence-of-tracking/server claims remain source-bounded, not externally measured. |

```sh
git show 5aac94d:docs/app-store-submission-packet.md | sed -n '57,66p'
git show 5aac94d:Cadence/Shared/CadenceDefaults.swift | sed -n '58,74p'
git show 5aac94d:Cadence/macOS/Views/SettingsView.swift | sed -n '12,17p'
```

## R33: Commit Messages and Ledger IDs

**MEASURED correction to the previous report's instrument:** `String#strip` removed trailing NUL separators before parsing an empty commit body. The previous script silently dropped such commits. Changed it to remove leading whitespace only. On this tree, old script: **909** commits; corrected script: **983**. Distinct ticket-ID counts are unchanged in this comparison; the omitted records introduce no new IDs. Earlier headline commit counts should not be reused.

**MEASURED, corrected HEAD history:** 983 ancestor commits; **736** exact-spelled IDs; **344** IDs lack a TODO entry; **168** lack both TODO and TODO_DONE; **22** TODO IDs have no commit-message mention. Full sets and individual recent messages are in [request-ledger-inventory.json](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-06/request-ledger-inventory.json).

**MEASURED all-ref extension:** `git rev-list --all` contained **986** commits: the 983 ancestors plus `b6fee90`, `86b666e`, `922a8f0`. The first two add no ticket IDs; the recovered-work branch adds only IDs already in the 736. Therefore the three requested ID-difference sets are the same across all current refs. Unreachable/pruned objects are not recoverable history and are not included.

Recent missing-both IDs: **T-734, T-768, T-849, T-879, T-880, T-1039, T-1064**. T-752 has gained an entry since the earlier report. The original five examples have entries. A missing ID in a body can be a cross-reference, not a completed task: do not mass-create fictional closure records.

TODO IDs without a commit mention: T-16, T-476, T-481, T-491, T-492, T-494, T-498, T-499, T-522, T-523, T-525, T-526, T-527, T-537, T-542, T-553, T-554, T-998, T-999, T-1053, T-1054, T-1055. These are bookkeeping observations, not evidence that the work was never done.

### A Real Unrelated-Work Collision

**MEASURED artifacts; REASONED semantic classification:** T-1043 has two incompatible meanings:

- `dcb0a15`: "a note's image reserved its height at one width and was drawn at another"; TODO entry at [line 145](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:145), closed.
- `1513495`: explicitly files T-1043 as the writer-side sibling of T-899, a calendar-link evidence test; TODO entry at [line 2327](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:2327), open.

These cannot be one implementation with a follow-up. Repeated T-610 sub-batches, T-761's a/b/c fixes, and T-624's investigation/follow-ups are not equivalent collisions. T-974 and T-781 also each have duplicate TODO declarations; those duplicates describe their existing work, not a confirmed unrelated allocation. The repeated-ID review found **one confirmed semantic collision**, not proof that no others exist in every historical prose reference.

```sh
ruby docs/audits/2026-09-05/ledger-inventory.rb 5aac94d
git rev-list 5aac94d --count
git log --all --not 5aac94d --format='%h %s'
git log 5aac94d --format='%h%n%B' --grep='T-1043'
git show 5aac94d:docs/TODO.md | rg -n '^\s*- \[T-1043\]'
```

**Suggested fix/order:** assign the calendar evidence request a genuinely unused ID, then update its exact references without changing the editor ticket. Choose the ID from the current allocation process, not a guessed next number in this report. Correct same-work duplicate declarations separately. A new-allocation guard is now justified: reject newly introduced duplicate declarations and refuse allocation of an ID already used in history unless deliberately restoring its existing ledger identity. Grandfather the T-462 historical deficit; do not block every unrelated commit on 168 old gaps. A warning for unmatched message mentions is safer than pretending every cross-reference is a new task. Semantic uniqueness still needs review; regex cannot decide it.

## R34: Empty First Run and Reachable Content

**MEASURED history; REASONED behavior:** all three revisions of `CadenceUITestSupport.swift` (`2d3a82f`, `0dc7d3a`, `5c5b124`) retain `CADENCE_UI_TEST_MODE` and the `guard isEnabled` gate. The app root calls the helper outside a test target, but that normal call does not seed without the flag. A developer manually supplying the flag can seed, so "only tests can ever reach it" would also be too strong.

History searches in app entry/startup/root code found default-tag seeding (`89db417`, later changes), removed by `c118582`, but no removed production starter-workspace call. That is evidence about the searched history, **not proof of a designer's unwritten intent**. The iOS sample-data helper creates sample containers, but its Today offer is DEBUG-gated at `iOSTodayTaskSections.swift:195`; it is not a released macOS onboarding path. Current startup maintenance creates no starter workspace.

**REASONED control-activation paths:** fresh released Mac configuration, starting on Today, successful writes, no restored navigation, typing/focusing text excluded. These are short concrete paths, not measured literal mouse-click minima across keyboard shortcuts, system dialogs, or all window states. Naming them simply "minimum clicks" would overstate this read-only audit.

| Main surface | Control activations to useful content | Path / dependency |
| --- | --- | --- |
| Today task list | 2 | Add task, Create; title entry excluded. |
| Today notes | 0 extra navigation controls | Core notes load on appearance; typing makes content. Load refusal is separate recovery behavior. |
| All Tasks list | 3 | Tasks destination, Add task, Create. No containers needed. |
| All Tasks Kanban | 4 | Tasks, Kanban mode, Add task, Create. Inbox column requires no setup. |
| Inbox | 3 | Inbox destination, Add task, Create; no list assignment required. |
| First named Area OR Project | 6 to create, 7 to open | Settings, Contexts, New Context, Create, resulting section's add-list button, Create List, select list. This is the previously traced FR-1 detour at this committed snapshot. |
| Named-list tasks / board | 9 / 10 | Open the new list as above, Add task, Create; board adds its mode control. Creating an Area AND Project is not required. |
| Goals | 3 | Goals, New Goal, Create. A title is sufficient; no initial list or parent goal required. |
| Habits | 3 for a habit; 4 including first check-in | Habits, New Habit, Create, optional check-in. A title is sufficient. |
| Daily notes page | 1 | Notes destination auto-opens today's note; typing excluded. |
| Weekly / Notepad page | 2 | Notes destination, corresponding tab; current/core note loads automatically. |
| Calendar | 1 to a useful dated grid; external-content count not fixed | Calendar destination. Visible Apple events require authorization and actual external events. A fresh Cadence store says nothing about the user's EventKit store. Do not invent a guaranteed event-population click count. |
| Focus | 3 via Today task | Create a task (2), use its focus/play action (1). A timer is meaningful without a project; elapsed time is not a click. |
| Settings | 1 | Settings destination is already usable, even with no user models. |
| Search / event notes / Reminders | Conditional, not a fixed fresh-store number | Search requires a query and indexed content; event notes require a real event; Reminders require separate permission and reminders already present externally. These are not missing-workspace blockers. |

Source anchors: previous [first-run report](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/first-run-creation.md) for list/task entrances; `CreateGoalSheet.swift:88`, `HabitsFormSheets.swift:48`, `NotesView.swift:161,255,349`, `NotePanel.swift:106`, `FocusManager.swift:43`. The first-list path is especially snapshot-sensitive: three sidebar source files became dirty during this audit and are deliberately excluded.

The historical gate is answered; **literal shortest full-screen click paths remain unmeasured**. Finish that portion with one claimed, isolated full-screen app and a fresh store, not another source-derived number labeled as a runtime observation.

## R35: All Twelve Correctness Tickets

Every row below is **REASONED from the archived implementation plus current ticket history**. None is a reproduced refused save or two-device CloudKit run. "Fixed" refers to the original ticket's mechanism, not every bug in that feature.

| Ticket | Can the original wrong state still be written? | Can released macOS show its original consequence? | Current evidence / action |
| --- | --- | --- | --- |
| T-760 | Original swallowed bundle insert is fixed. | No via the repaired path; Mac already had a wrapper. | CadenceTaskMutationSupport.swift:1070/:1094 commits the inserted bundle and restores membership on refusal; iOS callers now catch. No new fix. |
| T-761 | Original time/estimate/repeat paths are fixed. | The Mac estimate instances were included, not just iOS. | CadenceTaskDateEditing.swift:108 forwards commit; TasksPanelComponents.swift:550 and TaskEmbedFieldEditorPopover.swift:182 use the committing estimate picker; iOSTaskViews.swift:149 attaches the recurrence failure alert. Closures 4d1bf57a/4eb22949/70de2f3d. No platform-wide immunity claim. |
| T-614 | Settings context reorder no longer leaves a refused order looking committed. | Original Mac display consequence fixed. | SettingsView.swift:292-315 captures order, commitEdit restores on refusal, and reports the failure. Other reorder tickets are separate. |
| T-623 | **Conditional orphan creation remains:** a parent delete can enumerate only locally available children. | Potentially: ownerless tasks can enter Inbox; surviving lists can appear in Other; several ownerless record types remain inert. | CadenceListDeleteHelpers.swift:108/:133 uses local to-many arrays. This supports a race risk, **not a reproduced lost-content/corruption claim**. Keep the park; do not add an import-complete gate or destructive orphan collector. |
| T-624 | A calendar identifier is still written into synced linkedCalendarID. | Old false "missing" diagnosis is guarded for identifiers not observed on this device; underlying cross-device resolution remains conditional. | CadenceCalendarLinkRowState.swift:forLink and CadenceCalendarLinkObservations distinguish unverified from missing. Actual identifier behavior across the user's Macs is unmeasured. Preserve evidence gate; portable schema decision remains open. |
| T-654 | Original bank-then-reset-over-refusal defect is fixed. | No through repaired Mac timer commit path. | CadenceFocusBundleSupport.swift:285 commitEdit and reverse snapshot restoration; FocusManager.swift:99/:132 commit before ending session. Separate batch-02 focus continuity finding is not this ticket. |
| T-762 | Tag inserts now commit before note tag/frontmatter assignment. | Direct picker names failure; ambient autosave may remain quiet by policy without leaving the original uncommitted mint. | NoteEditorPane.swift:82/:325/:423 uses committing insertion helpers. No caret rollback redesign needed. |
| T-661 | Portable export still contains raw calendar IDs by deliberate contract. | There is no portable-JSON restore path making this a live foreign-device overwrite. | Existing export decision in TODO.md:2997; future importer must not blindly adopt these IDs. Native backup restore is a different path. |
| T-743 | Dedup merge no longer drops focus-ledger ownership. | Original counter consequence fixed. | DataIntegrityRepairService.swift:279 fetches logs; :644 and :725 repoint them before deleting duplicate Area/Project. |
| T-744 | Subject-less focus logs can still exist after deletion or partial relationship arrival. | Reconciliation ignores rows with no resolved subject; this is not a live visible counter corruption claim. | AppTask.swift:767 onward reconciles only resolved owners. Closed by decision against collecting, not by removing orphan population. |
| T-745 | The isolated defaults suite can diverge from direct standard-default readers in instrumented launches. | Not in an ordinary released Mac launch: both resolve to standard without the suite argument. | CadenceDefaults.swift:66. Test-isolation limitation, not a user preference-loss bug. |
| T-737 | Column typing is now draft-only; archive/completion no longer renames through that draft. | Original stale-name consequence is dissolved by the separate editing flow. | KanbanSectionColumnView.swift:37/:426 and KanbanColumnSupportViews.swift:494 bind editorName, not the live section name. |

**T-623 framing matters:** the proved code fact is local enumeration. The hypothesized bad outcome is children surviving a parent deletion under delayed/concurrent sync, not this code deleting unseen children. An import-complete bit cannot prevent another device creating a child after that bit is checked. Ownerless rows can also be a transient sync state, so collecting all of them can create the very data loss the proposal was meant to prevent. Preserve the existing nil-owner containment patterns; multi-device measurement and any persistent parent-deletion/tombstone design need explicit schema/product review.

**Patch order:** no re-fixing the seven repaired mechanisms. Keep T-661/T-744's explicit decisions, treat T-745 as instrumentation work, and take T-623/T-624 forward only with the evidence/design their parks require. The T-1043 allocation collision should be resolved before picking the calendar writer-side guard.

```sh
git show 5aac94d:Cadence/Services/CadenceListDeleteHelpers.swift | sed -n '108,160p'
git show 5aac94d:Cadence/Services/DataIntegrityRepairService.swift | sed -n '640,650p;722,732p'
git show 5aac94d:Cadence/macOS/Views/NoteEditorPane.swift | rg -n 'CommittingInsertions'
git show 5aac94d:Cadence/Shared/CadenceDefaults.swift | sed -n '58,74p'
```

## R37: Current AppKit Census Delta

**REASONED:** keep the existing seven-subclass/seven-representable inventory and its distinction between deliberate settings and inheritance. The divider's inherited focusRingType is still not evidence that AppKit drew the observed band.

Current [macOSRootShellViews.swift:207](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/macOSRootShellViews.swift:207) gates the app's own `.focused` accent on Full Keyboard Access; `canBecomeKeyView` at 256 uses the same system setting while `acceptsFirstResponder` remains true. At rest the appearance resolves to zero accent. This supersedes the earlier snapshot's pending divider change. A new default property setting is not needed to fix an unproven focus-ring theory. Existing right-click hit-test findings remain inferred until exercised at neighboring coordinates; no fresh window was launched.

## R38: Expanded Source Scan, Not a Completed Pixel Census

**MEASURED:** the full Cadence Swift tree contains **269 literal top/bottom-padding matches**, including **2 comment hits**. [grouping-candidates.json](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-06/grouping-candidates.json) records all locations, text, and comment flags. These are candidates, **not 267 semantic grouping pairs**. Nested stack spacing, platform defaults, page-edge padding, conditional rows, and text metrics prevent that equivalence.

**REASONED new candidate:** [CreateGoalSheet.swift:104](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Sheets/CreateGoalSheet.swift:104) puts `Definition of Done`, `Context`, `Parent Goal`, `Kind`, and the branch's `Status`/`Initial Linked List` label directly between controls in a VStack(spacing: 20). For each interior label, the layout-boundary pair is **20 away / 20 toward its own control**, before control-specific intrinsic text metrics. The initial Title label has no previous field, so it is not a failed grouping pair.

**Existing correct pattern, in the same sheet:** date label/control groups at 194-204 have **6pt inside** an outer **20pt section** spacing. Group each earlier label with its control using that pattern (or CadenceFieldSection), preserve outer section separation, then inspect long labels/full-screen Mac. This is a P3 visual-review candidate, not proof users misread the form. No exact matching ticket was found in the ledgers.

The previous eight-family report remains useful, but its old sidebar arithmetic must not be applied to a dirty sibling's layout rewrite. The board column header's top 2 / bottom 8 is **not automatically a reversed grouping**: it starts a column rather than sitting between peer groups. Do not apply the heuristic without a preceding group.

**Still open:** classifying every candidate and every stack-only grouping, then measuring actual ink gaps across responsive/conditional states. Neither a regex list nor the earlier eight examples fulfills the literal "every spacing pair" request. This answer adds a reproducible population and one sharper same-file candidate without falsely closing that census.

## What Looks Solid

**REASONED:** the workspace fixture gate is present in every historical revision; first-run tasks and global Kanban do not depend on a container hierarchy; the bundle and tag changes use existing transactional helpers; merge repair explicitly reparents focus logs; calendar-link display withholds destructive conclusions when local evidence is absent; marker contrast now uses composited colors. These are the patterns to preserve, not invitations to rewrite their surrounding features.

## Remaining Verification

No unanswered R31-R35 section is left without a researched response. Standing R31 remains a recurring snapshot request. R32's classifier execution, R33's exhaustive semantic-negative claim, R34's literal click minima, and R38's complete composed/visual census are **not certified by this source-only pass**. Their limits are stated above so the next agent does not confuse an answer with completed runtime measurement.

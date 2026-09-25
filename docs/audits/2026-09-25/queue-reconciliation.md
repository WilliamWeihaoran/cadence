# R32-R38: Current Reconciliation

```text
Tree read: c8735e4
Dirty files: 23 at capture
Source: clean committed snapshot; all working edits excluded
Mode: source/history inspection and Ruby inventory; no builds, tests, or app launches
MEASURED = source/count directly inspected, not a reproduced UI or sync failure
REASONED = consequence or recommendation inferred from that evidence
```

This updates, rather than repeats, [the September 6 report](../2026-09-06/request-follow-up.md).
The original requests predate substantial fixes. Do not turn their old findings into new tickets.

## R32: Four Claims

- **MEASURED:** the manifest now has **291 entries, 291 distinct names, zero missing bare function
  declarations**, not 240. `CadenceTests/CadenceRealTreeSweepScan.swift:26` defines the three
  conditions: a transitive product-tree walk, product-root literal, and Swift-source evidence.
  `:86` combines all three markers. A name census does not execute that classifier, establish
  suite-qualified ownership, or prove its full call-graph approximation correct.
- **MEASURED:** the recovery UI does not require the failed ambient context. Its export action is
  `Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:207`; the export pipeline can open
  another readable store and construct its own `ModelContext`
  (`Cadence/Services/PersistenceController.swift:430`). Thus "no context on any path" is
  false; "does not depend on the broken UI context" is the useful contract. The previous recovery
  report remains the detailed path map, not a promise that every damaged store is exportable.
- **MEASURED:** the description's former blanket settings-sync promise is gone:
  `docs/app-store-submission-packet.md:60` names content types. T-1098 owns that repair. Some look
  preferences subsequently gained sync, so "all settings are local" is now also wrong. R64's
  [field-by-field report](../2026-09-22/sync-rollback/coverage.md) is the current boundary. The
  packet's AI disclosure at `:86` names full note text, title and list name; do not repeat the old
  "selected text only" claim. This is a source correspondence review, not App Review certification.
- **MEASURED:** startup calls the production maintenance pipeline; it deliberately does not seed
  workspace entities or default tags (`Cadence/Services/PersistenceController.swift:197`).
  `CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift:675` now invokes that actual pipeline.
  The old omitted-focus-reconciliation replay gap is fixed by T-1108. **REASONED:** a genuinely
  empty store remains without contexts/areas/projects; the test was not executed in this pass.

Confirm counts with the inventory command below. For classifier equivalence, the existing
manifest generator/hygiene suite is the authority; do not add a second approximate classifier.

## R33: Ledger Correspondence

**Premise disproved: this is guarded now.** `scripts/agent-commit.sh:1859` refuses unfiled message
IDs and `:2008` refuses newly duplicated entries. CI invokes `ledger-lag-check.sh` in
`.github/workflows/ci.yml:138` and `docs.yml:139`. A new parallel guard would duplicate existing work.

**MEASURED, every ancestor of c8735e4, including merge history:** 1,191 commits, 930 distinct
literal `T-n` IDs in subjects/bodies, 600 TODO entry-shaped lines / 597 distinct IDs, and 188 DONE
entry-shaped lines. **350 commit IDs have no TODO entry; 163 have neither TODO nor DONE entry.**
Those are lexical differences, not 163 new allocation bugs. Full sets and repeated-ID commit
subjects are in [queue-inventory.json](queue-inventory.json), under `ledger` and
`repeated_id_commit_subjects`. Unmerged refs and unreachable objects are outside this history scope.

The 17 TODO IDs with no commit mention are T-476, T-492, T-494, T-498, T-499, T-522, T-523, T-525,
T-526, T-527, T-537, T-542, T-553, T-554, T-1139, T-1140 and T-1221. A ticket can legitimately be
filed or fixed without its ID in a commit message; this is not proof that no implementation exists.

**MEASURED semantic checks:** T-1043 really was allocated to unrelated editor-image and calendar
work (`docs/TODO.md:2196`, `:5804`). Both now read closed; T-1303 made the ledger reader handle
the historical collision, not rename it away. T-974 and T-781 appear twice because T-965 preserves
verbatim declined text (`:7123`), not because this scan found new unrelated implementations.
The sole missing-from-both ID >=700 is T-1069: `0fb5504` mentions it while describing an older
missing link, not allocating new T-1069 work. Inspect with `git show -s --format=%B 0fb5504`.

**Disposition:** the original five were not the whole population, but historical deficits and the
known collision are already tracked. Preserve delta-based guards; no mass backfill or renumbering.
The machine candidate set is complete for the stated history scope; an exhaustive semantic verdict
on every repeated ID is **not** certified. Multiple mentions alone cannot establish unrelated work.

## R34: Empty First Run

**MEASURED:** `Cadence/Services/CadenceUITestSupport.swift:9` enables fixtures only through
`CADENCE_UI_TEST_MODE=1`; `:15` gates preparation and `:38` seeds the fixture. This is an explicit
environment opt-in, not a compile-time impossibility in Release. A specially launched non-test
binary could opt in; an ordinary launch does not. The prior history review found no normal starter
workspace call to restore. Default-tag launch seeding was deliberately removed, which is a
different decision from seeding contexts/areas/projects.

**Important change:** T-1113 removed the first-list Settings detour.
`Cadence/macOS/Views/SidebarView.swift:218` draws "Add first list" when there are no sections;
`SidebarViewSupport.swift:229` documents why a context is not required. Global Kanban can contain
Inbox tasks; a context -> area -> project -> column chain is not a prerequisite.

**REASONED source routes, not measured minimum click counts.** Counts exclude text entry, assume
the normal Today opening state, no permission prompt, successful save, and pointer activation:

| Surface/content | Short route | Control activations |
| --- | --- | --- |
| Today task | Add task, submit | 2 |
| All Tasks | Navigate to Tasks, add, submit | 3 |
| Global board | Tasks, board mode, add, submit | About 4; mode persistence can reduce it |
| First named list | Add first list, submit | 2 to create; selection/opening is a separate step if needed |
| Goal / habit | Navigate, add, submit | About 3 each; habit check-in needs another activation |
| Today daily note | Type in its existing note surface | 0 extra navigation activations |
| Weekly/permanent note | Navigate to Notes and choose/create the note | Depends on selected Notes mode |
| Calendar | Navigate to Calendar | 1 for the grid; content requires a scheduled task or permitted external event |
| Focus | Create a task, start its timer | At least the task-creation route plus start |
| Search | Invoke search and type | Results require matching existing content |
| Settings | Open Settings | 1; does not require workspace data |

The earlier [creation report](../2026-09-05/first-run-creation.md) has the original surface paths;
its first-list prerequisite is obsolete. Literal per-surface minima remain a runtime observation,
not a fact derivable from counting button declarations. No product change is recommended merely
to make an empty store look populated. A future full-screen clean-fixture walkthrough should record
start destination, existing selections, keyboard vs pointer, and permission state alongside counts.

## R35: Twelve Correctness Tickets

**REASONED current reachability**, with **MEASURED source/ledger evidence**. "Repaired" means the
original mechanism, not every possible failure in that feature. No refused-save or two-device run.

| Ticket | Wrong state can still be written? | Released Mac consequence / disposition |
| --- | --- | --- |
| T-760 | Original swallowed bundle insert repaired | `CadenceTaskMutationSupport.swift:1111` commits inserted bundle with refusal recovery; do not refile. |
| T-761 | Original picker commit/report mismatch repaired | Time helper forwards commit at `CadenceTaskMutationSupport.swift:255`; Mac estimate and iOS repeat closures recorded at `docs/TODO.md:3081`. |
| T-614 | Original reorder refusal repaired | `docs/TODO.md:7736`; visible reorder is part of the save-report discipline, not merely an in-place edit. |
| T-623 | Conditional local-child enumeration race remains | `docs/TODO.md:4379` is closed **as a decision to park**, not a repair. A late child may survive parent deletion. Not reproduced data loss. No import-complete flag or orphan collector. |
| T-624 | Synced local calendar identifier remains | Unobserved foreign identifiers are treated as unverified, not falsely missing. Closed decision at `:4527`; actual device identifier measurement belongs to T-1117. |
| T-654 | Original focus-bank refusal/reset repaired | `:4816`; commit must succeed before clock reset. Preserve the existing bundle undo snapshot. |
| T-762 | Original uncommitted tag mint repaired | `:4852`; insertion helpers own commit/refusal before applying note tags. |
| T-661 | Raw IDs still exported and now imported | **Old report's "no importer" is obsolete.** `CadenceArchiveImportService.swift:525,547` restores linkedCalendarID verbatim. The import preview counts/warns about those links (`:1244`, T-1084); provenance/evidence rules still matter. It is not guaranteed cross-device relinking. |
| T-743 | Original merge losing focus ownership repaired | `DataIntegrityRepairService.swift:279` fetches logs; closed implementation at `docs/TODO.md:7310`. |
| T-744 | Subject-less focus logs still possible | `AppTask.swift:792` reconciles resolved subjects. Closed decision against collection at `docs/TODO.md:7323`, not proof no orphan can exist. |
| T-745 | Original mixed defaults routing repaired | `docs/TODO.md:5278`: 27 sites across 12 files routed through CadenceDefaults.store. Normal release behavior remains standard defaults. Old test-isolation finding is no longer open. |
| T-737 | Original draft rename/lifecycle overlap repaired | `docs/TODO.md:6830`; draft editor name separated from lifecycle changes by T-736/T-738. |

Paths without prefixes in this table are under `Cadence/Shared/`, `Cadence/Services/`, or
`Cadence/Models/` as in the original report; confirming command resolves them without ambiguity:

```sh
git grep -n -E 'commitInsert\(of: bundle|static func setScheduledTime|model.linkedCalendarID = record|static func reconcile\(rows' c8735e4 -- Cadence
git show c8735e4:docs/TODO.md | rg -n '^\s*- \[T-(760|761|614|623|624|654|762|661|743|744|745|737)\]'
```

**Priority:** preserve T-623's park and T-624's device-evidence requirement. For T-661, preserve the
preview warning and do not promise a portable identifier mapping. No newly established loss bug in
this twelve-ticket rereading warrants undoing their deliberate closures.

## R37: AppKit Decisions

**MEASURED declaration inventory: six custom view classes and six NSViewRepresentable wrappers.**
The old seventh was the separate sidebar right-click implementation, now consolidated. The
divider's alleged inherited focus-ring cause was already disproved by T-1037; do not patch it again.

`I` means inherited/not explicitly overridden for this native view, **not false or harmless**.
`E` means explicitly configured. Native defaults were not queried at runtime.

| Native view | Focus ring | Cursor | Tracking | Layer | Opaque | First responder | First mouse | Vibrancy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CadenceTextView, `macOS/Editor/MarkdownEditorInteractionSupport.swift:6` | I | I | E | I | I | I | I | I |
| MarkdownEditorScrollView, `macOS/Editor/MarkdownEditorView.swift:660` | I | I | I | I | I | I | I | I |
| SidebarResizeHandleView, `macOS/Views/macOSRootShellViews.swift:220` | I | E resize | E | E true | I | E true | E true | I |
| RightClickActionView, `macOS/Views/RightClickActionTrigger.swift:43` | I | I | I | I | I | I | I | I |
| WindowTopDragRegionView, `macOS/Views/WindowDragRegionSupportViews.swift:18` | I | I | I | I | I | I | E true | I |
| TaskNotesHostingView, `macOS/Views/TaskInspectorContentSupportViews.swift:258` | I | I | I | I | I | I | I | I |

All paths above are under `Cadence/`. The editor's embedded text field sets a focus ring at
`MarkdownEditorInteractionSupport.swift:565`; that is not a setting on the outer text view.
The notes panel's `isOpaque` at `TaskInspectorContentSupportViews.swift:244` belongs to NSPanel.

Wrappers and their native objects:
- `Cadence/macOS/CadenceScrollElasticity.swift:12`: plain NSView bridge, configures enclosing scroll view.
- `Cadence/macOS/Editor/MarkdownEditorView.swift:495`: custom editor scroll/text pair.
- `Cadence/macOS/Views/macOSRootShellViews.swift:82`: custom resize handle.
- `Cadence/macOS/Views/RightClickActionTrigger.swift:28`: shared right-click view.
- `Cadence/macOS/Views/WindowDragRegionSupportViews.swift:5`: custom window-drag view.
- `Cadence/macOS/Views/TaskTitleEntryFieldSupportViews.swift:10`: plain bridge, adjusts native title selection.

**Looks solid:** `RightClickActionTrigger.swift:58` now respects `super.hitTest(point)` before the
event filter. The old spatial-acceptance finding is repaired. Editor tracking areas are replaced,
not accumulated. Keep intentional cursor/tracking choices; blanket setting inherited properties
would not establish correct behavior. The generated declarations list reproduces this census.

## R38: Grouping Relationships

**Two old candidates are repaired.** The sidebar now shares its composed arithmetic in
`Cadence/macOS/Views/SidebarViewSupport.swift:181`: above = 8 + 2 + 2 + 14 = **26pt**, below =
3 + 4 + 2 = **9pt** for a populated context. Empty context below = 3pt and has no first list row.
`Cadence/macOS/Sheets/CreateGoalSheet.swift:312` groups a label/control with
`CadenceSectionLabelMetrics.labelToNamedBlock`; the outer 20pt stack at `:149` is not a 20/20
label/control gap anymore. `CadenceTests/CadenceSectionLabelGroupingTests.swift` owns that family.

**MEASURED:** [the inventory](queue-inventory.json) contains **1,452 raw candidate lines**, including
comments, from every Swift file under Cadence: top/bottom/vertical padding, vertical-stack spacing,
named header/label/section spacing, and the shared label-to-block token. It supplies path, line and
nearby source. This is a reproducible syntactic census, **not every semantic spacing pair**.
It deliberately does not assign an invented label owner or computed gap to conditionally composed
views. Painted glyph distances also differ from layout-box spacing.

**No new reversed grouping relationship confirmed.** A complete visual census still needs a
bounded surface-by-state inventory and full-screen screenshots. Cheapest next work: inspect the
remaining candidate families once, map each to its owning stack, and test the composed inequality
only where grouping is intended. Equal toolbar spacing and decorative separators are not defects.
Use SidebarContextHeaderRhythm as the existing correct pattern, not a global padding rewrite.

## Reproduce and Order

```sh
# Use an agent-scratch snapshot of c8735e4 as SNAPSHOT_ROOT.
ruby docs/audits/2026-09-25/queue_inventory.rb SNAPSHOT_ROOT c8735e4
git show c8735e4:Cadence/macOS/Views/SidebarViewSupport.swift | sed -n '181,206p'
git show c8735e4:Cadence/macOS/Sheets/CreateGoalSheet.swift | sed -n '306,322p'
```

The inventory itself was run; Swift tests were not. First consume these premise corrections, then
take the new MCP/accessibility/widget/startup recommendations. Do not spend another batch recreating
the repaired findings. Remaining runtime/semantic-census portions are explicitly not certified.

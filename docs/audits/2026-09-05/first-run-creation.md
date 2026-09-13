# First-Run Creation Reachability

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## FR-1: First macOS named list requires an unnecessary context detour

**P3 / UX reachability gap / inferred behavior from current source. Extends T-559, not a regression in its optional-context sheet.**

**Can this happen today?** Yes, on a genuinely empty local store with no contexts or lists. The sidebar renders no list-section header, so none of its "+" list-creation buttons exist. Settings > Contexts > New Context can supply the missing header. Existing/synced context-less lists instead create an "Other" header, so this is narrower than "Mac cannot create context-less lists."

**Exact spots:**
- [SidebarView.swift:181](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarView.swift:181): sections derive from existing contexts and lists; keeping empty contexts helps only when a context exists.
- [SidebarView.swift:196](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarView.swift:196): list region contains only a ForEach of those sections.
- [SidebarView.swift:219](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarView.swift:219): the header callback is the list-sheet entry point.
- [CreateListSheet.swift:38](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Sheets/CreateListSheet.swift:38): context is already optional.
- [SettingsListManagementSections.swift:584](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsListManagementSections.swift:584): reachable New Context fallback.
- [TODO.md:4678](/Users/williamwei/Desktop/Projects/Cadence/docs/TODO.md:4678): T-559 shipped optional-context editing and the catch-all header's "+"; it did not make that header exist on a blank store.

**30-second confirmation, from repository root:**
```sh
git grep -n -E 'CreateListSheet\(|CreateContextSheet\(' 4799e3c -- Cadence/macOS
git show 4799e3c:Cadence/macOS/Views/SidebarView.swift | sed -n '181,232p'
```
Measured call-site inventory: macOS presents CreateListSheet from SidebarView and CreateContextSheet from SettingsView. The missing entry point is inferred from the empty section derivation; no clicks were executed.

**Suggested fix:** Add a first-list action when the sidebar's list sections are empty, presenting the existing `CreateListSheet(context: nil)`. Reuse its name validation, context picker, commit handling, and dismissal. Do not seed an arbitrary workspace just to create a button.

**Acceptance checks for the implementing agent:**
- Zero contexts/areas/projects: one visible action reaches the list sheet with No context selected.
- Saving an Area or Project without a context makes it visible in Other.
- Creation failure keeps the sheet open and shows the existing failure notice.
- Existing context headers and Other's "+" still work; no duplicate empty-state action.
- Verify the actual SwiftUI entry-point wiring, not just the section-building helper.

## Setup Burden: What Is Not Required

**Inferred current control-flow result:** a task can exist without any context, area, project, or custom column. The All Tasks board always adds Inbox before it adds list columns:
[KanbanBoardSupport.swift:131](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/KanbanBoardSupport.swift:131).
An area/project board has a default section configuration:
[KanbanListSectionSupportViews.swift:25](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/KanbanListSectionSupportViews.swift:25).

A list is an Area **or** a Project, not a mandatory Area-then-Project hierarchy. The list sheet requires a name; context and custom columns are not prerequisites. Therefore the proposed "context + area + project + column before any Kanban" sequence is not the current implementation.

The reliably identified first-list route on a blank Mac is Settings > Contexts > New Context > Create, followed by the new sidebar header's "+" > Create. That is **six control activations**, excluding typing, focus changes, scrolls, and opening Cadence. This is a derived path, not a measured global minimum across keyboard shortcuts or other platforms.

## Seeding Gate

[CadenceUITestSupport.swift:6](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceUITestSupport.swift:6) requires `CADENCE_UI_TEST_MODE=1`; `prepareAppState` guards before calling the fixture seeder. The root calls the helper, but normal launches do not pass its gate. "UI Test Workspace", "Alpha Area", and "Beta Project" are test fixtures, not a normal first-run workspace.

The fixture string first appears in reachable history at `2d3a82f`:
```sh
git log 4799e3c --oneline -S 'UI Test Workspace' -- Cadence/Services/CadenceUITestSupport.swift
git show 4799e3c:Cadence/Services/CadenceUITestSupport.swift | sed -n '1,47p'
```
This does not prove no older, differently named seeder ever existed. Historical product intent and every main surface's minimum click count remain outside this scoped pass.

## Looks Solid

- [PersistenceController.swift:106](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:106) explicitly avoids startup default-tag seeding because an empty CloudKit store can mean data has not arrived yet. Preserve that decision.
- The optional-context list sheet and inherited task-context correction from T-559 already exist; this needs an entry point, not another creation implementation.
- R25's endless NotePanel loading finding has since been addressed by T-849; do not refile it from the older report.

## Patch Order

Expose the empty-sidebar action, pin its presentation/save-failure wiring, then evaluate onboarding separately. No production edits or test execution in this audit.

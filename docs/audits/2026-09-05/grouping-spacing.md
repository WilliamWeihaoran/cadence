# Grouping Spacing Audit

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## Result

**No new confirmed rendering bug in this pass.** One equal-gap settings composition deserves design review (SP-1). The sidebar's full composed gap has already been documented in R36/T-1041; it is not a new ticket.

This is a targeted review of high-frequency task, sidebar, note, and settings groupings. It does not fulfill R38's requested census of every grouping in the repository. No screenshots or pixel distances were measured.

## SP-1: Contexts Settings Uses the Same Gap on Both Sides of a Section Label

**P3 / design candidate, not correctness defect / inferred visual effect.**

**Can this happen today?** Yes, when at least one context is archived, Settings > Contexts displays an active card followed by an Archived Contexts label and its card.

[SettingsListManagementSections.swift:554](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsListManagementSections.swift:554) places all four siblings in a single VStack(spacing: 16). The archived label at [line 603](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsListManagementSections.swift:603) therefore has **16pt from the preceding card boundary and 16pt to the following card boundary**. The label describes the following card.

This meets the requested equal-or-reversed-gap heuristic. It is not proof that users misgroup the content: card framing and typography also establish ownership, and glyph-to-row gaps include internal card padding.

**30-second confirmation:**
```sh
git show 4799e3c:Cadence/macOS/Views/SettingsListManagementSections.swift | sed -n '554,620p'
```

**Suggested fix, subject to visual approval:** Group each label with its own card using the existing shared `CadenceFieldSection`, or give the label/card pair a smaller internal spacing than the outer section spacing. Inspect wrappers first to avoid nesting a card inside another card. Do not blindly replace every 16 with 10.

**Existing correct pattern:** [CadenceFieldRows.swift:57](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceFieldRows.swift:57) keeps a titled section's own gap at 10; [SettingsTemplatesSection.swift:39](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsTemplatesSection.swift:39) places separate field sections in an outer stack with spacing 16.

**Acceptance checks:** Full-screen Mac with both active and archived contexts; long context names; archived-empty state. Compare actual label-to-card grouping, not just constants. Any guard should pin the composed relation or shared component wiring. Do not declare a hardcoded pair a user-visible defect based only on this audit.

**Dedup:** no specific archived-context equal-gap finding found; do not merge this into the already-closed sidebar correction.

## Composed Relationships Inspected

Numbers are source-derived **layout-boundary gaps**, not screenshot-measured ink distances. Arithmetic was checked; judgments about perceived grouping are inferred.

| Surface | Away from following content | Toward following content | Scope / result |
| --- | --- | --- | --- |
| Sidebar context heading after populated section | 8 + 2 + 2 + 14 = 26 | 3 | Includes previous bottom inset, both section wrappers, and next top inset. Existing R36 result, not new. |
| Settings rail group heading | 8 | 3 | Outer group spacing versus heading-to-row-stack spacing. Correct direction. |
| Today task section heading | 16 | 6 | Parent LazyVStack has zero spacing; explicit header paddings. Correct direction. |
| All Tasks section heading | 16, or 20 for list group | 8 | Zero-spacing parent/group stacks; local header separation. Correct direction. |
| All Tasks completed heading | 16 | 8 | Same composed stack convention. Correct direction. |
| Contexts settings archived label | 16 | 16 | Between card boundaries; SP-1 design candidate. |
| Templates field section grouping | 16 between sections | 10 from title to own card | Shared grouping pattern; card interiors are additional spacing, not equal to the boundary gap. |
| Notes month groups | Desktop 10 / touch 8 between group boxes | Desktop 3 / touch 2 between header and row boxes | Nested group/row spacing favors own rows. Header/row internal padding is not included in these boundary values. |

Source map:
- Sidebar: [SidebarView.swift:196](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarView.swift:196), [SidebarComponents.swift:126](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarComponents.swift:126), [SidebarViewSupport.swift:250](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarViewSupport.swift:250).
- Settings rail: [SettingsViewSupport.swift:136](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsViewSupport.swift:136) and [line 174](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsViewSupport.swift:174).
- Today: [TasksPanelSectionViews.swift:46](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksPanelSectionViews.swift:46), [TasksPanel.swift:181](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksPanel.swift:181).
- All Tasks: [TasksListView.swift:246](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksListView.swift:246), [line 501](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksListView.swift:501), [line 548](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksListView.swift:548).
- Notes: [CadenceNotesListSupport.swift:216](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceNotesListSupport.swift:216), [line 238](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceNotesListSupport.swift:238), [line 724](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceNotesListSupport.swift:724).

## Existing Test Gap, Not a New Production Defect

[CadenceSidebarLayoutTests.swift:333](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceSidebarLayoutTests.swift:333) computes section-bottom plus next-header-top, omitting the two 2pt wrapper insets. The asserted design relationship can still be true while the claimed composed number is incomplete. Already explained in R36: extend that existing work rather than filing it again. A useful test should obtain both wrapper and section contributions, not duplicate only a subset of constants.

## Looks Solid

Task headers deliberately use smaller gaps toward their rows; a pane's 6pt and a full page's 8pt are documented choices, not drift by themselves. Notes shares one group/row layout across desktop and touch. Settings rail shares the sidebar's relevant metrics without incorrectly inheriting its outer section wrappers.

## Patch Order

Keep the existing sidebar correction/test follow-up separate. Visually decide SP-1 next; only then adjust its local composition and pin the relationship. Leave the passing patterns unchanged.


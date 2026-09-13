# AppKit Behavior and Hit-Testing Audit

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## AK-1: Both Right-Click Overlays Discard the Spatial Hit Test

**P2 / framework-contract risk / inferred runtime impact. Source inventory measured; no wrong-row click reproduced.**

**Can this happen today?** These are live overlays on macOS task rows, timeline blocks, calendar month tasks, Kanban cards, and sidebar lists. Each override returns itself for a rightMouseDown without inspecting the point or consulting the superclass. Whether that steals a neighbor's event depends on the enclosing SwiftUI hosting/clipping hierarchy; that part must be tested before claiming a user-visible misroute.

**Exact spots:**
- [RightClickActionTrigger.swift:23](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/RightClickActionTrigger.swift:23)
- [SidebarSupportViews.swift:480](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarSupportViews.swift:480)

Both implement the same acceptance rule:
```swift
guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
return event.type == .rightMouseDown ? self : nil
```
The argument `point` is unused. No bounds, hidden-state, or superclass spatial acceptance participates.

Live placements: [TasksPanelComponents.swift:132](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TasksPanelComponents.swift:132), [TimelineTaskBlock.swift:102](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TimelineTaskBlock.swift:102), [CalendarPageMonthSupportViews.swift:494](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:494), [KanbanCardView.swift:92](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/KanbanCardView.swift:92), [SidebarSupportViews.swift:351](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SidebarSupportViews.swift:351).

**30-second source confirmation:**
```sh
git show 4799e3c:Cadence/macOS/Views/RightClickActionTrigger.swift | sed -n '20,34p'
git show 4799e3c:Cadence/macOS/Views/SidebarSupportViews.swift | sed -n '477,491p'
git grep -n -E 'RightClickActionTrigger|SidebarRightClickEditTrigger' 4799e3c -- Cadence/macOS
```

**Suggested fix:** Preserve the event-type filter and require a successful `super.hitTest(point)` before returning self. Share that small behavior between the two wrappers if doing so removes the duplicate without expanding scope. Do not use `bounds.contains(point)` unconverted: AppKit supplies a point in the **superview's** coordinate system. [Apple NSView hitTest documentation](https://developer.apple.com/documentation/AppKit/NSView/hitTest%28_%3A%29).

**Acceptance checks, not run:** inside/outside point, hidden view, zero-size view, nonzero origin, transformed/nested parent, right click versus primary click. Then exercise adjacent SwiftUI rows/cards to establish whether the current hierarchy exposes the defect. Existing center-of-row UI interaction does not establish rejection outside the row. No direct hit-test regression coverage was found in the searched test sources.

**Dedup:** no matching hit-test/spatial acceptance ticket found in TODO or TODO_DONE. This is not the sidebar divider's focus-ring/resize issue in T-1036/T-1037.

## Source Census

Measured declaration search found **7 custom view subclasses and 7 NSViewRepresentable wrappers**. MarkdownEditorCoordinator conforms to NSTextViewDelegate but is an NSObject, so it is excluded from the view count.

Legend: **I** = no explicit setting/override found in this class or its associated construction path for that property; framework behavior inherited. **E** = explicit local decision. I is not a claim that the runtime value is false, nor a defect.

| Custom view (source line) | Focus ring | Cursor rects | Tracking | wantsLayer | isOpaque | First responder | First mouse | Vibrancy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CadenceTextView, MarkdownEditorInteractionSupport.swift:6 | I | I | E, own hover area at 156 | I | I | I | I | I |
| MarkdownEditorScrollView, MarkdownEditorView.swift:653 | I | I | I | I | I | I | I | I |
| WindowTopDragRegionView, WindowDragRegionSupportViews.swift:18 | I | I | I | I | I | I | E, true | I |
| SidebarResizeHandleView, macOSRootShellViews.swift:166 | I | E, resizeLeftRight | E, active-app hover | E, true | I | E, true | E, true | I |
| RightClickActionView, RightClickActionTrigger.swift:20 | I | I | I | I | I | I | I | I |
| TaskNotesHostingView, TaskInspectorContentSupportViews.swift:258 | I | I | I | I | I | I | I | I |
| RightClickEditView, SidebarSupportViews.swift:477 | I | I | I | I | I | I | I | I |

Paths above are under `Cadence/macOS/Editor/` for the editor types and `Cadence/macOS/Views/` for the others.

Important distinctions:
- MarkdownEditorView.makeNSView at [line 522](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Editor/MarkdownEditorView.swift:522) explicitly sets editing, rich text, undo, substitutions, spelling, backgrounds, insets, fonts, scrollers, and borders. An I-filled table does not mean the editor is unconfigured.
- CadenceTextView's embedded NSTextField has `focusRingType = .none` at [line 553](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift:553). That is not a setting on the outer text view.
- TaskNotesPanel's `isOpaque = false` at [line 244](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/TaskInspectorContentSupportViews.swift:244) belongs to NSPanel, not TaskNotesHostingView.
- WindowTopDragRegion and TaskNotesHostingView deliberately permit background window dragging; the resize handle explicitly refuses it.
- An inherited focusRingType does **not** prove a focus ring is drawn. The previous R36 investigation superseded R37's premise about the divider. Do not reopen that disproved diagnosis or replace sibling in-flight fixes.

### Representable Map

| Wrapper | Native object / special behavior |
| --- | --- |
| MarkdownEditorView, Editor/MarkdownEditorView.swift:495 | Constructs the configured custom scroll/text view pair. |
| WindowTopDragRegion, Views/WindowDragRegionSupportViews.swift:5 | Custom window-drag NSView. |
| SidebarResizeHandle, Views/macOSRootShellViews.swift:82 | Custom resize NSView and coordinator. |
| RightClickActionTrigger, Views/RightClickActionTrigger.swift:5 | RightClickActionView; AK-1. |
| SidebarRightClickEditTrigger, Views/SidebarSupportViews.swift:462 | RightClickEditView; AK-1. |
| CadenceScrollElasticityConfigurator, CadenceScrollElasticity.swift:12 | Plain NSView bridge; configures enclosing scroll view asynchronously, wrapper disables hit testing. |
| TaskTitleInitialSelectionSuppressor, Views/TaskTitleEntryFieldSupportViews.swift:10 | Plain NSView bridge; adjusts matching first responder selection asynchronously. Does not own a custom drawing view. |

```sh
git grep -n -E 'class .*:.*NS(View|TextView|ScrollView|Control|Button|ClipView|HostingView)|struct .*:.*NSViewRepresentable' 4799e3c -- Cadence
```

## Looks Solid

CadenceTextView removes/replaces its tracking area and clears hovered-task state on exit. The resize handle declares its cursor and tracking behavior rather than relying on defaults. The elasticity bridge does not intercept clicks. Preserve those specific choices; blanket setting every inherited property would add noise without establishing correctness.

## Patch Order and Limits

Verify AK-1 at the native-view boundary, preserve spatial rejection in both copies, then verify real hosting placement. No build, tests, screenshots, or runtime framework-default inspection were performed. This completes the source-property inventory, not a visual certification of every inherited AppKit behavior.


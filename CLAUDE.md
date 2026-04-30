# Cadence — SwiftUI Productivity App

## What This App Is
Cadence is a personal productivity and life-management app for macOS (with iOS planned). It is a GTD-style system where users organize life into **Contexts** → **Areas/Projects**, set long-term **Goals**, track daily **Habits**, manage **Tasks** with scheduling, write daily **Notes**, and stay focused with a **Focus timer**. Tasks can be scheduled to a timeline and synced with Apple Calendar.

## User
The user does not write code. Claude handles all implementation. When something requires a one-time GUI action in Xcode, explain the minimal steps clearly.

## Tech Stack
- SwiftUI + SwiftData (no UIKit, no third-party dependencies)
- CloudKit sync via SwiftData (`cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")`)
- Targets: macOS (fully built), iOS/iPadOS (stub — "coming soon"), watchOS (not started)
- Apple Calendar integration via `CalendarManager.swift` (EventKit). Apple Reminders: not implemented.
- Bundle ID: `com.haoranwei.Cadence`
- Deployment: TestFlight for personal use

## Platform Strategy
- **macOS**: purpose-built sidebar + multi-column layout (`macOS/`). Fully featured.
- **iOS + iPadOS**: stub only (`iOS/iOSRootView.swift` shows "coming soon"). No views built yet.
- **watchOS**: not started
- Use `#if os(macOS)` / `#if os(iOS)` for platform-specific branches

## Project Structure
```
Cadence/
├── CadenceApp.swift               # App entry, ModelContainer + CloudKit setup + error recovery
├── Models/                        # 100% shared across all platforms
│   ├── ModelEnums.swift           # TaskPriority, TaskStatus, and other shared enums
│   ├── Context.swift              # Top-level domain (Work/Personal/School)
│   ├── Area.swift                 # Ongoing responsibility (no deadline)
│   ├── Project.swift              # Finite effort with a clear outcome
│   ├── Goal.swift                 # Long-term milestone with progress tracking
│   ├── AppTask.swift              # Concrete action item (schedulable, has subtasks)
│   ├── Subtask.swift              # Sub-item belonging to one AppTask
│   ├── Habit.swift                # Recurring behavior to reinforce
│   ├── HabitCompletion.swift      # Daily check-in record
│   ├── DailyNote.swift            # Date-keyed freeform markdown note
│   ├── WeeklyNote.swift           # Week-keyed note
│   ├── PermNote.swift             # Permanent/pinned note
│   ├── Document.swift             # Markdown doc attached to Area or Project
│   └── SavedLink.swift            # Bookmarked URL attached to Area or Project
├── Shared/                        # Shared across iOS + macOS
│   ├── Theme.swift                # Design tokens
│   ├── DateFormatters.swift       # Shared static DateFormatters + TimeFormatters
│   ├── CadenceHoverStyles.swift   # Shared hover highlight styles for clickable controls
│   └── Components/
│       ├── CadenceDatePicker.swift  # Month calendar date picker + MonthCalendarPanel
│       ├── CadenceScrollElasticity.swift # Shared NSScrollView elasticity tuning for page surfaces
│       ├── EstimatePickerControl.swift # Shared estimate picker control
│       ├── EmptyStateView.swift     # Reusable empty state (message, subtitle, icon)
│       ├── FilterPill.swift         # Tappable filter tag pill
│       └── StatCard.swift           # Tinted stat card (label, value, color, icon)
├── iOS/
│   └── iOSRootView.swift          # Stub — "coming soon" placeholder
└── macOS/
    ├── macOSRootView.swift        # Root shell/state; delegates command routing, overlays, lifecycle, and shell fragments to support files
    ├── CadenceCalendarPicker.swift  # macOS-specific calendar date picker variant
    ├── Views/
    │   ├── TodayView.swift        # 3-column layout: NotePanel | TasksPanel | SchedulePanel
    │   ├── TasksPanel.swift       # Today + All Tasks orchestration (grouping, sorting, rollover, scoped completed sections)
    │   ├── TasksPanelComponents.swift # Fragile row primitives: MacTaskRow, completion button, animated row background
    │   ├── TasksPanelSectionViews.swift # Reusable task-panel sections, grouped/flat/completed renderers
    │   ├── TasksPanelSupportViews.swift # Header, overdue cards, picker badges, support rows
    │   ├── TasksPanelSupport.swift # Shared task-panel helpers and support types
    │   ├── NotePanel.swift        # Today's daily note editor (inline in TodayView)
    │   ├── SchedulePanel.swift    # Today timeline shell/state; delegates viewport + popover support to companion files
    │   ├── SchedulePanelComponents.swift # TaskDetailPopover stateful logic
    │   ├── SchedulePanelSupportViews.swift # Quick-create popovers and timeline support views
    │   ├── SchedulePanelShellViews.swift # Shell composition shared by Today timeline surfaces
    │   ├── SchedulePanelPopoverSupportViews.swift # Task inspector header/metadata/subtask/action views
    │   ├── InboxView.swift        # Inbox: tasks with no area/project, capture bar, drag-to-reorder
    │   ├── CalendarPageView.swift # Calendar page shell/state: Week/2W/Month, infinite scroll, restore/jump logic
    │   ├── CalendarPageComponents.swift # Month/grid rendering layer
    │   ├── CalendarPageSupportViews.swift # Timeline viewport composition and shared calendar support views
    │   ├── TimelineDayCanvas.swift  # Main timeline canvas state/orchestration; drag-to-create + drop handling
    │   ├── TimelineMetrics.swift    # Pixel↔minute coordinate math, snapping, shared timeline sizing
    │   ├── TimelineTaskBlock.swift  # Draggable scheduled task block with tap/popover detail
    │   ├── TimelineEventBlock.swift # Calendar event block (read-only display)
    │   ├── GoalsView.swift        # Goal timeline (Gantt-style), multi-scale (2W to 5Y)
    │   ├── HabitsView.swift       # Habit list, detail view, heatmap, CreateHabitSheet
    │   ├── NotesView.swift        # Note list + editor (NoteListRow, NoteEditorPane)
    │   ├── FocusView.swift        # Focus timer UI, task picking, session logging, actual-minute propagation
    │   ├── SidebarView.swift      # Fully custom sidebar shell with static tabs + settings icon
    │   ├── SidebarComponents.swift # Context/list rows + drag/drop helpers; reorder uses SidebarDragContext.shared + DropDelegate
    │   ├── ListDetailView.swift   # Area/Project detail shell: Tasks, Kanban, Planning, Notes, Links, Completed
    │   ├── ListDetailComponents.swift # List task view, grouping modes, completed view
    │   ├── ListPlanningView.swift # Scheduling-focused list planning page: upcoming do/due dates plus unscheduled backlog
    │   ├── KanbanView.swift       # Section-based kanban orchestration for lists and All Tasks
    │   ├── KanbanCardView.swift   # Shared kanban task card; hover/edit/action state stays here
    │   ├── KanbanBoardSectionView.swift # Shared board wrapper used by kanban views
    │   ├── ListNotesView.swift    # Area/project notes list + shared note editor; H1 heading in content auto-syncs to note.title; each note gets its own NSTextView via .id(note.id) to isolate undo stacks
    │   ├── EventNoteSupportViews.swift # Linked note sheet/editor for calendar events
    │   ├── LinksView.swift        # Saved link list + add UI
    │   ├── GlobalSearchView.swift # Spotlight-style overlay; ranking/index/state split into support files
    │   └── SettingsView.swift     # Category-based settings shell, including archived/completed lists
    ├── Sheets/
    │   ├── CreateContextSheet.swift
    │   ├── CreateListSheet.swift  # Creates Area or Project
    │   ├── CreateGoalSheet.swift
    │   ├── CreateTaskSheet.swift  # Full task creator: title, notes, due date, do date, priority, container
    │   └── EditListSheet.swift
    ├── Editor/
    │   ├── MarkdownEditorView.swift  # SwiftUI wrapper/build-up for the shared AppKit markdown editor
    │   ├── MarkdownEditorSupport.swift # Styling/parser support, list rules, hidden markdown attributes
    │   └── MarkdownEditorInteractionSupport.swift # NSTextView subclass, coordinator, custom drawing/caret behavior
    └── Services/
        ├── CalendarManager.swift       # EventKit: create/update/delete/observe; updateEvent can change calendar; fetchAllDayEvents(for:), event(withIdentifier:), convertAllDayEventToTimed(_:startMin:dateKey:)
        ├── FocusManager.swift          # @Observable singleton for focus timer state
        ├── TaskCreationManager.swift   # CreateTaskSheet + success toast; presentSuccessToast() activates the main window before showing the in-app toast (works from quick capture panel)
        ├── GlobalHotKeyManager.swift   # Carbon API global hotkey to open quick task panel system-wide
        ├── QuickTaskPanelController.swift  # NSPanel for system-wide quick task creation
        ├── HoveredTaskManager.swift    # Hovered task + hoveredDateKind (.doDate / .dueDate) for shortcuts; delayed clear to reduce regroup thrash
        ├── HoveredEditableManager.swift  # Tracks hover state for edit/delete keyboard shortcuts
        ├── HoveredTaskDatePickerManager.swift # Shared overlay for hovered-task do/due date picking
        ├── HoveredKanbanColumnManager.swift # Tracks hovered kanban column for Cmd+N
        ├── HoveredSectionManager.swift # Tracks hovered kanban section for edit/complete shortcuts
        ├── TaskCompletionAnimationManager.swift # Delayed green-fill completion flow for tasks
        ├── SectionCompletionAnimationManager.swift # Delayed green-fill completion flow for sections
        ├── DeleteConfirmationManager.swift # Custom delete confirmation overlay
        ├── SchedulingService.swift     # SchedulingActions: createTask/dropTask helpers for timeline, including direct container/section creation and drag-create list/section targeting
        ├── TaskWorkflowService.swift   # Completion flow for recurring tasks
        ├── GlobalSearchManager.swift   # Presents the in-app command palette
        ├── ListNavigationManager.swift # Opens areas/projects/tasks from global search
        ├── CalendarNavigationManager.swift # Jumps calendar to searched events/days
        ├── TaskSubtaskEntryManager.swift # Opens hovered tasks directly into focused subtask-entry mode
        ├── TodayTimelineFocusManager.swift # Focus/highlight the built-in Today timeline from Cmd+\
        ├── AppFocus.swift              # clearAppEditingFocus() — resigns first responder app-wide
        └── PersistenceController.swift # (legacy/unused — SwiftData handles persistence)
```

Several large macOS surfaces are now intentionally split into companion support files rather than one oversized view file. Important examples:
- `TasksPanel*` — orchestration vs sections vs row/support views
- `SchedulePanel*` — shell/state vs quick-create/task inspector support
- `TimelineDayCanvas*` — canvas state vs overlays/shell/state helpers
- `MarkdownEditor*` — wrapper vs styling/parser support vs interaction/coordinator logic
- `TaskSurfaceFreeze*` — shared hover-freeze models/coordinator/helpers used by Today, Inbox, and list-detail task surfaces

## Data Models
All SwiftData `@Model` classes. **Critical CloudKit rule: all to-many relationships must be optional arrays (`[Type]?`).**

```
Context:   id, name, colorHex, icon, order
           → areas:[Area]?, projects:[Project]?, tasks:[AppTask]?, goals:[Goal]?, habits:[Habit]?

Area:      id, name, desc, status("active"|"done"|"archived"), colorHex, icon, order, linkedCalendarID, hideDueDateIfEmpty,
           hideSectionDueDateIfEmpty (hides Kanban column due date UI when the column has no due date)
           → context:Context?, tasks:[AppTask]?, projects:[Project]?, documents:[Document]?, links:[SavedLink]?
           computed: isDone, isArchived, isActive

Project:   id, name, desc, status("active"|"done"|"archived"|"paused"|"cancelled"), colorHex, icon,
           dueDate(yyyy-MM-dd), order, linkedCalendarID, hideDueDateIfEmpty, hideSectionDueDateIfEmpty
           → context:Context?, area:Area?, tasks:[AppTask]?, documents:[Document]?, links:[SavedLink]?
           computed: isDone, isArchived, isActive, completionRate

Goal:      id, title, desc, startDate(yyyy-MM-dd), endDate(yyyy-MM-dd),
           progressType("subtasks"|"hours"), targetHours, loggedHours,
           colorHex, status("active"|"done"|"paused"), order, createdAt
           → context:Context?, tasks:[AppTask]?
           computed: progress (0.0–1.0)

AppTask:   id, title, notes, priority("none"|"low"|"medium"|"high"),
           status("todo"|"inprogress"|"done"|"cancelled"),
           dueDate(yyyy-MM-dd), scheduledDate(yyyy-MM-dd), scheduledStartMin(-1=unscheduled),
           estimatedMinutes, actualMinutes, calendarEventID, order, createdAt, completedAt,
           sectionName
           → area:Area?, project:Project?, goal:Goal?, context:Context?, subtasks:[Subtask]?
           computed: isDone, isCancelled, scheduledEndMin, containerName, containerColor,
                     resolvedSectionName, shouldShowDueDateField, hidesEmptyDueDateInList

Subtask:   id, title, isDone, order, createdAt → parentTask:AppTask?

Habit:     id, title, icon, colorHex, frequencyType("daily"|"daysOfWeek"|"timesPerWeek"|"monthly"),
           frequencyDaysRaw(JSON [Int]), targetCount, order, createdAt
           → context:Context?, completions:[HabitCompletion]?
           computed: frequencyDays (JSON get/set), currentStreak

HabitCompletion: id, date(yyyy-MM-dd), count, createdAt → habit:Habit?

DailyNote:   id, date(yyyy-MM-dd), content, createdAt, updatedAt
WeeklyNote:  id, weekKey(yyyy-Www), content, createdAt, updatedAt
PermNote:    id, title, content, order, createdAt, updatedAt

Document:  id, title, content, order, createdAt, updatedAt → area:Area?, project:Project?
SavedLink: id, title, url, order, createdAt → area:Area?, project:Project?
EventNote: id, eventIdentifier, title, content, createdAt, updatedAt
```

When accessing optional relationship arrays, always use `?? []`:
```swift
area.tasks ?? []
project.tasks ?? []
context.areas ?? []
```
When appending to optional relationship arrays:
```swift
area.tasks = (area.tasks ?? []) + [newTask]
```

## Design System (Shared/Theme.swift)
```swift
Theme.bg              = #0f1117   // app background
Theme.surface         = #1a1d27   // cards/surfaces
Theme.surfaceElevated = #1f2235   // elevated surfaces (inputs, sheets)
Theme.borderSubtle    = #252a3d   // card borders, dividers
Theme.text            = #e2e8f0   // primary text
Theme.muted           = #c4d4e8   // secondary text
Theme.dim             = #6b7a99   // tertiary/disabled/labels
Theme.blue            = #4a9eff   // primary action
Theme.red             = #ff6b6b
Theme.green           = #4ecb71
Theme.amber           = #ffa94d
Theme.purple          = #a78bfa

Theme.priorityColor("none"|"low"|"medium"|"high") -> Color
Theme.statusColor("todo"|"inprogress"|"done"|"cancelled") -> Color
Color(hex: "#4a9eff")  // hex initializer available everywhere
```

## Shared Utilities (Shared/DateFormatters.swift)
```swift
// Static date formatters — never create DateFormatter() inline
DateFormatters.ymd           // "yyyy-MM-dd" (storage format)
DateFormatters.longDate      // "EEEE, MMMM d"
DateFormatters.monthYear     // "MMMM yyyy"
DateFormatters.shortDate     // "MMM d"
DateFormatters.fullShortDate // "MMM d, yyyy"
DateFormatters.dayOfWeek     // "EEE"
DateFormatters.dayNumber     // "d"
DateFormatters.monthAbbrev   // "MMM"

DateFormatters.todayKey()              // -> String "yyyy-MM-dd" for today
DateFormatters.dateKey(from: Date)     // -> String "yyyy-MM-dd"
DateFormatters.date(from: String)      // -> Date?
DateFormatters.shortDateString(from:)  // "yyyy-MM-dd" string -> "Jan 15"

// Time formatting for minute-based scheduling
TimeFormatters.timeString(from: Int)                   // 75 -> "1:15 AM"
TimeFormatters.timeRange(startMin: Int, endMin: Int)   // "1:15 AM – 2:15 AM"
TimeFormatters.durationLabel(actual: Int, estimated: Int)  // "45/60m"
```

## Key Patterns
- `.preferredColorScheme(.dark)` set at root — always dark
- Avoid `navigationBarLeading`/`navigationBarTrailing` — use `.automatic` or `.primaryAction`
- Avoid `.keyboardType()` — iOS only
- `@Bindable` for editing SwiftData model properties directly in views
- All dates stored as `"yyyy-MM-dd"` strings (no timezone issues)
- Minutes from midnight (`scheduledStartMin`) for time scheduling; -1 = unscheduled
- `@Query` in views that need live sorted lists; child views receive models as `let` props
- Never instantiate `DateFormatter()` inline — always use `DateFormatters.*` statics
- Drag-to-reorder in **task lists** (InboxView, ListDetailView) uses `.draggable`/`.dropDestination` (SwiftUI Transferable API) with prefixed string payloads (NOT `.onMove` — it doesn't work on macOS sidebar or plain lists)
- Drag-to-reorder in the **sidebar** uses `.onDrag`/`.onDrop` with `DropDelegate` (NOT `.draggable`/`.dropDestination` — that API installs gesture recognizers that delay tap recognition across the whole ScrollView, breaking sidebar card button clicks). The dragged ID is stored in `SidebarDragContext.shared` (a plain class, not `@State`) so it survives SwiftUI view updates between `onDrag` and `performDrop`.
- Reorder and sidebar moves use `withAnimation(.spring(...))` so order changes animate smoothly.
- Non-kanban page scroll views can use `CadenceScrollElasticity` to soften vertical rubber-banding.

## Task lists: sort, group, and row UI
**Enums** (`TasksPanel.swift`, shared by list-style surfaces): `TaskSortField` (date, priority, **custom**), `TaskSortDirection`, `TaskGroupingMode` (by date, by list, by priority, **none**). **Custom** sort uses `task.order` (manual drag reorder). **None** grouping shows a single flat section.

**Where controls appear:** Today’s task column (`TasksPanel`), Inbox, All Tasks **list** mode, Area/Project **Tasks** tab, and All Tasks / list-detail **Kanban** (sort only — Kanban **does not** offer grouping; columns stay section-based). UI uses custom “picker badge” controls (not `Menu`), consistent with All Tasks. There is **no** global task **filter** UI (do date / list / priority filters were removed).

**Drag across groups:** Dropping a task into another group/section can update the relevant attribute (e.g. do date, list, priority, kanban section) and `order`.

**`MacTaskRow` (TasksPanelComponents.swift):** Container (area/project/inbox) uses pill styling; do/due dates are smaller, lower-contrast metadata (icons + text) with hover affordances, not pills. Due date badge only renders when `!task.dueDate.isEmpty` — no empty clickable badge. Overdue tasks can show red emphasis; “over-do” (past do date) is not amber-tinted on the row. Estimate and list pickers use `EstimatePickerControl(compact: true)` / compact container control. Priority strip height is slightly less than the row; estimate/focus controls sit beside the title when hovered.

**Performance:** `MacTaskRow` does NOT read `TaskCompletionAnimationManager` directly. The completion button and animated background are extracted into `TaskCompletionButton` and `TaskRowBackground` sub-view structs, each with their own `@Environment(TaskCompletionAnimationManager.self)`. This scopes SwiftUI observation so only those small sub-views re-render on animation ticks — not every visible row.

**`ContainerPickerBadge` / `TaskSectionPickerBadge` (TasksPanelComponents.swift):** Both popovers open with a search bar auto-focused. Search filters by `hasPrefix` (case-insensitive). Navigation: ↑↓ arrows or `Enter` to select the highlighted item. The highlighted item is tracked by `highlightIdx` (index into `flatFiltered` / `filteredSections`), resets to 0 on query change or close. List name capped at 80pt (60 compact), section name at 70pt — both truncate with `…`. Rows use dedicated `ContainerPickerRow` / `SectionPickerRow` View structs (not `@ViewBuilder` functions) with `let isHighlighted: Bool` for reliable in-place updates. Checkmark follows `isHighlighted`. Hover + highlight share a single `rowBackground` computed property.

## Today view task scope
The Today **tasks** column only includes tasks that are **do today**, **due today**, **past do** (over-do), or **past due**, plus work tied to **sections due today**. A one-time **rollover** banner can appear when there are over-do tasks from the previous day; dismissing it merges those tasks into normal grouping.

Page-level filters should carry through to the page's internal sections. In practice, the Today **Completed** section only shows tasks whose `completedAt` is **today**.

When unfinished tasks are rolled from yesterday into today, Cadence clears their old timeline slot:
- `scheduledDate` is moved to today
- `scheduledStartMin` is reset to `-1`
- any linked timed calendar event is removed first

Today’s by-list organization is now explicitly grouped by **context** rather than one flat stream of lists.

**Layout:** `TodayView` uses an `HSplitView` with tuned `minWidth` / `idealWidth` / `layoutPriority` so notepad and schedule get more default space than the task column (user-adjustable dividers).

## Drag-to-Reorder Payload Prefixes
Each drag context uses a unique prefix to prevent cross-context drops:
- `"area:\(id)"` — sidebar area rows (`.onDrag`/`.onDrop` + `SidebarAreaDropDelegate`)
- `"project:\(id)"` — sidebar project rows (`.onDrag`/`.onDrop` + `SidebarProjectDropDelegate`)
- `"listTask:\(id)"` — task rows in InboxView and ListDetailView (`.draggable`/`.dropDestination`)
- `"\(id)"` (plain UUID) — tasks dragged from TasksPanel onto the timeline
- `"allDayEvent:\(eventIdentifier)"` — all-day event chips dragged from the calendar header onto a day column timeline

## Task Creation
`TaskCreationManager` is an `@Observable` singleton (`TaskCreationManager.shared`) injected via `.environment`. Call `taskCreationManager.present(...)` with optional seed values (title, notes, dueDateKey, doDateKey, priority, container, sectionName) to show `CreateTaskSheet`.

The same shared sheet is used for:
- in-app creation
- kanban column creation
- the system-wide quick task panel (`QuickTaskPanelController`)

`CreateTaskSheet` behavior:
- Title field autofocuses on open; `Cmd+Return` creates the task
- Layout: full-width content area, chip strip at bottom: `[List] [Section?] ─── [Do Date] [Due Date] [Priority]`
- No estimate button; notes field is compact (height 40)
- Do date does **not** default to today — only pre-set if `doDateKey` is provided in the seed
- Priority chip displays short labels: **N/A / L / M / H**; picker still shows full names
- List + section can be preseeded; section picker normalizes to available sections on container change
- On success the sheet **closes immediately**; feedback is a brief global **”Task created”** toast — when closing the quick-capture panel, `presentSuccessToast()` is called after a 250ms delay so the panel fully dismisses first, then activates the main app window to make the toast visible

**Sheet-local keyboard shortcuts** (active whenever the sheet window is focused):
- `Cmd+T` — set do date to today (or cancel if already today)
- `Cmd+Shift+T` — open do date picker
- `Cmd+D` — set due date to today (or cancel if already today)
- `Cmd+Shift+D` — open due date picker
- `Cmd+P` — cycle priority (none → low → medium → high → none)
- `Cmd+Shift+=` / `Cmd+Shift+-` — nudge do date ±1 day (sets to today first if unset); **while tilde panel is open**, these cycle the highlighted list/section item instead

**Tilde trigger (`~`) for inline list search:**
- Typing `~` at the start of the title or immediately after a space opens a list-search popover anchored at the `~` badge (cursor position)
- The `~` is consumed from the title while the panel is open; a highlighted `~` badge replaces it visually in the title row
- Navigate with ↑↓ arrows or `Cmd+Shift+=/−`; `Enter` selects highlighted item
- After a list is selected, a section picker opens immediately at the same location with “Default” pre-highlighted
- `Tab` in either panel closes it and puts `~` back in the title, returning focus there
- Implementation: `TildeMode` enum (`.none` / `.list` / `.section`) on `CreateTaskSheet`; `tildeFlatContainers` computed property builds a flat ordered list for index-based highlighting
- **Title ZStack pattern:** The `TextField` is always in the hierarchy (never removed) — hidden with `opacity(0)` + `allowsHitTesting(false)` when tilde mode is active. Removing and re-inserting an `NSTextField` causes macOS to select-all on re-focus. A ZStack overlay shows `Text(title) + Text(“~”)` badge when tilde mode is active, with `.popover` attached to the `~` badge.
- **Picker row structs:** `TildeContainerPickerRow` and `TildeSectionPickerRow` are dedicated `View` structs with `let isHighlighted: Bool` props (not `@ViewBuilder` functions). The checkmark follows `isHighlighted`, not `isSelected`. Hover and highlight backgrounds are consolidated into a single `rowBackground` computed property inside the Button label — never two separate `.background()` modifiers on different layers.
- **Section search focus:** `TildeSectionSearchPanel` is a standalone struct with its own `@FocusState private var isSearchFocused: Bool`. macOS popovers are separate `NSWindow` instances — parent `@FocusState` cannot reliably capture `.onKeyPress` events inside the popover. The panel sets focus via `onAppear { DispatchQueue.main.async { isSearchFocused = true } }`.
- **ForEach identity:** Use `ForEach(Array(items.enumerated()), id: \.element.id)` with `Identifiable` items — never `ForEach(indices, id: \.self)`. Integer IDs cause SwiftUI to reuse the same view for different rows, breaking highlight state. Never put `.id(highlightIdx)` on a container VStack — it destroys/recreates the whole list on each arrow press, briefly showing double highlights.

**Timeline / calendar drag-create quick popover:**
- The drag-to-create title popover for new scheduled tasks/events supports the same `~` list-search flow
- Selecting a list can immediately step into section selection
- New scheduled tasks can now be created directly into the chosen list/section via `SchedulingActions.createTask(... containerSelection: sectionName: ...)`
- While dragging out a new time range, the ghost preview shows **start**, **end**, and **duration**

## Notes / Markdown
- The user-facing and active UI/service names are **Notes**; the legacy `Document` model remains only for migration compatibility
- Notes support both Markdown export and rendered PDF export
- The notes export flow avoids direct blocking `NSSavePanel.runModal()` usage
- Notes can surface linked notes, backlinks, and embedded task references above the editor
- Wiki-style note links are supported with `[[Note Title]]`
- Task references support both `[[task:Task Title]]` and ID-backed `[[task:UUID|Task Title]]`
- Typing `/` in the editor opens a compact live slash-command picker at the insertion caret
- Slash commands cover common transforms like headings, todo/done, quote, rule, link, and task inserts
- Hidden markdown markers are skipped by caret traversal instead of behaving like visible cursor stops

## Recurrence
- Recurring tasks are part of the core task workflow; completing one spawns the next occurrence through `TaskWorkflowService`
- If a recurring task is scheduled, the next occurrence continues through the normal scheduling path

## Calendar / Events
- Tasks can attach to existing calendar events from the task inspector
- Calendar events can have linked notes; reopening the same event reopens the same linked note instead of creating duplicates
- Timeline/today schedule export uses SwiftUI-native exporter flow rather than manual AppKit save panels

## Keyboard Shortcuts (macOSRootView)
Global local monitor unless noted. **Hovered task date nudge** requires the pointer over a **do** or **due** control (`HoveredTaskManager.hoveredDateKind`).

- **Cmd+Delete** — delete hovered task/editable (custom confirmation overlay)
- **Cmd+E** — open edit sheet for hovered task **or** hovered kanban **section** header
- **Cmd+T / Cmd+Shift+T** — set Do Today / open Do Date overlay for hovered task
- **Cmd+D / Cmd+Shift+D** — set Due Today / open Due Date overlay for hovered task
- **Cmd+Shift+Plus / Cmd+Shift+Minus** — nudge hovered do or due date by one calendar day (forward / back)
- **Cmd+P** — cycle hovered task priority (`none → low → medium → high → none`)
- **Cmd+Return** — toggle completion for hovered task; also creates a task in `CreateTaskSheet`
- **Cmd+/** — toggle cancellation for hovered task (same cancel/undo-cancel behavior and animations)
- **Cmd+N** — create a task in the hovered kanban column
- **Cmd+K** — open the global command palette / search overlay
- **Cmd+O** — toggle **main** sidebar visibility (also a floating control; works in Focus mode)
- **Cmd+S** — for a hovered task, open a focused **subtasks-only** popover with the subtask field ready for typing
- **Cmd+\\** — outside Today, toggle the **right** timeline sidebar; on Today, focus and highlight the built-in timeline pane instead
- **Cmd+Z / Cmd+Shift+Z** — undo / redo; routes to SwiftData `UndoManager` **unless** an `NSTextView` or `NSTextField` is first responder, in which case the event is passed through so the text view's own undo stack handles it (covers markdown editors and notepads)

**List detail (Area/Project):** **Cmd+Shift+[ / ]** cycles tabs (Tasks, Kanban, Documents, …) — implemented in `ListDetailView`; it does not conflict with date nudge (different chords).

## Hovered date overlay (`HoveredTaskDatePickerOverlay` in macOSRootView)
`Cmd+Shift+T` / `Cmd+Shift+D` shows an overlay with **`MonthCalendarPanel` embedded inline** (no extra click to open the calendar). Clear / Cancel / Apply use full hit targets (`contentShape`, minimum sizes).

## Global Search / Command Palette
- Triggered with **Cmd+K**
- Spotlight-style centered overlay with grouped results and arrow-key navigation
- Searches pages (including hidden sidebar tabs), contexts/areas/projects, tasks, calendar events, goals, and habits
- Includes a **Commands** section with app actions like `New Task`, `Focus`, `Today`, `All Tasks`, `Calendar`, and `Settings`
- Matching is token/prefix-weighted rather than loose substring-only search
- Selecting an area/project/task/event navigates directly to the relevant destination

## List Lifecycle
- Areas and projects can be **completed**, **archived**, or **deleted**
- Active lists appear in the sidebar; completed/archived lists are hidden from the active sidebar but remain searchable
- Lifecycle actions live in the edit sheets (`EditAreaSheet`, `EditProjectSheet`)
- A dedicated **Lists** category in Settings shows all completed and archived areas/projects with reopen / unarchive / delete actions
- Deleting a list recursively deletes its tasks, documents, links, and any nested projects in the case of an area

## Timeline / Scheduling Architecture
The scheduling UI is shared between `SchedulePanel` (today's view) and `CalendarPageView` (multi-day). Both use `TimelineDayCanvas` as the rendering and interaction engine.

The timeline/calendar stack is intentionally decomposed into a shell + support-file architecture:
- `TimelineMetrics.swift` — pixel↔minute math, snapping, `TimelineBlockFrame`, `computeTimelineBlockFrame()`
- `TimelineDayCanvas.swift` — main canvas state/orchestration: drag-to-create ghost, drop zone, selection/draft state
- `TimelineTaskBlock.swift` — draggable task block, tap-to-select, detail popover, within-canvas drag
- `TimelineEventBlock.swift` — read-only calendar event block
- support files under `Views/` now carry overlay layers, shell composition, state helpers, and calendar viewport helpers

Scheduling actions are in `SchedulingService.swift` (`SchedulingActions.createTask`, `SchedulingActions.dropTask`). `createTask` also has a container-aware overload used by drag-created scheduled tasks from the timeline/calendar quick popover.

**Coordinate rule:** Visual blocks and interactive hit targets must both use `.position(x:y:)` from the same `blockX/blockY` values. Never mix `.offset()` and `.padding()` for positioning in the same layer.

## What's Built (macOS)
- [x] Fully custom sidebar with nested context grouping, hover states, drag-to-reorder, and active-only list visibility; **project due date** on list rows (red flag, clickable) replaces the old area/project type label where applicable
- [x] Today view: note + **scoped** task list + schedule; optional **right** timeline (**Cmd+\\**); sort/group like other lists
- [x] Row-based task lists with collapsible grouping and completed/logbook sections
- [x] Today task view grouped by list in sidebar order, with Inbox pinned first; overdue / over-do / rollover UX
- [x] Today completed section scoped to tasks completed today
- [x] All Tasks: **list** vs **kanban** modes; shared sort UI; list has grouping, kanban **sort only** (no grouping)
- [x] Inbox: unassigned tasks, capture bar, drag-to-reorder, sort/group controls
- [x] Full task creation sheet (title, notes, due date, do date, priority, container, section, subtasks); tilde (`~`) inline list/section search from the title field
- [x] Global hotkey to open task creation from anywhere in the OS
- [x] In-app Spotlight-style command palette / global search (`Cmd+K`)
- [x] Custom delete confirmation overlay
- [x] Hover-driven task shortcuts for edit/delete/do/due/priority/completion
- [x] Hover-driven subtask-entry shortcut (`Cmd+S`) that opens a subtasks-only popover
- [x] Drag-to-schedule tasks from task list to timeline
- [x] Timeline drag-to-create new tasks
- [x] Drag-created timeline/calendar previews show start, end, and duration live while dragging
- [x] Timeline drag-to-reposition existing tasks (with grab-offset preserved)
- [x] Unscheduled task drop preview on timeline (shows block before release)
- [x] Calendar page view: Week / 2-Week / Month modes, infinite scroll
- [x] Month view (scroll/header edge cases may still need attention)
- [x] Remembered scroll position for Today timeline and calendar
- [x] Goals view: Gantt-style timeline, 2W/Month/Quarter/Year/5Y scales
- [x] Habits: list, detail, 52-week heatmap, streak tracking, create sheet
- [x] Daily notes with markdown editor
- [x] Notes view (formerly Documents in the UI) with Markdown export and rendered PDF export
- [x] Shared markdown editor supports headings, block quotes (`>`), dividers (`---`, `***`, `___`), hidden markdown markers, ordered/unordered lists, slash commands, wiki-links, task references, and 5 nesting levels
- [x] Markdown caret movement skips hidden formatting markers rather than traversing invisible syntax
- [x] Markdown list indentation is reduced/tighter than the original editor implementation
- [x] New documents start with the document title as the first markdown heading; editing the H1 in the document body syncs back to `document.title`
- [x] Documents: each selected doc gets its own `NSTextView` instance (`.id(doc.id)`) so undo history is isolated per document
- [x] Cmd+Z / Cmd+Shift+Z undo/redo works inside markdown editors and notepads (passes through to NSTextView's own undo stack when text field is focused)
- [x] Slash command picker opens at the insertion caret inside notes
- [x] Focus timer with log session popover (logs actual minutes, propagates to goals/areas/projects)
- [x] Area/Project detail: Tasks, Kanban, Planning, Notes, Links, Completed
- [x] List Planning page: upcoming schedule columns, due-only visibility, and unscheduled backlog without a prerequisite graph
- [x] Recurring task completion flow that generates the next occurrence
- [x] Attach tasks to existing calendar events
- [x] Linked notes for calendar events
- [x] Area/Project lifecycle: complete, archive, delete; completed/archived lists recoverable from Settings
- [x] Section-based kanban with editable/reorderable/archiveable columns (Cmd+E on section header; autosave section editor)
- [x] Per-list **hide column due date when empty** (`hideSectionDueDateIfEmpty` on Area/Project; create/edit list sheets)
- [x] Section-level due dates and completion
- [x] Sections due today surfaced in Today view
- [x] Apple Calendar sync (EventKit): create, update, delete, observe; event editor can **move event to another calendar**
- [x] Calendar week/2W view: all-day banner shows all-day events + unscheduled tasks as draggable chips; chips are scrollable and clickable (opens task inspector); dragging a chip onto a day column schedules it at the dropped time
- [x] Multiple dark themes selectable in Settings
- [x] CloudKit sync
- [x] Category-based Settings shell with contexts reordering, calendar linking, sidebar tab visibility, and archived/completed list management

## What's Not Built Yet
- [ ] iOS app (stub only)
- [ ] watchOS target
- [ ] Apple Reminders integration
- [ ] Notification scheduling
- [ ] Widget extensions
- [ ] WeeklyNote / PermNote UI (models exist, no views yet)

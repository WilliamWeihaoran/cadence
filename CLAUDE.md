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
│   └── Components/
│       ├── CadenceDatePicker.swift  # Month calendar date picker + MonthCalendarPanel
│       ├── EmptyStateView.swift     # Reusable empty state (message, subtitle, icon)
│       ├── FilterPill.swift         # Tappable filter tag pill
│       └── StatCard.swift           # Tinted stat card (label, value, color, icon)
├── iOS/
│   └── iOSRootView.swift          # Stub — "coming soon" placeholder
└── macOS/
    ├── macOSRootView.swift        # Root nav: SidebarItem enum, AllTasksPageView, CreateTaskSheet overlay,
    │                              #   keyboard shortcuts (Cmd+Delete, Cmd+E, Cmd+Z/Shift+Z)
    ├── CadenceCalendarPicker.swift  # macOS-specific calendar date picker variant
    ├── Views/
    │   ├── TodayView.swift        # 3-column layout: NotePanel | TasksPanel | SchedulePanel
    │   ├── TasksPanel.swift       # Task list (Overdue/Today/Upcoming/Done + grouped mode), MacTaskRow
    │   ├── NotePanel.swift        # Today's daily note editor (inline in TodayView)
    │   ├── SchedulePanel.swift    # Today's hour-by-hour timeline with drag scheduling
    │   ├── InboxView.swift        # Inbox: tasks with no area/project, capture bar, drag-to-reorder
    │   ├── CalendarPageView.swift # Calendar: Week/2W/Month views, infinite scroll, drag scheduling
    │   ├── TimelineDayCanvas.swift  # Main canvas: drag-to-create, drop zones, interaction state
    │   ├── TimelineMetrics.swift    # Pixel↔minute coordinate math, snapping
    │   ├── TimelineTaskBlock.swift  # Draggable task card with tap/popover detail
    │   ├── TimelineEventBlock.swift # Calendar event block (read-only display)
    │   ├── GoalsView.swift        # Goal timeline (Gantt-style), multi-scale (2W to 5Y)
    │   ├── HabitsView.swift       # Habit list, detail view, heatmap, CreateHabitSheet
    │   ├── NotesView.swift        # Note list + editor (NoteListRow, NoteEditorPane)
    │   ├── FocusView.swift        # Focus timer UI with log session popover
    │   ├── SidebarView.swift      # Sidebar (Contexts, areas, projects with drag-to-reorder)
    │   ├── ListDetailView.swift   # Area/Project detail: Tasks, Log, Documents, Links tabs
    │   ├── KanbanView.swift       # Kanban column view (status-based)
    │   ├── DocumentsView.swift    # Markdown document list + editor
    │   ├── LinksView.swift        # Saved link list + add UI
    │   └── SettingsView.swift     # App settings
    ├── Sheets/
    │   ├── CreateContextSheet.swift
    │   ├── CreateListSheet.swift  # Creates Area or Project
    │   ├── CreateGoalSheet.swift
    │   ├── CreateTaskSheet.swift  # Full task creator: title, notes, due date, do date, priority, container
    │   └── EditListSheet.swift
    ├── Editor/
    │   └── MarkdownEditorView.swift  # NSTextView subclass with live markdown styling
    └── Services/
        ├── CalendarManager.swift       # EventKit wrapper: create/update/delete/observe events
        ├── FocusManager.swift          # @Observable singleton for focus timer state
        ├── TaskCreationManager.swift   # @Observable singleton: presents CreateTaskSheet with seed data
        ├── GlobalHotKeyManager.swift   # Carbon API global hotkey to open quick task panel system-wide
        ├── QuickTaskPanelController.swift  # NSPanel for system-wide quick task creation
        ├── HoveredTaskManager.swift    # Tracks which task is currently hovered (for Cmd+Delete)
        ├── HoveredEditableManager.swift  # Tracks hover state for edit/delete keyboard shortcuts
        ├── SchedulingService.swift     # SchedulingActions: createTask/dropTask helpers for timeline
        ├── AppFocus.swift              # clearAppEditingFocus() — resigns first responder app-wide
        └── PersistenceController.swift # (legacy/unused — SwiftData handles persistence)
```

## Data Models
All SwiftData `@Model` classes. **Critical CloudKit rule: all to-many relationships must be optional arrays (`[Type]?`).**

```
Context:   id, name, colorHex, icon, order
           → areas:[Area]?, projects:[Project]?, tasks:[AppTask]?, goals:[Goal]?, habits:[Habit]?

Area:      id, name, desc, colorHex, icon, order, linkedCalendarID
           → context:Context?, tasks:[AppTask]?, projects:[Project]?, documents:[Document]?, links:[SavedLink]?

Project:   id, name, desc, status("active"|"done"|"paused"|"cancelled"), colorHex, icon,
           dueDate(yyyy-MM-dd), order, linkedCalendarID
           → context:Context?, area:Area?, tasks:[AppTask]?, documents:[Document]?, links:[SavedLink]?
           computed: isDone, completionRate

Goal:      id, title, desc, startDate(yyyy-MM-dd), endDate(yyyy-MM-dd),
           progressType("subtasks"|"hours"), targetHours, loggedHours,
           colorHex, status("active"|"done"|"paused"), order, createdAt
           → context:Context?, tasks:[AppTask]?
           computed: progress (0.0–1.0)

AppTask:   id, title, notes, priority("none"|"low"|"medium"|"high"),
           status("todo"|"inprogress"|"done"|"cancelled"),
           dueDate(yyyy-MM-dd), scheduledDate(yyyy-MM-dd), scheduledStartMin(-1=unscheduled),
           estimatedMinutes, actualMinutes, calendarEventID, order, createdAt
           → area:Area?, project:Project?, goal:Goal?, context:Context?, subtasks:[Subtask]?
           computed: isDone, isCancelled, scheduledEndMin, containerName, containerColor

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
- Drag-to-reorder uses `.draggable`/`.dropDestination` with prefixed string payloads (NOT `.onMove` — it doesn't work on macOS sidebar or plain lists)

## Drag-to-Reorder Payload Prefixes
Each drag context uses a unique prefix to prevent cross-context drops:
- `"area:\(id)"` — sidebar area rows
- `"project:\(id)"` — sidebar project rows
- `"listTask:\(id)"` — task rows in InboxView and ListDetailView
- `"\(id)"` (plain UUID) — tasks dragged from TasksPanel onto the timeline

## Task Creation
`TaskCreationManager` is an `@Observable` singleton (`TaskCreationManager.shared`) injected via `.environment`. Call `taskCreationManager.present(...)` with optional seed values (title, notes, dueDateKey, doDateKey, priority, container) to show `CreateTaskSheet` as a full-screen modal overlay in `macOSRootView`. Global hotkey (via `GlobalHotKeyManager`) also triggers it system-wide.

## Keyboard Shortcuts (macOSRootView)
- **Cmd+Delete** — delete hovered task (via `HoveredTaskManager`) or hovered editable (via `HoveredEditableManager`)
- **Cmd+E** — open edit sheet for hovered item
- **Cmd+Z / Cmd+Shift+Z** — undo / redo (SwiftData `UndoManager`)

## Timeline / Scheduling Architecture
The scheduling UI is shared between `SchedulePanel` (today's view) and `CalendarPageView` (multi-day). Both use `TimelineDayCanvas` as the rendering and interaction engine.

The timeline is split across four files:
- `TimelineMetrics.swift` — pixel↔minute math, snapping, `TimelineBlockFrame`, `computeTimelineBlockFrame()`
- `TimelineDayCanvas.swift` — main canvas: drag-to-create ghost, drop zone, `TimelineDropDelegate`, `TimelineCreateRow`
- `TimelineTaskBlock.swift` — draggable task card, tap-to-select, detail popover, within-canvas drag
- `TimelineEventBlock.swift` — read-only calendar event block

Scheduling actions are in `SchedulingService.swift` (`SchedulingActions.createTask`, `SchedulingActions.dropTask`).

**Coordinate rule:** Visual blocks and interactive hit targets must both use `.position(x:y:)` from the same `blockX/blockY` values. Never mix `.offset()` and `.padding()` for positioning in the same layer.

## What's Built (macOS)
- [x] Sidebar navigation with Contexts, Areas, Projects (drag-to-reorder)
- [x] Today view: note panel + task list + schedule panel
- [x] Task list with Overdue/Today/Upcoming/Done sections, priority, due date, container picker
- [x] All Tasks page: by-do-date list + Kanban toggle
- [x] Inbox view: unassigned tasks, capture bar, drag-to-reorder
- [x] Full task creation sheet (title, notes, due date, do date, priority, container, subtasks)
- [x] Global hotkey to open task creation from anywhere in the OS
- [x] Keyboard shortcuts: Cmd+Delete (delete), Cmd+E (edit), Cmd+Z/Shift+Z (undo/redo)
- [x] Drag-to-schedule tasks from task list to timeline
- [x] Timeline drag-to-create new tasks
- [x] Timeline drag-to-reposition existing tasks (with grab-offset preserved)
- [x] Unscheduled task drop preview on timeline (shows block before release)
- [x] Calendar page view: Week / 2-Week / Month modes, infinite scroll
- [x] Month view: correct grid with no duplicate rows at month boundaries
- [x] Goals view: Gantt-style timeline, 2W/Month/Quarter/Year/5Y scales
- [x] Habits: list, detail, 52-week heatmap, streak tracking, create sheet
- [x] Daily notes with markdown editor
- [x] Focus timer with log session popover (logs actual minutes, propagates to goals/areas/projects)
- [x] Area/Project detail: Tasks, Log, Documents, Links tabs
- [x] Kanban view
- [x] Apple Calendar sync (EventKit): create, update, delete, observe changes
- [x] CloudKit sync
- [x] Settings view

## What's Not Built Yet
- [ ] iOS app (stub only)
- [ ] watchOS target
- [ ] Apple Reminders integration
- [ ] Notification scheduling
- [ ] Widget extensions
- [ ] Subtask UI (model exists, no views yet)
- [ ] WeeklyNote / PermNote UI (models exist, no views yet)

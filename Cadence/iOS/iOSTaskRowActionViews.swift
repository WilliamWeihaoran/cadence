#if os(iOS)
import SwiftData
import SwiftUI

/// The task row's swipe tray, as values rather than views — `iOSSwipeActionsModifier` draws them,
/// and it needs their titles and tints for VoiceOver's custom actions as well as for the buttons.
///
/// Two actions an edge, deliberately. The leading edge used to carry four (Today, Tomorrow, Due,
/// Clear), which made each button narrow enough to mis-hit and buried the one people actually
/// reach for. `Due today` and `Clear do date` did not disappear: they are the `Due Date` and
/// `Do Date` submenus of `iOSTaskRowContextMenu`, which every one of these rows also has.
enum iOSTaskRowSwipeActions {
    /// Full swipe right runs `Today`, because it is first and not destructive.
    static func leading(task: AppTask, modelContext: ModelContext) -> [CadenceSwipeAction] {
        [
            CadenceSwipeAction(
                id: "do-today",
                title: "Today",
                systemImage: "sun.max.fill",
                tint: Theme.amber
            ) {
                CadenceTaskDateEditing.scheduleToday(task, in: modelContext)
            },
            CadenceSwipeAction(
                id: "do-tomorrow",
                title: "Tomorrow",
                systemImage: "calendar",
                tint: Theme.blue
            ) {
                CadenceTaskDateEditing.scheduleTomorrow(task, in: modelContext)
            }
        ]
    }

    /// Full swipe left toggles completion, never deletes: `Delete` is second *and* destructive, so
    /// `CadenceSwipeActionSupport.fullSwipeIndex` will not hand it to a full swipe. It also only
    /// ever raises the row's existing confirmation alert — nothing is deleted by the gesture.
    static func trailing(
        task: AppTask,
        modelContext: ModelContext,
        requestDelete: @escaping () -> Void
    ) -> [CadenceSwipeAction] {
        // T-344: the swipe describes what `toggleCompletion` will do, so it reads the same
        // predicate that decides it. On a cancelled row this used to promise "Done" and the tap
        // delivered it; both halves say "Todo" now, because a cancelled task is already settled.
        let isFinished = CadenceTaskQuerySupport.isFinishedTask(task)
        return [
            CadenceSwipeAction(
                id: "toggle-completion",
                title: isFinished ? "Todo" : "Done",
                systemImage: isFinished ? "circle" : "checkmark.circle.fill",
                tint: isFinished ? Theme.blue : Theme.green
            ) {
                CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
            },
            CadenceSwipeAction(
                id: "delete",
                title: "Delete",
                systemImage: "trash",
                tint: Theme.red,
                isDestructive: true,
                perform: requestDelete
            )
        ]
    }
}

// MARK: - Row chips

// A task row's metadata used to be seven read-only labels: to change the list a task was in, or
// nudge its do date, you opened the row's detail sheet and came back. Each chip now opens the
// picker for the field it names, which is the whole point of showing the field on the row.
//
// Every chip here follows the same three rules:
//
// - **One shared plate.** `iOSTaskAttributeChip(size: .row)` — the same component the create sheet's
//   strip and the inspector's breadcrumb use, at the row's type ramp. The chips are not near-copies
//   of it with their own paddings.
// - **44pt, without a taller row.** The plate is 30pt; `iOSTaskAttributeChip` expands the hit area
//   to 44 without taking 44 of layout. The strip hosting these must therefore keep `lineSpacing` at
//   or above `iOSTaskAttributeChipSize.row.hitInset * 2`, or two lines' expanded regions overlap.
// - **Its own state, its own popover.** A chip owns the `@State` for its panel and anchors the
//   popover to itself, so the panel opens at the chip rather than at the row's origin, and
//   `iOSTaskRow` does not carry seven booleans. Any `@Query` a picker needs lives in the popover's
//   *content* view, which SwiftUI only instantiates once the panel is presented — the trick
//   `iOSTaskRowContextMenu` documents below, and the reason twenty visible rows do not mean twenty
//   live fetches of every area and project in the store.

/// The list chip. Neutral, because which list a task is in is ordinary information.
struct iOSTaskRowContainerChip: View {
    let task: AppTask
    @State private var showPicker = false

    var body: some View {
        iOSTaskAttributeChip(
            title: task.containerName.isEmpty ? CadenceTaskInspectorSupport.inboxSegmentTitle : task.containerName,
            field: CadenceTaskControlAccessibility.list,
            systemImage: task.project?.icon ?? task.area?.icon ?? "tray.fill",
            isSet: true,
            size: .row,
            textColor: Theme.dim
        ) {
            showPicker = true
        }
        .popover(isPresented: $showPicker) {
            iOSTaskRowContainerPickerContent(task: task, isPresented: $showPicker)
        }
    }
}

private struct iOSTaskRowContainerPickerContent: View {
    let task: AppTask
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// The sentence to show under the rows, not a flag, and it is this popover's own now
    /// ([[T-727]]) — see `move(area:project:)`.
    @State private var moveFailure: String?

    var body: some View {
        iOSContainerChoicePopover(
            areas: areas,
            projects: projects,
            selection: currentToken,
            isPresented: $isPresented,
            failureNotice: moveFailure,
            select: apply
        )
    }

    private var currentToken: String {
        if let area = task.area {
            return CadenceTaskComposerSupport.token(for: .area(area.id))
        }
        if let project = task.project {
            return CadenceTaskComposerSupport.token(for: .project(project.id))
        }
        return CadenceTaskComposerSupport.token(for: .inbox)
    }

    /// A token naming a list that is not in the store moves nothing. `selection(fromToken:)` reads
    /// anything unrecognised as Inbox, which is the right answer for a *seed* and the wrong one
    /// here: it would silently take a task out of the list it is in.
    /// Answers whether the popover may close. An unresolvable token moves nothing, so it neither
    /// closes nor reports: there is no failure to name and nothing happened to acknowledge.
    private func apply(_ token: String) -> Bool {
        switch CadenceTaskComposerSupport.selection(fromToken: token) {
        case .inbox:
            return move(area: nil, project: nil)
        case .area(let id):
            guard let area = areas.first(where: { $0.id == id }) else { return false }
            return move(area: area, project: nil)
        case .project(let id):
            guard let project = projects.first(where: { $0.id == id }) else { return false }
            return move(area: nil, project: project)
        }
    }

    /// **T-702 routed this refusal to an alert on the row; [[T-727]] brings it back here.**
    ///
    /// T-702's reading was right about the code it had: the dismissal belonged to the shared
    /// popover, which set `isPresented = false` on the tap whatever the caller then did, so the
    /// only surface that outlived the refusal was the row. `iOSContainerChoicePopover` has a
    /// committing form now — the close waits on this answer — so the picker is still open when the
    /// store refuses, and the sentence goes where the user is already looking, exactly as the Mac's
    /// kanban picker has since T-497.
    ///
    /// The row's alert stays for the **context menu**, which has no such choice: a `Menu` closes
    /// itself and cannot be told not to.
    private func move(area: Area?, project: Project?) -> Bool {
        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        ) else {
            moveFailure = CadenceTaskFieldEditCommit.saveFailureNotice
            return false
        }
        moveFailure = nil
        return true
    }
}

/// Which date a row's date chip edits. The two are one view because they differ only in which
/// field they read and what they are called — a `doChip` beside a near-identical `dueChip` is how
/// the two stopped agreeing about clearing on macOS.
enum iOSTaskRowDateField {
    case doDate
    case dueDate

    var systemImage: String {
        switch self {
        case .doDate: return "sun.max.fill"
        case .dueDate: return "flag.fill"
        }
    }

    /// The field's name, from the shared words rather than spelled here — macOS's row reads the
    /// same two constants, so the two platforms cannot announce one field two ways (T-611).
    var accessibilityLabel: String {
        switch self {
        case .doDate: return CadenceTaskControlAccessibility.doDate
        case .dueDate: return CadenceTaskControlAccessibility.dueDate
        }
    }
}

/// A do/due chip over `CadenceQuickDatePopover` — the same Today / Tomorrow / This Weekend pills,
/// month grid and Clear row the task inspector and the create sheet's chips open.
struct iOSTaskRowDateChip: View {
    let task: AppTask
    let field: iOSTaskRowDateField
    let title: String
    /// Only ever non-neutral for the two exceptional cases: a deadline gone past, a do date gone
    /// past. A do date of *today* is the common case on the Today screen and stays `Theme.dim`.
    var tint: Color = Theme.dim
    @Environment(\.modelContext) private var modelContext
    @State private var isOpen = false
    @State private var viewMonth = Date()

    private var dateKey: String {
        switch field {
        case .doDate: return task.scheduledDate
        case .dueDate: return task.dueDate
        }
    }

    var body: some View {
        iOSTaskAttributeChip(
            title: title,
            // Which of the row's two dates this is — the whole point of the name, since both draw
            // the same "Tomorrow".
            field: field.accessibilityLabel,
            systemImage: field.systemImage,
            isSet: true,
            tint: tint,
            size: .row,
            // The chip's *text* takes the exceptional colour too, not just its glyph: an item is
            // either ordinary and entirely dim, or exceptional and entirely the colour that says so.
            textColor: tint
        ) {
            viewMonth = monthStart(of: DateFormatters.date(from: dateKey) ?? Date())
            isOpen = true
        }
        .popover(isPresented: $isOpen) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { DateFormatters.date(from: dateKey) ?? Date() },
                    set: { setDate(DateFormatters.dateKey(from: $0)) }
                ),
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                showsClear: !dateKey.isEmpty,
                onClear: clearDate
            )
            .background(Theme.surfaceElevated)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func setDate(_ key: String) {
        switch field {
        case .doDate: CadenceTaskDateEditing.setScheduledDate(key, for: task, in: modelContext)
        case .dueDate: CadenceTaskDateEditing.setDueDate(key, for: task, in: modelContext)
        }
    }

    /// Clearing a do date also drops its timeline slot — a slot on no day is not a slot, which is
    /// why this goes through `clearScheduledDate` rather than writing `""` here.
    private func clearDate() {
        switch field {
        case .doDate: CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
        case .dueDate: CadenceTaskDateEditing.clearDueDate(task, in: modelContext)
        }
    }

    private func monthStart(of date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: date)
        components.day = 1
        return Calendar.current.date(from: components) ?? date
    }
}

// There is **no status chip and no status menu** (T-74). A `TaskStatus` picker offering Todo / In
// Progress / Done / Cancelled was a four-option control for a field the row already has two
// dedicated affordances for — the completion circle owns `done`/`todo`, the swipe tray and context
// menu own `cancelled` — and `.inProgress` has exactly one writer worth keeping, the task
// inspector's Start/Stop button (`iOSTaskStatusActionsSection`).
//
// `AppTask.statusRaw` and `TaskStatus` stay: the property is persisted with no
// `SchemaMigrationPlan` behind it, `isDone`/`isCancelled` derive from it, and rows already holding
// `.inprogress` must keep rendering — the row still *reads* the value, it just cannot pick one.
// Start/Stop is also deliberately kept rather than deleted with the pickers: without it a task
// already In Progress could never leave that state.

/// The repeat chip. Changing the rule on a task that belongs to a series raises the same
/// `thisTask` / `thisAndFuture` dialog the context menu does — the row owns that dialog, so the
/// choice is handed back up through `pendingRecurrenceRule`.
struct iOSTaskRowRepeatChip: View {
    let task: AppTask
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @State private var showPicker = false

    var body: some View {
        iOSTaskAttributeChip(
            title: task.recurrenceRule.shortLabel,
            field: CadenceTaskControlAccessibility.recurrence,
            systemImage: task.recurrenceRule.systemImage,
            isSet: true,
            size: .row,
            textColor: Theme.dim
        ) {
            showPicker = true
        }
        .popover(isPresented: $showPicker) {
            iOSTaskRowRepeatPickerContent(
                task: task,
                pendingRecurrenceRule: $pendingRecurrenceRule,
                isPresented: $showPicker
            )
        }
    }
}

private struct iOSTaskRowRepeatPickerContent: View {
    let task: AppTask
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// The sentence to show under the rows when the store refused the rule ([[T-656]]).
    @State private var ruleFailure: String?

    var body: some View {
        iOSChoicePopoverList(
            rows: TaskRecurrenceRule.allCases.map { rule in
                iOSChoiceRow(value: rule, title: rule.label, systemImage: rule.systemImage, color: Theme.dim)
            },
            selection: task.recurrenceRule,
            isPresented: $isPresented,
            failureNotice: ruleFailure,
            select: { rule in
                let landed = iOSTaskRecurrenceSelection.select(
                    rule,
                    for: task,
                    allTasks: allTasks,
                    modelContext: modelContext,
                    pendingRecurrenceRule: $pendingRecurrenceRule
                )
                ruleFailure = landed ? nil : CadenceTaskFieldEditCommit.saveFailureNotice
                return landed
            }
        )
    }
}

/// Picking a recurrence rule, shared by the row's repeat chip and the context menu's repeat submenu.
///
/// The branch that matters is the second one: a task that is part of a series must not have its rule
/// rewritten until the user has said whether they mean this occurrence or the rest of them, so the
/// rule is parked in `pendingRecurrenceRule` and `iOSTaskRowRecurrenceScopeDialog` asks.
enum iOSTaskRecurrenceSelection {

    /// **Answers whether the picker that called it may close ([[T-656]]).**
    ///
    /// It used to end `try? modelContext.save()` and tell nobody, and the picker above it closed
    /// unconditionally — `CadenceChoicePopoverList`'s row wrote the binding and dismissed in the
    /// same tap, so the dismissal *was* the success report and the swallow was two files away from
    /// it. Neither half of the `try? save()` rule could see that: the report and the swallow are in
    /// different files and the link between them was a `Binding` setter, which is not a call.
    ///
    /// `true` means "close": the rule is in the store, or nothing needed changing, or the scope
    /// dialog has been armed and must be allowed to present. `false` means the store refused, the
    /// task is exactly as it was found, and the picker stays open to say so.
    ///
    /// The commit is `CadenceTaskFieldEditCommit` rather than a hand-rolled snapshot, for the
    /// reason `iOSTaskRowRecurrenceScopeDialogModifier` gives about the series branch: it is the
    /// unit every other recurrence edit in the app already goes through.
    @discardableResult
    static func select(
        _ rule: TaskRecurrenceRule,
        for task: AppTask,
        allTasks: [AppTask],
        modelContext: ModelContext,
        pendingRecurrenceRule: Binding<TaskRecurrenceRule?>
    ) -> Bool {
        guard task.recurrenceRule != rule else { return true }
        guard !task.isRecurrenceSeriesMember else {
            pendingRecurrenceRule.wrappedValue = rule
            return true
        }
        return CadenceTaskFieldEditCommit.commit(task, in: modelContext) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
        }
    }
}

/// The milestone chip. The glyph keeps the goal's own `colorHex` — a goal's colour is the user's
/// own, and it is what tells two milestones apart — while the text stays row-neutral.
struct iOSTaskRowGoalChip: View {
    let task: AppTask
    let goal: Goal
    @State private var showPicker = false

    var body: some View {
        iOSTaskAttributeChip(
            title: TaskTitleSupport.displayTitle(goal.title, fallback: "Goal"),
            field: CadenceTaskControlAccessibility.milestone,
            systemImage: goal.icon,
            isSet: true,
            size: .row,
            textColor: Theme.dim
        ) {
            showPicker = true
        }
        .popover(isPresented: $showPicker) {
            iOSTaskRowGoalPickerContent(task: task, isPresented: $showPicker)
        }
    }
}

private struct iOSTaskRowGoalPickerContent: View {
    let task: AppTask
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.order) private var goals: [Goal]
    /// The sentence to show under the rows when the store refused the milestone ([[T-656]]).
    @State private var goalFailure: String?

    /// Finished goals are not offered — but the task's own goal is always in the list even if it is
    /// finished, or the picker would open with no row matching the chip that opened it.
    private var availableGoals: [Goal] {
        let openGoals = goals.filter { $0.status != .done }
        guard let currentGoal = task.goal,
              !openGoals.contains(where: { $0.id == currentGoal.id })
        else { return openGoals }
        return openGoals + [currentGoal]
    }

    var body: some View {
        iOSChoicePopoverList(
            rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", systemImage: "circle.dashed", color: Theme.dim)]
                + availableGoals.map { goal in
                    iOSChoiceRow(
                        value: Optional(goal.id),
                        title: CadenceTitleNormalization.display(goal.title, fallback: CadenceTitleNormalization.defaultMilestoneTitle),
                        systemImage: goal.icon,
                        color: Color(hex: goal.colorHex)
                    )
                },
            selection: task.goal?.id,
            isPresented: $isPresented,
            failureNotice: goalFailure,
            select: selectGoal
        )
    }

    /// **The same defect the repeat chip beside it had ([[T-656]])**: `task.goal = …` followed by
    /// `try? modelContext.save()`, in a binding setter, under a row that closed the popover in the
    /// same tap. The undo is written inline rather than through `CadenceTaskFieldEditCommit`
    /// because `CadenceTaskFieldSnapshot` deliberately does not carry `goal` — its own doc names
    /// the boundary — and one field is exactly the case `commitEdit(in:undo:)` documents as the
    /// caller's own.
    private func selectGoal(_ goalID: UUID?) -> Bool {
        let previous = task.goal
        let next = goalID.flatMap { id in availableGoals.first { $0.id == id } }
        guard previous?.id != next?.id else {
            goalFailure = nil
            return true
        }
        task.goal = next
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                task.goal = previous
            }
        } catch {
            goalFailure = CadenceTaskFieldEditCommit.saveFailureNotice
            return false
        }
        goalFailure = nil
        return true
    }
}

/// The estimate, at the row's trailing edge — where the disclosure chevron used to be.
///
/// An estimate is a property of the task like its priority, not a date, which is the same reasoning
/// that moved macOS's estimate out of the inspector's SCHEDULE well and onto its title row. It is
/// drawn only when there is one: a placeholder on every row would put a permanent control at the
/// edge of every task in the app for a field most tasks never use.
struct iOSTaskRowEstimateChip: View {
    let task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false

    var body: some View {
        iOSTaskAttributeChip(
            title: CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes),
            field: CadenceTaskControlAccessibility.estimate,
            systemImage: "clock",
            isSet: true,
            size: .row,
            textColor: Theme.dim
        ) {
            showPicker = true
        }
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            EstimatePickerPopoverContent(
                value: Binding(
                    get: { task.estimatedMinutes },
                    set: { CadenceTaskMutationSupport.setEstimatedMinutes($0, for: task, modelContext: modelContext) }
                )
            ) {
                showPicker = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// One unfinished subtask, listed beneath its task.
///
/// The **whole row** is the button, not just the circle: the only thing to do with a subtask from
/// here is finish it, and a 12pt glyph as the sole target in a list of them is the kind of control
/// that gets missed. It is a `Button` rather than a tap gesture so it outranks the task row's own
/// tap — which would otherwise open the detail sheet instead — and `minHeight` keeps the target
/// honest without an expanded hit area that would overlap its neighbours.
/// The `compact` flag this used to take is gone with `iOSTaskRowDensity`; see
/// `CadenceTaskRowMetrics`. Its only writer was the row's density, and on a phone that meant a
/// subtask under a Today task was drawn 1pt smaller than the same subtask under an Inbox task.
struct iOSTaskRowSubtaskRow: View {
    let subtask: Subtask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            subtask.isDone = true
            try? modelContext.save()
        } label: {
            HStack(spacing: 8) {
                iOSTaskCompletionCircle(isDone: false, tint: Theme.dim, diameter: 12)
                Text(TaskTitleSupport.displayTitle(subtask.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Complete subtask \(subtask.title)")
    }
}

/// The queries live here rather than on `iOSTaskRow`: this view is the context menu's *content*,
/// so it is only instantiated when the menu is actually presented, whereas the row that hosts it
/// exists once per visible task.
struct iOSTaskRowContextMenu: View {
    let task: AppTask
    /// T-201: an action, not a `Binding<Bool>` into the row. The row no longer owns the panel's
    /// presentation state, so there is no flag here to bind to.
    let openDetail: () -> Void
    @Binding var showDeleteConfirmation: Bool
    /// See `iOSTaskRowContainerChip.moveFailed`. A `Menu` closes itself on the tap exactly as the
    /// popover does, so this refusal has no surface of its own either (T-702).
    @Binding var moveFailed: Bool
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    /// The same grouped three-way choice `iOSContainerChoicePopover` offers, in a menu instead of
    /// a popover — so it narrows the same way (T-514): the list the task is already in stays
    /// offered even once it is archived or finished, because otherwise this menu shows no
    /// checkmark at all and has no row that means "where this task is".
    private var offerableAreas: [Area] {
        CadenceTaskComposerSupport.pickableAreas(areas, selectedID: task.area?.id)
    }

    private var offerableProjects: [Project] {
        CadenceTaskComposerSupport.pickableProjects(projects, selectedID: task.project?.id)
    }

    private var availableSectionNames: [String] {
        let rawNames = task.area?.sectionNames ?? task.project?.sectionNames ?? []
        let names = rawNames.isEmpty ? [TaskSectionDefaults.defaultName] : rawNames
        if names.contains(where: { $0.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame }) {
            return names
        }
        return names + [task.resolvedSectionName]
    }

    var body: some View {
        Button(action: openDetail) {
            Label("Edit", systemImage: "square.and.pencil")
        }

        focusMenuItem

        priorityMenu
        recurrenceMenu
        doDateMenu
        dueDateMenu
        sectionMenu
        moveToListMenu

        Button {
            _ = try? CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Task", systemImage: "trash")
        }
    }

    // The status submenu is gone with the status chip (T-74) — it was the same four-option picker
    // in a second shape, on the same row, and every value in it is either what the completion
    // circle does or what the swipe tray's own action does.

    /// T-266: the phone's answer to macOS's hover ▶ on `MacTaskRow`. It goes in the long-press
    /// menu rather than the swipe tray because a swipe is for the two or three things you do to a
    /// task without looking, and this one takes you to another screen — and because the menu is
    /// attached to `iOSTaskRow`, which is *the* task row on every iOS surface, so one entry reaches
    /// Today, All Tasks, Inbox, list detail, the calendar inspector and the month agenda at once.
    ///
    /// `.shared` rather than `@Environment`: this view only ever writes to the inbox. The two views
    /// that observe it — the shell, which navigates, and `iOSFocusView`, which adopts — take it from
    /// the environment. Same division `CadenceDeepLinkManager` already uses.
    ///
    /// **T-276: absent on a settled task, not disabled.** macOS's ▶ has always been gated on this
    /// predicate and draws a `Color.clear` spacer instead; this entry asked nothing, and the handoff
    /// resolves, so the session really ran and really banked minutes against work already finished
    /// or cancelled. A menu is a list of things you can do, so the item simply is not in it — the
    /// same shape the completion circle's own state already gives the row.
    ///
    /// It is its own property rather than an `if` inside `body` so a test can brace-match *this*
    /// declaration: `iOSTaskRowActionViews.swift` holds several views, so `var body: some View` is
    /// not a unique landmark in it and a needle counted over the whole file would survive the guard
    /// being deleted.
    @ViewBuilder
    private var focusMenuItem: some View {
        if CadenceFocusSupport.canFocus(task) {
            Button {
                CadenceFocusHandoffCenter.shared.request(.task(task.id))
            } label: {
                Label("Focus", systemImage: CadenceFeatureDestination.focus.systemImage)
            }
        }
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext)
                } label: {
                    Label(priority.label, systemImage: priority == task.priority ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label("Priority: \(task.priority.label)", systemImage: "flag.fill")
        }
    }

    private var recurrenceMenu: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { recurrence in
                Button {
                    selectRecurrenceRule(recurrence)
                } label: {
                    Label(
                        recurrence.label,
                        systemImage: recurrence == task.recurrenceRule ? "checkmark.circle.fill" : recurrence.systemImage
                    )
                }
            }
        } label: {
            Label(task.recurrenceRule == .none ? "Repeat" : "Repeat: \(task.recurrenceRule.shortLabel)", systemImage: "repeat")
        }
    }

    private var doDateMenu: some View {
        Menu {
            Button {
                CadenceTaskDateEditing.scheduleToday(task, in: modelContext)
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }

            Button {
                CadenceTaskDateEditing.scheduleTomorrow(task, in: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskDateEditing.scheduleNextWeek(task, in: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Do Date", systemImage: "sun.max.fill")
        }
    }

    private var dueDateMenu: some View {
        Menu {
            Button {
                CadenceTaskDateEditing.dueToday(task, in: modelContext)
            } label: {
                Label("Today", systemImage: "flag.fill")
            }

            Button {
                CadenceTaskDateEditing.dueTomorrow(task, in: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskDateEditing.dueNextWeek(task, in: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.dueDate.isEmpty {
                Button {
                    CadenceTaskDateEditing.clearDueDate(task, in: modelContext)
                } label: {
                    Label("Clear Due Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Due Date", systemImage: "flag.fill")
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        let names = availableSectionNames
        if names.count > 1 {
            Menu {
                ForEach(names, id: \.self) { section in
                    Button {
                        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext)
                    } label: {
                        Label(section, systemImage: section.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame ? "checkmark.circle.fill" : "rectangle.split.3x1")
                    }
                }
            } label: {
                Label("Move Section", systemImage: "rectangle.split.3x1.fill")
            }
        }
    }

    private var moveToListMenu: some View {
        Menu {
            Button {
                moveToContainer(area: nil, project: nil)
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : "tray.fill")
            }

            if !offerableAreas.isEmpty {
                Divider()

                ForEach(offerableAreas) { area in
                    Button {
                        moveToContainer(area: area, project: nil)
                    } label: {
                        Label(CadenceAreaPickerSupport.title(for: area), systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : area.icon)
                    }
                }
            }

            if !offerableProjects.isEmpty {
                Divider()

                ForEach(offerableProjects) { project in
                    Button {
                        moveToContainer(area: nil, project: project)
                    } label: {
                        Label(CadenceProjectPickerSupport.title(for: project), systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : project.icon)
                    }
                }
            }
        } label: {
            Label("Move to List", systemImage: "folder.fill")
        }
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        iOSTaskRecurrenceSelection.select(
            rule,
            for: task,
            allTasks: allTasks,
            modelContext: modelContext,
            pendingRecurrenceRule: $pendingRecurrenceRule
        )
    }

    /// **T-702.** The other half of the same discard. The menu's checkmarks read the task rather
    /// than a token, so they self-correct on the restore — what was missing is that the menu had
    /// already closed, leaving a tap on "Move to List" that did nothing and said nothing.
    private func moveToContainer(area: Area?, project: Project?) {
        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        ) else {
            moveFailed = true
            return
        }
        moveFailed = false
    }
}

/// Takes no `allTasks` list: a `ViewModifier` renders as part of its host row, so a `@Query`
/// here would cost exactly what one on the row costs. The series lookup is instead fetched at
/// the moment the user picks a scope, which happens at most once per presented dialog.
struct iOSTaskRowRecurrenceScopeDialogModifier: ViewModifier {
    let task: AppTask
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Environment(\.modelContext) private var modelContext
    /// The sentence to show, not a flag: the two ways this dialog fails are a series that could not
    /// be read and a store that refused the write, and they are different sentences (T-633).
    @State private var seriesUpdateFailure: String?

    private var isPresented: Binding<Bool> {
        Binding(
            get: { pendingRecurrenceRule != nil },
            set: { presented in
                if !presented {
                    pendingRecurrenceRule = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            CadenceRecurrenceScopeCopy.taskScopeTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                applyPendingRecurrenceRule(scope: .thisTask)
            }
            Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingRecurrenceRule(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurrenceRule = nil
            }
        } message: {
            Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
        }
        .alert(
            CadenceRecurrenceScopeCopy.taskScopeFailureTitle,
            isPresented: Binding(
                get: { seriesUpdateFailure != nil },
                set: { if !$0 { seriesUpdateFailure = nil } }
            ),
            presenting: seriesUpdateFailure
        ) { _ in
            Button("OK", role: .cancel) { seriesUpdateFailure = nil }
        } message: { notice in
            Text(notice)
        }
    }

    /// **The commit is not swallowed and the dialog is not the report (T-633).**
    ///
    /// Closing the dialog — which is what `pendingRecurrenceRule = nil` does — used to be the last
    /// thing that happened before `try? modelContext.save()`, so a refused write looked exactly
    /// like an accepted one: for `.thisAndFuture` every later occurrence in the series had its rule
    /// rewritten in memory, the sheet closed, and the alert two lines above had nothing that could
    /// ever fire it. The alert already existed; this is the path to it.
    ///
    /// `CadenceTaskFieldEditCommit.commit` is the unit rather than a fourth hand-rolled snapshot:
    /// it is the one macOS's `TaskEmbedFieldEditorPopover` reaches this same dialog through, and
    /// its `alsoRestoring:` is there for exactly this edit — `.thisAndFuture` writes the rule to
    /// every later occurrence, so the undo has to reach all of them, and the list is the one the
    /// edit itself walks rather than a second derivation of it.
    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let rule = pendingRecurrenceRule else { return }
        // The dialog closes either way: a confirmation dialog dismisses itself on the button tap,
        // and leaving the binding non-nil behind an alert would ask this row to present twice.
        pendingRecurrenceRule = nil

        // "This and future" is the only scope that needs the rest of the series, and a failed
        // fetch must not quietly downgrade it to a one-occurrence edit — the user asked to change
        // a series, and changing one instance instead is a different, silent answer. Same set and
        // same ordering the `@Query(sort: \AppTask.order)` this replaced produced.
        var allTasks: [AppTask] = []
        if scope == .thisAndFuture {
            do {
                allTasks = try modelContext.fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
            } catch {
                seriesUpdateFailure = CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice
                return
            }
        }

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
        let landed = CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        if !landed {
            seriesUpdateFailure = CadencePendingChangePersistence.editFailureNotice
        }
    }
}

/// The one iOS spelling of "that delete did not land" (T-440).
///
/// Both surfaces that can refuse a task delete — `iOSTaskRow` and `iOSTaskDetailSheet` — used to
/// carry their own copy of this alert: the same title, the same shared sentence, the same single
/// `OK` button. The test that pinned them read both files and asserted the two **agreed**, which is
/// the shape of a comparison standing in for a shared thing. Agreement that has to be asserted is
/// duplication; there is one modifier now, and the test reads the one call each surface makes.
///
/// It is an alert rather than an inline notice for the reason both call sites already recorded: a
/// destructive confirmation alert dismisses itself on the button tap, so — unlike the note and list
/// sheets, which stay open and say why — there is no surface left to report into. macOS answers this
/// differently on purpose (`DeleteConfirmationManager` holds its overlay open), which is why this
/// lives here and not in `Shared/`; only the sentence and the title are shared, and those are on
/// `CadenceTaskMutationSupport`.
struct iOSTaskDeleteFailureAlertModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert(CadenceTaskMutationSupport.deleteFailureAlertTitle, isPresented: $isPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(CadenceTaskMutationSupport.deleteFailureNotice)
            }
    }
}

/// A refused **move between lists**, on the two row affordances that have nowhere to put it
/// (T-702).
///
/// An alert for the reason `iOSTaskDeleteFailureAlertModifier` gives: a `Menu` closes itself on
/// the tap and cannot be told not to, so the affordance that made the move is gone by the time the
/// store answers.
///
/// **[[T-727]] took the chip off this alert and left the menu on it.** Both used to be here, and
/// the chip only because `iOSContainerChoicePopover` closed itself in the same statement that
/// picked the list; it has a committing form now, so that picker stays open over a refusal and
/// says so under its own rows — like the Mac's kanban popover and `iOSTaskDetailSheet`, and unlike
/// a `Menu`, which has no such choice.
struct iOSTaskMoveFailureAlertModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert(CadenceTaskMutationSupport.moveFailureAlertTitle, isPresented: $isPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(CadenceTaskFieldEditCommit.saveFailureNotice)
            }
    }
}

extension View {
    /// See `iOSTaskDeleteFailureAlertModifier`.
    func iOSTaskDeleteFailureAlert(isPresented: Binding<Bool>) -> some View {
        modifier(iOSTaskDeleteFailureAlertModifier(isPresented: isPresented))
    }

    /// See `iOSTaskMoveFailureAlertModifier`.
    func iOSTaskMoveFailureAlert(isPresented: Binding<Bool>) -> some View {
        modifier(iOSTaskMoveFailureAlertModifier(isPresented: isPresented))
    }

    func iOSTaskRowRecurrenceScopeDialog(
        task: AppTask,
        pendingRecurrenceRule: Binding<TaskRecurrenceRule?>
    ) -> some View {
        modifier(iOSTaskRowRecurrenceScopeDialogModifier(
            task: task,
            pendingRecurrenceRule: pendingRecurrenceRule
        ))
    }
}
#endif

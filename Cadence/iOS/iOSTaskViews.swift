#if os(iOS)
import SwiftData
import SwiftUI

enum iOSTaskRowDensity {
    case regular
    case compact
}

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    var density: iOSTaskRowDensity = .regular
    /// Off for surfaces that are already scoped to one list, where naming it on every row is
    /// noise — the same knob, and the same reason, as `KanbanCard.showsContainerChip` on macOS.
    var showsContainer: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    // No `@Query` here on purpose. A list can have twenty of these rows alive at once, and a
    // task/area/project query per row meant twenty live fetches plus twenty observation
    // registrations re-firing on any write — for data only the context menu and the recurrence
    // dialog ever read. The queries now live in the context-menu *content* (only instantiated
    // when the menu is presented), the same trick `KanbanContainerMetaButton` documents.
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isCompact: Bool {
        density == .compact
    }

    var body: some View {
        rowContent
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .frame(minHeight: 44)
            // One layer, one radius: the divider is the row's only chrome, at the same weight
            // `MacTaskRow` draws its bottom hairline.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.22))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showDetail = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens task details")
            .sheet(isPresented: $showDetail) {
                iOSTaskDetailSheet(task: task)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                iOSTaskRowTrailingSwipeActions(
                    task: task,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                iOSTaskRowLeadingSwipeActions(task: task)
            }
            .contextMenu {
                iOSTaskRowContextMenu(
                    task: task,
                    showDetail: $showDetail,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    pendingRecurrenceRule: $pendingRecurrenceRule
                )
            }
            .iOSTaskRowRecurrenceScopeDialog(
                task: task,
                pendingRecurrenceRule: $pendingRecurrenceRule
            )
            .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteTask)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
            .onAppear(perform: handlePendingDeepLink)
            .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
                handlePendingDeepLink()
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: isCompact ? 9 : (isRegularWidth ? 12 : 9)) {
            completionButton
            taskSummary

            // Neutral, like every other piece of row chrome. It used to be tinted by priority —
            // or, for an unprioritised task, by the container colour — which made a plain
            // disclosure arrow the loudest colour in the row and duplicated what the completion
            // circle already says. macOS removed the same container-colour bleed from its row.
            Image(systemName: "chevron.right")
                .font(.system(size: isCompact ? 10 : (isRegularWidth ? 12 : 10), weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.top, 4)
        }
    }

    private var rowHorizontalPadding: CGFloat {
        if isCompact { return 11 }
        return isRegularWidth ? 14 : 11
    }

    private var rowVerticalPadding: CGFloat {
        if isCompact { return 8 }
        return isRegularWidth ? 12 : 9
    }

    /// The circle carries priority and nothing else, exactly as `MacTaskRow`'s does — and once a
    /// task is done every priority converges on `Theme.doneFill`. It used to fall back to the
    /// *container* colour for an unprioritised task, so one glyph meant two different things.
    ///
    /// `iOSExpandedHitArea` gives the glyph a 44pt touch target without letting it take 44pt of
    /// layout, which would shove the title across the row.
    private var completionButton: some View {
        Button {
            toggleCompletion()
        } label: {
            iOSTaskCompletionCircle(
                isDone: task.isDone,
                tint: Theme.priorityColor(task.priority),
                diameter: isCompact ? 14 : 16
            )
            .frame(width: completionGlyphSize, height: completionGlyphSize)
            .iOSExpandedHitArea((44 - completionGlyphSize) / 2)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")
    }

    private var completionGlyphSize: CGFloat {
        if isCompact { return 20 }
        return isRegularWidth ? 24 : 20
    }

    private var taskSummary: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : (isRegularWidth ? 8 : 6)) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .strikethrough(task.isDone, color: Theme.dim)
                .lineLimit(isCompact ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: secondaryFontSize, weight: .medium))
                    .foregroundStyle(Theme.dim.opacity(task.isDone ? 0.58 : 0.82))
                    .lineLimit(isCompact ? 1 : (isRegularWidth ? 2 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            taskBadges

            if !isCompact {
                tagScroller
            }
        }
    }

    private var secondaryFontSize: CGFloat {
        if isCompact { return 10.5 }
        return isRegularWidth ? 12 : 11
    }

    private var taskBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isCompact ? 4 : (isRegularWidth ? 6 : 5)) {
                taskBadgeContent
            }
            .padding(.trailing, 1)
        }
    }

    /// Notes preview only. The container used to be glued onto the front of this string
    /// (`"Errands - buy milk"`), which read as prose and left the list a task belongs to
    /// unclickable and indistinguishable from its notes. It is a chip now, like macOS's.
    private var secondaryLine: String? {
        let previewLimit = isCompact ? 80 : (isRegularWidth ? 120 : 64)
        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: task.notes, limit: previewLimit)
        return preview.isEmpty ? nil : preview
    }

    /// Row metadata, in `MacTaskRow`'s vocabulary: a tinted icon carries the *identity* of the
    /// field (amber sun = do date, red flag = due date, the goal's own colour = goal) while the
    /// text stays neutral, going red only when a date is genuinely late. Every one of these used
    /// to be a filled capsule in its own hue, so a task with four attributes rendered as four
    /// competing colours and urgency stopped standing out.
    ///
    /// Priority is deliberately absent: it is the completion circle's job here exactly as it is on
    /// macOS, and a chip repeating it was a second affordance for one field.
    @ViewBuilder
    private var taskBadgeContent: some View {
        if showsListContextChip {
            iOSTaskContainerChip(
                icon: task.project?.icon ?? task.area?.icon ?? "tray.fill",
                name: task.containerName,
                tint: Color(hex: task.containerColor),
                compact: isCompact
            )
        }

        if task.status == .inProgress {
            taskMeta(systemImage: "play.fill", text: "In Progress", tint: Theme.blue)
        }

        if !task.scheduledDate.isEmpty {
            taskMeta(
                systemImage: task.scheduledStartMin >= 0 ? "clock.fill" : "sun.max.fill",
                text: scheduledDateLabel,
                tint: Theme.amber,
                textColor: isOverdo ? Theme.red : (isDoToday ? Theme.amber : Theme.dim)
            )
        }

        if let dueUrgency {
            taskMeta(
                systemImage: "flag.fill",
                text: CadenceTaskPresentationSupport.dueDateLabel(for: task),
                tint: dueUrgency == .overdue ? Theme.red : Theme.dim,
                textColor: dueUrgency == .overdue ? Theme.red : Theme.dim
            )
        }

        if task.recurrenceRule != .none {
            taskMeta(systemImage: task.recurrenceRule.systemImage, text: task.recurrenceRule.shortLabel, tint: Theme.purple)
        }

        if let subtaskProgress = CadenceTaskPresentationSupport.subtaskProgress(for: task) {
            taskMeta(
                systemImage: "checklist",
                text: isCompact ? subtaskProgress.compactLabel : subtaskProgress.label,
                tint: subtaskProgress.completed == subtaskProgress.total ? Theme.green : Theme.dim
            )
        }

        if task.estimatedMinutes > 0 {
            taskMeta(systemImage: "clock", text: estimateLabel, tint: Theme.dim)
        }

        if CadenceTaskPresentationSupport.hasNotes(task) {
            taskMeta(systemImage: "doc.text", text: "Notes", tint: Theme.dim)
        }

        if let goal = task.goal {
            taskMeta(
                systemImage: goal.icon,
                text: goal.title.isEmpty ? "Goal" : goal.title,
                tint: Color(hex: goal.colorHex)
            )
        }
    }

    private var showsListContextChip: Bool {
        showsContainer && !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Same semantics as `KanbanCardComputedSupport.isOverdo` / `.isDoToday`, which macOS's row and
    /// card both read: a finished task is never late, and the comparison goes through
    /// `DateFormatters.dayOffset` rather than a string compare so both platforms answer alike.
    /// That helper is behind `#if os(macOS)`; the two should be folded into one shared classifier.
    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    private var isDoToday: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    @ViewBuilder
    private var tagScroller: some View {
        if !task.sortedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(task.sortedTags.prefix(4)) { tag in
                        iOSTagChip(tag: tag)
                    }

                    if task.sortedTags.count > 4 {
                        Text("+\(task.sortedTags.count - 4)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Theme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    /// `CadenceDueUrgency` rather than an inline `dueDate < todayKey`: the inline spelling had no
    /// `isDone` guard, so a task completed after its deadline kept rendering a red flag badge
    /// telling the user a settled deadline was still urgent. macOS reads the same classifier.
    private var dueUrgency: CadenceDueUrgency? {
        CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone)
    }

    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes)
    }

    private var scheduledDateLabel: String {
        CadenceTaskPresentationSupport.scheduledDateLabel(for: task)
    }

    private func taskMeta(
        systemImage: String,
        text: String,
        tint: Color,
        textColor: Color = Theme.dim
    ) -> some View {
        iOSTaskMetaLabel(
            systemImage: systemImage,
            text: text,
            tint: tint,
            textColor: textColor,
            compact: isCompact
        )
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }

    private func deleteTask() {
        CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        showDetail = true
        deepLinkManager.clearPendingTask(task.id)
    }
}

/// One piece of row metadata, in the vocabulary `KanbanMetaChip` established on macOS: the icon
/// carries identity (which field this is, whose colour it belongs to) and the text carries state.
/// No fill, because a strip of filled capsules turns every attribute into an alert.
struct iOSTaskMetaLabel: View {
    let systemImage: String
    let text: String
    /// Icon colour. Identity, not state — see the note on `KanbanMetaHoverStyle`.
    let tint: Color
    var textColor: Color = Theme.dim
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
    }
}

/// The list chip. The container colour stays on the **icon** — that is the list's identity — while
/// the chip itself is the same neutral raised surface on every row, so a wall of tasks does not
/// become a wall of whatever hues the user happened to pick for their lists. Same rule
/// `KanbanCard.contextMetaItem` documents on macOS.
struct iOSTaskContainerChip: View {
    let icon: String
    let name: String
    let tint: Color
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(name.isEmpty ? "Inbox" : name)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 3 : 4)
        .background(Theme.surfaceElevated.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

struct iOSTaskListRow: View {
    @Bindable var task: AppTask
    var opacity: Double = 1
    var showsContainer: Bool = true

    var body: some View {
        iOSTaskRow(task: task, showsContainer: showsContainer)
            .opacity(opacity)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Delegates to the shared `SectionEyebrowLabel` rather than re-spelling its size/weight/kerning —
/// this was a byte-for-byte copy of it with a tint, which is what the shared component's `tint`
/// parameter is for.
struct iOSTaskSectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        SectionEyebrowLabel(text: title, tint: color)
            .padding(.top, 6)
    }
}

struct iOSTaskViewOptionsBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    var completedCount: Int
    @State private var showSortPicker = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Both controls are the same neutral chip on the same radius, sized to a 44pt touch target.
    /// They used to be two different treatments for two peer controls — a blue-washed capsule
    /// beside a grey one — which read as one being an action and the other a state.
    var body: some View {
        HStack(spacing: 10) {
            Button {
                showSortPicker = true
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, isRegularWidth ? 12 : 10)
                    .frame(minHeight: 44)
                    .background(Theme.surfaceElevated.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.iosPressable)
            .popover(isPresented: $showSortPicker) {
                iOSChoicePopoverList(
                    rows: CadenceTaskSortMode.allCases.map { mode in
                        iOSChoiceRow(value: mode, title: mode.title, color: Theme.blue)
                    },
                    selection: $sortMode,
                    isPresented: $showSortPicker
                )
            }

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, isRegularWidth ? 12 : 10)
                    .frame(minHeight: 44)
                    .background(showCompleted ? Theme.surfaceElevated.opacity(0.72) : Theme.surfaceElevated.opacity(0.36))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.iosPressable)
            .disabled(completedCount == 0)
            .opacity(completedCount == 0 ? 0.45 : 1)
        }
        .tint(Theme.blue)
    }
}

struct iOSTaskCaptureBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let placeholder: String
    @Binding var title: String
    let action: () -> Void

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: isRegularWidth ? 15 : 15))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, isRegularWidth ? 13 : 12)
                .frame(minHeight: 44)
                .background(Theme.surfaceElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: isRegularWidth ? 16 : 15, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 44, height: 44)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.iosPressable)
            .disabled(TaskTitleSupport.isEmpty(title))
            .opacity(TaskTitleSupport.isEmpty(title) ? 0.45 : 1)
        }
    }
}

let iOSPanelHeaderHeight: CGFloat = 92

struct iOSPanelHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    var count: Int? = nil

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: isRegularWidth ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: isRegularWidth ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 10 : 8)
                    .padding(.vertical, isRegularWidth ? 6 : 4)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, isRegularWidth ? 20 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
    }
}

/// Thin wrapper over the shared `EmptyStateView`, which is what macOS's empty states render.
/// This used to be a second, slightly-different empty state (flat glyph, no medallion, its own
/// type ramp) sitting beside the shared one in the same app. The signature is kept so the two
/// dozen call sites across the iOS surface do not have to change.
///
/// Empty states are one of the three places that deliberately *keep* a subtitle — it says
/// something the screen does not.
struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        EmptyStateView(message: title, subtitle: subtitle, icon: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
    }
}
#endif

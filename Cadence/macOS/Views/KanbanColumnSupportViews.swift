#if os(macOS)
import SwiftUI

// MARK: - Shared column chrome
//
// Everything in this MARK section is used by BOTH kanban column implementations —
// `ListSectionKanbanColumn` (KanbanSectionColumnView.swift) and `TaskListKanbanColumn`
// (KanbanListColumnView.swift). The two boards must look identical; keeping the styling here
// rather than copy-pasted in each column is what makes that structural instead of accidental.
// If you need to change column appearance, change it here — never in one column only.

/// The 7pt dot + uppercased title + task count that opens every kanban column, on both boards.
/// `trailing` is where a board adds its own controls (the section board puts the completion and
/// ellipsis buttons there; the list board passes `EmptyView()`).
struct KanbanColumnTitleRow<Trailing: View>: View {
    let dotColor: Color
    let title: String
    let count: Int
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: kanbanColumnDotSize, height: kanbanColumnDotSize)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()

            trailing()
        }
    }
}

extension KanbanColumnTitleRow where Trailing == EmptyView {
    init(dotColor: Color, title: String, count: Int) {
        self.init(dotColor: dotColor, title: title, count: count) { EmptyView() }
    }
}

/// The **one** column-header treatment, shared by every board surface: the section/list kanban
/// columns, and the Calendar Board's day columns and pinned rails. Same dot, same label size and
/// casing, same count placement, same padding, same closing hairline. Paired with
/// `KanbanColumnScroll`, which puts the add-task row in the same place on all of them.
///
/// It is width-agnostic on purpose: the Calendar Board's rails are narrower than its day columns
/// and still line up, because the header fills whatever width its column hands it.
///
/// Exactly three things may differ per board, because they are genuinely different content:
/// - `title` — bucket name / section name / weekday + date.
/// - `trailing` — per-column controls (the section board's complete + overflow buttons).
/// - `detail` — an optional second line (the section board's due-date row).
///
/// `accentRule` replaces the neutral hairline with a coloured one. The Calendar Board's *today*
/// column is the single sanctioned user of it; nothing else should pass a colour here.
struct BoardColumnHeader<Trailing: View, Detail: View>: View {
    private let dotColor: Color
    private let title: String
    private let count: Int
    private let accentRule: Color?
    private let trailing: () -> Trailing
    private let detail: () -> Detail

    init(
        dotColor: Color,
        title: String,
        count: Int,
        accentRule: Color? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.dotColor = dotColor
        self.title = title
        self.count = count
        self.accentRule = accentRule
        self.trailing = trailing
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                KanbanColumnTitleRow(dotColor: dotColor, title: title, count: count, trailing: trailing)
                detail()
            }
            .kanbanColumnHeaderPadding()

            rule
        }
    }

    @ViewBuilder
    private var rule: some View {
        if let accentRule {
            // Same 1pt hairline slot as every other column — it just carries colour, so the
            // exception costs no layout difference.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accentRule.opacity(0.85), accentRule.opacity(0.45), accentRule.opacity(0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        } else {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }
}

extension BoardColumnHeader where Detail == EmptyView {
    init(
        dotColor: Color,
        title: String,
        count: Int,
        accentRule: Color? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            dotColor: dotColor,
            title: title,
            count: count,
            accentRule: accentRule,
            trailing: trailing,
            detail: { EmptyView() }
        )
    }
}

extension BoardColumnHeader where Trailing == EmptyView, Detail == EmptyView {
    init(dotColor: Color, title: String, count: Int, accentRule: Color? = nil) {
        self.init(
            dotColor: dotColor,
            title: title,
            count: count,
            accentRule: accentRule,
            trailing: { EmptyView() },
            detail: { EmptyView() }
        )
    }
}

/// The column is containerless at rest: no fill, no stroke. This layer only supplies a
/// transparent-but-hit-testable region plus the *transient* drag-over wash, so a wall of
/// columns never reads as a wall of color. Without it the drop destination, the section-reorder
/// `.onDrag`, and the column hover state would only register on top of actual glyphs.
///
/// `overlay` is for board-specific transient state on top of the wash (the section board layers
/// its pending-completion sweep there).
struct KanbanColumnDropSurface<Overlay: View>: View {
    let tint: Color
    let isTargeted: Bool
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack {
            Color.clear

            if isTargeted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .fill(tint.opacity(kanbanColumnDropFillOpacity))
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .strokeBorder(
                        tint.opacity(kanbanColumnDropStrokeOpacity),
                        style: StrokeStyle(lineWidth: 1, dash: kanbanColumnDropDash)
                    )
            }

            overlay()
        }
        .contentShape(Rectangle())
        .animation(kanbanColumnDropAnimation, value: isTargeted)
    }
}

/// Fixed width + transparent drop surface + full-column hit shape. The outer `contentShape`
/// is what guarantees the whole 236pt column — not just its glyphs — is a drop target.
struct KanbanColumnChrome<SurfaceOverlay: View>: ViewModifier {
    let tint: Color
    let isTargeted: Bool
    @ViewBuilder let surfaceOverlay: () -> SurfaceOverlay

    func body(content: Content) -> some View {
        content
            .frame(width: kanbanColumnWidth)
            .background(
                KanbanColumnDropSurface(tint: tint, isTargeted: isTargeted, overlay: surfaceOverlay)
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func kanbanColumnChrome<SurfaceOverlay: View>(
        tint: Color,
        isTargeted: Bool,
        @ViewBuilder surfaceOverlay: @escaping () -> SurfaceOverlay
    ) -> some View {
        modifier(KanbanColumnChrome(tint: tint, isTargeted: isTargeted, surfaceOverlay: surfaceOverlay))
    }

    func kanbanColumnChrome(tint: Color, isTargeted: Bool) -> some View {
        modifier(KanbanColumnChrome(tint: tint, isTargeted: isTargeted) { EmptyView() })
    }

    /// Padding shared by both boards' column header blocks.
    func kanbanColumnHeaderPadding() -> some View {
        padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 8)
    }
}

/// The scrolling card stack for a column. The `minHeight` and the inner/outer `contentShape`s
/// are what keep the empty space under the last card — and an entirely empty column — a live
/// drop target now that the column paints nothing. Bundling the add-task row in here makes that
/// structural instead of something each board has to remember.
struct KanbanColumnScroll<Content: View>: View {
    let isColumnHovered: Bool
    /// `nil` drops the add-task row. The Calendar Board's Overdue rail is the only caller that
    /// passes it: overdue is a derived state, so "add a task here" has no meaning — the same
    /// reason the rail refuses drops.
    let onAddTask: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                content()
                // Replaces the old header "+" chip; always genuinely last in the column.
                if let onAddTask {
                    KanbanColumnAddTaskRow(isColumnHovered: isColumnHovered, action: onAddTask)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(minHeight: 200)
        .background(
            Color.clear.contentShape(Rectangle())
        )
    }
}

/// The collapsed/expanded "Completed N" row that closes a column's card stack. Shared by the
/// section board and the Calendar Board so a completed pile reads the same on both.
struct KanbanCompletedTasksToggle: View {
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("Completed")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.green.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

/// A card that can be picked up and that accepts a drop *in front of itself*. Used for every
/// card on both boards.
struct KanbanDraggableCard: View {
    let task: AppTask
    var showsDropIndicator: Bool = false
    var onDropTargetedChanged: (Bool) -> Void = { _ in }
    let onDropBefore: ([String]) -> Bool

    var body: some View {
        KanbanCard(task: task)
            .overlay(alignment: .top) {
                if showsDropIndicator {
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(height: 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showsDropIndicator)
            .draggable(task.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                onDropBefore(items)
            } isTargeted: { isOver in
                onDropTargetedChanged(isOver)
            }
    }
}

/// Holds a column's card ordering still while the pointer is over one of its cards, so hover
/// never makes rows resort under the cursor. Both boards install this.
struct KanbanFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenTasks: [AppTask]?
    let columnTaskIDs: Set<UUID>
    let capturedTasks: [AppTask]
    private let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if let newID, columnTaskIDs.contains(newID) {
                    if frozenTasks == nil { frozenTasks = capturedTasks }
                } else if frozenTasks != nil {
                    withAnimation(releaseAnimation) {
                        frozenTasks = nil
                    }
                }
            }
    }
}

// MARK: - Section-board column header

struct KanbanColumnHeader<DueDatePopover: View, EditorPopover: View>: View {
    let section: TaskSectionConfig
    let activeTaskCount: Int
    let columnColor: Color
    let hideColumnDueDateIfEmpty: Bool
    let sectionDueDateIsOverdue: Bool
    let isPendingCompletion: Bool
    let completionProgress: Double
    @Binding var showHeaderDueDatePicker: Bool
    @Binding var showEditor: Bool
    let onToggleCompletion: () -> Void
    let onOpenDueDatePicker: () -> Void
    let onOpenEditor: () -> Void
    let onHoverChanged: (Bool) -> Void
    @ViewBuilder let dueDatePopover: () -> DueDatePopover
    @ViewBuilder let editorPopover: () -> EditorPopover

    /// Column containers are gone, so the header is the only place the section's color
    /// survives — a single 7pt dot. Everything else is neutral, quiet type.
    private var dotColor: Color {
        section.isCompleted || isPendingCompletion ? Theme.green : columnColor
    }

    var body: some View {
        BoardColumnHeader(
            dotColor: dotColor,
            title: section.name,
            count: activeTaskCount,
            trailing: { headerControls },
            detail: { headerDetail }
        )
        .onHover(perform: onHoverChanged)
    }

    @ViewBuilder
    private var headerDetail: some View {
        if !section.dueDate.isEmpty || !hideColumnDueDateIfEmpty {
            dueDateRow
                .padding(.leading, 14)
        }

        if section.isCompleted || isPendingCompletion {
            Text(section.isCompleted ? "Completed" : "Completing…")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.green)
                .padding(.leading, 14)
        }
    }

    @ViewBuilder
    private var headerControls: some View {
        Group {
            Button(action: onToggleCompletion) {
                TaskCompletionProgressGlyph(
                    icon: section.isCompleted ? "checkmark.circle.fill" : "circle",
                    color: section.isCompleted || isPendingCompletion ? Theme.green : Theme.dim,
                    progress: isPendingCompletion ? completionProgress : nil,
                    size: 12,
                    lineWidth: 1.5
                )
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .help(section.isCompleted ? "Mark column active" : "Mark column completed")

            Button(action: onOpenEditor) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .popover(isPresented: $showEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                editorPopover()
            }
        }
    }

    private var dueDateRow: some View {
        Button(action: onOpenDueDatePicker) {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(section.dueDate.isEmpty ? Theme.dim : Theme.red)
                Text(section.dueDate.isEmpty ? "No due date" : DateFormatters.relativeDate(from: section.dueDate))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(sectionDueDateIsOverdue ? Theme.red : Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showHeaderDueDatePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            dueDatePopover()
        }
    }
}

/// Bottom-of-column affordance that replaces the old header "+" button. It is always
/// present — including for empty columns, which otherwise render as nothing now that the
/// column has no container — and routes to the exact same task-creation call.
struct KanbanColumnAddTaskRow: View {
    let isColumnHovered: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add task")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                    .fill(Theme.surface.opacity(isHovered ? 1 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
        .opacity(isColumnHovered || isHovered ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.14), value: isColumnHovered)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct KanbanSectionDueDatePickerPopover: View {
    let dueDateKey: String
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isPresented: Bool
    let onClear: () -> Void

    var body: some View {
        CadenceQuickDatePopover(
            selection: $selection,
            viewMonth: $viewMonth,
            isOpen: $isPresented,
            showsClear: !dueDateKey.isEmpty,
            onClear: onClear
        )
    }
}

struct KanbanSectionEditorPopover: View {
    let section: TaskSectionConfig
    let editorColorOptions: [String]
    @Binding var editorName: String
    @Binding var editorColorHex: String
    @Binding var editorDueDate: Date
    @Binding var editorHasDueDate: Bool
    let onNameChanged: () -> Void
    let onColorSelected: () -> Void
    let onDueDateChanged: () -> Void
    let onClearDate: () -> Void
    let onToggleCompletion: () -> Void
    let onToggleArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.isDefault ? "Default Column" : "Edit Column")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            if section.isDefault {
                Text("Default always stays available and cannot be renamed, archived, or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Column name", text: $editorName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: editorName) { _, _ in onNameChanged() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    ForEach(editorColorOptions, id: \.self) { hex in
                        Button {
                            editorColorHex = hex
                            onColorSelected()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle()
                                        .stroke(editorColorHex == hex ? Theme.text : .clear, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                CadenceDatePicker(
                    selection: $editorDueDate,
                    showsClear: editorHasDueDate,
                    onClear: onClearDate
                )
                    .onChange(of: editorDueDate) { _, _ in
                        editorHasDueDate = true
                        onDueDateChanged()
                    }

                if editorHasDueDate {
                    Button("Clear date", action: onClearDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .buttonStyle(.cadencePlain)
                }
            }

            Divider().background(Theme.borderSubtle)

            Button(action: onToggleCompletion) {
                HStack(spacing: 8) {
                    Image(systemName: section.isCompleted ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(section.isCompleted ? "Mark Section Active" : "Mark Section Completed")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(section.isCompleted ? Theme.blue : Theme.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)

            if !section.isDefault {
                Button(action: onToggleArchive) {
                    HStack(spacing: 8) {
                        Image(systemName: section.isArchived ? "tray.and.arrow.up.fill" : "archivebox.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(section.isArchived ? "Unarchive Column" : "Archive Column")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)

                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Delete Column")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.surface)
    }
}
#endif

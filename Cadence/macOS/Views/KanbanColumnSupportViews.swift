#if os(macOS)
import SwiftUI

// MARK: - Shared column chrome
//
// Everything in this MARK section is used by BOTH kanban column implementations —
// `ListSectionKanbanColumn` (KanbanSectionColumnView.swift) and `TaskListKanbanColumn`
// (KanbanListColumnView.swift). The two boards must look identical; keeping the styling here
// rather than copy-pasted in each column is what makes that structural instead of accidental.
// If you need to change column appearance, change it here — never in one column only.

// The **one** column-header treatment is `CadenceBoardColumnHeader` in
// `Shared/Components/CadenceBoardColumnHeader.swift`, and it is shared with iOS.
//
// `BoardColumnHeader` and `KanbanColumnTitleRow` used to be declared here, beside a
// character-for-character `iOSBoardColumnHeader` in `Cadence/iOS/iOSDesignSystem.swift` that
// differed only in its label size, its count size and a missing 2pt of top padding. This file's
// own banner comment above — "the two boards must look identical; keeping the styling here rather
// than copy-pasted in each column is what makes that structural instead of accidental" — was true
// of the *three macOS boards* and quietly false of the two platforms. The header is in `Shared/`
// now, so it is structural across both.

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

}

/// What a board column's bottom-of-column add row does when it is pressed.
///
/// The split is the whole task-creation rule in one type: a column that already answers "where does
/// this go" composes the card in place, and one that cannot falls back to the full create sheet.
enum KanbanColumnAddBehavior {
    /// Open the inline composer, seeded from this surface. Section and list columns, and board day
    /// columns, all take this path.
    case compose(InlineTaskComposerSurface)
    /// Open the full create sheet. The Calendar Board's Unscheduled rail is the one caller: a
    /// backlog has no date and no list to seed, so there is nothing for a composer to pre-fill.
    case presentSheet(() -> Void)

    /// Whether pressing this column's add affordance opens the *inline composer*, which is also the
    /// question "does Cmd+N over this column do anything". A column that answers `true` registers
    /// with `HoveredKanbanColumnManager`; one that answers `false` deliberately does not, so the
    /// shortcut documented as "open the inline composer in the hovered column" never resolves to a
    /// modal create sheet under the pointer.
    var opensInlineComposer: Bool {
        if case .compose = self { return true }
        return false
    }
}

extension Optional where Wrapped == KanbanColumnAddBehavior {
    /// `nil` is a column with no add affordance at all (the Overdue rail), so there is nothing for
    /// Cmd+N to open there either.
    var opensInlineComposer: Bool { self?.opensInlineComposer ?? false }
}

/// The scrolling card stack for a column. The `minHeight` and the inner/outer `contentShape`s
/// are what keep the empty space under the last card — and an entirely empty column — a live
/// drop target now that the column paints nothing. Bundling the add-task row — and the composer
/// that replaces it — in here makes their placement structural instead of something each board has
/// to remember.
struct KanbanColumnScroll<Content: View>: View {
    let isColumnHovered: Bool
    /// `nil` drops the add-task row entirely. The Calendar Board's Overdue rail is the only caller
    /// that passes it: overdue is a derived state, so "add a task here" has no meaning — the same
    /// reason the rail refuses drops.
    let add: KanbanColumnAddBehavior?
    /// Owned by the column rather than by this view so a column can open its composer from
    /// somewhere other than the add row — Cmd+N on the hovered kanban column does exactly that.
    /// Columns whose `add` is not `.compose` never read it.
    var isComposing: Binding<Bool> = .constant(false)
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                content()
                // Replaces the old header "+" chip; always genuinely last in the column. The
                // composer takes the same slot, so the row it grew out of does not shift.
                if case .compose(let surface) = add, isComposing.wrappedValue {
                    InlineTaskComposer(surface: surface) {
                        isComposing.wrappedValue = false
                    }
                } else if let add {
                    KanbanColumnAddTaskRow(isColumnHovered: isColumnHovered) {
                        switch add {
                        case .compose:
                            isComposing.wrappedValue = true
                        case .presentSheet(let present):
                            present()
                        }
                    }
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
        CadenceBoardColumnHeader(
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
            // Not offered on Default, for the same reason Archive is not (T-268): the model
            // refuses the flag and the settle underneath the button does not. See
            // `TaskSectionConfig.supportsLifecycle`.
            if section.supportsLifecycle {
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
            }

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
/// column has no container. Pressing it opens whatever `KanbanColumnAddBehavior` the column
/// declared: the inline composer for columns that know where the card goes, the create sheet
/// otherwise.
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
                Text("Default always stays available and cannot be renamed, completed, archived, or deleted.")
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
                                        .stroke(
                                            CadenceColorPalette.matches(hex, editorColorHex) ? Theme.text : .clear,
                                            lineWidth: 1.5
                                        )
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

            // **Everything below the rule is a lifecycle action, and Default has no lifecycle.**
            // Completion sat outside this gate for as long as Archive sat inside it, which read
            // as a deliberate asymmetry and was not (T-268): `normalizedSectionConfigs` discards
            // both flags on Default, and completion was the one of the two that settled the
            // column's open tasks on the way out. The divider comes inside with them — a rule
            // with nothing under it is a control the user goes looking for.
            if section.supportsLifecycle {
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

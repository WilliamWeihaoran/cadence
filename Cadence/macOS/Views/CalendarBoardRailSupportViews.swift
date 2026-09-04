#if os(macOS)
import SwiftUI

/// One of the two rails pinned either side of the Calendar Board's day columns.
///
/// Structurally this is a day column: the same `CadenceBoardColumnHeader`, the same `KanbanColumnScroll`,
/// the same `KanbanCard`. The one deliberate difference is the plate. Day columns sit straight on
/// the board canvas (`Theme.bg`); a rail sits on `Theme.surfaceRecessed`, because a rail is an
/// *inbox* — Overdue and Unscheduled are not dates, and must not read as though they were. The
/// recess is also what tells the eye these two columns are pinned while the days scroll past them.
///
/// **`form` is a reduction, not a fork** (T-251). The plate, the insets, the closing hairline, the
/// drop destination and the accessibility label are the same in both forms and are applied once, to
/// the whole column; only what is inside changes. That is what keeps a collapsed rail a working
/// drop target for the drag it exists to receive.
struct CalendarBoardRailColumn: View {
    let rail: CalendarBoardRail
    let tasks: [AppTask]
    /// `nil` on the Overdue rail — see `KanbanColumnScroll.add`. The Unscheduled rail passes
    /// `.presentSheet`: a backlog has neither a day nor a list, so there is nothing for the inline
    /// composer the day columns use to pre-fill.
    let add: KanbanColumnAddBehavior?
    /// Full inbox column, or the identity strip the board falls back to when the pane cannot pay
    /// for two of them and a whole day column. See `CadenceCalendarBoardLayout`.
    var form: CadenceCalendarBoardRailForm = .expanded
    /// `nil` above `CadenceCalendarBoardLayout.expandedRailsMinimumWidth`, where the form is not the
    /// user's to change. Below it this both expands a collapsed rail and closes an expanded one, so
    /// there is exactly one control and one piece of state behind the toggle.
    var onToggleForm: (() -> Void)? = nil
    let onDrop: ([String]) -> Bool

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        content
        // Matches `CalendarBoardDayColumn`'s insets exactly so the rail header sits on the same
        // baseline as the day headers even though the rail is narrower.
        .padding(.horizontal, CadenceCalendarBoardLayout.railHorizontalPadding)
        .padding(.vertical, 10)
        .frame(width: CadenceCalendarBoardLayout.railWidth(form: form))
        .frame(maxHeight: .infinity, alignment: .top)
        .onHover { isHovered = $0 }
        .background(Theme.surfaceRecessed)
        .overlay(alignment: rail == .overdue ? .trailing : .leading) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius, style: .continuous)
                    .strokeBorder(
                        rail.dotColor.opacity(kanbanColumnDropStrokeOpacity),
                        style: StrokeStyle(lineWidth: 1, dash: kanbanColumnDropDash)
                    )
                    .padding(2)
            }
        }
        .animation(kanbanColumnDropAnimation, value: isDropTargeted)
        .contentShape(Rectangle())
        .modifier(CalendarBoardRailDropModifier(
            rail: rail,
            onDrop: onDrop,
            onTargetChange: { isDropTargeted = $0 }
        ))
        .accessibilityLabel("\(rail.label.capitalized), \(tasks.count) task\(tasks.count == 1 ? "" : "s")")
    }

    @ViewBuilder
    private var content: some View {
        switch form {
        case .expanded:  expandedContent
        case .collapsed: collapsedContent
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            CadenceBoardColumnHeader(dotColor: rail.dotColor, title: rail.label, count: tasks.count) {
                // The shared header's own trailing slot — the same one the section board puts its
                // completion and overflow buttons in. A second chrome layer for one chevron is
                // exactly the near-copy the board components exist to avoid.
                if let onToggleForm {
                    Button(action: onToggleForm) {
                        Image(systemName: rail == .overdue ? "chevron.left" : "chevron.right")
                            .font(.system(size: CadenceBoardColumnHeaderMetrics.labelSize, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(CadenceHoverHighlight(cornerRadius: 5))
                    .cadenceControlLabel("Collapse \(rail.label.capitalized)")
                }
            }

            KanbanColumnScroll(isColumnHovered: isHovered, add: add) {
                ForEach(tasks) { task in
                    KanbanCard(task: task, showsContainerChip: true)
                        .draggable(TaskDragPayload.string(for: task.id))
                }
            }
        }
    }

    /// The rail reduced to what identifies it — dot, count, name — and nothing else. It stays a drop
    /// target because the drop modifier is applied to the column rather than to this content, so
    /// dragging a card out of a day column onto Unscheduled works collapsed exactly as expanded.
    private var collapsedContent: some View {
        Button {
            onToggleForm?()
        } label: {
            VStack(spacing: 9) {
                Circle()
                    .fill(rail.dotColor)
                    .frame(
                        width: CadenceBoardColumnHeaderMetrics.dotSize,
                        height: CadenceBoardColumnHeaderMetrics.dotSize
                    )

                Text("\(tasks.count)")
                    .font(.system(size: CadenceBoardColumnHeaderMetrics.countSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)

                // Rotation is a render transform and leaves layout bounds alone, so the slot is
                // stated rather than measured — see `collapsedRailLabelSlotHeight`. The rotated
                // footprint swaps the label's two dimensions: the slot's width is the text's line
                // height, not its font's point size (T-729), and its height is the text's own width,
                // bounded by `collapsedRailLabelSlotHeight`.
                Text(rail.label)
                    .font(.system(size: CadenceBoardColumnHeaderMetrics.labelSize, weight: .semibold))
                    .kerning(CadenceBoardColumnHeaderMetrics.labelKerning)
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(
                        width: CadenceBoardColumnHeaderMetrics.labelLineHeight,
                        height: CadenceCalendarBoardLayout.collapsedRailLabelSlotHeight
                    )

                Spacer(minLength: 0)
            }
            .padding(.top, CadenceBoardColumnHeaderMetrics.topPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(CadenceHoverHighlight(cornerRadius: kanbanColumnCornerRadius))
        .accessibilityLabel("Expand \(rail.label.capitalized)")
        .accessibilityValue("\(tasks.count) task\(tasks.count == 1 ? "" : "s")")
        .help("\(rail.label.capitalized) — \(tasks.count) task\(tasks.count == 1 ? "" : "s"). Click to expand.")
    }
}

/// Installs the drop destination only on rails that accept one. Overdue is a derived state —
/// dropping a task "into overdue" would mean backdating it — so it never becomes a drop target
/// rather than accepting a drop and silently no-oping.
private struct CalendarBoardRailDropModifier: ViewModifier {
    let rail: CalendarBoardRail
    let onDrop: ([String]) -> Bool
    let onTargetChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if rail.acceptsDrops {
            content
                .dropDestination(for: String.self) { items, _ in
                    onDrop(items)
                } isTargeted: { isTargeted in
                    onTargetChange(isTargeted)
                }
        } else {
            content
        }
    }
}
#endif

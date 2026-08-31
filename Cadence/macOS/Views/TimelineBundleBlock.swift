#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TimelineBundleBlock: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedBundleID: UUID?
    @Binding var activeDragBundleID: UUID?
    let onTaskDropped: (AppTask, TaskBundle) -> Void
    let onSelect: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var resizeSession: TimelineResizeSession? = nil
    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin)
    }

    var body: some View {
        bundleBlockBody
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    hoveredEditableManager.beginHovering(id: "timeline-bundle-\(bundle.id.uuidString)") {
                        onSelect()
                        activeDragBundleID = nil
                        selectedBundleID = bundle.id
                    } onDelete: {
                        deleteConfirmationManager.present(
                            title: "Delete Bundle?",
                            message: "This will delete \"\(bundle.displayTitle)\" and keep its tasks on the same day."
                        ) {
                            if selectedBundleID == bundle.id {
                                selectedBundleID = nil
                            }
                            if activeDragBundleID == bundle.id {
                                activeDragBundleID = nil
                            }
                            SchedulingActions.deleteBundle(bundle, in: modelContext)
                        }
                    }
                } else {
                    hoveredEditableManager.endHovering(id: "timeline-bundle-\(bundle.id.uuidString)")
                }
            }
            .onTapGesture {
                handleBlockTap()
            }
            .onDrag {
                selectedBundleID = nil
                activeDragBundleID = bundle.id
                return NSItemProvider(object: TaskDragPayload.bundleString(for: bundle.id) as NSString)
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(
                of: [UTType.text.identifier],
                delegate: TimelineBundleDropDelegate(
                    bundle: bundle,
                    allTasks: allTasks,
                    onTaskDropped: onTaskDropped,
                    isTargeted: $isDropTargeted
                )
            )
            .overlay(alignment: .top) {
                resizeHandle(edge: .start)
            }
            .overlay(alignment: .bottom) {
                resizeHandle(edge: .end)
            }
            .popover(
                isPresented: Binding(
                    get: { selectedBundleID == bundle.id },
                    set: { if !$0 && selectedBundleID == bundle.id { selectedBundleID = nil } }
                )
            ) {
                TaskBundleDetailPopover(
                    bundle: bundle,
                    allTasks: allTasks,
                    areas: areas,
                    projects: projects,
                    onFocus: {
                        focusManager.startFocus(bundle: bundle)
                        selectedBundleID = nil
                    },
                    onAddTask: { task in
                        SchedulingActions.addTask(task, to: bundle)
                    },
                    onRemoveTask: { task in
                        SchedulingActions.removeTaskFromBundle(task)
                    },
                    onMoveTask: { task, direction in
                        SchedulingActions.moveTaskInBundle(task, direction: direction)
                    },
                    onComplete: {
                        if focusManager.activeBundle?.id == bundle.id {
                            focusManager.reset()
                            focusManager.activeSession = nil
                        }
                        SchedulingActions.completeBundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    },
                    onUnbundle: {
                        SchedulingActions.unbundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    },
                    onDelete: {
                        SchedulingActions.deleteBundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    }
                )
            }
            .position(x: frame.centerX, y: frame.centerY)
    }

    /// Bundle-complete mirrors a single task's "done" look: once every member task is
    /// checked off, the whole block should read as done rather than as a distinct state.
    private var isBundleComplete: Bool {
        let members = bundle.sortedTasks
        return !members.isEmpty && members.allSatisfy(\.isDone)
    }

    private var bundleAccent: Color {
        isBundleComplete ? Theme.green : Theme.amber
    }

    private var bundleIcon: String {
        isBundleComplete ? "checkmark.circle.fill" : "square.stack"
    }

    /// The deadline the block reports on its own title line: the earliest due date among members
    /// that are still open. Keys are `yyyy-MM-dd`, so the lexical minimum is the earliest date and
    /// therefore the most urgent. A finished member's deadline is settled and never sets the tone,
    /// and members folded into "+N more" — or hidden entirely on a short block — are still counted,
    /// which is the whole point: the per-member flags only ever cover the first two rows.
    private var mostUrgentMemberDueDateKey: String? {
        bundle.sortedTasks
            .filter { !$0.isDone && !$0.dueDate.isEmpty }
            .map(\.dueDate)
            .min()
    }

    private var bundleBlockBody: some View {
        let memberCount = bundle.sortedTasks.count
        let accent = bundleAccent
        let todayKey = DateFormatters.todayKey()
        let urgentDueKey = mostUrgentMemberDueDateKey
        let dueLabel = urgentDueKey.flatMap {
            CadenceFocusSupport.dueLabel(forDueDateKey: $0, todayKey: todayKey)
        }
        let dueTint = urgentDueKey
            .flatMap { CadenceDueUrgency.evaluate(dueDateKey: $0, todayKey: todayKey) }?
            .tint ?? Theme.dim
        return HStack(alignment: .top, spacing: 0) {
            accent
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: style.cornerRadius,
                    bottomLeadingRadius: style.cornerRadius
                ))

            VStack(alignment: .leading, spacing: 3) {
                if frame.height >= 54 {
                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }

                // The title line is the one thing every tier draws, so the block's deadline rides
                // along here rather than with the member rows the short tiers drop. The block is
                // hard-clipped, so the due text takes layout priority and the title truncates
                // first: a deadline is a commitment, a bundle name is a label. The title also
                // gives up its second line while sharing the row — a wrapped line here would be
                // clipped away rather than shown.
                HStack(spacing: 5) {
                    Image(systemName: bundleIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(bundle.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isBundleComplete ? Theme.dim : Theme.text)
                        .strikethrough(isBundleComplete, color: Theme.dim)
                        .lineLimit(dueLabel == nil && frame.height >= 42 ? 2 : 1)
                    if let dueLabel {
                        Spacer(minLength: 0)
                        Text(dueLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(dueTint)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if frame.height >= 58 {
                    ForEach(Array(bundle.sortedTasks.prefix(2)), id: \.id) { member in
                        let memberDue = CadenceDueUrgency.evaluate(dueDateKey: member.dueDate, isDone: member.isDone)
                        let memberDueLabel = CadenceFocusSupport.dueLabel(
                            forDueDateKey: member.dueDate,
                            todayKey: DateFormatters.todayKey()
                        ) ?? ""
                        // One expression for the drawn name and the announced one. A label may not
                        // spell its own empty-title fallback (T-590) — and the ternary this
                        // replaces also drew a whitespace-only title as a blank line, which
                        // `displayTitle` trims first.
                        let memberTitle = TaskTitleSupport.displayTitle(
                            member.title,
                            fallback: TaskTitleSupport.defaultCompactDisplayTitle
                        )
                        HStack(spacing: 5) {
                            Circle()
                                .strokeBorder(member.isDone ? Color.clear : Theme.dim, lineWidth: 1)
                                .background(Circle().fill(member.isDone ? accent : Color.clear))
                                .frame(width: 6, height: 6)
                            Text(memberTitle)
                                .font(.system(size: 9))
                                .foregroundStyle(member.isDone ? Theme.dim : Theme.muted)
                                .strikethrough(member.isDone, color: Theme.dim)
                                .lineLimit(1)
                            if let memberDue {
                                // A member row is only ~9pt tall inside a clipped block, so the day
                                // itself cannot fit here; the flag ranks the deadline and the row's
                                // tooltip carries the actual date.
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(memberDue.tint)
                            }
                        }
                        .accessibilityLabel(memberTitle)
                        .accessibilityValue(memberDueLabel)
                        .help(memberDueLabel)
                    }
                    if memberCount > 2 {
                        Text("+\(memberCount - 2) more")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.dim)
                    }
                } else if frame.height >= 42 {
                    Text("\(memberCount) task\(memberCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)

            Spacer(minLength: 0)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: style.cornerRadius).fill(accent.opacity(0.16))
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: style.cornerRadius).fill(accent.opacity(0.16))
                }
                if isHovered {
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .fill(TimelineHoverVisuals.hoverFill(tint: accent, isHovered: isHovered, opacity: 0.08))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    selectedBundleID == bundle.id || isDropTargeted
                        ? accent.opacity(0.62)
                        : TimelineHoverVisuals.borderColor(
                            tint: accent,
                            isSelected: false,
                            isHovered: isHovered,
                            selectedOpacity: 0.62,
                            hoverOpacity: 0.34
                        ),
                    lineWidth: isHovered || isDropTargeted ? 1.2 : 1
                )
        )
        .shadow(
            color: TimelineHoverVisuals.shadowColor(isActive: isHovered || selectedBundleID == bundle.id),
            radius: TimelineHoverVisuals.shadowRadius(isActive: isHovered || selectedBundleID == bundle.id),
            y: TimelineHoverVisuals.shadowY(isActive: isHovered || selectedBundleID == bundle.id)
        )
        .opacity(isBundleComplete ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        let handleHeight = TimelineBlockGeometry.resizeHandleHeight(blockHeight: frame.height)
        if handleHeight > 0 {
            Rectangle()
                .fill(Color.clear)
                .frame(height: handleHeight)
                .contentShape(Rectangle())
                .overlay {
                    let emphasized = resizeSession?.edge == edge || isHovered || selectedBundleID == bundle.id
                    Capsule()
                        .fill(emphasized ? Theme.onColorHandleActive : Theme.onColorHandle)
                        .frame(width: TimelineBlockGeometry.handleCapsuleWidth(blockWidth: frame.width), height: 2)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            guard TimelineBlockGeometry.isResizeDrag(translation: value.translation) else { return }
                            beginResizeIfNeeded(edge: edge, localY: value.startLocation.y)
                            updateResize(localY: value.location.y)
                        }
                        .onEnded { value in
                            guard resizeSession != nil else {
                                handleBlockTap()
                                return
                            }
                            updateResize(localY: value.location.y)
                            resizeSession = nil
                        }
                )
        }
    }

    private func handleBlockTap() {
        onSelect()
        activeDragBundleID = nil
        selectedBundleID = bundle.id
    }

    private func beginResizeIfNeeded(edge: TimelineResizeEdge, localY: CGFloat) {
        guard resizeSession == nil else { return }
        onSelect()
        selectedBundleID = nil
        activeDragBundleID = nil
        resizeSession = TimelineResizeSession.begin(
            edge: edge,
            localY: localY,
            blockTopY: frame.y,
            blockDrawnHeight: frame.height,
            originStartMin: bundle.startMin,
            originEndMin: bundle.endMin,
            metrics: metrics
        )
    }

    private func updateResize(localY: CGFloat) {
        guard let resizeSession else { return }
        let range = metrics.resizedRange(
            session: resizeSession,
            localY: localY,
            blockTopY: frame.y,
            blockDrawnHeight: frame.height
        )
        SchedulingActions.updateBundleTime(bundle, startMin: range.start, endMin: range.end)
    }
}

private struct TimelineBundleDropDelegate: DropDelegate {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let onTaskDropped: (AppTask, TaskBundle) -> Void
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let taskID = TaskDragPayload.taskID(from: payload as String) else { return }
            Task { @MainActor in
                guard let task = allTasks.first(where: { $0.id == taskID }) else { return }
                guard task.bundle?.id != bundle.id else {
                    SchedulingActions.addTask(task, to: bundle)
                    return
                }
                onTaskDropped(task, bundle)
            }
        }
        return true
    }
}

#endif

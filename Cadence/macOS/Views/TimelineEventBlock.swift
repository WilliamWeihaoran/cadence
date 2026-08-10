#if os(macOS)
import SwiftUI
import AppKit
import EventKit
import SwiftData

// MARK: - Timeline Event Block

struct TimelineEventBlock: View {
    private enum ResizeEdge { case start, end }
    private enum PendingEventMutation {
        case move(startMin: Int)
        case resize(startMin: Int, durationMinutes: Int)
        case delete
    }

    let item: CalendarEventItem
    let layout: TimelineEventLayout
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedEventID: String?
    @Binding var selectedTaskID: UUID?

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    // Live drag/resize state — cleared when the item refreshes from iCal
    @State private var liveStartMin: Int? = nil
    @State private var liveDurationMinutes: Int? = nil
    @State private var dragGrabOffset: CGFloat = 0
    @State private var activeResizeEdge: ResizeEdge? = nil
    @State private var resizeOriginStartMin: Int? = nil
    @State private var resizeOriginEndMin: Int? = nil
    @State private var isHovered = false
    @State private var pendingMutation: PendingEventMutation?

    private let resizeHandleHeight: CGFloat = 8

    private var effectiveStartMin: Int  { liveStartMin      ?? item.startMin       }
    private var effectiveDuration: Int  { liveDurationMinutes ?? item.durationMinutes }

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: effectiveStartMin,
            durationMinutes: effectiveDuration,
            column: layout.column,
            totalColumns: layout.totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var isSelected: Bool { selectedEventID == item.id }

    var body: some View {
        eventBlockBody
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    hoveredEditableManager.beginHovering(id: "timeline-event-\(item.id)") {
                        selectedTaskID = nil
                        selectedEventID = item.id
                    } onDelete: {
                        deleteConfirmationManager.present(
                            title: "Delete Calendar Event?",
                            message: "This will permanently delete \"\(item.title)\" from your calendar."
                        ) {
                            requestEventMutation(.delete)
                        }
                    }
                } else {
                    hoveredEditableManager.endHovering(id: "timeline-event-\(item.id)")
                }
            }
            .onTapGesture {
                guard liveStartMin == nil else { return }   // ignore tap during drag
                selectedTaskID = nil
                selectedEventID = isSelected ? nil : item.id
            }
            // MARK: Move gesture — uses named canvas coordinate space so drag speed
            // is 1:1 with cursor even as the block repositions during the gesture.
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("timelineCanvas"))
                    .onChanged { value in
                        guard activeResizeEdge == nil else { return }
                        selectedEventID = nil
                        if liveStartMin == nil {
                            // Record where in the block the user grabbed it
                            dragGrabOffset = value.startLocation.y - metrics.yOffset(for: item.startMin)
                        }
                        let eventTopY = value.location.y - dragGrabOffset
                        liveStartMin = metrics.snappedMinute(fromY: max(0, eventTopY))
                    }
                    .onEnded { _ in
                        guard activeResizeEdge == nil else { return }
                        if let newStart = liveStartMin {
                            requestEventMutation(.move(startMin: newStart))
                            // Keep liveStartMin set until item refreshes from iCal (onChange clears it)
                        }
                        dragGrabOffset = 0
                    }
            )
            // MARK: Resize handles
            .overlay(alignment: .top)    { resizeHandle(edge: .start) }
            .overlay(alignment: .bottom) { resizeHandle(edge: .end)   }
            // MARK: Detail popover
            .popover(
                isPresented: Binding(
                    get: { isSelected },
                    set: { if !$0 && selectedEventID == item.id { selectedEventID = nil } }
                )
            ) {
                CalendarEventEditPopover(
                    item: item,
                    onSave: { title, startMin, duration, calendarID, scope in
                        if let range = item.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration) {
                            calendarManager.updateEvent(
                                item.ekEvent,
                                title: title,
                                startDate: range.start,
                                endDate: range.end,
                                calendarID: calendarID,
                                scope: scope
                            )
                        }
                        selectedEventID = nil
                    },
                    onDelete: { scope in
                        deleteConfirmationManager.present(
                            title: "Delete Calendar Event?",
                            message: "This will permanently delete \"\(item.title)\" from your calendar."
                        ) {
                            calendarManager.deleteEvent(item.ekEvent, scope: scope)
                            selectedEventID = nil
                        }
                    }
                )
            }
            .position(x: frame.centerX, y: frame.centerY)
            // Clear live state once the item refreshes from iCal
            .onChange(of: item.startMin) {
                liveStartMin = nil
                liveDurationMinutes = nil
                dragGrabOffset = 0
            }
            .confirmationDialog(
                "Change recurring event?",
                isPresented: Binding(
                    get: { pendingMutation != nil },
                    set: { if !$0 { cancelPendingEventMutation() } }
                ),
                titleVisibility: .visible
            ) {
                Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                    applyPendingEventMutation(scope: .thisOccurrence)
                }
                Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                    applyPendingEventMutation(scope: .futureOccurrences)
                }
                Button("Cancel", role: .cancel) {
                    cancelPendingEventMutation()
                }
            } message: {
                Text("Choose whether this calendar change applies only to this occurrence or to this and future events.")
            }
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay {
                let isEmphasized = activeResizeEdge == edge || isHovered || isSelected
                Capsule()
                    .fill(isEmphasized ? Theme.onColorHandleActive : Theme.onColorHandle)
                    .frame(width: min(18, max(10, frame.width - 18)), height: 2)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        beginResizeIfNeeded(edge: edge)
                        updateResize(edge: edge, localY: value.location.y)
                    }
                    .onEnded { value in
                        updateResize(edge: edge, localY: value.location.y)
                        endResize()
                    }
            )
    }

    private func beginResizeIfNeeded(edge: ResizeEdge) {
        guard activeResizeEdge == nil else { return }
        selectedEventID = nil
        activeResizeEdge = edge
        resizeOriginStartMin = effectiveStartMin
        resizeOriginEndMin   = effectiveStartMin + max(effectiveDuration, 5)
    }

    private func updateResize(edge: ResizeEdge, localY: CGFloat) {
        guard let originStart = resizeOriginStartMin,
              let originEnd   = resizeOriginEndMin else { return }
        let localYOffset: CGFloat
        switch edge {
        case .start: localYOffset = localY
        case .end:   localYOffset = max(0, frame.height - resizeHandleHeight) + localY
        }
        let snapped = metrics.snappedMinute(fromY: frame.y + localYOffset)
        switch edge {
        case .start:
            let nextStart = min(snapped, originEnd - 5)
            liveStartMin        = nextStart
            liveDurationMinutes = max(5, originEnd - nextStart)
        case .end:
            let nextEnd = max(snapped, originStart + 5)
            liveStartMin        = originStart
            liveDurationMinutes = max(5, nextEnd - originStart)
        }
    }

    private func endResize() {
        let finalStart    = liveStartMin        ?? effectiveStartMin
        let finalDuration = liveDurationMinutes ?? effectiveDuration
        requestEventMutation(.resize(startMin: finalStart, durationMinutes: finalDuration))
        // Keep live state until item refreshes (onChange clears it)
        activeResizeEdge    = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin   = nil
    }

    private func requestEventMutation(_ mutation: PendingEventMutation) {
        if item.isRecurringSeriesMember {
            pendingMutation = mutation
        } else {
            applyEventMutation(mutation, scope: .thisOccurrence)
        }
    }

    private func applyPendingEventMutation(scope: CalendarRecurrenceEditScope) {
        guard let pendingMutation else { return }
        self.pendingMutation = nil
        applyEventMutation(pendingMutation, scope: scope)
    }

    private func cancelPendingEventMutation() {
        pendingMutation = nil
        liveStartMin = nil
        liveDurationMinutes = nil
        dragGrabOffset = 0
        activeResizeEdge = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin = nil
    }

    private func applyEventMutation(_ mutation: PendingEventMutation, scope: CalendarRecurrenceEditScope) {
        switch mutation {
        case .move(let startMin):
            updateEventRange(item.eventDateRangeForMovedSegment(startMin: startMin), scope: scope)
        case .resize(let startMin, let durationMinutes):
            updateEventRange(
                item.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: durationMinutes),
                scope: scope
            )
        case .delete:
            deleteConfirmationManager.present(
                title: "Delete Calendar Event?",
                message: scope == .futureOccurrences
                    ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                    : "This will permanently delete \"\(item.title)\" from your calendar."
            ) {
                calendarManager.deleteEvent(item.ekEvent, scope: scope)
            }
        }
    }

    private func updateEventRange(_ range: (start: Date, end: Date)?, scope: CalendarRecurrenceEditScope) {
        guard let range else {
            cancelPendingEventMutation()
            return
        }
        calendarManager.updateEvent(
            item.ekEvent,
            title: item.title,
            startDate: range.start,
            endDate: range.end,
            scope: scope
        )
    }

    // MARK: - Block Body

    private var eventBlockBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            if frame.height >= 36 {
                Text(timeRangeLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondaryLabelColor)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondaryLabelColor)
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CalendarEventVisualStyle.primaryLabelColor)
                    .lineLimit(2)
                if item.isRecurringSeriesMember {
                    Image(systemName: "repeat")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CalendarEventVisualStyle.tertiaryLabelColor(isSelected: isSelected, isHovered: isHovered))
                }
            }
            if frame.height >= 54 && !item.calendarTitle.isEmpty {
                Text(item.calendarTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(secondaryLabelColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        // Hover and selection are carried by the fill's own luminance ladder, not by a white wash
        // stacked on top of it. A wash was the wrong lever here: it lifts the block by draining
        // the hue it is supposed to be showing, which is half of why these blocks read as washed
        // out. `CalendarEventVisualStyle.fillLuminance` brightens the calendar's colour instead.
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(CalendarEventVisualStyle.fill(for: item.calendarColor, isSelected: isSelected, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    TimelineHoverVisuals.borderColor(
                        tint: item.calendarColor,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        selectedOpacity: CalendarEventVisualStyle.chipBorderOpacity(isActive: true),
                        hoverOpacity: CalendarEventVisualStyle.chipBorderOpacity(),
                        idleOpacity: 0.12
                    ),
                    lineWidth: isHovered || isSelected ? 1.2 : 1
                )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.onColor.opacity(CalendarEventVisualStyle.blockAccentOpacity(isSelected: isSelected, isHovered: isHovered)))
                .frame(height: isSelected ? 2 : 1)
                .padding(.horizontal, 8)
        }
        .shadow(
            color: TimelineHoverVisuals.shadowColor(isActive: isHovered || isSelected),
            radius: TimelineHoverVisuals.shadowRadius(isActive: isHovered || isSelected, active: 12, idle: 8),
            x: 0,
            y: TimelineHoverVisuals.shadowY(isActive: isHovered || isSelected, active: 5, idle: 3)
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: effectiveStartMin,
                                 endMin: effectiveStartMin + effectiveDuration)
    }

    /// Read three times in the block body, so it is resolved once against the same state the fill
    /// is — the two have to move together or the brighter hover fill eats the label.
    private var secondaryLabelColor: Color {
        CalendarEventVisualStyle.secondaryLabelColor(isSelected: isSelected, isHovered: isHovered)
    }
}
#endif

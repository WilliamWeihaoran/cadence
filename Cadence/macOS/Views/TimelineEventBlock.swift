#if os(macOS)
import SwiftUI
import AppKit
import EventKit
import SwiftData

// MARK: - Timeline Event Block

struct TimelineEventBlock: View {
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
    @State private var isMoveDragActive = false
    @State private var dragGrabOffset: CGFloat = 0
    @State private var resizeSession: TimelineResizeSession? = nil
    @State private var isHovered = false
    @State private var pendingMutation: PendingEventMutation?
    @State private var actionFailureNotice: String?

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
                        // No confirmation here. `requestEventMutation(.delete)` is the single
                        // delete path and it confirms — with a message that knows whether the
                        // recurrence scope makes this one event or all future ones. Confirming
                        // first meant a non-recurring event asked "Delete Calendar Event?" twice
                        // in a row.
                        requestEventMutation(.delete)
                    }
                } else {
                    hoveredEditableManager.endHovering(id: "timeline-event-\(item.id)")
                }
            }
            .onTapGesture {
                handleBlockTap()
            }
            // MARK: Move gesture — uses named canvas coordinate space so drag speed
            // is 1:1 with cursor even as the block repositions during the gesture.
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(TimelineDayCanvas.coordinateSpaceName))
                    .onChanged { value in
                        guard resizeSession == nil else { return }
                        selectedEventID = nil
                        // The grab offset belongs to *this* gesture, so it is recorded when the
                        // gesture starts. It used to be recorded when `liveStartMin == nil`, which
                        // is a different question: live state is deliberately held until EventKit
                        // round-trips, so grabbing the block again before the store notification
                        // arrived (or after a save that failed) reused the previous gesture's
                        // offset and teleported the block on the first pointer move.
                        if !isMoveDragActive {
                            isMoveDragActive = true
                            dragGrabOffset = value.startLocation.y - metrics.yOffset(for: effectiveStartMin)
                        }
                        let eventTopY = value.location.y - dragGrabOffset
                        liveStartMin = metrics.snappedMinute(fromY: max(0, eventTopY))
                    }
                    .onEnded { _ in
                        guard resizeSession == nil else { return }
                        if let newStart = liveStartMin {
                            requestEventMutation(.move(startMin: newStart))
                            // Keep liveStartMin set until item refreshes from iCal (onChange clears it)
                        }
                        isMoveDragActive = false
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
                        // Closing the popover is the only report that Save worked, so a refusal has
                        // to leave it open — the title, notes, calendar and time range the user
                        // typed live in its `@State` and nothing else on screen holds them (T-658).
                        // An unformable range never reached EventKit, so it names no cause.
                        guard let range = item.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration) else {
                            calendarManager.report(
                                .refused(notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)),
                                into: $actionFailureNotice
                            )
                            return
                        }
                        let failure = calendarManager.updateEvent(
                            item.ekEvent,
                            title: title,
                            startDate: range.start,
                            endDate: range.end,
                            calendarID: calendarID,
                            scope: scope
                        )
                        calendarManager.report(
                            CadenceCalendarEventEditingSupport.saveOutcome(for: failure),
                            into: $actionFailureNotice
                        ) { selectedEventID = nil }
                    },
                    onDelete: { scope in
                        // The popover already asked for a scope, so the scope dialog is skipped —
                        // but the delete itself goes through the one confirm-then-delete path
                        // rather than a third copy of it. This copy had already drifted: it
                        // bypassed `requestEventMutation`, so its message never mentioned future
                        // occurrences even when the user had chosen them.
                        //
                        // Delete stays on `.calendarWriteFailureAlert()` while Save moved inline.
                        //
                        // **Measured, not reasoned (T-768).** The line below — not an outside
                        // click on the confirmation overlay — is why an inline notice would have
                        // nowhere to draw: `selectedEventID = nil` closes this popover
                        // synchronously, right here, before `applyEventMutation` even calls
                        // `deleteConfirmationManager.present` to show the overlay. By the time its
                        // Delete button exists on screen, this popover's content view is already
                        // gone. (`CalendarBoardEventCard`'s delete is the one that actually depends
                        // on the overlay's Delete button being a click outside a still-open
                        // popover — see the comment there.) Save has no such step, and a draft to
                        // keep.
                        selectedEventID = nil
                        applyEventMutation(.delete, scope: scope)
                    },
                    actionFailureNotice: $actionFailureNotice
                )
            }
            .position(x: frame.centerX, y: frame.centerY)
            // Clear live state once the item refreshes from iCal.
            //
            // This watched `item.startMin` alone, but a pure end-edge resize leaves the start
            // where it was — so the round-trip fired no change and `liveDurationMinutes` stayed
            // set for the life of the view, pinning the block to its stale local length and
            // ignoring every later edit to the event from Calendar.app, the popover, or a
            // recurrence-scope change. Live state has to be cleared by an observation that fires
            // for every mutation that state could have made.
            .onChange(of: [item.startMin, item.durationMinutes]) {
                liveStartMin = nil
                liveDurationMinutes = nil
                isMoveDragActive = false
                dragGrabOffset = 0
            }
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.eventScopeTitle,
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
                Text(CadenceRecurrenceScopeCopy.eventScopeMessage)
            }
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        let handleHeight = TimelineBlockGeometry.resizeHandleHeight(blockHeight: frame.height)
        if handleHeight > 0 {
            Rectangle()
                .fill(Color.clear)
                .frame(height: handleHeight)
                .contentShape(Rectangle())
                .overlay {
                    let isEmphasized = resizeSession?.edge == edge || isHovered || isSelected
                    Capsule()
                        .fill(isEmphasized ? Theme.onColorHandleActive : Theme.onColorHandle)
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
                            // `endResize` writes back to EventKit unconditionally, and on a
                            // recurring event that raises the "Change recurring event?" dialog. It
                            // used to run for a press that never moved, because `minimumDistance: 0`
                            // guarantees an `onChanged` on mouse-down and that always opened a
                            // session. A click is now a click.
                            guard resizeSession != nil else {
                                handleBlockTap()
                                return
                            }
                            updateResize(localY: value.location.y)
                            endResize()
                        }
                )
        }
    }

    private func handleBlockTap() {
        guard liveStartMin == nil else { return }   // ignore tap during drag
        selectedTaskID = nil
        selectedEventID = isSelected ? nil : item.id
    }

    private func beginResizeIfNeeded(edge: TimelineResizeEdge, localY: CGFloat) {
        guard resizeSession == nil else { return }
        selectedEventID = nil
        resizeSession = TimelineResizeSession.begin(
            edge: edge,
            localY: localY,
            blockTopY: frame.y,
            blockDrawnHeight: frame.height,
            originStartMin: effectiveStartMin,
            originEndMin: effectiveStartMin + max(effectiveDuration, 5),
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
        liveStartMin        = range.start
        liveDurationMinutes = max(5, range.end - range.start)
    }

    private func endResize() {
        let finalStart    = liveStartMin        ?? effectiveStartMin
        let finalDuration = liveDurationMinutes ?? effectiveDuration
        requestEventMutation(.resize(startMin: finalStart, durationMinutes: finalDuration))
        // Keep live state until item refreshes (onChange clears it)
        resizeSession = nil
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
        isMoveDragActive = false
        dragGrabOffset = 0
        resizeSession = nil
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
                .strokeBorder(
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

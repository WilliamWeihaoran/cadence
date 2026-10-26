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
            cascadeDepth: layout.cascadeDepth,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var isSelected: Bool { selectedEventID == item.id }

    /// Read-only calendars (Birthdays, Holidays, subscribed feeds) take no write, so the block
    /// offers no gesture that would ask for one ([[T-5241]]).
    private var isEditable: Bool { CalendarEventEditPopover.isEditable(item.ekEvent) }

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
                        liveStartMin = TimelineEventBlockEditGate.movedStartMinute(
                            topY: value.location.y - dragGrabOffset,
                            durationMinutes: item.durationMinutes,
                            isMultiDayTimedEvent: item.isMultiDayTimedEvent,
                            metrics: metrics
                        )
                    }
                    .onEnded { _ in
                        guard resizeSession == nil else { return }
                        if let newStart = liveStartMin {
                            if TimelineEventBlockEditGate.commitsMove(to: newStart, from: item.startMin) {
                                requestEventMutation(.move(startMin: newStart))
                                // Keep liveStartMin set until item refreshes from iCal (onChange clears it)
                            } else {
                                // Nothing moved, so no refresh is coming to clear the live state.
                                liveStartMin = nil
                            }
                        }
                        isMoveDragActive = false
                        dragGrabOffset = 0
                    },
                // `.subviews` keeps the tap above and the popover working on a read-only event
                // while the move itself is never recognised ([[T-5241]]).
                including: TimelineEventBlockEditGate.allowsMove(isEditable: isEditable) ? .all : .subviews
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
                    onSave: { request, scope in
                        // Closing the popover is the only report that Save worked, so a refusal has
                        // to leave it open — the title, notes, calendar and time range the user
                        // typed live in its `@State` and nothing else on screen holds them (T-658).
                        // An unformable range never reached EventKit, so it names no cause. The
                        // range is the WHOLE event's, from the shared panel's draft ([[T-3171]]),
                        // not this block's segment of it.
                        guard let range = request.range else {
                            calendarManager.report(
                                .refused(notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)),
                                into: $actionFailureNotice
                            )
                            return
                        }
                        let failure = calendarManager.updateEvent(
                            item.ekEvent,
                            title: request.title,
                            startDate: range.start,
                            endDate: range.end,
                            calendarID: request.calendarID,
                            notes: request.notes,
                            scope: scope,
                            isAllDay: request.isAllDay,
                            location: request.location,
                            recurrence: request.recurrence
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
        // A midnight clip of a multi-day event is not an edge it has ([[T-5242]]), and a read-only
        // event has no edge to drag ([[T-5241]]).
        if handleHeight > 0,
           TimelineEventBlockEditGate.drawsResizeHandle(
               edge: edge,
               isEditable: isEditable,
               isFirstSegment: item.isFirstSegment,
               isLastSegment: item.isLastSegment
           ) {
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
            // `presentRefusable` rather than `present` (T-919). EventKit can refuse this — access
            // not granted, a read-only calendar, a store error — and it says which. The popover
            // this block owns is already gone by now (`selectedEventID` was cleared before the
            // confirmation was ever presented), so the overlay is the only surface left that can
            // carry the reason.
            deleteConfirmationManager.presentRefusable(
                title: "Delete Calendar Event?",
                message: scope == .futureOccurrences
                    ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                    : "This will permanently delete \"\(item.title)\" from your calendar."
            ) {
                calendarManager.deleteOutcome(
                    for: calendarManager.deleteEvent(item.ekEvent, scope: scope)
                )
            }
        }
    }

    private func updateEventRange(_ range: (start: Date, end: Date)?, scope: CalendarRecurrenceEditScope) {
        guard let range else {
            cancelPendingEventMutation()
            return
        }
        let failure = calendarManager.updateEvent(
            item.ekEvent,
            title: item.title,
            startDate: range.start,
            endDate: range.end,
            scope: scope
        )
        // A refused write (read-only calendar, revoked access, a conflict) and a write of the
        // range the event already has both leave the item's values unchanged, so the `.onChange`
        // that clears live state never fires and the block would keep drawing the dropped time
        // — and ignore every later click ([[T-5241]]). The refusal itself still reaches the
        // page-root `.calendarWriteFailureAlert()`.
        if TimelineEventBlockEditGate.clearsLiveState(
            after: failure,
            requested: range,
            current: (item.eventStartDate, item.eventEndDate)
        ) {
            cancelPendingEventMutation()
        }
    }

    // MARK: - Block Body

    private var eventBlockBody: some View {
        HStack(alignment: .top, spacing: 0) {
            // **T-3160: the event block wears Apple Calendar's rail treatment.** The leading rail
            // is the identity marker — since [[T-3168]]'s second lever `railColor` carries the
            // calendar's own chroma *whole*, at the brightness that keeps the most of it, while
            // the plate behind it is washed down to a chroma ceiling of 0.12 — and it is
            // *stateless on purpose*: a marker that answers "which calendar
            // is this" must not change colour under the pointer. The state ladder is carried by
            // the plate and the labels, which is why `railColor` takes no `isSelected`/`isActive`.
            //
            // **A plain strip, shaped by the block's clip rather than by its own corners**
            // (T-3167). The rail used to round its own leading corners, but a 3pt-wide shape
            // cannot carry the plate's corner radius — the radii clamp to the strip — so the rail
            // ran the block's full height while the plate's corners curved away from it, leaving
            // ~5pt of bare rail standing proud at the top and bottom. Apple clips its rail to the
            // block's rounded rectangle; so does this, through `.clipShape(blockShape)` below,
            // which is the same construction the iOS event block uses. In a cascade (T-3161) an
            // indented block's rail is drawn **over the body of the block beneath it**, which is
            // what Apple does — and why the rail is an opaque fill rather than a wash, since a
            // translucent one would show the neighbour's hue through the marker that is supposed
            // to name this event's calendar.
            //
            // `CadenceCalendarEventStyle.railWidth`, not a sixth hand-typed `3`.
            Rectangle()
                .fill(railColor)
                .frame(width: CadenceCalendarEventStyle.railWidth)

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
                        .foregroundStyle(
                            CadenceCalendarEventStyle.railTitleColor(
                                for: item.calendarColor,
                                isSelected: isSelected,
                                isActive: isHovered
                            )
                        )
                        // T-3315: a word too wide for the column ends the title in an ellipsis
                        // on one line rather than breaking between characters.
                        .lineLimit(
                            TimelineEventBlockRows.titleLineLimit(
                                for: item.title,
                                availableWidth: TimelineEventBlockRows.titleWidth(
                                    blockWidth: frame.width,
                                    horizontalPadding: style.horizontalPadding,
                                    isRecurring: item.isRecurringSeriesMember
                                )
                            )
                        )
                        .truncationMode(.tail)
                    // The recurrence glyph stays with the event. T-3160 moved paint, not
                    // affordances — this marker and the task's completion circle are what still
                    // say which species a block is where the two treatments come closest.
                    if item.isRecurringSeriesMember {
                        Image(systemName: "repeat")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(
                                CadenceCalendarEventStyle.railTertiaryLabelColor(
                                    for: item.calendarColor,
                                    isSelected: isSelected,
                                    isActive: isHovered
                                )
                            )
                    }
                }
                // T-3166: a block another event is cascaded over drops this row rather than
                // letting it run under the block in front, where only the strip left of that
                // block's indent showed — "Cas" — and read as a glitch. The rail already names the
                // calendar, so the row is the one label a covered block can lose.
                if TimelineEventBlockRows.showsCalendarRow(
                    frameHeight: frame.height,
                    hasCalendarTitle: !item.calendarTitle.isEmpty,
                    uncoveredHeight: TimelineEventBlockRows.uncoveredHeight(
                        startMinute: effectiveStartMin,
                        coveredFromMinute: layout.coveredFromMinute,
                        hourHeight: metrics.hourHeight
                    ),
                    verticalPadding: style.verticalPadding
                ) {
                    Text(item.calendarTitle)
                        .font(.system(size: TimelineEventBlockRows.calendarRowFontSize))
                        .foregroundStyle(secondaryLabelColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        // The block's own shape, not its bounding box: the rail and the labels end where the
        // plate's rounded corners do (T-3167).
        .clipShape(blockShape)
        // Hover and selection are carried by the plate's own luminance ladder, not by a wash
        // stacked on top of it. A wash is the wrong lever here twice over: it lifts the block by
        // draining the hue it is supposed to be showing, and every `rail*` label tier is solved
        // against `railFillLuminance` specifically — so a wash would quietly move the surface the
        // whole AA budget was computed against. `railFill` brightens the calendar's colour instead.
        //
        // **The white accent hairline that used to run across the top went with the swap**
        // (T-3160). It was a bare `Theme.onColor` at 0.18 / 0.34 / 0.48, and over a plate solved
        // to Y = 0.030-0.060 it composites brighter than the rail itself: a second, colourless
        // accent marker competing with the one element that now says which calendar this is.
        .background(
            blockShape
                .fill(
                    CadenceCalendarEventStyle.railFill(
                        for: item.calendarColor,
                        isSelected: isSelected,
                        isActive: isHovered
                    )
                )
        )
        .overlay(
            blockShape
                .strokeBorder(
                    TimelineHoverVisuals.borderColor(
                        tint: railColor,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        selectedOpacity: CadenceCalendarEventStyle.railBorderOpacity(isSelected: true),
                        hoverOpacity: CadenceCalendarEventStyle.railBorderOpacity(isActive: true),
                        // The rail's own colour at rest rather than the white wash this helper
                        // otherwise draws there — see `TimelineHoverVisuals.borderColor`.
                        idleTintOpacity: CadenceCalendarEventStyle.railBorderOpacity()
                    ),
                    lineWidth: isHovered || isSelected ? 1.2 : 1
                )
        )
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

    /// Read three times in the block body, so it is resolved once against the same state the plate
    /// is — the two have to move together or the brighter hover plate eats the label.
    ///
    /// **Narrow by construction, and that is stated rather than hidden**: this tier owes 4.6:1
    /// against a title that owes 5.1:1 on the same plate, about 3.2 L* apart, so it reads as a
    /// dimmer line of the same colour rather than a different weight of ink. See
    /// `CadenceCalendarEventStyle.railSecondaryContrastTarget` for why buying more would cost the
    /// hue this treatment exists to show.
    private var secondaryLabelColor: Color {
        CadenceCalendarEventStyle.railSecondaryLabelColor(
            for: item.calendarColor,
            isSelected: isSelected,
            isActive: isHovered
        )
    }

    /// The plate, its rim and the clip are one shape, so the rail cannot stand proud of the
    /// corners the plate draws (T-3167).
    private var blockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius)
    }

    /// The leading rail and the block's edge resolve from one call, so the two cannot drift.
    /// Stateless — see `CadenceCalendarEventStyle.railColor(for:)`.
    private var railColor: Color {
        CadenceCalendarEventStyle.railColor(for: item.calendarColor)
    }
}
#endif

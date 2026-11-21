#if os(macOS)
import EventKit
import SwiftUI

/// The event editor a Month-grid event chip and a Week/Day all-day chip open on click
/// ([[T-5240]]).
///
/// Both chips used to be plain plates: a click on one did nothing, while the task chip beside it
/// opened its inspector, so an all-day event could be opened on macOS only from Board view or
/// Cmd+K and no event at all from Month view. This is `CalendarBoardEventCard`'s popover body with
/// the same write wiring — a refused Save keeps the editor open with the typed reason (T-658), and
/// a delete goes through the refusable confirmation and closes the editor only once it happened
/// (T-919) — so the three surfaces that open an event outside the timeline answer the same way.
struct CalendarEventChipEditPopover: View {
    let item: CalendarEventItem
    @Binding var isPresented: Bool

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var actionFailureNotice: String?

    var body: some View {
        CalendarEventEditPopover(
            item: item,
            onSave: { request, scope in
                // The range is the whole event's, from the shared panel's draft ([[T-3171]]); an
                // unformable one never reached EventKit, so it names no cause.
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
                ) { isPresented = false }
            },
            onDelete: { scope in
                // As on the Board card: the popover stays bound while the confirmation overlay
                // asks, and closes only on a delete that happened, so a refusal is named there.
                deleteConfirmationManager.presentRefusable(
                    title: CadenceCalendarEventEditingSupport.deleteConfirmationTitle,
                    message: CadenceCalendarEventEditingSupport.deleteConfirmationMessage(eventTitle: item.title, scope: scope)
                ) {
                    let outcome = calendarManager.deleteOutcome(
                        for: calendarManager.deleteEvent(item.ekEvent, scope: scope)
                    )
                    if outcome == .deleted { isPresented = false }
                    return outcome
                }
            },
            actionFailureNotice: $actionFailureNotice
        )
    }
}

extension View {
    /// Click-to-edit for a calendar event chip: the tap opens `CalendarEventChipEditPopover`
    /// anchored on the chip. A `.draggable` applied after this keeps working beside it, as it does
    /// on `AllDayTaskChip`.
    func calendarEventChipEditor(
        isPresented: Binding<Bool>,
        item: @escaping () -> CalendarEventItem
    ) -> some View {
        contentShape(Rectangle())
            .onTapGesture { isPresented.wrappedValue = true }
            // [[T-8721]]: the same trait and action as `calendarTaskChipInteractions`, for the
            // same reason -- the click was the only way in.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isPresented.wrappedValue = true }
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                CalendarEventChipEditPopover(item: item(), isPresented: isPresented)
            }
            // [[T-11196]] (1): an all-day event Cmd+K picked opens here, as a timed one opens on
            // its timeline block.
            .honoursCalendarEventEditorRequest(eventID: item().id) { isPresented.wrappedValue = true }
            // [[T-18884]]: Cmd+E and Cmd+Delete over the chip, as over the timeline event block.
            .modifier(CalendarEventHoverKeys(
                hoverID: CalendarEventHoverKeysSupport.chipHoverID(eventID: item().id),
                item: item(),
                onEdit: { isPresented.wrappedValue = true }
            ))
    }

    /// `.draggable` only when the event can take the write the drop would ask for ([[T-5241]]):
    /// dropping an all-day event on the timeline converts it to timed, which EventKit refuses on
    /// a read-only calendar. An organizer-cancelled event is view-only as well ([[T-18179]]), so it
    /// does not drag either: the timed block's own gate answers.
    @ViewBuilder
    func calendarEventDraggable(_ payload: String, isEditable: Bool, isCancelled: Bool) -> some View {
        if TimelineEventBlockEditGate.allowsMove(isEditable: isEditable, isCancelled: isCancelled) {
            draggable(payload)
        } else {
            self
        }
    }
}
/// **[[T-18884]] — an event outside the timeline answers the hover keys too.** The timeline event
/// block registers Cmd+E (open its editor) and, only where the event takes a delete, Cmd+Delete
/// with `HoveredEditableManager` (`TimelineEventBlock`'s `.onHover`, [[T-18175]]). The Month chip,
/// the all-day chip and the Calendar Board card registered nothing, so both keys fell through.
enum CalendarEventHoverKeysSupport {
    /// Namespaced per surface, as the timeline block's `timeline-event-` id is.
    static func chipHoverID(eventID: String) -> String { "calendar-chip-event-\(eventID)" }
    static func boardHoverID(eventID: String) -> String { "calendar-board-event-\(eventID)" }

    /// The timeline block's gate: a view-only event (read-only calendar or organizer-cancelled)
    /// registers no delete, so Cmd+Delete falls through as the editor offers no Delete either.
    static func allowsDelete(_ event: EKEvent) -> Bool {
        TimelineEventBlockEditGate.allowsDelete(
            isEditable: CalendarEventEditPopover.isEditable(event),
            isCancelled: CadenceCalendarEventVisibility.isCancelled(event)
        )
    }

    static func beginHover(
        id: String,
        allowsDelete: Bool,
        hoveredEditableManager: HoveredEditableManager,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        hoveredEditableManager.beginHovering(id: id, onEdit: onEdit, onDelete: allowsDelete ? onDelete : nil)
    }

    /// The [[T-18718]] teardown, guarded on this surface's own hover.
    static func endHoverOnDisappear(isHovered: inout Bool, id: String, hoveredEditableManager: HoveredEditableManager) {
        guard isHovered else { return }
        isHovered = false
        hoveredEditableManager.endHovering(id: id)
    }
}

/// What an event surface needs from its item to register the hover keys.
struct CalendarEventHoverItem {
    let title: String
    let isRecurringSeriesMember: Bool
    let ekEvent: EKEvent
}

extension CalendarEventHoverItem {
    init(_ item: CalendarEventItem) {
        self.init(title: item.title, isRecurringSeriesMember: item.isRecurringSeriesMember, ekEvent: item.ekEvent)
    }

    init(_ item: CalendarBoardEventDisplayItem) {
        self.init(title: item.title, isRecurringSeriesMember: item.isRecurringSeriesMember, ekEvent: item.ekEvent)
    }
}

/// The hover registration itself. A repeating event's Cmd+Delete asks which occurrences first, as
/// the timeline block's `requestEventMutation(.delete)` does; the confirmation after it is the one
/// refusable overlay every event delete goes through (T-919).
struct CalendarEventHoverKeys: ViewModifier {
    let hoverID: String
    let item: CalendarEventHoverItem
    let onEdit: () -> Void
    var onHoverChanged: (Bool) -> Void = { _ in }

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(CalendarManager.self) private var calendarManager
    @State private var isHovered = false
    @State private var isAskingDeleteScope = false

    init(hoverID: String, item: CalendarEventItem, onEdit: @escaping () -> Void) {
        self.hoverID = hoverID
        self.item = CalendarEventHoverItem(item)
        self.onEdit = onEdit
    }

    init(
        hoverID: String,
        item: CalendarBoardEventDisplayItem,
        onEdit: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.hoverID = hoverID
        self.item = CalendarEventHoverItem(item)
        self.onEdit = onEdit
        self.onHoverChanged = onHoverChanged
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                onHoverChanged(hovering)
                if hovering {
                    CalendarEventHoverKeysSupport.beginHover(
                        id: hoverID,
                        allowsDelete: CalendarEventHoverKeysSupport.allowsDelete(item.ekEvent),
                        hoveredEditableManager: hoveredEditableManager,
                        onEdit: onEdit,
                        onDelete: requestDelete
                    )
                } else {
                    hoveredEditableManager.endHovering(id: hoverID)
                }
            }
            .onDisappear {
                CalendarEventHoverKeysSupport.endHoverOnDisappear(
                    isHovered: &isHovered,
                    id: hoverID,
                    hoveredEditableManager: hoveredEditableManager
                )
            }
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.eventDeleteScopeTitle,
                isPresented: $isAskingDeleteScope,
                titleVisibility: .visible
            ) {
                Button(CalendarRecurrenceEditScope.thisOccurrence.label) { confirmDelete(scope: .thisOccurrence) }
                Button(CalendarRecurrenceEditScope.futureOccurrences.label) { confirmDelete(scope: .futureOccurrences) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CadenceRecurrenceScopeCopy.eventDeleteScopeMessage)
            }
    }

    private func requestDelete() {
        if item.isRecurringSeriesMember {
            isAskingDeleteScope = true
        } else {
            confirmDelete(scope: .thisOccurrence)
        }
    }

    private func confirmDelete(scope: CalendarRecurrenceEditScope) {
        deleteConfirmationManager.presentRefusable(
            title: CadenceCalendarEventEditingSupport.deleteConfirmationTitle,
            message: CadenceCalendarEventEditingSupport.deleteConfirmationMessage(eventTitle: item.title, scope: scope)
        ) {
            calendarManager.deleteOutcome(for: calendarManager.deleteEvent(item.ekEvent, scope: scope))
        }
    }
}
#endif

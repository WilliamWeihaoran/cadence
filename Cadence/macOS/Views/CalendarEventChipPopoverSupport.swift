#if os(macOS)
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
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                CalendarEventChipEditPopover(item: item(), isPresented: isPresented)
            }
    }

    /// `.draggable` only when the event can take the write the drop would ask for ([[T-5241]]):
    /// dropping an all-day event on the timeline converts it to timed, which EventKit refuses on
    /// a read-only calendar.
    @ViewBuilder
    func calendarEventDraggable(_ payload: String, isEditable: Bool) -> some View {
        if isEditable {
            draggable(payload)
        } else {
            self
        }
    }
}
#endif

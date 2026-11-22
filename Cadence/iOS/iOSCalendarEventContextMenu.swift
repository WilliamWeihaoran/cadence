#if os(iOS)
import EventKit
import SwiftUI

/// **[[T-19016]] -- a long-press on an iOS Calendar event opens its menu.** The Calendar Board
/// event card and the iPhone Month-agenda event row answered a long-press (and, on iPad, a
/// right-click) with nothing, while the task card or row beside them opened the task menu -- the
/// asymmetry [[T-18883]] removed on the Mac. Neither surface spends its press on a drag, so nothing
/// competes for it.
///
/// **Edit** runs the surface's own tap (the event sheet). **Delete Event** is the sheet's delete,
/// reachable without opening the sheet: a series member is asked the scope first, then every
/// delete stops at the one refusable confirmation ([[T-7075]], `CadenceEventDeleteStep`), in the
/// sheet's own words. A view-only event -- read-only calendar or organizer-cancelled -- gets Edit
/// alone, as the sheet draws no Delete for it (`CadenceEventContextMenuItems`).
struct iOSEventContextMenuHost: ViewModifier {
    let event: EKEvent
    let onEdit: () -> Void

    @Environment(iOSCalendarManager.self) private var calendarManager
    @State private var asksDeleteScope = false
    /// The scope the confirmation names, while it is up.
    @State private var deleteConfirmationScope: CalendarRecurrenceEditScope?
    @State private var deleteFailure: String?

    private var allowsDelete: Bool {
        CadenceEventContextMenuItems.allowsDelete(
            isEditable: calendarManager.canModify(event),
            isCancelled: CadenceCalendarEventVisibility.isCancelled(event)
        )
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                let items = CadenceEventContextMenuItems.items(allowsDelete: allowsDelete)
                if items.contains(.edit) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                }
                if items.contains(.delete) {
                    Button(role: .destructive, action: beginDelete) {
                        Label("Delete Event", systemImage: "trash")
                    }
                    .cadenceDestructiveMenuRow()
                }
            }
            .confirmationDialog(
                CadenceRecurrenceScopeCopy.eventDeleteScopeTitle,
                isPresented: $asksDeleteScope,
                titleVisibility: .visible
            ) {
                Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                    confirmDelete(after: .thisOccurrence)
                }
                Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                    confirmDelete(after: .futureOccurrences)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CadenceRecurrenceScopeCopy.eventDeleteScopeMessage)
            }
            .confirmationDialog(
                CadenceCalendarEventEditingSupport.deleteConfirmationTitle,
                isPresented: Binding(
                    get: { deleteConfirmationScope != nil },
                    set: { if !$0 { deleteConfirmationScope = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteConfirmationScope
            ) { scope in
                Button(CadenceCalendarEventEditingSupport.deleteConfirmationLabel, role: .destructive) {
                    applyDelete(scope: scope)
                }
                Button("Cancel", role: .cancel) {}
            } message: { scope in
                Text(
                    CadenceCalendarEventEditingSupport.deleteConfirmationMessage(
                        eventTitle: iOSCalendarEventSupport.title(for: event),
                        scope: scope
                    )
                )
            }
            .alert(
                "Couldn't Delete Event",
                isPresented: Binding(
                    get: { deleteFailure != nil },
                    set: { if !$0 { deleteFailure = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteFailure ?? "")
            }
    }

    private func beginDelete() {
        switch CadenceEventDeleteStep.first(
            isRecurringSeriesMember: CadenceEventNoteSupport.isRecurringSeriesMember(event)
        ) {
        case .askScope:
            asksDeleteScope = true
        case .confirm(let scope):
            deleteConfirmationScope = scope
        }
    }

    /// The scope dialog is still dismissing when its button runs; the confirmation is raised on the
    /// next main-queue turn, as the sheet's is.
    private func confirmDelete(after scope: CalendarRecurrenceEditScope) {
        guard let confirmed = CadenceEventDeleteStep.afterScope(scope).confirmationScope else { return }
        DispatchQueue.main.async {
            deleteConfirmationScope = confirmed
        }
    }

    /// Re-reads the gate at the moment of writing: the event may have gone view-only while the
    /// dialogs were up.
    private func applyDelete(scope: CalendarRecurrenceEditScope) {
        guard allowsDelete else { return }
        if let failure = calendarManager.deleteEvent(event, span: scope.eventSpan) {
            deleteFailure = CadenceCalendarEventEditingSupport.deleteFailureNotice(for: failure)
        }
    }
}

extension View {
    /// Hosts `iOSEventContextMenuHost` on an event surface.
    func iOSEventContextMenu(event: EKEvent, onEdit: @escaping () -> Void) -> some View {
        modifier(iOSEventContextMenuHost(event: event, onEdit: onEdit))
    }
}
#endif

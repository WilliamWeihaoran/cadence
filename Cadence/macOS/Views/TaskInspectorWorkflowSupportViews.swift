#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask

    var body: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                Button {
                    task.recurrenceRule = rule
                } label: {
                    Label(rule.label, systemImage: rule.systemImage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: task.recurrenceRule.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(task.isRecurring ? Theme.blue : Theme.dim)
                Text(task.recurrenceRule.shortLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.isRecurring ? Theme.text : Theme.dim)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.surfaceElevated.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }
}

struct TaskInspectorEventAttachmentControl: View {
    @Bindable var task: AppTask
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EventNote.updatedAt, order: .reverse) private var eventNotes: [EventNote]

    @State private var showPicker = false
    @State private var searchQuery = ""
    @State private var presentedEventNote: EventNote?

    private var linkedEvent: EKEvent? {
        calendarManager.event(withIdentifier: task.calendarEventID)
    }

    private var linkedEventNote: EventNote? {
        EventNoteSupport.note(for: task.calendarEventID, in: eventNotes)
    }

    private var results: [EKEvent] {
        calendarManager.searchEvents(matching: searchQuery)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let linkedEvent {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkedEvent.title?.isEmpty == false ? linkedEvent.title! : "Linked event")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(linkedEventSummary(linkedEvent))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }

                    Button(linkedEventNote == nil ? "Create linked note" : "Open linked note") {
                        openEventNote(for: linkedEvent)
                    }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                }

                Spacer(minLength: 8)

                Button("Change") {
                    showPicker = true
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.blue)

                Button("Detach") {
                    task.calendarEventID = ""
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
            } else {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Attach existing event")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(calendarManager.isAuthorized ? Theme.blue : Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .disabled(!calendarManager.isAuthorized)

                if !calendarManager.isAuthorized {
                    Spacer(minLength: 8)
                    Text("Calendar access needed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { presentedEventNote != nil },
            set: { if !$0 { presentedEventNote = nil } }
        )) {
            if let linkedEvent = linkedEvent, let presentedEventNote {
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: linkedEvent.title ?? "Linked Event")
            }
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    TextField("Search calendar events...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Theme.borderSubtle)

                if results.isEmpty {
                    Text("No matching events")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(results.prefix(10), id: \.eventIdentifier) { event in
                                Button {
                                    attach(event)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title?.isEmpty == false ? event.title! : "Untitled Event")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(linkedEventSummary(event))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.dim)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 260)
                }
            }
            .frame(width: 280)
            .background(Theme.surface)
        }
    }

    private func attach(_ event: EKEvent) {
        task.calendarEventID = event.eventIdentifier
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task.title = event.title ?? ""
        }
        calendarManager.syncTaskFromLinkedEvent(task)
        searchQuery = ""
        showPicker = false
    }

    private func linkedEventSummary(_ event: EKEvent) -> String {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        let startComps = Calendar.current.dateComponents([.hour, .minute], from: start)
        let endComps = Calendar.current.dateComponents([.hour, .minute], from: end)
        let startMin = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
        let endMin = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)
        return "\(DateFormatters.shortDate.string(from: start)) • \(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))"
    }

    private func openEventNote(for event: EKEvent) {
        let eventID = event.eventIdentifier ?? task.calendarEventID
        let metadata = EventNoteSupport.eventDateMetadata(from: event)
        presentedEventNote = EventNoteSupport.noteForEditing(
            calendarEventID: eventID,
            eventTitle: event.title ?? "Linked Event",
            calendarID: event.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            notes: eventNotes
        ) { modelContext.insert($0) }
    }
}
#endif

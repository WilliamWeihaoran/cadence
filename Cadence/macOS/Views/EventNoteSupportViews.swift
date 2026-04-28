#if os(macOS)
import SwiftUI

struct EventNoteEditorSheet: View {
    @Bindable var note: EventNote
    let eventTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Event note title", text: $note.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(eventTitle.isEmpty ? "Linked event note" : eventTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().background(Theme.borderSubtle)

            MarkdownEditorView(text: Binding(
                get: { note.content },
                set: {
                    note.content = $0
                    note.updatedAt = Date()
                }
            ))
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
    }
}

enum EventNoteSupport {
    static func note(for calendarEventID: String, in notes: [EventNote]) -> EventNote? {
        notes.first { $0.calendarEventID == calendarEventID }
    }

    @discardableResult
    static func noteForEditing(
        calendarEventID: String,
        eventTitle: String,
        notes: [EventNote],
        insert: (EventNote) -> Void
    ) -> EventNote? {
        guard !calendarEventID.isEmpty else { return nil }
        if let existing = note(for: calendarEventID, in: notes) {
            if existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
            }
            return existing
        }

        let created = EventNote(calendarEventID: calendarEventID, eventTitle: eventTitle)
        insert(created)
        return created
    }
}
#endif

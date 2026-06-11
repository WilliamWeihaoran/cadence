#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSEventNoteEditorSheet: View {
    @Bindable var note: Note
    let eventTitle: String
    let event: EKEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @State private var isEditorFocused = false

    private var title: String {
        note.displayTitle
    }

    private var subtitle: String {
        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Linked event note" : trimmed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider().background(Theme.borderSubtle)

                iOSMarkdownEditor(text: $note.content, isFocused: $isEditorFocused)
                    .background(Theme.surface)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Meeting Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        persistNote()
                        isEditorFocused = false
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshEventMetadata()
                persistNote(syncToCalendar: false)
            }
            .onChange(of: note.content) { _, _ in
                persistNote()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        persistNote()
                        isEditorFocused = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private func refreshEventMetadata() {
        guard let event else { return }
        let metadata = CadenceEventNoteSupport.eventDateMetadata(from: event)
        CadenceEventNoteSupport.updateMetadata(
            note,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin
        )
    }

    private func persistNote(syncToCalendar: Bool = true) {
        note.updatedAt = Date()
        try? modelContext.save()

        guard syncToCalendar else { return }
        if let event {
            calendarManager.updateEventNotes(event, notes: note.content)
        } else if !note.calendarEventID.isEmpty {
            calendarManager.updateEventNotes(calendarEventID: note.calendarEventID, notes: note.content)
        }
    }
}
#endif

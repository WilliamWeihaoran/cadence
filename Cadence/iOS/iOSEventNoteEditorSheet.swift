#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSEventNoteEditorSheet: View {
    @Bindable var note: Note
    let eventTitle: String
    let event: EKEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @State private var isEditorFocused = false
    @State private var editorMode: iOSMarkdownEditorMode = .edit

    private var title: String {
        note.displayTitle
    }

    private var subtitle: String {
        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Linked event note" : trimmed
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            editorLayout
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

    @ViewBuilder
    private var editorLayout: some View {
        if isRegularWidth {
            regularEditorLayout
        } else {
            compactEditorLayout
        }
    }

    private var compactEditorLayout: some View {
        VStack(spacing: 0) {
            header

            Divider().background(Theme.borderSubtle)

            editorSurface
        }
    }

    private var regularEditorLayout: some View {
        HStack(spacing: 0) {
            header
                .frame(width: 320, alignment: .topLeading)

            Divider().background(Theme.borderSubtle)

            editorSurface
        }
    }

    private var editorSurface: some View {
        iOSMarkdownEditingSurface(
            text: $note.content,
            isFocused: $isEditorFocused,
            mode: $editorMode,
            placeholder: "Start writing..."
        )
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

            HStack {
                Spacer()
                iOSMarkdownModePicker(mode: $editorMode)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: isRegularWidth ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, isRegularWidth ? 20 : 18)
        .padding(.vertical, isRegularWidth ? 20 : 14)
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

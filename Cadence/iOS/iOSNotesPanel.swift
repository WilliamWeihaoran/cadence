#if os(iOS)
import SwiftData
import SwiftUI

struct iOSNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: NoteTab = .today
    @State private var todayNote: Note?
    @State private var permanentNote: Note?

    private enum NoteTab: String, CaseIterable {
        case today = "Today"
        case notepad = "Notepad"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: "Notes",
                title: activeTab.rawValue
            )

            HStack(spacing: 8) {
                ForEach(NoteTab.allCases, id: \.self) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: activeTab == tab ? .semibold : .medium))
                            .foregroundStyle(activeTab == tab ? .white : Theme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(activeTab == tab ? Theme.blue : Theme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider().background(Theme.borderSubtle)

            if let note = selectedNote {
                TextEditor(text: Binding(
                    get: { note.content },
                    set: { update(note, content: $0) }
                ))
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
                .padding(12)
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear(perform: loadNotes)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadNotes()
        }
    }

    private var selectedNote: Note? {
        switch activeTab {
        case .today: return todayNote
        case .notepad: return permanentNote
        }
    }

    private func loadNotes() {
        todayNote = try? NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext)
        permanentNote = try? NoteMigrationService.permanentNote(in: modelContext)
    }

    private func update(_ note: Note, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? modelContext.save()
    }
}
#endif

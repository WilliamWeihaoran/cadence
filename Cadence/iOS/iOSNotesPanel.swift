#if os(iOS)
import SwiftData
import SwiftUI

struct iOSNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: NoteTab = .today
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @FocusState private var isEditorFocused: Bool
    var useStandardHeaderHeight = false

    private enum NoteTab: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case notepad = "Notepad"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                iOSPanelHeader(
                    eyebrow: "Notes",
                    title: activeTab.rawValue
                )

                HStack(spacing: 0) {
                    ForEach(NoteTab.allCases, id: \.self) { tab in
                        iOSNotePanelTabButton(
                            title: tab.rawValue,
                            isSelected: activeTab == tab
                        ) {
                            activeTab = tab
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(height: useStandardHeaderHeight ? iOSPanelHeaderHeight : nil, alignment: .top)

            Divider().background(Theme.borderSubtle)

            if let note = selectedNote {
                ZStack(alignment: .topLeading) {
                    if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditorFocused {
                        Text("Start writing...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim.opacity(0.6))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ))
                    .focused($isEditorFocused)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Theme.surface)
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
        .onChange(of: activeTab) { _, _ in
            isEditorFocused = false
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    private var selectedNote: Note? {
        switch activeTab {
        case .today: return todayNote
        case .week: return weekNote
        case .notepad: return permanentNote
        }
    }

    private func loadNotes() {
        todayNote = try? NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext)
        weekNote = try? NoteMigrationService.weeklyNote(for: DateFormatters.currentWeekKey(), in: modelContext)
        permanentNote = try? NoteMigrationService.permanentNote(in: modelContext)
    }

    private func update(_ note: Note, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct iOSNotePanelTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                .frame(minWidth: 78, minHeight: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle()
                            .fill(Theme.blue.opacity(0.8))
                            .frame(height: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
#endif

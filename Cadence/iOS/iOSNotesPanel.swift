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

                    iOSMarkdownEditor(text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ), isFocused: Binding(
                        get: { isEditorFocused },
                        set: { isEditorFocused = $0 }
                    ))
                    .background(Color.clear)
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

struct iOSCompactNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: CompactNoteTab = .today
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @FocusState private var isEditorFocused: Bool

    private enum CompactNoteTab: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case notepad = "Notepad"

        var id: Self { self }

        var subtitle: String {
            switch self {
            case .today:
                guard let today = DateFormatters.date(from: DateFormatters.todayKey()) else {
                    return "Today"
                }
                return DateFormatters.longDate.string(from: today)
            case .week:
                return DateFormatters.weekLabel(from: DateFormatters.currentWeekKey())
            case .notepad:
                return "Permanent notes"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            Picker("Note", selection: $activeTab) {
                ForEach(CompactNoteTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider().background(Theme.borderSubtle)

            if let note = selectedNote {
                ZStack(alignment: .topLeading) {
                    if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditorFocused {
                        Text("Start writing...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.dim.opacity(0.62))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 20)
                    }

                    iOSMarkdownEditor(text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ), isFocused: Binding(
                        get: { isEditorFocused },
                        set: { isEditorFocused = $0 }
                    ))
                }
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
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

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 42, height: 42)
                .background(Theme.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(activeTab.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
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

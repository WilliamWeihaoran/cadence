#if os(macOS)
import SwiftUI
import SwiftData

struct NotePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allDailyNotes:  [DailyNote]
    @Query private var allWeeklyNotes: [WeeklyNote]
    @Query private var allPermNotes:   [PermNote]

    enum NoteTab: String, CaseIterable {
        case today  = "Today"
        case week   = "This Week"
        case notepad = "Notepad"
    }

    @State private var activeTab: NoteTab = .today
    @State private var todayNote:  DailyNote?
    @State private var weekNote:   WeeklyNote?
    @State private var permNote:   PermNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            PanelHeader(eyebrow: "Notes", title: headerTitle)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(NoteTab.allCases, id: \.self) { tab in
                    NotePanelTabButton(tab: tab, isSelected: activeTab == tab) {
                        activeTab = tab
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)

            Divider().background(Theme.borderSubtle)

            // Content
            Group {
                switch activeTab {
                case .today:
                    if let note = todayNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { note.content = $0; note.updatedAt = Date() }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .week:
                    if let note = weekNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { note.content = $0; note.updatedAt = Date() }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .notepad:
                    if let note = permNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { note.content = $0; note.updatedAt = Date() }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Theme.surface)
        .onAppear { loadOrCreate() }
    }

    private var headerTitle: String {
        switch activeTab {
        case .today:   return "Today"
        case .week:    return "This Week"
        case .notepad: return "Notepad"
        }
    }

    private func loadOrCreate() {
        let todayKey = DateFormatters.todayKey()
        if let existing = allDailyNotes.first(where: { $0.date == todayKey }) {
            todayNote = existing
        } else {
            let note = DailyNote(date: todayKey)
            modelContext.insert(note)
            todayNote = note
        }

        let wKey = DateFormatters.currentWeekKey()
        if let existing = allWeeklyNotes.first(where: { $0.weekKey == wKey }) {
            weekNote = existing
        } else {
            let note = WeeklyNote(weekKey: wKey)
            modelContext.insert(note)
            weekNote = note
        }

        if let existing = allPermNotes.first {
            permNote = existing
        } else {
            let note = PermNote()
            modelContext.insert(note)
            permNote = note
        }
    }
}

// MARK: - Tab Button

private struct NotePanelTabButton: View {
    let tab: NotePanel.NoteTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                .frame(minWidth: 78, minHeight: 32)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle().fill(Theme.blue).frame(height: 2)
                    }
                }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif

#if os(macOS)
import SwiftUI
import SwiftData

struct NotePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    var useStandardHeaderHeight = false

    enum NoteTab: String, CaseIterable {
        case today  = "Today"
        case week   = "This Week"
        case notepad = "Notepad"
    }

    @State private var activeTab: NoteTab = .today
    @State private var todayNote:  DailyNote?
    @State private var weekNote:   WeeklyNote?
    @State private var permNote:   PermNote?
    @State private var notesContext: ModelContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(eyebrow: "Notes", title: headerTitle)

                HStack(spacing: 0) {
                    ForEach(NoteTab.allCases, id: \.self) { tab in
                        NotePanelTabButton(tab: tab, isSelected: activeTab == tab) {
                            activeTab = tab
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)

            Divider().background(Theme.borderSubtle)

            // Content
            Group {
                switch activeTab {
                case .today:
                    if let note = todayNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { update(note: note, content: $0) }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .week:
                    if let note = weekNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { update(note: note, content: $0) }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .notepad:
                    if let note = permNote {
                        MarkdownEditorView(text: Binding(
                            get: { note.content },
                            set: { update(note: note, content: $0) }
                        ))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Theme.surface)
        .onAppear { loadOrCreate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshFromStore()
        }
        .onChange(of: activeTab) { _, _ in
            refreshFromStore()
        }
    }

    private var headerTitle: String {
        switch activeTab {
        case .today:   return "Today"
        case .week:    return "This Week"
        case .notepad: return "Notepad"
        }
    }

    private func loadOrCreate() {
        let context = notesContext ?? makeNotesContext()
        notesContext = context

        let todayKey = DateFormatters.todayKey()
        if let existing = fetchDailyNote(date: todayKey, in: context) {
            todayNote = existing
        } else {
            let note = DailyNote(date: todayKey)
            context.insert(note)
            todayNote = note
        }

        let wKey = DateFormatters.currentWeekKey()
        if let existing = fetchWeeklyNote(weekKey: wKey, in: context) {
            weekNote = existing
        } else {
            let note = WeeklyNote(weekKey: wKey)
            context.insert(note)
            weekNote = note
        }

        if let existing = fetchPermanentNote(in: context) {
            permNote = existing
        } else {
            let note = PermNote()
            context.insert(note)
            permNote = note
        }

        try? context.save()
    }

    private func refreshFromStore() {
        if let notesContext, notesContext.hasChanges {
            try? notesContext.save()
        }

        notesContext = makeNotesContext()
        todayNote = nil
        weekNote = nil
        permNote = nil
        loadOrCreate()
    }

    private func makeNotesContext() -> ModelContext {
        ModelContext(modelContext.container)
    }

    private func update(note: DailyNote, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? notesContext?.save()
    }

    private func update(note: WeeklyNote, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? notesContext?.save()
    }

    private func update(note: PermNote, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? notesContext?.save()
    }

    private func fetchDailyNote(date: String, in context: ModelContext) -> DailyNote? {
        var descriptor = FetchDescriptor<DailyNote>(
            predicate: #Predicate { $0.date == date }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchWeeklyNote(weekKey: String, in context: ModelContext) -> WeeklyNote? {
        var descriptor = FetchDescriptor<WeeklyNote>(
            predicate: #Predicate { $0.weekKey == weekKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchPermanentNote(in context: ModelContext) -> PermNote? {
        var descriptor = FetchDescriptor<PermNote>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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

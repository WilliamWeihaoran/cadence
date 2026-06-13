#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

enum iOSSearchScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case lists
    case notes
    case events
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .notes: return "Notes"
        case .events: return "Events"
        case .progress: return "More"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tasks: return "checkmark.circle"
        case .lists: return "folder"
        case .notes: return "note.text"
        case .events: return "calendar"
        case .progress: return "sparkles"
        }
    }
}

enum iOSSearchFeatureDestination: String, CaseIterable, Hashable {
    case today
    case allTasks
    case inbox
    case notes
    case focus
    case calendar
    case pursuits
    case milestones
    case habits
    case lists
    case settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .inbox: return "Inbox"
        case .notes: return "Notes"
        case .focus: return "Focus"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .milestones: return "Milestones"
        case .habits: return "Habits"
        case .lists: return "Lists"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .today: return "Plan the day"
        case .allTasks: return "Full task index"
        case .inbox: return "Capture and triage"
        case .notes: return "Workspace notes"
        case .focus: return "Timer and current work"
        case .calendar: return "Timeline and month"
        case .pursuits: return "Long-running directions"
        case .milestones: return "Goals and progress"
        case .habits: return "Repeating commitments"
        case .lists: return "Areas and projects"
        case .settings: return "Preferences and diagnostics"
        }
    }

    var detail: String {
        switch self {
        case .today: return "tasks notes schedule"
        case .allTasks: return "tasks completed active"
        case .inbox: return "capture unsorted tasks"
        case .notes: return "daily weekly notepad markdown"
        case .focus: return "timer pomodoro session"
        case .calendar: return "calendar schedule timeline month"
        case .pursuits: return "pursuits aspirations directions"
        case .milestones: return "goals milestones progress"
        case .habits: return "habits streaks routines"
        case .lists: return "areas projects lists"
        case .settings: return "settings preferences sync tags themes"
        }
    }

    var aliases: String { "\(rawValue) \(title) \(subtitle) \(detail)" }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .inbox: return "tray.fill"
        case .notes: return "note.text"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .pursuits: return "sparkles"
        case .milestones: return "flag.fill"
        case .habits: return "flame.fill"
        case .lists: return "folder.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .today: return Theme.amber
        case .allTasks, .inbox, .settings: return Theme.blue
        case .notes, .calendar, .pursuits: return Theme.purple
        case .focus: return Theme.red
        case .milestones, .lists: return Theme.green
        case .habits: return Theme.amber
        }
    }
}

struct iOSSearchListCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let route: iOSListRoute
    let fields: [String]

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .list,
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score,
            listRoute: route
        )
    }
}

struct iOSSearchFeatureCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let destination: iOSSearchFeatureDestination
    let fields: [String]

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .feature,
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score,
            featureDestination: destination
        )
    }
}

struct iOSSearchResult: Identifiable {
    enum Kind {
        case task
        case list
        case note
        case event
        case progress
        case feature
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let score: Int
    var task: AppTask?
    var note: Note?
    var event: EKEvent?
    var listRoute: iOSListRoute?
    var featureDestination: iOSSearchFeatureDestination?
}

struct iOSSearchScopePicker: View {
    @Binding var selection: iOSSearchScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(iOSSearchScope.allCases) { scope in
                    iOSSearchScopeChip(
                        scope: scope,
                        isSelected: selection == scope
                    ) {
                        withAnimation(.snappy(duration: 0.16)) {
                            selection = scope
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

private struct iOSSearchScopeChip: View {
    let scope: iOSSearchScope
    let isSelected: Bool
    let action: () -> Void

    private var foreground: Color {
        isSelected ? .white : Theme.text
    }

    private var background: Color {
        isSelected ? Theme.blue : Theme.surfaceElevated
    }

    private var border: Color {
        Theme.borderSubtle.opacity(isSelected ? 0 : 0.9)
    }

    var body: some View {
        Button(action: action) {
            Label(scope.title, systemImage: scope.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct iOSSearchResultRow: View {
    let result: iOSSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(result.color)
                .frame(width: 30, height: 30)
                .background(result.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                if !result.detail.isEmpty {
                    Text(result.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim.opacity(0.78))
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

struct iOSNoteDetailSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isEditorFocused = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSMarkdownEditor(text: $note.content, isFocused: $isEditorFocused)
                    .background(Theme.surface)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(note.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isEditorFocused = false
                        note.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onChange(of: note.content) { _, _ in
                note.updatedAt = Date()
                try? modelContext.save()
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
        .preferredColorScheme(.dark)
    }
}
#endif

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
    let destination: CadenceFeatureDestination
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
    var featureDestination: CadenceFeatureDestination?
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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

            Spacer(minLength: 0)
        }
        .padding(12)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

struct iOSNoteDetailSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var isEditorFocused = false
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $editorModeRaw)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSMarkdownEditingSurface(
                    text: Binding(
                        get: { note.content },
                        set: { updateContent($0) }
                    ),
                    isFocused: $isEditorFocused,
                    mode: editorModeBinding,
                    placeholder: "Start writing...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference
                )
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

                ToolbarItem(placement: .primaryAction) {
                    iOSMarkdownModePicker(mode: editorModeBinding, compact: true)
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
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    private func updateContent(_ content: String) {
        note.content = content
        note.updatedAt = Date()
        try? modelContext.save()
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }
}
#endif

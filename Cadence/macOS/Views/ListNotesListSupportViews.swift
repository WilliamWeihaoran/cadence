#if os(macOS)
import SwiftUI
import SwiftData

struct ListNoteFolderGroup: Identifiable {
    let folderPath: String
    let notes: [Note]

    var id: String { folderPath.isEmpty ? "__root__" : folderPath }
    var displayName: String { folderPath.isEmpty ? "Notes" : folderPath }
}

struct NoteFolderSheetRequest: Identifiable {
    enum Mode {
        case newNote
        case moveNote(UUID)
    }

    let id = UUID()
    let mode: Mode

    var title: String {
        switch mode {
        case .newNote: return "New Folder Note"
        case .moveNote: return "Move to Folder"
        }
    }

    var actionTitle: String {
        switch mode {
        case .newNote: return "Create Note"
        case .moveNote: return "Move"
        }
    }
}

struct NoteFolderSheet: View {
    let request: NoteFolderSheetRequest
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folderPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Planning/Research", text: $folderPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceElevated.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)

                Button(request.actionTitle) {
                    onSave(folderPath)
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue.opacity(folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)
                .disabled(folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.surface)
    }
}

struct TaskNoteListRow: View {
    @Bindable var task: AppTask
    let isSelected: Bool

    private var title: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title
    }

    private var excerpt: String {
        task.notes
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dueLabel: String? {
        CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: DateFormatters.todayKey())
    }

    private var isOverdue: Bool {
        !task.isDone && CadenceFocusSupport.isOverdue(dueDateKey: task.dueDate, todayKey: DateFormatters.todayKey())
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                // A due date always claims the second line first; the excerpt is what gives way
                // when the row runs out of width.
                if dueLabel != nil || !excerpt.isEmpty {
                    HStack(spacing: 6) {
                        if let dueLabel {
                            Text(dueLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                        if !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.16 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.24 : 0.12)
        )
    }
}

struct ListNoteRow: View {
    @Bindable var note: Note
    let isSelected: Bool
    @State private var isEditingTitle = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 4) {
                if isEditingTitle {
                    TextField("", text: $note.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                        .onSubmit { isEditingTitle = false }
                        .onExitCommand { isEditingTitle = false }
                } else {
                    Text(note.displayTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)
                }
                CompactTagStrip(tags: note.sortedTags, limit: 2)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.16 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.24 : 0.12)
        )
        .onTapGesture(count: 2) {
            isEditingTitle = true
            focused = true
        }
    }
}
#endif

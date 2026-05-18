#if os(iOS)
import SwiftData
import SwiftUI

struct iOSListPickerRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Theme.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

struct iOSArchivedListRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex).opacity(0.58))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Theme.muted)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Button("Restore", action: restore)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 3)
    }
}

struct iOSListNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    let area: Area?
    let project: Project?
    @State private var note: Note?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "List Notes", title: "Notes")
            Divider().background(Theme.borderSubtle)

            if let note {
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
        .onAppear(perform: loadOrCreateNote)
    }

    private func loadOrCreateNote() {
        let descriptor = FetchDescriptor<Note>()
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        if let area {
            if let existing = notes.first(where: { $0.kind == .list && $0.area?.id == area.id && $0.project == nil }) {
                note = existing
                return
            }
            let created = Note(kind: .list, title: area.name, area: area)
            modelContext.insert(created)
            try? modelContext.save()
            note = created
            return
        }

        if let project {
            if let existing = notes.first(where: { $0.kind == .list && $0.project?.id == project.id }) {
                note = existing
                return
            }
            let created = Note(kind: .list, title: project.name, project: project)
            modelContext.insert(created)
            try? modelContext.save()
            note = created
        }
    }

    private func update(_ note: Note, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? modelContext.save()
    }
}
#endif

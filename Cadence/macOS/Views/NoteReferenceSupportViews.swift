#if os(macOS)
import SwiftUI

struct NoteReferenceStrip: View {
    let linkedNotes: [Note]
    let linkedTasks: [AppTask]
    let backlinks: [Note]
    let onOpenNote: (Note) -> Void

    private var todayKey: String { DateFormatters.todayKey() }

    var body: some View {
        if linkedNotes.isEmpty && linkedTasks.isEmpty && backlinks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !linkedNotes.isEmpty {
                    ReferenceSection(label: "Linked Notes") {
                        ForEach(linkedNotes, id: \.id) { linked in
                            Button {
                                onOpenNote(linked)
                            } label: {
                                ReferenceChip(icon: "doc.text", title: linked.displayTitle, tint: Theme.blue)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                if !linkedTasks.isEmpty {
                    ReferenceSection(label: "Task References") {
                        ForEach(linkedTasks, id: \.id) { task in
                            ReferenceChip(
                                icon: "checkmark.circle",
                                title: task.title.isEmpty ? "Untitled Task" : task.title,
                                tint: Theme.green,
                                dueLabel: CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey),
                                isOverdue: !task.isDone && CadenceFocusSupport.isOverdue(dueDateKey: task.dueDate, todayKey: todayKey)
                            )
                        }
                    }
                }

                if !backlinks.isEmpty {
                    ReferenceSection(label: "Backlinks") {
                        ForEach(backlinks, id: \.id) { backlink in
                            Button {
                                onOpenNote(backlink)
                            } label: {
                                ReferenceChip(icon: "arrow.uturn.backward.circle", title: backlink.displayTitle, tint: Theme.amber)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(alignment: .bottom) {
                Divider().background(Theme.borderSubtle)
            }
        }
    }
}

private struct ReferenceSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content }
            }
        }
    }
}

private struct ReferenceChip: View {
    let icon: String
    let title: String
    let tint: Color
    var dueLabel: String? = nil
    var isOverdue: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            // The chip is tight, so the deadline gets the fixed width and the title truncates
            // around it — a task with a due date never shows up here as a bare title.
            if let dueLabel {
                Text(dueLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}
#endif

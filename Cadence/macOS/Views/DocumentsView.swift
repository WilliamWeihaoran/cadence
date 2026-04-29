#if os(macOS)
import SwiftUI
import SwiftData

struct DocumentsView: View {
    var area: Area? = nil
    var project: Project? = nil
    @Binding var requestedEventNoteID: UUID?

    init(area: Area? = nil, project: Project? = nil, requestedEventNoteID: Binding<UUID?> = .constant(nil)) {
        self.area = area
        self.project = project
        _requestedEventNoteID = requestedEventNoteID
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(CalendarManager.self) private var calendarManager
    @State private var selectedNoteID: UUID? = nil
    @State private var selectedEventNoteID: UUID? = nil
    @Query(sort: \Note.order) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]

    private var docs: [Note] {
        if let area {
            return allNotes.filter { $0.kind == .list && $0.area?.id == area.id }
        } else if let project {
            return allNotes.filter { $0.kind == .list && $0.project?.id == project.id }
        }
        return []
    }

    private var selectedDoc: Note? {
        docs.first { $0.id == selectedNoteID }
    }

    private var linkedCalendarID: String {
        area?.linkedCalendarID ?? project?.linkedCalendarID ?? ""
    }

    private var meetingNotes: [Note] {
        guard !linkedCalendarID.isEmpty else { return [] }
        return allNotes.filter { $0.kind == .meeting && $0.calendarID == linkedCalendarID }
    }

    private var selectedEventNote: Note? {
        meetingNotes.first { $0.id == selectedEventNoteID }
    }

    private var tasks: [AppTask] {
        if let area {
            return allTasks.filter { $0.area?.id == area.id }
        } else if let project {
            return allTasks.filter { $0.project?.id == project.id }
        }
        return []
    }

    var body: some View {
        HSplitView {
            // Document list
            VStack(spacing: 0) {
                HStack {
                    Text("Notes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if let selectedDoc {
                        Menu {
                            Button("Export Markdown") {
                                DocumentExportService.exportMarkdown(selectedDoc)
                            }
                            Button("Export PDF") {
                                DocumentExportService.exportPDF(selectedDoc, imageAssets: imageAssets)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Button {
                        addDocument()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.cadencePlain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Theme.borderSubtle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !meetingNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Meeting Notes")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                                ForEach(meetingNotes) { note in
                                    MeetingNoteListRow(note: note, isSelected: selectedEventNoteID == note.id)
                                        .onTapGesture {
                                            selectedEventNoteID = note.id
                                            selectedNoteID = nil
                                            requestedEventNoteID = nil
                                        }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            if !meetingNotes.isEmpty && !docs.isEmpty {
                                Text("Notes")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                            }

                            ForEach(docs) { doc in
                                DocRow(note: doc, isSelected: selectedNoteID == doc.id)
                                    .onTapGesture {
                                        selectedNoteID = doc.id
                                        selectedEventNoteID = nil
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteDoc(doc)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding(8)
                }

                if docs.isEmpty && meetingNotes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No notes",
                        subtitle: "Tap + to create one",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
            .background(Theme.surface)

            // Editor — .id(doc.id) ensures a fresh NSTextView (and undo stack) per document
            if let eventNote = selectedEventNote {
                NoteEditorPane(note: eventNote)
            } else if let doc = selectedDoc {
                VStack(spacing: 0) {
                    NoteReferenceStrip(
                        note: doc,
                        docs: docs,
                        tasks: tasks,
                        onOpenNote: { selectedNoteID = $0.id }
                    )

                    ListNoteMarkdownEditor(note: doc)
                        .id(doc.id)
                }
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.dim)
                        Text("Select a note")
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .background(Theme.bg)
        .onAppear {
            backfillMeetingNoteMetadata()
            applyRequestedEventNoteSelection()
            if selectedNoteID == nil, selectedEventNoteID == nil {
                selectedEventNoteID = meetingNotes.first?.id
                if selectedEventNoteID == nil {
                    selectedNoteID = docs.first?.id
                }
            }
        }
        .onChange(of: requestedEventNoteID) { _, _ in
            applyRequestedEventNoteSelection()
        }
        .onChange(of: allNotes.map(\.id)) { _, _ in
            backfillMeetingNoteMetadata()
            applyRequestedEventNoteSelection()
        }
    }

    private func addDocument() {
        let doc = Note(kind: .list)
        doc.area = area
        doc.project = project
        doc.order = docs.count
        doc.content = defaultDocumentContent(for: doc.title)
        modelContext.insert(doc)
        selectedNoteID = doc.id
        selectedEventNoteID = nil
    }

    private func deleteDoc(_ doc: Note) {
        deleteConfirmationManager.present(
            title: "Delete Note?",
            message: "This will permanently delete \"\(doc.displayTitle)\"."
        ) {
            if selectedNoteID == doc.id {
                selectedNoteID = docs.first { $0.id != doc.id }?.id
            }
            modelContext.delete(doc)
        }
    }

    private func defaultDocumentContent(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingTitle = trimmed.isEmpty ? "Untitled" : trimmed
        return "# \(headingTitle)\n\n"
    }

    private func applyRequestedEventNoteSelection() {
        guard let requestedEventNoteID else { return }
        guard meetingNotes.contains(where: { $0.id == requestedEventNoteID }) else { return }
        selectedEventNoteID = requestedEventNoteID
        selectedNoteID = nil
        self.requestedEventNoteID = nil
    }

    private func backfillMeetingNoteMetadata() {
        for note in allNotes where note.kind == .meeting && note.calendarID.isEmpty {
            EventNoteSupport.backfillMetadataIfPossible(note, calendarManager: calendarManager)
        }
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

}

// MARK: - Doc Row

private struct DocRow: View {
    @Bindable var note: Note
    let isSelected: Bool
    @State private var isEditingTitle = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
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
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.16 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.24 : 0.12)
        )
        .onTapGesture(count: 2) {
            isEditingTitle = true
            focused = true
        }
    }
}

// MARK: - Markdown Editor

private struct ListNoteMarkdownEditor: View {
    @Bindable var note: Note

    var body: some View {
        MarkdownEditor(text: $note.content)
            .onChange(of: note.content) {
                note.updatedAt = Date()
                syncTitleFromH1()
            }
    }

    private func syncTitleFromH1() {
        // Extract the first H1 line ("# Title") and keep note.title in sync with it
        let firstLine = note.content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != note.title else { return }
        note.title = h1Text
    }
}

private struct NoteReferenceStrip: View {
    let note: Note
    let docs: [Note]
    let tasks: [AppTask]
    let onOpenNote: (Note) -> Void

    private var linkedNotes: [Note] {
        let titles = MarkdownReferenceParser.noteLinks(in: note.content)
        return titles.compactMap { title in
            docs.first {
                $0.id != note.id &&
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    private var linkedTasks: [AppTask] {
        let titles = MarkdownReferenceParser.taskReferences(in: note.content)
        return titles.compactMap { title in
            tasks.first {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    private var backlinks: [Note] {
        let currentTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else { return [] }
        return docs.filter { other in
            other.id != note.id &&
            MarkdownReferenceParser.noteLinks(in: other.content).contains {
                $0.caseInsensitiveCompare(currentTitle) == .orderedSame
            }
        }
    }

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
                            ReferenceChip(icon: "checkmark.circle", title: task.title.isEmpty ? "Untitled Task" : task.title, tint: Theme.green)
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

private enum MarkdownReferenceParser {
    static func noteLinks(in content: String) -> [String] {
        matches(in: content, pattern: #"\[\[([^\[\]]+?)\]\]"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("task:") }
    }

    static func taskReferences(in content: String) -> [String] {
        matches(in: content, pattern: #"\[\[task:(.+?)\]\]"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func matches(in content: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = content as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: content, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }
}
#endif

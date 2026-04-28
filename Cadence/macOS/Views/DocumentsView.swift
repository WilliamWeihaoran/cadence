#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct DocumentsView: View {
    var area: Area? = nil
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var selectedDocID: UUID? = nil
    @Query(sort: \Document.order) private var allDocs: [Document]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    private var docs: [Document] {
        if let area {
            return allDocs.filter { $0.area?.id == area.id }
        } else if let project {
            return allDocs.filter { $0.project?.id == project.id }
        }
        return []
    }

    private var selectedDoc: Document? {
        docs.first { $0.id == selectedDocID }
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
                                exportDocumentAsMarkdown(selectedDoc)
                            }
                            Button("Export PDF") {
                                exportDocumentAsPDF(selectedDoc)
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
                    VStack(spacing: 2) {
                        ForEach(docs) { doc in
                            DocRow(doc: doc, isSelected: selectedDocID == doc.id)
                                .onTapGesture { selectedDocID = doc.id }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteDoc(doc)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(8)
                }

                if docs.isEmpty {
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
            if let doc = selectedDoc {
                VStack(spacing: 0) {
                    NoteReferenceStrip(
                        doc: doc,
                        docs: docs,
                        tasks: tasks,
                        onOpenNote: { selectedDocID = $0.id }
                    )

                    MarkdownEditor(doc: doc)
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
            if selectedDocID == nil { selectedDocID = docs.first?.id }
        }
    }

    private func addDocument() {
        let doc = Document()
        doc.area = area
        doc.project = project
        doc.order = docs.count
        doc.content = defaultDocumentContent(for: doc.title)
        modelContext.insert(doc)
        selectedDocID = doc.id
    }

    private func deleteDoc(_ doc: Document) {
        deleteConfirmationManager.present(
            title: "Delete Note?",
            message: "This will permanently delete \"\(doc.title.isEmpty ? "Untitled" : doc.title)\"."
        ) {
            if selectedDocID == doc.id {
                selectedDocID = docs.first { $0.id != doc.id }?.id
            }
            modelContext.delete(doc)
        }
    }

    private func defaultDocumentContent(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingTitle = trimmed.isEmpty ? "Untitled" : trimmed
        return "# \(headingTitle)\n\n"
    }

    private func exportDocumentAsMarkdown(_ doc: Document) {
        let baseName = doc.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedName = (baseName.isEmpty ? "Untitled Note" : baseName) + ".md"

        presentSavePanel(suggestedName: suggestedName, contentType: .plainText) { url in
            try? doc.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportDocumentAsPDF(_ doc: Document) {
        let baseName = doc.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedName = (baseName.isEmpty ? "Untitled Note" : baseName) + ".pdf"

        presentSavePanel(suggestedName: suggestedName, contentType: .pdf) { url in
            guard let pdfData = renderedPDFData(for: doc) else { return }
            try? pdfData.write(to: url)
        }
    }

    private func presentSavePanel(
        suggestedName: String,
        contentType: UTType,
        onSave: @escaping (URL) -> Void
    ) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [contentType]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = suggestedName

            let save: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let url = panel.url else { return }
                onSave(url)
            }

            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: save)
            } else {
                panel.begin(completionHandler: save)
            }
        }
    }

    private func renderedPDFData(for doc: Document) -> Data? {
        let pageWidth: CGFloat = 612
        let horizontalInset: CGFloat = 42
        let verticalInset: CGFloat = 42
        let contentWidth = pageWidth - (horizontalInset * 2)

        let textStorage = NSTextStorage(string: doc.content)
        let layoutManager = CadenceLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CadenceTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(hex: "#0f1117")
        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.string = doc.content
        MarkdownStylist.apply(to: textView)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = max(ceil(usedRect.height + (verticalInset * 2)), 240)
        textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: documentHeight)

        return textView.dataWithPDF(inside: textView.bounds)
    }
}

// MARK: - Doc Row

private struct DocRow: View {
    @Bindable var doc: Document
    let isSelected: Bool
    @State private var isEditingTitle = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            if isEditingTitle {
                TextField("", text: $doc.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { isEditingTitle = false }
                    .onExitCommand { isEditingTitle = false }
            } else {
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
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

private struct MarkdownEditor: View {
    @Bindable var doc: Document

    var body: some View {
        MarkdownEditorView(text: $doc.content)
            .onChange(of: doc.content) {
                doc.updatedAt = Date()
                syncTitleFromH1()
            }
    }

    private func syncTitleFromH1() {
        // Extract the first H1 line ("# Title") and keep doc.title in sync with it
        let firstLine = doc.content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != doc.title else { return }
        doc.title = h1Text
    }
}

private struct NoteReferenceStrip: View {
    let doc: Document
    let docs: [Document]
    let tasks: [AppTask]
    let onOpenNote: (Document) -> Void

    private var linkedNotes: [Document] {
        let titles = MarkdownReferenceParser.noteLinks(in: doc.content)
        return titles.compactMap { title in
            docs.first {
                $0.id != doc.id &&
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    private var linkedTasks: [AppTask] {
        let titles = MarkdownReferenceParser.taskReferences(in: doc.content)
        return titles.compactMap { title in
            tasks.first {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    private var backlinks: [Document] {
        let currentTitle = doc.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else { return [] }
        return docs.filter { other in
            other.id != doc.id &&
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
                                ReferenceChip(icon: "doc.text", title: linked.title.isEmpty ? "Untitled" : linked.title, tint: Theme.blue)
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
                                ReferenceChip(icon: "arrow.uturn.backward.circle", title: backlink.title.isEmpty ? "Untitled" : backlink.title, tint: Theme.amber)
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

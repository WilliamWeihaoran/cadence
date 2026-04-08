#if os(macOS)
import SwiftUI
import SwiftData

struct DocumentsView: View {
    var area: Area? = nil
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var selectedDocID: UUID? = nil
    @Query(sort: \Document.order) private var allDocs: [Document]

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

    var body: some View {
        HSplitView {
            // Document list
            VStack(spacing: 0) {
                HStack {
                    Text("Documents")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Spacer()
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
                        message: "No documents",
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
                MarkdownEditor(doc: doc)
                    .id(doc.id)
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.dim)
                        Text("Select a document")
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
            title: "Delete Document?",
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
#endif

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

private enum AIReviewPayload: Identifiable {
    case summary(String)
    case taskDrafts([AITaskDraft])

    var id: String {
        switch self {
        case .summary:
            return "summary"
        case .taskDrafts:
            return "taskDrafts"
        }
    }
}

enum NoteActionSupport {
    static func appendSummary(_ summary: String, to note: Note, modelContext: ModelContext?) {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }
        let separator = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        note.content = "\(note.content)\(separator)## AI Summary\n\n\(trimmedSummary)"
        note.updatedAt = Date()
        try? modelContext?.save()
    }

    static func copyMarkdownLink(to note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(NoteReferenceParser.noteReferenceMarkdown(for: note), forType: .string)
    }

    static func move(_ note: Note, toArea area: Area?, modelContext: ModelContext?) {
        note.area = area
        note.project = nil
        note.updatedAt = Date()
        try? modelContext?.save()
    }

    static func move(_ note: Note, toProject project: Project?, modelContext: ModelContext?) {
        note.area = nil
        note.project = project
        note.updatedAt = Date()
        try? modelContext?.save()
    }
}

struct NoteActionMenu: View {
    let note: Note
    var area: Area?
    var project: Project?
    var onAppendSummary: ((String) -> Void)?
    var onDelete: (() -> Void)?

    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @State private var payload: AIReviewPayload?
    @State private var errorMessage: String?
    @State private var isRunning = false

    var body: some View {
        Menu {
            Section {
                Button("Export Markdown") {
                    NoteExportService.export(note, as: .markdown)
                }
                Button("Export PDF") {
                    NoteExportService.export(note, as: .pdf, imageAssets: imageAssets)
                }
                Button("Copy Note Link") {
                    NoteActionSupport.copyMarkdownLink(to: note)
                }
            }
            if note.kind == .list, !areas.isEmpty || !projects.isEmpty {
                Section("Move To") {
                    Button("No List") {
                        NoteActionSupport.move(note, toArea: nil, modelContext: modelContext)
                    }
                    .disabled(note.area == nil && note.project == nil)

                    if !areas.isEmpty {
                        Menu("Areas") {
                            ForEach(areas) { area in
                                Button(area.name) {
                                    NoteActionSupport.move(note, toArea: area, modelContext: modelContext)
                                }
                                .disabled(note.area?.id == area.id)
                            }
                        }
                    }

                    if !projects.isEmpty {
                        Menu("Projects") {
                            ForEach(projects) { project in
                                Button(project.name) {
                                    NoteActionSupport.move(note, toProject: project, modelContext: modelContext)
                                }
                                .disabled(note.project?.id == project.id)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Summarize Note") {
                    runSummary()
                }
                .disabled(!aiSettingsManager.hasAPIKey || isRunning)
                Button("Extract Tasks") {
                    runTaskExtraction()
                }
                .disabled(!aiSettingsManager.hasAPIKey || isRunning)
            }
            if let onDelete {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Text("Delete Note")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("Actions")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.blue.opacity(0.12))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Note actions")
        .sheet(item: $payload) { payload in
            switch payload {
            case .summary(let markdown):
                AISummaryReviewSheet(markdown: markdown) {
                    if let onAppendSummary {
                        onAppendSummary(markdown)
                    } else {
                        NoteActionSupport.appendSummary(markdown, to: note, modelContext: modelContext)
                    }
                    self.payload = nil
                }
            case .taskDrafts(let drafts):
                AITaskDraftReviewSheet(
                    initialDrafts: drafts,
                    area: area,
                    project: project,
                    areas: areas,
                    projects: projects,
                    modelContext: modelContext
                )
            }
        }
        .alert("AI Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runSummary() {
        Task {
            await run {
                let provider = try aiSettingsManager.provider()
                let context = try AIActionService.noteContext(note: note, area: area, project: project)
                payload = .summary(try await provider.summarizeNote(context))
            }
        }
    }

    private func runTaskExtraction() {
        Task {
            await run {
                let provider = try aiSettingsManager.provider()
                let context = try AIActionService.noteContext(note: note, area: area, project: project)
                payload = .taskDrafts(try await provider.extractTasks(from: context))
            }
        }
    }

    @MainActor
    private func run(_ operation: @escaping () async throws -> Void) async {
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            try await operation()
        } catch {
            errorMessage = AIErrorPresenter.message(for: error)
        }
    }
}

private struct AISummaryReviewSheet: View {
    let markdown: String
    let onAppend: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Summary")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
            ScrollView {
                Text(markdown)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Button("Append to Note") {
                    onAppend()
                    dismiss()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Theme.bg)
    }
}

private struct AITaskDraftReviewSheet: View {
    let area: Area?
    let project: Project?
    let areas: [Area]
    let projects: [Project]
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [AITaskDraft]
    @State private var selectedIDs: Set<UUID>
    @State private var statusMessage: String?

    init(
        initialDrafts: [AITaskDraft],
        area: Area?,
        project: Project?,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) {
        self.area = area
        self.project = project
        self.areas = areas
        self.projects = projects
        self.modelContext = modelContext
        _drafts = State(initialValue: initialDrafts)
        _selectedIDs = State(initialValue: Set(initialDrafts.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Task Drafts")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Review each draft before creating anything in Cadence.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            if drafts.isEmpty {
                EmptyStateView(message: "No tasks found", subtitle: "The note did not contain clear action items.", icon: "sparkles")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($drafts) { $draft in
                            AITaskDraftRow(
                                draft: $draft,
                                isSelected: Binding(
                                    get: { selectedIDs.contains(draft.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedIDs.insert(draft.id)
                                        } else {
                                            selectedIDs.remove(draft.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(2)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Button("Create Selected") {
                    createSelected()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedIDs.isEmpty ? Theme.dim : Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
        .background(Theme.bg)
    }

    private func createSelected() {
        do {
            let created = try AIActionService.applyTaskDrafts(
                drafts,
                selectedIDs: selectedIDs,
                area: area,
                project: project,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
            statusMessage = "Created \(created.count) task\(created.count == 1 ? "" : "s")."
            dismiss()
        } catch {
            statusMessage = AIErrorPresenter.message(for: error)
        }
    }
}

private struct AITaskDraftRow: View {
    @Binding var draft: AITaskDraft
    @Binding var isSelected: Bool

    private var validation: AITaskDraftValidation {
        AIActionService.validation(for: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                TextField("Task title", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            HStack(spacing: 8) {
                TextField("Priority", text: $draft.priority)
                    .frame(width: 90)
                TextField("Due yyyy-MM-dd", text: $draft.dueDate)
                    .frame(width: 120)
                TextField("Do yyyy-MM-dd", text: $draft.scheduledDate)
                    .frame(width: 120)
                TextField("Section", text: $draft.sectionName)
                    .frame(width: 110)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text)

            if !validation.isValid {
                Text(validation.errors.joined(separator: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(validation.isValid ? Theme.borderSubtle : Theme.red.opacity(0.45), lineWidth: 1)
        }
    }
}
#endif

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
    @State private var payload: AIReviewPayload?
    @State private var errorMessage: String?
    @State private var isRunning = false
    @State private var showsPicker = false
    @State private var isMoveSectionExpanded = false

    private var showsMoveDestinationSection: Bool {
        note.kind == .list && (!areas.isEmpty || !projects.isEmpty)
    }

    private var canRunAI: Bool {
        aiSettingsManager.hasAPIKey && !isRunning
    }

    var body: some View {
        actionButton
            .overlay(alignment: .topTrailing) {
                if showsPicker {
                    pickerCard
                }
            }
        .zIndex(showsPicker ? 1_000 : 0)
        .sheet(item: $payload, content: reviewSheet)
        .alert("AI Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var actionButton: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                showsPicker.toggle()
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
                Image(systemName: showsPicker ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.blue.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .fixedSize()
        .help("Note actions")
    }

    private var pickerCard: some View {
        NoteActionPickerCard {
            exportSection
            moveDestinationSection
            Divider().background(Theme.borderSubtle.opacity(0.9))
            aiSection
            deleteSection
        }
        .offset(y: 42)
        .zIndex(1_000)
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
    }

    private var exportSection: some View {
        NoteActionPickerSection(title: "Export") {
            NoteActionPickerRow(icon: "doc.text", title: "Export Markdown") {
                dismissPicker()
                NoteExportService.export(note, as: .markdown)
            }
            NoteActionPickerRow(icon: "doc.richtext", title: "Export PDF") {
                dismissPicker()
                NoteExportService.export(note, as: .pdf, imageAssets: imageAssetsReferencedByNote())
            }
            NoteActionPickerRow(icon: "link", title: "Copy Note Link") {
                dismissPicker()
                NoteActionSupport.copyMarkdownLink(to: note)
            }
        }
    }

    @ViewBuilder
    private var moveDestinationSection: some View {
        if showsMoveDestinationSection {
            Divider().background(Theme.borderSubtle.opacity(0.9))

            NoteActionPickerSection(title: "Organize") {
                moveNoteRow
                expandedMoveDestinations
            }
        }
    }

    private var moveNoteRow: some View {
        NoteActionPickerRow(
            icon: "tray.full",
            title: "Move Note",
            subtitle: "Change which list owns this note",
            trailingSymbol: isMoveSectionExpanded ? "chevron.up" : "chevron.down"
        ) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                isMoveSectionExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var expandedMoveDestinations: some View {
        if isMoveSectionExpanded {
            VStack(alignment: .leading, spacing: 6) {
                noListDestination
                areaDestinations
                projectDestinations
            }
            .padding(.top, 2)
            .padding(.leading, 8)
        }
    }

    private var noListDestination: some View {
        NoteActionDestinationRow(
            title: "No List",
            subtitle: "Keep it loose in notes",
            isSelected: note.area == nil && note.project == nil
        ) {
            dismissPicker()
            NoteActionSupport.move(note, toArea: nil, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private var areaDestinations: some View {
        if !areas.isEmpty {
            NoteActionSubsectionLabel(title: "Areas")
            ForEach(areas) { area in
                NoteActionDestinationRow(
                    title: area.name,
                    subtitle: "Area",
                    isSelected: note.area?.id == area.id
                ) {
                    dismissPicker()
                    NoteActionSupport.move(note, toArea: area, modelContext: modelContext)
                }
            }
        }
    }

    @ViewBuilder
    private var projectDestinations: some View {
        if !projects.isEmpty {
            NoteActionSubsectionLabel(title: "Projects")
            ForEach(projects) { project in
                NoteActionDestinationRow(
                    title: project.name,
                    subtitle: "Project",
                    isSelected: note.project?.id == project.id
                ) {
                    dismissPicker()
                    NoteActionSupport.move(note, toProject: project, modelContext: modelContext)
                }
            }
        }
    }

    private var aiSection: some View {
        NoteActionPickerSection(title: "AI") {
            NoteActionPickerRow(
                icon: "text.magnifyingglass",
                title: "Summarize Note",
                subtitle: aiSettingsManager.hasAPIKey ? "Generate a concise recap" : "Add an API key to enable AI",
                isEnabled: canRunAI
            ) {
                dismissPicker()
                runSummary()
            }
            NoteActionPickerRow(
                icon: "sparkles.rectangle.stack",
                title: "Extract Tasks",
                subtitle: aiSettingsManager.hasAPIKey ? "Turn notes into task drafts" : "Add an API key to enable AI",
                isEnabled: canRunAI
            ) {
                dismissPicker()
                runTaskExtraction()
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if let onDelete {
            Divider().background(Theme.borderSubtle.opacity(0.9))

            NoteActionPickerSection(title: "Danger") {
                NoteActionPickerRow(
                    icon: "trash",
                    title: "Delete Note",
                    tint: Theme.red
                ) {
                    dismissPicker()
                    onDelete()
                }
            }
        }
    }

    @ViewBuilder
    private func reviewSheet(for payload: AIReviewPayload) -> some View {
        switch payload {
        case .summary(let markdown):
            AISummaryReviewSheet(markdown: markdown) {
                appendSummary(markdown)
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

    private func appendSummary(_ markdown: String) {
        if let onAppendSummary {
            onAppendSummary(markdown)
        } else {
            NoteActionSupport.appendSummary(markdown, to: note, modelContext: modelContext)
        }
    }

    private func dismissPicker() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            showsPicker = false
        }
    }

    private func imageAssetsReferencedByNote() -> [MarkdownImageAsset] {
        let referencedIDs = MarkdownImageAssetService.referencedIDs(in: note.content)
        guard !referencedIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MarkdownImageAsset>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { referencedIDs.contains($0.id) }
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

private enum NoteActionPickerMetrics {
    static let width: CGFloat = 280
    static let maxHeight: CGFloat = 430
}

private struct NoteActionPickerCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: NoteActionPickerMetrics.width)
        .frame(maxHeight: NoteActionPickerMetrics.maxHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(0.98))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .shadow(color: Theme.overlayCardShadow, radius: 22, x: 0, y: 14)
    }
}

private struct NoteActionPickerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
                .padding(.horizontal, 4)
            content
        }
    }
}

private struct NoteActionSubsectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.7)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }
}

private struct NoteActionPickerRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = Theme.text
    var isEnabled: Bool = true
    var trailingSymbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? tint : Theme.dim)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEnabled ? tint : Theme.dim)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isEnabled ? Theme.dim : Theme.dim.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, subtitle == nil ? 8 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
        .disabled(!isEnabled)
        .cadenceHoverHighlight(
            cornerRadius: 12,
            fillColor: isEnabled ? Theme.blue.opacity(0.08) : Color.clear,
            strokeColor: isEnabled ? Theme.blue.opacity(0.12) : Color.clear
        )
    }
}

private struct NoteActionDestinationRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        NoteActionPickerRow(
            icon: isSelected ? "checkmark.circle.fill" : "circle",
            title: title,
            subtitle: subtitle,
            tint: isSelected ? Theme.blue : Theme.text,
            trailingSymbol: isSelected ? "checkmark" : nil
        ) {
            action()
        }
    }
}

#endif

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

/// Which page of the Actions popover is showing.
///
/// Export and Move are drill-down submenus rather than expand-in-place sections: expanding them
/// inline pushed everything below out of view, and inside a popover that is the difference
/// between a menu and a scrolling list.
private enum NoteActionPage {
    case root
    case templates
    case export
    case move
}

struct NoteActionMenu: View {
    let note: Note
    var area: Area?
    var project: Project?
    /// Templates for this note's kind. Empty where the caller has no template story — the "Start
    /// With" row then does not render at all.
    var templates: [NoteTemplate] = []
    var onApplyTemplate: ((NoteTemplate) -> Void)?
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
    @State private var page: NoteActionPage = .root

    private var showsMoveDestinationSection: Bool {
        note.kind == .list && (!areas.isEmpty || !projects.isEmpty)
    }

    private var canRunAI: Bool {
        aiSettingsManager.hasAPIKey && !isRunning
    }

    var body: some View {
        actionButton
            // A real popover, not a card overlaid on the trigger. The old inline card was
            // positioned with `.offset(y: 42)` inside the note header, so the header's bounds
            // squeezed and clipped it; a popover is its own window and cannot be.
            .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
                NoteActionPickerCard {
                    switch page {
                    case .root: rootPage
                    case .templates: templatesPage
                    case .export: exportPage
                    case .move: movePage
                    }
                }
            }
            .onChange(of: showsPicker) { _, isShowing in
                if !isShowing { page = .root }
            }
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
        CadenceQuietPillButton(state: showsPicker ? .active : .resting, action: { showsPicker.toggle() }) {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("Actions")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.muted)
        }
        .fixedSize()
        .help("Note actions")
    }

    // MARK: - Pages

    private var showsTemplatesSection: Bool {
        onApplyTemplate != nil && !templates.isEmpty
    }

    @ViewBuilder
    private var rootPage: some View {
        // Templates used to be a chip strip pinned above every note. They are one of the things you
        // do *to* a note, so this is where they belong — and unlike the strip, this route is still
        // there after the note has something in it, where applying a template appends rather than
        // fills.
        if showsTemplatesSection {
            NoteActionPickerRow(icon: "doc.on.doc", title: "Start With", trailingSymbol: "chevron.right") {
                page = .templates
            }
        }

        NoteActionPickerRow(icon: "square.and.arrow.up", title: "Export", trailingSymbol: "chevron.right") {
            page = .export
        }

        if showsMoveDestinationSection {
            NoteActionPickerRow(icon: "tray.full", title: "Move Note", trailingSymbol: "chevron.right") {
                page = .move
            }
        }

        NoteActionPickerDivider()

        aiSection

        if onDelete != nil {
            NoteActionPickerDivider()
            deleteSection
        }
    }

    @ViewBuilder
    private var templatesPage: some View {
        NoteActionSubmenuHeader(title: "Start With") { page = .root }
        ForEach(templates) { template in
            NoteActionPickerRow(icon: "doc.text", title: template.title, subtitle: template.subtitle) {
                dismissPicker()
                onApplyTemplate?(template)
            }
        }
    }

    @ViewBuilder
    private var exportPage: some View {
        NoteActionSubmenuHeader(title: "Export") { page = .root }
        NoteActionPickerRow(icon: "doc.text", title: "Export Markdown") {
            dismissPicker()
            NoteExportService.export(note, as: .markdown)
        }
        NoteActionPickerRow(icon: "doc.richtext", title: "Export PDF") {
            dismissPicker()
            NoteExportService.export(note, as: .pdf, imageAssets: imageAssetsReferencedByNote())
        }
    }

    @ViewBuilder
    private var movePage: some View {
        NoteActionSubmenuHeader(title: "Move Note") { page = .root }
        noListDestination
        areaDestinations
        projectDestinations
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

    @ViewBuilder
    private var aiSection: some View {
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

    @ViewBuilder
    private var deleteSection: some View {
        if let onDelete {
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
        showsPicker = false
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
    static let width: CGFloat = 260
    static let maxHeight: CGFloat = 430
}

/// The popover's content shell. No shadow or corner clipping of its own — the popover window
/// supplies both; drawing a second card inside one is how the old inline version ended up looking
/// like a card floating on a card.
private struct NoteActionPickerCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: NoteActionPickerMetrics.width)
        .frame(maxHeight: NoteActionPickerMetrics.maxHeight, alignment: .top)
        .background(Theme.surface)
    }
}

private struct NoteActionPickerDivider: View {
    var body: some View {
        Divider()
            .background(Theme.borderSubtle)
            .padding(.vertical, 4)
    }
}

/// Back bar for a drill-down submenu page.
private struct NoteActionSubmenuHeader: View {
    let title: String
    let onBack: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isHovered ? Theme.surfaceHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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

/// One row of the Actions popover.
///
/// Exactly one hover layer at one radius. This previously stacked `.cadencePlain`'s blue fill at
/// radius 10 under `.cadenceHoverHighlight`'s blue fill at radius 12, which is why the highlight
/// had a visible double edge.
private struct NoteActionPickerRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = Theme.text
    var isEnabled: Bool = true
    var trailingSymbol: String? = nil
    let action: () -> Void

    @State private var isHovered = false

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
            .padding(.vertical, subtitle == nil ? 7 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isHovered && isEnabled ? Theme.surfaceHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
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

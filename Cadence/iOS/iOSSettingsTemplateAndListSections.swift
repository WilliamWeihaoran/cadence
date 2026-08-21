#if os(iOS)
import SwiftUI

struct iOSTemplatesSettingsSection: View {
    @Binding var templateOverridesRaw: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTemplateID = "project-brief"
    @State private var bodyEditorFocused = false
    // Title and description are stored trimmed. Binding a text field straight at storage means the
    // getter hands back the trimmed value on the next render, so a space typed at the end of the
    // title was undone before the next character arrived and "Daily Plan" + " " + "N" came out as
    // "Daily PlanN". These hold what the user is typing; storage is written from them.
    @State private var titleDraft = ""
    @State private var subtitleDraft = ""

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.editableTemplates(overridesRaw: templateOverridesRaw)
    }

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Note Templates")

            iOSSettingsCard {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: iOSEditorSheetMetrics.groupSpacing) {
                        templateList
                            .frame(width: 260)

                        Rectangle()
                            .fill(Theme.borderSubtle)
                            .frame(width: 1)

                        templateEditor
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                        templatePicker
                        templateEditor
                    }
                }
            }

            iOSSettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.blue)

                    Text("Templates affect future insertions only. Existing notes keep their current content.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: selectedTemplateID) { _, _ in loadDrafts() }
    }

    private var templatePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(templates) { template in
                    iOSTemplateSettingsChip(
                        template: template,
                        isSelected: selectedTemplateID == template.id,
                        isCustomized: NoteTemplateLibrary.isCustomized(template, overridesRaw: templateOverridesRaw),
                        action: { selectedTemplateID = template.id }
                    )
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(templates) { template in
                iOSTemplateSettingsRow(
                    template: template,
                    isSelected: selectedTemplateID == template.id,
                    isCustomized: NoteTemplateLibrary.isCustomized(template, overridesRaw: templateOverridesRaw),
                    noteKinds: NoteTemplateLibrary.noteKinds(containing: template),
                    action: { selectedTemplateID = template.id }
                )
            }
        }
    }

    @ViewBuilder
    private var templateEditor: some View {
        if let selectedTemplate {
            VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedTemplate.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        Text(selectedTemplate.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw) {
                        iOSMetaChip(label: "Customized", color: Theme.blue)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(NoteTemplateLibrary.noteKinds(containing: selectedTemplate), id: \.rawValue) { kind in
                        iOSMetaChip(label: kind.templateDisplayName, color: Theme.muted)
                    }
                }

                iOSSettingsField(title: "Title") {
                    TextField("Template title", text: titleBinding)
                        .textInputAutocapitalization(.words)
                }

                iOSSettingsField(title: "Description") {
                    TextField("Short sidebar description", text: subtitleBinding)
                }

                iOSTemplateBodyEditor(
                    isFocused: $bodyEditorFocused,
                    text: bodyBinding(for: selectedTemplate)
                )

                HStack {
                    Spacer()

                    iOSActionButton(
                        title: "Reset Template",
                        systemImage: "arrow.counterclockwise",
                        role: .ghost,
                        size: .compact,
                        isDisabled: !NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw),
                        action: resetSelectedTemplate
                    )
                }
            }
        } else {
            iOSSettingsEmptyInlineRow(
                systemImage: "doc.text",
                title: "No templates available",
                subtitle: "Template definitions could not be loaded."
            )
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { titleDraft },
            set: { newValue in
                titleDraft = newValue
                commitDrafts()
            }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: { subtitleDraft },
            set: { newValue in
                subtitleDraft = newValue
                commitDrafts()
            }
        )
    }

    /// The body is not trimmed on the way in, so it round-trips unchanged and needs no draft.
    private func bodyBinding(for template: NoteTemplate) -> Binding<String> {
        Binding(
            get: { selectedTemplate?.body ?? template.body },
            set: { updateSelectedTemplate(body: $0) }
        )
    }

    private func loadDrafts() {
        guard let selectedTemplate else { return }
        titleDraft = selectedTemplate.title
        subtitleDraft = selectedTemplate.subtitle
    }

    private func commitDrafts() {
        updateSelectedTemplate(body: selectedTemplate?.body ?? "")
    }

    private func updateSelectedTemplate(body: String) {
        guard let selectedTemplate else { return }
        templateOverridesRaw = NoteTemplateLibrary.setOverride(
            for: selectedTemplate.id,
            title: titleDraft,
            subtitle: subtitleDraft,
            body: body,
            in: templateOverridesRaw
        )
    }

    private func resetSelectedTemplate() {
        guard let selectedTemplate else { return }
        templateOverridesRaw = NoteTemplateLibrary.resetOverride(for: selectedTemplate.id, in: templateOverridesRaw)
        loadDrafts()
    }
}

struct iOSListsLifecycleSettingsSection: View {
    let completedAreas: [Area]
    let archivedAreas: [Area]
    let completedProjects: [Project]
    let archivedProjects: [Project]
    let onReopenArea: (Area) -> Void
    let onReopenProject: (Project) -> Void
    /// Delete is here for the same reason macOS's Settings → Lists has it: a completed or archived
    /// list is off the Lists page, so this is the only screen that can still reach it.
    let onDeleteArea: (Area) -> Void
    let onDeleteProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if completedAreas.isEmpty && archivedAreas.isEmpty && completedProjects.isEmpty && archivedProjects.isEmpty {
                CadenceSettingsSectionLabel(text: "Inactive Lists")
                iOSSettingsCard {
                    iOSSettingsEmptyInlineRow(
                        systemImage: "archivebox",
                        title: "No completed or archived lists",
                        subtitle: "Areas and projects you complete or archive will appear here."
                    )
                }
            } else {
                if !completedAreas.isEmpty {
                    CadenceSettingsSectionLabel(text: "Completed Areas")
                    lifecycleCard(areas: completedAreas)
                }
                if !archivedAreas.isEmpty {
                    CadenceSettingsSectionLabel(text: "Archived Areas")
                    lifecycleCard(areas: archivedAreas)
                }
                if !completedProjects.isEmpty {
                    CadenceSettingsSectionLabel(text: "Completed Projects")
                    lifecycleCard(projects: completedProjects)
                }
                if !archivedProjects.isEmpty {
                    CadenceSettingsSectionLabel(text: "Archived Projects")
                    lifecycleCard(projects: archivedProjects)
                }
            }
        }
    }

    private func lifecycleCard(areas: [Area] = [], projects: [Project] = []) -> some View {
        iOSSettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    iOSListLifecycleSettingsRow(
                        icon: area.icon,
                        title: area.name.isEmpty ? "Untitled Area" : area.name,
                        subtitle: area.context?.name ?? "No context",
                        color: Color(hex: area.colorHex),
                        statusLabel: area.isDone ? "Completed" : "Archived",
                        primaryLabel: area.isDone ? "Reopen" : "Unarchive",
                        primaryAction: { onReopenArea(area) },
                        deleteAction: { onDeleteArea(area) }
                    )

                    if index < areas.count - 1 || !projects.isEmpty {
                        iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                    }
                }

                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    iOSListLifecycleSettingsRow(
                        icon: project.icon,
                        title: project.name.isEmpty ? "Untitled Project" : project.name,
                        subtitle: projectSubtitle(project),
                        color: Color(hex: project.colorHex),
                        statusLabel: project.isDone ? "Completed" : "Archived",
                        primaryLabel: project.isDone ? "Reopen" : "Unarchive",
                        primaryAction: { onReopenProject(project) },
                        deleteAction: { onDeleteProject(project) }
                    )

                    if index < projects.count - 1 {
                        iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                    }
                }
            }
        }
    }

    private func projectSubtitle(_ project: Project) -> String {
        let parts = [project.context?.name, project.area?.name].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "No parent list" : parts.joined(separator: " • ")
    }
}

struct iOSAISettingsSection: View {
    let aiSettingsManager: AISettingsManager
    @Binding var aiAPIKeyDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "OpenAI")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top, spacing: 13) {
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .fill((aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim).opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim)
                            }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("OpenAI API Key")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            Text("Stored in Keychain. Cadence sends selected note content to OpenAI only when you run an AI action.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)

                            if let statusMessage = aiSettingsManager.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    iOSRowDivider()

                    VStack(alignment: .leading, spacing: 9) {
                        iOSAISettingsDisclosureRow(
                            icon: "checkmark.shield.fill",
                            title: "User initiated",
                            detail: "AI requests run only after you choose an AI command."
                        )
                        iOSAISettingsDisclosureRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Selected note content",
                            detail: "The note title, note text, and related list names may be sent for the requested action."
                        )
                        iOSAISettingsDisclosureRow(
                            icon: "key.fill",
                            title: "Your API key",
                            detail: "The key is stored in Keychain and can be removed here at any time."
                        )
                    }

                    iOSRowDivider()

                    iOSSettingsField(title: "API Key") {
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    iOSSettingsField(title: "Model ID") {
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            iOSActionButton(
                                title: "Save Key",
                                systemImage: "key.fill",
                                role: .primary,
                                size: .compact,
                                fullWidth: true,
                                isDisabled: aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                action: saveAPIKey
                            )

                            iOSActionButton(
                                title: aiSettingsManager.isTestingConnection ? "Testing" : "Test",
                                systemImage: "network",
                                role: .secondary,
                                size: .compact,
                                tint: aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim,
                                fullWidth: true,
                                isDisabled: !aiSettingsManager.hasAPIKey || aiSettingsManager.isTestingConnection
                            ) {
                                Task { await aiSettingsManager.testConnection() }
                            }
                        }

                        if aiSettingsManager.hasAPIKey {
                            iOSActionButton(
                                title: "Delete API Key",
                                systemImage: "trash",
                                role: .destructive,
                                size: .compact,
                                fullWidth: true,
                                action: removeAPIKey
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            aiSettingsManager.refreshKeyStatus()
        }
    }

    private func saveAPIKey() {
        do {
            try aiSettingsManager.saveAPIKey(aiAPIKeyDraft)
            aiAPIKeyDraft = ""
        } catch {
            aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
        }
    }

    private func removeAPIKey() {
        do {
            try aiSettingsManager.removeAPIKey()
        } catch {
            aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
        }
    }
}

private struct iOSTemplateSettingsRow: View {
    let template: NoteTemplate
    let isSelected: Bool
    let isCustomized: Bool
    let noteKinds: [NoteKind]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    iOSTemplateIcon(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(template.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                                .lineLimit(1)

                            if isCustomized {
                                Circle()
                                    .fill(Theme.blue)
                                    .frame(width: 5, height: 5)
                            }
                        }

                        Text(template.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    ForEach(noteKinds, id: \.rawValue) { kind in
                        iOSMetaChip(label: kind.templateDisplayName, color: Theme.muted)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: iOSSettingsMetrics.minimumTapTarget, alignment: .leading)
            // One selection layer, one radius. It used to be a tinted fill *and* a tinted
            // stroke, which read as two different selected states stacked on each other.
            .background(isSelected ? Theme.surfaceHighlight : Theme.surfaceElevated.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }
}

private struct iOSTemplateSettingsChip: View {
    let template: NoteTemplate
    let isSelected: Bool
    let isCustomized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .semibold))

                Text(template.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                if isCustomized {
                    Circle()
                        .fill(Theme.blue)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.muted)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isSelected ? Theme.surfaceHighlight : Theme.surfaceElevated.opacity(0.72))
            .clipShape(Capsule())
            .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }
}

private struct iOSTemplateIcon: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
            .fill((isSelected ? Theme.blue : Theme.dim).opacity(isSelected ? 0.18 : 0.12))
            .frame(width: iOSSettingsMetrics.glyphSlot, height: iOSSettingsMetrics.glyphSlot)
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            }
    }
}

private struct iOSTemplateBodyEditor: View {
    @Binding var isFocused: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BODY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .tracking(0.8)

            iOSMarkdownEditingSurface(
                text: $text,
                isFocused: $isFocused,
                placeholder: "Write the reusable note template...",
                allowsEmbeddedTaskCreation: false
            )
            .iOSMarkdownWell()
        }
    }
}

private struct iOSListLifecycleSettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let statusLabel: String
    let primaryLabel: String
    let primaryAction: () -> Void
    /// Requests the delete only — the confirmation and the cascade are `iOSSettingsView`'s, through
    /// the one `iOSListDeletion` modifier.
    let deleteAction: () -> Void

    private var statusTint: Color {
        statusLabel == "Completed" ? Theme.green : Theme.amber
    }

    var body: some View {
        HStack(alignment: .center, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: icon,
                color: color,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    iOSMetaChip(label: statusLabel, color: statusTint)
                }

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            iOSActionButton(
                title: primaryLabel,
                role: .secondary,
                size: .compact,
                action: primaryAction
            )

            iOSActionButton(
                title: "Delete",
                role: .destructive,
                size: .compact,
                action: deleteAction
            )
        }
        .padding(.vertical, 6)
    }
}

private struct iOSAISettingsDisclosureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct iOSSettingsEmptyInlineRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: iOSSettingsMetrics.glyphSlot, height: iOSSettingsMetrics.glyphSlot)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
#endif

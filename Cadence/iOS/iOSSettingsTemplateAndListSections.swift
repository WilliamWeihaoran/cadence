#if os(iOS)
import SwiftUI

struct iOSTemplatesSettingsSection: View {
    @Binding var templateOverridesRaw: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTemplateID = "project-brief"
    @State private var bodyEditorFocused = false
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var bodyEditorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue

    private var bodyEditorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $bodyEditorModeRaw)
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.editableTemplates(overridesRaw: templateOverridesRaw)
    }

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Note Templates")

            CadenceSettingsCard {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 14) {
                        templateList
                            .frame(width: 260)

                        Divider().background(Theme.borderSubtle)

                        templateEditor
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        templatePicker
                        templateEditor
                    }
                }
            }

            CadenceSettingsCard {
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
            VStack(alignment: .leading, spacing: 14) {
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
                        Text("Customized")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    ForEach(NoteTemplateLibrary.noteKinds(containing: selectedTemplate), id: \.rawValue) { kind in
                        Text(kind.templateDisplayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceElevated.opacity(0.76))
                            .clipShape(Capsule())
                    }
                }

                iOSTemplateEditorField(title: "Title") {
                    TextField("Template title", text: titleBinding(for: selectedTemplate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.words)
                }

                iOSTemplateEditorField(title: "Description") {
                    TextField("Short sidebar description", text: subtitleBinding(for: selectedTemplate))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }

                iOSTemplateBodyEditor(
                    mode: bodyEditorModeBinding,
                    isFocused: $bodyEditorFocused,
                    text: bodyBinding(for: selectedTemplate)
                )

                HStack {
                    Spacer()

                    Button {
                        resetSelectedTemplate()
                    } label: {
                        Label("Reset Template", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.dim)
                    .disabled(!NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw))
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

    private func titleBinding(for template: NoteTemplate) -> Binding<String> {
        Binding(
            get: { selectedTemplate?.title ?? template.title },
            set: { updateSelectedTemplate(title: $0, subtitle: selectedTemplate?.subtitle ?? template.subtitle, body: selectedTemplate?.body ?? template.body) }
        )
    }

    private func subtitleBinding(for template: NoteTemplate) -> Binding<String> {
        Binding(
            get: { selectedTemplate?.subtitle ?? template.subtitle },
            set: { updateSelectedTemplate(title: selectedTemplate?.title ?? template.title, subtitle: $0, body: selectedTemplate?.body ?? template.body) }
        )
    }

    private func bodyBinding(for template: NoteTemplate) -> Binding<String> {
        Binding(
            get: { selectedTemplate?.body ?? template.body },
            set: { updateSelectedTemplate(title: selectedTemplate?.title ?? template.title, subtitle: selectedTemplate?.subtitle ?? template.subtitle, body: $0) }
        )
    }

    private func updateSelectedTemplate(title: String, subtitle: String, body: String) {
        guard let selectedTemplate else { return }
        templateOverridesRaw = NoteTemplateLibrary.setOverride(
            for: selectedTemplate.id,
            title: title,
            subtitle: subtitle,
            body: body,
            in: templateOverridesRaw
        )
    }

    private func resetSelectedTemplate() {
        guard let selectedTemplate else { return }
        templateOverridesRaw = NoteTemplateLibrary.resetOverride(for: selectedTemplate.id, in: templateOverridesRaw)
    }
}

struct iOSListsLifecycleSettingsSection: View {
    let completedAreas: [Area]
    let archivedAreas: [Area]
    let completedProjects: [Project]
    let archivedProjects: [Project]
    let onReopenArea: (Area) -> Void
    let onReopenProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if completedAreas.isEmpty && archivedAreas.isEmpty && completedProjects.isEmpty && archivedProjects.isEmpty {
                CadenceSettingsSectionLabel(text: "Inactive Lists")
                CadenceSettingsCard {
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
        CadenceSettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    iOSListLifecycleSettingsRow(
                        icon: area.icon,
                        title: area.name.isEmpty ? "Untitled Area" : area.name,
                        subtitle: area.context?.name ?? "No context",
                        color: Color(hex: area.colorHex),
                        statusLabel: area.isDone ? "Completed" : "Archived",
                        primaryLabel: area.isDone ? "Reopen" : "Unarchive",
                        primaryAction: { onReopenArea(area) }
                    )

                    if index < areas.count - 1 || !projects.isEmpty {
                        Divider().background(Theme.borderSubtle).padding(.leading, 42)
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
                        primaryAction: { onReopenProject(project) }
                    )

                    if index < projects.count - 1 {
                        Divider().background(Theme.borderSubtle).padding(.leading, 42)
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

            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top, spacing: 13) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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

                    Divider().background(Theme.borderSubtle)

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

                    Divider().background(Theme.borderSubtle)

                    iOSTemplateEditorField(title: "API Key") {
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }

                    iOSTemplateEditorField(title: "Model ID") {
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                saveAPIKey()
                            } label: {
                                Label("Save Key", systemImage: "key.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.blue)
                            .disabled(aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                Task { await aiSettingsManager.testConnection() }
                            } label: {
                                Label(aiSettingsManager.isTestingConnection ? "Testing" : "Test", systemImage: "network")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim)
                            .disabled(!aiSettingsManager.hasAPIKey || aiSettingsManager.isTestingConnection)
                        }

                        if aiSettingsManager.hasAPIKey {
                            Button(role: .destructive) {
                                removeAPIKey()
                            } label: {
                                Label("Delete API Key", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.red)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
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
                        Text(kind.templateDisplayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surfaceElevated.opacity(0.72))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.1) : Theme.surfaceElevated.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Theme.blue.opacity(0.42) : Theme.borderSubtle.opacity(0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.blue.opacity(0.18) : Theme.surfaceElevated.opacity(0.72))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Theme.blue.opacity(0.46) : Theme.borderSubtle.opacity(0.58), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSTemplateIcon: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill((isSelected ? Theme.blue : Theme.dim).opacity(isSelected ? 0.18 : 0.12))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            }
    }
}

private struct iOSTemplateBodyEditor: View {
    @Binding var mode: iOSMarkdownEditorMode
    @Binding var isFocused: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Text("BODY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .tracking(0.8)

                Spacer(minLength: 0)

                iOSMarkdownModePicker(mode: $mode, compact: true)
            }

            iOSMarkdownEditingSurface(
                text: $text,
                isFocused: $isFocused,
                mode: $mode,
                placeholder: "Write the reusable note template...",
                allowsEmbeddedTaskCreation: false
            )
            .frame(minHeight: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.borderSubtle.opacity(0.74), lineWidth: 1)
            }
        }
    }
}

private struct iOSTemplateEditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)

            content
                .padding(10)
                .background(Theme.bg.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.75), lineWidth: 1)
                }
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(statusLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(statusLabel == "Completed" ? Theme.green : Theme.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background((statusLabel == "Completed" ? Theme.green : Theme.amber).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button(primaryLabel, action: primaryAction)
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
        }
        .padding(.vertical, 10)
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
                .frame(width: 32, height: 32)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
#endif

#if os(macOS)
import SwiftUI

struct SettingsTemplatesSection: View {
    @Binding var templateOverridesRaw: String
    @State private var selectedTemplateID = "project-brief"

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.editableTemplates(overridesRaw: templateOverridesRaw)
    }

    private var selectedTemplate: NoteTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Note Templates")

            SettingsCard {
                HStack(alignment: .top, spacing: 16) {
                    templateList
                        .frame(width: 230)

                    Divider()
                        .background(Theme.borderSubtle)

                    templateEditor
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                    Text("Templates appear in the note sidebar for matching note types. Editing a template changes future insertions only; existing notes stay untouched.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(templates) { template in
                TemplateSettingsRow(
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
                    Text(selectedTemplate.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    if NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw) {
                        Text("Customized")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)

                    SettingsActionButton(tone: .tinted(Theme.dim), action: resetSelectedTemplate) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw))
                    .opacity(NoteTemplateLibrary.isCustomized(selectedTemplate, overridesRaw: templateOverridesRaw) ? 1 : 0.45)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TemplateEditorField(title: "Title") {
                        TextField("Template title", text: titleBinding(for: selectedTemplate))
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }

                    TemplateEditorField(title: "Description") {
                        TextField("Short sidebar description", text: subtitleBinding(for: selectedTemplate))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }

                    TemplateEditorField(title: "Body") {
                        TextEditor(text: bodyBinding(for: selectedTemplate))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 280)
                    }
                }
            }
        } else {
            Text("No templates available")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
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

private struct TemplateSettingsRow: View {
    let template: NoteTemplate
    let isSelected: Bool
    let isCustomized: Bool
    let noteKinds: [NoteKind]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((isSelected ? Theme.blue : Theme.dim).opacity(isSelected ? 0.18 : 0.12))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(template.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                                .lineLimit(1)
                            if isCustomized {
                                Circle()
                                    .fill(Theme.blue)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        Text(template.subtitle)
                            .font(.system(size: 10))
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
        .buttonStyle(.cadencePlain)
    }
}

private struct TemplateEditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
#endif

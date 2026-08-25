#if os(macOS)
import SwiftUI

struct SettingsTemplatesSection: View {
    @Binding var templateOverridesRaw: String
    /// The width the card's own content was handed. The settings rail, its divider, the detail
    /// column's padding and the card's inset take 333pt off the pane before this stack sees
    /// anything, so a 960pt window with the stored 264pt sidebar hands it 363 — of which the fixed
    /// chooser and the two gaps took 263, leaving the editor 100. Zero until the first measurement
    /// lands; see `CadenceSettingsTemplatesCardLayout.layout`.
    @State private var cardContentWidth: CGFloat = 0
    @State private var selectedTemplateID = "project-brief"
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

    /// One column or two. macOS has no size class, so width is the only input — and it is an input
    /// this card never had: it split unconditionally, however little was left for the editor.
    private var cardLayout: CadenceSettingsCardLayout {
        CadenceSettingsTemplatesCardLayout.layout(
            isRegularWidth: true,
            hostWidth: cardContentWidth,
            isDesktop: true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Note Templates")

            SettingsCard {
                templateCardContent
                    // Measured, not wrapped — the same call the iOS card and `iOSNotesView` make,
                    // and for the same reason: a `GeometryReader` here would become the layout
                    // container for a stack that sizes itself from what is left over.
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        cardContentWidth = newWidth
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
        .onAppear(perform: loadDrafts)
        .onChange(of: selectedTemplateID) { _, _ in loadDrafts() }
    }

    /// **The one-column form macOS did not have.** iOS could be gated to a fallback that already
    /// ships on the phone; here it had to be written, and it is written as the same rows stacked
    /// above the editor rather than as a new horizontal chip strip. A chip strip would mean a macOS
    /// near-copy of `iOSTemplateSettingsChip` for a layout reached only by narrowing the window
    /// below ~1180pt, and the standing rule is one shared component over near-copies. `templateList`
    /// is reused verbatim; its rows are already `maxWidth: .infinity`, so they simply run wide.
    @ViewBuilder
    private var templateCardContent: some View {
        switch cardLayout {
        case .twoColumn:
            HStack(alignment: .top, spacing: CadenceSettingsTemplatesCardLayout.columnSpacing) {
                templateList
                    .frame(width: CadenceSettingsTemplatesCardLayout.chooserWidth(isDesktop: true))

                Divider()
                    .background(Theme.borderSubtle)

                templateEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .oneColumn:
            VStack(alignment: .leading, spacing: 16) {
                templateList

                Divider()
                    .background(Theme.borderSubtle)

                templateEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        TextField("Template title", text: titleBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }

                    TemplateEditorField(title: "Description") {
                        TextField("Short sidebar description", text: subtitleBinding)
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
            SectionEyebrowLabel(text: title)
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

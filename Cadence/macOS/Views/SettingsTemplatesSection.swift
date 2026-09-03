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
            CadenceFieldSection(title: "Note Templates") {
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

            CadenceFieldSection(title: nil) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                    // The first clause names the note sidebar, a surface this platform has and
                    // the phone does not, so it stays spelled here rather than in the shared
                    // constant both surfaces read (T-599(b)).
                    Text(
                        "Templates appear in the note sidebar for matching note types. "
                            + CadenceTemplateSettingsCopy.editScopeFootnote
                    )
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

                CadenceRowDivider(axis: .vertical)

                templateEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .oneColumn:
            VStack(alignment: .leading, spacing: 16) {
                templateList

                CadenceRowDivider()

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

                // `TemplateEditorField` used to sit at the bottom of this file: an eyebrow over an
                // inset well at radius 10, with `.stroke` (which straddles the edge) and
                // `Theme.bg.opacity(0.55)` behind it — the fourth private spelling of
                // `CadenceSettingsField` on this platform, after `SettingsAISection.settingsField`
                // and `SettingsTagsSection`'s two. It is the shared component now (T-286).
                //
                // The two text fields keep their own fonts: the shared well sets 14pt medium as a
                // default and each `content` overrides it closer to the leaf, which is the point of
                // the well being chrome rather than a text style. The body editor keeps its 280pt
                // floor for the same reason — `rowHeight` is a minimum, not a height — and opts out
                // of the well's 12pt gutter, because an `NSScrollView` insets its own text.
                VStack(alignment: .leading, spacing: 8) {
                    CadenceSettingsField(title: "Title") {
                        TextField("Template title", text: titleBinding)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }

                    CadenceSettingsField(title: "Description") {
                        TextField("Short sidebar description", text: subtitleBinding)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }

                    // **T-442 — the body is markdown, and macOS now edits it as markdown.**
                    // This was a bare `TextEditor` in 12pt monospace while iOS bound the same
                    // `UserDefaults` string to `iOSMarkdownEditingSurface`: no live styling, no
                    // format row, no `/` menu. The parity fix is the *macOS* shared surface —
                    // `MarkdownEditor`, which five note hosts already draw — not a port of the iOS
                    // view, whose toolbar, `[[`/`/` strips and photos picker are phone chrome.
                    //
                    // `allowsImageInsertion: false` for the reason iOS refuses it here: a template
                    // body is a JSON string under `NoteTemplateLibrary.storageKey`, so an image
                    // pasted into it is referenced by nothing `CadenceMarkdownSourceInventory` can
                    // read and the next sweep deletes the asset.
                    //
                    // No `referenceNotes`/`referenceTasks`: a stencil that names one particular
                    // note is not reusable, and iOS passes none either. `slashTemplates` stays
                    // empty for the same reason — a template inserting a template.
                    CadenceSettingsField(title: "Body", insetsContent: false) {
                        MarkdownEditor(
                            text: bodyBinding(for: selectedTemplate),
                            allowsImageInsertion: false
                        )
                        // `MarkdownEditor` has no intrinsic content size — it fills exactly what it
                        // is given — so this is the editor's height, as the 280pt floor under the
                        // `TextEditor` was. The toolbar takes 44 of it.
                        .frame(minHeight: 280)
                    }
                }
            }
        } else {
            // Was a bare `Text` with no glyph, no card row and no second line — the loudest of the
            // four one-liners T-600(b) closed, because it is the only one that is not "you have
            // nothing yet": the templates ship with the app, so this state means the stored
            // definitions could not be read, and the subtitle now says so.
            CadenceSettingsNoticeRow(
                systemImage: "doc.text",
                title: CadenceSettingsEmptyStateCopy.templatesTitle,
                detail: CadenceSettingsEmptyStateCopy.templatesSubtitle
            ) {
                EmptyView()
            }
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
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.42) : Theme.borderSubtle.opacity(0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif

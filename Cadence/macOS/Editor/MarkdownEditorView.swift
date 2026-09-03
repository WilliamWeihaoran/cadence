#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

enum MarkdownEditorMetrics {
    static let textInset: CGFloat = 20
    static let lineFragmentPadding: CGFloat = 5
    static let firstTextColumnInset: CGFloat = textInset + lineFragmentPadding
    /// Height of the format toolbar above the text. Exposed so an overlay drawn over the whole
    /// `MarkdownEditor` — the empty-body placeholder — can sit on the first text line rather than
    /// on top of the toolbar.
    static let toolbarHeight: CGFloat = 44
}

struct MarkdownEditor: View {
    @Binding var text: String
    var showsToolbar = true
    var toolbarAccessory: AnyView? = nil
    /// Templates offered inside the `/` command menu, alongside the built-in commands. One of the
    /// three routes to a template now that they no longer take a row above the note.
    var slashTemplates: [NoteTemplate] = []
    /// Whether this host may mint `MarkdownImageAsset` rows from the toolbar's photo button, the
    /// `/image` slash command, a paste, or a drop.
    ///
    /// **T-442, and the same door `iOSMarkdownEditingSurface.allowsImageInsertion` closes.** Every
    /// image path here writes a `cadence-image://` token into `text` and a row into the store; the
    /// row survives only while `CadenceMarkdownSourceInventory` can still find that token in some
    /// *stored* field. A host binding this editor to a `Note`, a `Document` or `AppTask.notes` is
    /// fine — those are in the inventory. A host binding it to the note-template body is not: that
    /// text is a JSON string in `UserDefaults` under `NoteTemplateLibrary.storageKey`, so the token
    /// is somewhere no `ModelContext` fetch can look and the next note delete or list cascade
    /// sweeps the asset. That is a *deletion* of `.externalStorage` bytes, not a leak, which is why
    /// the door closes rather than the scan widening.
    ///
    /// **One flag reaches all four doors here, where iOS needed three guards.** The panel, the
    /// paste and the drop all funnel through `onCreateMarkdownImages` — which is `createAssets`
    /// below — and `CadenceTextView.insertMarkdownImages` no-ops on an empty asset list, so a
    /// refused paste falls through to `super.paste(_:)` as ordinary text. The toolbar button and
    /// the `/` entry are removed rather than offered and ignored.
    var allowsImageInsertion = true
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    var onOpenNoteReference: (UUID?, String) -> Void = { _, _ in }
    var onOpenTaskReference: (UUID?, String) -> Void = { _, _ in }
    var onCreateEmbeddedTask: (String) -> MarkdownReferenceSuggestion? = { _ in nil }
    var onToggleEmbeddedTask: (UUID) -> Void = { _ in }
    var onToggleEmbeddedSubtask: (UUID, UUID) -> Void = { _, _ in }
    var onRenameEmbeddedTask: (UUID, String) -> Void = { _, _ in }
    var onOpenEmbeddedTask: (UUID) -> Void = { _ in }
    var onEditEmbeddedTask: (UUID, MarkdownTaskEmbedField) -> Void = { _, _ in }
    var onHoverEmbeddedTask: (UUID, Bool) -> Void = { _, _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onTextViewChanged: (CadenceTextView) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var textView: CadenceTextView?
    /// Set when an image insertion loses pictures — because the store refused the commit (T-629),
    /// or because the decoder refused some of the items before it (T-649). Drawn under the toolbar,
    /// on the first text column, because the editor has no sheet to close and no other way to say
    /// that a picture the user just pasted is not in the note.
    @State private var imageFailureNotice: String?

    // MARK: - Reference candidates
    //
    // Both lists go through `MarkdownReferenceCompletionSupport`, which is where iOS's `[[` menu
    // and picker sheet already get theirs. Two things were wrong with the local sorts these
    // replaced, and only the first is a bug:
    //
    // **Non-total.** Both ended at a case-insensitive title compare, and both consumers truncate —
    // `MarkdownReferencePickerController` takes `.prefix(8)`, the toolbar menu `.prefix(12)`. Two
    // notes named "Meeting" therefore left *which eight were offered* undefined, not merely their
    // order. This is the defect `41b25f8` fixed on the iOS copies by ending in
    // `TaskOrdering.fallbackPrecedes`; the macOS copy was missed.
    //
    // **Alphabetical.** Converged onto iOS's ordering — notes most-recently-edited first, tasks
    // open-before-done then priority — rather than keeping alphabetical here. The case for keeping
    // it was that a Mac shows a wider list, and that turned out not to be true of this picker: both
    // consumers cap at 8 and 12. Alphabetical order under a cap does not rank, it filters by first
    // letter, so an empty `[[` on a vault of a few hundred notes offered eight titles beginning
    // with "A" and could not reach anything else without typing. Recency is the useful eight.
    // Sorting still matters once a query is typed, because the query filter downstream preserves
    // this order rather than scoring.

    @MainActor private var noteSuggestions: [MarkdownReferenceSuggestion] {
        MarkdownReferenceCompletionSupport.candidateNotes(from: referenceNotes, query: "")
            .map(MarkdownReferenceSuggestion.note)
    }

    @MainActor private var taskSuggestions: [MarkdownReferenceSuggestion] {
        MarkdownReferenceCompletionSupport.candidateTasks(from: referenceTasks, query: "")
            .map(MarkdownReferenceSuggestion.task)
    }

    @MainActor private var referenceSuggestions: [MarkdownReferenceSuggestion] {
        noteSuggestions + taskSuggestions
    }

    @MainActor private var tagSuggestions: [MarkdownTagSuggestion] {
        TagSupport.uniqueBySlug(tags).map(MarkdownTagSuggestion.tag)
    }

    @MainActor private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(uniqueKeysWithValues: referenceTasks.map { ($0.id, MarkdownTaskEmbedRenderInfo.task($0)) })
    }

    /// `nil` when this host refuses images, which is how the toolbar drops the photo button rather
    /// than drawing one that declines the click.
    private var chooseImagesAction: (() -> Void)? {
        allowsImageInsertion ? { chooseImages() } : nil
    }

    /// The `/` menu without `/image` when images are refused, rather than with an entry whose
    /// follow-up does nothing.
    private var availableSlashCommands: [MarkdownSlashCommand] {
        let all = MarkdownSlashCommand.all + MarkdownSlashCommand.templateCommands(for: slashTemplates)
        return allowsImageInsertion ? all : MarkdownSlashCommand.refusingImageInsertion(all)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                MarkdownEditorToolbar(
                    textView: textView,
                    noteSuggestions: noteSuggestions,
                    taskSuggestions: taskSuggestions,
                    onChooseImages: chooseImagesAction,
                    accessory: toolbarAccessory
                )
                .zIndex(10)
            }

            if let imageFailureNotice {
                CadenceInlineFailureNotice(text: imageFailureNotice) { self.imageFailureNotice = nil }
                    .padding(.horizontal, MarkdownEditorMetrics.firstTextColumnInset)
                    .padding(.bottom, 6)
                    .zIndex(5)
            }

            MarkdownEditorView(
                text: $text,
                slashCommands: availableSlashCommands,
                imageAssets: imageAssets,
                onCreateImages: createAssets,
                onResizeImage: resizeImage,
                onChooseImages: chooseImages,
                referenceSuggestions: referenceSuggestions,
                tagSuggestions: tagSuggestions,
                taskEmbedInfos: taskEmbedInfos,
                onOpenReference: openReference,
                onCreateTag: createInlineTag,
                onCreateEmbeddedTask: onCreateEmbeddedTask,
                onToggleEmbeddedTask: onToggleEmbeddedTask,
                onToggleEmbeddedSubtask: onToggleEmbeddedSubtask,
                onRenameEmbeddedTask: onRenameEmbeddedTask,
                onOpenEmbeddedTask: onOpenEmbeddedTask,
                onEditEmbeddedTask: onEditEmbeddedTask,
                onHoverEmbeddedTask: onHoverEmbeddedTask,
                onEditingChanged: onEditingChanged,
                onTextViewChanged: {
                    textView = $0
                    onTextViewChanged($0)
                },
                allowsImageInsertion: allowsImageInsertion
            )
            .zIndex(0)
        }
    }

    /// Mints the asset rows for a paste, a drop or the file panel, and hands back only the ones the
    /// store actually took.
    ///
    /// **T-629.** `MarkdownImageAssetService.createAsset` does `modelContext.insert(asset)` and
    /// nothing else, so this frame owns the commit — and it used to swallow it. The picture still
    /// rendered, because the context held the row; it stopped rendering the first time anything
    /// unrelated called `rollback()` on the app's single context, and by then the note had already
    /// been given a `![…](cadence-image://<uuid>)` reference to an asset that had never existed.
    /// Nothing rewrites a note to drop such a reference, so the loss is permanent.
    ///
    /// **This agrees with T-620 (`9d38854`) rather than cutting across it.** That fix made the
    /// delete sweep a candidate-set delete because an asset whose owning row has not imported from
    /// CloudKit yet is indistinguishable from an unreferenced one — deletion errs toward keeping.
    /// So does this: a refused commit un-inserts the assets and writes **no reference at all**,
    /// costing the user the paste rather than leaving a token pointing at nothing. Neither end ever
    /// leaves markdown referencing an asset the store does not hold.
    ///
    /// `[]` is already this function's refusal (`allowsImageInsertion`), and
    /// `CadenceTextView.insertMarkdownImages` no-ops on an empty list, so a refused commit reaches
    /// the text layer as "there are no images", which is exactly true.
    ///
    /// **T-649 is the other half of the same door.** The two `compactMap`s above drop every image
    /// the decoder refuses, and until this ticket the survivors were committed and referenced with
    /// no sentence about the rest — drop eight pictures, get six, and nothing says which count was
    /// real. The loss is counted here and reported through the *same* `imageFailureNotice` the
    /// commit refusal uses, because a door with two notices is a door the user has to look at
    /// twice. The two never collide: this branch runs only when a commit landed.
    private func createAssets(images: [NSImage], urls: [URL]) -> [MarkdownImageAsset] {
        guard allowsImageInsertion else { return [] }
        // Every caller has already established that these are images — the panel sets
        // `allowedContentTypes = [.image]`, and the paste and drop paths read through
        // `MarkdownImageAssetService.imageFileURLs(from:)`, which filters on `UTType.image`. So an
        // item counted here and not returned is one the decoder refused, which is exactly what
        // T-649's sentence claims.
        let attempted = urls.count + images.count
        var assets = MarkdownImageAssetService.createAssets(fromFileURLs: urls, in: modelContext)
        assets.append(contentsOf: images.compactMap {
            MarkdownImageAssetService.createAsset(from: $0, in: modelContext)
        })
        guard !assets.isEmpty else {
            imageFailureNotice = CadenceMarkdownImageInsertionNotice.notice(attempted: attempted, accepted: 0)
            return []
        }
        do {
            try CadencePendingChangePersistence.commitInsert(of: assets, in: modelContext)
        } catch {
            imageFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return []
        }
        imageFailureNotice = CadenceMarkdownImageInsertionNotice.notice(
            attempted: attempted,
            accepted: assets.count
        )
        return assets
    }

    private func resizeImage(id: UUID, width: CGFloat) {
        MarkdownImageAssetService.setDisplayWidth(width, for: id, in: imageAssets)
        try? modelContext.save()
    }

    private func chooseImages() {
        guard allowsImageInsertion else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let assets = createAssets(images: [], urls: panel.urls)
            insertAssets(assets)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func insertAssets(_ assets: [MarkdownImageAsset]) {
        guard !assets.isEmpty else { return }
        if let textView {
            textView.insertMarkdownImages(assets)
        } else {
            let markdown = assets.map { MarkdownImageAssetService.markdown(for: $0) }.joined(separator: "\n\n")
            text += text.hasSuffix("\n") || text.isEmpty ? markdown + "\n" : "\n\n\(markdown)\n"
        }
    }

    private func openReference(_ target: MarkdownReferenceTarget) {
        switch target.kind {
        case .note:
            onOpenNoteReference(target.id, target.title)
        case .task:
            onOpenTaskReference(target.id, target.title)
        }
    }

    private func createInlineTag(_ name: String) -> MarkdownTagSuggestion? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else { return nil }
        let wasArchived = tag.isArchived
        let previousUpdatedAt = tag.updatedAt
        tag.isArchived = false
        tag.updatedAt = Date()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: {
                tag.isArchived = wasArchived
                tag.updatedAt = previousUpdatedAt
            })
        } catch {
            return nil
        }
        return .tag(tag)
    }
}

private struct MarkdownEditorToolbar: View {
    private static let height: CGFloat = MarkdownEditorMetrics.toolbarHeight

    let textView: CadenceTextView?
    let noteSuggestions: [MarkdownReferenceSuggestion]
    let taskSuggestions: [MarkdownReferenceSuggestion]
    /// `nil` at a host that refuses images. Dropped rather than disabled: a button drawn and then
    /// declining the click advertises a capability the row does not have — the same rule
    /// `iOSMarkdownFormatToolbar` follows.
    let onChooseImages: (() -> Void)?
    let accessory: AnyView?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    MarkdownToolbarTextButton(title: "H1", accessibilityLabel: "Heading 1") {
                        textView?.performMarkdownFormatCommand(.heading(1))
                    }
                    MarkdownToolbarTextButton(title: "H2", accessibilityLabel: "Heading 2") {
                        textView?.performMarkdownFormatCommand(.heading(2))
                    }
                    toolbarDivider
                    MarkdownToolbarButton(systemName: "bold", accessibilityLabel: "Bold") {
                        textView?.performMarkdownFormatCommand(.bold)
                    }
                    MarkdownToolbarButton(systemName: "italic", accessibilityLabel: "Italic") {
                        textView?.performMarkdownFormatCommand(.italic)
                    }
                    MarkdownToolbarButton(systemName: "strikethrough", accessibilityLabel: "Strikethrough") {
                        textView?.performMarkdownFormatCommand(.strikethrough)
                    }
                    MarkdownToolbarButton(systemName: "highlighter", accessibilityLabel: "Highlight") {
                        textView?.performMarkdownFormatCommand(.highlight)
                    }
                    MarkdownToolbarButton(systemName: "chevron.left.forwardslash.chevron.right", accessibilityLabel: "Inline code") {
                        textView?.performMarkdownFormatCommand(.inlineCode)
                    }
                    toolbarDivider
                    MarkdownToolbarButton(systemName: "link", accessibilityLabel: "Link") {
                        textView?.performMarkdownFormatCommand(.link)
                    }
                    MarkdownReferenceMenuButton(
                        systemName: "text.badge.plus",
                        accessibilityLabel: "Note link",
                        emptyTitle: "Blank Note Link",
                        suggestions: noteSuggestions,
                        blankAction: { textView?.performMarkdownFormatCommand(.noteLink) },
                        selectAction: { textView?.insertMarkdownReference($0.markdown) }
                    )
                    MarkdownReferenceMenuButton(
                        systemName: "checkmark.circle",
                        accessibilityLabel: "Task reference",
                        emptyTitle: "Blank Task Reference",
                        suggestions: taskSuggestions,
                        blankAction: { textView?.performMarkdownFormatCommand(.taskReference) },
                        selectAction: { textView?.insertMarkdownReference($0.markdown) }
                    )
                    toolbarDivider
                    MarkdownToolbarButton(systemName: "list.bullet", accessibilityLabel: "Bulleted list") {
                        textView?.performMarkdownFormatCommand(.unorderedList)
                    }
                    MarkdownToolbarButton(systemName: "list.number", accessibilityLabel: "Numbered list") {
                        textView?.performMarkdownFormatCommand(.orderedList)
                    }
                    MarkdownToolbarButton(systemName: "checklist", accessibilityLabel: "Checklist") {
                        textView?.performMarkdownFormatCommand(.todoList)
                    }
                    MarkdownToolbarButton(systemName: "text.quote", accessibilityLabel: "Quote") {
                        textView?.performMarkdownFormatCommand(.quote)
                    }
                    toolbarDivider
                    MarkdownToolbarButton(systemName: "curlybraces.square", accessibilityLabel: "Code block") {
                        textView?.performMarkdownFormatCommand(.codeBlock)
                    }
                    MarkdownToolbarButton(systemName: "minus", accessibilityLabel: "Divider") {
                        textView?.performMarkdownFormatCommand(.divider)
                    }
                    if let onChooseImages {
                        MarkdownToolbarButton(systemName: "photo", accessibilityLabel: "Image") {
                            onChooseImages()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .frame(maxHeight: .infinity, alignment: .center)

            if let accessory {
                Divider()
                    .background(Theme.borderSubtle)
                accessory
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .fixedSize()
            }
        }
        .frame(height: Self.height)
        .background(Theme.surfaceElevated)
        .overlay(alignment: .bottom) {
            Divider().background(Theme.borderSubtle)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}

/// A toolbar entry whose label is an icon, so the string has to be spelled twice: once for the
/// pointer (`.help`) and once for assistive technology (`.accessibilityLabel`). Both read the same
/// stored property, which is why it is named for the accessible name rather than for the tooltip —
/// a `help:` that was only a tooltip is what T-472 found on all three of these views, and
/// `CadenceIconButton` had the paired shape all along.
private struct MarkdownReferenceMenuButton: View {
    let systemName: String
    let accessibilityLabel: String
    let emptyTitle: String
    let suggestions: [MarkdownReferenceSuggestion]
    let blankAction: () -> Void
    let selectAction: (MarkdownReferenceSuggestion) -> Void

    var body: some View {
        Menu {
            if suggestions.isEmpty {
                Button(emptyTitle, action: blankAction)
            } else {
                Button(emptyTitle, action: blankAction)
                Divider()
                ForEach(suggestions.prefix(12)) { suggestion in
                    Button {
                        selectAction(suggestion)
                    } label: {
                        Text(suggestion.title)
                    }
                }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        .cadenceHoverHighlight(cornerRadius: Theme.radiusControlCompact, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct MarkdownToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        .cadenceHoverHighlight(cornerRadius: Theme.radiusControlCompact, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

/// The one toolbar button with visible text, and the one whose accessible name deliberately
/// differs from it: the row reads `H1`, VoiceOver is handed "Heading 1". `.accessibilityLabel`
/// replaces the label's own text rather than adding to it, so there is no double announcement.
private struct MarkdownToolbarTextButton: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 30, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .buttonStyle(.cadencePlain)
        .background(Theme.bg.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        .cadenceHoverHighlight(cornerRadius: Theme.radiusControlCompact, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    /// The `/` menu's command list. Defaults to the built-ins; callers that have templates append
    /// them, so the picker is per-note-kind without the editor knowing what a note kind is.
    var slashCommands: [MarkdownSlashCommand] = MarkdownSlashCommand.all
    var imageAssets: [MarkdownImageAsset] = []
    var onCreateImages: ([NSImage], [URL]) -> [MarkdownImageAsset] = { _, _ in [] }
    var onResizeImage: (UUID, CGFloat) -> Void = { _, _ in }
    var onChooseImages: () -> Void = {}
    var referenceSuggestions: [MarkdownReferenceSuggestion] = []
    var tagSuggestions: [MarkdownTagSuggestion] = []
    var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var onOpenReference: (MarkdownReferenceTarget) -> Void = { _ in }
    var onCreateTag: (String) -> MarkdownTagSuggestion? = { _ in nil }
    var onCreateEmbeddedTask: (String) -> MarkdownReferenceSuggestion? = { _ in nil }
    var onToggleEmbeddedTask: (UUID) -> Void = { _ in }
    var onToggleEmbeddedSubtask: (UUID, UUID) -> Void = { _, _ in }
    var onRenameEmbeddedTask: (UUID, String) -> Void = { _, _ in }
    var onOpenEmbeddedTask: (UUID) -> Void = { _ in }
    var onEditEmbeddedTask: (UUID, MarkdownTaskEmbedField) -> Void = { _, _ in }
    var onHoverEmbeddedTask: (UUID, Bool) -> Void = { _, _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onTextViewChanged: (CadenceTextView) -> Void = { _ in }
    /// `MarkdownEditor.allowsImageInsertion`, carried down to the text view so the drop path can
    /// refuse in the same breath as the toolbar button, the `/` menu and the paste (T-478).
    var allowsImageInsertion = true

    func makeNSView(context: NSViewRepresentableContext<MarkdownEditorView>) -> NSScrollView {
        let scrollView = MarkdownEditorScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.nsBg
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let initialContainerWidth = max(1, contentSize.width - MarkdownEditorMetrics.textInset * 2)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: initialContainerWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CadenceTextView(frame: NSRect(origin: .zero, size: CGSize(width: contentSize.width, height: 0)),
                                       textContainer: textContainer)
        textView.frame = NSRect(origin: .zero, size: CGSize(width: contentSize.width, height: 0))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: initialContainerWidth,
                                                        height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true       // must be true to preserve custom attributes
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = Theme.nsBg
        textView.insertionPointColor = Theme.nsBlue
        textView.textContainerInset = NSSize(
            width: MarkdownEditorMetrics.textInset,
            height: MarkdownEditorMetrics.textInset
        )
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        configure(textView, context: context)

        scrollView.documentView = textView
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        guard let textView = scrollView.documentView as? CadenceTextView else { return }
        context.coordinator.update(parent: self)
        let didUpdateRenderedContent = configure(textView, context: context)
        let currentText = textView.string
        let displayText = currentText == text ? currentText : MarkdownListSupport.normalizedMarkdownListPrefixes(in: text)
        let didUpdateText = currentText != displayText

        guard didUpdateText || didUpdateRenderedContent else { return }

        if didUpdateText {
            let sel = textView.selectedRange()
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                textView.string = displayText
                MarkdownStylist.apply(to: textView)
            }
            let safe = NSRange(location: min(sel.location, (displayText as NSString).length), length: 0)
            textView.setSelectedRange(safe)
        } else {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: textView)
            }
        }
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
    }

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(parent: self)
    }

    @discardableResult
    private func configure(_ textView: CadenceTextView, context: NSViewRepresentableContext<MarkdownEditorView>) -> Bool {
        let referencedImageIDs = MarkdownImageAssetService.standaloneReferencedIDs(in: text)
        let referencedAssets = imageAssets.filter { referencedImageIDs.contains($0.id) }
        let imageAssetVersions = Dictionary(uniqueKeysWithValues: referencedAssets.map { ($0.id, $0.updatedAt) })
        var didUpdateRenderedContent = false

        if textView.markdownImageAssetVersions != imageAssetVersions {
            textView.markdownImageAssetVersions = imageAssetVersions
            textView.markdownImageRects.removeAll()
            textView.markdownImageAssets = Dictionary(
                uniqueKeysWithValues: referencedAssets.compactMap { asset in
                    MarkdownImageAssetService.renderAsset(for: asset.id, in: referencedAssets).map { (asset.id, $0) }
                }
            )
            if let selectedMarkdownImageID = textView.selectedMarkdownImageID,
               imageAssetVersions[selectedMarkdownImageID] == nil {
                textView.selectedMarkdownImageID = nil
            }
            didUpdateRenderedContent = true
        }

        if textView.markdownTaskEmbeds != taskEmbedInfos {
            textView.markdownTaskEmbedRects.removeAll()
            textView.markdownTaskEmbeds = taskEmbedInfos
            if let hoveredMarkdownTaskEmbed = textView.hoveredMarkdownTaskEmbed,
               taskEmbedInfos[hoveredMarkdownTaskEmbed.id] == nil {
                textView.hoveredMarkdownTaskEmbed = nil
            }
            didUpdateRenderedContent = true
        }
        textView.referenceSuggestions = referenceSuggestions
        textView.tagSuggestions = tagSuggestions
        textView.onOpenMarkdownReference = onOpenReference
        textView.onCreateEmbeddedMarkdownTask = onCreateEmbeddedTask
        textView.onToggleEmbeddedMarkdownTask = onToggleEmbeddedTask
        textView.onToggleEmbeddedMarkdownSubtask = onToggleEmbeddedSubtask
        textView.onRenameEmbeddedMarkdownTask = onRenameEmbeddedTask
        textView.onOpenEmbeddedMarkdownTask = onOpenEmbeddedTask
        textView.onEditEmbeddedMarkdownTask = onEditEmbeddedTask
        textView.onHoverEmbeddedMarkdownTask = onHoverEmbeddedTask
        textView.onCreateMarkdownImages = onCreateImages
        textView.onResizeMarkdownImage = onResizeImage
        textView.allowsMarkdownImageInsertion = allowsImageInsertion
        textView.registerMarkdownDraggedTypes()
        context.coordinator.notifyTextViewIfNeeded(textView, onChange: onTextViewChanged)
        return didUpdateRenderedContent
    }
}

private final class MarkdownEditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        MarkdownEditorScrollSupport.refreshLayout(in: self)
    }
}

enum MarkdownEditorScrollSupport {
    static func preservingScrollPosition(in scrollView: NSScrollView, _ updates: () -> Void) {
        let clipView = scrollView.contentView
        let originalOrigin = clipView.bounds.origin
        updates()
        restoreScrollPosition(originalOrigin, in: scrollView)
    }

    static func refreshLayout(in scrollView: NSScrollView) {
        preservingScrollPosition(in: scrollView) {
            refreshLayoutWithoutRestoringScroll(in: scrollView)
        }
    }

    private static func refreshLayoutWithoutRestoringScroll(in scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let contentSize = scrollView.contentSize
        let targetWidth = max(1, contentSize.width)
        let targetContainerWidth = max(1, targetWidth - textView.textContainerInset.width * 2)
        let currentSize = textView.frame.size

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: targetContainerWidth, height: CGFloat.greatestFiniteMagnitude)

        if abs(currentSize.width - targetWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: targetWidth, height: max(currentSize.height, contentSize.height)))
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let targetHeight = max(
            contentSize.height,
            ceil(usedRect.maxY + textView.textContainerInset.height * 2 + 1)
        )

        let updatedSize = textView.frame.size
        if abs(updatedSize.height - targetHeight) > 0.5 || abs(updatedSize.width - targetWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        }
    }

    private static func restoreScrollPosition(_ origin: NSPoint, in scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let restoredOrigin = NSPoint(
            x: min(max(origin.x, 0), maxX),
            y: min(max(origin.y, 0), maxY)
        )

        guard abs(clipView.bounds.origin.x - restoredOrigin.x) > 0.5 ||
                abs(clipView.bounds.origin.y - restoredOrigin.y) > 0.5 else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            clipView.scroll(to: restoredOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}
#endif

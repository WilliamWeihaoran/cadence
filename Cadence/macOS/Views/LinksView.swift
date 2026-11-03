#if os(macOS)
import SwiftUI
import SwiftData

struct LinksView: View {
    var area: Area? = nil
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    @State private var addForm = SavedLinkAddForm()
    @State private var actionError: String?

    private var links: [SavedLink] {
        if let area {
            return allLinks.filter { $0.area?.id == area.id }
        } else if let project {
            return allLinks.filter { $0.project?.id == project.id }
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Saved Links")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                // The header button is the form's second Cancel while it is open, so it does what
                // the form's own Cancel does and draws the same "x" iOS's toggle draws (T-7256).
                // It used to stay a "+" and only hide the form, so reopening it brought back the
                // abandoned title, URL and failure notice.
                Button {
                    if addForm.toggle() { actionError = nil }
                } label: {
                    Image(systemName: addForm.headerSymbol)
                        .foregroundStyle(Theme.blue)
                        // [[T-9501]]: the bare glyph was the whole hit area and hover wash.
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel(addForm.headerLabel)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if addForm.isOpen {
                AddLinkBar(
                    title: $addForm.title,
                    url: $addForm.url,
                    onSave: { addLink() },
                    onCancel: { addForm.cancel(); actionError = nil }
                )
            }

            if let actionError {
                Text(actionError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            Divider().background(Theme.borderSubtle)

            if links.isEmpty {
                Spacer()
                EmptyStateView(
                    message: CadenceEmptyStateCopy.savedLinksTitle,
                    subtitle: CadenceEmptyStateCopy.savedLinksSubtitle,
                    icon: "link"
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(links) { link in
                            LinkRow(link: link) {
                                deleteConfirmationManager.present(
                                    title: CadenceSavedLinkPersistence.deleteConfirmationTitle,
                                    message: CadenceSavedLinkPersistence.deleteConfirmationMessage(title: link.title)
                                ) {
                                    deleteLink(link)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.bg)
    }

    private func addLink() {
        let title = CadenceTitleNormalization.normalized(addForm.title)
        // Trim, blank-check and scheme are one shared decision now: the inline version here and
        // the copy on iOS both read `hasPrefix` case-sensitively and turned `HTTPS://example.com`
        // into `https://HTTPS://example.com` (T-509).
        guard let urlStr = CadenceSavedLinkURL.normalized(addForm.url) else { return }
        let link = SavedLink(title: CadenceTitleNormalization.display(title, fallback: urlStr), url: urlStr)
        link.area = area
        link.project = project
        link.order = CadenceOrderAllocation.nextOrder(after: links, order: \.order)
        // `modelContext.insert(link)` alone left the new link waiting on autosave, so a quit
        // before that flush lost it. The commit happens inside the helper, which removes the
        // link again if it throws.
        do {
            try CadenceSavedLinkPersistence.insert(link, in: modelContext)
        } catch {
            actionError = CadenceSavedLinkPersistence.saveFailureNotice
            return
        }
        actionError = nil
        addForm.cancel()
    }

    /// A delete with no commit is undone by the next launch, which is the one failure the user
    /// cannot tell from success. The helper rolls a failed delete back, so the row the message
    /// talks about is visibly still there.
    private func deleteLink(_ link: SavedLink) {
        do {
            try CadenceSavedLinkPersistence.delete(link, in: modelContext)
            actionError = nil
        } catch {
            actionError = CadenceSavedLinkPersistence.deleteFailureNotice
        }
    }
}

// MARK: - Add Link Form State

// `SavedLinkAddForm` lives in `Cadence/Shared/CadenceSavedLinkPersistence.swift` since
// [[T-10056]], so iOS's Links tab closes its form the same way.

// MARK: - Add Link Bar

private struct AddLinkBar: View {
    @Binding var title: String
    @Binding var url: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            TextField("URL", text: $url)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .onSubmit { onSave() }

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    onCancel()
                }
                // [[T-9972]]: `.primary`, the commit of a Cancel/commit pair everywhere else on
                // the Mac (the context editor, Edit Tag, the list editor, the folder sheet) and
                // the role iOS's own add-link form commits with. It was the one `.secondary` Save.
                CadenceActionButton(
                    title: CadenceSavedLinkPersistence.saveActionTitle,
                    role: .primary,
                    size: .compact,
                    isDisabled: CadenceTitleNormalization.isBlank(url)
                ) {
                    onSave()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.surface)
        // [[T-10016]]: Escape cancels, through the same `onCancel` as the button, as it does in the
        // inline task composer and the list-note rename. Focus-scoped rather than a `.cancelAction`
        // key equivalent, which would answer Escape anywhere in the window while the form is open.
        // Both spellings, as `TaskInspectorChildPanelEscapeDismissal` carries: `onExitCommand`
        // rides `cancelOperation(_:)` from the focused field, `onKeyPress` follows SwiftUI focus,
        // and `SavedLinkAddForm.cancel()` is idempotent, so whichever fires second is a no-op.
        .onExitCommand(perform: onCancel)
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }
}

// MARK: - Link Row Actions

/// What a saved link offers besides its hover buttons ([[T-7258]]).
///
/// The row's Open and Delete buttons are built only while the pointer is over it, so they were
/// in neither the view tree nor the accessibility tree otherwise: right-click did nothing and
/// VoiceOver could not delete a link. The row now carries a context menu and named accessibility
/// actions that run the same three operations the hover buttons and the click run.
enum MacSavedLinkRowActions {
    static let openActionName = "Open link"
    static let deleteActionName = "Delete link"

    static let openMenuTitle = CadenceSavedLinkRowMenu.openTitle
    static let copyMenuTitle = CadenceSavedLinkRowMenu.copyTitle
    static let deleteMenuTitle = CadenceSavedLinkRowMenu.deleteTitle

    static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// The stored URL as plain text. The pasteboard is a parameter so a test can hand it a private
    /// one instead of the user's clipboard.
    static func copy(_ urlString: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
    }
}

// MARK: - Link Row

private struct LinkRow: View {
    @Bindable var link: SavedLink
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Favicon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.surfaceElevated)
                    .frame(width: 28, height: 28)
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(link.url)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer()

            // The sighted pointer shortcut. The context menu and the accessibility actions below
            // are the paths that exist without hovering (T-7258).
            if isHovering {
                // [[T-10165]]: the menu's Open glyph, and iOS's row's -- one action, one glyph.
                // It was the boxed up-right arrow here and the bare one on the menu beside it.
                Button(action: openLink) {
                    Image(systemName: CadenceSavedLinkRowMenu.openSystemImage)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.blue)
                        // [[T-9501]]: the bare glyph was the whole hit area and hover wash.
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel(MacSavedLinkRowActions.openActionName)

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: CadenceSavedLinkRowMenu.deleteSystemImage)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.red)
                        // [[T-9501]]: the bare glyph was the whole hit area and hover wash.
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel(MacSavedLinkRowActions.deleteActionName)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
        .cadenceHoverHighlight(cornerRadius: Theme.radiusCard)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: openLink)
        // Every other Mac row answers a right-click with a menu (`MacTaskRowContextMenu`, the note
        // rows' "Copy Note Link" / Delete). Delete is `onDelete`, the hover button's own closure,
        // so it asks through `deleteConfirmationManager` exactly as the button does.
        // [[T-10165]]: every item carries its glyph, the three iOS's long-press draws from the same
        // shared set. Open and Copy were bare words above a glyphed Delete.
        .contextMenu {
            Button(action: openLink) {
                Label(MacSavedLinkRowActions.openMenuTitle, systemImage: CadenceSavedLinkRowMenu.openSystemImage)
            }
            Button(action: copyLink) {
                Label(MacSavedLinkRowActions.copyMenuTitle, systemImage: CadenceSavedLinkRowMenu.copySystemImage)
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(MacSavedLinkRowActions.deleteMenuTitle, systemImage: CadenceSavedLinkRowMenu.deleteSystemImage)
            }
        }
        // `.contain` makes the card one element without swallowing its texts, as the task row
        // does, so the actions have a row to sit on while the hover buttons are absent.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: MacSavedLinkRowActions.openActionName, openLink)
        .accessibilityAction(named: MacSavedLinkRowActions.deleteActionName, onDelete)
    }

    private func openLink() { MacSavedLinkRowActions.open(link.url) }
    private func copyLink() { MacSavedLinkRowActions.copy(link.url) }
}
#endif

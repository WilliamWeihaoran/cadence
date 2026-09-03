#if os(macOS)
import SwiftUI
import SwiftData

struct LinksView: View {
    var area: Area? = nil
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newURL = ""
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
                Button {
                    showingAdd.toggle()
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel(showingAdd ? "Cancel adding a link" : "Add link")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if showingAdd {
                AddLinkBar(
                    title: $newTitle,
                    url: $newURL,
                    onSave: { addLink() },
                    onCancel: { showingAdd = false; newTitle = ""; newURL = ""; actionError = nil }
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
                                    title: "Delete Link?",
                                    message: "This will permanently delete \"\(link.title)\"."
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
        let title = CadenceTitleNormalization.normalized(newTitle)
        // Trim, blank-check and scheme are one shared decision now: the inline version here and
        // the copy on iOS both read `hasPrefix` case-sensitively and turned `HTTPS://example.com`
        // into `https://HTTPS://example.com` (T-509).
        guard let urlStr = CadenceSavedLinkURL.normalized(newURL) else { return }
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
        newTitle = ""
        newURL = ""
        showingAdd = false
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
                CadenceActionButton(
                    title: "Save",
                    role: .secondary,
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

            if isHovering {
                Button {
                    if let url = URL(string: link.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Open link")

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.red)
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Delete link")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
        .cadenceHoverHighlight(cornerRadius: Theme.radiusCard)
        .onHover { isHovering = $0 }
        .onTapGesture {
            if let url = URL(string: link.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
#endif

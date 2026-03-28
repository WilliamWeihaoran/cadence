#if os(macOS)
import SwiftUI
import SwiftData

struct LinksView: View {
    var area: Area? = nil
    var project: Project? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newURL = ""

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
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if showingAdd {
                AddLinkBar(
                    title: $newTitle,
                    url: $newURL,
                    onSave: { addLink() },
                    onCancel: { showingAdd = false; newTitle = ""; newURL = "" }
                )
            }

            Divider().background(Theme.borderSubtle)

            if links.isEmpty {
                Spacer()
                EmptyStateView(
                    message: "No saved links",
                    subtitle: "Tap + to save a link",
                    icon: "link"
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(links) { link in
                            LinkRow(link: link) {
                                modelContext.delete(link)
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
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        var urlStr = newURL.trimmingCharacters(in: .whitespaces)
        guard !urlStr.isEmpty else { return }
        if !urlStr.hasPrefix("http://") && !urlStr.hasPrefix("https://") {
            urlStr = "https://" + urlStr
        }
        let link = SavedLink(title: title.isEmpty ? urlStr : title, url: urlStr)
        link.area = area
        link.project = project
        link.order = links.count
        modelContext.insert(link)
        newTitle = ""
        newURL = ""
        showingAdd = false
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
                .padding(8)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("URL", text: $url)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(8)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit { onSave() }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                Button("Save") { onSave() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
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
                .buttonStyle(.plain)

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .onTapGesture {
            if let url = URL(string: link.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import SwiftData

struct TagPickerControl: View {
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    let placeholder: String
    let onCreateTag: (String) -> Tag

    @State private var isPresented = false

    private var visibleSelectedTags: [Tag] {
        TagSupport.sorted(selectedTags)
    }

    var body: some View {
        HStack(spacing: 6) {
            if visibleSelectedTags.isEmpty {
                Text(placeholder)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceElevated.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                ForEach(visibleSelectedTags.prefix(3)) { tag in
                    TagChip(tag: tag) {
                        selectedTags.removeAll { $0.id == tag.id }
                    }
                }
                if visibleSelectedTags.count > 3 {
                    Text("+\(visibleSelectedTags.count - 3)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .help(visibleSelectedTags.dropFirst(3).map(\.name).joined(separator: ", "))
                }
            }

            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.cadencePlain)
            .help("Edit tags")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                TagPickerPopover(
                    selectedTags: $selectedTags,
                    allTags: allTags,
                    onCreateTag: onCreateTag
                )
            }
        }
    }
}

struct TagChip: View {
    let tag: Tag
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: tag.colorHex).opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke((tag.isArchived ? Theme.dim : Color(hex: tag.colorHex)).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(tag.isArchived ? 0.62 : 1)
    }
}

struct CompactTagStrip: View {
    let tags: [Tag]
    var limit: Int = 2
    var allowsArchived: Bool = true

    private var visibleTags: [Tag] {
        let base = allowsArchived ? tags : tags.filter { !$0.isArchived }
        return TagSupport.uniqueBySlug(base)
    }

    var body: some View {
        if !visibleTags.isEmpty {
            HStack(spacing: 4) {
                ForEach(visibleTags.prefix(limit)) { tag in
                    TagMiniChip(tag: tag)
                }
                if visibleTags.count > limit {
                    Text("+\(visibleTags.count - limit)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .help(visibleTags.dropFirst(limit).map(\.name).joined(separator: ", "))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct TagMiniChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tag.isArchived ? Theme.dim : Color(hex: tag.colorHex))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color(hex: tag.colorHex).opacity(tag.isArchived ? 0.08 : 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(hex: tag.colorHex).opacity(tag.isArchived ? 0.18 : 0.26), lineWidth: 1)
            )
            .help(tag.isArchived ? "\(tag.name) (archived)" : tag.name)
    }
}

struct TagFilterBar: View {
    let tags: [Tag]
    @Binding var selectedSlugs: Set<String>
    var maxVisibleTags: Int = 8

    private var visibleTags: [Tag] {
        Array(TagSupport.uniqueBySlug(tags.filter { !$0.isArchived }).prefix(maxVisibleTags))
    }

    var body: some View {
        if !visibleTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleTags) { tag in
                        let isSelected = selectedSlugs.contains(tag.slug)
                        Button {
                            if isSelected {
                                selectedSlugs.remove(tag.slug)
                            } else {
                                selectedSlugs.insert(tag.slug)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color(hex: tag.colorHex).opacity(0.18) : Theme.surfaceElevated.opacity(0.58))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(hex: tag.colorHex).opacity(isSelected ? 0.42 : 0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.cadencePlain)
                        .help(isSelected ? "Remove tag filter" : "Filter by \(tag.name)")
                    }

                    if !selectedSlugs.isEmpty {
                        Button {
                            selectedSlugs.removeAll()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.cadencePlain)
                        .help("Clear tag filters")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct TagPickerPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    let onCreateTag: (String) -> Tag

    @State private var query = ""
    @State private var editingTag: Tag?
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var editColorHex = ""
    @FocusState private var isSearchFocused: Bool

    private var activeTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    private var filteredTags: [Tag] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return activeTags }
        return activeTags.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.slug.localizedCaseInsensitiveContains(TagSupport.slug(for: trimmed))
        }
    }

    private var canCreate: Bool {
        let name = TagSupport.displayName(for: query)
        guard !name.isEmpty,
              name.rangeOfCharacter(from: .alphanumerics) != nil else { return false }
        let slug = TagSupport.slug(for: name)
        return !allTags.contains { $0.slug == slug }
    }

    private var archivedQueryMatch: Tag? {
        let name = TagSupport.displayName(for: query)
        guard !name.isEmpty else { return nil }
        let slug = TagSupport.slug(for: name)
        return allTags.first { $0.isArchived && $0.slug == slug }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Find or create tag", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .focused($isSearchFocused)
                    .onSubmit(createQueriedTagIfNeeded)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredTags) { tag in
                        tagRow(tag)
                    }

                    if let archivedQueryMatch {
                        Button {
                            restore(archivedQueryMatch)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                                Text("Restore \"\(archivedQueryMatch.name)\"")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.cadencePlain)
                        .cadenceHoverHighlight(cornerRadius: 6)
                    } else if canCreate {
                        Button {
                            createQueriedTagIfNeeded()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                                Text("Create \"\(TagSupport.displayName(for: query))\"")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.cadencePlain)
                        .cadenceHoverHighlight(cornerRadius: 6)
                    }

                    if filteredTags.isEmpty && !canCreate {
                        Text("No tags")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .padding(10)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 240)
        .background(Theme.surfaceElevated)
        .sheet(item: $editingTag) { tag in
            TagEditSheet(
                tag: tag,
                allTags: allTags,
                name: $editName,
                description: $editDescription,
                colorHex: $editColorHex,
                onCancel: { editingTag = nil },
                onSave: { saveEdits(to: tag) },
                onArchive: { archive(tag) }
            )
        }
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let selected = selectedTags.contains { $0.id == tag.id }
        return HStack(spacing: 4) {
            Button {
                if selected {
                    selectedTags.removeAll { $0.id == tag.id }
                } else {
                    selectedTags.append(tag)
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tag.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if !tag.desc.isEmpty {
                            Text(tag.desc)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .background(selected ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .cadenceHoverHighlight(cornerRadius: 6)

            Button {
                beginEditing(tag)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .cadenceHoverHighlight(cornerRadius: 6)
            .help("Edit tag")
        }
    }

    private func createQueriedTagIfNeeded() {
        guard canCreate else { return }
        let tag = onCreateTag(query)
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
        }
        query = ""
    }

    private func restore(_ tag: Tag) {
        tag.isArchived = false
        tag.updatedAt = Date()
        try? modelContext.save()
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
        }
        query = ""
    }

    private func beginEditing(_ tag: Tag) {
        editName = tag.name
        editDescription = tag.desc
        editColorHex = tag.colorHex
        editingTag = tag
    }

    private func saveEdits(to tag: Tag) {
        let name = TagSupport.displayName(for: editName)
        guard !name.isEmpty else { return }
        tag.name = name
        tag.slug = TagSupport.slug(for: name)
        tag.desc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = TagSupport.normalizedColorHex(editColorHex)
        tag.updatedAt = Date()
        try? modelContext.save()
        editingTag = nil
    }

    private func archive(_ tag: Tag) {
        tag.isArchived = true
        tag.updatedAt = Date()
        try? modelContext.save()
        editingTag = nil
    }

}

private struct TagEditSheet: View {
    let tag: Tag
    let allTags: [Tag]
    @Binding var name: String
    @Binding var description: String
    @Binding var colorHex: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let onArchive: () -> Void

    private var normalizedSlug: String {
        TagSupport.slug(for: name)
    }

    private var hasDuplicateSlug: Bool {
        allTags.contains { $0.id != tag.id && $0.slug == normalizedSlug }
    }

    private var canSave: Bool {
        !TagSupport.displayName(for: name).isEmpty && !hasDuplicateSlug
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit tag")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Description", text: $description)
                    .textFieldStyle(.roundedBorder)
                TextField("Color", text: $colorHex)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                ForEach(TagSupport.colorOptions, id: \.self) { option in
                    Button {
                        colorHex = option
                    } label: {
                        Circle()
                            .fill(Color(hex: option))
                            .frame(width: 18, height: 18)
                            .overlay {
                                if colorHex.caseInsensitiveCompare(option) == .orderedSame {
                                    Circle()
                                        .stroke(Theme.text.opacity(0.8), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.cadencePlain)
                }
            }

            if hasDuplicateSlug {
                Text("A tag with this name already exists.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Archive", role: .destructive, action: onArchive)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.surfaceElevated)
    }
}
#endif

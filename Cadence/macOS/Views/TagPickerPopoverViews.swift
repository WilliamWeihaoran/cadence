#if os(macOS)
import SwiftUI
import SwiftData

struct TagPickerPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    let onCreateTag: (String) -> Tag?

    @State private var query = ""
    @State private var editingTag: Tag?
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var editColorHex = ""
    /// T-497: the edit sheet's own failure line. `editingTag = nil` is this popover's dismissal,
    /// so it only runs on a committed change and the sheet stays open over a refused one.
    @State private var editFailureNotice: String?
    /// **T-652: the popover's own failure line**, and it is a second `@State` rather than a reuse
    /// of `editFailureNotice` on purpose. Restore is pressed from the list below, not from the
    /// edit sheet, and `editFailureNotice` is only ever rendered *inside* `TagEditSheet` — which is
    /// not on screen when this runs. A refused restore needs its sentence where the press was.
    @State private var restoreFailureNotice: String?
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

                    TagPickerPlaceholderRow(
                        placeholder: TagPickerPlaceholder.resolve(
                            hasActiveTags: !activeTags.isEmpty,
                            matchCount: filteredTags.count,
                            canCreate: canCreate,
                            canRestore: archivedQueryMatch != nil
                        )
                    )
                }
                .padding(6)
            }
            .frame(maxHeight: 220)

            if let restoreFailureNotice {
                Divider().background(Theme.borderSubtle)
                CadenceInlineFailureNotice(text: restoreFailureNotice)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
            }
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
                failureNotice: editFailureNotice,
                onCancel: {
                    editFailureNotice = nil
                    editingTag = nil
                },
                onSave: { saveEdits(to: tag) },
                onArchive: { archive(tag) }
            )
        }
        .onChange(of: query) {
            // The notice names the tag the old query matched. Once the query moves on it is about
            // something that is no longer on screen.
            restoreFailureNotice = nil
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
                    CadenceTagChip(tag: tag)
                    Spacer(minLength: 8)
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
            .cadenceControlLabel("Edit tag")
        }
    }

    /// **T-631.** `onCreateTag` answers `nil` when the store refused the new tag, and this stops
    /// there: no chip is selected, and the query stays in the field so the name the user typed is
    /// still on screen to try again with. Clearing it was this control's only report that the tag
    /// had been made, and it used to run whether or not one had been.
    ///
    /// The sentence explaining *why* belongs to the surface that owns the `ModelContext` and ran
    /// the commit — the composer, the inspector, the note header — which is where it is shown.
    private func createQueriedTagIfNeeded() {
        guard canCreate, let tag = onCreateTag(query) else { return }
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
        }
        query = ""
    }

    /// **T-652, and the third member of the set [[T-497]] fixed two of.** `archive(_:)` one screen
    /// down is this function inverted, and it was already correct; this one was not.
    ///
    /// The report half here is not a dismissal, which is why the sweep did not see it: nothing is
    /// closed, nothing is set to `nil`. The chip arriving in the field and the search term
    /// vanishing *are* the report — they say the tag came back — and they ran whether or not the
    /// store took the un-archive, leaving a selected chip for a tag every other picker still hides.
    ///
    /// The undo is the same two-field snapshot `archive` takes, not `rollback()`: this popover is
    /// opened from a task inspector that routinely has unrelated edits pending behind it. See
    /// `CadencePendingChangePersistence.commitEdit`.
    private func restore(_ tag: Tag) {
        let previousIsArchived = tag.isArchived
        let previousUpdatedAt = tag.updatedAt
        tag.isArchived = false
        tag.updatedAt = Date()

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                tag.isArchived = previousIsArchived
                tag.updatedAt = previousUpdatedAt
            }
        } catch {
            restoreFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        restoreFailureNotice = nil
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
        }
        query = ""
    }

    private func beginEditing(_ tag: Tag) {
        editFailureNotice = nil
        editName = tag.name
        editDescription = tag.desc
        editColorHex = tag.colorHex
        editingTag = tag
    }

    /// T-497, the report half of the `try? save()` rule. `editingTag = nil` closes the sheet, and
    /// it closed whether or not the store took the rename — the chip behind the popover then read
    /// the new name from the live object while the store held the old one.
    ///
    /// The undo restores the five fields rather than rolling the context back: this is the app's
    /// single `ModelContext` and the popover is opened from a task inspector that routinely has
    /// unrelated edits pending behind it. See `CadencePendingChangePersistence.commitEdit`.
    private func saveEdits(to tag: Tag) {
        let name = TagSupport.displayName(for: editName)
        guard !name.isEmpty else { return }
        let previousName = tag.name
        let previousSlug = tag.slug
        let previousDesc = tag.desc
        let previousColorHex = tag.colorHex
        let previousUpdatedAt = tag.updatedAt

        tag.name = name
        tag.slug = TagSupport.slug(for: name)
        tag.desc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = TagSupport.normalizedColorHex(editColorHex)
        tag.updatedAt = Date()

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                tag.name = previousName
                tag.slug = previousSlug
                tag.desc = previousDesc
                tag.colorHex = previousColorHex
                tag.updatedAt = previousUpdatedAt
            }
        } catch {
            editFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        editFailureNotice = nil
        editingTag = nil
    }

    /// The same shape as `saveEdits(to:)`: archiving takes the tag out of every picker in the app,
    /// so a sheet that closed over a refused archive left the tag visible everywhere with no sign
    /// that anything had failed.
    private func archive(_ tag: Tag) {
        let previousIsArchived = tag.isArchived
        let previousUpdatedAt = tag.updatedAt
        tag.isArchived = true
        tag.updatedAt = Date()

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                tag.isArchived = previousIsArchived
                tag.updatedAt = previousUpdatedAt
            }
        } catch {
            editFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        editFailureNotice = nil
        editingTag = nil
    }
}

private struct TagEditSheet: View {
    let tag: Tag
    let allTags: [Tag]
    @Binding var name: String
    @Binding var description: String
    @Binding var colorHex: String
    let failureNotice: String?
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
                    .foregroundStyle(Theme.red)
            }

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
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

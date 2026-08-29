#if os(macOS)
import SwiftUI
import SwiftData

struct SettingsTagsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @State private var newTagName = ""
    @State private var newTagDescription = ""
    @State private var newTagColorHex = TagSupport.colorOptions[2]
    /// T-497: the creator's one failure, said under the fields that still hold the draft.
    @State private var createFailureNotice: String?

    private var activeTags: [Tag] {
        TagSupport.uniqueBySlug(tags.filter { !$0.isArchived })
    }

    private var archivedTags: [Tag] {
        TagSupport.uniqueBySlug(tags.filter(\.isArchived))
    }

    private var newTagSlug: String {
        TagSupport.slug(for: newTagName)
    }

    private var matchingArchivedTag: Tag? {
        guard !TagSupport.displayName(for: newTagName).isEmpty else { return nil }
        return archivedTags.first { $0.slug == newTagSlug }
    }

    private var hasDuplicateSlug: Bool {
        guard !TagSupport.displayName(for: newTagName).isEmpty else { return false }
        return tags.contains { !$0.isArchived && $0.slug == newTagSlug }
    }

    private var canCreateTag: Bool {
        let displayName = TagSupport.displayName(for: newTagName)
        return !displayName.isEmpty &&
            displayName.rangeOfCharacter(from: .alphanumerics) != nil &&
            !hasDuplicateSlug &&
            matchingArchivedTag == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CadenceFieldSection(title: "Create Tag") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color(hex: newTagColorHex))
                            .frame(width: 12, height: 12)
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                tagTextField("Name", text: $newTagName)
                                    .frame(minWidth: 180)
                                tagTextField("Optional description", text: $newTagDescription)
                            }

                            HStack(spacing: 8) {
                                TagColorSwatches(selectedHex: $newTagColorHex)
                                Spacer()
                                SettingsActionButton(tone: .tinted(Theme.blue), action: restoreDefaults) {
                                    Label("Add Defaults", systemImage: "arrow.clockwise")
                                }
                                SettingsActionButton(tone: .filled(Theme.blue), action: createTag) {
                                    Label("Create Tag", systemImage: "plus")
                                }
                                .disabled(!canCreateTag)
                                .opacity(canCreateTag ? 1 : 0.45)
                            }
                        }
                    }

                    if let matchingArchivedTag {
                        TagNoticeRow(
                            icon: "archivebox.fill",
                            text: "\"\(matchingArchivedTag.name)\" is archived.",
                            actionTitle: "Restore"
                        ) {
                            restore(matchingArchivedTag)
                            clearCreateFields()
                        }
                    } else if hasDuplicateSlug {
                        TagNoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            text: "A tag with this name already exists.",
                            actionTitle: nil,
                            action: {}
                        )
                    }

                    if let createFailureNotice {
                        CadenceInlineFailureNotice(text: createFailureNotice)
                    }
                }
            }

            if activeTags.isEmpty {
                CadenceFieldSection(title: "Active Tags") {
                    EmptyTagCatalogRow(title: "No active tags.", subtitle: "Create a tag or add the default set.")
                }
            } else {
                // The catalog is a grid of cards, not rows in a card, so it keeps the eyebrow
                // without the section's own card behind it — `CadenceFieldSection(style: .ruled)`
                // is the spelling for a group whose content supplies its own surfaces.
                CadenceFieldSection(title: "Active Tags", style: .ruled) {
                    tagCatalog(activeTags, isArchivedList: false)
                }
            }

            if !archivedTags.isEmpty {
                CadenceFieldSection(title: "Archived Tags", style: .ruled) {
                    tagCatalog(archivedTags, isArchivedList: true)
                }
            }
        }
        .onAppear {
            TagSupport.seedDefaultTags(in: modelContext)
        }
    }

    private func tagCatalog(_ list: [Tag], isArchivedList: Bool) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(list) { tag in
                SettingsTagRow(
                    tag: tag,
                    allTags: tags,
                    isArchivedList: isArchivedList,
                    onArchive: { archive(tag) },
                    onRestore: { restore(tag) }
                )
            }
        }
    }

    /// The creator's two fields and `SettingsTagRow.editField` were byte-identical private wells —
    /// radius 8, `.stroke` rather than `.strokeBorder`, their own padding — beside the one the
    /// shared `CadenceSettingsField` draws. They are the shared well now (T-286). It stays a helper
    /// only because these fields are placeholder-only and so have no eyebrow for the titled
    /// component to draw.
    private func tagTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .cadenceSettingsWell()
    }

    /// T-497, the existence half of the `try? save()` rule — and the same function on iOS, in
    /// `iOSSettingsTagsSection.createTag`. It inserted a tag, swallowed the save and cleared the
    /// fields, so the draft was gone whether or not the store took the tag. Clearing the fields is
    /// this screen's only report of success, so it now happens on the committed path alone; a
    /// refused insert is un-inserted by `commitInsert` and the draft stays where the user can
    /// press Create Tag again.
    private func createTag() {
        guard canCreateTag else { return }
        let name = TagSupport.displayName(for: newTagName)
        let tag = Tag(
            name: name,
            slug: TagSupport.slug(for: name),
            desc: newTagDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: TagSupport.normalizedColorHex(newTagColorHex),
            order: (tags.map(\.order).max() ?? -1) + 1
        )
        modelContext.insert(tag)
        do {
            try CadencePendingChangePersistence.commitInsert(of: tag, in: modelContext)
        } catch {
            createFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        createFailureNotice = nil
        clearCreateFields()
    }

    private func clearCreateFields() {
        newTagName = ""
        newTagDescription = ""
        newTagColorHex = TagSupport.colorOptions[2]
    }

    private func archive(_ tag: Tag) {
        tag.isArchived = true
        tag.updatedAt = Date()
        try? modelContext.save()
    }

    private func restore(_ tag: Tag) {
        tag.isArchived = false
        tag.updatedAt = Date()
        try? modelContext.save()
    }

    private func restoreDefaults() {
        TagSupport.seedDefaultTags(in: modelContext)
    }
}

private struct SettingsTagRow: View {
    let tag: Tag
    let allTags: [Tag]
    let isArchivedList: Bool
    let onArchive: () -> Void
    let onRestore: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var draftColorHex = ""
    /// T-497: the row's own failure line, which is why the row can stay open over a refused save.
    @State private var saveFailureNotice: String?

    private var taskCount: Int {
        tag.tasks?.count ?? 0
    }

    private var noteCount: Int {
        tag.notes?.count ?? 0
    }

    private var draftSlug: String {
        TagSupport.slug(for: draftName)
    }

    private var hasDuplicateSlug: Bool {
        allTags.contains { $0.id != tag.id && $0.slug == draftSlug }
    }

    private var canSave: Bool {
        !TagSupport.displayName(for: draftName).isEmpty && !hasDuplicateSlug
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                editContent
            } else {
                displayContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
        .opacity(tag.isArchived ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(tag.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if tag.isArchived {
                            Text("Archived")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.surfaceElevated.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if !tag.desc.isEmpty {
                        Text(tag.desc)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    rowButton(icon: "pencil", help: "Edit tag") {
                        startEditing()
                    }
                    if isArchivedList {
                        rowButton(icon: "arrow.uturn.backward", color: Theme.blue, help: "Restore tag", action: onRestore)
                    } else {
                        rowButton(icon: "archivebox", color: Theme.amber, help: "Archive tag", action: onArchive)
                    }
                }
            }

            HStack(spacing: 7) {
                TagUsageBadge(text: taskCount == 1 ? "1 task" : "\(taskCount) tasks")
                TagUsageBadge(text: noteCount == 1 ? "1 note" : "\(noteCount) notes")
                Spacer()
            }
        }
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(hex: TagSupport.normalizedColorHex(draftColorHex, fallback: tag.colorHex)))
                    .frame(width: 12, height: 12)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        editField("Name", text: $draftName)
                            .frame(minWidth: 180)
                        editField("Description", text: $draftDescription)
                    }

                    HStack(spacing: 8) {
                        TagColorSwatches(selectedHex: $draftColorHex)
                        editField("#hex", text: $draftColorHex)
                            .frame(width: 96)
                    }
                }
            }

            if hasDuplicateSlug {
                Text("A tag with this name already exists.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .padding(.leading, 24)
            }

            if let saveFailureNotice {
                CadenceInlineFailureNotice(text: saveFailureNotice)
                    .padding(.leading, 24)
            }

            HStack {
                Spacer()
                SettingsActionButton(tone: .tinted(Theme.dim), action: cancelEditing) {
                    Text("Cancel")
                }
                SettingsActionButton(tone: .filled(Theme.blue), action: saveEdits) {
                    Text("Save")
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }
        }
    }

    private func editField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .cadenceSettingsWell()
    }

    private func rowButton(icon: String, color: Color = Theme.dim, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .help(help)
    }

    private func startEditing() {
        saveFailureNotice = nil
        draftName = tag.name
        draftDescription = tag.desc
        draftColorHex = tag.colorHex
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = true
        }
    }

    private func cancelEditing() {
        saveFailureNotice = nil
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
    }

    /// T-497, the report half of the `try? save()` rule. An inline row editor collapsing back to
    /// its display row is a dismissal — it just has no sheet to say so with — and this one
    /// collapsed over a name the store may not hold, leaving the catalog reading one thing and the
    /// store another with nothing on screen disagreeing.
    ///
    /// The undo restores the five fields written above rather than rolling the context back: this
    /// is the app's single `ModelContext`, and a rollback here would discard whatever unrelated
    /// work another screen has pending. See `CadencePendingChangePersistence.commitEdit`.
    private func saveEdits() {
        guard canSave else { return }
        let previousName = tag.name
        let previousSlug = tag.slug
        let previousDesc = tag.desc
        let previousColorHex = tag.colorHex
        let previousUpdatedAt = tag.updatedAt

        let name = TagSupport.displayName(for: draftName)
        tag.name = name
        tag.slug = TagSupport.slug(for: name)
        tag.desc = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = TagSupport.normalizedColorHex(draftColorHex, fallback: tag.colorHex)
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
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
    }
}

private struct TagUsageBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(Capsule())
    }
}

private struct TagColorSwatches: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TagSupport.colorOptions, id: \.self) { option in
                Button {
                    selectedHex = option
                } label: {
                    Circle()
                        .fill(Color(hex: option))
                        .frame(width: 18, height: 18)
                        .overlay {
                            if TagSupport.normalizedColorHex(selectedHex).caseInsensitiveCompare(option) == .orderedSame {
                                Circle()
                                    .stroke(Theme.text.opacity(0.78), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.cadencePlain)
                .help(option)
            }
        }
    }
}

private struct TagNoticeRow: View {
    let icon: String
    let text: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct EmptyTagCatalogRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        CadenceSettingsNoticeRow(
            systemImage: "tag",
            tint: Theme.dim,
            title: title,
            detail: subtitle
        ) {
            EmptyView()
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import SwiftData

struct SettingsTagsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @State private var newTagName = ""
    @State private var newTagDescription = ""
    @State private var newTagColorHex = TagSupport.colorOptions[2]

    private var activeTags: [Tag] {
        TagSupport.sorted(tags.filter { !$0.isArchived })
    }

    private var archivedTags: [Tag] {
        TagSupport.sorted(tags.filter(\.isArchived))
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
            SettingsSectionLabel(text: "Create Tag")
            SettingsCard {
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
                }
            }

            SettingsSectionLabel(text: "Active Tags")
            SettingsCard {
                if activeTags.isEmpty {
                    EmptyTagCatalogRow(title: "No active tags.", subtitle: "Create a tag or add the default set.")
                } else {
                    tagList(activeTags, isArchivedList: false)
                }
            }

            if !archivedTags.isEmpty {
                SettingsSectionLabel(text: "Archived Tags")
                SettingsCard {
                    tagList(archivedTags, isArchivedList: true)
                }
            }
        }
        .onAppear {
            TagSupport.seedDefaultTags(in: modelContext)
        }
    }

    private func tagList(_ list: [Tag], isArchivedList: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, tag in
                SettingsTagRow(
                    tag: tag,
                    allTags: tags,
                    isArchivedList: isArchivedList,
                    onArchive: { archive(tag) },
                    onRestore: { restore(tag) }
                )
                if index < list.count - 1 {
                    Divider()
                        .background(Theme.borderSubtle)
                        .padding(.leading, 42)
                }
            }
        }
    }

    private func tagTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
    }

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
        try? modelContext.save()
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

    private var taskCount: Int {
        tag.tasks?.count ?? 0
    }

    private var noteCount: Int {
        tag.notes?.count ?? 0
    }

    private var usageText: String {
        "\(taskCount) task\(taskCount == 1 ? "" : "s"), \(noteCount) note\(noteCount == 1 ? "" : "s")"
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
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }

    private var displayContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, 5)
                .opacity(tag.isArchived ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    TagMiniChip(tag: tag)
                    Text(tag.slug)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                if !tag.desc.isEmpty {
                    Text(tag.desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(usageText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

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
        .padding(.horizontal, 2)
        .opacity(tag.isArchived ? 0.72 : 1)
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
        .padding(.horizontal, 2)
    }

    private func editField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
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
        draftName = tag.name
        draftDescription = tag.desc
        draftColorHex = tag.colorHex
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = true
        }
    }

    private func cancelEditing() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
    }

    private func saveEdits() {
        guard canSave else { return }
        let name = TagSupport.displayName(for: draftName)
        tag.name = name
        tag.slug = TagSupport.slug(for: name)
        tag.desc = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = TagSupport.normalizedColorHex(draftColorHex, fallback: tag.colorHex)
        tag.updatedAt = Date()
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = false
        }
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
        HStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}
#endif

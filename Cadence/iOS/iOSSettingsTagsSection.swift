#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTagsSettingsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newColorHex = TagSupport.colorOptions[2]

    private var activeTags: [Tag] {
        TagSupport.sorted(tags.filter { !$0.isArchived })
    }

    private var archivedTags: [Tag] {
        TagSupport.sorted(tags.filter(\.isArchived))
    }

    private var newSlug: String {
        TagSupport.slug(for: newName)
    }

    private var hasDuplicate: Bool {
        guard !TagSupport.displayName(for: newName).isEmpty else { return false }
        return activeTags.contains { $0.slug == newSlug }
    }

    private var matchingArchived: Tag? {
        guard !TagSupport.displayName(for: newName).isEmpty else { return nil }
        return archivedTags.first { $0.slug == newSlug }
    }

    private var canCreate: Bool {
        let display = TagSupport.displayName(for: newName)
        return !display.isEmpty &&
            display.rangeOfCharacter(from: .alphanumerics) != nil &&
            !hasDuplicate &&
            matchingArchived == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Create Tag")
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("Optional description", text: $newDescription)
                        .textFieldStyle(.roundedBorder)

                    iOSTagColorPicker(selectedHex: $newColorHex)

                    if let matchingArchived {
                        iOSTagNoticeRow(
                            icon: "archivebox.fill",
                            text: "\"\(matchingArchived.name)\" is archived.",
                            actionTitle: "Restore",
                            action: {
                                restore(matchingArchived)
                                clearDraft()
                            }
                        )
                    } else if hasDuplicate {
                        iOSTagNoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            text: "A tag with this name already exists.",
                            actionTitle: nil,
                            action: {}
                        )
                    }

                    HStack {
                        Button {
                            TagSupport.seedDefaultTags(in: modelContext)
                        } label: {
                            Label("Add Defaults", systemImage: "arrow.clockwise")
                        }
                        .font(.system(size: 12, weight: .semibold))

                        Spacer()

                        Button {
                            createTag()
                        } label: {
                            Label("Create", systemImage: "plus")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blue)
                        .disabled(!canCreate)
                    }
                }
            }

            CadenceSettingsSectionLabel(text: "Active Tags")
            iOSSettingsCard {
                if activeTags.isEmpty {
                    iOSSettingsEmptyRow(title: "No active tags", subtitle: "Create one or add the default set.")
                } else {
                    iOSTagList(tags: activeTags, isArchivedList: false, archive: archive(_:), restore: restore(_:))
                }
            }

            if !archivedTags.isEmpty {
                CadenceSettingsSectionLabel(text: "Archived Tags")
                iOSSettingsCard {
                    iOSTagList(tags: archivedTags, isArchivedList: true, archive: archive(_:), restore: restore(_:))
                }
            }
        }
        .onAppear {
            TagSupport.seedDefaultTags(in: modelContext)
        }
    }

    private func createTag() {
        guard canCreate else { return }
        let displayName = TagSupport.displayName(for: newName)
        let tag = Tag(
            name: displayName,
            slug: TagSupport.slug(for: displayName),
            desc: newDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: TagSupport.normalizedColorHex(newColorHex),
            order: (tags.map(\.order).max() ?? -1) + 1
        )
        modelContext.insert(tag)
        try? modelContext.save()
        clearDraft()
    }

    private func clearDraft() {
        newName = ""
        newDescription = ""
        newColorHex = TagSupport.colorOptions[2]
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
}

private struct iOSTagList: View {
    let tags: [Tag]
    let isArchivedList: Bool
    let archive: (Tag) -> Void
    let restore: (Tag) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                iOSTagSettingsRow(
                    tag: tag,
                    isArchivedList: isArchivedList,
                    archive: { archive(tag) },
                    restore: { restore(tag) }
                )

                if index < tags.count - 1 {
                    Divider().background(Theme.borderSubtle)
                }
            }
        }
    }
}

private struct iOSTagSettingsRow: View {
    let tag: Tag
    let isArchivedList: Bool
    let archive: () -> Void
    let restore: () -> Void

    private var usageText: String {
        let taskCount = tag.tasks?.count ?? 0
        let noteCount = tag.notes?.count ?? 0
        return "\(taskCount) task\(taskCount == 1 ? "" : "s"), \(noteCount) note\(noteCount == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(alignment: tag.desc.isEmpty ? .center : .top, spacing: 11) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, tag.desc.isEmpty ? 0 : 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("#\(tag.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tag.isArchived ? Theme.muted : Theme.text)
                    .lineLimit(1)

                Text(usageText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)

                if !tag.desc.isEmpty {
                    Text(tag.desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                isArchivedList ? restore() : archive()
            } label: {
                Image(systemName: isArchivedList ? "arrow.uturn.backward" : "archivebox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isArchivedList ? Theme.blue : Theme.amber)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .opacity(tag.isArchived ? 0.72 : 1)
    }
}

private struct iOSTagColorPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 9) {
            ForEach(TagSupport.colorOptions, id: \.self) { option in
                Button {
                    selectedHex = option
                } label: {
                    Circle()
                        .fill(Color(hex: option))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if TagSupport.normalizedColorHex(selectedHex).caseInsensitiveCompare(option) == .orderedSame {
                                Circle().strokeBorder(Theme.text.opacity(0.78), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct iOSTagNoticeRow: View {
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
#endif

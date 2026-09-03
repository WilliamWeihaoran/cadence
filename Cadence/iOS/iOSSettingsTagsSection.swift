#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTagsSettingsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newColorHex = TagSupport.colorOptions[2]
    /// T-497: the creator's one failure, said under the fields that still hold the draft — macOS's
    /// `SettingsTagsSection.createTag` is the same function and carries the same notice.
    @State private var createFailureNotice: String?
    /// T-653: "Add Defaults"' own failure, said in the same place — macOS's
    /// `SettingsTagsSection.restoreDefaults` is the same function.
    @State private var seedFailureNotice: String?

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
                VStack(alignment: .leading, spacing: 14) {
                    // `.roundedBorder` drew UIKit's own light field chrome into a dark
                    // card — the one place in settings with no palette colour at all.
                    iOSSettingsField(title: "Name") {
                        TextField("Tag name", text: $newName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    iOSSettingsField(title: "Description") {
                        TextField("Optional description", text: $newDescription)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrowLabel(text: "Color")
                        iOSSettingsColorSwatchRow(selectedHex: $newColorHex)
                    }

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

                    if let createFailureNotice {
                        CadenceInlineFailureNotice(text: createFailureNotice)
                    }
                    if let seedFailureNotice {
                        CadenceInlineFailureNotice(text: seedFailureNotice)
                    }

                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        iOSActionButton(
                            title: "Add Defaults",
                            systemImage: "arrow.clockwise",
                            role: .secondary,
                            size: .compact
                        ) {
                            restoreDefaults()
                        }

                        iOSActionButton(
                            title: "Create Tag",
                            systemImage: "plus",
                            role: .primary,
                            size: .compact,
                            isDisabled: !canCreate,
                            action: createTag
                        )
                    }
                }
            }

            CadenceSettingsSectionLabel(text: "Active Tags")
            iOSSettingsCard {
                if activeTags.isEmpty {
                    iOSSettingsEmptyInlineRow(
                        systemImage: "tag",
                        title: CadenceTagSettingsCopy.emptyCatalogTitle,
                        subtitle: CadenceTagSettingsCopy.emptyCatalogSubtitle
                    )
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
        // T-528: the macOS twin is `SettingsTagsSection` and the two are fixed as one. An empty
        // tag list is not evidence the user has never had tags, so appearing on screen does not
        // seed; the "Add Defaults" button above is the one caller that may.
    }

    /// T-497, the existence half of the `try? save()` rule. The macOS twin is
    /// `SettingsTagsSection.createTag` and the two are fixed as one: clearing the draft is the only
    /// report that the tag was made, so it runs on the committed path alone, and a refused insert
    /// is un-inserted by `commitInsert` rather than left pending for another screen's save.
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
        do {
            try CadencePendingChangePersistence.commitInsert(of: tag, in: modelContext)
        } catch {
            createFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        createFailureNotice = nil
        clearDraft()
    }

    private func clearDraft() {
        newName = ""
        newDescription = ""
        newColorHex = TagSupport.colorOptions[2]
    }

    /// T-653, the existence half of the `try? save()` rule. The macOS twin is
    /// `SettingsTagsSection.restoreDefaults`: `seedDefaultTagsCommitting` rolls the whole seed back
    /// on a refusal rather than leaving a half-merged, half-seeded table.
    private func restoreDefaults() {
        do {
            try TagSupport.seedDefaultTagsCommitting(in: modelContext)
            seedFailureNotice = nil
        } catch {
            seedFailureNotice = CadencePendingChangePersistence.editFailureNotice
        }
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
                    iOSRowDivider(leadingInset: 22)
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

    private var taskCount: Int { tag.tasks?.count ?? 0 }
    private var noteCount: Int { tag.notes?.count ?? 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 11, height: 11)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 5) {
                Text("#\(tag.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tag.isArchived ? Theme.muted : Theme.text)
                    .lineLimit(1)

                if !tag.desc.isEmpty {
                    Text(tag.desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Two counts, two chips — the same shape macOS's tag row uses, instead of
                // one comma-joined sentence.
                HStack(spacing: 6) {
                    iOSMetaChip(label: taskCount == 1 ? "1 task" : "\(taskCount) tasks", color: Theme.muted)
                    iOSMetaChip(label: noteCount == 1 ? "1 note" : "\(noteCount) notes", color: Theme.muted)
                }
            }

            Spacer(minLength: 8)

            iOSIconButton(
                systemImage: isArchivedList ? "arrow.uturn.backward" : "archivebox",
                accessibilityLabel: isArchivedList ? "Restore tag" : "Archive tag",
                tint: isArchivedList ? Theme.blue : Theme.amber,
                isSelected: true
            ) {
                isArchivedList ? restore() : archive()
            }
        }
        .padding(.vertical, 8)
        .opacity(tag.isArchived ? 0.72 : 1)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.amber)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionTitle {
                iOSActionButton(
                    title: actionTitle,
                    role: .secondary,
                    size: .compact,
                    action: action
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif

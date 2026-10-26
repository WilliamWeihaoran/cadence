import Foundation
import SwiftData

/// The mobile inline editor's validation and atomic field edit, available to unit tests.
enum iOSTagSettingsEdit {
    static func hasDuplicate(name: String, tag: Tag, allTags: [Tag]) -> Bool {
        let slug = TagSupport.slug(for: name)
        return allTags.contains { $0.id != tag.id && $0.slug == slug }
    }

    static func canSave(name: String, tag: Tag, allTags: [Tag]) -> Bool {
        !TagSupport.displayName(for: name).isEmpty && !hasDuplicate(name: name, tag: tag, allTags: allTags)
    }

    /// `rewritingInlineMentions` is the user's answer to the T-6261 warning, not a default the
    /// caller may skip thinking about: `false` is today's behaviour — the tag splits — and `true`
    /// rewrites `#old` in the note bodies as well. The row above asks before it calls this, and
    /// only when `TagSupport.inlineMentionCount` found something to ask about.
    @MainActor
    static func save(
        tag: Tag, name: String, description: String, colorHex: String,
        allTags: [Tag], in modelContext: ModelContext,
        rewritingInlineMentions: Bool,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard canSave(name: name, tag: tag, allTags: allTags) else { return }
        let previousDesc = tag.desc
        let previousColorHex = tag.colorHex
        let previousUpdatedAt = tag.updatedAt
        let undoRename = TagSupport.rename(tag, to: name, rewritingInlineMentions: rewritingInlineMentions)
        tag.desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = TagSupport.normalizedColorHex(colorHex, fallback: tag.colorHex)
        tag.updatedAt = Date()
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, undo: {
            undoRename()
            tag.desc = previousDesc
            tag.colorHex = previousColorHex
            tag.updatedAt = previousUpdatedAt
        })
    }
}

#if os(iOS)
import SwiftUI

struct iOSTagsSettingsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
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

    /// The create rule, asked rather than computed. `TagSupport.creationDecision(for:in:)` is the
    /// one owner; the same four clauses used to be spelled here and again in macOS's
    /// `SettingsTagsSection`, and neither copy was the rule.
    ///
    /// It takes `tags` — the whole table — not `activeTags`/`archivedTags`, which are this
    /// screen's *display* views and would each answer half the question.
    private var creationDecision: TagSupport.CreationDecision {
        TagSupport.creationDecision(for: newName, in: tags)
    }

    private var hasDuplicate: Bool { creationDecision.activeDuplicate != nil }

    private var matchingArchived: Tag? { creationDecision.archivedMatch }

    private var canCreate: Bool { creationDecision.isCreatable }

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

                    // T-4113(a): at accessibility sizes the two buttons stack, trailing-aligned,
                    // rather than share one row an iPhone card is too narrow for — side by side
                    // they wrapped mid-word ("Add Default" / "s"). Same idiom as the settings rows.
                    let stacksActions = CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling)
                    let actionLayout = stacksActions
                        ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 10))
                        : AnyLayout(HStackLayout(spacing: 10))
                    actionLayout {
                        if !stacksActions { Spacer(minLength: 0) }

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
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                    iOSTagList(tags: activeTags, allTags: tags, isArchivedList: false, archive: archive(_:), restore: restore(_:))
                }
            }

            if !archivedTags.isEmpty {
                CadenceSettingsSectionLabel(text: "Archived Tags")
                iOSSettingsCard {
                    iOSTagList(tags: archivedTags, allTags: tags, isArchivedList: true, archive: archive(_:), restore: restore(_:))
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
        guard case let .creatable(displayName, slug) = creationDecision else { return }
        let tag = Tag(
            name: displayName,
            slug: slug,
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
    let allTags: [Tag]
    let isArchivedList: Bool
    let archive: (Tag) -> Void
    let restore: (Tag) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                iOSTagSettingsRow(
                    tag: tag,
                    allTags: allTags,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var draftColorHex = ""
    @State private var saveFailureNotice: String?
    /// T-6261: the notes whose prose mentions this tag, counted when Save is tapped and held here
    /// while the user answers. Non-`nil` only when the count is non-zero.
    @State private var inlineMentionPrompt: CadenceTagRenameInlineMentions.Prompt?
    let tag: Tag
    let allTags: [Tag]
    let isArchivedList: Bool
    let archive: () -> Void
    let restore: () -> Void

    private var taskCount: Int { tag.tasks?.count ?? 0 }
    private var noteCount: Int { tag.notes?.count ?? 0 }

    private var canSave: Bool {
        iOSTagSettingsEdit.canSave(name: draftName, tag: tag, allTags: allTags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                editContent
            } else {
                displayContent
            }
        }
        .padding(.vertical, 8)
        .opacity(tag.isArchived ? 0.72 : 1)
        // T-6261: the same dialog both macOS editors present, from the same shared modifier. A
        // rename that warns on the Mac and splits silently on the phone is worse than today.
        .cadenceTagRenameInlineConfirmation($inlineMentionPrompt) { rewriteInlineMentions in
            saveEdits(rewritingInlineMentions: rewriteInlineMentions)
        }
    }

    private var displayContent: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 11, height: 11)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 5) {
                Text("#\(tag.name)")
                    .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                    .foregroundStyle(tag.isArchived ? Theme.muted : Theme.text)
                    .lineLimit(CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) ? nil : 1)

                if !tag.desc.isEmpty {
                    Text(tag.desc)
                        .cadenceFont(.metadata, base: 12, weight: .regular)
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Two counts, two chips — the same shape macOS's tag row uses, instead of
                // one comma-joined sentence. T-4113(a): stacked at accessibility sizes, where
                // side by side each wrapped into a two-line oval.
                let countLayout = CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling)
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 6))
                countLayout {
                    iOSMetaChip(label: taskCount == 1 ? "1 task" : "\(taskCount) tasks", color: Theme.muted)
                    iOSMetaChip(label: noteCount == 1 ? "1 note" : "\(noteCount) notes", color: Theme.muted)
                }
            }

            Spacer(minLength: 8)

            iOSIconButton(systemImage: "pencil", accessibilityLabel: "Edit tag") {
                draftName = tag.name
                draftDescription = tag.desc
                draftColorHex = tag.colorHex
                saveFailureNotice = nil
                isEditing = true
            }

            iOSIconButton(
                systemImage: isArchivedList ? "arrow.uturn.backward" : "archivebox",
                accessibilityLabel: isArchivedList ? "Restore tag" : "Archive tag",
                tint: isArchivedList ? Theme.blue : Theme.amber,
                isSelected: true
            ) {
                isArchivedList ? restore() : archive()
            }
        }
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            iOSSettingsField(title: "Name") {
                TextField("Tag name", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            iOSSettingsField(title: "Description") {
                TextField("Optional description", text: $draftDescription, axis: .vertical)
            }
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrowLabel(text: "Color")
                iOSSettingsColorSwatchRow(selectedHex: $draftColorHex, fallbackHex: tag.colorHex)
                iOSSettingsField(title: "Hex") {
                    TextField("#hex", text: $draftColorHex)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            if iOSTagSettingsEdit.hasDuplicate(name: draftName, tag: tag, allTags: allTags) {
                iOSTagNoticeRow(icon: "exclamationmark.triangle.fill",
                                text: "A tag with this name already exists.",
                                actionTitle: nil, action: {})
            }
            if let saveFailureNotice {
                CadenceInlineFailureNotice(text: saveFailureNotice)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                iOSActionButton(title: "Cancel", role: .secondary, size: .compact) {
                    saveFailureNotice = nil
                    isEditing = false
                }
                iOSActionButton(title: "Save", role: .primary, size: .compact,
                                isDisabled: !canSave, action: requestSave)
            }
        }
    }

    /// **The Save button. T-6261: it asks before it edits the user's own sentences.**
    ///
    /// Counted from the notes as they stand, before `rename` changes the text it is counted from.
    /// Nothing mentioned in prose means no dialog and a straight save.
    private func requestSave() {
        guard canSave else { return }
        guard let prompt = CadenceTagRenameInlineMentions.prompt(for: tag, renamedTo: draftName) else {
            saveEdits(rewritingInlineMentions: false)
            return
        }
        inlineMentionPrompt = prompt
    }

    private func saveEdits(rewritingInlineMentions: Bool) {
        guard canSave else { return }
        do {
            try iOSTagSettingsEdit.save(tag: tag, name: draftName, description: draftDescription,
                                       colorHex: draftColorHex, allTags: allTags, in: modelContext,
                                       rewritingInlineMentions: rewritingInlineMentions)
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        isEditing = false
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
                .cadenceFont(.metadata, base: 13, weight: .semibold)
                .foregroundStyle(Theme.amber)

            Text(text)
                .cadenceFont(.metadata, base: 12, weight: .medium)
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

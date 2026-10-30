#if os(iOS)
import SwiftData
import SwiftUI

enum iOSContextEditorMode: Identifiable {
    case new
    case edit(Context)

    var id: String {
        switch self {
        case .new:
            return "new-context"
        case .edit(let context):
            return "context-\(context.id)"
        }
    }
}

/// [[T-5174]] (a): the three fields `iOSContextEditorSheet.save()` writes back for an existing context.
struct iOSContextEditorSheet: View {
    let mode: iOSContextEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @State private var name = ""
    @State private var icon = Self.defaultIcon
    @State private var colorHex = Theme.blueHex
    @State private var hasLoaded = false
    /// [[T-5174]]: the draft as `load()` left it, against which a swipe-down is refused.
    @State private var openedDraft: CadenceContextEditorDraftSnapshot?
    /// Set when the commit was refused. The editor stays open holding it — see `save()`.
    @State private var saveFailureNotice: String?

    private var currentDraft: CadenceContextEditorDraftSnapshot {
        CadenceContextEditorDraftSnapshot(name: name, icon: icon, colorHex: colorHex)
    }

    private static let defaultIcon = "square.stack.fill"

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            // The grouped `Form` this replaced brought UIKit's own row chrome, insets, and
            // separator colours into a surface that sits inside Cadence's settings; the
            // card + field vocabulary is the same one every other settings section uses.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 16) {
                            iOSSettingsField(title: "Name") {
                                TextField("Context name", text: $name)
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                SectionEyebrowLabel(text: "Color")
                                iOSSettingsColorSwatchRow(
                                    selectedHex: $colorHex,
                                    options: Self.colorOptions
                                )
                            }

                            // [[T-8541]]: the shared palette, not a typed SF Symbol name -- a
                            // developer's input, where a typo saved a name that draws nothing.
                            // The list editor and macOS's `CreateContextSheet` offer the same set.
                            VStack(alignment: .leading, spacing: 7) {
                                SectionEyebrowLabel(text: "Icon")
                                iOSListIconStrip(selected: $icon, colorHex: normalizedColor)
                            }
                        }
                    }

                    if let saveFailureNotice {
                        CadenceInlineFailureNotice(text: saveFailureNotice)
                    }

                    CadenceSettingsSectionLabel(text: "Preview")
                    iOSSettingsCard {
                        iOSSettingsContextPreview(
                            name: trimmedName.isEmpty ? "Context" : trimmedName,
                            icon: normalizedIcon,
                            colorHex: normalizedColor
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .cadenceScaledTypography()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Context" : "New Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(Theme.muted)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .tint(Theme.blue)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
            // [[T-5174]]: the [[T-3171]] rule, in both modes since (b). Presented by `.sheet`
            // only (`iOSSettingsView`).
            .interactiveDismissDisabled(
                CadenceSheetDismissGuard.blocksSwipe(opened: openedDraft, current: currentDraft)
            )
        }
        .preferredColorScheme(.dark)
    }

    /// The accent leads, then one lap of the tag palette. Contexts and tags are both
    /// user-coloured labels, so they draw from the same strip rather than from a second
    /// list that would drift away from it.
    private static var colorOptions: [String] {
        [Theme.blueHex] + TagSupport.colorOptions
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .new:
            name = ""
            icon = Self.defaultIcon
            colorHex = Theme.blueHex
        case .edit(let context):
            name = context.name
            icon = context.icon
            colorHex = context.colorHex
        }
        // [[T-5174]] (b): creation snapshots too — a half-typed context name is typed text, and
        // the defaults above are what the sheet opened on.
        openedDraft = currentDraft
    }

    /// T-321: this wrote the context, ran `try? modelContext.save()` and dismissed, so the editor
    /// closed identically whether or not the store took the change. A context scopes task
    /// grouping app-wide, so a rename that did not land is not a cosmetic loss — and the only
    /// thing that ever reported success was the sheet closing.
    ///
    /// The two modes undo differently for the reason
    /// `CadencePendingChangePersistence.commitEdit` gives: a creation deletes what it inserted, an
    /// edit puts back the three fields it wrote. Neither rolls the context back, because this
    /// context is the whole app's.
    private func save() {
        if let clash = activeContextCarryingTheTypedName {
            switch mode {
            case .new: saveFailureNotice = Self.duplicateNameNotice(clash.name)
            case .edit: saveFailureNotice = Self.duplicateRenameNotice(clash.name)
            }
            return
        }
        do {
            switch mode {
            case .new:
                let context = Context(name: trimmedName, colorHex: normalizedColor, icon: normalizedIcon)
                context.order = nextContextOrder()
                modelContext.insert(context)
                try CadencePendingChangePersistence.commitInsert(of: context, in: modelContext)
            case .edit(let context):
                let previousName = context.name
                let previousIcon = context.icon
                let previousColorHex = context.colorHex
                context.name = trimmedName
                context.icon = normalizedIcon
                context.colorHex = normalizedColor
                try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                    context.name = previousName
                    context.icon = previousIcon
                    context.colorHex = previousColorHex
                }
            }
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        dismiss()
    }

    /// The active list this creation or rename would be fused with at the next launch, if there
    /// is one ([[T-3125]], [[T-4722]]).
    ///
    /// `DataIntegrityRepairService` groups active contexts by
    /// `normalizedContextName` and merges every group of more than one — deterministically since
    /// [[T-3101]], but still irreversibly: the separation the user made by naming two lists the
    /// same is gone with no undo. The owner's decision of 2026-10-22 is to refuse the second one
    /// here rather than to narrow that merge, which `mergeArea` and `mergeProject` are reached
    /// through.
    ///
    /// **The rule lives beside the merge**, in `DataIntegrityRepairService.activeContextSharingName`,
    /// so a guard here that allowed a name that merge would still fuse cannot exist — MCP
    /// `create_context` and `update_context` read the same function. An edit excludes the row
    /// being edited, so saving a list under its own name, or a change of case, is not a clash.
    private var activeContextCarryingTheTypedName: Context? {
        switch mode {
        case .new:
            DataIntegrityRepairService.activeContextSharingName(trimmedName, among: contexts)
        case .edit(let context):
            // An archived row is not in the merge's grouping, so renaming one makes no pair; and
            // an unchanged name writes nothing new, so a recolour is never refused.
            context.isArchived || trimmedName == context.name ? nil
                : DataIntegrityRepairService.activeContextSharingName(trimmedName, among: contexts, excluding: context)
        }
    }

    /// [[T-5808]]: the Mac's sentences, from the one shared copy. These said "list".
    static func duplicateNameNotice(_ existingName: String) -> String {
        CadenceContextNameClashCopy.notCreated(existingName)
    }

    static func duplicateRenameNotice(_ existingName: String) -> String {
        CadenceContextNameClashCopy.notRenamed(existingName)
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultIcon : trimmed
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return Theme.blueHex
        }
        return trimmed
    }

    private func nextContextOrder() -> Int {
        (contexts.map(\.order).max() ?? -1) + 1
    }
}

struct iOSSettingsContextRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let context: Context

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex)

            Text(CadenceContextPickerSupport.title(for: context))
                .cadenceFont(.rowTitle, base: 15, weight: .medium)
                .foregroundStyle(Theme.text)
                .lineLimit(CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) ? nil : 1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .cadenceFont(.rowTitle, base: 12, weight: .semibold)
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 10)
        .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

struct iOSSettingsArchivedContextRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let context: Context
    let restore: () -> Void
    /// An archived context is not on any other screen, so this row is the only place it can be
    /// removed from — the same reason macOS puts delete beside its own archived-list rows.
    let delete: () -> Void

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex, opacity: 0.42)

            VStack(alignment: .leading, spacing: 3) {
                Text(CadenceContextPickerSupport.title(for: context))
                    .cadenceFont(.rowTitle, base: 15, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) ? nil : 1)
                Text("Archived")
                    .cadenceFont(.metadata, base: 11, weight: .semibold)
                    .foregroundStyle(Theme.amber)
            }

            Spacer(minLength: 8)

            iOSActionButton(
                title: "Restore",
                role: .secondary,
                size: .compact,
                action: restore
            )

            iOSActionButton(
                title: "Delete",
                role: .destructive,
                size: .compact,
                action: delete
            )
        }
        .padding(.vertical, 6)
    }
}

struct iOSSettingsContextPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let name: String
    let icon: String
    let colorHex: String

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: icon, colorHex: colorHex)

            Text(name)
                .cadenceFont(.rowTitle, base: 15, weight: .medium)
                .foregroundStyle(Theme.text)
                .lineLimit(CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) ? nil : 1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct iOSSettingsContextIcon: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let icon: String
    let colorHex: String
    var opacity: Double = 1

    var body: some View {
        let tint = Color(hex: colorHex)

        Image(systemName: icon)
            .cadenceFont(.rowTitle, base: 15, weight: .semibold)
            .foregroundStyle(tint.opacity(opacity))
            .frame(width: CadenceSettingsTypographyLayout.glyphFrame(iOSSettingsMetrics.glyphSlot, glyph: 15, role: .rowTitle, at: dynamicTypeSize, scaling: scaling), height: CadenceSettingsTypographyLayout.glyphFrame(iOSSettingsMetrics.glyphSlot, glyph: 15, role: .rowTitle, at: dynamicTypeSize, scaling: scaling))
            .background(tint.opacity(0.14 * opacity))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif

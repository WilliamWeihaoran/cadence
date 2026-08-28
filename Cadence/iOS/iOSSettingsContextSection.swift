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

struct iOSContextEditorSheet: View {
    let mode: iOSContextEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @State private var name = ""
    @State private var icon = Self.defaultIcon
    @State private var colorHex = Theme.blueHex
    @State private var hasLoaded = false
    /// Set when the commit was refused. The editor stays open holding it — see `save()`.
    @State private var saveFailureNotice: String?

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

                            iOSSettingsField(title: "Icon") {
                                TextField("SF Symbol name", text: $icon)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
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
    let context: Context

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex)

            Text(context.name.isEmpty ? "Untitled Context" : context.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 10)
        .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

struct iOSSettingsArchivedContextRow: View {
    let context: Context
    let restore: () -> Void
    /// An archived context is not on any other screen, so this row is the only place it can be
    /// removed from — the same reason macOS puts delete beside its own archived-list rows.
    let delete: () -> Void

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex, opacity: 0.42)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.name.isEmpty ? "Untitled Context" : context.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text("Archived")
                    .font(.system(size: 11, weight: .semibold))
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
    let name: String
    let icon: String
    let colorHex: String

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSSettingsContextIcon(icon: icon, colorHex: colorHex)

            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct iOSSettingsContextIcon: View {
    let icon: String
    let colorHex: String
    var opacity: Double = 1

    var body: some View {
        let tint = Color(hex: colorHex)

        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint.opacity(opacity))
            .frame(width: iOSSettingsMetrics.glyphSlot, height: iOSSettingsMetrics.glyphSlot)
            .background(tint.opacity(0.14 * opacity))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif

#if os(macOS)
import SwiftUI
import SwiftData

// **T-286: this file is the one of the seven that mostly resists the shared row vocabulary, and
// that is a finding rather than an omission.**
//
// `CadenceFieldRow` models a *field*: a glyph in a fixed 22pt slot, a quiet 13pt label, and a
// control on the trailing edge. Nothing declared below is one. `ContextSettingsRow` and
// `SidebarTabSettingsRow` are drag sources and drop targets that expand into an inline editor;
// `ArchivedContextRow` and `ListLifecycleRow` carry a status pill and two destructive buttons; all
// four lead with a 28–30pt tinted identity tile, which is the opposite of the fixed-slot bare glyph
// the field row exists to impose. Rebuilding them on `CadenceFieldRow` would mean either losing the
// drag affordance and the tile or passing them through as `content`, which is the shared component
// in name only — and the standing rule is that forcing a row that does not fit is worse than
// leaving it.
//
// What did convert is the chrome that is genuinely shared and was re-typed anyway: the context
// rename field now draws the one settings well (it was radius 7, `.stroke`, 8pt padding — a third
// private spelling of the same rectangle), and the sidebar-tab editor's "Color" heading is
// `SectionEyebrowLabel`, which `ContextSettingsRow` two hundred lines above was already using for
// the identical label in the identical role.
//
// Left deliberately: `SidebarTabEditorSheet.settingsPanelRow` — a title/subtitle/accessory line on
// its own card. It is close to `CadenceSettingsNoticeRow` and differs by having no state glyph, and
// inventing one to reach the shared component would be adding a verdict where the sheet reports
// none. Recorded as residue rather than bent.

struct ContextSettingsRow: View {
    @Bindable var context: Context
    /// Hands back the id of the context that was **dragged onto this row** — not this row's own
    /// id. Named for what it carries: as `onDropBefore` it read like the drop *target*, and the
    /// call site duly passed it into the target slot and this row's `context.id` into the dragged
    /// slot, so dropping C onto A reordered A instead of C.
    let onDropDraggedContext: (UUID) -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editColor = ""
    @State private var editIcon = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: isEditing ? editColor : context.colorHex).opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: isEditing ? editIcon : context.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: isEditing ? editColor : context.colorHex))
                    }

                Text(isEditing ? (editName.isEmpty ? context.name : editName) : context.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)

                Spacer()

                if isHovered && !isEditing {
                    HStack(spacing: 4) {
                        actionButton(icon: "pencil") { startEditing() }
                        actionButton(icon: "archivebox", color: Theme.amber) { onArchive() }
                        actionButton(icon: "trash", color: Theme.red) { onDelete() }
                    }
                    .transition(.opacity)
                }

                if !isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDropTarget ? Theme.blue.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTarget ? Theme.blue.opacity(0.45) : Color.clear, lineWidth: 1)
            )

            if isEditing {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Context name", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .cadenceSettingsWell()

                    SectionEyebrowLabel(text: "Color")
                    ColorGrid(selected: $editColor)

                    SectionEyebrowLabel(text: "Icon")
                    IconGrid(selected: $editIcon)

                    HStack {
                        Spacer()
                        CadenceActionButton(
                            title: "Cancel",
                            role: .ghost,
                            size: .compact
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { isEditing = false }
                        }

                        CadenceActionButton(
                            title: "Save",
                            role: .primary,
                            size: .compact,
                            isDisabled: CadenceTitleNormalization.isBlank(editName)
                        ) {
                            saveEdit()
                        }
                    }
                    .padding(.bottom, 4)
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
        .onHover { isHovered = $0 }
        .draggable(context.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.compactMap(UUID.init(uuidString:)).first else { return false }
            onDropDraggedContext(draggedID)
            isDropTarget = false
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }

    @ViewBuilder
    private func actionButton(icon: String, color: Color = Theme.dim, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
    }

    private func startEditing() {
        editName = context.name
        editColor = context.colorHex
        editIcon = context.icon
        withAnimation(.easeInOut(duration: 0.15)) { isEditing = true }
    }

    private func saveEdit() {
        let trimmed = CadenceTitleNormalization.normalized(editName)
        guard !trimmed.isEmpty else { return }
        context.name = trimmed
        context.colorHex = editColor
        context.icon = editIcon
        withAnimation(.easeInOut(duration: 0.15)) { isEditing = false }
    }
}

struct ArchivedContextRow: View {
    let context: Context
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: context.colorHex).opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: context.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: context.colorHex).opacity(0.5))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text("Archived")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }

            Spacer()

            Button("Restore", action: onRestore)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Delete", action: onDelete)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 10)
    }
}

struct SidebarTabSettingsRow: View {
    let destination: SidebarStaticDestination
    let tintHex: String
    let isVisible: Bool
    let onEdit: () -> Void
    let onDropBefore: (SidebarStaticDestination) -> Void

    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: tintHex).opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: destination.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: tintHex))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Text(isVisible ? "Visible in sidebar" : "Hidden from sidebar")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTarget ? Theme.blue.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTarget ? Theme.blue.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .draggable(destination.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = SidebarStaticDestination(rawValue: raw) else { return false }
            onDropBefore(dragged)
            isDropTarget = false
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}

struct SidebarTabEditorSheet: View {
    let destination: SidebarStaticDestination
    @Binding var tintHex: String
    @Binding var isVisible: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: tintHex).opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: destination.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: tintHex))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.label)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Set this tab's color and visibility.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrowLabel(text: "Color")

                // `destinationTints`, not the list palette: this edits a destination's glyph tint,
                // whose default is a `Theme` accent, and the twelve-hue list palette does not
                // contain `Theme.tealHex` — so Focus's editor drew a thirteenth swatch beside the
                // palette's own `#14b8a6` and could never get teal back once anything else was
                // tapped (T-245).
                ColorGrid(selected: $tintHex, palette: CadenceColorPalette.destinationTints)
            }

            settingsPanelRow(
                title: "Visible in Sidebar",
                subtitle: "Turn this off to hide the tab without losing its place."
            ) {
                Toggle("", isOn: $isVisible)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.blue)
            }

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Done",
                    role: .primary,
                    size: .compact
                ) {
                    dismiss()
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func settingsPanelRow<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .cadenceCard(cornerRadius: Theme.radiusCard)
    }
}

struct ListLifecycleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let statusLabel: String
    let primaryLabel: String
    let onPrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusLabel == "Completed" ? Theme.green : Theme.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((statusLabel == "Completed" ? Theme.green : Theme.amber).opacity(0.14))
                        .clipShape(Capsule())
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Button(primaryLabel, action: onPrimary)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Delete", action: onDelete)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 10)
    }
}
#endif

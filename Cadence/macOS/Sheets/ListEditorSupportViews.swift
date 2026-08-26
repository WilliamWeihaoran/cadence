#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Sheet shell

/// Eyebrow + content + footer, shared by the three list sheets.
///
/// Deliberately has **no** `ScrollView` and **no** fixed height: colour and icon are always-visible
/// strips rather than expanding rows, so the sheet's height is constant and can size to content.
///
/// The footer has a leading slot for whole-list lifecycle actions (Archive, Delete). Those live
/// here, not in the field well, so a destructive action never shares a surface with a routine one.
struct ListEditorSheetShell<Content: View, FooterLeading: View>: View {
    let title: String
    /// Right-hand note in the eyebrow, e.g. "in Work".
    var titleTrailing: String? = nil
    let confirmTitle: String
    let isConfirmDisabled: Bool
    let onConfirm: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footerLeading: FooterLeading

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The sheet's own name is an eyebrow, not a heading: the thing you actually read at the
            // top is the list you are editing, typed into the header below.
            HStack(spacing: 8) {
                SectionEyebrowLabel(text: title)
                Spacer(minLength: 0)
                if let titleTrailing {
                    Text(titleTrailing)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                footerLeading
                Spacer(minLength: 12)
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                    dismiss()
                }
                CadenceActionButton(
                    title: confirmTitle,
                    role: .primary,
                    size: .compact,
                    isDisabled: isConfirmDisabled
                ) {
                    onConfirm()
                }
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(Theme.surface)
    }
}

extension ListEditorSheetShell where FooterLeading == EmptyView {
    init(
        title: String,
        titleTrailing: String? = nil,
        confirmTitle: String,
        isConfirmDisabled: Bool,
        onConfirm: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            titleTrailing: titleTrailing,
            confirmTitle: confirmTitle,
            isConfirmDisabled: isConfirmDisabled,
            onConfirm: onConfirm,
            content: content,
            footerLeading: { EmptyView() }
        )
    }
}

// MARK: - Identity header

/// Colour/icon tile beside an inline-editable name, then colour and icon as always-visible strips.
///
/// The name is a title you type into rather than a bordered form field, and appearance is chosen in
/// place: no rows, no disclosure, no chevron, so the sheet never changes height while you use it.
///
/// `details` is the list's `desc`, and it is optional because `CreateContextSheet` uses this header
/// for a model that has no such field. Where it is passed it sits directly under the name and above
/// the appearance strips, which is where iOS's list editor puts it (T-330): before that, `Area.desc`
/// and `Project.desc` could be written on iPhone, were indexed by *both* platforms' search, and
/// could not be read or edited anywhere on the Mac.
///
/// One line, not iOS's `2...5`. That is the shell's own constraint rather than a style choice —
/// `ListEditorSheetShell` has no `ScrollView` and no fixed height, so a field that grows as you type
/// would make the sheet grow with it, which is exactly what the strips above exist to avoid.
struct ListEditorIdentityHeader: View {
    @Binding var name: String
    @Binding var colorHex: String
    @Binding var icon: String
    var placeholder: String = "List name…"
    var details: Binding<String>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ListEditorIdentityTile(colorHex: colorHex, icon: icon)

                    TextField(placeholder, text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if let details {
                    TextField("Description", text: details)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            ListEditorColorStrip(selected: $colorHex)
            ListEditorIconStrip(selected: $icon, colorHex: colorHex)
        }
    }
}

/// Live preview of the two choices below it. Not itself a control — the strips are the controls.
private struct ListEditorIdentityTile: View {
    let colorHex: String
    let icon: String

    var body: some View {
        let tint = Color(hex: colorHex)
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)

        shape
            .fill(tint.opacity(0.16))
            .overlay(shape.strokeBorder(tint.opacity(0.32), lineWidth: 1))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: 38, height: 38)
    }
}

// MARK: - Colour strip

/// The twelve palette colours on one line, current selection ringed.
///
/// Shares `ColorGrid`'s palette and its stored-colour rule, so a list holding a hex the palette no
/// longer offers still shows a ringed swatch and is never silently re-coloured on open.
struct ListEditorColorStrip: View {
    @Binding var selected: String

    private let swatchSize: CGFloat = 20
    private let rowHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CadenceColorPalette.offeredColors(for: selected), id: \.self) { hex in
                let isSelected = CadenceColorPalette.matches(hex, selected)
                Button {
                    selected = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.text, lineWidth: 1.5)
                                .padding(-4)
                                .opacity(isSelected ? 1 : 0)
                        )
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Selected colour" : "Use this colour")
            }
        }
    }
}

// MARK: - Icon strip

/// The icons people actually pick, on one line, with the full set one click away.
struct ListEditorIconStrip: View {
    @Binding var selected: String
    let colorHex: String

    @State private var showAll = false

    /// Eight glyphs that cover most lists. The current icon is prepended when it is not one of
    /// them, so the strip always shows what is selected instead of hiding it behind "More…".
    static let common = [
        "folder.fill", "checklist", "briefcase.fill", "graduationcap.fill",
        "house.fill", "heart.fill", "star.fill", "flag.fill",
    ]

    private var offered: [String] {
        guard !selected.isEmpty, !Self.common.contains(selected) else { return Self.common }
        return [selected] + Self.common
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(offered, id: \.self) { icon in
                ListEditorIconCell(
                    icon: icon,
                    isSelected: icon == selected,
                    tint: Color(hex: colorHex)
                ) {
                    selected = icon
                }
            }

            ListEditorIconCell(
                icon: "ellipsis",
                isSelected: false,
                tint: Color(hex: colorHex),
                help: "More icons"
            ) {
                showAll.toggle()
            }
            .popover(isPresented: $showAll, arrowEdge: .bottom) {
                ScrollView {
                    IconGrid(selected: $selected)
                        .padding(12)
                }
                .frame(maxHeight: 320)
                .background(Theme.surfaceElevated)
                .onChange(of: selected) { _, _ in showAll = false }
            }

            Spacer(minLength: 0)
        }
    }
}

/// One icon cell. Hover and selection share a single fill on a single shape — never two layers.
private struct ListEditorIconCell: View {
    let icon: String
    let isSelected: Bool
    let tint: Color
    var help: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? tint : Theme.muted)
                .frame(width: 28, height: 28)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(isSelected ? tint.opacity(0.35) : Color.clear, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .modifier(ListEditorOptionalHelp(text: help))
    }

    private var fill: Color {
        if isSelected { return tint.opacity(0.16) }
        return isHovered ? Theme.surfaceHover : Theme.surfaceElevated
    }
}

/// `.help()` only when there is something to say — an empty help string still arms a tooltip.
private struct ListEditorOptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

// MARK: - Check row

/// A boolean field row. The mark is right-aligned and reads as "on", so a setting that is off
/// leaves nothing behind — a switch would have been the loudest thing in the sheet.
struct ListEditorCheckRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            TaskInspectorFieldRow(label: label, reservesIconSlot: false) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .opacity(isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Apple Calendar row

struct ListEditorCalendarRow: View {
    let calendars: [EKCalendar]
    @Binding var selectedID: String

    @State private var showPicker = false

    private var selectedTitle: String? {
        calendars.first { $0.calendarIdentifier == selectedID }?.title
    }

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Apple Calendar",
            reservesIconSlot: false,
            valueText: selectedTitle ?? "None",
            isSet: selectedTitle != nil
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ScrollView {
                CadenceCalendarPickerList(
                    calendars: calendars,
                    selectedID: $selectedID,
                    onPick: { showPicker = false }
                )
            }
            .frame(width: 260)
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }
}

// MARK: - Lifecycle

enum ListEditorLifecycleChoice: CaseIterable {
    case active, completed, archived

    /// What this choice does to the work still open in the list, as a value rather than as a branch
    /// inside a sheet's `apply(_:)`.
    ///
    /// Both edit sheets used to switch on the choice and call
    /// `completeRemainingActiveTasks` / `cancelRemainingActiveTasks` by hand. Swapping those two
    /// calls — so that archiving a list marked its leftovers *done* and completing one cancelled
    /// them — kept every test green, because the only assertion counted both names over the whole
    /// file and both counts were unchanged (`docs/TODO.md` T-161). The mapping is here, and
    /// `CadenceListWindDownSurfaceTests` states it as an equality.
    ///
    /// `nil` for `.active`: reopening a list settles nothing. That is deliberately not
    /// `.done`-with-an-empty-set, because "there is no wind-down" and "wind down zero tasks" are
    /// different sentences and only the first one is true here.
    var windDownOutcome: CadenceWindDownOutcome? {
        switch self {
        case .active: return nil
        case .completed: return .done
        case .archived: return .cancelled
        }
    }
}

/// Status as one field row plus a picker.
///
/// The picker carries the active/completed axis only. Archiving is a footer button, and offering it
/// here as well would be two routes to one state — the row reports where the list is (including
/// paused, cancelled, or archived, which the picker never sets), the buttons move it.
struct ListEditorStatusRow: View {
    /// "Area" or "Project" — the picker explains what happens to *this* kind of list.
    let noun: String
    /// Shown as the row value. Not derived from the choices: a project can also be paused or
    /// cancelled, and the row must not claim otherwise.
    let statusLabel: String
    let onSelect: (ListEditorLifecycleChoice) -> Void

    @State private var showPicker = false

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Status",
            reservesIconSlot: false,
            valueText: statusLabel,
            isSet: true
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                choiceRow(
                    .active,
                    title: "Active",
                    subtitle: "Show \(noun.lowercased()) in the sidebar."
                )
                choiceRow(
                    .completed,
                    title: "Completed",
                    subtitle: "Hide it from the active sidebar but keep it restorable."
                )
            }
            .padding(6)
            .frame(width: 300)
            .background(Theme.surface)
        }
    }

    @ViewBuilder
    private func choiceRow(_ choice: ListEditorLifecycleChoice, title: String, subtitle: String) -> some View {
        Button {
            showPicker = false
            onSelect(choice)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
    }
}

/// Footer archive/unarchive button. Archiving is recoverable from Settings → Lists, so this is a
/// neutral action button — it must not borrow Delete's red.
struct ListEditorArchiveButton: View {
    let isArchived: Bool
    /// "Area" or "Project", used for the help text only.
    let noun: String
    let action: () -> Void

    var body: some View {
        CadenceActionButton(
            title: isArchived ? "Unarchive" : "Archive",
            // Deliberately not `arrow.up.bin`: a bin glyph next to a red Delete would read as
            // undoing a deletion rather than returning a list to the sidebar.
            systemImage: isArchived ? "tray.and.arrow.up" : "archivebox",
            role: .secondary,
            size: .compact,
            tint: Theme.muted,
            action: action
        )
        .help(
            isArchived
                ? "Return this \(noun.lowercased()) to the sidebar."
                : "Store this \(noun.lowercased()) away and cancel its remaining tasks. Recoverable from Settings → Lists."
        )
    }
}

/// Footer delete button. Sits opposite Cancel/Save, away from both the field well and the confirm
/// button.
struct ListEditorDeleteButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        CadenceActionButton(
            title: title,
            systemImage: "trash",
            role: .destructive,
            size: .compact,
            action: action
        )
    }
}
#endif

#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Sheet shell

/// Title bar + content + confirm/cancel footer, shared by the three list sheets.
///
/// Deliberately has **no** `ScrollView` and **no** fixed height: the appearance rows expand one at
/// a time, so the sheet can size to its content instead of clipping a grid mid-row.
struct ListEditorSheetShell<Content: View>: View {
    let title: String
    /// Right-hand note in the title bar, e.g. "in Work".
    var titleTrailing: String? = nil
    let confirmTitle: String
    let isConfirmDisabled: Bool
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let titleTrailing {
                    Text(titleTrailing)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
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

// MARK: - Name field

struct ListEditorNameField: View {
    @Binding var name: String
    var placeholder: String = "List name…"

    var body: some View {
        TextField(placeholder, text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Theme.text)
            .padding(10)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))
    }
}

// MARK: - Appearance rows

/// Colour and icon as two inspector rows whose pickers open inline beneath them.
///
/// The expanded field is one optional, so opening either collapses the other by construction —
/// that mutual exclusion is what keeps the sheet on screen without a scroll view.
struct ListEditorAppearanceRows: View {
    @Binding var colorHex: String
    @Binding var icon: String

    private enum Field { case color, icon }

    @State private var expanded: Field?

    var body: some View {
        Group {
            ListEditorExpandableRow(
                label: "Color",
                icon: "paintpalette",
                iconColor: Color(hex: colorHex),
                isExpanded: expanded == .color,
                toggle: { toggle(.color) }
            ) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Theme.onColorBorder, lineWidth: 1))
            } expansion: {
                ColorGrid(selected: $colorHex, columns: 6, swatchSize: 26, spacing: 10)
            }

            TaskInspectorFieldDivider()

            ListEditorExpandableRow(
                label: "Icon",
                icon: "square.grid.2x2",
                iconColor: Color(hex: colorHex),
                isExpanded: expanded == .icon,
                toggle: { toggle(.icon) }
            ) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: colorHex))
            } expansion: {
                IconGrid(selected: $icon, columns: 8, cellSize: 34, spacing: 6)
            }
        }
    }

    private func toggle(_ field: Field) {
        withAnimation(.easeOut(duration: 0.14)) {
            expanded = expanded == field ? nil : field
        }
    }
}

/// One field row that reveals a picker underneath itself. The row is the only hover layer, at the
/// inspector's radius; the expansion sits below it rather than inside a second box.
private struct ListEditorExpandableRow<Value: View, Expansion: View>: View {
    let label: String
    let icon: String
    let iconColor: Color
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let value: Value
    @ViewBuilder let expansion: Expansion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                TaskInspectorFieldRow(label: label, icon: icon, iconColor: iconColor) {
                    HStack(spacing: 8) {
                        value
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))

            if isExpanded {
                expansion
                    .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Toggle row

/// A boolean field row. The switch is the control; the row carries no hover wash because it is not
/// itself clickable.
struct ListEditorToggleRow: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        TaskInspectorFieldRow(label: label, icon: icon) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
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
            icon: "calendar",
            iconColor: Theme.purple,
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

// MARK: - Lifecycle rows

enum ListEditorLifecycleChoice: CaseIterable {
    case active, completed, archived
}

/// Status as one field row plus a picker, replacing the three stacked description cards. The
/// consequence copy those cards carried moves into the picker rows, where it is still read before
/// the choice is made.
struct ListEditorStatusRow: View {
    /// "Area" or "Project" — the picker explains what happens to *this* kind of list.
    let noun: String
    /// Shown as the row value. Not derived from the three choices: a project can also be paused or
    /// cancelled, and the row must not claim otherwise.
    let statusLabel: String
    let isActive: Bool
    let onSelect: (ListEditorLifecycleChoice) -> Void

    @State private var showPicker = false

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Status",
            icon: "circle.dashed",
            iconColor: isActive ? Theme.green : Theme.amber,
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
                choiceRow(
                    .archived,
                    title: "Archived",
                    subtitle: "Store it away without deleting its tasks and documents."
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

/// Destructive field row. Same metrics and hover layer as its neighbours; only the tint differs.
struct ListEditorDeleteRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "trash")
                    .font(.system(size: TaskInspectorFieldRowMetrics.iconSize))
                    .foregroundStyle(Theme.red)
                    .frame(width: TaskInspectorFieldRowMetrics.iconSlot, alignment: .leading)

                Text(title)
                    .font(TaskInspectorFieldRowMetrics.labelFont)
                    .foregroundStyle(Theme.red)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.vertical, TaskInspectorFieldRowMetrics.verticalPadding)
            .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: TaskInspectorFieldRowMetrics.minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
    }
}
#endif

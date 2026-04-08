#if os(macOS)
import SwiftUI

struct SidebarRow: View {
    let item: SidebarItem
    let icon: String
    let label: String
    let color: Color
    @Binding var selection: SidebarItem?
    @State private var isHovered = false

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 15)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(backgroundFillShape)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: selection == item ? 1 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var borderColor: Color {
        selection == item ? Theme.blue.opacity(0.34) : Theme.borderSubtle.opacity(isHovered ? 0.75 : 0.4)
    }

    private var backgroundFill: Color {
        if selection == item {
            return Theme.blue.opacity(0.22)
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.9)
        }
        return Theme.surfaceElevated.opacity(0.45)
    }
}

private extension SidebarRow {
    @ViewBuilder
    var backgroundFillShape: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(backgroundFill)
    }
}

struct SidebarListRow: View {
    enum Kind {
        case area
        case project

        var label: String {
            switch self {
            case .area: return "Area"
            case .project: return "Project"
            }
        }

        var tint: Color {
            switch self {
            case .area: return Theme.blue
            case .project: return Theme.amber
            }
        }
    }

    let item: SidebarItem
    let icon: String
    let label: String
    let color: Color
    let kind: Kind
    let dueDateKey: String?
    let onSetDueDate: ((String) -> Void)?
    @Binding var selection: SidebarItem?
    let onEdit: () -> Void

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var isHovered = false
    @State private var showDueDatePicker = false
    @State private var dueDatePickerDate = Date()
    @State private var dueDateViewMonth = Date()

    private var hoverID: String {
        "sidebar-\(kind.label)-\(label)"
    }

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer(minLength: 8)

                if let dueDateKey, !dueDateKey.isEmpty, onSetDueDate != nil {
                    dueDateBadge(dueDateKey)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selection == item ? Theme.blue.opacity(0.16) : (isHovered ? Theme.surfaceElevated.opacity(0.78) : Color.clear))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selection == item ? Theme.blue.opacity(0.3) : Theme.borderSubtle.opacity(isHovered ? 0.75 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredEditableManager.beginHovering(id: hoverID, onEdit: onEdit)
            } else {
                hoveredEditableManager.endHovering(id: hoverID)
            }
        }
    }

    @ViewBuilder
    private func dueDateBadge(_ key: String) -> some View {
        Button {
            openDueDatePicker(key)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.red)
                Text(DateFormatters.relativeDate(from: key))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(key < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.surfaceElevated.opacity(isHovered ? 0.9 : 0.7))
            .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showDueDatePicker) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { dueDatePickerDate },
                    set: {
                        dueDatePickerDate = $0
                        onSetDueDate?(DateFormatters.dateKey(from: $0))
                    }
                ),
                viewMonth: $dueDateViewMonth,
                isOpen: $showDueDatePicker,
                showsClear: true,
                onClear: {
                    onSetDueDate?("")
                }
            )
        }
    }

    private func openDueDatePicker(_ key: String) {
        let resolved = DateFormatters.date(from: key) ?? Date()
        dueDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDueDatePicker = true
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}
#endif

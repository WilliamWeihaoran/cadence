#if os(macOS)
import AppKit
import SwiftUI

/// Icon-first tile used for the four highest-traffic destinations at the top of the
/// sidebar. Deliberately tiny (icon + micro label) so all four fit on one row and read
/// as a toolbar rather than as four competing cards.
struct SidebarDestinationTile: View {
    let icon: String
    let label: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(alignment: .topTrailing) {
                if let count {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 3)
                        .padding(.trailing, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Theme.surfaceElevated
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.6)
        }
        return Theme.surface
    }
}

/// Low-profile single-line row for secondary destinations (All Tasks, Focus, Goals,
/// Habits…). No card, no border — selection is carried by a filled background alone.
struct SidebarCompactRow: View {
    let icon: String
    let label: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Theme.surfaceElevated
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.55)
        }
        return Color.clear
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
                        .foregroundStyle(selection == item ? Theme.text : Theme.muted)
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
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selection == item ? Color.clear : (isHovered ? Theme.surfaceElevated.opacity(0.72) : Color.clear))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selection == item ? Color.clear : Theme.borderSubtle.opacity(isHovered ? 0.68 : 0), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(selection == item ? color : Color.clear)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .overlay {
            SidebarRightClickEditTrigger(action: onEdit)
        }
        .accessibilityIdentifier("sidebar.list.\(kind.accessibilityFragment).\(accessibilitySlug(label))")
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredEditableManager.beginHovering(id: hoverID, onEdit: onEdit)
            } else {
                hoveredEditableManager.endHovering(id: hoverID)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: selection == item)
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

private extension SidebarListRow.Kind {
    var accessibilityFragment: String {
        switch self {
        case .area: return "area"
        case .project: return "project"
        }
    }
}

private func accessibilitySlug(_ value: String) -> String {
    value
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}

private struct SidebarRightClickEditTrigger: NSViewRepresentable {
    typealias NSViewType = RightClickEditView

    let action: () -> Void

    func makeNSView(context: NSViewRepresentableContext<SidebarRightClickEditTrigger>) -> RightClickEditView {
        let view = RightClickEditView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickEditView, context: NSViewRepresentableContext<SidebarRightClickEditTrigger>) {
        nsView.action = action
    }

    final class RightClickEditView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
            return event.type == .rightMouseDown ? self : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action()
        }
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

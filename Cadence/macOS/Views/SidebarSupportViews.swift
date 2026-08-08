#if os(macOS)
import AppKit
import SwiftUI

/// A single icon-only button in the permanent left rail.
///
/// The rail carries no labels, so every button needs a `.help(...)` tooltip to stay
/// learnable. Selection is expressed by a filled `Theme.surfaceElevated` pill plus the
/// destination's own tint on the glyph; inactive buttons drop to `Theme.dim` so the
/// rail reads as one calm column with a single obvious active item.
struct SidebarRailButton: View {
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
            RoundedRectangle(cornerRadius: SidebarRailMetrics.cornerRadius, style: .continuous)
                .fill(backgroundFill)
                .frame(width: SidebarRailMetrics.buttonSize, height: SidebarRailMetrics.buttonSize)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : Theme.dim)
                }
                .overlay(alignment: .topTrailing) {
                    if let count, count > 0 {
                        badge(count)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private func badge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.bg : Theme.muted)
            .padding(.horizontal, 3)
            .frame(minWidth: SidebarRailMetrics.badgeSize, minHeight: SidebarRailMetrics.badgeSize)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint : Theme.borderSubtle)
            )
            .offset(x: 3, y: -3)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Theme.surfaceElevated
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.6)
        }
        return Color.clear
    }
}

/// Hairline that splits the rail into its daily / views / tracking groups.
struct SidebarRailSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(width: SidebarRailMetrics.separatorWidth, height: 1)
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

#endif

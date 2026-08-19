#if os(macOS)
import AppKit
import SwiftUI

/// Branding block at the top of the sidebar: the real app mark, the product name, and
/// the search affordance.
///
/// The mark and the wordmark are deliberately **not** a button. This slot used to be the
/// first item of the icon rail, where it read as a navigable destination that went
/// nowhere; here it is branding only, and the sole control in the row is search.
struct SidebarAppHeader: View {
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: SidebarMetrics.headerSpacing) {
            appMark

            Text("Cadence")
                .font(.system(size: SidebarMetrics.appTitleFontSize, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 6)

            Button(action: onSearch) {
                Image(systemName: CadenceFeatureDestination.search.systemImage)
                    .font(.system(size: SidebarMetrics.searchIconSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: SidebarMetrics.searchButtonSize, height: SidebarMetrics.searchButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .help("Search (⌘K)")
            .accessibilityLabel("Search")
            .accessibilityIdentifier("sidebar.search")
        }
        .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
    }

    /// Prefers the shipped app icon so the header carries the product's actual mark.
    /// Falls back to a tinted tile when the icon can't be resolved (previews, or a build
    /// whose asset catalog hasn't produced an icon yet) rather than rendering nothing.
    @ViewBuilder
    private var appMark: some View {
        if let image = SidebarAppMark.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: SidebarMetrics.appMarkSize, height: SidebarMetrics.appMarkSize)
                .clipShape(
                    RoundedRectangle(cornerRadius: SidebarMetrics.appMarkCornerRadius, style: .continuous)
                )
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: SidebarMetrics.appMarkCornerRadius, style: .continuous)
                .fill(Theme.blue)
                .frame(width: SidebarMetrics.appMarkSize, height: SidebarMetrics.appMarkSize)
                .overlay {
                    Image(systemName: CadenceFeatureDestination.allTasks.systemImage)
                        .font(.system(size: SidebarMetrics.appMarkFallbackIconSize, weight: .bold))
                        .foregroundStyle(Theme.onColor)
                }
                .accessibilityHidden(true)
        }
    }
}

/// Resolved once: `NSImage` lookups hit disk, and the header re-renders on every
/// selection change.
enum SidebarAppMark {
    static let image: NSImage? = {
        if let named = NSImage(named: "AppIcon") { return named }
        let applicationIcon: NSImage? = NSApplication.shared.applicationIconImage
        return applicationIcon
    }()
}

/// A single navigation row: colored glyph, label, optional trailing count.
///
/// The glyph keeps its destination tint whether or not the row is selected — the colors
/// are what make nine destinations scannable in one column, so dropping them on
/// deselection would cost more than it saves. Selection reads from the filled row
/// background plus the heavier label.
///
/// Hover and selection share **one** background layer at **one** radius, the same rule
/// `TaskInspectorFieldButtonRow` follows: `.plain` rather than `.cadencePlain`, because
/// cadencePlain would stack its own fill and radius on top of this one.
struct SidebarNavRow: View {
    /// Bottom-group rows are quieter than the top group, but they are real destinations
    /// — the difference is a slightly softened glyph, never a disabled-looking label.
    enum Emphasis {
        case primary
        case secondary
    }

    let icon: String
    let label: String
    let tint: Color
    let count: CadenceSidebarCount?
    let isSelected: Bool
    var emphasis: Emphasis = .primary
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.iconLabelSpacing) {
                Image(systemName: icon)
                    .font(.system(size: SidebarMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(tint.opacity(iconOpacity))
                    .frame(width: SidebarMetrics.iconSlotWidth)

                Text(label)
                    .font(.system(size: SidebarMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: SidebarMetrics.badgeLeadingGap)

                if let count {
                    CadenceSidebarCountLabel(count: count)
                        // The count is the row's fixed element; the label is what gives.
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var iconOpacity: Double {
        switch emphasis {
        case .primary: return 1
        case .secondary: return SidebarMetrics.secondaryIconOpacity
        }
    }

    private var backgroundFill: Color {
        // Two distinct steps up the neutral ramp. Hover was `surfaceElevated` at 0.6, which
        // composited to roughly two luminance steps above a near-black page and read as
        // nothing at all; selection now takes the stop above it so the states stay apart
        // instead of both landing on the same plate.
        if isSelected {
            return Theme.surfaceHighlight
        }
        if isHovered {
            return Theme.surfaceElevated
        }
        return Color.clear
    }
}

/// Hairline splitting the column into nav / lists / nav.
struct SidebarSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, SidebarMetrics.dividerInset)
    }
}

/// One area/project row: a 2pt colour bar, the name, and an optional trailing count.
///
/// **No glyph.** A list's icon was a second identity competing with its colour and its name, and a
/// column of a dozen different symbols is harder to scan than a column of names. The list's own
/// `colorHex` survives as a 2pt bar drawn *inside the row's leading padding* — outside the text
/// column — so every name starts on the same x whatever colour it carries. A dot would have had to
/// sit in the text column and push the names off that line.
///
/// Hover and selection share **one** background layer at **one** radius, same rule as
/// `SidebarNavRow` and `TaskInspectorFieldButtonRow`.
struct SidebarListRow: View {
    enum Kind {
        case area
        case project

        /// Names the kind for the hover ID and the accessibility identifier. There is no tint
        /// here: a row's colour is the list's own `colorHex`, never a per-kind hue.
        var label: String {
            switch self {
            case .area: return "Area"
            case .project: return "Project"
            }
        }
    }

    let item: SidebarItem
    let label: String
    let color: Color
    let kind: Kind
    let count: CadenceSidebarCount?
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

    private var isSelected: Bool { selection == item }

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: SidebarMetrics.listTrailingItemSpacing) {
                Text(label)
                    .font(.system(size: SidebarMetrics.listLabelFontSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: SidebarMetrics.listTrailingGap)

                if let dueDateKey, !dueDateKey.isEmpty, onSetDueDate != nil {
                    dueDateBadge(dueDateKey)
                }

                if let count {
                    CadenceSidebarCountLabel(count: count)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            .padding(.vertical, SidebarMetrics.listRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.listRowCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            // Decorative and inside the button's own label, but `allowsHitTesting(false)` is
            // stated rather than assumed: a filled shape laid over an interactive surface is
            // exactly the thing that has silently eaten clicks in this repo before.
            .overlay(alignment: .leading) { colorBar.allowsHitTesting(false) }
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
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// The list's own colour, in the row's leading padding. Always drawn — it is the only thing
    /// left identifying the list, and at 2pt a full column of them reads as a margin rather than
    /// as the row of saturated glyphs this replaced.
    private var colorBar: some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(
                width: SidebarMetrics.listColorBarWidth,
                height: SidebarMetrics.listColorBarHeight
            )
            .padding(.leading, SidebarMetrics.listColorBarLeadingInset)
    }

    private var backgroundFill: Color {
        // Two distinct steps up the neutral ramp. Hover was `surfaceElevated` at 0.6, which
        // composited to roughly two luminance steps above a near-black page and read as
        // nothing at all; selection now takes the stop above it so the states stay apart
        // instead of both landing on the same plate.
        if isSelected {
            return Theme.surfaceHighlight
        }
        if isHovered {
            return Theme.surfaceElevated
        }
        return Color.clear
    }

    /// Bare tinted text rather than a filled pill: as a capsule this annotation carried
    /// more weight than the list name it annotates.
    @ViewBuilder
    private func dueDateBadge(_ key: String) -> some View {
        Button {
            openDueDatePicker(key)
        } label: {
            HStack(spacing: SidebarMetrics.listDueDateSpacing) {
                Image(systemName: "flag.fill")
                    .font(.system(size: SidebarMetrics.listDueDateIconSize, weight: .semibold))
                    .foregroundStyle(Theme.red)
                Text(DateFormatters.relativeDate(from: key))
                    .font(.system(size: SidebarMetrics.listDueDateFontSize, weight: .semibold))
                    .foregroundStyle(key < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                    .lineLimit(1)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Set due date")
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

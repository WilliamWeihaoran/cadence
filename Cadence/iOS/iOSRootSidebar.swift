#if os(iOS)
import SwiftData
import SwiftUI

struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let sidebarStyle = iOSSidebarStyle.style(for: proxy.size.width)

            HStack(spacing: 0) {
                iOSSidebar(selection: $selection, style: sidebarStyle)
                    .frame(width: sidebarStyle.width)
                    // `Theme.surface` against the detail pane's `Theme.bg`, closed by a full-weight
                    // hairline — the same construction and the same reasoning as macOS's
                    // `SidebarView`: on a near-black palette the tonal step alone does not separate
                    // the column from the page, so the edge has to carry it. This used to paint
                    // `surface` here and `bg` inside the sidebar, so the step never existed and the
                    // edge was a half-point line at 58% of a subtle border.
                    .background(Theme.surface)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Theme.borderSubtle)
                            .frame(width: 1)
                    }
                    .zIndex(1)

                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
                    .clipped()
                    .zIndex(0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.container)
    }
}

struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    let style: iOSSidebarStyle
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @State private var isWorkspaceDrawerPresented = false

    private var activeListCount: Int {
        areas.filter(\.isActive).count + projects.filter(\.isActive).count
    }

    private var badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count,
            activeListCount: activeListCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSSidebarBrand(style: style) {
                isWorkspaceDrawerPresented = true
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, style == .expanded ? 18 : 14)
            .padding(.bottom, style == .expanded ? 18 : 14)

            if style == .expanded {
                expandedNavigation
            } else {
                railNavigation
            }
        }
        .popover(isPresented: $isWorkspaceDrawerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            iOSWorkspaceDrawer(selection: $selection)
                .frame(width: 342, height: 640)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var expandedNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    iOSSidebarSection(title: "Plan") {
                        ForEach(CadenceFeatureDestination.primaryOrder) { destination in
                            navButton(for: destination)
                        }
                    }

                    iOSSidebarSection(title: "Workspace") {
                        ForEach([CadenceFeatureDestination.notes, .lists]) { destination in
                            navButton(for: destination)
                        }
                    }

                    iOSSidebarSection(title: "Progress") {
                        ForEach([CadenceFeatureDestination.focus, .goals, .habits]) { destination in
                            navButton(for: destination)
                        }
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 7) {
                ForEach(CadenceFeatureDestination.utilityOrder) { destination in
                    navButton(for: destination)
                        .frame(maxWidth: destination == .search ? .infinity : 42)
                        .layoutPriority(destination == .search ? 1 : 0)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .overlay(alignment: .top) {
                iOSSidebarRailDivider()
                    .padding(.horizontal, style.horizontalPadding)
            }
        }
    }

    private var railNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(CadenceFeatureDestination.primaryOrder) { destination in
                    navButton(for: destination)
                }
            }
            .padding(.horizontal, style.horizontalPadding - 1)
            .padding(.bottom, 10)

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(CadenceFeatureDestination.secondaryOrder) { destination in
                        navButton(for: destination)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, style.horizontalPadding - 1)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(CadenceFeatureDestination.utilityOrder) { destination in
                    navButton(for: destination)
                }
            }
            .padding(.horizontal, style.horizontalPadding - 1)
            .padding(.bottom, 14)
        }
    }

    private func navButton(for destination: CadenceFeatureDestination) -> some View {
        iOSSidebarButton(
            title: destination.compactTitle,
            systemImage: destination.systemImage,
            count: count(for: destination),
            isSelected: selection == destination.item,
            style: style
        ) {
            selection = destination.item
        }
    }

    private func count(for destination: CadenceFeatureDestination) -> Int? {
        badgeSnapshot.count(for: destination)
    }
}

extension CadenceFeatureDestination {
    var item: iOSSidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        case .notes: return .notes
        case .lists: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }
}

enum iOSSidebarStyle: Equatable {
    case rail
    case expanded

    static func style(for width: CGFloat) -> iOSSidebarStyle {
        // Full window width (not the sidebar's own column width). iPad portrait
        // widths run from ~744pt (mini) to ~1032pt (13"); landscape is comfortably
        // wider on every model. 820pt activates the labeled `.expanded` sidebar for
        // portrait on 10.9"+ iPads and for both orientations on 11"/13" iPads, while
        // still falling back to `.rail` for genuinely narrow contexts (iPad mini
        // portrait, Slide Over/Split View compact widths).
        width >= 820 ? .expanded : .rail
    }

    var width: CGFloat {
        switch self {
        case .rail: return iOSSidebarMetrics.railWidth
        case .expanded: return iOSSidebarMetrics.expandedWidth
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .rail: return 10
        case .expanded: return 12
        }
    }
}

enum iOSSidebarMetrics {
    static let railWidth: CGFloat = 58
    static let expandedWidth: CGFloat = 188
    /// Also the touch floor: a nav row is the most-tapped control on the iPad shell, so it does
    /// not get to be 40pt.
    static let buttonHeight: CGFloat = 44
    static let iconSize: CGFloat = 14
    static let iconBoxSize: CGFloat = 30
    static let selectedCornerRadius: CGFloat = Theme.radiusControl
}

struct iOSSidebarRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

/// The app mark, and the control that opens `iOSWorkspaceDrawer`.
///
/// It used to read "Cadence / Workspace". "Workspace" is a subtitle naming the app you are already
/// in — the same thing the `subtitle` parameter was deleted from `DesktopPageHeader` for. The word
/// is gone; the app name stays, because that is identity rather than description.
struct iOSSidebarBrand: View {
    let style: iOSSidebarStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                iOSIconTile(systemImage: "sidebar.leading", color: Theme.blue, size: 32)

                if style == .expanded {
                    Text("Cadence")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: style == .expanded ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Cadence")
    }
}

struct iOSSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrowLabel(text: title)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 2) {
                content()
            }
        }
    }
}

/// A navigation row in the iPad shell's sidebar.
///
/// **The glyph is chrome, not a colour code.** Every row used to draw its `CadenceFeatureDestination`
/// tint — Today amber, Tasks blue, Calendar purple, Lists green, Focus red — which put six hues in
/// one column encoding nothing a reader could act on. Colour in this app is reserved for the
/// exceptional (overdue, past-do, in-progress) and for a `colorHex` the user chose on a list, tag,
/// habit or calendar. macOS keeps its tinted sidebar glyphs precisely because there they *are* a
/// user choice: `SidebarStaticDestination` persists a per-destination colour through
/// `CadencePreferenceKeys.sidebarTabColors`. iPad has no such picker, so the hue was decoration.
///
/// What carries state instead is the row: `Theme.surfaceHighlight` behind it, `Theme.text` on the
/// glyph and label, semibold. One layer, one radius — `SidebarNavRow`'s rule, and the iPhone More
/// tab's.
struct iOSSidebarButton: View {
    let title: String
    let systemImage: String
    let count: Int?
    let isSelected: Bool
    let style: iOSSidebarStyle
    let action: () -> Void

    /// The one place selection is spelled out, so the two label variants cannot drift.
    private var glyphColor: Color {
        isSelected ? Theme.text : Theme.dim
    }

    var body: some View {
        Button(action: action) {
            if style == .expanded {
                expandedLabel
            } else {
                railLabel
            }
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var expandedLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 4)

            if let count, count > 0 {
                countBadge
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionLayer)
        .contentShape(selectionShape)
    }

    private var railLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(maxWidth: .infinity)
                .frame(height: iOSSidebarMetrics.buttonHeight)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18)
                    .frame(height: 17)
                    .background(Capsule().fill(Theme.borderSubtle))
                    .offset(x: -1, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .background(selectionLayer)
        .contentShape(selectionShape)
    }

    private var selectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    /// One selection layer at one radius, the rule `SidebarNavRow` follows: selection is a step up
    /// the neutral ramp, not a coloured 2pt rail bolted to the leading edge of an otherwise
    /// unchanged row.
    private var selectionLayer: some View {
        selectionShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear)
    }

    /// Neutral capsule, neutral digits. The capsule used to fill with the destination tint on the
    /// selected row, which was the last hue left in the column once the glyphs went to `Theme.dim`
    /// — one orange pill on Today and nothing to explain it. Selection is carried by the row.
    private var countBadge: some View {
        Text("\(count ?? 0)")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.text : Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 19)
            .background(Capsule(style: .continuous).fill(Theme.borderSubtle))
            .accessibilityHidden(true)
    }
}

struct iOSMissingListView: View {
    var body: some View {
        iOSEmptyPanel(
            systemImage: "questionmark.folder",
            title: "List not found",
            subtitle: "This list may have been archived, deleted, or changed on another device."
        )
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

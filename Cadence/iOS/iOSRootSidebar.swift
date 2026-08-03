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
                    .background(Theme.surface)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.58))
                            .frame(width: 0.5)
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
    @Query(filter: #Predicate<Pursuit> { $0.statusRaw == "active" }) private var activePursuits: [Pursuit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    @State private var isWorkspaceDrawerPresented = false

    private var activeListCount: Int {
        areas.filter(\.isActive).count + projects.filter(\.isActive).count
    }

    private var badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activePursuitCount: activePursuits.count,
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
        .background(Theme.bg)
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
                        ForEach([CadenceFeatureDestination.focus, .pursuits, .goals, .habits]) { destination in
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
            tint: destination.tint,
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
        case .pursuits: return .pursuits
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
    static let buttonHeight: CGFloat = 40
    static let iconSize: CGFloat = 14
    static let iconBoxSize: CGFloat = 30
    static let selectedCornerRadius: CGFloat = 9
}

struct iOSSidebarRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.54))
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
    }
}

struct iOSSidebarBrand: View {
    let style: iOSSidebarStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.blue.opacity(0.13))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1)
                    }

                if style == .expanded {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cadence")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        Text("Workspace")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: style == .expanded ? .leading : .center)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cadence")
    }
}

struct iOSSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim.opacity(0.78))
                .textCase(.uppercase)
                .kerning(0.8)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 5) {
                content()
            }
        }
    }
}

struct iOSSidebarButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let style: iOSSidebarStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if style == .expanded {
                expandedLabel
            } else {
                railLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var expandedLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? tint : tint.opacity(0.84))
                .frame(width: 26, height: 26)
                .background(tint.opacity(isSelected ? 0.18 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(isSelected ? 0.30 : 0.13), lineWidth: 1)
                }

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 4)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? tint : Theme.dim)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(isSelected ? tint.opacity(0.14) : Theme.surfaceElevated.opacity(0.55))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .padding(.horizontal, 8)
        .background(isSelected ? tint.opacity(0.11) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.22) : Color.clear, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: 20)
                    .offset(x: -2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var railLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : tint.opacity(0.86))
                .frame(width: iOSSidebarMetrics.iconBoxSize, height: iOSSidebarMetrics.iconBoxSize)
                .background(
                    RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
                        .fill(iconFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
                        .strokeBorder(iconBorder, lineWidth: 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: iOSSidebarMetrics.buttonHeight)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18)
                    .frame(height: 17)
                    .background(tint.opacity(0.95))
                    .clipShape(Capsule())
                    .offset(x: -1, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .background(isSelected ? tint.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.22) : Color.clear, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: 22)
                    .offset(x: -4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var iconFill: Color {
        if isSelected {
            return tint.opacity(0.24)
        }
        return Color.clear
    }

    private var iconBorder: Color {
        if isSelected {
            return tint.opacity(0.34)
        }
        return Color.clear
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

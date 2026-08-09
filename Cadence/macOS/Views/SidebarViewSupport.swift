#if os(macOS)
import SwiftUI

enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
    case planning
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits

    var id: String { rawValue }

    var item: SidebarItem {
        switch self {
        case .today: return .today
        case .planning: return .planning
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var feature: CadenceFeatureDestination {
        switch self {
        case .today: return .today
        case .planning: return .planning
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var icon: String {
        feature.systemImage
    }

    var label: String {
        feature.title
    }

    var color: Color {
        Color(hex: defaultColorHex)
    }

    var defaultColorHex: String {
        feature.defaultColorHex
    }
}

extension SidebarStaticDestination {
    static var defaultOrder: [SidebarStaticDestination] {
        CadenceFeatureDestination.desktopSidebarOrder.compactMap { SidebarStaticDestination(rawValue: $0.rawValue) }
    }

    static func orderedDestinations(from raw: String) -> [SidebarStaticDestination] {
        let stored = raw
            .split(separator: ",")
            .compactMap { SidebarStaticDestination(rawValue: String($0)) }
        let uniqueStored = stored.reduce(into: [SidebarStaticDestination]()) { partial, item in
            if !partial.contains(item) { partial.append(item) }
        }
        let missing = defaultOrder.filter { !uniqueStored.contains($0) }
        return uniqueStored + missing
    }

    static func rawOrderString(from destinations: [SidebarStaticDestination]) -> String {
        destinations.map(\.rawValue).joined(separator: ",")
    }

    static func colorHexMap(from raw: String) -> [SidebarStaticDestination: String] {
        raw
            .split(separator: ",")
            .reduce(into: [SidebarStaticDestination: String]()) { partial, pair in
                let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, let destination = SidebarStaticDestination(rawValue: parts[0]) else { return }
                partial[destination] = parts[1]
            }
    }

    static func rawColorString(from colors: [SidebarStaticDestination: String]) -> String {
        defaultOrder.compactMap { destination in
            guard let hex = colors[destination] else { return nil }
            return "\(destination.rawValue):\(hex)"
        }
        .joined(separator: ",")
    }

    func resolvedColorHex(from raw: String) -> String {
        SidebarStaticDestination.colorHexMap(from: raw)[self] ?? defaultColorHex
    }
}

/// Fixed geometry for the single sidebar column: app header, nav rows, the scrolling
/// lists region, and the pinned bottom group all size off these values.
///
/// The sidebar used to be an icon rail plus a separate lists panel; it is now one
/// column, so this is the only place row height, glyph size, and inset are decided.
/// Nav glyphs deliberately inherit the old rail's sizing judgment — a large, legible
/// icon rather than the 12–13pt used by list rows — because nav is the primary
/// affordance in this column. `iconSize` and `iconSlotWidth` move together: growing the
/// glyph past the slot pushes labels out of alignment with each other.
enum SidebarMetrics {
    // MARK: Column

    static let horizontalInset: CGFloat = 10
    /// The column starts below this inset so its first row clears the window's traffic
    /// lights and the floating Cmd+O sidebar toggle, both drawn over the top-left corner
    /// of the content view (`.fullSizeContentView`).
    static let topInset: CGFloat = 46
    static let bottomInset: CGFloat = 10

    // MARK: App header

    static let appMarkSize: CGFloat = 24
    static let appMarkCornerRadius: CGFloat = 7
    static let appMarkFallbackIconSize: CGFloat = 13
    static let appTitleFontSize: CGFloat = 15
    /// Sized so `appMarkSize + headerSpacing == iconSlotWidth + iconLabelSpacing`: the
    /// wordmark then starts on exactly the same x as every nav row label below it.
    static let headerSpacing: CGFloat = 6
    static let headerBottomSpacing: CGFloat = 12
    static let searchButtonSize: CGFloat = 26
    static let searchIconSize: CGFloat = 13

    // MARK: Nav rows

    static let rowHeight: CGFloat = 32
    static let rowCornerRadius: CGFloat = 10
    static let rowSpacing: CGFloat = 2
    static let rowHorizontalPadding: CGFloat = 10
    static let iconSlotWidth: CGFloat = 20
    static let iconSize: CGFloat = 15
    static let iconLabelSpacing: CGFloat = 10
    static let labelFontSize: CGFloat = 13
    /// Icon opacity for the quieter bottom nav group. Kept well clear of a
    /// disabled-looking wash — these are real destinations, just less-travelled ones.
    static let secondaryIconOpacity: Double = 0.8

    // MARK: Count badges

    static let badgeFontSize: CGFloat = 10
    static let badgeMinWidth: CGFloat = 20
    static let badgeHeight: CGFloat = 16
    static let badgeHorizontalPadding: CGFloat = 5
    /// Minimum gap held between a row's truncating label and its count badge. The badge
    /// is fixed-size and wins layout priority, so this is the point at which the *label*
    /// starts truncating — a three-digit count never overlaps it.
    static let badgeLeadingGap: CGFloat = 8

    // MARK: Group separation

    static let groupSpacing: CGFloat = 8
    static let dividerInset: CGFloat = 2
}

/// One navigation row. Modelled as a value type rather than a
/// `SidebarStaticDestination` so Notes — which has no static-destination case, and
/// therefore no hide toggle or color override in Settings — can sit in the nav groups
/// alongside the destinations that do.
struct SidebarNavItem: Identifiable {
    let id: String
    let item: SidebarItem
    let icon: String
    let label: String
    let tint: Color
    let count: Int?
    let accessibilityID: String
}
#endif

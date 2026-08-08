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

/// Fixed geometry for the permanent icon rail on the left edge of the sidebar.
/// The rail never scrolls, so every value here is a hard layout constant rather
/// than something derived from available space.
enum SidebarRailMetrics {
    static let width: CGFloat = 42
    static let buttonSize: CGFloat = 30
    static let cornerRadius: CGFloat = 8
    static let spacing: CGFloat = 4
    static let separatorWidth: CGFloat = 22
    static let badgeSize: CGFloat = 12
    /// Both rail and panel start below this inset so their first row clears the
    /// window's traffic lights and the floating Cmd+O sidebar toggle, which are
    /// drawn over the top-left corner of the content view (`.fullSizeContentView`).
    static let topInset: CGFloat = 46
}

/// One icon-only rail entry. Modelled as a value type rather than a
/// `SidebarStaticDestination` so Notes — which has no static-destination case, and
/// therefore no hide toggle or color override in Settings — can sit in the rail
/// alongside the destinations that do.
struct SidebarRailItem: Identifiable {
    let id: String
    let item: SidebarItem
    let icon: String
    let label: String
    let tint: Color
    let count: Int?
    let accessibilityID: String
}
#endif

#if os(macOS)
import SwiftUI

enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case pursuits
    case goals
    case habits

    var id: String { rawValue }

    var item: SidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .pursuits: return .pursuits
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var feature: CadenceFeatureDestination {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .pursuits: return .pursuits
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

    var isPrimaryNavigation: Bool {
        feature.isPrimaryNavigation
    }

    var isTrackingNavigation: Bool {
        feature.isTrackingNavigation
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

struct CompactSidebarIconButton: View {
    let item: SidebarItem
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backgroundFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSelected ? 1 : 0.8)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.\(identifierFragment(for: item))")
        .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        if isSelected {
            return Theme.blue.opacity(0.22)
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.9)
        }
        return Theme.surfaceElevated.opacity(0.45)
    }

    private var borderColor: Color {
        isSelected ? Theme.blue.opacity(0.34) : Theme.borderSubtle.opacity(isHovered ? 0.75 : 0.4)
    }
}

private func identifierFragment(for item: SidebarItem) -> String {
    switch item {
    case .today: return "today"
    case .allTasks: return "allTasks"
    case .inbox: return "inbox"
    case .area(let id): return "area.\(id.uuidString)"
    case .project(let id): return "project.\(id.uuidString)"
    case .pursuits: return "pursuits"
    case .goals: return "goals"
    case .habits: return "habits"
    case .notes: return "notes"
    case .calendar: return "calendar"
    case .focus: return "focus"
    case .settings: return "settings"
    }
}

struct SidebarCardButton: View {
    let destination: SidebarStaticDestination
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: destination.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 20, height: 20)

                    Spacer()

                    if let count {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(isSelected ? 0.18 : 0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? tint : Color.clear)
                        .frame(width: 3, height: 14)

                    Text(destination.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .cadenceCard(
                background: backgroundFill,
                cornerRadius: Theme.radiusCard,
                shadowRadius: isHovered ? 12 : 7,
                shadowY: isHovered ? 5 : 3
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(tint.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.destination.\(destination.rawValue)")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected {
            return tint.opacity(0.14)
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.7)
        }
        return Theme.surfaceElevated.opacity(0.34)
    }
}

struct SidebarTrackingButton: View {
    let destination: SidebarStaticDestination
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: destination.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : tint)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isSelected ? tint.opacity(0.95) : tint.opacity(isHovered ? 0.18 : 0.12))
                    )

                Text(destination.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.9))

                Spacer(minLength: 8)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? .white : tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? tint.opacity(0.9) : tint.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.destination.\(destination.rawValue)")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundFill: Color {
        if isSelected {
            return tint.opacity(0.18)
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.66)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            return tint.opacity(0.32)
        }
        return Theme.borderSubtle.opacity(isHovered ? 0.55 : 0)
    }
}
#endif

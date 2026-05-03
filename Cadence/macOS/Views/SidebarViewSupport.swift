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

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .pursuits: return "sparkles"
        case .goals: return "target"
        case .habits: return "flame.fill"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .goals: return "Goals"
        case .habits: return "Habits"
        }
    }

    var color: Color {
        Color(hex: defaultColorHex)
    }

    var defaultColorHex: String {
        switch self {
        case .today: return "#FFB84D"
        case .allTasks: return "#5AA2FF"
        case .focus: return "#FF6B6B"
        case .inbox: return "#5AA2FF"
        case .calendar: return "#9E8CFF"
        case .pursuits: return "#A78BFA"
        case .goals: return "#4ECB71"
        case .habits: return "#FFB84D"
        }
    }
}

extension SidebarStaticDestination {
    static var defaultOrder: [SidebarStaticDestination] {
        [.today, .allTasks, .focus, .inbox, .calendar, .pursuits, .goals, .habits]
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

struct SidebarCardButton: View {
    let destination: SidebarStaticDestination
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: destination.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : tint)

                    Spacer()

                    if let count {
                        Text("\(count)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isSelected ? .white : tint)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)

                Spacer(minLength: 6)

                Text(destination.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? destination.color
                        : destination.color.opacity(isHovered ? 0.22 : 0.14))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? destination.color.opacity(0.5) : destination.color.opacity(isHovered ? 0.3 : 0.18),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
#endif

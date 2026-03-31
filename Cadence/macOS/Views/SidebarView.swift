#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let sidebarStaticDragPrefix = "sidebar-static::"

enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
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
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
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
        case .goals: return "Goals"
        case .habits: return "Habits"
        }
    }

    var color: Color {
        switch self {
        case .today: return Theme.amber
        case .allTasks: return Theme.blue
        case .focus: return Theme.red
        case .inbox: return Theme.blue
        case .calendar: return Theme.purple
        case .goals: return Theme.green
        case .habits: return Theme.amber
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @AppStorage("sidebarCoreOrder") private var sidebarCoreOrderRaw = ""
    @AppStorage("sidebarTrackOrder") private var sidebarTrackOrderRaw = ""

    @State private var showCreateContext = false
    @State private var contextForNewList: Context? = nil
    @State private var draggingStaticDestination: SidebarStaticDestination? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surfaceElevated)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "checklist.checked")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cadence")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coreDestinations) { destination in
                        SidebarRow(item: destination.item, icon: destination.icon, label: destination.label, color: destination.color, selection: $selection)
                            .onDrag {
                                draggingStaticDestination = destination
                                return NSItemProvider(object: NSString(string: "\(sidebarStaticDragPrefix)\(destination.rawValue)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarStaticDropDelegate(
                                    target: destination,
                                    dragging: $draggingStaticDestination,
                                    current: coreDestinations,
                                    save: saveCoreDestinations
                                )
                            )
                    }
                }

                SidebarSection(title: "ORGANIZE") {
                    ForEach(contexts) { context in
                        ContextSection(
                            context: context,
                            selection: $selection,
                            onAddList: { contextForNewList = context }
                        )
                    }
                }

                SidebarSection(title: "TRACK") {
                    ForEach(trackDestinations) { destination in
                        SidebarRow(item: destination.item, icon: destination.icon, label: destination.label, color: destination.color, selection: $selection)
                            .onDrag {
                                draggingStaticDestination = destination
                                return NSItemProvider(object: NSString(string: "\(sidebarStaticDragPrefix)\(destination.rawValue)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarStaticDropDelegate(
                                    target: destination,
                                    dragging: $draggingStaticDestination,
                                    current: trackDestinations,
                                    save: saveTrackDestinations
                                )
                            )
                    }
                }

                SidebarSection(title: "NOTES") {
                    SidebarRow(item: .notes, icon: "doc.text", label: "Notes", color: Theme.purple, selection: $selection)
                }

                Button {
                    showCreateContext = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Context")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surfaceElevated.opacity(0.68))
                    )
                }
                .buttonStyle(.cadencePlain)

                Spacer(minLength: 8)

                SidebarRow(item: .settings, icon: "gearshape.fill", label: "Settings", color: Theme.dim, selection: $selection)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    private var coreDestinations: [SidebarStaticDestination] {
        resolveDestinations(
            rawValue: sidebarCoreOrderRaw,
            defaults: [.today, .allTasks, .focus, .inbox, .calendar]
        )
    }

    private var trackDestinations: [SidebarStaticDestination] {
        resolveDestinations(
            rawValue: sidebarTrackOrderRaw,
            defaults: [.goals, .habits]
        )
    }

    private func resolveDestinations(rawValue: String, defaults: [SidebarStaticDestination]) -> [SidebarStaticDestination] {
        let stored = rawValue
            .split(separator: ",")
            .compactMap { SidebarStaticDestination(rawValue: String($0)) }

        let filtered = stored.filter(defaults.contains)
        let missing = defaults.filter { !filtered.contains($0) }
        let resolved = filtered + missing
        return resolved.isEmpty ? defaults : resolved
    }

    private func reorderStatic(
        moving: SidebarStaticDestination,
        before target: SidebarStaticDestination,
        in source: [SidebarStaticDestination],
        save: ([SidebarStaticDestination]) -> Void
    ) {
        guard let fromIndex = source.firstIndex(of: moving),
              let toIndex = source.firstIndex(of: target) else { return }
        var updated = source
        let item = updated.remove(at: fromIndex)
        updated.insert(item, at: fromIndex < toIndex ? toIndex - 1 : toIndex)
        save(updated)
    }

    private func saveCoreDestinations(_ destinations: [SidebarStaticDestination]) {
        sidebarCoreOrderRaw = destinations.map(\.rawValue).joined(separator: ",")
    }

    private func saveTrackDestinations(_ destinations: [SidebarStaticDestination]) {
        sidebarTrackOrderRaw = destinations.map(\.rawValue).joined(separator: ",")
    }
}

#endif

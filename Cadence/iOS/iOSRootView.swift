#if os(iOS)
import SwiftData
import SwiftUI

enum iOSSidebarItem: Hashable {
    case today
    case inbox
    case area(UUID)
    case project(UUID)
}

struct iOSRootView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var selection: iOSSidebarItem? = .today

    var body: some View {
        let _ = themeManager.selectedTheme

        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    iOSSidebar(selection: $selection)
                } detail: {
                    detailView(for: selection ?? .today)
                }
            } else {
                TabView {
                    NavigationStack {
                        iPadTodayView()
                    }
                    .tabItem {
                        Label("Today", systemImage: "sun.max.fill")
                    }

                    NavigationStack {
                        iPadInboxView()
                    }
                    .tabItem {
                        Label("Inbox", systemImage: "tray.fill")
                    }

                    NavigationStack {
                        iOSListsView()
                    }
                    .tabItem {
                        Label("Lists", systemImage: "folder.fill")
                    }
                }
                .tint(Theme.blue)
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func detailView(for item: iOSSidebarItem) -> some View {
        switch item {
        case .today:
            iPadTodayView()
        case .inbox:
            iPadInboxView()
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(area: area)
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(project: project)
            } else {
                iOSMissingListView()
            }
        }
    }
}

private struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Today", systemImage: "sun.max.fill")
                    .tag(iOSSidebarItem.today)

                Label("Inbox", systemImage: "tray.fill")
                    .tag(iOSSidebarItem.inbox)
            }

            if !activeAreas.isEmpty {
                Section("Areas") {
                    ForEach(activeAreas) { area in
                        iOSSidebarListRow(
                            name: area.name,
                            icon: area.icon,
                            colorHex: area.colorHex,
                            subtitle: area.context?.name
                        )
                        .tag(iOSSidebarItem.area(area.id))
                    }
                }
            }

            if !activeProjects.isEmpty {
                Section("Projects") {
                    ForEach(activeProjects) { project in
                        iOSSidebarListRow(
                            name: project.name,
                            icon: project.icon,
                            colorHex: project.colorHex,
                            subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / ")
                        )
                        .tag(iOSSidebarItem.project(project.id))
                    }
                }
            }
        }
        .navigationTitle("Cadence")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tint(Theme.blue)
    }
}

private struct iOSSidebarListRow: View {
    let name: String
    let icon: String
    let colorHex: String
    let subtitle: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Untitled" : name)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: colorHex))
        }
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

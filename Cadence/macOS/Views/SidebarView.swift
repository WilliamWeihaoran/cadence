#if os(macOS)
import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Environment(\.modelContext) private var modelContext

    @State private var showCreateContext = false
    @State private var contextForNewList: Context? = nil

    var body: some View {
        List(selection: $selection) {
            // Focus & Today
            Section {
                SidebarRow(icon: "sun.max.fill",   label: "Today",    color: Theme.amber)
                    .tag(SidebarItem.today)
                SidebarRow(icon: "timer",          label: "Focus",    color: Theme.red)
                    .tag(SidebarItem.focus)
                SidebarRow(icon: "tray.fill",      label: "Inbox",    color: Theme.blue)
                    .tag(SidebarItem.inbox)
                SidebarRow(icon: "calendar",       label: "Calendar", color: Theme.purple)
                    .tag(SidebarItem.calendar)
            }

            // Organize
            Section("ORGANIZE") {
                ForEach(contexts) { context in
                    ContextSection(
                        context: context,
                        selection: $selection,
                        onAddList: { contextForNewList = context }
                    )
                }
            }

            // Track
            Section("TRACK") {
                SidebarRow(icon: "target",      label: "Goals",  color: Theme.green)
                    .tag(SidebarItem.goals)
                SidebarRow(icon: "flame.fill",  label: "Habits", color: Theme.amber)
                    .tag(SidebarItem.habits)
            }

            // Notes
            Section("NOTES") {
                SidebarRow(icon: "doc.text", label: "Notes", color: Theme.purple)
                    .tag(SidebarItem.notes)
            }

            // New Context
            Section {
                Button {
                    showCreateContext = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle").font(.system(size: 12))
                        Text("New Context").font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .background(Theme.surface)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }
}

// MARK: - Context Section

private struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @Environment(\.modelContext) private var modelContext

    private var areas: [Area]    { (context.areas    ?? []).sorted { $0.order < $1.order } }
    private var projects: [Project] { (context.projects ?? []).sorted { $0.order < $1.order } }

    var body: some View {
        Section {
            ForEach(areas) { area in
                SidebarRow(icon: area.icon, label: area.name, color: Color(hex: area.colorHex))
                    .tag(SidebarItem.area(area.id))
            }
            .onMove { indices, newOffset in moveAreas(from: indices, to: newOffset) }

            ForEach(projects) { project in
                SidebarRow(icon: project.icon, label: project.name, color: Color(hex: project.colorHex))
                    .tag(SidebarItem.project(project.id))
            }
            .onMove { indices, newOffset in moveProjects(from: indices, to: newOffset) }

        } header: {
            HStack(spacing: 6) {
                Image(systemName: context.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: context.colorHex))
                Text(context.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Spacer()
                Button(action: onAddList) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moveAreas(from indices: IndexSet, to newOffset: Int) {
        var sorted = areas
        sorted.move(fromOffsets: indices, toOffset: newOffset)
        for (i, area) in sorted.enumerated() { area.order = i }
    }

    private func moveProjects(from indices: IndexSet, to newOffset: Int) {
        var sorted = projects
        sorted.move(fromOffsets: indices, toOffset: newOffset)
        for (i, project) in sorted.enumerated() { project.order = i }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Label {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 13))
        }
    }
}
#endif

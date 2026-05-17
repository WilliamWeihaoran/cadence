#if os(macOS)
import SwiftUI
import SwiftData

struct AttachWorkSheet: View {
    let goal: Goal
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var groupedLists: [(context: Context?, areas: [Area], projects: [Project])] {
        var result: [(Context?, [Area], [Project])] = contexts.compactMap { context in
            let contextAreas = areas
                .filter { $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            let contextProjects = projects
                .filter { $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            guard !contextAreas.isEmpty || !contextProjects.isEmpty else { return nil }
            return (context, contextAreas, contextProjects)
        }

        let unfiledAreas = areas.filter { $0.context == nil && matches($0.name) }
        let unfiledProjects = projects.filter { $0.context == nil && matches($0.name) }
        if !unfiledAreas.isEmpty || !unfiledProjects.isEmpty {
            result.append((nil, unfiledAreas, unfiledProjects))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attach Lists")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(goal.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                CadenceActionButton(title: "Done", role: .secondary, size: .compact) {
                    dismiss()
                }
            }
            .padding(20)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                TextField("Search lists", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
            .padding(16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    attachListsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 620, height: 700)
        .background(Theme.surface)
    }

    private var attachListsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GoalSectionHeading(title: "Lists", count: groupedLists.reduce(0) { $0 + $1.areas.count + $1.projects.count })
            if groupedLists.isEmpty {
                GoalInlineEmpty(text: "No matching lists.")
            } else {
                ForEach(Array(groupedLists.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text((group.context?.name ?? "No Context").uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(group.context.map { Color(hex: $0.colorHex) } ?? Theme.dim)
                            .padding(.top, 4)
                        ForEach(group.areas) { area in
                            AttachListCandidateRow(
                                icon: area.icon,
                                title: area.name,
                                subtitle: "\(area.tasks?.filter { !$0.isCancelled }.count ?? 0) active tasks",
                                color: Color(hex: area.colorHex),
                                isAttached: isAttached(area: area),
                                onToggle: { toggle(area: area) }
                            )
                        }
                        ForEach(group.projects) { project in
                            AttachListCandidateRow(
                                icon: project.icon,
                                title: project.name,
                                subtitle: "\(project.tasks?.filter { !$0.isCancelled }.count ?? 0) active tasks",
                                color: Color(hex: project.colorHex),
                                isAttached: isAttached(project: project),
                                onToggle: { toggle(project: project) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.lowercased().contains(query)
    }

    private func isAttached(area: Area) -> Bool {
        (goal.listLinks ?? []).contains { $0.pointsTo(area: area) }
    }

    private func isAttached(project: Project) -> Bool {
        (goal.listLinks ?? []).contains { $0.pointsTo(project: project) }
    }

    private func toggle(area: Area) {
        if let existing = (goal.listLinks ?? []).first(where: { $0.pointsTo(area: area) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(GoalListLink(goal: goal, area: area))
        }
    }

    private func toggle(project: Project) {
        if let existing = (goal.listLinks ?? []).first(where: { $0.pointsTo(project: project) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(GoalListLink(goal: goal, project: project))
        }
    }
}
#endif

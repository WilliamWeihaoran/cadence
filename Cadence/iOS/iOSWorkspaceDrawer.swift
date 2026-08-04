#if os(iOS)
import SwiftData
import SwiftUI

struct iOSWorkspaceDrawer: View {
    @Binding var selection: iOSSidebarItem?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Pursuit> { $0.statusRaw == "active" }) private var activePursuits: [Pursuit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activePursuitCount: activePursuits.count,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count,
            activeListCount: activeAreas.count + activeProjects.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(CadenceFeatureDestination.workspaceDrawerSections) { section in
                        iOSWorkspaceDrawerSection(title: section.title) {
                            ForEach(section.destinations) { destination in
                                drawerFeatureRow(destination)
                            }

                            if section.kind == .organize {
                                organizedListRows
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var drawerHeader: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .fill(Theme.blue.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cadence")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Workspace")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceElevated.opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.72))
                .frame(height: 0.5)
        }
    }

    private func drawerFeatureRow(_ destination: CadenceFeatureDestination) -> some View {
        iOSWorkspaceDrawerRow(
            title: destination.title,
            subtitle: destination.subtitle,
            systemImage: destination.systemImage,
            color: destination.tint,
            count: count(for: destination),
            isSelected: selection == destination.item
        ) {
            selection = destination.item
            dismiss()
        }
    }

    @ViewBuilder
    private var organizedListRows: some View {
        if activeAreas.isEmpty && activeProjects.isEmpty {
            iOSWorkspaceDrawerEmptyRow()
        } else {
            ForEach(activeAreas) { area in
                drawerListRow(
                    title: area.name,
                    subtitle: area.context?.name ?? "Area",
                    systemImage: area.icon,
                    color: Color(hex: area.colorHex),
                    count: CadenceTaskQuerySupport.openTaskCount(for: area)
                ) {
                    selection = .area(area.id)
                    dismiss()
                }
            }

            ForEach(activeProjects) { project in
                drawerListRow(
                    title: project.name,
                    subtitle: project.area?.name ?? project.context?.name ?? "Project",
                    systemImage: project.icon,
                    color: Color(hex: project.colorHex),
                    count: CadenceTaskQuerySupport.openTaskCount(for: project)
                ) {
                    selection = .project(project.id)
                    dismiss()
                }
            }
        }
    }

    private func drawerListRow(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        iOSWorkspaceDrawerRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            color: color,
            count: CadenceTaskQuerySupport.badgeCount(count),
            isSelected: false,
            action: action
        )
    }

    private func count(for destination: CadenceFeatureDestination) -> Int? {
        badgeSnapshot.count(for: destination)
    }
}

private struct iOSWorkspaceDrawerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .cadenceCard(background: Theme.surface.opacity(0.72), cornerRadius: Theme.radiusCard)
        }
    }
}

private struct iOSWorkspaceDrawerRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.text : color)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? color.opacity(0.30) : color.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.text : color)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(color.opacity(isSelected ? 0.24 : 0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 3, height: 28)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct iOSWorkspaceDrawerEmptyRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceElevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("No active lists")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Create areas and projects in Lists")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
#endif

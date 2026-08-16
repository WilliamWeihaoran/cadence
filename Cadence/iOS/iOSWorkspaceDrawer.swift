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

    /// Same mark and same one line as `iOSSidebarBrand`, which is the control that opens this. The
    /// two used to disagree twice over: a different glyph (`checklist.checked` against
    /// `sidebar.leading`), and a "Workspace" subtitle under the app's own name.
    private var drawerHeader: some View {
        HStack(spacing: 11) {
            iOSIconTile(systemImage: "sidebar.leading", color: Theme.blue, size: 34)

            Text("Cadence")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceElevated.opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    // 30pt of plate, 44pt of target — `iOSIconButton`'s trick, so the close control
                    // is not a 28pt tap in a popover you are trying to get out of.
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(7)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Close")
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

    /// A destination row. `glyphColor` is left nil so the glyph reads as chrome — see the note on
    /// `iOSSidebarButton`, which this drawer sits next to and must not contradict.
    private func drawerFeatureRow(_ destination: CadenceFeatureDestination) -> some View {
        iOSWorkspaceDrawerRow(
            title: destination.title,
            subtitle: destination.subtitle,
            systemImage: destination.systemImage,
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
                    colorHex: area.colorHex,
                    count: CadenceTaskQuerySupport.openTaskCount(for: area),
                    isSelected: selection == .area(area.id)
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
                    colorHex: project.colorHex,
                    count: CadenceTaskQuerySupport.openTaskCount(for: project),
                    isSelected: selection == .project(project.id)
                ) {
                    selection = .project(project.id)
                    dismiss()
                }
            }
        }
    }

    /// A list row. Unlike a destination row it *does* colour its glyph, because that hue is the
    /// `colorHex` the user picked in the list editor — the sanctioned exception to the chrome rule.
    ///
    /// `isSelected` used to be hardcoded `false`, so the one screen that can open a list never
    /// showed which list was open: pick Beta Area and the drawer still looked exactly as it did
    /// before you touched it.
    private func drawerListRow(
        title: String,
        subtitle: String,
        systemImage: String,
        colorHex: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        iOSWorkspaceDrawerRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            glyphColor: Color(hex: colorHex),
            count: CadenceTaskQuerySupport.badgeCount(count),
            isSelected: isSelected,
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
            // The shared eyebrow, not a hand-rolled 10pt bold `.textCase(.uppercase)` — the
            // sidebar's PLAN / WORKSPACE / PROGRESS and the iPhone More tab both draw
            // `SectionEyebrowLabel`, and this was the one copy that had drifted (bold vs semibold,
            // no kerning).
            SectionEyebrowLabel(text: title)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            // 4pt of inset so a selected row's radius-10 fill sits *inside* the card rather than
            // bleeding into its radius-18 corner.
            .padding(4)
            .cadenceCard(background: Theme.surface.opacity(0.72), cornerRadius: Theme.radiusCard)
        }
    }
}

/// A row in the workspace drawer.
///
/// Selection is one neutral layer at one radius — `Theme.surfaceHighlight` on
/// `Theme.radiusControl`, the same treatment `iOSSidebarButton` and `SidebarNavRow` use. It used to
/// be three simultaneous layers: a tinted row wash, a 3pt coloured rail overlaid on the leading
/// edge at a bare numeric radius, and a third tint step on the icon plate.
private struct iOSWorkspaceDrawerRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    /// `nil` for navigation destinations, whose glyphs are chrome. Set only where the colour is the
    /// user's own `colorHex` — a list row.
    var glyphColor: Color? = nil
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // A bare glyph in a fixed leading slot, the vocabulary `iOSEditorInlineLabel`
                // established, so every title in the drawer starts on the same x.
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(glyphColor ?? (isSelected ? Theme.text : Theme.dim))
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let count {
                    iOSListCountBadge(count: count)
                }
            }
            .padding(.horizontal, 10)
            // 44pt, because this popover is the only way to reach a list from the iPad shell.
            .frame(minHeight: 44)
            .background(rowShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
            .contentShape(rowShape)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct iOSWorkspaceDrawerEmptyRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("No active lists")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("Create areas and projects in Lists")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
    }
}
#endif

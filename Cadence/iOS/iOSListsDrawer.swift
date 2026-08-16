#if os(iOS)
import SwiftData
import SwiftUI

/// The iPad shell's list picker, opened from the sidebar's **Lists** row.
///
/// It used to be a "workspace drawer" that listed every destination — Today, Tasks, Inbox,
/// Calendar, Focus, Goals, Habits, Notes, Lists, Search, Settings — above the lists. At expanded
/// width every one of those rows was already on screen about 200pt to its left, in the sidebar the
/// drawer opens from; the only thing here that the sidebar cannot show is the lists themselves,
/// because there is no row per list. So that is all this is now, and the duplication paid for the
/// room the lists needed: the drawer was pinned at 342×640 on a screen over 1100pt tall, which put
/// Search and Settings below the fold of a panel whose whole purpose was reaching them.
struct iOSListsDrawer: View {
    @Binding var selection: iOSSidebarItem?
    /// Raised to the sidebar rather than presented from here: this view dies with the popover, and
    /// a sheet owned by a dismissed presenter goes with it.
    let onCreate: (iOSListEditorMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    /// Completed and archived lists both. They are off the sidebar and out of the active sections,
    /// but they are still readable — the distinction the Lists page draws, drawn here too, so a
    /// list does not simply vanish from the one surface that switches between them.
    private var inactiveAreas: [Area] {
        areas.filter { !$0.isActive }
    }

    private var inactiveProjects: [Project] {
        projects.filter { !$0.isActive }
    }

    private var activeCount: Int {
        activeAreas.count + activeProjects.count
    }

    /// Writes land on `onCreate`; the getter is never read, because nothing in this panel shows a
    /// pending editor — the sheet belongs to the sidebar. This is what lets the drawer use the
    /// shared `iOSListCreateButtonsRow` rather than growing a second pair of create chips.
    private var createBinding: Binding<iOSListEditorMode?> {
        Binding(
            get: { nil },
            set: { mode in
                guard let mode else { return }
                dismiss()
                onCreate(mode)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            iOSListCreateButtonsRow(editorMode: createBinding)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            iOSListHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if activeCount == 0 {
                        iOSListsDrawerSection(title: "Lists") {
                            iOSListsDrawerEmptyRow()
                        }
                    }

                    if !activeAreas.isEmpty {
                        iOSListsDrawerSection(title: "Areas") {
                            ForEach(activeAreas) { area in
                                areaRow(area)
                            }
                        }
                    }

                    if !activeProjects.isEmpty {
                        iOSListsDrawerSection(title: "Projects") {
                            ForEach(activeProjects) { project in
                                projectRow(project)
                            }
                        }
                    }

                    if !inactiveAreas.isEmpty || !inactiveProjects.isEmpty {
                        iOSListsDrawerSection(title: "Archived") {
                            ForEach(inactiveAreas) { area in
                                areaRow(area, isMuted: true)
                            }

                            ForEach(inactiveProjects) { project in
                                projectRow(project, isMuted: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            iOSListHairline()

            allListsRow
        }
        .background(Theme.bg)
    }

    /// Names the panel, not the app. The mark and the word "Cadence" used to sit here, mirroring
    /// the sidebar brand that opened it — identity repeated 200pt from itself, above content it did
    /// not describe.
    private var drawerHeader: some View {
        HStack(spacing: 11) {
            iOSListIconBadge(icon: "folder.fill", colorHex: Theme.blueHex, size: 34)

            Text("Lists")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            if activeCount > 0 {
                iOSListCountBadge(count: activeCount)
            }

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

    /// The way to the full Lists page — creating, archiving, restoring and reordering live there.
    /// It is the one destination row left in this panel, and it earns the place: the Lists row in
    /// the sidebar now opens *this*, so without it the page would have no opener at all.
    private var allListsRow: some View {
        iOSListsDrawerRow(
            title: "All Lists",
            subtitle: "Manage areas and projects",
            systemImage: CadenceFeatureDestination.lists.systemImage,
            count: nil,
            isSelected: selection == .lists
        ) {
            selection = .lists
            dismiss()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func areaRow(_ area: Area, isMuted: Bool = false) -> some View {
        iOSListsDrawerRow(
            title: area.name,
            subtitle: area.context?.name ?? "Area",
            systemImage: area.icon,
            // The sanctioned exception to the chrome-glyph rule: this hue is the `colorHex` the
            // user picked in the list editor.
            glyphColor: Color(hex: area.colorHex),
            isMuted: isMuted,
            count: isMuted ? nil : CadenceTaskQuerySupport.badgeCount(CadenceTaskQuerySupport.openTaskCount(for: area)),
            isSelected: selection == .area(area.id)
        ) {
            selection = .area(area.id)
            dismiss()
        }
    }

    private func projectRow(_ project: Project, isMuted: Bool = false) -> some View {
        iOSListsDrawerRow(
            title: project.name,
            subtitle: project.area?.name ?? project.context?.name ?? "Project",
            systemImage: project.icon,
            glyphColor: Color(hex: project.colorHex),
            isMuted: isMuted,
            count: isMuted ? nil : CadenceTaskQuerySupport.badgeCount(CadenceTaskQuerySupport.openTaskCount(for: project)),
            isSelected: selection == .project(project.id)
        ) {
            selection = .project(project.id)
            dismiss()
        }
    }
}

private struct iOSListsDrawerSection<Content: View>: View {
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

/// A row in the lists drawer.
///
/// Selection is one neutral layer at one radius — `Theme.surfaceHighlight` on
/// `Theme.radiusControl`, the same treatment `iOSSidebarButton` and `SidebarNavRow` use. It used to
/// be three simultaneous layers: a tinted row wash, a 3pt coloured rail overlaid on the leading
/// edge at a bare numeric radius, and a third tint step on the icon plate.
private struct iOSListsDrawerRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    /// `nil` where the glyph is chrome. Set only where the colour is the user's own `colorHex`.
    var glyphColor: Color? = nil
    /// An archived or completed list: the same row, one step quieter. It stays tappable — the list
    /// is still readable, it is just no longer part of the active workspace.
    var isMuted = false
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    private var resolvedGlyphColor: Color {
        let base = glyphColor ?? (isSelected ? Theme.text : Theme.dim)
        return isMuted ? base.opacity(0.55) : base
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // A bare glyph in a fixed leading slot, the vocabulary `iOSEditorInlineLabel`
                // established, so every title in the drawer starts on the same x.
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(resolvedGlyphColor)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isMuted ? Theme.muted : Theme.text)
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
        .accessibilityLabel(title.isEmpty ? "Untitled" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct iOSListsDrawerEmptyRow: View {
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
                Text("Start one with New Area or New Project")
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

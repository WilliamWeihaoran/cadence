#if os(macOS)
import SwiftUI
import AppKit
import EventKit
import SwiftData

struct SettingsCalendarSection: View {
    let calendarManager: CalendarManager
    let areas: [Area]
    let projects: [Project]
    let modelContext: ModelContext

    @AppStorage(CalendarVisibilityPreferences.hiddenCalendarIDsKey) private var hiddenCalendarIDsRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCalendarWorkHoursSection()

            if calendarManager.isAuthorized {
                // Above the calendar list, not inside it: these lists have no live calendar to
                // hang off, which is exactly why they were invisible before T-400.
                if !missingLinks.isEmpty {
                    SettingsSectionLabel(text: "Broken Calendar Links")
                    missingLinksCard
                }

                SettingsSectionLabel(text: "Apple Calendars")
                calendarsCard
            } else {
                calendarAccessCard
            }
        }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var calendars: [EKCalendar] {
        _ = calendarManager.storeVersion
        return calendarManager.allCalendars
    }

    private var hiddenCalendarIDs: Set<String> {
        CalendarVisibilityPreferences.hiddenCalendarIDs(from: hiddenCalendarIDsRaw)
    }

    /// **T-400.** Lists whose `linkedCalendarID` names a calendar EventKit no longer has.
    ///
    /// `calendars` is `allCalendars`, so a calendar merely switched off with the Active toggle is
    /// not reported dead — hidden is not missing.
    private var missingLinks: [CadenceMissingCalendarLink] {
        CadenceCalendarLinkHealth.missingLinks(
            areas: areas,
            projects: projects,
            liveCalendarIDs: Set(calendars.map(\.calendarIdentifier)),
            isCalendarAccessAuthorized: calendarManager.isAuthorized
        )
    }

    private var missingLinksCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                let links = missingLinks
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    SettingsMissingCalendarLinkRow(
                        link: link,
                        calendars: calendars,
                        onRelink: { relink(link, to: $0) },
                        onUnlink: { relink(link, to: "") }
                    )

                    if index < links.count - 1 {
                        CadenceRowDivider(leadingInset: 44)
                    }
                }
            }
        }
    }

    private var calendarsCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if calendars.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text("No Apple calendars found.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else {
                    ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                        SettingsCalendarRow(
                            calendar: calendar,
                            areas: activeAreas,
                            projects: activeProjects,
                            isActive: !hiddenCalendarIDs.contains(calendar.calendarIdentifier),
                            onActiveChanged: { setCalendar(calendar.calendarIdentifier, isActive: $0) },
                            onToggleArea: { toggleCalendar(calendar.calendarIdentifier, for: $0) },
                            onToggleProject: { toggleCalendar(calendar.calendarIdentifier, for: $0) }
                        )

                        if index < calendars.count - 1 {
                            CadenceRowDivider(leadingInset: 44)
                        }
                    }
                }
            }
        }
    }

    private var calendarAccessCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendarManager.isDenied ? "Calendar access denied" : "Calendar access required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(calendarManager.isDenied
                         ? "Allow Cadence from System Settings, Privacy & Security, Calendars."
                         : "Allow Cadence to create and sync calendar events.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if calendarManager.isDenied {
                    SettingsActionButton(tone: .filled(Theme.dim), action: openCalendarPrivacySettings) {
                        Text("Open Calendar Settings")
                    }
                } else {
                    SettingsActionButton(tone: .filled(Theme.blue), action: requestCalendarAccess) {
                        Text("Allow Access")
                    }
                }
            }
        }
    }

    private func requestCalendarAccess() {
        Task { await calendarManager.requestAccess() }
    }

    private func openCalendarPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    private func setCalendar(_ calendarID: String, isActive: Bool) {
        var ids = hiddenCalendarIDs
        if isActive {
            ids.remove(calendarID)
        } else {
            ids.insert(calendarID)
        }
        hiddenCalendarIDsRaw = CalendarVisibilityPreferences.rawHiddenCalendarIDs(from: ids)
        calendarManager.storeVersion += 1
    }

    private func toggleCalendar(_ calendarID: String, for area: Area) {
        area.linkedCalendarID = area.linkedCalendarID == calendarID ? "" : calendarID
        saveCalendarLinks()
    }

    private func toggleCalendar(_ calendarID: String, for project: Project) {
        project.linkedCalendarID = project.linkedCalendarID == calendarID ? "" : calendarID
        saveCalendarLinks()
    }

    /// Writes the user's re-pick, or `""` for Remove Link.
    ///
    /// Deliberately the same assignment the connect menu makes. There is no repair path here that
    /// the user did not choose: nothing infers a calendar from the old identifier or from the
    /// list's name.
    private func relink(_ link: CadenceMissingCalendarLink, to calendarID: String) {
        switch link.kind {
        case .area:
            areas.first { $0.id == link.id }?.linkedCalendarID = calendarID
        case .project:
            projects.first { $0.id == link.id }?.linkedCalendarID = calendarID
        }
        saveCalendarLinks()
    }

    private func saveCalendarLinks() {
        do {
            try modelContext.save()
        } catch {
            print("SettingsCalendarSection: failed to save calendar links: \(error)")
        }
    }
}

/// One dead list-to-calendar link, with the two ways out of it.
private struct SettingsMissingCalendarLinkRow: View {
    let link: CadenceMissingCalendarLink
    let calendars: [EKCalendar]
    let onRelink: (String) -> Void
    let onUnlink: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: link.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: link.colorHex))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(link.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(CadenceCalendarLinkHealth.missingLinkTitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text(CadenceCalendarLinkHealth.missingLinkSummary(for: link))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            repickMenu
                .padding(.top, 1)
        }
        .padding(.vertical, 10)
    }

    /// The re-pick. It lists the calendars that exist and nothing else — no suggested match, no
    /// pre-selection, no ordering that puts a same-named calendar first.
    private var repickMenu: some View {
        Menu {
            if calendars.isEmpty {
                Text("No Apple calendars available")
            } else {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Button(calendar.title) {
                        onRelink(calendar.calendarIdentifier)
                    }
                }
            }

            Divider()

            Button("Remove Link", role: .destructive, action: onUnlink)
        } label: {
            Text("Fix")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Link this list to a calendar that exists, or remove the link")
    }
}

private struct SettingsCalendarRow: View {
    let calendar: EKCalendar
    let areas: [Area]
    let projects: [Project]
    let isActive: Bool
    let onActiveChanged: (Bool) -> Void
    let onToggleArea: (Area) -> Void
    let onToggleProject: (Project) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(calendarColor)
                .frame(width: 12, height: 12)
                .padding(.top, 15)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(calendar.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.text : Theme.muted)
                        .lineLimit(1)

                    if !calendar.allowsContentModifications {
                        Text("Read Only")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Text(sourceTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)

                Text(connectionSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(connectedNames.isEmpty ? Theme.dim : Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                connectionMenu

                Toggle("Active", isOn: Binding(
                    get: { isActive },
                    set: { onActiveChanged($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(isActive ? "Hide this calendar from Cadence" : "Show this calendar in Cadence")
            }
            .padding(.top, 7)
        }
        .padding(.vertical, 10)
    }

    private var connectionMenu: some View {
        Menu {
            if areas.isEmpty && projects.isEmpty {
                Text("No active areas or projects")
            } else {
                if !areas.isEmpty {
                    Section("Areas") {
                        ForEach(areas) { area in
                            Button {
                                onToggleArea(area)
                            } label: {
                                Label(area.name, systemImage: area.linkedCalendarID == calendar.calendarIdentifier ? "checkmark" : area.icon)
                            }
                        }
                    }
                }

                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { project in
                            Button {
                                onToggleProject(project)
                            } label: {
                                Label(project.name, systemImage: project.linkedCalendarID == calendar.calendarIdentifier ? "checkmark" : project.icon)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Connect to areas and projects")
    }

    private var calendarColor: Color {
        guard let cgColor = calendar.cgColor else { return Theme.blue }
        return Color(cgColor: cgColor)
    }

    private var sourceTitle: String {
        calendar.source?.title ?? "Apple Calendar"
    }

    private var connectedNames: [String] {
        let areaNames = areas
            .filter { $0.linkedCalendarID == calendar.calendarIdentifier }
            .map(\.name)
        let projectNames = projects
            .filter { $0.linkedCalendarID == calendar.calendarIdentifier }
            .map(\.name)
        return areaNames + projectNames
    }

    private var connectionSummary: String {
        guard !connectedNames.isEmpty else { return "Not connected to any area or project" }
        return connectedNames.joined(separator: ", ")
    }
}

struct SettingsContextsSection: View {
    let activeContexts: [Context]
    let archivedContexts: [Context]
    let onMoveContext: (UUID, UUID) -> Void
    let onArchiveContext: (Context) -> Void
    let onDeleteContext: (Context) -> Void
    let onRestoreContext: (Context) -> Void
    let onCreateContext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Active Contexts")
            SettingsCard {
                VStack(spacing: 0) {
                    if activeContexts.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dim)
                            Text("No active contexts.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 2)
                        CadenceRowDivider()
                    } else {
                        ForEach(Array(activeContexts.enumerated()), id: \.element.id) { _, context in
                            ContextSettingsRow(
                                context: context,
                                // (dragged, target) — the row hands back the dragged id and *is*
                                // the target, matching `SidebarTabSettingsRow`'s wiring. Reversed,
                                // dropping C onto A moved A and left C where it was.
                                onDropDraggedContext: { draggedID in onMoveContext(draggedID, context.id) },
                                onArchive: { onArchiveContext(context) },
                                onDelete: { onDeleteContext(context) }
                            )
                            CadenceRowDivider(leadingInset: 42)
                        }
                    }

                    Button(action: onCreateContext) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                            Text("New Context")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.blue)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 2)
                    }
                    .buttonStyle(.cadencePlain)
                }
            }

            if !archivedContexts.isEmpty {
                SettingsSectionLabel(text: "Archived Contexts")
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(archivedContexts.enumerated()), id: \.element.id) { index, context in
                            ArchivedContextRow(
                                context: context,
                                onRestore: { onRestoreContext(context) },
                                onDelete: { onDeleteContext(context) }
                            )
                            if index < archivedContexts.count - 1 {
                                CadenceRowDivider(leadingInset: 42)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SettingsListsSection: View {
    let completedAreas: [Area]
    let archivedAreas: [Area]
    let completedProjects: [Project]
    let archivedProjects: [Project]
    let onReopenArea: (Area) -> Void
    let onDeleteArea: (Area) -> Void
    let onReopenProject: (Project) -> Void
    let onDeleteProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if completedAreas.isEmpty && archivedAreas.isEmpty && completedProjects.isEmpty && archivedProjects.isEmpty {
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text("No completed or archived lists.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                }
            } else {
                if !completedAreas.isEmpty {
                    SettingsSectionLabel(text: "Completed Areas")
                    lifecycleCard(areas: completedAreas)
                }
                if !archivedAreas.isEmpty {
                    SettingsSectionLabel(text: "Archived Areas")
                    lifecycleCard(areas: archivedAreas)
                }
                if !completedProjects.isEmpty {
                    SettingsSectionLabel(text: "Completed Projects")
                    lifecycleCard(projects: completedProjects)
                }
                if !archivedProjects.isEmpty {
                    SettingsSectionLabel(text: "Archived Projects")
                    lifecycleCard(projects: archivedProjects)
                }
            }
        }
    }

    private func lifecycleCard(areas: [Area] = [], projects: [Project] = []) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    ListLifecycleRow(
                        icon: area.icon,
                        title: area.name,
                        subtitle: area.context?.name ?? "No context",
                        color: Color(hex: area.colorHex),
                        statusLabel: area.isDone ? "Completed" : "Archived",
                        primaryLabel: area.isDone ? "Reopen" : "Unarchive",
                        onPrimary: { onReopenArea(area) },
                        onDelete: { onDeleteArea(area) }
                    )
                    if index < areas.count - 1 || !projects.isEmpty {
                        CadenceRowDivider(leadingInset: 42)
                    }
                }

                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    ListLifecycleRow(
                        icon: project.icon,
                        title: project.name,
                        subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " • "),
                        color: Color(hex: project.colorHex),
                        statusLabel: project.isDone ? "Completed" : "Archived",
                        primaryLabel: project.isDone ? "Reopen" : "Unarchive",
                        onPrimary: { onReopenProject(project) },
                        onDelete: { onDeleteProject(project) }
                    )
                    if index < projects.count - 1 {
                        CadenceRowDivider(leadingInset: 42)
                    }
                }
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import AppKit

struct SettingsCalendarSection: View {
    let calendarManager: CalendarManager
    let areas: [Area]
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if calendarManager.isAuthorized {
                if !activeAreas.isEmpty {
                    SettingsSectionLabel(text: "Area Calendars")
                    linkCard(items: activeAreas)
                }

                if !activeProjects.isEmpty {
                    SettingsSectionLabel(text: "Project Calendars")
                    linkCard(items: activeProjects)
                }
            } else {
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
        }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private func requestCalendarAccess() {
        Task { await calendarManager.requestAccess() }
    }

    private func openCalendarPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    private func linkCard(items: [Area]) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, area in
                    CalendarLinkRow(
                        icon: area.icon,
                        name: area.name,
                        color: Color(hex: area.colorHex),
                        linkedCalendarID: Binding(
                            get: { area.linkedCalendarID },
                            set: { area.linkedCalendarID = $0 }
                        ),
                        calendars: calendarManager.availableCalendars
                    )
                    if index < items.count - 1 {
                        Divider()
                            .background(Theme.borderSubtle)
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func linkCard(items: [Project]) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, project in
                    CalendarLinkRow(
                        icon: project.icon,
                        name: project.name,
                        color: Color(hex: project.colorHex),
                        linkedCalendarID: Binding(
                            get: { project.linkedCalendarID },
                            set: { project.linkedCalendarID = $0 }
                        ),
                        calendars: calendarManager.availableCalendars
                    )
                    if index < items.count - 1 {
                        Divider()
                            .background(Theme.borderSubtle)
                            .padding(.leading, 44)
                    }
                }
            }
        }
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
                        Divider().background(Theme.borderSubtle)
                    } else {
                        ForEach(Array(activeContexts.enumerated()), id: \.element.id) { _, context in
                            ContextSettingsRow(
                                context: context,
                                onDropBefore: { targetID in onMoveContext(context.id, targetID) },
                                onArchive: { onArchiveContext(context) },
                                onDelete: { onDeleteContext(context) }
                            )
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
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
                                Divider().background(Theme.borderSubtle).padding(.leading, 42)
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
                        Divider().background(Theme.borderSubtle).padding(.leading, 42)
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
                        Divider().background(Theme.borderSubtle).padding(.leading, 42)
                    }
                }
            }
        }
    }
}
#endif

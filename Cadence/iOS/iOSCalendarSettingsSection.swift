#if os(iOS)
import EventKit
import SwiftData
import SwiftUI
import UIKit

struct iOSCalendarSettingsSection: View {
    let calendarManager: iOSCalendarManager
    let areas: [Area]
    let projects: [Project]
    let modelContext: ModelContext

    @AppStorage(CalendarVisibilityPreferences.hiddenCalendarIDsKey) private var hiddenCalendarIDsRaw = ""

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Apple Calendar")

            if calendarManager.isAuthorized {
                calendarsCard
            } else {
                accessCard
            }
        }
        .onAppear {
            calendarManager.refreshAuthorizationState()
        }
    }

    private var calendarsCard: some View {
        CadenceSettingsCard {
            VStack(spacing: 0) {
                if calendars.isEmpty {
                    iOSSettingsEmptyInlineRow(
                        systemImage: "calendar",
                        title: "No Apple calendars found",
                        subtitle: "Calendars available to this device will appear here."
                    )
                } else {
                    ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                        iOSCalendarSettingsRow(
                            calendar: calendar,
                            areas: activeAreas,
                            projects: activeProjects,
                            isActive: !hiddenCalendarIDs.contains(calendar.calendarIdentifier),
                            onActiveChanged: { setCalendar(calendar.calendarIdentifier, isActive: $0) },
                            onToggleArea: { toggleCalendar(calendar.calendarIdentifier, for: $0) },
                            onToggleProject: { toggleCalendar(calendar.calendarIdentifier, for: $0) }
                        )

                        if index < calendars.count - 1 {
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var accessCard: some View {
        CadenceSettingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: calendarManager.isDenied ? "exclamationmark.triangle.fill" : "calendar.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(calendarManager.isDenied ? Theme.amber : Theme.blue)
                    .frame(width: 34, height: 34)
                    .background((calendarManager.isDenied ? Theme.amber : Theme.blue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(calendarManager.isDenied ? "Calendar access denied" : "Calendar access required")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(calendarManager.isDenied
                         ? "Allow Cadence from the iOS Settings app to show Apple Calendar events."
                         : "Allow Cadence to show events and connect Apple calendars to areas or projects.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        calendarManager.isDenied ? openSystemSettings() : requestAccess()
                    } label: {
                        Label(calendarManager.isDenied ? "Open Settings" : "Allow Access", systemImage: calendarManager.isDenied ? "gearshape.fill" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(calendarManager.isDenied ? Theme.amber : Theme.blue)
                    .padding(.top, 6)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func requestAccess() {
        Task {
            await calendarManager.requestAccess()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

    private func saveCalendarLinks() {
        try? modelContext.save()
    }
}

private struct iOSCalendarSettingsRow: View {
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

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(calendar.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.text : Theme.muted)
                        .lineLimit(1)

                    if !calendar.allowsContentModifications {
                        Text("Read Only")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceElevated)
                            .clipShape(Capsule())
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

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                connectionMenu

                Toggle("Active", isOn: Binding(
                    get: { isActive },
                    set: { onActiveChanged($0) }
                ))
                .labelsHidden()
            }
            .padding(.top, 5)
        }
        .padding(.vertical, 10)
        .opacity(isActive ? 1 : 0.68)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
    }

    private var calendarColor: Color {
        iOSCalendarEventSupport.color(for: calendar)
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
#endif

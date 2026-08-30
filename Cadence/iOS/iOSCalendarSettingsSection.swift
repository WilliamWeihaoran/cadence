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
        iOSSettingsCard {
            VStack(spacing: 0) {
                let links = missingLinks
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    iOSMissingCalendarLinkRow(
                        link: link,
                        calendars: calendars,
                        onRelink: { relink(link, to: $0) },
                        onUnlink: { relink(link, to: "") }
                    )

                    if index < links.count - 1 {
                        iOSRowDivider(leadingInset: 24)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Apple Calendar")

            if calendarManager.isAuthorized {
                // Above the calendar list, not inside it: these lists have no live calendar to
                // hang off, which is exactly why they were invisible before T-400.
                if !missingLinks.isEmpty {
                    CadenceSettingsSectionLabel(text: CadenceCalendarLinkHealth.brokenLinksSectionTitle)
                    missingLinksCard
                }

                calendarsCard
            } else {
                accessCard
            }

            iOSCalendarWorkHoursSection()
        }
        .onAppear {
            calendarManager.refreshAuthorizationState()
        }
    }

    private var calendarsCard: some View {
        iOSSettingsCard {
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
                            iOSRowDivider(leadingInset: 24)
                        }
                    }
                }
            }
        }
    }

    private var accessCard: some View {
        iOSSettingsCard {
            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                iOSIconTile(
                    systemImage: calendarManager.isDenied ? "exclamationmark.triangle.fill" : "calendar.badge.plus",
                    color: calendarManager.isDenied ? Theme.amber : Theme.blue,
                    size: 34,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(calendarManager.isDenied ? CadenceCalendarSettingsCopy.accessDeniedTitle : CadenceCalendarSettingsCopy.accessRequiredTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(calendarManager.isDenied
                         ? "Allow Cadence from the iOS Settings app to show Apple Calendar events."
                         : "Allow Cadence to show events and connect Apple calendars to areas or projects.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)

                    iOSActionButton(
                        title: calendarManager.isDenied ? "Open Settings" : "Allow Access",
                        systemImage: calendarManager.isDenied ? "gearshape.fill" : "checkmark.circle.fill",
                        role: .primary,
                        size: .compact,
                        tint: calendarManager.isDenied ? Theme.amber : Theme.blue
                    ) {
                        calendarManager.isDenied ? openSystemSettings() : requestAccess()
                    }
                    .padding(.top, 2)
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
        try? modelContext.save()
    }
}

/// One dead list-to-calendar link, with the two ways out of it.
private struct iOSMissingCalendarLinkRow: View {
    let link: CadenceMissingCalendarLink
    let calendars: [EKCalendar]
    let onRelink: (String) -> Void
    let onUnlink: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: link.icon,
                color: Color(hex: link.colorHex),
                size: 34,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(link.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(CadenceCalendarLinkHealth.missingLinkTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .clipShape(Capsule())
                }

                Text(CadenceCalendarLinkHealth.missingLinkSummary(for: link))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            repickMenu
                .padding(.top, 2)
        }
        .padding(.vertical, 10)
    }

    /// The re-pick. It lists the calendars that exist and nothing else — no suggested match, no
    /// pre-selection, no ordering that puts a same-named calendar first.
    private var repickMenu: some View {
        Menu {
            if calendars.isEmpty {
                Text(CadenceCalendarLinkHealth.noRelinkTargetsLabel)
            } else {
                Section("Link To") {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        Button(calendar.title) {
                            onRelink(calendar.calendarIdentifier)
                        }
                    }
                }
            }

            Button("Remove Link", role: .destructive, action: onUnlink)
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .frame(
                    width: iOSSettingsMetrics.minimumTapTarget,
                    height: iOSSettingsMetrics.minimumTapTarget
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Fix broken calendar link")
    }
}

/// iOS's half of the work-hours preference. Reads and writes the same
/// `calendar.workHours.*.v1` keys as macOS's `SettingsCalendarWorkHoursSection` — the preference
/// was `#if os(macOS)` despite its `calendar.*` (not `macos.*`) key namespace, so a window set on
/// the Mac was invisible and unchangeable here while the iPad timeline drew no band at all.
private struct iOSCalendarWorkHoursSection: View {
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey)
    private var startMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey)
    private var endMinute = CalendarWorkHoursPreferences.defaultEndMinute

    @State private var showStartPicker = false
    @State private var showEndPicker = false

    private var workHoursLabel: String {
        CalendarWorkHoursPreferences.displayLabel(startMinute: startMinute, endMinute: endMinute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Work Hours")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "sun.max.fill",
                            color: Theme.amber,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(CadenceCalendarSettingsCopy.workdayBoundaryTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Calendar day columns gently highlight \(workHoursLabel).")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        picker(
                            title: startMinute,
                            options: CalendarWorkHoursPreferences.selectableStartMinutes,
                            isPresented: $showStartPicker,
                            set: setStartMinute
                        )

                        Text("to")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)

                        picker(
                            title: endMinute,
                            options: CalendarWorkHoursPreferences.selectableEndMinutes,
                            isPresented: $showEndPicker,
                            set: setEndMinute
                        )

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onAppear(perform: repairStoredRangeIfNeeded)
    }

    private func picker(
        title minute: Int,
        options: [Int],
        isPresented: Binding<Bool>,
        set: @escaping (Int) -> Void
    ) -> some View {
        iOSChoiceValueButton(title: TimeFormatters.timeString(from: minute), color: Theme.text) {
            isPresented.wrappedValue = true
        }
        .popover(isPresented: isPresented) {
            iOSChoicePopoverList(
                rows: options.map { option in
                    iOSChoiceRow(value: option, title: TimeFormatters.timeString(from: option), color: Theme.amber)
                },
                selection: Binding(get: { minute }, set: { set($0) }),
                isPresented: isPresented
            )
        }
    }

    private func setStartMinute(_ minute: Int) {
        let range = CalendarWorkHoursPreferences.rangeByUpdatingStart(minute, currentEndMinute: endMinute)
        startMinute = range.startMinute
        endMinute = range.endMinute
    }

    private func setEndMinute(_ minute: Int) {
        let range = CalendarWorkHoursPreferences.rangeByUpdatingEnd(minute, currentStartMinute: startMinute)
        startMinute = range.startMinute
        endMinute = range.endMinute
    }

    private func repairStoredRangeIfNeeded() {
        let range = CalendarWorkHoursPreferences.normalizedRange(startMinute: startMinute, endMinute: endMinute)
        if startMinute != range.startMinute {
            startMinute = range.startMinute
        }
        if endMinute != range.endMinute {
            endMinute = range.endMinute
        }
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.text : Theme.muted)
                        .lineLimit(1)

                    if !calendar.allowsContentModifications {
                        Text("Read Only")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 7)
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
                    .foregroundStyle(connectedNames.isEmpty ? Theme.dim : Theme.subdued)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                connectionMenu

                // Without a tint this is UIKit's system green — the one switch in
                // settings whose colour came from outside the palette.
                Toggle("Active", isOn: Binding(
                    get: { isActive },
                    set: { onActiveChanged($0) }
                ))
                .labelsHidden()
                .tint(Theme.blue)
            }
            .padding(.top, 5)
        }
        .padding(.vertical, 10)
        .opacity(isActive ? 1 : 0.68)
    }

    private var connectionMenu: some View {
        Menu {
            if areas.isEmpty && projects.isEmpty {
                Text(CadenceCalendarSettingsCopy.noConnectableListsLabel)
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
                .frame(width: 36, height: 36)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .frame(
                    width: iOSSettingsMetrics.minimumTapTarget,
                    height: iOSSettingsMetrics.minimumTapTarget
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(CadenceCalendarSettingsCopy.connectMenuLabel)
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
        guard !connectedNames.isEmpty else { return CadenceCalendarSettingsCopy.unconnectedSummary }
        return connectedNames.joined(separator: ", ")
    }
}
#endif

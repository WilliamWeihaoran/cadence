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
    /// **T-624.** Device-local, never synced: the identifiers this device has seen EventKit carry.
    @AppStorage(CadenceCalendarLinkObservations.observedCalendarIDsKey) private var observedCalendarIDsRaw = ""

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
            observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(from: observedCalendarIDsRaw),
            isCalendarAccessAuthorized: calendarManager.isAuthorized
        )
    }

    /// **T-624.** The macOS surface's `refreshCalendarObservations()`, same rule and same three
    /// call sites: appear, store change, and every link write. See
    /// `CadenceCalendarLinkObservations` for why the record is device-local.
    private func refreshCalendarObservations() {
        let updated = CadenceCalendarLinkObservations.observing(
            linkedCalendarIDs: CadenceCalendarLinkObservations.linkedCalendarIDs(areas: areas, projects: projects),
            liveCalendarIDs: Set(calendars.map(\.calendarIdentifier)),
            isCalendarAccessAuthorized: calendarManager.isAuthorized,
            observed: CadenceCalendarLinkObservations.observedCalendarIDs(from: observedCalendarIDsRaw)
        )
        let raw = CadenceCalendarLinkObservations.rawObservedCalendarIDs(from: updated)
        guard raw != observedCalendarIDsRaw else { return }
        observedCalendarIDsRaw = raw
    }

    /// **T-557.** Inactive lists that still hold a calendar link.
    ///
    /// No live set, no observed set and no authorization state: see
    /// `CadenceCalendarLinkHealth.dormantLinks(areas:projects:)` for why asking EventKit nothing is
    /// what keeps this card clear of T-624's evidence gate.
    private var dormantLinks: [CadenceDormantCalendarLink] {
        CadenceCalendarLinkHealth.dormantLinks(areas: areas, projects: projects)
    }

    private var dormantLinksCard: some View {
        iOSSettingsCard {
            VStack(spacing: 0) {
                let links = dormantLinks
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    iOSDormantCalendarLinkRow(
                        link: link,
                        onDisconnect: { disconnect(link) }
                    )

                    if index < links.count - 1 {
                        iOSRowDivider(leadingInset: 24)
                    }
                }
            }
        }
    }

    /// Clears a dormant link. The only write this card makes, and the only one it may make: a
    /// re-pick would put a fresh `EKCalendar.calendarIdentifier` into a CloudKit-synced property,
    /// which is the clobber T-624 removed.
    private func disconnect(_ link: CadenceDormantCalendarLink) {
        switch link.kind {
        case .area:
            areas.first { $0.id == link.id }?.linkedCalendarID = ""
        case .project:
            projects.first { $0.id == link.id }?.linkedCalendarID = ""
        }
        saveCalendarLinks()
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
            if calendarManager.isAuthorized {
                // Above the calendar list, not inside it: these lists have no live calendar to
                // hang off, which is exactly why they were invisible before T-400.
                if !missingLinks.isEmpty {
                    CadenceSettingsSectionLabel(text: CadenceCalendarLinkHealth.brokenLinksSectionTitle)
                    missingLinksCard
                }

                // Inside the branch, as on macOS (T-599(e)). It used to head the whole section, so
                // the access-denied card was also filed under an eyebrow for a list of calendars
                // this app cannot see.
                CadenceSettingsSectionLabel(text: CadenceCalendarSettingsCopy.appleCalendarsSectionTitle)
                calendarsCard
            } else {
                accessCard
            }

            // **Outside the authorization branch, deliberately** (T-557). Every other card here
            // asks EventKit something and so has to wait for permission to ask it. This one asks
            // only this app's own store — which inactive lists still hold a `linkedCalendarID` —
            // and its only control clears one. Gating it on a calendar permission would hide a
            // purely local fact behind an unrelated question, which is a smaller version of the
            // invisibility the card exists to end.
            if !dormantLinks.isEmpty {
                CadenceSettingsSectionLabel(text: CadenceCalendarLinkHealth.dormantLinksSectionTitle)
                dormantLinksCard
            }

            iOSCalendarWorkHoursSection()
        }
        .onAppear {
            calendarManager.refreshAuthorizationState()
            refreshCalendarObservations()
        }
        .onChange(of: calendarManager.storeVersion) { refreshCalendarObservations() }
    }

    private var calendarsCard: some View {
        iOSSettingsCard {
            VStack(spacing: 0) {
                if calendars.isEmpty {
                    iOSSettingsEmptyInlineRow(
                        systemImage: "calendar",
                        title: CadenceSettingsEmptyStateCopy.appleCalendarsTitle,
                        subtitle: CadenceSettingsEmptyStateCopy.appleCalendarsSubtitle
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
                         : CadenceCalendarSettingsCopy.accessRequiredDetail)
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
        refreshCalendarObservations()
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

            Button(CadenceCalendarLinkHealth.removeLinkLabel, role: .destructive, action: onUnlink)
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

/// One dormant list-to-calendar link, with the one way out of it.
///
/// **No re-pick, and no calendar named.** The link is not broken, so there is nothing to repair;
/// the row's job is to say the connection is still there and let the user end it. It resolves the
/// stored identifier against nothing, which is what keeps it silent on a device that has never seen
/// the calendar (T-624).
private struct iOSDormantCalendarLinkRow: View {
    let link: CadenceDormantCalendarLink
    let onDisconnect: () -> Void

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

                    Text(link.statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .clipShape(Capsule())
                }

                Text(CadenceCalendarLinkHealth.dormantLinkSummary(for: link))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)

                // `Theme.dim` on its own 12% wash, which is what macOS's
                // `SettingsActionButton(tone: .tinted(Theme.dim))` renders for the same control:
                // a quiet secondary action, not a red one. Nothing here is broken.
                iOSActionButton(
                    title: CadenceCalendarLinkHealth.removeLinkLabel,
                    role: .secondary,
                    size: .compact,
                    tint: Theme.dim,
                    action: onDisconnect
                )
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
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
                        Text(CadenceCalendarLinkExclusion.readOnly.qualifier)
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
        calendar.source?.title ?? CadenceAppleCalendarNaming.unnamedAccountTitle
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

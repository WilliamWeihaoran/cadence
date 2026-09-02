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
    /// **T-624.** Device-local, never synced: the identifiers this Mac has seen EventKit carry.
    @AppStorage(CadenceCalendarLinkObservations.observedCalendarIDsKey) private var observedCalendarIDsRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCalendarWorkHoursSection()

            if calendarManager.isAuthorized {
                // Above the calendar list, not inside it: these lists have no live calendar to
                // hang off, which is exactly why they were invisible before T-400.
                if !missingLinks.isEmpty {
                    SettingsSectionLabel(text: CadenceCalendarLinkHealth.brokenLinksSectionTitle)
                    missingLinksCard
                }

                SettingsSectionLabel(text: CadenceCalendarSettingsCopy.appleCalendarsSectionTitle)
                calendarsCard
            } else {
                calendarAccessCard
            }

            // **Outside the authorization branch, deliberately** (T-557). Every other card here
            // asks EventKit something and so has to wait for permission to ask it. This one asks
            // only this app's own store — which inactive lists still hold a `linkedCalendarID` —
            // and its only control clears one. Gating it on a calendar permission would hide a
            // purely local fact behind an unrelated question, which is a smaller version of the
            // invisibility the card exists to end.
            if !dormantLinks.isEmpty {
                SettingsSectionLabel(text: CadenceCalendarLinkHealth.dormantLinksSectionTitle)
                dormantLinksCard
            }
        }
        .onAppear { refreshCalendarObservations() }
        .onChange(of: calendarManager.storeVersion) { refreshCalendarObservations() }
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
            observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(from: observedCalendarIDsRaw),
            isCalendarAccessAuthorized: calendarManager.isAuthorized
        )
    }

    /// **T-624.** Learns the identifiers this Mac can currently see behind a live link, and forgets
    /// the ones no list points at any more.
    ///
    /// Run on appear *and* on a store change, because a cold launch renders this screen before
    /// EventKit has finished handing over its calendars, and run again after every link write —
    /// a calendar linked here is by definition one this device can see, and waiting for the next
    /// appearance to notice would leave that link unvouched-for in between.
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
        SettingsCard {
            VStack(spacing: 0) {
                let links = dormantLinks
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    SettingsDormantCalendarLinkRow(
                        link: link,
                        onDisconnect: { disconnect(link) }
                    )

                    if index < links.count - 1 {
                        CadenceRowDivider(leadingInset: 44)
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
                    // **T-545.** The shared notice row rather than a private one-liner, and the
                    // fifth of the four cards T-600(b) converged. It is the odd one: access has
                    // been granted and EventKit answered with nothing, so "you have made none yet"
                    // is not what happened and the second line — what *would* appear here — is the
                    // only useful thing to say.
                    CadenceSettingsNoticeRow(
                        systemImage: "calendar",
                        title: CadenceSettingsEmptyStateCopy.appleCalendarsTitle,
                        detail: CadenceSettingsEmptyStateCopy.appleCalendarsSubtitle
                    ) {
                        EmptyView()
                    }
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

    /// **T-543.** One glyph and one sentence per state, on the row Notifications and Reminders
    /// already draw.
    ///
    /// This card used to draw an amber warning triangle **unconditionally** — including before
    /// anybody had been asked, which is the state a fresh install is in — beside a button offering
    /// access. Nobody has done anything wrong there, so the triangle contradicted the offer next to
    /// it. The denied arm keeps it, because that one *is* a fault the reader has to go and fix.
    ///
    /// The not-yet-asked sentence is shared with the phone now; the denied one is not, and must not
    /// be: it names where the reader has to go, and that is a different place on each platform.
    private var calendarAccessCard: some View {
        SettingsCard {
            CadenceSettingsNoticeRow(
                systemImage: calendarManager.isDenied ? "exclamationmark.triangle.fill" : "calendar.badge.plus",
                tint: calendarManager.isDenied ? Theme.amber : Theme.blue,
                title: calendarManager.isDenied
                    ? CadenceCalendarSettingsCopy.accessDeniedTitle
                    : CadenceCalendarSettingsCopy.accessRequiredTitle,
                detail: calendarManager.isDenied
                    ? "Allow Cadence from System Settings, Privacy & Security, Calendars."
                    : CadenceCalendarSettingsCopy.accessRequiredDetail
            ) {
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
        refreshCalendarObservations()
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
                Text(CadenceCalendarLinkHealth.noRelinkTargetsLabel)
            } else {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Button(calendar.title) {
                        onRelink(calendar.calendarIdentifier)
                    }
                }
            }

            Divider()

            Button(CadenceCalendarLinkHealth.removeLinkLabel, role: .destructive, action: onUnlink)
        } label: {
            Text("Fix")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Fix calendar link")
        .help("Link this list to a calendar that exists, or remove the link")
    }
}

/// One dormant list-to-calendar link, with the one way out of it.
///
/// **No re-pick, and no calendar named.** The link is not broken, so there is nothing to repair;
/// the row's job is to say the connection is still there and let the user end it. It resolves the
/// stored identifier against nothing, which is what keeps it silent on a device that has never seen
/// the calendar (T-624).
private struct SettingsDormantCalendarLinkRow: View {
    let link: CadenceDormantCalendarLink
    let onDisconnect: () -> Void

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

                    Text(link.statusLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text(CadenceCalendarLinkHealth.dormantLinkSummary(for: link))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            SettingsActionButton(tone: .tinted(Theme.dim), action: onDisconnect) {
                Text(CadenceCalendarLinkHealth.removeLinkLabel)
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 10)
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
                        Text(CadenceCalendarLinkExclusion.readOnly.qualifier)
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
                .accessibilityLabel("Active")
                .help(isActive ? "Hide this calendar from Cadence" : "Show this calendar in Cadence")
            }
            .padding(.top, 7)
        }
        .padding(.vertical, 10)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .cadenceControlLabel(CadenceCalendarSettingsCopy.connectMenuLabel)
    }

    private var calendarColor: Color {
        guard let cgColor = calendar.cgColor else { return Theme.blue }
        return Color(cgColor: cgColor)
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
                        // "Create one here" is true on this platform too: the **New Context**
                        // button is in this same card, directly under the divider below.
                        CadenceSettingsNoticeRow(
                            systemImage: "square.stack.3d.up",
                            title: CadenceSettingsEmptyStateCopy.contextsTitle,
                            detail: CadenceSettingsEmptyStateCopy.contextsSubtitle
                        ) {
                            EmptyView()
                        }
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
                // The eyebrow is half of T-600(b) here: every other branch of this pane names
                // the group it is showing, and the empty one — the only branch a reader with no
                // inactive lists ever sees — named nothing.
                SettingsSectionLabel(text: CadenceSettingsEmptyStateCopy.inactiveListsSectionTitle)
                SettingsCard {
                    CadenceSettingsNoticeRow(
                        systemImage: "archivebox",
                        title: CadenceSettingsEmptyStateCopy.inactiveListsTitle,
                        detail: CadenceSettingsEmptyStateCopy.inactiveListsSubtitle
                    ) {
                        EmptyView()
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
                        // Not `area.name` (T-577): an unnamed list drew a row with no title at
                        // all, three lines above a subtitle branch that already knew to fall back.
                        title: CadenceTitleNormalization.display(
                            area.name,
                            fallback: CadenceTitleNormalization.defaultAreaName
                        ),
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
                        title: CadenceTitleNormalization.display(
                            project.name,
                            fallback: CadenceTitleNormalization.defaultProjectName
                        ),
                        // The join was `""` for a project with neither a context nor an area, so
                        // the row's second line was blank rather than absent (T-577).
                        subtitle: CadenceListSettingsCopy.parentSubtitle(
                            contextName: project.context?.name,
                            areaName: project.area?.name
                        ),
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

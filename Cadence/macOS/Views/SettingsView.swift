#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct SettingsView: View {
    private enum SettingsCategory: String, CaseIterable, Identifiable {
        case appearance
        case account
        case navigation
        case sidebar
        case contexts
        case lists
        case ai
        case calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .account: return "Account"
            case .navigation: return "Navigation"
            case .sidebar: return "Sidebar"
            case .contexts: return "Contexts"
            case .lists: return "Lists"
            case .ai: return "AI"
            case .calendar: return "Calendar"
            }
        }

        var subtitle: String {
            switch self {
            case .appearance:
                return "Themes and overall visual mood."
            case .account:
                return "Apple account identity."
            case .navigation:
                return "How lists open and behave by default."
            case .sidebar:
                return "Choose which static destinations stay visible."
            case .contexts:
                return "Add, edit, archive, and reorder contexts."
            case .lists:
                return "Completed and archived areas and projects."
            case .ai:
                return "Bring your own OpenAI key for local AI actions."
            case .calendar:
                return "Apple Calendar access and linked calendars."
            }
        }

        var icon: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .account: return "person.crop.circle.fill"
            case .navigation: return "rectangle.stack.fill"
            case .sidebar: return "sidebar.left"
            case .contexts: return "square.stack.3d.up.fill"
            case .lists: return "archivebox.fill"
            case .ai: return "sparkles"
            case .calendar: return "calendar"
            }
        }

        var tint: Color {
            switch self {
            case .appearance: return Theme.blue
            case .account: return Theme.green
            case .navigation: return Theme.green
            case .sidebar: return Theme.amber
            case .contexts: return Theme.red
            case .lists: return Theme.amber
            case .ai: return Theme.blue
            case .calendar: return Theme.purple
            }
        }
    }

    @Environment(ThemeManager.self) private var themeManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(AppleAccountManager.self) private var appleAccountManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("listDetailDefaultPage") private var listDetailDefaultPage = ListDetailPage.tasks.rawValue
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""
    @AppStorage("sidebarTabOrder") private var sidebarTabOrderRaw = ""
    @AppStorage("sidebarTabColors") private var sidebarTabColorsRaw = ""
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var pendingDeleteArea: Area? = nil
    @State private var pendingDeleteProject: Project? = nil
    @State private var pendingDeleteContext: Context? = nil
    @State private var showCreateContext = false
    @State private var editingSidebarTab: SidebarStaticDestination? = nil
    @State private var aiAPIKeyDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            settingsRail

            Divider()
                .background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHeader
                    selectedSectionContent
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .cadenceSoftPageBounce()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete Area?",
            isPresented: Binding(
                get: { pendingDeleteArea != nil },
                set: { if !$0 { pendingDeleteArea = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Area", role: .destructive) {
                if let area = pendingDeleteArea { deleteArea(area) }
                pendingDeleteArea = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteArea = nil }
        } message: {
            Text("This permanently deletes the area and its tasks, projects, documents, and links.")
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = pendingDeleteProject { deleteProject(project) }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
        } message: {
            Text("This permanently deletes the project and its tasks, documents, and links.")
        }
        .confirmationDialog(
            "Delete Context?",
            isPresented: Binding(
                get: { pendingDeleteContext != nil },
                set: { if !$0 { pendingDeleteContext = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Context", role: .destructive) {
                if let context = pendingDeleteContext { deleteContext(context) }
                pendingDeleteContext = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteContext = nil }
        } message: {
            Text("This permanently deletes the context and all its areas, projects, tasks, goals, and habits.")
        }
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $editingSidebarTab) { destination in
            SidebarTabEditorSheet(
                destination: destination,
                tintHex: Binding(
                    get: { destination.resolvedColorHex(from: sidebarTabColorsRaw) },
                    set: { setTabColor(destination, hex: $0) }
                ),
                isVisible: Binding(
                    get: { !hiddenTabs.contains(destination) },
                    set: { newValue in
                        let isCurrentlyVisible = !hiddenTabs.contains(destination)
                        if newValue != isCurrentlyVisible {
                            toggleTab(destination)
                        }
                    }
                )
            )
        }
    }

    // MARK: - Calendar Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(ThemeOption.allCases) { option in
                    themeOptionCard(option)
                }
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill((appleAccountManager.isSignedIn ? Theme.green : Theme.dim).opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(appleAccountManager.isSignedIn ? Theme.green : Theme.dim)
                            }

                        VStack(alignment: .leading, spacing: 7) {
                            if let profile = appleAccountManager.profile {
                                Text(profile.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                if !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(profile.email)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.dim)
                                }
                                Text("Signed in \(DateFormatters.shortDate.string(from: profile.signedInAt))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            } else {
                                Text("Sign in with Apple")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("Use your Apple account as your Cadence identity. This does not lock the app or change iCloud sync.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let statusMessage = appleAccountManager.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer()

                        if appleAccountManager.isSignedIn {
                            Button("Sign Out") {
                                appleAccountManager.signOut()
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Button {
                                appleAccountManager.signIn()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(appleAccountManager.isAuthorizing ? "Signing In..." : "Sign in with Apple")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(appleAccountManager.isAuthorizing ? Theme.dim : Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                            .disabled(appleAccountManager.isAuthorizing)
                        }
                    }

                    Divider()
                        .background(Theme.borderSubtle)

                    VStack(spacing: 8) {
                        accountDiagnosticRow(
                            title: "Credential",
                            value: appleAccountManager.credentialStatus.title,
                            color: appleAccountManager.credentialStatus == .authorized ? Theme.green : Theme.dim
                        )
                        accountDiagnosticRow(
                            title: "Apple Sign-In Entitlement",
                            value: appleAccountManager.entitlementStatus.title,
                            color: appleAccountManager.entitlementStatus.isConfigured ? Theme.green : Theme.amber,
                            detail: appleAccountManager.entitlementStatus.detail
                        )
                    }
                }
            }
        }
        .onAppear {
            appleAccountManager.refreshCredentialState()
        }
    }

    private func accountDiagnosticRow(
        title: String,
        value: String,
        color: Color,
        detail: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill((aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim).opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("OpenAI BYOK")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Cadence stores your API key in Keychain and sends only the note you choose to summarize or extract tasks from.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let statusMessage = aiSettingsManager.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        Spacer()
                    }

                    Divider().background(Theme.borderSubtle)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("API Key")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Model")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Save Key") {
                            do {
                                try aiSettingsManager.saveAPIKey(aiAPIKeyDraft)
                                aiAPIKeyDraft = ""
                            } catch {
                                aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
                            }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(aiSettingsManager.isTestingConnection ? "Testing..." : "Test Connection") {
                            Task { await aiSettingsManager.testConnection() }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!aiSettingsManager.hasAPIKey || aiSettingsManager.isTestingConnection)

                        if aiSettingsManager.hasAPIKey {
                            Button("Remove Key") {
                                do {
                                    try aiSettingsManager.removeAPIKey()
                                } catch {
                                    aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
                                }
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .onAppear {
            aiSettingsManager.refreshKeyStatus()
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if calendarManager.isAuthorized {
                // Areas
                let activeAreas = areas.filter(\.isActive)
                if !activeAreas.isEmpty {
                    sectionLabel("Areas")
                    settingsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(activeAreas.enumerated()), id: \.element.id) { index, area in
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
                                if index < activeAreas.count - 1 {
                                    Divider()
                                        .background(Theme.borderSubtle)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                }

                // Projects
                let activeProjects = projects.filter(\.isActive)
                if !activeProjects.isEmpty {
                    sectionLabel("Projects")
                    settingsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(activeProjects.enumerated()), id: \.element.id) { index, project in
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
                                if index < activeProjects.count - 1 {
                                    Divider()
                                        .background(Theme.borderSubtle)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                }
            } else {
                // Not authorized — show grant or redirect button
                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.amber)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendarManager.isDenied ? "Access denied" : "Calendar access required")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(calendarManager.isDenied
                                 ? "Open System Settings → Privacy & Security → Calendars to allow access."
                                 : "Cadence needs permission to create and sync calendar events.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if calendarManager.isDenied {
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.dim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Button("Grant Access") {
                                Task { await calendarManager.requestAccess() }
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default List Page")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    HStack(spacing: 10) {
                        ForEach(ListDetailPage.allCases) { page in
                            Button {
                                listDetailDefaultPage = page.rawValue
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: page.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(page.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(listDetailDefaultPage == page.rawValue ? .white : Theme.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 34)
                                .contentShape(Rectangle())
                                .background(listDetailDefaultPage == page.rawValue ? Theme.blue : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
        }
    }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    private var orderedSidebarTabs: [SidebarStaticDestination] {
        SidebarStaticDestination.orderedDestinations(from: sidebarTabOrderRaw)
    }

    private func toggleTab(_ destination: SidebarStaticDestination) {
        var set = hiddenTabs
        if set.contains(destination) { set.remove(destination) } else { set.insert(destination) }
        sidebarHiddenTabsRaw = set.map(\.rawValue).joined(separator: ",")
    }

    private func setTabColor(_ destination: SidebarStaticDestination, hex: String) {
        var colors = SidebarStaticDestination.colorHexMap(from: sidebarTabColorsRaw)
        colors[destination] = hex
        sidebarTabColorsRaw = SidebarStaticDestination.rawColorString(from: colors)
    }

    private func moveSidebarTab(_ dragged: SidebarStaticDestination, before target: SidebarStaticDestination) {
        var current = orderedSidebarTabs
        guard let fromIndex = current.firstIndex(of: dragged),
              let toIndex = current.firstIndex(of: target) else { return }
        let moved = current.remove(at: fromIndex)
        current.insert(moved, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        sidebarTabOrderRaw = SidebarStaticDestination.rawOrderString(from: current)
    }

    private var sidebarTabsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(orderedSidebarTabs.enumerated()), id: \.element.id) { index, destination in
                        SidebarTabSettingsRow(
                            destination: destination,
                            tintHex: destination.resolvedColorHex(from: sidebarTabColorsRaw),
                            isVisible: !hiddenTabs.contains(destination),
                            onEdit: { editingSidebarTab = destination },
                            onDropBefore: { moveSidebarTab($0, before: destination) }
                        )
                        if index < orderedSidebarTabs.count - 1 {
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let activeContexts = contexts.filter { !$0.isArchived }
            let archivedContexts = contexts.filter { $0.isArchived }

            settingsCard {
                VStack(spacing: 0) {
                    if activeContexts.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dim)
                            Text("No contexts yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 2)
                        Divider().background(Theme.borderSubtle)
                    } else {
                        ForEach(Array(activeContexts.enumerated()), id: \.element.id) { index, context in
                            ContextSettingsRow(
                                context: context,
                                onDropBefore: { targetID in moveContext(context.id, before: targetID) },
                                onArchive: { context.isArchived = true },
                                onDelete: { pendingDeleteContext = context }
                            )
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
                    }

                    Button { showCreateContext = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                            Text("Add Context")
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
                sectionLabel("Archived")
                settingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(archivedContexts.enumerated()), id: \.element.id) { index, context in
                            ArchivedContextRow(
                                context: context,
                                onRestore: { context.isArchived = false },
                                onDelete: { pendingDeleteContext = context }
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

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let completedAreas = areas.filter(\.isDone)
            let archivedAreas = areas.filter(\.isArchived)
            let completedProjects = projects.filter(\.isDone)
            let archivedProjects = projects.filter(\.isArchived)

            if completedAreas.isEmpty && archivedAreas.isEmpty && completedProjects.isEmpty && archivedProjects.isEmpty {
                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text("No completed or archived lists yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                }
            } else {
                if !completedAreas.isEmpty {
                    sectionLabel("Completed Areas")
                    listLifecycleCard(areas: completedAreas)
                }
                if !archivedAreas.isEmpty {
                    sectionLabel("Archived Areas")
                    listLifecycleCard(areas: archivedAreas)
                }
                if !completedProjects.isEmpty {
                    sectionLabel("Completed Projects")
                    listLifecycleCard(projects: completedProjects)
                }
                if !archivedProjects.isEmpty {
                    sectionLabel("Archived Projects")
                    listLifecycleCard(projects: archivedProjects)
                }
            }
        }
    }

    private func moveContext(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var ordered = contexts
        guard let fromIndex = ordered.firstIndex(where: { $0.id == draggedID }),
              let toIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }

        let moved = ordered.remove(at: fromIndex)
        let insertionIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
        ordered.insert(moved, at: insertionIndex)

        for (index, context) in ordered.enumerated() {
            context.order = index
        }

        try? modelContext.save()
    }

    private var settingsRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Tune the app without digging through one giant page.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(SettingsCategory.allCases) { category in
                    settingsRailButton(category)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }

    private var detailHeader: some View {
        settingsCard {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedCategory.tint.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: selectedCategory.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selectedCategory.tint)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedCategory.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(detailHeaderDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if selectedCategory == .calendar {
                    authBadge
                } else if selectedCategory == .account {
                    accountBadge
                } else if selectedCategory == .ai {
                    aiBadge
                }
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedCategory {
        case .appearance:
            appearanceSection
        case .account:
            accountSection
        case .navigation:
            navigationSection
        case .sidebar:
            sidebarTabsSection
        case .contexts:
            contextsSection
        case .lists:
            listsSection
        case .ai:
            aiSection
        case .calendar:
            calendarSection
        }
    }

    private var detailHeaderDescription: String {
        switch selectedCategory {
        case .appearance:
            return "Pick the dark palette that best fits your workspace. Changes apply across the app immediately."
        case .account:
            return "Connect an Apple account for local identity. Cadence still works signed out."
        case .navigation:
            return "Choose which page new lists open on by default. Once you visit a specific list, Cadence still remembers that list's most recently opened page."
        case .sidebar:
            return "Choose which tabs appear in the sidebar. Hidden tabs are still accessible by re-enabling them here."
        case .contexts:
            return "Add, edit, archive, and drag to reorder contexts. Archived contexts are hidden from the sidebar but not deleted."
        case .lists:
            return "Completed and archived lists live here so you can restore, reopen, or permanently delete them."
        case .ai:
            return "Use your own OpenAI API key for note summaries and task extraction. Cadence stores the key in Keychain."
        case .calendar:
            return "Scheduled tasks sync to Apple Calendar when their area or project has a linked calendar."
        }
    }

    @ViewBuilder
    private func settingsRailButton(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category

        Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.tint.opacity(isSelected ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: category.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(category.tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.92))
                    Text(category.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? selectedCategory.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }

    @ViewBuilder
    private var accountBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appleAccountManager.isSignedIn ? Theme.green : Theme.dim)
                .frame(width: 7, height: 7)
            Text(appleAccountManager.isSignedIn ? "Signed in" : "Signed out")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(appleAccountManager.isSignedIn ? Theme.green : Theme.dim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((appleAccountManager.isSignedIn ? Theme.green : Theme.dim).opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var aiBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim)
                .frame(width: 7, height: 7)
            Text(aiSettingsManager.hasAPIKey ? "Key saved" : "No key")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim).opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var authBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(calendarManager.isAuthorized ? Theme.green : Theme.dim)
                .frame(width: 7, height: 7)
            Text(calendarManager.isAuthorized ? "Connected" : "Not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(calendarManager.isAuthorized ? Theme.green : Theme.dim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((calendarManager.isAuthorized ? Theme.green : Theme.dim).opacity(0.12))
        .clipShape(Capsule())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    @ViewBuilder
    private func listLifecycleCard(areas: [Area] = [], projects: [Project] = []) -> some View {
        settingsCard {
            VStack(spacing: 0) {
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    ListLifecycleRow(
                        icon: area.icon,
                        title: area.name,
                        subtitle: area.context?.name ?? "No context",
                        color: Color(hex: area.colorHex),
                        statusLabel: area.isDone ? "Completed" : "Archived",
                        primaryLabel: area.isDone ? "Reopen" : "Unarchive",
                        onPrimary: {
                            area.status = .active
                            try? modelContext.save()
                        },
                        onDelete: { pendingDeleteArea = area }
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
                        onPrimary: {
                            project.status = .active
                            try? modelContext.save()
                        },
                        onDelete: { pendingDeleteProject = project }
                    )
                    if index < projects.count - 1 {
                        Divider().background(Theme.borderSubtle).padding(.leading, 42)
                    }
                }
            }
        }
    }

    private func deleteContext(_ context: Context) {
        modelContext.deleteContext(context)
        try? modelContext.save()
    }

    private func deleteArea(_ area: Area) {
        modelContext.deleteArea(area)
        try? modelContext.save()
    }

    private func deleteProject(_ project: Project) {
        modelContext.deleteProject(project)
        try? modelContext.save()
    }

    @ViewBuilder
    private func themeOptionCard(_ option: ThemeOption) -> some View {
        let isSelected = themeManager.selectedTheme == option

        Button {
            themeManager.selectedTheme = option
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Array(option.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(height: 34)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if isSelected {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.blue)
                                .clipShape(Capsule())
                        }
                    }

                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.blue.opacity(0.7) : Theme.borderSubtle, lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
    }
}

#endif

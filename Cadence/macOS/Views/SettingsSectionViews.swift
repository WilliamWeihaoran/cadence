#if os(macOS)
import SwiftUI
import AppKit
import EventKit

struct SettingsAppearanceSection: View {
    let selectedTheme: ThemeOption
    let onSelectTheme: (ThemeOption) -> Void

    var body: some View {
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

    private func themeOptionCard(_ option: ThemeOption) -> some View {
        let isSelected = selectedTheme == option

        return Button {
            onSelectTheme(option)
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
}

struct SettingsAccountSection: View {
    let appleAccountManager: AppleAccountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
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
}

struct SettingsAISection: View {
    let aiSettingsManager: AISettingsManager
    @Binding var aiAPIKeyDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
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

                    settingsField(title: "API Key") {
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                    }

                    settingsField(title: "Model") {
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
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

    private func settingsField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content()
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
    }
}

struct SettingsDataSafetySection: View {
    @State private var backups: [StoreBackupSnapshot] = []
    @State private var statusMessage: String?
    @State private var pendingRestore: StoreBackupSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.amber.opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "externaldrive.fill.badge.timemachine")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.amber)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Store Snapshots")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Cadence copies the full SwiftData store, WAL, CloudKit assets, and external storage before startup migration work. Automatic snapshots are thinned over time.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Button {
                                createBackup()
                            } label: {
                                Label("Create Backup", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                cleanUpAutomaticBackups()
                            } label: {
                                Label("Clean Up", systemImage: "wand.and.sparkles")
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.amber.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                revealBackupFolder()
                            } label: {
                                Label("Reveal", systemImage: "folder.fill")
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            SettingsSectionLabel(text: "Restore Points")
            SettingsCard {
                VStack(spacing: 0) {
                    if backups.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                            Text("No backups yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(backups.prefix(16).enumerated()), id: \.element.id) { index, backup in
                            StoreBackupRow(
                                backup: backup,
                                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) },
                                onRestore: { pendingRestore = backup }
                            )
                            if index < min(backups.count, 16) - 1 {
                                Divider().background(Theme.borderSubtle).padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshBackups)
        .confirmationDialog(
            "Restore Backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stage Restore", role: .destructive) {
                if let pendingRestore {
                    stageRestore(pendingRestore)
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            Text("Cadence will restore this backup before SwiftData opens the store on the next app launch. Quit and reopen Cadence after staging.")
        }
    }

    private func refreshBackups() {
        backups = StoreBackupManager.listBackups()
    }

    private func createBackup() {
        do {
            if let url = try StoreBackupManager.createBackupIfStoreExists(reason: .manual) {
                statusMessage = "Created \(url.lastPathComponent)."
            } else {
                statusMessage = "No active store exists yet."
            }
            refreshBackups()
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func cleanUpAutomaticBackups() {
        do {
            let removedCount = try StoreBackupManager.cleanUpAutomaticBackups()
            statusMessage = removedCount == 0
                ? "Automatic backups are already thinned."
                : "Removed \(removedCount) older automatic backup\(removedCount == 1 ? "" : "s")."
            refreshBackups()
        } catch {
            statusMessage = "Cleanup failed: \(error.localizedDescription)"
        }
    }

    private func revealBackupFolder() {
        do {
            try FileManager.default.createDirectory(at: StoreBackupManager.backupRootURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([StoreBackupManager.backupRootURL])
        } catch {
            statusMessage = "Could not open backup folder: \(error.localizedDescription)"
        }
    }

    private func stageRestore(_ backup: StoreBackupSnapshot) {
        do {
            try StoreBackupManager.scheduleRestore(from: backup.url)
            statusMessage = "Restore staged. Quit and reopen Cadence to apply it."
        } catch {
            statusMessage = "Could not stage restore: \(error.localizedDescription)"
        }
    }
}

private struct StoreBackupRow: View {
    let backup: StoreBackupSnapshot
    let onReveal: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.amber.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(backup.reason) • \(backup.displaySize)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            Button("Reveal", action: onReveal)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Restore", action: onRestore)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.amber.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}

struct SettingsCalendarSection: View {
    let calendarManager: CalendarManager
    let areas: [Area]
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if calendarManager.isAuthorized {
                if !activeAreas.isEmpty {
                    SettingsSectionLabel(text: "Areas")
                    linkCard(items: activeAreas)
                }

                if !activeProjects.isEmpty {
                    SettingsSectionLabel(text: "Projects")
                    linkCard(items: activeProjects)
                }
            } else {
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.amber)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendarManager.isDenied ? "Access denied" : "Calendar access required")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(calendarManager.isDenied
                                 ? "Open System Settings -> Privacy & Security -> Calendars to allow access."
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

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
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

struct SettingsNavigationSection: View {
    @Binding var listDetailDefaultPage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
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
}

struct SettingsSidebarSection: View {
    let orderedSidebarTabs: [SidebarStaticDestination]
    let hiddenTabs: Set<SidebarStaticDestination>
    let sidebarTabColorsRaw: String
    let onEdit: (SidebarStaticDestination) -> Void
    let onDropBefore: (SidebarStaticDestination, SidebarStaticDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(orderedSidebarTabs.enumerated()), id: \.element.id) { index, destination in
                        SidebarTabSettingsRow(
                            destination: destination,
                            tintHex: destination.resolvedColorHex(from: sidebarTabColorsRaw),
                            isVisible: !hiddenTabs.contains(destination),
                            onEdit: { onEdit(destination) },
                            onDropBefore: { onDropBefore($0, destination) }
                        )
                        if index < orderedSidebarTabs.count - 1 {
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
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
            SettingsCard {
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
                SettingsSectionLabel(text: "Archived")
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
                        Text("No completed or archived lists yet.")
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

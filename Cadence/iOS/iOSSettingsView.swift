#if os(iOS)
import CloudKit
import SwiftData
import SwiftUI

struct iOSSettingsView: View {
    @Query private var tasks: [AppTask]
    @Query private var areas: [Area]
    @Query private var projects: [Project]
    @Query private var notes: [Note]
    @State private var accountStatus: CKAccountStatus?
    @State private var accountError: String?
    @State private var isCheckingAccount = false
    @State private var lastChecked: Date?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cadence")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("iPad and iPhone companion")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Sync") {
                HStack(spacing: 12) {
                    Image(systemName: cloudStatusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(cloudStatusColor)
                        .frame(width: 30, height: 30)
                        .background(cloudStatusColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(cloudStatusTitle)
                            .foregroundStyle(Theme.text)
                        Text(cloudStatusSubtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }

                    Spacer()

                    if isCheckingAccount {
                        ProgressView()
                            .tint(Theme.blue)
                    }
                }

                Button {
                    refreshAccountStatus()
                } label: {
                    Label("Check iCloud Status", systemImage: "arrow.clockwise")
                }
                .disabled(isCheckingAccount)

                if let lastChecked {
                    LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Build") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Bundle ID", value: bundleID)
            }

            Section("Local Data") {
                LabeledContent("Active tasks", value: "\(activeTaskCount)")
                LabeledContent("Completed tasks", value: "\(completedTaskCount)")
                LabeledContent("Inbox tasks", value: "\(inboxTaskCount)")
                LabeledContent("Active areas", value: "\(activeAreaCount)")
                LabeledContent("Active projects", value: "\(activeProjectCount)")
                LabeledContent("Notes", value: "\(notes.count)")
            }

            Section("Mobile Coverage") {
                iOSSettingsCapabilityRow(title: "Today planning", isReady: true)
                iOSSettingsCapabilityRow(title: "Inbox capture", isReady: true)
                iOSSettingsCapabilityRow(title: "Create/edit/archive lists", isReady: true)
                iOSSettingsCapabilityRow(title: "Search", isReady: true)
                iOSSettingsCapabilityRow(title: "Plain notes", isReady: true)
                iOSSettingsCapabilityRow(title: "Calendar timeline", isReady: false)
                iOSSettingsCapabilityRow(title: "Focus timer", isReady: false)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .onAppear {
            if accountStatus == nil && !isCheckingAccount {
                refreshAccountStatus()
            }
        }
    }

    private var activeTaskCount: Int {
        tasks.filter { !$0.isDone && !$0.isCancelled }.count
    }

    private var completedTaskCount: Int {
        tasks.filter(\.isDone).count
    }

    private var inboxTaskCount: Int {
        tasks.filter { $0.area == nil && $0.project == nil && !$0.isDone && !$0.isCancelled }.count
    }

    private var activeAreaCount: Int {
        areas.filter(\.isActive).count
    }

    private var activeProjectCount: Int {
        projects.filter(\.isActive).count
    }

    private var cloudStatusTitle: String {
        if isCheckingAccount { return "Checking iCloud" }
        if let accountError { return "Could not check iCloud" }
        guard let accountStatus else { return "iCloud not checked" }

        switch accountStatus {
        case .available:
            return "iCloud available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud restricted"
        case .couldNotDetermine:
            return "iCloud unknown"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        @unknown default:
            return "iCloud unknown"
        }
    }

    private var cloudStatusSubtitle: String {
        if let accountError { return accountError }
        guard let accountStatus else {
            return "Check status before relying on TestFlight sync."
        }

        switch accountStatus {
        case .available:
            return "CloudKit should be able to sync Cadence data."
        case .noAccount:
            return "Sign into iCloud on this device to sync."
        case .restricted:
            return "iCloud is restricted by device or account policy."
        case .couldNotDetermine:
            return "Try again or check device network/iCloud settings."
        case .temporarilyUnavailable:
            return "Apple reported iCloud is temporarily unavailable."
        @unknown default:
            return "This device returned an unknown iCloud state."
        }
    }

    private var cloudStatusIcon: String {
        if isCheckingAccount { return "icloud" }
        if accountError != nil { return "exclamationmark.icloud" }
        guard accountStatus == .available else { return "icloud.slash" }
        return "checkmark.icloud"
    }

    private var cloudStatusColor: Color {
        if accountStatus == .available && accountError == nil { return Theme.green }
        if isCheckingAccount { return Theme.blue }
        if accountStatus == nil && accountError == nil { return Theme.dim }
        return Theme.amber
    }

    private func refreshAccountStatus() {
        isCheckingAccount = true
        accountError = nil

        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                accountStatus = status
                accountError = error?.localizedDescription
                isCheckingAccount = false
                lastChecked = Date()
            }
        }
    }
}

private struct iOSSettingsCapabilityRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.text)
            Spacer()
            Label(isReady ? "Ready" : "Later",
                  systemImage: isReady ? "checkmark.circle.fill" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isReady ? Theme.green : Theme.dim)
        }
    }
}
#endif

#if os(iOS)
import CloudKit
import SwiftUI

struct iOSCloudStatusPresentation {
    let accountStatus: CKAccountStatus?
    let accountError: String?
    let isCheckingAccount: Bool

    var title: String {
        if isCheckingAccount { return "Checking iCloud" }
        if accountError != nil { return "Could not check iCloud" }
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

    var subtitle: String {
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

    var icon: String {
        if isCheckingAccount { return "icloud" }
        if accountError != nil { return "exclamationmark.icloud" }
        guard accountStatus == .available else { return "icloud.slash" }
        return "checkmark.icloud"
    }

    var color: Color {
        if accountStatus == .available && accountError == nil { return Theme.green }
        if isCheckingAccount { return Theme.blue }
        if accountStatus == nil && accountError == nil { return Theme.dim }
        return Theme.amber
    }
}

struct iOSSyncSettingsSection: View {
    let accountStatus: CKAccountStatus?
    let accountError: String?
    let isCheckingAccount: Bool
    let lastChecked: Date?
    let refreshAccountStatus: () -> Void

    private var presentation: iOSCloudStatusPresentation {
        iOSCloudStatusPresentation(
            accountStatus: accountStatus,
            accountError: accountError,
            isCheckingAccount: isCheckingAccount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "iCloud")
            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: presentation.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(presentation.color)
                            .frame(width: 34, height: 34)
                            .background(presentation.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(presentation.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if isCheckingAccount {
                            ProgressView()
                                .tint(Theme.blue)
                        }
                    }

                    HStack {
                        Button(action: refreshAccountStatus) {
                            Label("Check iCloud Status", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blue)
                        .disabled(isCheckingAccount)

                        Spacer()

                        if let lastChecked {
                            Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
    }
}

struct iOSLocalDataSettingsSection: View {
    let activeTaskCount: Int
    let completedTaskCount: Int
    let inboxTaskCount: Int
    let activeContextCount: Int
    let activeAreaCount: Int
    let activeProjectCount: Int
    let noteCount: Int
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Local Data")
            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        iOSSettingsMetricTile(title: "Active tasks", value: "\(activeTaskCount)", icon: "checklist", color: Theme.blue)
                        iOSSettingsMetricTile(title: "Completed", value: "\(completedTaskCount)", icon: "checkmark.circle.fill", color: Theme.green)
                        iOSSettingsMetricTile(title: "Inbox", value: "\(inboxTaskCount)", icon: "tray.fill", color: Theme.blue)
                        iOSSettingsMetricTile(title: "Contexts", value: "\(activeContextCount)", icon: "square.stack.3d.up.fill", color: Theme.red)
                        iOSSettingsMetricTile(title: "Areas", value: "\(activeAreaCount)", icon: "folder.fill", color: Theme.green)
                        iOSSettingsMetricTile(title: "Projects", value: "\(activeProjectCount)", icon: "flag.fill", color: Theme.amber)
                        iOSSettingsMetricTile(title: "Notes", value: "\(noteCount)", icon: "doc.text.fill", color: Theme.purple)
                    }

                    #if DEBUG
                    Divider().background(Theme.borderSubtle)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                                .frame(width: 30, height: 30)
                                .background(Theme.amber.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Simulator Samples")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("Adds Today, Inbox, and timed tasks for UI review.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                            }

                            Spacer(minLength: 0)

                            Button(action: seedSampleData) {
                                Label("Seed Tasks", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.blue)
                        }

                        if let sampleDataStatus {
                            Text(sampleDataStatus)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    #endif
                }
            }
        }
    }
}

struct iOSMobileCoverageSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Mobile Coverage")
            CadenceSettingsCard {
                VStack(spacing: 0) {
                    ForEach(iOSMobileCapability.readyCapabilities, id: \.self) { title in
                        iOSSettingsCapabilityRow(title: title, isReady: true)
                        if title != iOSMobileCapability.readyCapabilities.last {
                            Divider().background(Theme.borderSubtle)
                        }
                    }
                }
            }
        }
    }
}

struct iOSAboutSettingsSection: View {
    let appVersion: String
    let buildNumber: String
    let bundleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Build")
            CadenceSettingsCard {
                VStack(spacing: 0) {
                    iOSSettingsInfoRow(title: "Version", value: appVersion)
                    Divider().background(Theme.borderSubtle)
                    iOSSettingsInfoRow(title: "Build", value: buildNumber)
                    Divider().background(Theme.borderSubtle)
                    iOSSettingsInfoRow(title: "Bundle ID", value: bundleID)
                }
            }
        }
    }
}
#endif

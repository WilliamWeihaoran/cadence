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

struct iOSNavigationSettingsSection: View {
    @Binding var todayLayoutMode: iPadTodayLayoutMode
    @Binding var calendarViewMode: CadenceCalendarViewMode
    @Binding var calendarPresentation: CadenceCalendarPresentation
    @Binding var calendarZoomLevel: Int
    @Binding var notesEditorMode: iOSMarkdownEditorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Defaults")
            CadenceSettingsCard {
                VStack(spacing: 0) {
                    iOSSettingsControlRow(
                        title: "iPad Today",
                        subtitle: "Focus keeps two panes. Mac shows notes, tasks, and timeline on wide iPads.",
                        icon: todayLayoutMode.systemImage,
                        color: Theme.green
                    ) {
                        Picker("iPad Today", selection: $todayLayoutMode) {
                            ForEach(iPadTodayLayoutMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().background(Theme.borderSubtle)

                    iOSSettingsControlRow(
                        title: "Calendar View",
                        subtitle: "Choose the first calendar range shown on mobile.",
                        icon: "calendar",
                        color: Theme.purple
                    ) {
                        Picker("Calendar View", selection: $calendarViewMode) {
                            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().background(Theme.borderSubtle)

                    iOSSettingsControlRow(
                        title: "Calendar Style",
                        subtitle: "Timeline mirrors the Mac schedule; Board gives the iPad planning canvas.",
                        icon: calendarPresentation == .timeline ? "timeline.selection" : "square.grid.2x2",
                        color: Theme.blue
                    ) {
                        Picker("Calendar Style", selection: $calendarPresentation) {
                            ForEach(CadenceCalendarPresentation.allCases, id: \.self) { presentation in
                                Text(presentation.rawValue).tag(presentation)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().background(Theme.borderSubtle)

                    iOSSettingsControlRow(
                        title: "Timeline Density",
                        subtitle: "Adjust the vertical spacing of timed blocks.",
                        icon: "arrow.up.and.down",
                        color: Theme.amber
                    ) {
                        Stepper(value: $calendarZoomLevel, in: 1...3) {
                            Text(zoomLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .monospacedDigit()
                        }
                    }

                    Divider().background(Theme.borderSubtle)

                    iOSSettingsControlRow(
                        title: "Notes Editor",
                        subtitle: "Choose whether notes open with live rendering, raw markdown, or rendered preview.",
                        icon: notesEditorMode.systemImage,
                        color: Theme.purple
                    ) {
                        Picker("Notes Editor", selection: $notesEditorMode) {
                            ForEach(iOSMarkdownEditorMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
    }

    private var zoomLabel: String {
        switch calendarZoomLevel {
        case 1: return "Compact"
        case 2: return "Comfort"
        default: return "Spacious"
        }
    }
}

private struct iOSSettingsControlRow<Control: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            control()
        }
        .padding(.vertical, 12)
    }
}

struct iOSMobileCoverageSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Mobile Coverage")
            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        iOSSettingsMetricTile(
                            title: "Ready",
                            value: "\(iOSMobileCapability.count(for: .ready))",
                            icon: iOSMobileCapabilityStatus.ready.systemImage,
                            color: iOSMobileCapabilityStatus.ready.color
                        )
                        iOSSettingsMetricTile(
                            title: "Partial",
                            value: "\(iOSMobileCapability.count(for: .partial))",
                            icon: iOSMobileCapabilityStatus.partial.systemImage,
                            color: iOSMobileCapabilityStatus.partial.color
                        )
                        iOSSettingsMetricTile(
                            title: "Later",
                            value: "\(iOSMobileCapability.count(for: .later))",
                            icon: iOSMobileCapabilityStatus.later.systemImage,
                            color: iOSMobileCapabilityStatus.later.color
                        )
                    }

                    ForEach(iOSMobileCapabilityStatus.allCases) { status in
                        let items = iOSMobileCapability.items(for: status)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 7) {
                                    Image(systemName: status.systemImage)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(status.color)
                                    Text(status.title)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.dim)
                                        .textCase(.uppercase)
                                        .tracking(0.7)
                                    Spacer(minLength: 0)
                                }
                                .padding(.bottom, 7)

                                VStack(spacing: 0) {
                                    ForEach(items) { capability in
                                        iOSSettingsCapabilityRow(capability: capability)
                                        if capability.id != items.last?.id {
                                            Divider().background(Theme.borderSubtle)
                                        }
                                    }
                                }
                                .background(Theme.surfaceElevated.opacity(0.34))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
                                }
                            }
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

            CadenceSettingsSectionLabel(text: "Review Links")
            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(width: 32, height: 32)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy and Support")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Use these during TestFlight and App Review checks.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            reviewLinkButtons
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            reviewLinkButtons
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reviewLinkButtons: some View {
        iOSReviewLinkButton(
            title: "Privacy Policy",
            icon: "lock.shield.fill",
            url: AppStoreReviewReadiness.privacyPolicyURL,
            missingMessage: AppStoreReviewReadiness.privacyPolicyMissingMessage
        )
        iOSReviewLinkButton(
            title: "Support",
            icon: "questionmark.circle.fill",
            url: AppStoreReviewReadiness.supportURL,
            missingMessage: AppStoreReviewReadiness.supportURLMissingMessage
        )
    }
}

private struct iOSReviewLinkButton: View {
    let title: String
    let icon: String
    let url: URL?
    let missingMessage: String

    var body: some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .padding(.horizontal, 10)
                    .background(Theme.blue.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.blue.opacity(0.24), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(missingMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
#endif

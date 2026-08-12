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
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        iOSIconTile(
                            systemImage: presentation.icon,
                            color: presentation.color,
                            size: 34,
                            iconSize: 17
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(presentation.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if isCheckingAccount {
                            ProgressView()
                                .tint(Theme.blue)
                        }
                    }

                    HStack {
                        iOSActionButton(
                            title: "Check iCloud Status",
                            systemImage: "arrow.clockwise",
                            role: .primary,
                            size: .compact,
                            isDisabled: isCheckingAccount,
                            action: refreshAccountStatus
                        )

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
            iOSSettingsCard {
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
                    iOSRowDivider()

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                            iOSIconTile(
                                systemImage: "wand.and.stars",
                                color: Theme.amber,
                                size: iOSSettingsMetrics.glyphSlot,
                                iconSize: 14
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Simulator Samples")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("Adds Today, Inbox, and timed tasks for UI review.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subdued)
                            }

                            Spacer(minLength: 0)

                            iOSActionButton(
                                title: "Seed Tasks",
                                systemImage: "plus",
                                role: .primary,
                                size: .compact,
                                action: seedSampleData
                            )
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
            iOSSettingsCard {
                VStack(spacing: 0) {
                    iOSSettingsControlRow(
                        title: "iPad Today",
                        subtitle: "Focus keeps two panes. Mac shows notes, tasks, and timeline on wide iPads.",
                        icon: todayLayoutMode.systemImage,
                        color: Theme.green
                    ) {
                        iOSSegmentedChoice(
                            options: iPadTodayLayoutMode.allCases.map { ($0, $0.title) },
                            selection: $todayLayoutMode
                        )
                    }

                    iOSRowDivider()

                    iOSSettingsControlRow(
                        title: "Calendar View",
                        subtitle: "Choose the first calendar range shown on mobile.",
                        icon: "calendar",
                        color: Theme.purple
                    ) {
                        iOSSegmentedChoice(
                            options: CadenceCalendarViewMode.pickerCases.map { ($0, $0.rawValue) },
                            selection: $calendarViewMode
                        )
                    }

                    iOSRowDivider()

                    iOSSettingsControlRow(
                        title: "Calendar Style",
                        subtitle: "Timeline mirrors the Mac schedule; Board gives the iPad planning canvas.",
                        icon: calendarPresentation == .timeline ? "timeline.selection" : "square.grid.2x2",
                        color: Theme.blue
                    ) {
                        iOSSegmentedChoice(
                            options: CadenceCalendarPresentation.allCases.map { ($0, $0.rawValue) },
                            selection: $calendarPresentation
                        )
                    }

                    iOSRowDivider()

                    iOSSettingsControlRow(
                        title: "Timeline Density",
                        subtitle: "Adjust the vertical spacing of timed blocks.",
                        icon: "arrow.up.and.down",
                        color: Theme.amber
                    ) {
                        iOSSegmentedChoice(
                            options: [(1, "Compact"), (2, "Comfort"), (3, "Spacious")],
                            selection: $calendarZoomLevel
                        )
                    }

                    iOSRowDivider()

                    iOSSettingsControlRow(
                        title: "Notes Editor",
                        subtitle: "Choose whether notes open with live rendering, raw markdown, or rendered preview.",
                        icon: notesEditorMode.systemImage,
                        color: Theme.purple
                    ) {
                        iOSSegmentedChoice(
                            options: iOSMarkdownEditorMode.allCases.map { ($0, $0.rawValue) },
                            selection: $notesEditorMode
                        )
                    }
                }
            }
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
            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                iOSIconTile(
                    systemImage: icon,
                    color: color,
                    size: iOSSettingsMetrics.glyphSlot,
                    iconSize: 14
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.subdued)
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
            iOSSettingsCard {
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
                                    SectionEyebrowLabel(text: status.title)
                                    Spacer(minLength: 0)
                                }
                                .padding(.bottom, 7)

                                VStack(spacing: 0) {
                                    ForEach(items) { capability in
                                        iOSSettingsCapabilityRow(capability: capability)
                                        if capability.id != items.last?.id {
                                            iOSRowDivider()
                                        }
                                    }
                                }
                                .background(Theme.surfaceElevated.opacity(0.34))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
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
            iOSSettingsCard {
                VStack(spacing: 0) {
                    iOSSettingsInfoRow(title: "Version", value: appVersion)
                    iOSRowDivider()
                    iOSSettingsInfoRow(title: "Build", value: buildNumber)
                    iOSRowDivider()
                    iOSSettingsInfoRow(title: "Bundle ID", value: bundleID)
                }
            }

            CadenceSettingsSectionLabel(text: "Review Links")
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "hand.raised.fill",
                            color: Theme.blue,
                            size: iOSSettingsMetrics.glyphSlot,
                            iconSize: 15
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy and Support")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Use these during TestFlight and App Review checks.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
                    .padding(.horizontal, 12)
                    // One layer: the tinted fill alone, same as `.tinted` action buttons.
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.iosPressable)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(missingMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
    }
}
#endif

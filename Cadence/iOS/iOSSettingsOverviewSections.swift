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

/// The five app defaults, as value rows.
///
/// They were five stacked segmented controls, each under a coloured icon tile and a two-line
/// paragraph: about 150pt per setting, so a phone showed two of the twelve settings in the app.
/// This is the vocabulary the task inspector already uses — quiet label on the left, the current
/// value with a chevron on the right, a checkmarked popover behind it — so the two surfaces agree
/// and all five fit on one screen.
///
/// The paragraphs did not survive the move. Three of them ("Choose the first calendar range shown
/// on mobile" under a row labelled *Calendar view*) said nothing the label did not; the two that
/// carried real information now sit on the options they describe, inside the picker, where you
/// read them at the moment you are choosing.
struct iOSNavigationSettingsSection: View {
    @Binding var todayLayoutMode: iPadTodayLayoutMode
    @Binding var calendarViewMode: CadenceCalendarViewMode
    @Binding var calendarPresentation: CadenceCalendarPresentation
    @Binding var calendarZoomLevel: Int
    @State private var openPicker: DefaultsPicker?

    private enum DefaultsPicker: String, Identifiable {
        case todayLayout
        case calendarView
        case calendarStyle
        case timelineDensity

        var id: String { rawValue }
    }

    private static let densityLabels: [(value: Int, title: String)] = [
        (1, "Compact"),
        (2, "Comfort"),
        (3, "Spacious")
    ]

    var body: some View {
        iOSEditorSection(title: "Defaults") {
            todayLayoutRow
            iOSEditorDivider()
            calendarViewRow
            iOSEditorDivider()
            calendarStyleRow
            iOSEditorDivider()
            timelineDensityRow
        }
    }

    private var todayLayoutRow: some View {
        iOSEditorFieldRow(label: "iPad Today", systemImage: "sidebar.squares.left") {
            valueButton(todayLayoutMode.title, picker: .todayLayout)
                .popover(isPresented: isPresented(.todayLayout)) {
                    iOSChoicePopoverList(
                        // `iPadTodayLayoutMode` already carries the one-line explanation of each
                        // layout; it just had nowhere to be shown.
                        rows: iPadTodayLayoutMode.allCases.map { mode in
                            iOSChoiceRow(
                                value: mode,
                                title: mode.title,
                                subtitle: mode.subtitle,
                                systemImage: mode.systemImage,
                                color: Theme.green
                            )
                        },
                        selection: $todayLayoutMode,
                        isPresented: isPresented(.todayLayout),
                        width: 280
                    )
                }
        }
    }

    private var calendarViewRow: some View {
        iOSEditorFieldRow(label: "Calendar view", systemImage: "calendar") {
            valueButton(calendarViewMode.rawValue, picker: .calendarView)
                .popover(isPresented: isPresented(.calendarView)) {
                    iOSChoicePopoverList(
                        rows: CadenceCalendarViewMode.pickerCases.map { mode in
                            iOSChoiceRow(
                                value: mode,
                                title: mode.rawValue,
                                systemImage: "calendar",
                                color: Theme.purple
                            )
                        },
                        selection: $calendarViewMode,
                        isPresented: isPresented(.calendarView)
                    )
                }
        }
    }

    private var calendarStyleRow: some View {
        iOSEditorFieldRow(label: "Calendar style", systemImage: "square.grid.2x2") {
            valueButton(calendarPresentation.rawValue, picker: .calendarStyle)
                .popover(isPresented: isPresented(.calendarStyle)) {
                    iOSChoicePopoverList(
                        rows: [
                            iOSChoiceRow(
                                value: CadenceCalendarPresentation.timeline,
                                title: CadenceCalendarPresentation.timeline.rawValue,
                                subtitle: "Hour-by-hour, the way the Mac schedule reads.",
                                systemImage: "timeline.selection",
                                color: Theme.blue
                            ),
                            iOSChoiceRow(
                                value: CadenceCalendarPresentation.board,
                                title: CadenceCalendarPresentation.board.rawValue,
                                subtitle: "Columns per day, with overdue and unscheduled rails.",
                                systemImage: "square.grid.2x2",
                                color: Theme.blue
                            )
                        ],
                        selection: $calendarPresentation,
                        isPresented: isPresented(.calendarStyle),
                        width: 280
                    )
                }
        }
    }

    private var timelineDensityRow: some View {
        iOSEditorFieldRow(label: "Timeline density", systemImage: "arrow.up.and.down") {
            valueButton(densityTitle, picker: .timelineDensity)
                .popover(isPresented: isPresented(.timelineDensity)) {
                    iOSChoicePopoverList(
                        rows: Self.densityLabels.map { option in
                            iOSChoiceRow(
                                value: option.value,
                                title: option.title,
                                systemImage: "arrow.up.and.down",
                                color: Theme.amber
                            )
                        },
                        selection: $calendarZoomLevel,
                        isPresented: isPresented(.timelineDensity)
                    )
                }
        }
    }

    private var densityTitle: String {
        Self.densityLabels.first { $0.value == calendarZoomLevel }?.title ?? Self.densityLabels[0].title
    }

    /// The value half of a row. `minHeight` hands the row's own 44pt to the button, because here
    /// the button is the only thing in the row there is to tap.
    private func valueButton(_ title: String, picker: DefaultsPicker) -> some View {
        iOSChoiceValueButton(
            title: title,
            minHeight: iOSSettingsMetrics.minimumTapTarget
        ) {
            openPicker = picker
        }
    }

    private func isPresented(_ picker: DefaultsPicker) -> Binding<Bool> {
        Binding(
            get: { openPicker == picker },
            set: { openPicker = $0 ? picker : nil }
        )
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

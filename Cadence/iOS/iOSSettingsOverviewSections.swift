#if os(iOS)
import SwiftUI

struct iOSSyncSettingsSection: View {
    /// The account check itself, shared with macOS's `SettingsSyncSection`. This used to be four
    /// `@State` properties in `iOSSettingsView` handed down as four `let`s, which is the copy
    /// macOS would have had to make to gain a sync surface at all — see `CadenceCloudAccountProbe`.
    let probe: CadenceCloudAccountProbe

    /// The shared answer, not a second opinion.
    ///
    /// This row used to read `CKAccountStatus` alone, which meant a device whose store had dropped
    /// to a local recovery container showed a green `checkmark.icloud` and "CloudKit should be able
    /// to sync Cadence data" while nothing was syncing at all. `CadenceSyncHealth` folds the store's
    /// own state in and lets it win — an available account is necessary for sync, not sufficient.
    private var health: CadenceSyncHealth {
        CadenceSyncHealth.resolve(
            startupIssue: PersistenceController.startupIssue,
            account: probe.state
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "iCloud")
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        iOSIconTile(
                            systemImage: health.iconName,
                            color: health.tone.tint,
                            size: 34,
                            iconSize: 17
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(health.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(health.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if probe.isChecking {
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
                            isDisabled: probe.isChecking,
                            action: probe.refresh
                        )

                        Spacer()

                        if let lastChecked = probe.lastChecked {
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

/// The app defaults, as value rows.
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
    @Binding var calendarViewMode: CadenceCalendarViewMode
    @Binding var calendarPresentation: CadenceCalendarPresentation
    @Binding var calendarZoomLevel: Int
    @State private var openPicker: DefaultsPicker?

    private enum DefaultsPicker: String, Identifiable {
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
            calendarViewRow
            iOSEditorDivider()
            calendarStyleRow
            iOSEditorDivider()
            timelineDensityRow
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

struct iOSAboutSettingsSection: View {
    let appVersion: String
    let buildNumber: String
    let bundleID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Build")
            iOSSettingsCard {
                VStack(spacing: 0) {
                    CadenceSettingsInfoRow(title: "Version", value: appVersion)
                    iOSRowDivider()
                    CadenceSettingsInfoRow(title: "Build", value: buildNumber)
                    iOSRowDivider()
                    CadenceSettingsInfoRow(title: "Bundle ID", value: bundleID)
                }
            }

            CadenceSettingsSectionLabel(text: CadenceAppReferenceLink.sectionTitle)
            iOSSettingsCard {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        linkButtons
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        linkButtons
                    }
                }
            }
        }
    }

    /// The pair comes from `CadenceAppReferenceLink.all`, which macOS's About screen reads too, so
    /// a third link — or a retitled one — is one edit rather than two.
    ///
    /// The glyph tile, the `Privacy and Support` heading and the App-Review-flavoured sentence that
    /// used to sit above these buttons are gone: the heading restated the two buttons under it,
    /// which is the page-header `subtitle` mistake one card down, and the sentence told a shipped
    /// user which internal checks the links were for.
    @ViewBuilder
    private var linkButtons: some View {
        ForEach(CadenceAppReferenceLink.all) { link in
            iOSReviewLinkButton(link: link)
        }
    }
}

/// One reference link, at iOS's 44pt tap target.
///
/// The chrome is the one deliberately per-platform half: macOS's About screen draws the same link
/// through `SettingsActionButton`, which is what every other button on those panes looks like.
private struct iOSReviewLinkButton: View {
    let link: CadenceAppReferenceLink

    var body: some View {
        if let url = link.url {
            Link(destination: url) {
                Label(link.title, systemImage: link.systemImage)
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
            // `#if DEBUG`, matching macOS: the message names work the developer has to do before
            // submitting, and a release build has no business showing it to a user. iOS was the
            // only unguarded one.
            #if DEBUG
            VStack(alignment: .leading, spacing: 4) {
                Label(link.title, systemImage: link.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(link.missingMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            #endif
        }
    }
}
#endif

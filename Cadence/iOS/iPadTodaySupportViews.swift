#if os(iOS)
import SwiftUI

struct iPadTodayTaskHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    let summary: CadenceTodaySummary
    @Binding var layoutMode: iPadTodayLayoutMode
    var allowsThreePane = true

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            iOSIconTile(
                systemImage: "sun.max.fill",
                color: Theme.amber,
                size: isRegularWidth ? 34 : 30,
                iconSize: isRegularWidth ? 15 : 13
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: isRegularWidth ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(title)
                        .font(.system(size: isRegularWidth ? 23 : 17, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    // The one badge on this screen carrying the active count, in the shape
                    // `iOSCompactPageHeader` uses for exactly this on the phone. It used to be
                    // followed on the same row by a two-chip mini summary repeating the first two
                    // of the three chips already sitting below the capture bar.
                    Text("\(summary.activeCount)")
                        .font(.system(size: isRegularWidth ? 12 : 11, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .monospacedDigit()
                        .padding(.horizontal, isRegularWidth ? 8 : 7)
                        .padding(.vertical, isRegularWidth ? 4 : 3)
                        .background(Theme.blue.opacity(0.11))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 10)

            iPadTodayLayoutPicker(
                selection: $layoutMode,
                allowsThreePane: allowsThreePane
            )
        }
        .padding(.horizontal, isRegularWidth ? 18 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
        .frame(height: iOSPanelHeaderHeight, alignment: .center)
        .background(Theme.surface)
    }
}

/// The inspector pane's only chrome row: which of the two panels it is showing, and nothing else.
///
/// It used to be a title reading `selection.title` beside this picker, above a pane whose own
/// header read `SCHEDULE / Timeline` — the word "Timeline" three times within 120pt, the first two
/// of them naming the panel already selected in the control on the same row. That is the Notes
/// header bug `775833d` fixed, and the fix is the same one: the panel keeps its identity, the
/// duplicates go. The hosted panels are passed `showsHeader: false` / `showsTitle: false`, so this
/// row is the pane's header rather than an extra one above it.
struct iPadTodayInspectorSwitcher: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(spacing: 12) {
            iOSSegmentedPillGroup {
                ForEach(iPadTodaySidePanel.allCases) { panel in
                    iOSSegmentedPill(
                        title: panel.title,
                        systemImage: panel.icon,
                        isSelected: selection == panel,
                        minWidth: 84
                    ) {
                        selection = panel
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }
}

enum iPadTodaySidePanel: String, CaseIterable, Identifiable {
    case notes
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .timeline: return "Timeline"
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .timeline: return "clock"
        }
    }
}

enum iPadTodayLayoutMode: String, CaseIterable, Identifiable {
    case focus
    case mac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .mac: return "Mac"
        }
    }

    /// Read by Settings → Navigation's picker rows, which have room for the explanation. The
    /// header's own segments do not show it — there the two options sit side by side and the
    /// glyphs already draw the difference.
    var subtitle: String {
        switch self {
        case .focus: return "Tasks plus one inspector"
        case .mac: return "Notes, tasks, and timeline"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "rectangle.split.2x1"
        case .mac: return "rectangle.split.3x1"
        }
    }
}

/// The counts the header badge does not already carry, as one `Theme.dim` line.
///
/// This was `iPadTodaySummaryStrip`: three tinted capsules — blue "Active", purple "Timed", green
/// "Done" — permanently on screen, so an unplanned day spent a full band saying "0" three times in
/// three hues. Absent entirely when there is nothing to say; see `CadenceTodaySummary.line`.
struct iPadTodaySummaryLine: View {
    let summary: CadenceTodaySummary

    var body: some View {
        if let line = summary.line {
            Text(line)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
    }
}

private struct iPadTodayLayoutPicker: View {
    @Binding var selection: iPadTodayLayoutMode
    /// False when the pane is narrower than `CadenceTodayLayoutSupport.threePaneMinimumWidth`.
    /// Three columns genuinely do not fit there, so Mac reads as unavailable instead of accepting
    /// a tap and leaving the screen exactly as it was.
    var allowsThreePane = true

    private func isAvailable(_ mode: iPadTodayLayoutMode) -> Bool {
        mode != .mac || allowsThreePane
    }

    /// `iOSSegmentedPillGroup`, the control the Tasks tab uses for Today / All / Inbox and the
    /// Calendar tab for Week / Month / Board — not a third hand-rolled segmented control with its
    /// own heights, radii and disabled treatment, which is what this was.
    var body: some View {
        iOSSegmentedPillGroup {
            ForEach(iPadTodayLayoutMode.allCases) { mode in
                let available = isAvailable(mode)
                iOSSegmentedPill(
                    title: mode.title,
                    systemImage: mode.systemImage,
                    isSelected: selection == mode,
                    minWidth: 74,
                    isEnabled: available,
                    accessibilityHint: available ? nil : "Needs a wider window"
                ) {
                    selection = mode
                }
            }
        }
    }
}

#endif

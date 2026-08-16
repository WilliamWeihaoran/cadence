#if os(iOS)
import SwiftUI

/// Today's page header — and, since the layout picker left it, Today's *only* chrome row.
///
/// Two things moved onto this row rather than keeping a band each below it:
/// - **The sort / completed controls.** `iOSTaskViewOptionsBar` sat in a 13pt-padded deck of its
///   own directly underneath, which cost ~70pt of the task column to hold two chips that fit in
///   the space the picker vacated. It is the same shared bar the Inbox and All Tasks use, hosted
///   with `spreads: false` so its internal `Spacer` does not fight this row's.
/// - **The day's summary**, into the eyebrow beside the date. Left where it was it would have been
///   a padded band holding one dim sentence — the exact "row existing to hold one thing" shape the
///   Notes header fix deleted — and a *conditional* one at that (`CadenceTodaySummary.line` is nil
///   on an unplanned day), so the band would appear and vanish under the header as the day filled.
///   The date and the summary are both already `Theme.dim`; side by side they read as one quiet
///   line, with the date keeping its uppercase/kerned treatment and the summary in sentence case
///   so the two halves stay distinguishable.
struct iPadTodayTaskHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    let summary: CadenceTodaySummary
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var eyebrowFontSize: CGFloat {
        isRegularWidth ? 10 : 9
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
                eyebrowLine

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

            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: summary.completedCount,
                spreads: false
            )
            // Sized before the text column, so a narrow task column truncates the date rather than
            // squeezing two 44pt controls. Priority, not `.fixedSize()`: at the very bottom of the
            // width range the chips still give ground instead of overflowing the header and being
            // clipped, which is how the capture field once ended up reading "l a task for today…".
            .layoutPriority(1)
        }
        .padding(.horizontal, isRegularWidth ? 18 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
        .frame(height: iOSPanelHeaderHeight, alignment: .center)
        .background(Theme.surface)
    }

    /// Date, then the day's counts. The summary is the half that gives way: it is `lineLimit(1)`
    /// with no layout priority against a date that has one, so a squeezed header truncates
    /// "· 3 timed" before it touches "SUNDAY, AUGUST 17".
    private var eyebrowLine: some View {
        HStack(spacing: 6) {
            Text(eyebrow)
                .font(.system(size: eyebrowFontSize, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)
                .lineLimit(1)
                .layoutPriority(1)

            if let line = summary.line {
                Text("· \(line)")
                    .font(.system(size: eyebrowFontSize, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
    }
}

/// The inspector pane's only chrome row: which of the two panels it is showing, and nothing else.
///
/// It used to be a title reading `selection.title` beside this picker, above a pane whose own
/// header read `SCHEDULE / Timeline` — the word "Timeline" three times within 120pt, the first two
/// of them naming the panel already selected in the control on the same row. That is the Notes
/// header bug `775833d` fixed, and the fix is the same one: the panel keeps its identity, the
/// duplicates go. The hosted panels draw no title of their own here, so this row is the pane's
/// header rather than an extra one above it.
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

#endif

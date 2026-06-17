#if os(iOS)
import SwiftUI

struct iPadTodayTaskHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    let summary: CadenceTodaySummary
    @Binding var layoutMode: iPadTodayLayoutMode

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: isRegularWidth ? 15 : 13, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: isRegularWidth ? 34 : 30, height: isRegularWidth ? 34 : 30)
                .background(Theme.amber.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 9, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.20), lineWidth: 1)
                }

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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    iPadTodayHeaderMiniSummary(summary: summary)
                        .layoutPriority(1)

                    iPadTodayLayoutPicker(selection: $layoutMode, showsLabels: true)
                        .frame(width: 166)
                }

                iPadTodayLayoutPicker(selection: $layoutMode, showsLabels: false)
                    .frame(width: 82)
            }
        }
        .padding(.horizontal, isRegularWidth ? 18 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
        .frame(height: iOSPanelHeaderHeight, alignment: .center)
        .background(Theme.surface)
    }
}

struct iPadTodayEmptyReviewDeck: View {
    let timedCount: Int
    let completedCount: Int
    @Binding var selectedPanel: iPadTodaySidePanel
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    #if DEBUG
    init(
        timedCount: Int,
        completedCount: Int,
        selectedPanel: Binding<iPadTodaySidePanel>,
        sampleDataStatus: String? = nil,
        seedSampleData: @escaping () -> Void = {}
    ) {
        self.timedCount = timedCount
        self.completedCount = completedCount
        self._selectedPanel = selectedPanel
        self.sampleDataStatus = sampleDataStatus
        self.seedSampleData = seedSampleData
    }
    #else
    init(
        timedCount: Int,
        completedCount: Int,
        selectedPanel: Binding<iPadTodaySidePanel>
    ) {
        self.timedCount = timedCount
        self.completedCount = completedCount
        self._selectedPanel = selectedPanel
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            iPadTodayEmptyStateCard(
                sampleDataStatus: sampleDataStatus,
                seedSampleData: seedSampleData
            )
            #else
            iPadTodayEmptyStateCard()
            #endif

            HStack(spacing: 10) {
                Button {
                    selectedPanel = .notes
                } label: {
                    iPadTodayReviewTile(
                        title: "Write notes",
                        detail: "Capture the context for today before tasks fill in.",
                        value: selectedPanel == .notes ? "Open" : "Notes",
                        systemImage: "note.text",
                        tint: Theme.purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes panel")

                Button {
                    selectedPanel = .timeline
                } label: {
                    iPadTodayReviewTile(
                        title: "Check timeline",
                        detail: timedCount == 0 ? "Timed tasks will land in the inspector." : "\(timedCount) timed item\(timedCount == 1 ? "" : "s") today.",
                        value: "\(timedCount)",
                        systemImage: "clock",
                        tint: Theme.blue
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open timeline panel")

                iPadTodayReviewTile(
                    title: "Completed",
                    detail: completedCount == 0 ? "Finished tasks will stay available here." : "Review finished work when completed is shown.",
                    value: "\(completedCount)",
                    systemImage: "checkmark.circle.fill",
                    tint: Theme.green
                )
            }
        }
    }
}

struct iPadTodayInspectorSwitcher: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(selection.subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            iPadTodaySidePanelPicker(selection: $selection)
                .frame(width: 192)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
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

    var subtitle: String {
        switch self {
        case .notes: return "Today, week, and notepad"
        case .timeline: return "Timed tasks and schedule"
        }
    }

    var compactTitle: String {
        switch self {
        case .notes: return "Notes"
        case .timeline: return "Timeline"
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

struct iPadTodaySummaryStrip: View {
    let summary: CadenceTodaySummary

    var body: some View {
        HStack(spacing: 8) {
            ForEach(summary.metrics) { metric in
                iPadTodaySummaryChip(metric: metric)
            }
        }
    }
}

struct iPadTodayStarterHints: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                hintContent
            }

            VStack(spacing: 10) {
                hintContent
            }
        }
    }

    @ViewBuilder
    private var hintContent: some View {
        iPadTodayHint(
            title: "Capture",
            detail: "Quick-add a task and it lands on today.",
            systemImage: "plus"
        )
        iPadTodayHint(
            title: "Plan",
            detail: "Use the inspector to switch notes and timeline.",
            systemImage: "sidebar.right"
        )
    }
}

private struct iPadTodayReviewTile: View {
    let title: String
    let detail: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 6)

                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.26))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.4), lineWidth: 1)
        }
    }
}

private struct iPadTodayHeaderMiniSummary: View {
    let summary: CadenceTodaySummary

    var body: some View {
        HStack(spacing: 7) {
            ForEach(summary.metrics.prefix(2)) { metric in
                HStack(spacing: 5) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(metric.tint)

                    Text("\(metric.value)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.surfaceElevated.opacity(0.44))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.36), lineWidth: 1)
                }
            }
        }
    }
}

private struct iPadTodayLayoutPicker: View {
    @Binding var selection: iPadTodayLayoutMode
    var showsLabels = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(iPadTodayLayoutMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        if showsLabels {
                            Text(mode.title)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                    .foregroundStyle(selection == mode ? Theme.text : Theme.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(selection == mode ? Theme.blue.opacity(0.22) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) layout")
            }
        }
        .padding(3)
        .frame(maxWidth: showsLabels ? 166 : 82)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct iPadTodaySidePanelPicker: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(iPadTodaySidePanel.allCases) { panel in
                Button {
                    selection = panel
                } label: {
                    Label(panel.compactTitle, systemImage: panel.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == panel ? Theme.text : Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(selection == panel ? Color.white.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.title)
            }
        }
        .padding(3)
        .background(Theme.surfaceElevated.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct iPadTodaySummaryChip: View {
    let metric: CadenceTodaySummaryMetric

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(metric.tint)

            Text("\(metric.value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()

            Text(metric.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Theme.surfaceElevated.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.46), lineWidth: 1)
        }
    }
}

private struct iPadTodayEmptyStateCard: View {
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void

    init(sampleDataStatus: String? = nil, seedSampleData: @escaping () -> Void = {}) {
        self.sampleDataStatus = sampleDataStatus
        self.seedSampleData = seedSampleData
    }
    #else
    init() {}
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.blue.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(CadenceTodayPresentationSupport.emptyTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(CadenceTodayPresentationSupport.emptyReviewSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                #if DEBUG
                Button(action: seedSampleData) {
                    Label("Samples", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.blue.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.blue.opacity(0.24), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seed sample tasks")
                #endif
            }

            #if DEBUG
            if let sampleDataStatus {
                Text(sampleDataStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.leading, 50)
            }
            #endif
        }
        .padding(14)
        .background(Theme.surfaceElevated.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
        }
    }
}

private struct iPadTodayHint: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 24, height: 24)
                .background(Theme.surfaceElevated.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.38), lineWidth: 1)
        }
    }
}

#endif

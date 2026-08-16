#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactTodayView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    let todayTasks: [AppTask]
    let completedTodayTasks: [AppTask]
    let todayTaskGroups: [CadenceTodayTaskGroup]
    @Binding var showCompleted: Bool
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if showsHeader {
                    header
                }
                // Tasks and nothing else. The day's note card and the schedule preview used to sit
                // under this list; both are one tab away and better there — the Notes tab opens the
                // same daily note, and Calendar shows the same schedule at full height. Today's job
                // in the Tasks tab is the day's tasks.
                taskSections
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            // Breathing room at the end of the content, not bar clearance: the tab bar is a `VStack`
            // sibling of the tab content in `iOSCompactRootShell`, so this scroll view is handed a
            // height that already stops where the bar starts. This used to be 132 — hand-cut
            // clearance for a floating `+` — which is the shape of thing that goes wrong the moment
            // the bar's height changes.
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Drawn only when this is a *pushed* screen, where it is the page's only title and — with the
    /// navigation bar hidden on iPhone — the only row the back control has to live on. Inside the
    /// Tasks tab the tab's header does both jobs; see `showsHeader`.
    private var header: some View {
        iOSCompactPageHeader(
            eyebrow: DateFormatters.longDate.string(from: Date()),
            title: "Today",
            systemImage: "sun.max.fill",
            color: Theme.amber,
            count: todayTasks.count,
            onBack: { dismiss() }
        )
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    @ViewBuilder
    private var taskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            iOSCompactTodayEmptyState()
                .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)

            #if DEBUG
            iOSCompactSampleDataCard(
                status: sampleDataStatus,
                action: seedSampleData
            )
            #endif
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(todayTaskGroups, id: \.title) { group in
                    iOSCompactTodayTaskGroup(
                        group: group,
                        color: CadenceTodayPresentationSupport.accent(for: group.kind)
                    )
                }

                if showCompleted && !completedTodayTasks.isEmpty {
                    iOSCompactCompletedTasks(tasks: Array(completedTodayTasks.prefix(12)))
                }
            }
            .padding(12)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
        }
    }

}

/// The one Today empty state, on both widths.
///
/// iPad used to run its own: a card, then a row of three tinted "Write notes" / "Check timeline" /
/// "Completed" tiles, then two more "Capture" / "Plan" hint cards — five instructional cards
/// standing in for content, one of which ("Plan — Use the inspector to switch notes and timeline")
/// described the page it was drawn on. That is the mistake the deleted `iOSCompactHomeView` grid
/// made. An empty day looks empty and says so once, in `Theme.dim`.
struct iOSCompactTodayEmptyState: View {
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 42, height: 42)
                .background(Theme.surfaceElevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(CadenceTodayPresentationSupport.emptyCompactTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(CadenceTodayPresentationSupport.emptySubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// Debug-only, on both widths — the seeding affordance cannot ship. iPad had its own "Samples"
/// button welded into its empty-state card; it is this card now.
#if DEBUG
struct iOSCompactSampleDataCard: View {
    let status: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            iOSIconTile(systemImage: "wand.and.stars", color: Theme.amber, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(status ?? "Need realistic rows?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Text("Seed local simulator tasks for Today, Inbox, and Timeline.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 34, height: 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .accessibilityLabel("Seed sample tasks")
        }
        .padding(12)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
    }
}
#endif

private struct iOSCompactTodayTaskGroup: View {
    let group: CadenceTodayTaskGroup
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: group.title, color: color)
                Spacer()
                Text("\(group.tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(group.tasks) { task in
                    iOSTaskRow(task: task, density: .compact)
                }
            }
        }
    }
}

private struct iOSCompactCompletedTasks: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.green.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task, density: .compact)
                        .opacity(0.62)
                }
            }
        }
    }
}


#endif

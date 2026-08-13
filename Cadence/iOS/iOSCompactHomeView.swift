#if os(iOS)
import SwiftData
import SwiftUI

/// The iPhone landing screen.
///
/// It used to be a Settings-shaped menu: three titled sections of rows, each row an icon, a name
/// and a subtitle that restated the name ("Plan the current day" under "Today"). Eight
/// destinations, a full screen of scrolling, and not one fact about the user's actual day.
///
/// Now the screen answers "what does today look like" before it offers to navigate anywhere: a
/// greeting, a today card carrying real counts and the single next action, and a flat two-column
/// grid of destinations with a count only where a count means something. Everything computable is
/// in `CadenceHomeSummarySupport` (tested from `CadenceTests`); this file is composition.
struct iOSCompactHomeView: View {
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]

    @State private var selectedTask: AppTask?

    private var todayKey: String { DateFormatters.todayKey() }

    private var badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            todayKey: todayKey,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count,
            activeListCount: areas.filter(\.isActive).count + projects.filter(\.isActive).count
        )
    }

    private var habitProgress: CadenceHomeSummarySupport.HabitProgress? {
        CadenceHomeSummarySupport.habitProgress(for: habits)
    }

    private var todayStats: CadenceHomeSummarySupport.TodayStats {
        CadenceHomeSummarySupport.todayStats(from: allTasks, todayKey: todayKey)
    }

    private var nextAction: AppTask? {
        CadenceHomeSummarySupport.nextAction(
            from: allTasks,
            todayKey: todayKey,
            nowMinute: CadenceHomeSummarySupport.minuteOfDay(for: Date())
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // No icon and no subtitle: the eyebrow says which day it is and the title greets
                // you. A line under it explaining that this is the home screen would be the
                // subtitle rule's textbook case.
                iOSCompactPageHeader(
                    eyebrow: CadenceHomeSummarySupport.dateEyebrow(for: Date()),
                    title: CadenceHomeSummarySupport.greeting(for: Date())
                )

                iOSHomeTodayCard(
                    stats: todayStats,
                    nextAction: nextAction,
                    todayKey: todayKey,
                    onOpenNextAction: { selectedTask = $0 }
                )

                iOSHomeDestinationGrid(
                    badges: badgeSnapshot,
                    habitProgress: habitProgress
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $selectedTask) { task in
            iOSTaskDetailSheet(task: task)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: CadenceFeatureDestination.settings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.dim)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: CadenceFeatureDestination.search) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

// MARK: - Today card

/// One card, two tap targets: the counts open Today, the next action opens that task.
///
/// The card itself is the single selection layer at a single radius — neither half draws its own
/// background. Press feedback is `iOSPressableButtonStyle` with the scale turned off, because
/// shrinking one half of a card leaves the other half standing still.
private struct iOSHomeTodayCard: View {
    let stats: CadenceHomeSummarySupport.TodayStats
    let nextAction: AppTask?
    let todayKey: String
    let onOpenNextAction: (AppTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: CadenceFeatureDestination.today) {
                summaryRow
            }
            .buttonStyle(iOSPressableButtonStyle(pressedScale: 1))

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            nextActionSection
        }
        .cadenceCard()
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.dim)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }

            HStack(alignment: .top, spacing: 10) {
                iOSHomeTodayStat(value: stats.dueTodayCount, label: "Due", tint: Theme.blue)
                iOSHomeTodayStat(
                    value: stats.overdueCount,
                    label: "Overdue",
                    // Red only when there is something to be red about. A permanently red zero
                    // trains you to stop reading the number.
                    tint: stats.overdueCount > 0 ? Theme.red : Theme.dim
                )
                iOSHomeTodayStat(value: stats.completedCount, label: "Done", tint: Theme.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var nextActionSection: some View {
        if let nextAction {
            Button {
                onOpenNextAction(nextAction)
            } label: {
                iOSHomeNextActionRow(
                    task: nextAction,
                    detail: CadenceHomeSummarySupport.nextActionDetail(for: nextAction, todayKey: todayKey)
                )
            }
            .buttonStyle(iOSPressableButtonStyle(pressedScale: 1))
        } else {
            HStack(spacing: 10) {
                iOSIconTile(
                    systemImage: "checkmark.circle",
                    color: Theme.green,
                    size: 30,
                    iconSize: 14,
                    fillOpacity: 0.12,
                    bordered: false
                )

                Text(stats.completedCount > 0 ? "Nothing left today" : "Nothing planned today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52, alignment: .leading)
        }
    }
}

private struct iOSHomeTodayStat: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? tint : Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.subdued)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct iOSHomeNextActionRow: View {
    let task: AppTask
    let detail: CadenceHomeSummarySupport.NextActionDetail

    var body: some View {
        HStack(spacing: 10) {
            iOSIconTile(
                systemImage: "arrow.forward.circle.fill",
                color: Theme.blue,
                size: 30,
                iconSize: 14,
                fillOpacity: 0.12,
                bordered: false
            )

            Text(task.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            iOSMetaChip(
                label: detail.label,
                color: Theme.blue,
                systemImage: detail.systemImage
            )
            // A ceiling rather than a priority. Giving the title absolute priority let a long list
            // name shrink to a single character — a chip reading "[" is worse than no chip — and
            // giving the chip its intrinsic width let it eat the title it annotates. Capped, a
            // short detail ("9 AM") leaves the title nearly the whole row, and a long one takes a
            // predictable slice and truncates inside itself.
            .frame(maxWidth: 124, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Destination grid

/// One flat grid rather than the three titled sections the rows used to sit in. At two columns the
/// section headings cost a row of height each to group two or three cells you can already see in
/// one glance, and the ordering alone carries the same grouping.
private struct iOSHomeDestinationGrid: View {
    let badges: CadenceFeatureBadgeSupport.Snapshot
    let habitProgress: CadenceHomeSummarySupport.HabitProgress?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CadenceHomeSummarySupport.gridDestinations) { destination in
                NavigationLink(value: destination) {
                    iOSHomeDestinationCell(
                        destination: destination,
                        countLabel: CadenceHomeSummarySupport.gridCountLabel(
                            for: destination,
                            badges: badges,
                            habitProgress: habitProgress
                        )
                    )
                }
                .buttonStyle(.iosPressable)
            }
        }
    }
}

private struct iOSHomeDestinationCell: View {
    let destination: CadenceFeatureDestination
    let countLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                iOSIconTile(systemImage: destination.systemImage, color: destination.tint)

                Spacer(minLength: 0)

                if let countLabel {
                    Text(countLabel)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(destination.tint)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(destination.tint.opacity(0.13))
                        .clipShape(Capsule())
                }
            }

            Text(destination.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .contentShape(Rectangle())
        .cadenceCard()
    }
}
#endif

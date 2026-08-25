import SwiftUI

// Habit detail chrome shared by macOS and iOS.
//
// These all used to live in `macOS/Views/HabitsSupportViews.swift`, which is `#if os(macOS)` —
// which is why the iOS habit detail had no activity grid and no card treatment to hang one on.
// They carry no AppKit or hover assumptions, so they are shared rather than copied.

/// The habit's own colour and glyph as a rounded tile. `CommitmentIconTile` (macOS) and
/// `iOSIconTile` (iOS) are the two platform tiles; this picks the right one so a habit reads the
/// same on both.
struct HabitIconTile: View {
    let habit: Habit
    var size: CGFloat
    var iconSize: CGFloat

    var body: some View {
        #if os(macOS)
        CommitmentIconTile(
            systemImage: habit.icon,
            color: Color(hex: habit.colorHex),
            size: size,
            iconSize: iconSize,
            fillOpacity: 0.16
        )
        #else
        iOSIconTile(
            systemImage: habit.icon,
            color: Color(hex: habit.colorHex),
            size: size,
            iconSize: iconSize,
            fillOpacity: 0.16
        )
        #endif
    }
}

/// Titled card wrapper for a section of the habit detail (Goal, Activity, …), so the two habit
/// details agree on the eyebrow treatment and on the card's radius and elevation.
struct HabitInfoCard<Content: View>: View {
    let title: String
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrowLabel(text: title)
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}

// MARK: - Habit Heatmap

/// 52 weeks of check-ins, one column per week, most recent week last.
///
/// The range is deliberately fixed at a year: the grid is the only place a habit's long arc is
/// legible, so it is information-bearing rather than decorative. On a narrow surface the caller
/// wraps it in a horizontal `ScrollView` (anchored trailing) instead of shortening it.
struct HabitHeatmap: View {
    let habit: Habit

    /// Cell geometry is a parameter so a compact surface can tighten the grid without forking
    /// the view; both platforms currently render at the same size.
    var cellSize: CGFloat = 12
    var gap: CGFloat = 2
    var weeks = 52

    private var completionDates: Set<String> {
        Set((habit.completions ?? []).map { $0.date })
    }

    /// The heatmap's date math, pulled out of the view so it can be asserted on.
    ///
    /// The grid used to anchor on `today - weeks * 7` and then round *backwards* to the start of
    /// that week, so its last cell landed between one and seven days before today — today's own
    /// check-in never appeared, on any day of the week. (`isFuture` in the body was consequently
    /// unreachable, which is the clearest evidence the grid was meant to run through today.)
    /// Anchoring on the week containing today and counting back puts the current week in the
    /// final column, where a heatmap's most recent week belongs.
    ///
    /// The column boundary is the **habit week** — fixed Monday-start, via
    /// `Habit.isoWeekCalendar` — not `calendar.firstWeekday`. Every weekly *computation* in the
    /// app already goes through that calendar (`weeklyStreak`, `GoalHabitMomentumResolver`,
    /// `isDue` for `.timesPerWeek`), so a Sunday-start grid drew a 3x/week habit checked
    /// Sun/Mon/Tue as one full-looking column while the scoring counted that week 2/3.
    enum HabitHeatmapGrid {
        struct Cell {
            let date: Date
            let key: String
        }

        /// One label per calendar month, at the first column whose week begins in that month.
        struct MonthLabel: Identifiable {
            let label: String
            let weekCol: Int

            var id: Int { weekCol }
        }

        static func startDate(weeks: Int, today: Date, calendar: Calendar) -> Date {
            let weekCalendar = Habit.isoWeekCalendar(inheritingTimeZoneFrom: calendar)
            let startOfToday = weekCalendar.startOfDay(for: today)
            let startOfThisWeek = weekCalendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start ?? startOfToday
            return weekCalendar.date(byAdding: .day, value: -(max(1, weeks) - 1) * 7, to: startOfThisWeek) ?? startOfThisWeek
        }

        /// Every cell the grid draws, in render order. **The view body iterates this**, rather
        /// than re-deriving the same sequence inline — when it did, this type had no production
        /// caller at all and the tests over it proved nothing about what was on screen.
        static func cells(weeks: Int, today: Date, calendar: Calendar) -> [Cell] {
            let weekCalendar = Habit.isoWeekCalendar(inheritingTimeZoneFrom: calendar)
            let start = startDate(weeks: weeks, today: today, calendar: calendar)
            return (0..<(max(1, weeks) * 7)).compactMap { offset in
                guard let raw = weekCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let day = weekCalendar.startOfDay(for: raw)
                return Cell(date: day, key: DateFormatters.dateKey(from: day, calendar: weekCalendar))
            }
        }

        /// The month ruler above the grid. **The view body iterates this too**, for the same
        /// reason `cells` exists.
        ///
        /// Dedup is on year *and* month. Keyed on the month number alone — over a 364-day grid,
        /// whose first and last columns are almost always the same month — the current month was
        /// emitted once for the column a year ago and then suppressed for every column at the
        /// right edge, so the last label a reader saw was the month *before* this one and
        /// counting back from it to date a cell landed a month out.
        static func monthLabels(weeks: Int, today: Date, calendar: Calendar) -> [MonthLabel] {
            let weekCalendar = Habit.isoWeekCalendar(inheritingTimeZoneFrom: calendar)
            let start = startDate(weeks: weeks, today: today, calendar: calendar)
            var seen = Set<DateComponents>()
            var result: [MonthLabel] = []

            for weekIdx in 0..<max(1, weeks) {
                guard let weekStart = weekCalendar.date(byAdding: .day, value: weekIdx * 7, to: start) else { continue }
                let key = weekCalendar.dateComponents([.year, .month], from: weekStart)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(MonthLabel(label: DateFormatters.monthAbbrev.string(from: weekStart), weekCol: weekIdx))
            }
            return result
        }
    }

    private var cal: Calendar { Calendar.current }

    private var months: [HabitHeatmapGrid.MonthLabel] {
        HabitHeatmapGrid.monthLabels(weeks: weeks, today: Date(), calendar: cal)
    }

    /// Not on `Theme`'s radius scale on purpose: that scale sizes card-like *surfaces*, and a
    /// 12pt cell is a data mark. Derived from the cell so the grid keeps its proportions if a
    /// caller tightens it.
    private var cellCornerRadius: CGFloat { max(2, cellSize * 0.25) }

    var body: some View {
        let cells = HabitHeatmapGrid.cells(weeks: weeks, today: Date(), calendar: cal)
        let now = Date()
        let todayKey = DateFormatters.dateKey(from: now, calendar: cal)

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 16)
                ForEach(months) { m in
                    Text(m.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.subdued)
                        .offset(x: CGFloat(m.weekCol) * (cellSize + gap))
                }
            }

            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { weekIdx in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { dayOfWeek in
                            let index = weekIdx * 7 + dayOfWeek
                            let cell: HabitHeatmapGrid.Cell? = index < cells.count ? cells[index] : nil
                            let isDone = cell.map { completionDates.contains($0.key) } ?? false
                            // Live now that the grid runs through the end of the current week:
                            // the days after today in that final column are drawn empty.
                            let isFuture = cell.map { $0.date > now } ?? true
                            let isToday = cell?.key == todayKey

                            RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                .fill(isFuture ? Color.clear : (isDone ? Color(hex: habit.colorHex) : Theme.borderSubtle))
                                .frame(width: cellSize, height: cellSize)
                                .overlay {
                                    // Today needs to be findable, otherwise a year of identical
                                    // squares gives the reader no anchor to count back from.
                                    if isToday {
                                        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                            .strokeBorder(isDone ? Theme.onColorBorderStrong : Theme.borderStrong, lineWidth: 1)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Last 7 days

/// The habit's last seven days as a run of bars, oldest first, today last.
///
/// Reads `Habit.last7DayStates`, which is where the day walk and its DST handling live — the view
/// does no date arithmetic beyond naming the weekday under each bar, and the walk it labels is the
/// same one it fills. `last7DayStates` returns exactly seven states, so the labels cannot slip out
/// of step with the bars.
///
/// Shared because it is not a platform decision: macOS's habit detail showed a year-long heatmap
/// and no recent week at all, which is the one range you actually check a habit against.
struct HabitLast7DayStrip: View {
    let habit: Habit
    /// Bar geometry is a parameter so a narrower surface can tighten the strip rather than fork it.
    var barHeight: CGFloat = 26
    var spacing: CGFloat = 8

    private var tint: Color { Color(hex: habit.colorHex) }

    var body: some View {
        let states = habit.last7DayStates

        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.subdued)

            HStack(spacing: spacing) {
                ForEach(Array(states.enumerated()), id: \.offset) { index, done in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: Theme.radiusControl - 2, style: .continuous)
                            .fill(done ? tint : Theme.borderSubtle)
                            .frame(height: barHeight)
                        Text(Self.dayLabel(offset: states.count - 1 - index))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.subdued)
                    }
                }
            }
        }
    }

    /// `offset` days back from today, as `EEE`. Same direction as `last7DayStates`' own walk.
    private static func dayLabel(offset: Int, asOf referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) ?? referenceDate
        return DateFormatters.dayOfWeek.string(from: date)
    }
}

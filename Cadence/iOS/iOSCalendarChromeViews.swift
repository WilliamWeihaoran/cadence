#if os(iOS)
import SwiftUI

struct iOSCalendarLeadItem: Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    static func == (lhs: iOSCalendarLeadItem, rhs: iOSCalendarLeadItem) -> Bool {
        lhs.title == rhs.title &&
        lhs.detail == rhs.detail &&
        lhs.systemImage == rhs.systemImage
    }
}

struct iOSCalendarContextStrip: View {
    let selectedDate: Date
    let presentationLabel: String
    let totalCount: Int
    let timedCount: Int
    let taskCount: Int
    let eventCount: Int
    let bundleCount: Int
    let leadItem: iOSCalendarLeadItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                compactStrip
            } else {
                regularStrip
            }
        }
        .background(Theme.bg.opacity(0.84))
    }

    private var regularStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                selectedDayCard
                    .frame(width: 198)

                metricsRow

                leadItemCard
                    .frame(width: 232)
            }

            HStack(spacing: 10) {
                selectedDayCard
                    .frame(width: 190)

                metricsRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metric(value: totalCount, label: "Total", systemImage: "calendar", tint: Theme.blue)
            metric(value: timedCount, label: "Timed", systemImage: "clock.fill", tint: Theme.purple)
            metric(value: taskCount, label: "Tasks", systemImage: "checklist", tint: Theme.green)
            metric(value: eventCount + bundleCount, label: "Events", systemImage: "tray.full.fill", tint: Theme.amber)
        }
    }

    private var compactStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                selectedDayCard
                    .frame(width: 190)
                metric(value: totalCount, label: "Total", systemImage: "calendar", tint: Theme.blue)
                    .frame(width: 108)
                metric(value: timedCount, label: "Timed", systemImage: "clock.fill", tint: Theme.purple)
                    .frame(width: 108)
                metric(value: taskCount, label: "Tasks", systemImage: "checklist", tint: Theme.green)
                    .frame(width: 108)
                metric(value: eventCount + bundleCount, label: "Events", systemImage: "tray.full.fill", tint: Theme.amber)
                    .frame(width: 108)
                leadItemCard
                    .frame(width: 228)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .scrollIndicators(.hidden)
    }

    private var selectedDayCard: some View {
        HStack(spacing: 9) {
            VStack(spacing: 1) {
                Text(DateFormatters.dayOfWeek.string(from: selectedDate).prefix(3).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                Text(DateFormatters.dayNumber.string(from: selectedDate))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .frame(width: 38, height: 38)
            .background(Theme.blue.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.22), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentationLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(DateFormatters.longDate.string(from: selectedDate))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: isCompact ? 54 : 48)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.42), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }

    private func metric(value: Int, label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 54 : 48)
        .cadenceCard(background: tint.opacity(0.10), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }

    @ViewBuilder
    private var leadItemCard: some View {
        if let leadItem {
            HStack(spacing: 9) {
                Image(systemName: leadItem.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(leadItem.tint)
                    .frame(width: 30, height: 30)
                    .background(leadItem.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(leadItem.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(leadItem.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: isCompact ? 54 : 48)
            .cadenceCard(background: Theme.surfaceElevated.opacity(0.36), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
        } else {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceElevated.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("No lead item")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Add work from the inspector")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: isCompact ? 54 : 48)
            .cadenceCard(background: Theme.surfaceElevated.opacity(0.24), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
        }
    }
}

struct iOSCalendarToolbar: View {
    let title: String
    @Binding var viewMode: CadenceCalendarViewMode
    @Binding var presentation: CadenceCalendarPresentation
    @Binding var zoomLevel: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactToolbar
            } else {
                regularToolbar
            }
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 18 : 16)
        .padding(.vertical, horizontalSizeClass == .regular ? 10 : 12)
        .background(Theme.surface)
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                titleBlock
                Spacer(minLength: 10)
                navigationControls
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    modeControl
                    zoomControls
                }
                .padding(.trailing, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var regularToolbar: some View {
        HStack(spacing: 12) {
            titleBlock

            Spacer(minLength: 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    zoomControls
                    modeControl
                    navigationControls
                }

                HStack(spacing: 8) {
                    modeControl
                    navigationControls
                }
            }
        }
        .frame(minHeight: 42)
    }

    private var titleBlock: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 11 : 0) {
            if horizontalSizeClass == .regular {
                Image(systemName: CadenceFeatureDestination.calendar.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CadenceFeatureDestination.calendar.tint)
                    .frame(width: 32, height: 32)
                    .background(CadenceFeatureDestination.calendar.tint.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(CadenceFeatureDestination.calendar.tint.opacity(0.20), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar")
                    .font(.system(size: horizontalSizeClass == .regular ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: horizontalSizeClass == .regular ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minWidth: horizontalSizeClass == .regular ? 208 : 116, idealWidth: 246, maxWidth: 312, alignment: .leading)
        .layoutPriority(1)
    }

    private var modeControl: some View {
        iOSCalendarControlGroup {
            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                iOSCalendarToolbarPill(
                    title: mode.rawValue,
                    systemImage: mode == .month ? "calendar" : "rectangle.split.3x1",
                    isSelected: presentation == .timeline && viewMode == mode
                ) {
                    presentation = .timeline
                    viewMode = mode
                }
            }

            iOSCalendarToolbarPill(
                title: "Board",
                systemImage: "rectangle.grid.2x2",
                isSelected: presentation == .board
            ) {
                presentation = .board
            }
        }
    }

    @ViewBuilder
    private var zoomControls: some View {
        if presentation == .timeline && viewMode != .month {
            iOSCalendarControlGroup {
                iOSCalendarToolbarIconButton(systemImage: "minus", isEnabled: zoomLevel > 1) {
                    zoomLevel = max(1, zoomLevel - 1)
                }

                Text("\(zoomLevel)x")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
                    .frame(minWidth: 26, minHeight: 34)

                iOSCalendarToolbarIconButton(systemImage: "plus", isEnabled: zoomLevel < 3) {
                    zoomLevel = min(3, zoomLevel + 1)
                }
            }
        }
    }

    private var navigationControls: some View {
        iOSCalendarControlGroup {
            iOSCalendarToolbarIconButton(systemImage: "chevron.left", action: previous)
            iOSCalendarToolbarIconButton(systemImage: "location.fill", action: today)
            iOSCalendarToolbarIconButton(systemImage: "chevron.right", action: next)
        }
    }
}

private struct iOSCalendarControlGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 3) {
            content()
        }
        .padding(3)
        .background(Theme.bg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct iOSCalendarToolbarPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
            .frame(minWidth: 60)
            .frame(height: 34)
            .padding(.horizontal, 6)
            .background(isSelected ? Theme.blue.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.28) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct iOSCalendarToolbarIconButton: View {
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.text : Theme.dim.opacity(0.38))
                .frame(width: 34, height: 34)
                .background(isEnabled ? Theme.surfaceElevated.opacity(0.36) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage)
    }
}
#endif

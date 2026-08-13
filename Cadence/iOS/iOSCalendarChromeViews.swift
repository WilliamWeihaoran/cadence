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

/// The line under the toolbar that says what the selected day holds.
///
/// It used to be five shadowed cards in a row — a day card, four metric cards and a lead-item card,
/// each with its own fill, radius and elevation — occupying a full band above the calendar. Every
/// number in it is still here; they are chips on one row now, which is the treatment macOS uses for
/// exactly this kind of small tinted fact. The two things that went are the presentation label
/// ("Week" / "Board"), which only repeated the toolbar pill already lit up beside it, and the
/// "No lead item / Add work from the inspector" placeholder card, which took a card's worth of
/// space to say nothing.
struct iOSCalendarContextStrip: View {
    let selectedDate: Date
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
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                selectedDayLabel

                metricChips

                if let leadItem {
                    leadItemLabel(leadItem)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, isCompact ? 16 : 18)
            .padding(.vertical, 9)
            .frame(minWidth: horizontalSizeClass == .regular ? nil : 0)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Theme.bg.opacity(0.84))
    }

    private var selectedDayLabel: some View {
        HStack(spacing: 9) {
            VStack(spacing: 1) {
                Text(DateFormatters.dayOfWeek.string(from: selectedDate).prefix(3).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                Text(DateFormatters.dayNumber.string(from: selectedDate))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .frame(width: 36, height: 36)
            .background(Theme.blue.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.22), lineWidth: 1)
            }

            Text(DateFormatters.longDate.string(from: selectedDate))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private var metricChips: some View {
        HStack(spacing: 6) {
            iOSMetaChip(label: "\(totalCount) total", color: Theme.blue, systemImage: "calendar")
            iOSMetaChip(label: "\(timedCount) timed", color: Theme.purple, systemImage: "clock.fill")
            iOSMetaChip(label: "\(taskCount) tasks", color: Theme.green, systemImage: "checklist")
            // Blocks and events are separate things and used to be reported separately, by an
            // inspector strip this replaced. Summing them made a day of 2 blocks + 1 event read
            // identically to a day of 0 blocks + 3 events. Each is shown only when it has one.
            if bundleCount > 0 {
                iOSMetaChip(label: "\(bundleCount) blocks", color: Theme.amber, systemImage: "tray.full.fill")
            }
            if eventCount > 0 {
                iOSMetaChip(label: "\(eventCount) events", color: Theme.amber, systemImage: "calendar.badge.clock")
            }
            if bundleCount == 0 && eventCount == 0 {
                iOSMetaChip(label: "0 events", color: Theme.amber, systemImage: "calendar.badge.clock")
            }
        }
        .fixedSize()
    }

    private func leadItemLabel(_ leadItem: iOSCalendarLeadItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: leadItem.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(leadItem.tint)

            Text(leadItem.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Text(leadItem.detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.subdued)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next up: \(leadItem.title), \(leadItem.detail)")
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
        .frame(minHeight: 48)
    }

    /// Title only. This used to carry a "CALENDAR" eyebrow above the date — a page header naming
    /// the page you are already looking at, which the tab bar and sidebar both already say.
    private var titleBlock: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 11 : 0) {
            if horizontalSizeClass == .regular {
                iOSIconTile(
                    systemImage: CadenceFeatureDestination.calendar.systemImage,
                    color: CadenceFeatureDestination.calendar.tint,
                    size: 34,
                    iconSize: 15
                )
            }

            Text(title)
                .font(.system(size: horizontalSizeClass == .regular ? 21 : 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: horizontalSizeClass == .regular ? 208 : 116, idealWidth: 246, maxWidth: 312, alignment: .leading)
        .layoutPriority(1)
    }

    private var modeControl: some View {
        iOSSegmentedPillGroup {
            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                iOSSegmentedPill(
                    title: mode.rawValue,
                    systemImage: mode == .month ? "calendar" : "rectangle.split.3x1",
                    isSelected: presentation == .timeline && viewMode == mode
                ) {
                    presentation = .timeline
                    viewMode = mode
                }
            }

            iOSSegmentedPill(
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
            iOSSegmentedPillGroup {
                iOSIconButton(
                    systemImage: "minus",
                    accessibilityLabel: "Zoom out",
                    isEnabled: zoomLevel > 1,
                    plateSize: 38,
                    iconSize: 13,
                    showsPlate: false
                ) {
                    zoomLevel = max(1, zoomLevel - 1)
                }

                Text("\(zoomLevel)x")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
                    .frame(minWidth: 26, minHeight: 38)

                iOSIconButton(
                    systemImage: "plus",
                    accessibilityLabel: "Zoom in",
                    isEnabled: zoomLevel < 3,
                    plateSize: 38,
                    iconSize: 13,
                    showsPlate: false
                ) {
                    zoomLevel = min(3, zoomLevel + 1)
                }
            }
        }
    }

    private var navigationControls: some View {
        iOSSegmentedPillGroup {
            iOSIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous",
                plateSize: 38,
                iconSize: 13,
                showsPlate: false,
                action: previous
            )
            iOSIconButton(
                systemImage: "location.fill",
                accessibilityLabel: "Today",
                foreground: Theme.blue,
                plateSize: 38,
                iconSize: 13,
                showsPlate: false,
                action: today
            )
            iOSIconButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Next",
                plateSize: 38,
                iconSize: 13,
                showsPlate: false,
                action: next
            )
        }
    }
}
#endif

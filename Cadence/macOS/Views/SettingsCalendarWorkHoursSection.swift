#if os(macOS)
import SwiftUI

/// Settings → Calendar → Work Hours: the window the weekly views emphasize.
///
/// **The two controls were `Picker(.pickerStyle(.menu))` — the one place in Cadence's settings
/// where a control drew AppKit's own chrome and took no colour from the palette at all.** iOS's
/// half of this exact preference (`iOSCalendarWorkHoursSection`, same `calendar.workHours.*.v1`
/// keys) already presented it through the checkmarked popover list; T-20 pointed macOS at the same
/// shared `CadenceChoiceValueButton` / `CadenceChoicePopoverList`, so a work-hours picker looks the
/// same on both platforms and looks like every other picker in the app.
///
/// The sentence under the title is the one place a user learns what the setting *does*, which is
/// exactly the kind of line iOS kept when it dropped the ones that only restated their label. It
/// used to say "**Weekly calendar views** gently highlight …", and no part of that was true
/// (T-544). The band is `TimelineWorkHoursHighlightLayer`, drawn by `TimelineDayCanvas` once per
/// **day column**, and only where a caller passes `showWorkHoursHighlight: true`. There are exactly
/// two such callers: `CalDayColumn`, the Calendar page's day column, and
/// `SchedulePanelTimelineViewport` — the panel the app titles **Timeline**, which is not a calendar
/// view at all. "Weekly" was wrong a second way: the Calendar page's timeline draws day columns at
/// Week *and* 2 Weeks, and its Month presentation draws neither a day column nor a band.
///
/// What the sentence still leaves out is the weekend: `CalendarWorkHoursPreferences.shouldShowHighlight(on:)`
/// suppresses the band on Saturday and Sunday, on both platforms and in neither subtitle (T-696).
/// The call-site set is pinned by `CadenceSettingsSectionCopyTests`, so a third surface switching
/// the band on fails a test rather than making this sentence quietly wrong again.
struct SettingsCalendarWorkHoursSection: View {
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey) private var startMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey) private var endMinute = CalendarWorkHoursPreferences.defaultEndMinute
    @State private var showStartPicker = false
    @State private var showEndPicker = false

    private var workHoursLabel: String {
        CalendarWorkHoursPreferences.displayLabel(
            startMinute: startMinute,
            endMinute: endMinute
        )
    }

    var body: some View {
        CadenceFieldSection(title: "Work Hours") {
            HStack(alignment: .center, spacing: 14) {
                icon
                description
                Spacer(minLength: 12)
                controls
            }
        }
        .onAppear(perform: repairStoredRangeIfNeeded)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.amber.opacity(0.13))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(CadenceCalendarSettingsCopy.workdayBoundaryTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Calendar and Timeline day columns gently highlight \(workHoursLabel).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            timePicker(
                minute: startMinute,
                options: CalendarWorkHoursPreferences.selectableStartMinutes,
                isPresented: $showStartPicker,
                set: setStartMinute
            )

            Text("to")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            timePicker(
                minute: endMinute,
                options: CalendarWorkHoursPreferences.selectableEndMinutes,
                isPresented: $showEndPicker,
                set: setEndMinute
            )
        }
    }

    /// Byte-for-byte the shape `iOSCalendarWorkHoursSection.picker(title:options:isPresented:set:)`
    /// has: the value with a chevron, and the same checkmarked list behind it. The two differ only
    /// in the `minHeight` the row hands the button, which is `CadenceSettingsRowMetrics.rowHeight`
    /// on both and resolves per platform.
    private func timePicker(
        minute: Int,
        options: [Int],
        isPresented: Binding<Bool>,
        set: @escaping (Int) -> Void
    ) -> some View {
        CadenceChoiceValueButton(
            title: TimeFormatters.timeString(from: minute),
            minHeight: CadenceSettingsRowMetrics.rowHeight
        ) {
            isPresented.wrappedValue = true
        }
        .popover(isPresented: isPresented) {
            CadenceChoicePopoverList(
                rows: options.map { option in
                    CadenceChoiceRow(
                        value: option,
                        title: TimeFormatters.timeString(from: option),
                        color: Theme.amber
                    )
                },
                selection: Binding(get: { minute }, set: { set($0) }),
                isPresented: isPresented
            )
        }
    }

    private func setStartMinute(_ minute: Int) {
        let range = CalendarWorkHoursPreferences.rangeByUpdatingStart(
            minute,
            currentEndMinute: endMinute
        )
        startMinute = range.startMinute
        endMinute = range.endMinute
    }

    private func setEndMinute(_ minute: Int) {
        let range = CalendarWorkHoursPreferences.rangeByUpdatingEnd(
            minute,
            currentStartMinute: startMinute
        )
        startMinute = range.startMinute
        endMinute = range.endMinute
    }

    private func repairStoredRangeIfNeeded() {
        let range = CalendarWorkHoursPreferences.normalizedRange(
            startMinute: startMinute,
            endMinute: endMinute
        )
        if startMinute != range.startMinute {
            startMinute = range.startMinute
        }
        if endMinute != range.endMinute {
            endMinute = range.endMinute
        }
    }
}

// `SettingsWorkHoursTimePicker` used to sit here, wrapping `Picker(.menu)` at a fixed 104pt.
// It is gone rather than restyled: a menu picker is AppKit's control, drawing AppKit's bezel and
// AppKit's accent, and no amount of `Theme` around it changes what it paints. See `timePicker`
// above.

#endif

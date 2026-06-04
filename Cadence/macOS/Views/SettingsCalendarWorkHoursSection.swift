#if os(macOS)
import SwiftUI

struct SettingsCalendarWorkHoursSection: View {
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey) private var startMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey) private var endMinute = CalendarWorkHoursPreferences.defaultEndMinute

    private var workHoursLabel: String {
        CalendarWorkHoursPreferences.displayLabel(
            startMinute: startMinute,
            endMinute: endMinute
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Work Hours")
            SettingsCard {
                HStack(alignment: .center, spacing: 14) {
                    icon
                    description
                    Spacer(minLength: 12)
                    controls
                }
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
            Text("Workday boundary")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Weekly calendar views gently highlight \(workHoursLabel).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SettingsWorkHoursTimePicker(
                title: "Start",
                selection: Binding(
                    get: { startMinute },
                    set: { setStartMinute($0) }
                ),
                options: CalendarWorkHoursPreferences.selectableStartMinutes
            )

            Text("to")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            SettingsWorkHoursTimePicker(
                title: "End",
                selection: Binding(
                    get: { endMinute },
                    set: { setEndMinute($0) }
                ),
                options: CalendarWorkHoursPreferences.selectableEndMinutes
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

private struct SettingsWorkHoursTimePicker: View {
    let title: String
    @Binding var selection: Int
    let options: [Int]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { minute in
                Text(TimeFormatters.timeString(from: minute))
                    .tag(minute)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 104)
        .help(title)
    }
}
#endif

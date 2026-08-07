#if os(macOS)
import SwiftUI

struct HabitFormFields: View {
    @Binding var title: String
    @Binding var selectedIcon: String
    @Binding var selectedColor: String
    @Binding var frequencyType: HabitFrequency
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerWeek: Int
    @Binding var monthlyDay: Int
    @Binding var selectedContextID: UUID?
    @Binding var selectedGoalID: UUID?
    @Binding var hasReminder: Bool
    @Binding var reminderMinuteOfDay: Int

    let contexts: [Context]
    let goals: [Goal]

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HabitFormLabel("Title")
            TextField("e.g. Morning Run, Read 30 min", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(10)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

            if !contexts.isEmpty {
                HabitFormLabel("Context")
                CadenceContextPickerButton(
                    contexts: contexts,
                    selectedID: $selectedContextID
                )
            }

            HabitFormLabel("Goal")
            GoalLinkPickerButton(
                goals: goals,
                selectedID: $selectedGoalID,
                noneTitle: "No goal",
                noneSubtitle: "Track this habit independently",
                searchPlaceholder: "Search goals",
                emptyText: "No matching goals"
            )

            HabitFormLabel("Icon")
            IconGrid(selected: $selectedIcon)

            HabitFormLabel("Color")
            ColorGrid(selected: $selectedColor)

            HabitFormLabel("Frequency")
            HabitFrequencyPicker(selection: $frequencyType, tintHex: selectedColor)

            frequencyDetails

            HabitFormLabel("Reminder")
            HabitReminderPicker(
                hasReminder: $hasReminder,
                reminderMinuteOfDay: $reminderMinuteOfDay,
                tintHex: selectedColor
            )
        }
    }

    @ViewBuilder
    private var frequencyDetails: some View {
        switch frequencyType {
        case .daysOfWeek:
            HabitWeekdayPicker(
                selectedDays: $selectedDays,
                dayNames: dayNames,
                tintHex: selectedColor
            )
        case .timesPerWeek:
            HabitNumberStepper(
                title: "Weekly target",
                detail: "check-ins per week",
                value: $timesPerWeek,
                range: 1...7,
                tintHex: selectedColor
            )
        case .monthly:
            HabitNumberStepper(
                title: "Monthly day",
                detail: "day of month",
                value: $monthlyDay,
                range: 1...31,
                tintHex: selectedColor
            )
        case .daily:
            HabitFrequencyNote(
                icon: "sun.max.fill",
                title: "Every day",
                detail: "This habit is expected daily.",
                tintHex: selectedColor
            )
        }
    }
}

private struct HabitFormLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}

private struct HabitFrequencyPicker: View {
    @Binding var selection: HabitFrequency
    let tintHex: String

    private var options: [HabitFrequencyOption] {
        [
            HabitFrequencyOption(type: .daily, title: "Daily", detail: "Every day", icon: "sun.max.fill"),
            HabitFrequencyOption(type: .daysOfWeek, title: "Days", detail: "Specific weekdays", icon: "calendar"),
            HabitFrequencyOption(type: .timesPerWeek, title: "Weekly", detail: "Target count", icon: "number"),
            HabitFrequencyOption(type: .monthly, title: "Monthly", detail: "One day each month", icon: "calendar.badge.clock"),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(options) { option in
                frequencyButton(option)
            }
        }
    }

    private func frequencyButton(_ option: HabitFrequencyOption) -> some View {
        let isSelected = selection == option.type
        let tint = Color(hex: tintHex)

        return Button {
            selection = option.type
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.dim)
                    .frame(width: 28, height: 28)
                    .background((isSelected ? tint : Theme.dim).opacity(isSelected ? 0.14 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    Text(option.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 54)
            .background(isSelected ? tint.opacity(0.10) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tint.opacity(0.42) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

private struct HabitFrequencyOption: Identifiable {
    let type: HabitFrequency
    let title: String
    let detail: String
    let icon: String

    var id: String { type.rawValue }
}

private struct HabitWeekdayPicker: View {
    @Binding var selectedDays: Set<Int>
    let dayNames: [String]
    let tintHex: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let dayValue = index + 1
                let isSelected = selectedDays.contains(dayValue)
                Button {
                    if isSelected {
                        selectedDays.remove(dayValue)
                    } else {
                        selectedDays.insert(dayValue)
                    }
                } label: {
                    Text(dayNames[index])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isSelected ? Color(hex: tintHex) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.clear : Theme.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.cadencePlain)
            }
        }
    }
}

private struct HabitNumberStepper: View {
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tintHex: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            stepButton(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text("\(value)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 42, height: 32)
                .background(Color(hex: tintHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: tintHex).opacity(0.24), lineWidth: 1)
                )

            stepButton(systemImage: "plus", isDisabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    private func stepButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.45) : Color(hex: tintHex))
                .frame(width: 30, height: 30)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
    }
}

/// Daily reminder time-of-day toggle + picker. Setting a time IS the per-habit reminder opt-in —
/// there's no separate enabled flag on the model, `reminderMinuteOfDay == nil` means "off."
private struct HabitReminderPicker: View {
    @Binding var hasReminder: Bool
    @Binding var reminderMinuteOfDay: Int
    let tintHex: String

    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderMinuteOfDay / 60,
                    minute: reminderMinuteOfDay % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminderMinuteOfDay = ((comps.hour ?? 9) * 60) + (comps.minute ?? 0)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remind me")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("A daily local notification at this time.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Toggle("", isOn: $hasReminder)
                    .labelsHidden()
                    .tint(Color(hex: tintHex))
            }

            if hasReminder {
                Divider()
                    .background(Theme.borderSubtle)
                    .padding(.vertical, 10)
                DatePicker(
                    "Reminder time",
                    selection: reminderDate,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.field)
            }
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

private struct HabitFrequencyNote: View {
    let icon: String
    let title: String
    let detail: String
    let tintHex: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: tintHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: tintHex).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}
#endif

#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

struct ScheduleTimeRailRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        Text(hourLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(width: timeLabelWidth, height: hourHeight, alignment: .topTrailing)
            .padding(.trailing, timeLabelPad)
            .offset(y: -6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hourLabel: String { "\(hour)" }
}

/// Shared metrics for the inspector's "label left / value right" field list.
enum TaskInspectorFieldRowMetrics {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let minHeight: CGFloat = 34
    static let labelFont = Font.system(size: 11)
    static let valueFont = Font.system(size: 11, weight: .medium)
}

/// One line of the inspector overview list: field name on the left, value flush right.
struct TaskInspectorFieldRow<Value: View>: View {
    let label: String
    var verticalPadding: CGFloat = TaskInspectorFieldRowMetrics.verticalPadding
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(TaskInspectorFieldRowMetrics.labelFont)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            value
        }
        .padding(.horizontal, TaskInspectorFieldRowMetrics.horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskInspectorFieldRowMetrics.minHeight, alignment: .leading)
    }
}

/// Value text for a field row — bright when the field has a value, dim when it is empty.
struct TaskInspectorFieldValueText: View {
    let text: String
    let isSet: Bool

    var body: some View {
        Text(text)
            .font(TaskInspectorFieldRowMetrics.valueFont)
            .foregroundStyle(isSet ? Theme.text : Theme.dim)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// Hairline between field rows. `strong` marks the break between field groups.
struct TaskInspectorFieldDivider: View {
    var strong: Bool = false

    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(strong ? 1 : 0.6))
            .frame(height: 1)
    }
}

/// A field row whose entire surface is a button (opens a picker/menu for that field).
struct TaskInspectorFieldButtonRow: View {
    let label: String
    let valueText: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskInspectorFieldRow(label: label) {
                TaskInspectorFieldValueText(text: valueText, isSet: isSet)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
    }
}

struct TaskInspectorDateControl: View {
    /// Field name shown on the left (e.g. "Do date").
    let label: String
    /// Short word shown as the value when no date is set.
    var placeholder: String = "Set"
    /// Tint used by the picker's quick pills.
    var activeColor: Color = Theme.blue
    @Binding var isOn: Bool
    @Binding var date: Date

    @State private var showPicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    private var displayValue: String {
        guard isOn else { return placeholder }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: label,
            valueText: displayValue,
            isSet: isOn
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            pickerPopover
        }
        .onAppear {
            var comps = cal.dateComponents([.year, .month], from: isOn ? date : Date())
            comps.day = 1
            viewMonth = cal.date(from: comps) ?? Date()
        }
    }

    @ViewBuilder
    private var pickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                quickPill("Today", offset: 0)
                quickPill("Tomorrow", offset: 1)
                quickPill("This Weekend", weekend: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(
                    get: { date },
                    set: {
                        date = $0
                        isOn = true
                        showPicker = false
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $showPicker
            )

            if isOn {
                Divider().background(Theme.borderSubtle)

                Button {
                    isOn = false
                    showPicker = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clear date")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private func quickPill(_ label: String, offset: Int = 0, weekend: Bool = false) -> some View {
        let target: Date = {
            let today = cal.startOfDay(for: Date())
            if weekend {
                let todayWeekday = cal.component(.weekday, from: today)
                if todayWeekday == 7 || todayWeekday == 1 { return today }
                let daysUntilSaturday = (7 - todayWeekday + 7) % 7
                return cal.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
            }
            return cal.date(byAdding: .day, value: offset, to: today) ?? today
        }()
        let isSelected = isOn && cal.isDate(date, inSameDayAs: target)

        Button {
            date = target
            isOn = true
            showPicker = false
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.onColor : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? activeColor : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(InspectorPickerHover(cornerRadius: 999))
    }
}

struct TaskInspectorInfoCard<Content: View>: View {
    /// Inset applied around the card content. Pass `0` when the content supplies its own
    /// row padding (e.g. the overview field list, whose hairlines run edge to edge).
    var contentPadding: CGFloat = 10
    var contentSpacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            content
        }
        .padding(contentPadding)
        .background(Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.82), lineWidth: 1)
        )
    }
}

struct TaskInspectorSectionGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim)
                }
            }

            content
        }
    }
}

struct TaskInspectorDetailRow<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 11)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            .padding(.top, 7)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28, alignment: .top)
    }
}

struct TaskPriorityPill: View {
    let priority: TaskPriority
    let selected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(TaskTitleSupport.priorityMark(for: priority))
                .font(.system(size: 12, weight: .bold))
                .frame(minWidth: 18)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .foregroundStyle(selected ? Theme.priorityColor(priority) : Theme.dim)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .background(selected ? Theme.priorityColor(priority).opacity(0.12) : Theme.surface.opacity(0.6))
        .overlay(
            Capsule()
                .stroke(selected ? Theme.priorityColor(priority).opacity(0.35) : Theme.borderSubtle, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

struct InspectorPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

/// Estimate field row: whole row opens the shared estimate picker.
struct TaskInspectorEstimateFieldRow: View {
    @Binding var value: Int
    @State private var showPicker = false

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Estimate",
            valueText: TaskInspectorEstimateLabel.short(for: value),
            isSet: value > 0
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            EstimatePickerPopoverContent(value: $value) {
                showPicker = false
            }
        }
    }
}

enum TaskInspectorEstimateLabel {
    static func short(for minutes: Int) -> String {
        switch minutes {
        case ..<1:  return "None"
        case 60:    return "1h"
        case 90:    return "1.5h"
        case 120:   return "2h"
        case 150:   return "2.5h"
        case 180:   return "3h"
        default:    return "\(minutes)m"
        }
    }
}

/// Logged-minutes field row — the value stays inline-editable, right aligned.
struct TaskInspectorMinutesFieldRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        TaskInspectorFieldRow(label: label) {
            MinutesField(value: $value)
        }
    }
}

struct MinutesField: View {
    @Binding var value: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("—", text: $text)
                .textFieldStyle(.plain)
                .font(TaskInspectorFieldRowMetrics.valueFont)
                .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                .multilineTextAlignment(.trailing)
                .frame(width: 46)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { if !focused { commit() } }
            Text("min")
                .font(.system(size: 11))
                .foregroundStyle(value > 0 ? Theme.muted : Theme.dim)
        }
        .onAppear { text = value > 0 ? "\(value)" : "" }
        .onChange(of: value) { text = value > 0 ? "\(value)" : "" }
    }

    private func commit() {
        if let parsed = Int(text.trimmingCharacters(in: .whitespaces)), parsed >= 0 {
            value = parsed
        } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
            value = 0
        }
        text = value > 0 ? "\(value)" : ""
    }
}
#endif

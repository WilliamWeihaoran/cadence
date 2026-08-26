#if os(macOS)
import SwiftUI

/// Shared metrics for the inspector's "icon / label left / value right" field list.
enum TaskInspectorFieldRowMetrics {
    /// Each row carries its own horizontal inset rather than inheriting one from the recessed
    /// group. That is what lets a hovered row wash the full width of the well: if the group
    /// padded its contents, every hover would be a narrower box drawn inside the well's box.
    static let verticalPadding: CGFloat = 6
    static let minHeight: CGFloat = 32
    /// Fixed leading slot so every label in a group starts on the same x.
    static let iconSlot: CGFloat = 19
    static let iconSize: CGFloat = 12
    static let hoverCornerRadius: CGFloat = 6
    static let labelFont = Font.system(size: 11)
    static let valueFont = Font.system(size: 11)
    static let groupHorizontalPadding: CGFloat = 10
    static let groupCornerRadius: CGFloat = 8
    /// The *trailing* value beside a group label — a count, not an eyebrow — drawn at the
    /// eyebrow's own size so the two sit on one line. The label itself is
    /// `SectionEyebrowLabel(size: .compact)`; there is no second kerning constant here any more
    /// (T-284 — it was 0.54, one of four the 9pt tier had accumulated).
    static let groupLabelFont = SectionEyebrowLabel.Size.compact.font
}

/// Shared metrics for the inspector's `List › Section` breadcrumb. The segments themselves are
/// `ContainerPickerBadge` / `TaskSectionPickerBadge` in `breadcrumbSegment` mode — the same
/// pickers the chips elsewhere present, drawn as bare text.
enum TaskInspectorBreadcrumbMetrics {
    static let font = Font.system(size: 11, weight: .medium)
    static let segmentHeight: CGFloat = 20
    static let segmentHorizontalPadding: CGFloat = 5
    /// Caps one segment so a long list name cannot push the section out of the panel; the text
    /// still takes its intrinsic width when it is shorter.
    static let maxSegmentWidth: CGFloat = 128
    static let hoverCornerRadius: CGFloat = 5
}

/// One line of the inspector overview list: leading glyph, field name, value flush right.
struct TaskInspectorFieldRow<Value: View>: View {
    let label: String
    /// SF Symbol drawn in the fixed leading slot. `nil` leaves the slot empty so rows without
    /// an icon still align with their neighbours.
    var icon: String? = nil
    var iconColor: Color = Theme.dim
    /// Keeps the leading slot when `icon` is `nil`, so one iconless row still lines up with iconed
    /// neighbours. Set `false` for a group where *no* row has an icon — otherwise every label in it
    /// is indented past an empty column.
    var reservesIconSlot: Bool = true
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: TaskInspectorFieldRowMetrics.iconSize))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: icon == nil && !reservesIconSlot ? 0 : TaskInspectorFieldRowMetrics.iconSlot, alignment: .leading)

            Text(label)
                .font(TaskInspectorFieldRowMetrics.labelFont)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            value
        }
        .padding(.vertical, TaskInspectorFieldRowMetrics.verticalPadding)
        .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskInspectorFieldRowMetrics.minHeight, alignment: .leading)
    }
}

/// Uppercase group heading, optionally with a right-aligned counter ("1/3").
struct TaskInspectorGroupLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            SectionEyebrowLabel(text: title, size: .compact)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(TaskInspectorFieldRowMetrics.groupLabelFont)
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
            }
        }
    }
}

/// Recessed well that holds a run of field rows (or any inspector content).
struct TaskInspectorRecessedGroup<Content: View>: View {
    var verticalPadding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRecessed)
        .clipShape(RoundedRectangle(cornerRadius: TaskInspectorFieldRowMetrics.groupCornerRadius))
    }
}

/// Group heading + recessed well, the standard inspector section shape.
struct TaskInspectorRecessedSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TaskInspectorGroupLabel(title: title, trailing: trailing)
            TaskInspectorRecessedGroup {
                content
            }
        }
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

/// Hairline between field rows. Never drawn after the last row of a group.
struct TaskInspectorFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 1)
            // Matches the rows' own inset so the hairlines still start at the icon column now
            // that the group no longer pads its contents.
            .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
    }
}

/// A field row whose entire surface is a button (opens a picker/menu for that field).
///
/// Uses `.plain`, **not** `.cadencePlain`, so every row in the well hovers identically:
/// `InspectorPickerHover` is the one hover layer. Stacking cadencePlain's radius-10 blue fill +
/// stroke on top of that made the button rows hover heavier than their neighbour and nested a
/// radius-6 wash inside a radius-10 border. One layer, one radius, every row in the well.
struct TaskInspectorFieldButtonRow: View {
    let label: String
    var icon: String? = nil
    /// Semantic tint for the glyph — the colour the field's concept already carries elsewhere in
    /// the app (do = blue, due = red, estimate = purple, actual = green, repeat = amber).
    var iconColor: Color = Theme.dim
    /// See `TaskInspectorFieldRow.reservesIconSlot`.
    var reservesIconSlot: Bool = true
    let valueText: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskInspectorFieldRow(
                label: label,
                icon: icon,
                iconColor: iconColor,
                reservesIconSlot: reservesIconSlot
            ) {
                TaskInspectorFieldValueText(text: valueText, isSet: isSet)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
    }
}

struct TaskInspectorDateControl: View {
    /// Field name shown on the left (e.g. "Do").
    let label: String
    /// SF Symbol for the row's leading slot.
    var icon: String? = nil
    /// Tint used by the picker's quick pills.
    var activeColor: Color = Theme.blue
    /// See `TaskInspectorFieldRow.reservesIconSlot`.
    var reservesIconSlot: Bool = true
    @Binding var isOn: Bool
    @Binding var date: Date

    @State private var showPicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    private var displayValue: String {
        guard isOn else { return "Set" }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: label,
            icon: icon,
            // The glyph reuses the field's own accent rather than taking a second parameter —
            // "Do is blue, Due is red" is one fact, and two knobs could disagree.
            iconColor: activeColor,
            reservesIconSlot: reservesIconSlot,
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

/// Group heading + free-form (non-recessed) content, e.g. the Actions row.
struct TaskInspectorSectionGroup<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TaskInspectorGroupLabel(title: title, trailing: trailing)
            content
        }
    }
}

/// Header priority affordance: the shared "!" mark convention on a tinted, clickable surface.
/// Deliberately not a flag glyph — the marks are the app-wide priority language.
struct TaskPriorityMarkControl: View {
    let priority: TaskPriority

    private var isSet: Bool { priority != .none }
    private var tint: Color { isSet ? Theme.priorityColor(priority) : Theme.dim }

    var body: some View {
        Text(TaskTitleSupport.priorityMark(for: priority))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(minWidth: 28, minHeight: 28)
            .background(isSet ? tint.opacity(0.10) : Theme.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSet ? tint.opacity(0.30) : Theme.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}

/// The inspector's single hover layer: one neutral wash, one radius, no border.
///
/// It fills with the same `TaskHoverVisuals` raise the task rows elsewhere in the app use, so a
/// hovered inspector row reads as "this row" rather than as an accent-tinted box drawn inside the
/// well's box. Anything that needs a hover here goes through this modifier — never a second
/// `.background()` at a call site.
struct InspectorPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(TaskHoverVisuals.hoverFill(isHovered: isHovered))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

/// Estimate as a compact chip for the inspector's title row.
///
/// It used to be a field row inside the SCHEDULE well. An estimate is a property of the task the
/// way its priority is, not a date you pick, so it now sits beside the title with the priority
/// tile — the two things you set while naming the task. Same roller popover either way.
struct TaskInspectorEstimateChip: View {
    @Binding var value: Int
    /// Uppercase heading for the roller panel.
    var title: String = "ESTIMATE"
    @State private var showPicker = false

    private var isSet: Bool { value > 0 }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                    // Purple is the app's planned-time colour, as it was on the old row's glyph.
                    .foregroundStyle(isSet ? Theme.purple : Theme.dim)
                Text(isSet ? CadenceTaskPresentationSupport.estimateLabel(minutes: value) : "Est")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSet ? Theme.text : Theme.dim)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(Theme.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        // The title beside it is an editable field: without this the chip is treated as flexible
        // and a long title squeezes it down to its glyph.
        .fixedSize()
        // Buttons take key focus under Full Keyboard Access; leaving the chip out of the focus
        // ring means clicking it cannot pull the caret out of a title being typed.
        .focusable(false)
        .help("Estimate")
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            EstimatePickerPopoverContent(value: $value, title: title) {
                showPicker = false
            }
        }
    }
}

/// The macOS spelling of the app's one estimate roller.
///
/// The roller itself moved to `Shared/Components/EstimatePickerControl.swift` when iPad and iPhone
/// adopted it: there is a single implementation now, and this name only survives so the macOS call
/// sites that predate the move keep reading the way they did.
typealias TaskInspectorEstimateRollerPopover = EstimatePickerPopoverContent


#endif

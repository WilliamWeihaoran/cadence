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
    static let groupLabelFont = Font.system(size: 9, weight: .semibold)
    /// ~0.06em at 9pt.
    static let groupLabelKerning: CGFloat = 0.54
}

/// One line of the inspector overview list: leading glyph, field name, value flush right.
struct TaskInspectorFieldRow<Value: View>: View {
    let label: String
    /// SF Symbol drawn in the fixed leading slot. `nil` leaves the slot empty so rows without
    /// an icon still align with their neighbours.
    var icon: String? = nil
    var iconColor: Color = Theme.dim
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
            .frame(width: TaskInspectorFieldRowMetrics.iconSlot, alignment: .leading)

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
            Text(title.uppercased())
                .font(TaskInspectorFieldRowMetrics.groupLabelFont)
                .foregroundStyle(Theme.dim)
                .kerning(TaskInspectorFieldRowMetrics.groupLabelKerning)

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
    let valueText: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskInspectorFieldRow(label: label, icon: icon, iconColor: iconColor) {
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

/// Estimate field row: whole row opens the roller picker.
struct TaskInspectorEstimateFieldRow: View {
    @Binding var value: Int
    var label: String = "Estimate"
    var icon: String = "timer"
    var iconColor: Color = Theme.purple
    @State private var showPicker = false

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: label,
            icon: icon,
            iconColor: iconColor,
            valueText: value > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: value) : "None",
            isSet: value > 0
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            // The popover heading follows the row, so the "Actual" row cannot present a panel
            // titled ESTIMATE.
            TaskInspectorEstimateRollerPopover(value: $value, title: label.uppercased()) {
                showPicker = false
            }
        }
    }
}

// MARK: - Estimate roller

/// Duration editor as a roller: the live total on top, an hours column stepping by 1 beside a
/// minutes column stepping by 5, then the presets.
///
/// SwiftUI has no wheel picker on macOS, so each column is a `ScrollView` whose *centred* row is
/// read back through `scrollPosition(id:anchor:)`. That keeps real trackpad/scroll-wheel input
/// working — a custom drag-driven offset would only answer to click-drags, since SwiftUI exposes
/// no scroll-wheel event — while `.onKeyPress` on the focused column handles ↑/↓ to step it and
/// ←/→ to move between the two.
struct TaskInspectorEstimateRollerPopover: View {
    @Binding var value: Int
    /// Uppercase heading. Callers editing a duration that is not a planning estimate (logged
    /// "Actual" minutes) pass their own so the panel is not mislabelled.
    var title: String = "ESTIMATE"
    var onClose: () -> Void = {}

    private enum RollerColumn: Hashable { case hours, minutes }

    @State private var hours = 0
    @State private var minutes = 0
    /// The scroll positions report their centred row a beat *after* layout. Until that has
    /// settled, a reported change is the picker seeding itself rather than an edit — committing
    /// it would silently round an off-step value (focus-logged "Actual" minutes are rarely
    /// multiples of 5) merely because the popover was opened.
    @State private var isSeeding = true
    @FocusState private var focusedColumn: RollerColumn?

    private static let hourValues = Array(0...24)
    private static let minuteValues = Array(stride(from: 0, through: 55, by: 5))
    private static let presets: [Int] = [15, 30, 45, 60, 90]
    /// Matches every other estimate entry point in the app: a duration field tops out at 24h.
    private static let maxMinutes = 1440

    private var total: Int { min(hours * 60 + minutes, Self.maxMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            rollers
            presetRow

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            footer
        }
        .padding(10)
        .frame(width: 260)
        .background(Theme.surfaceElevated)
        .onAppear {
            seed(from: value)
            DispatchQueue.main.async { focusedColumn = .hours }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            isSeeding = false
        }
        .onChange(of: hours) { _, _ in commit() }
        .onChange(of: minutes) { _, _ in commit() }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.54)

            Spacer(minLength: 0)

            Text(total > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: total) : "None")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(total > 0 ? Theme.text : Theme.dim)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var rollers: some View {
        HStack(spacing: 8) {
            column(.hours, values: Self.hourValues, unit: "h", selection: $hours)
            column(.minutes, values: Self.minuteValues, unit: "m", selection: $minutes)
        }
    }

    @ViewBuilder
    private func column(
        _ id: RollerColumn,
        values: [Int],
        unit: String,
        selection: Binding<Int>
    ) -> some View {
        EstimateRollerColumn(
            values: values,
            unit: unit,
            selection: selection,
            isFocused: focusedColumn == id
        )
        .focusable()
        // The column already says it has focus, with its own blue stroke. AppKit's ring is drawn
        // outside the frame and wraps the whole scroll view, so leaving it on stated the same
        // thing twice at two different sizes — which read as a stray box, not as focus.
        .focusEffectDisabled()
        .focused($focusedColumn, equals: id)
        .onKeyPress(.upArrow) { step(-1, in: values, selection: selection); return .handled }
        .onKeyPress(.downArrow) { step(1, in: values, selection: selection); return .handled }
        .onKeyPress(.leftArrow) { focusedColumn = .hours; return .handled }
        .onKeyPress(.rightArrow) { focusedColumn = .minutes; return .handled }
        .onKeyPress(.return) { onClose(); return .handled }
    }

    @ViewBuilder
    private var presetRow: some View {
        HStack(spacing: 5) {
            ForEach(Self.presets, id: \.self) { preset in
                let isSelected = total == preset
                Button {
                    apply(preset)
                    onClose()
                } label: {
                    Text(CadenceTaskPresentationSupport.estimateLabel(minutes: preset))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.blue : Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(isSelected ? Theme.blue.opacity(0.14) : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(InspectorPickerHover(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                apply(0)
                onClose()
            } label: {
                Text("Clear")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(InspectorPickerHover(cornerRadius: 6))

            Spacer(minLength: 0)

            Button {
                commit(force: true)
                onClose()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Edits

    private func seed(from minutesValue: Int) {
        let clamped = min(max(0, minutesValue), Self.maxMinutes)
        hours = clamped / 60
        // Floored, not rounded, to a step the minutes column actually carries.
        minutes = (clamped % 60) / 5 * 5
    }

    private func step(_ delta: Int, in values: [Int], selection: Binding<Int>) {
        isSeeding = false
        guard let index = values.firstIndex(of: selection.wrappedValue) else {
            selection.wrappedValue = values.first ?? 0
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            selection.wrappedValue = values[min(max(0, index + delta), values.count - 1)]
        }
    }

    /// Sets both columns from a total. Commits directly rather than relying on the column
    /// `onChange`, so "Clear" still writes 0 when the columns already read 0h 0m.
    private func apply(_ totalMinutes: Int) {
        isSeeding = false
        seed(from: totalMinutes)
        commit(force: true)
    }

    private func commit(force: Bool = false) {
        guard force || !isSeeding else { return }
        if value != total { value = total }
    }
}

/// One roller column. The centre band is drawn *behind* the scrolling rows so it tints the well
/// rather than the glyphs sitting in it.
/// Caps how far one gesture can carry the roller.
///
/// `.viewAligned` snaps to a row but says nothing about distance, so a flick lands wherever
/// momentum takes it — at a 26pt row a light trackpad push crosses a dozen values, which reads
/// as the control running away from you rather than as scrolling. Clamping the landing point to
/// a few rows either side of where the gesture started keeps a flick feeling like a nudge, and
/// still lets a deliberate drag move as far as the finger actually travels.
private struct EstimateRollerScrollBehavior: ScrollTargetBehavior {
    let rowHeight: CGFloat
    let maxRowsPerGesture: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let origin = context.originalTarget.rect.minY
        let limit = rowHeight * maxRowsPerGesture
        let bounded = min(max(target.rect.minY, origin - limit), origin + limit)
        // Land on a whole row regardless, so the centre band never holds a half value.
        target.rect.origin.y = (bounded / rowHeight).rounded() * rowHeight
    }
}

private struct EstimateRollerColumn: View {
    let values: [Int]
    let unit: String
    @Binding var selection: Int
    let isFocused: Bool

    private static let rowHeight: CGFloat = 26
    /// Deliberately small. The presets below the rollers cover the common values, so these are
    /// for adjusting by a step or two — precision matters more here than range.
    private static let maxRowsPerGesture: CGFloat = 3
    private static let visibleRows: CGFloat = 5
    private static let cornerRadius: CGFloat = 8

    private var viewportHeight: CGFloat { Self.rowHeight * Self.visibleRows }

    /// `scrollPosition` wants an optional; a nil centre (mid-fling, empty content) must not wipe
    /// the selection.
    private var centeredValue: Binding<Int?> {
        Binding(
            get: { selection },
            set: { if let newValue = $0 { selection = newValue } }
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { item in
                    Text("\(item)\(unit)")
                        .font(.system(size: 13, weight: item == selection ? .semibold : .regular))
                        .foregroundStyle(item == selection ? Theme.text : Theme.muted)
                        .monospacedDigit()
                        .opacity(opacity(for: item))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.rowHeight)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(
            EstimateRollerScrollBehavior(
                rowHeight: Self.rowHeight,
                maxRowsPerGesture: Self.maxRowsPerGesture
            )
        )
        // Lets the first and last rows reach the centre band instead of stopping at the edges.
        .contentMargins(.vertical, (viewportHeight - Self.rowHeight) / 2, for: .scrollContent)
        .scrollPosition(id: centeredValue, anchor: .center)
        .frame(height: viewportHeight)
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.blue.opacity(0.12))
                .frame(height: Self.rowHeight)
                .padding(.horizontal, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Theme.surfaceRecessed)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(isFocused ? Theme.blue.opacity(0.5) : Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func opacity(for item: Int) -> Double {
        guard let itemIndex = values.firstIndex(of: item),
              let selectedIndex = values.firstIndex(of: selection) else { return 0.35 }
        switch abs(itemIndex - selectedIndex) {
        case 0:  return 1
        case 1:  return 0.55
        default: return 0.3
        }
    }
}

#endif

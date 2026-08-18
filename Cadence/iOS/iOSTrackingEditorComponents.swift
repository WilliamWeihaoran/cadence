#if os(iOS)
import SwiftUI

struct iOSTrackingEditorShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let canSave: Bool
    let tint: Color
    let save: () -> Void
    @ViewBuilder let content: Content

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
                    .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The default bar is transparent until the content scrolls under it, and the material
            // it then uses is thin enough over `Theme.bg` that the segmented control passing
            // underneath reads straight through "New Goal" and "Save". An opaque bar in the app's
            // own surface colour is what the rest of Cadence's chrome does anyway.
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(tint)
        }
    }

    /// The fourth editor sheet, and the last to be speaking its own dialect: it had written down the
    /// gutter ramp, the two-column cap and the gap between groups again, in its own literals, so
    /// three decisions the other three sheets share were four copies each. Nothing here is a new
    /// layout — it is the same layout, stated once.
    @ViewBuilder
    private var editorContent: some View {
        if isRegularWidth {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: iOSEditorSheetMetrics.groupSpacing, alignment: .top),
                    GridItem(.flexible(), spacing: iOSEditorSheetMetrics.groupSpacing, alignment: .top)
                ],
                alignment: .leading,
                spacing: iOSEditorSheetMetrics.groupSpacing
            ) {
                content
            }
            .frame(maxWidth: iOSEditorSheetMetrics.twoColumnMaxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                content
            }
        }
    }
}

struct iOSTrackingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        iOSTrackingPickerSection(title: title) {
            field
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceElevated.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
    }

    @ViewBuilder
    private var field: some View {
        if axis == .vertical {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(3...6)
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(1)
        }
    }
}

/// The tracking editors' name for `iOSEditorSection`. The calendar sheets each carried their own
/// byte-identical copy of this; there is one now.
struct iOSTrackingPickerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        iOSEditorSection(title: title) { content }
    }
}

/// The label half of a label/value row inside an editor card. Previously these were bare `Text`,
/// which resolves to the system's own primary colour rather than anything in `Theme` — and read at
/// the same weight as the value beside it, so neither looked like the answer.
struct iOSTrackingFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.subdued)
    }
}

struct iOSTrackingDateRangeSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        iOSTrackingPickerSection(title: "Dates") {
            HStack {
                iOSTrackingFieldLabel("Start")
                Spacer()
                CadenceDatePicker(selection: $startDate)
            }
            iOSEditorDivider()
            HStack {
                iOSTrackingFieldLabel("End")
                Spacer()
                CadenceDatePicker(selection: $endDate)
            }
            .onChange(of: endDate) { _, newValue in
                if newValue < startDate {
                    endDate = startDate
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
    }
}

struct iOSHabitFrequencyEditor: View {
    let frequencyType: HabitFrequency
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerWeek: Int
    @Binding var monthlyDay: Int
    @State private var showTimesPerWeekPicker = false
    @State private var showMonthlyDayPicker = false

    private let weekdays = [
        (1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")
    ]

    var body: some View {
        switch frequencyType {
        case .daily:
            Text("Every day")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.subdued)
        case .daysOfWeek:
            // 44pt circles, not 34: these are the smallest controls in the editor and the
            // easiest to mis-tap, and selected/unselected now read as tint-wash vs. plain the
            // same way every other toggle in the app does.
            HStack(spacing: 6) {
                ForEach(weekdays, id: \.0) { day, label in
                    let isOn = selectedDays.contains(day)
                    Button {
                        if isOn {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOn ? Theme.blue : Theme.dim)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(isOn ? Theme.blue.opacity(0.14) : Theme.surfaceElevated.opacity(0.55)))
                            .overlay(Circle().strokeBorder(isOn ? Theme.blue.opacity(0.28) : Theme.borderSubtle.opacity(0.45), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.iosPressable)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        case .timesPerWeek:
            HStack {
                iOSTrackingFieldLabel("Times per week")
                Spacer()
                iOSChoiceValueButton(title: "\(timesPerWeek)", color: Theme.text) {
                    showTimesPerWeekPicker = true
                }
                .popover(isPresented: $showTimesPerWeekPicker) {
                    iOSChoicePopoverList(
                        rows: HabitFrequency.weeklyTargetRange.map { count in
                            iOSChoiceRow(value: count, title: "\(count)", color: Theme.blue)
                        },
                        selection: $timesPerWeek,
                        isPresented: $showTimesPerWeekPicker
                    )
                }
            }
        case .monthly:
            HStack {
                iOSTrackingFieldLabel("Day of month")
                Spacer()
                iOSChoiceValueButton(title: "\(monthlyDay)", color: Theme.text) {
                    showMonthlyDayPicker = true
                }
                .popover(isPresented: $showMonthlyDayPicker) {
                    iOSChoicePopoverList(
                        rows: (1...31).map { day in
                            iOSChoiceRow(value: day, title: "\(day)", color: Theme.blue)
                        },
                        selection: $monthlyDay,
                        isPresented: $showMonthlyDayPicker
                    )
                }
            }
        }
    }
}

struct iOSTrackingIconGrid: View {
    @Binding var selection: String
    /// The shared set, not a fourth private one. This used to offer `sparkles`, `figure.run` and
    /// `brain.head.profile`, none of which macOS can select — so an icon chosen for a goal here
    /// showed no selection when the same goal was opened on the Mac.
    private var icons: [String] { CadenceIconPalette.offeredIcons(for: selection) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { icon in
                let isOn = selection == icon
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.blue : Theme.dim)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .fill(isOn ? Theme.blue.opacity(0.14) : Theme.surfaceElevated.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .strokeBorder(isOn ? Theme.blue.opacity(0.28) : Theme.borderSubtle.opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

struct iOSTrackingColorGrid: View {
    @Binding var selection: String
    private var colors: [String] { CadenceColorPalette.offeredColors(for: selection) }

    /// Wraps onto a second line rather than scrolling sideways.
    ///
    /// Twelve 36pt swatches plus their gaps need ~531pt and the enclosing `iOSEditorSection` card
    /// leaves about 329pt on an iPhone, so this was a horizontal `ScrollView`. That version did
    /// scroll — the parent scroll is vertical and nothing competes for the gesture — but four of
    /// the twelve colours sat off the edge with nothing to say so, and the icon grid directly above
    /// it in the same sheet wraps. `CadenceWrappingHStack` shows the whole palette at once and
    /// removes the only reason the two grids looked like different kinds of control.
    var body: some View {
        CadenceWrappingHStack(spacing: 9, lineSpacing: 9) {
            ForEach(colors, id: \.self) { color in
                let isOn = CadenceColorPalette.matches(color, selection)
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(isOn ? Theme.text : Color.clear, lineWidth: 2)
                        }
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(isOn ? Color(hex: color).opacity(0.45) : Color.clear, lineWidth: 1)
                        }
                        .iOSExpandedHitArea(4)
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Color \(color)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
#endif

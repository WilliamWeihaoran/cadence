import SwiftUI

/// The **testable** half of the time roller: which values each column carries, how they are
/// printed, and how the three of them become one minute-of-day.
///
/// Kept out of the view for the reason `EstimateRollerMetrics` is: the macOS test target cannot
/// reach a SwiftUI body, and the arithmetic of "12 AM is hour 0, 12 PM is hour 12" is exactly the
/// kind of thing that is wrong once and then wrong everywhere.
///
/// **Minutes from midnight is the app's existing vocabulary for a clock time** —
/// `AppTask.scheduledStartMin`, `TaskBundle.startMin`, `CadenceStartTimeFieldRow`'s binding and
/// `TimeFormatters.timeString(from:)` all speak it — so the roller speaks it too rather than
/// introducing a `Date` or a `DateComponents` that would have to be converted at every call site.
@MainActor
enum CadenceTimeRollerModel {
    /// The minute column's step.
    ///
    /// `pointerTimeGridMinutes`, not the 15 a *tap* on a timeline lands on: a roller is dragged
    /// past its values rather than aimed at one, so it can afford the finer grid, and five minutes
    /// is the step the estimate roller's minute column already uses. A user who wants 4:15 reaches
    /// it either way; a user who wants 4:05 can only reach it here.
    static let minuteStep = CadenceScheduleSupport.pointerTimeGridMinutes

    static let minuteValues = Array(stride(from: 0, to: 60, by: minuteStep))

    /// `0` is AM and `1` is PM, as `Int`s, so the meridiem wheel is the same `CadenceRollerColumn`
    /// the other two are rather than a third kind of control standing beside them.
    static let meridiemValues = [0, 1]
    static let amValue = 0
    static let pmValue = 1

    /// 1…12 on a 12-hour face, 0…23 on a 24-hour one.
    ///
    /// Ascending from 1 rather than Apple's `12, 1, 2, …, 11`. A column that starts at 12, drops to
    /// 1 and climbs back to 11 is a ring drawn as a list — correct on an endless wheel, and a
    /// discontinuity on a `ScrollView` that has a first row and a last one.
    static func hourValues(usesTwentyFourHourClock: Bool) -> [Int] {
        usesTwentyFourHourClock ? Array(0...23) : Array(1...12)
    }

    static func hourLabel(_ hour: Int, usesTwentyFourHourClock: Bool) -> String {
        usesTwentyFourHourClock ? String(format: "%02d", hour) : "\(hour)"
    }

    static func minuteLabel(_ minute: Int) -> String {
        String(format: "%02d", minute)
    }

    static func meridiemLabel(_ value: Int) -> String {
        value == pmValue ? "PM" : "AM"
    }

    // MARK: Column widths ([[T-8471]])

    /// The roller's three wheels, named here rather than inside the view so the width each one is
    /// owed can be asked of the model — the test target cannot lay out a SwiftUI body.
    enum Column: Hashable, CaseIterable {
        case hour
        case minute
        case meridiem
    }

    /// The AM/PM wheel's floor, unchanged from the literal the view used to pass.
    static let meridiemColumnMinimumWidth: CGFloat = 48

    /// A digit's advance as a fraction of its point size. SF's tabular digits — the column draws
    /// `.monospacedDigit()` — run at about 0.6em; the extra hundredths cover the semibold the
    /// centred row is drawn in.
    static let digitAdvanceRatio: CGFloat = 0.62

    /// Clear space either side of the digits: the centre band is inset 4pt from the well's edge,
    /// and the digits need room inside the band as well as inside the well.
    static let digitColumnHorizontalInset: CGFloat = 12

    /// How wide a column must stay to draw its widest label in full.
    ///
    /// **[[T-8471]].** The view used to pass `48` for the meridiem wheel and `nil` for the other
    /// two, so when the popover was handed less than its ideal width — on iPad,
    /// `iOSTimelineDraftPanelHost`'s editor gives the nested roller popover ~112pt — the hour and
    /// minute columns were the ones that gave way, and the minute wheel was cut to a sliver drawing
    /// ellipses where `00`/`05`/`10` should be. A column that carries digits now has a floor sized
    /// from them, so the squeeze lands on the popover's width rather than on the glyphs. Not a
    /// platform branch: the same floor holds on macOS, where the popover simply reports a slightly
    /// larger ideal width.
    static func minimumColumnWidth(
        for column: Column,
        usesTwentyFourHourClock: Bool,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let labels: [String]
        switch column {
        case .meridiem:
            return meridiemColumnMinimumWidth
        case .hour:
            labels = hourValues(usesTwentyFourHourClock: usesTwentyFourHourClock)
                .map { hourLabel($0, usesTwentyFourHourClock: usesTwentyFourHourClock) }
        case .minute:
            labels = minuteValues.map(minuteLabel)
        }
        let widestLabel = CGFloat(labels.map(\.count).max() ?? 2)
        let pointSize = CadenceTypeScale.size(
            .controlLabel,
            base: CadenceRollerMetrics.rowLabelSize,
            at: dynamicTypeSize,
            scaling: scaling
        )
        return (widestLabel * pointSize * digitAdvanceRatio).rounded(.up) + digitColumnHorizontalInset * 2
    }

    /// A minute-of-day split into the three columns.
    ///
    /// The minute is **floored** to a step the column actually carries, never rounded up: a stored
    /// 4:07 opens on 4:05, so merely opening the roller cannot push a time later than the one that
    /// was recorded. Same rule, same reason, as `EstimateRollerMetrics.columns(forTotal:)`.
    static func components(
        fromMinutes minutes: Int,
        usesTwentyFourHourClock: Bool
    ) -> (hour: Int, minute: Int, meridiem: Int) {
        let clamped = min(max(0, minutes), 24 * 60 - 1)
        let hour24 = clamped / 60
        let minute = (clamped % 60) / minuteStep * minuteStep
        if usesTwentyFourHourClock {
            return (hour24, minute, hour24 >= 12 ? pmValue : amValue)
        }
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return (hour12, minute, hour24 >= 12 ? pmValue : amValue)
    }

    /// The three columns back into a minute-of-day.
    ///
    /// On a 12-hour face `12 AM` is midnight and `12 PM` is noon, which is the one pair of readings
    /// a naive `hour + meridiem * 12` gets wrong in both directions.
    static func minutes(
        hour: Int,
        minute: Int,
        meridiem: Int,
        usesTwentyFourHourClock: Bool
    ) -> Int {
        let boundedMinute = min(max(0, minute), 59)
        if usesTwentyFourHourClock {
            return min(max(0, hour), 23) * 60 + boundedMinute
        }
        let base = (min(max(1, hour), 12) % 12) + (meridiem == pmValue ? 12 : 0)
        return base * 60 + boundedMinute
    }
}

/// Hour and minute on **separate** wheels, with AM/PM beside them on a 12-hour face.
///
/// The owner's ruling, and the reason it is not a system control: SwiftUI's `DatePicker` offers one
/// combined spinner and none at all in wheel form on macOS. This is `CadenceRollerColumn` — the
/// mechanism `EstimatePickerControl` has shipped on both platforms since T-1431 — three times over.
///
/// ## Pointer and keyboard, not only touch
///
/// Inherited from that column rather than re-solved, and worth naming because a roller that can only
/// be flicked is useless on a Mac:
///
/// - each column is a real `ScrollView`, so a trackpad two-finger scroll and a mouse wheel drive it
///   natively (a custom drag-driven offset would answer only to click-drags — SwiftUI surfaces no
///   scroll-wheel event);
/// - the focused column takes **↑/↓** to step one row, and **←/→** to move between hour, minute and
///   meridiem, so the whole control is reachable without ever touching the pointer;
/// - **Return** closes, through `onSubmit`;
/// - and the focused column draws its own blue stroke, with AppKit's focus ring suppressed so focus
///   is stated once rather than twice at two different sizes.
struct CadenceTimeRoller: View {
    @Binding var minutes: Int
    /// The reader's clock face. Defaulted from the locale and injectable so a test — and the
    /// 24-hour half of the app — does not depend on the machine it runs on.
    var usesTwentyFourHourClock: Bool = TimeFormatters.usesTwentyFourHourClock()
    var onSubmit: () -> Void = {}

    private typealias Column = CadenceTimeRollerModel.Column

    @State private var hour = 9
    @State private var minute = 0
    @State private var meridiem = CadenceTimeRollerModel.amValue
    /// The scroll positions report their centred row a beat after layout. Until that has settled a
    /// reported change is the roller seeding itself, and writing it back would floor a stored
    /// off-step minute merely because the popover was opened. `EstimatePickerPopoverContent` holds
    /// the same latch for the same reason.
    @State private var isSeeding = true
    @FocusState private var focusedColumn: Column?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hourValues: [Int] {
        CadenceTimeRollerModel.hourValues(usesTwentyFourHourClock: usesTwentyFourHourClock)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TimeFormatters.timeString(from: minutes))
                .cadenceFont(.fieldValue, base: CadenceRollerMetrics.totalLabelSize)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .lineLimit(1)

            HStack(spacing: 6) {
                column(.hour, values: hourValues, selection: $hour) {
                    CadenceTimeRollerModel.hourLabel($0, usesTwentyFourHourClock: usesTwentyFourHourClock)
                }
                column(.minute, values: CadenceTimeRollerModel.minuteValues, selection: $minute) {
                    CadenceTimeRollerModel.minuteLabel($0)
                }
                if !usesTwentyFourHourClock {
                    column(
                        .meridiem,
                        values: CadenceTimeRollerModel.meridiemValues,
                        selection: $meridiem,
                        label: CadenceTimeRollerModel.meridiemLabel
                    )
                }
            }
        }
        .cadenceScaledTypography()
        .onAppear {
            seed(from: minutes)
            DispatchQueue.main.async { focusedColumn = .hour }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            isSeeding = false
        }
        .onChange(of: hour) { _, _ in write() }
        .onChange(of: minute) { _, _ in write() }
        .onChange(of: meridiem) { _, _ in write() }
        // An outside edit — the day picker moving a start, or a sibling row — must move the wheels
        // under it, or the control would go on showing the time it was opened at.
        .onChange(of: minutes) { _, newValue in
            guard newValue != composed else { return }
            seed(from: newValue)
        }
    }

    @ViewBuilder
    private func column(
        _ id: Column,
        values: [Int],
        selection: Binding<Int>,
        label: @escaping (Int) -> String
    ) -> some View {
        CadenceRollerColumn(
            values: values,
            label: label,
            selection: selection,
            isFocused: focusedColumn == id,
            // The time roller writes to a draft in memory rather than to a store, so there is no
            // refusal to wait for and no debt to redeem at the settle: the phase is accepted and
            // dropped. `EstimateRollerCommitGate` exists because that picker's committing form can
            // be told no.
            reportScrollPhase: { _ in },
            // Every column gets a floor, not only the meridiem one: under a squeezed popover a
            // column with no floor is the one that gives way ([[T-8471]]). `.enabled` because the
            // body declares `.cadenceScaledTypography()`, the scope the column's rows draw under.
            minimumWidth: CadenceTimeRollerModel.minimumColumnWidth(
                for: id,
                usesTwentyFourHourClock: usesTwentyFourHourClock,
                at: dynamicTypeSize,
                scaling: .enabled
            )
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focusedColumn, equals: id)
        .onKeyPress(.upArrow) { step(-1, in: values, selection: selection); return .handled }
        .onKeyPress(.downArrow) { step(1, in: values, selection: selection); return .handled }
        .onKeyPress(.leftArrow) { focusedColumn = previousColumn(before: id); return .handled }
        .onKeyPress(.rightArrow) { focusedColumn = nextColumn(after: id); return .handled }
        .onKeyPress(.return) { onSubmit(); return .handled }
        .accessibilityLabel(accessibilityLabel(for: id))
    }

    private func accessibilityLabel(for id: Column) -> String {
        switch id {
        case .hour: return "Hour"
        case .minute: return "Minute"
        case .meridiem: return "AM or PM"
        }
    }

    /// ←/→ stop at the ends rather than wrapping, matching the estimate roller's ↑/↓ rule: a
    /// control that jumps from the last column back to the first loses a value by overshooting.
    private func previousColumn(before id: Column) -> Column {
        switch id {
        case .hour: return .hour
        case .minute: return .hour
        case .meridiem: return .minute
        }
    }

    private func nextColumn(after id: Column) -> Column {
        switch id {
        case .hour: return .minute
        case .minute: return usesTwentyFourHourClock ? .minute : .meridiem
        case .meridiem: return .meridiem
        }
    }

    private var composed: Int {
        CadenceTimeRollerModel.minutes(
            hour: hour,
            minute: minute,
            meridiem: meridiem,
            usesTwentyFourHourClock: usesTwentyFourHourClock
        )
    }

    private func seed(from value: Int) {
        let parts = CadenceTimeRollerModel.components(
            fromMinutes: value,
            usesTwentyFourHourClock: usesTwentyFourHourClock
        )
        hour = parts.hour
        minute = parts.minute
        meridiem = parts.meridiem
    }

    private func step(_ delta: Int, in values: [Int], selection: Binding<Int>) {
        isSeeding = false
        withAnimation(.easeOut(duration: CadenceRollerMetrics.rowTransitionDuration)) {
            selection.wrappedValue = CadenceRollerMetrics.stepped(
                from: selection.wrappedValue,
                in: values,
                by: delta
            )
        }
    }

    private func write() {
        guard !isSeeding else { return }
        let value = composed
        guard value != minutes else { return }
        minutes = value
    }
}

/// A labelled field row whose value opens the time roller.
///
/// **Why this takes a `label:` and `CadenceStartTimeFieldRow` refuses one.** That component fixes
/// its word inside itself because it *is* the start row, and T-598(a) folded the literal in after
/// three sheets had each re-typed it under a different name. This row exists for the surfaces that
/// legitimately carry more than one time — a block with a Start **and** an End, a task with a Do
/// time — where a fixed word could only be wrong on the second row. The two are not duplicates: the
/// obvious next move, under [[T-3171]], is for `CadenceStartTimeFieldRow` to become this row with
/// `"Start"` passed in and its quarter-hour list popover retired, which is deliberately not done
/// here because it would change three sheets this ticket is not about.
struct CadenceTimeRollerFieldRow: View {
    let label: String
    var systemImage: String = "clock.fill"
    var color: Color = Theme.blue
    @Binding var minutes: Int

    @State private var isPickerPresented = false

    var body: some View {
        CadenceFieldRow(label: label, systemImage: systemImage, color: color) {
            CadenceChoiceValueButton(
                title: TimeFormatters.timeString(from: minutes),
                color: Theme.text
            ) {
                isPickerPresented = true
            }
            .popover(isPresented: $isPickerPresented) {
                CadenceTimeRoller(minutes: $minutes) {
                    isPickerPresented = false
                }
                .padding(CadenceRollerMetrics.panelPadding)
                .background(Theme.surfaceElevated)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

import SwiftUI

/// The one row that sets when something starts: a label, the current time, and the 15-minute
/// popover behind it.
///
/// **T-598(a).** Three sheets reachable from the one Calendar screen each spelled this row out —
/// `iOSCalendarQuickCreateSheet`, `iOSCalendarEventEditSheet` and `iOSCalendarBundleDetailSheet` —
/// with the same glyph, the same tint, the same `stride(from: 0, to: 1440, by: 15)` popover and the
/// same `TimeFormatters.timeString(from:)` on both the trigger and every row in the list. What
/// differed was the word: "Starts", "Time" and "Start". Open two of those sheets in a row and the
/// same control has been renamed twice.
///
/// **"Start" wins, and the label is not a parameter.** The other two rows in these sections are
/// "Date" and "Duration" — nouns naming the field, so "Starts" is the only verb on the card, and
/// "Time" is the only one that does not say *which* time next to a "Date" row that sets the other
/// half of the same instant. "Start" is also already what the block sheet says, so the winning
/// spelling is one that shipped rather than a fourth invention.
///
/// Being a fixed `static let` inside the component rather than an argument is the actual fix: a
/// `label:` parameter is how the app got three of them. The literal is five characters, which is
/// below `CadenceSharedConstantReuseSweepTests`' twelve-character floor, so a shared *constant*
/// could never have been armed against a call site re-typing it — folding the word into the one
/// component is the guard the constant could not be.
///
/// It owns its own presentation state. All three call sites carried a `@State showStartTimePicker`
/// used by nothing else in the file.
struct CadenceStartTimeFieldRow: View {
    /// The word every surface uses for this control. See the note above on why it is not a
    /// parameter.
    static let label = "Start"

    /// Minutes from midnight, matching `AppTask.scheduledStartMin` / `TaskBundle.startMin`.
    @Binding var minutes: Int

    @State private var isPickerPresented = false

    /// Every quarter hour of the day, which is the granularity all three sheets already offered.
    private static let selectableMinutes = Array(stride(from: 0, to: 24 * 60, by: 15))

    var body: some View {
        CadenceFieldRow(label: Self.label, systemImage: "clock.fill", color: Theme.blue) {
            CadenceChoiceValueButton(
                title: TimeFormatters.timeString(from: minutes),
                color: Theme.text
            ) {
                isPickerPresented = true
            }
            .popover(isPresented: $isPickerPresented) {
                CadenceChoicePopoverList(
                    rows: Self.selectableMinutes.map { minute in
                        CadenceChoiceRow(
                            value: minute,
                            title: TimeFormatters.timeString(from: minute),
                            color: Theme.blue
                        )
                    },
                    selection: $minutes,
                    isPresented: $isPickerPresented
                )
            }
        }
    }
}

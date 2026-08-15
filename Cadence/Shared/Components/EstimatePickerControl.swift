import SwiftUI

struct EstimatePickerControl: View {
    @Binding var value: Int
    /// Uppercase heading shown by the popover. Override when the control edits something other
    /// than a planning estimate (e.g. logged/actual time), so the panel does not claim to be
    /// editing a field it is not.
    var pickerTitle: String = "ESTIMATE"
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                // Neutral glyph. A blue timer on every task that has an estimate is a colour that
                // fires on the ordinary case; the text going from `dim` to `text` already says
                // whether there is a value. Colour in these surfaces is kept for what is wrong.
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // 44pt, not the 30pt desktop control height it was built at: every call site is under
            // `Cadence/iOS/` (macOS has its own roller behind `TaskInspectorEstimateChip`), and in
            // the task inspector this chip sits in the title row where a finger has to find it.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            EstimatePickerPopoverContent(value: $value, title: pickerTitle) {
                showPicker = false
            }
            // Same reason as `CadenceDatePicker`: compact width otherwise promotes this to a
            // full-height sheet wrapped around a 238pt panel, so a two-tap duration edit took over
            // the whole screen while every neighbouring picker stayed an anchored overlay.
            .presentationCompactAdaptation(.popover)
        }
    }

    private var label: String {
        value > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: value) : "No estimate"
    }
}

/// Shared duration editor. Quick presets plus separate hour / minute entry — the app never
/// asks for (or shows) a decimal hour.
struct EstimatePickerPopoverContent: View {
    @Binding var value: Int
    /// Uppercase heading. Defaults to the planning-estimate wording; callers that edit a
    /// different duration field (logged/actual time) pass their own so the panel is not
    /// mislabelled.
    var title: String = "ESTIMATE"
    var onSelect: () -> Void = {}

    @State private var hoursText = ""
    @State private var minutesText = ""

    private static let presets: [Int] = [15, 30, 45, 60, 120]
    /// Matches every other estimate entry point in the app (task-embed stepper, kanban card):
    /// a duration field tops out at 24h.
    private static let maxMinutes = 1440

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.54)

            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { minutes in
                    presetPill(minutes)
                }
            }

            HStack(spacing: 8) {
                unitField(text: $hoursText, unit: "h", placeholder: "0")
                unitField(text: $minutesText, unit: "m", placeholder: "0")
                Spacer(minLength: 0)
                Text(value > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: value) : "None")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            HStack(spacing: 8) {
                Button {
                    apply(0)
                    onSelect()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)

                Spacer(minLength: 0)

                Button {
                    commitFields()
                    onSelect()
                } label: {
                    Text("Set")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Theme.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(10)
        .frame(width: 238)
        .background(Theme.surfaceElevated)
        .onAppear { syncFields() }
        // Typed digits are deliberately NOT written through on every keystroke: doing so turns
        // typing "120" into three SwiftData mutations and three undo entries. The fields commit
        // on Set, on Return, and once more on dismiss so a click-away still saves.
        .onDisappear { commitFields() }
    }

    @ViewBuilder
    private func presetPill(_ minutes: Int) -> some View {
        let isSelected = value == minutes
        Button {
            apply(minutes)
            onSelect()
        } label: {
            Text(CadenceTaskPresentationSupport.estimateLabel(minutes: minutes))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.blue : Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(isSelected ? Theme.blue.opacity(0.14) : Theme.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
    }

    @ViewBuilder
    private func unitField(text: Binding<String>, unit: String, placeholder: String) -> some View {
        HStack(spacing: 3) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .frame(width: 26)
                .onSubmit { commitFields() }
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func apply(_ minutes: Int) {
        let clamped = min(max(0, minutes), Self.maxMinutes)
        // Guard the write so a no-op commit (Set with unchanged fields, dismiss after a preset)
        // does not push a redundant SwiftData mutation and undo entry.
        if value != clamped { value = clamped }
        syncFields()
    }

    private func syncFields() {
        hoursText = value >= 60 ? "\(value / 60)" : ""
        minutesText = value % 60 > 0 ? "\(value % 60)" : ""
    }

    /// Reads both fields, clamps, and writes once. Also rewrites the fields from the clamped
    /// value so an out-of-range entry visibly snaps back instead of silently disagreeing.
    private func commitFields() {
        let hours = Self.digits(hoursText)
        let minutes = Self.digits(minutesText)
        apply(hours * 60 + minutes)
    }

    private static func digits(_ text: String) -> Int {
        let filtered = text.filter(\.isNumber)
        guard !filtered.isEmpty else { return 0 }
        return Int(filtered.prefix(4)) ?? 0
    }
}

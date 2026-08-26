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
            // `Cadence/iOS/` (macOS opens the same roller from `TaskInspectorEstimateChip`), and in
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
            // full-height sheet wrapped around a 260pt panel, so a two-tap duration edit took over
            // the whole screen while every neighbouring picker stayed an anchored overlay.
            .presentationCompactAdaptation(.popover)
        }
    }

    private var label: String {
        value > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: value) : "No estimate"
    }
}

/// The app's **one** duration editor: the live total on top, an hours column stepping by 1 beside a
/// minutes column stepping by 5, then the presets.
///
/// It used to be two. macOS had this roller (as `TaskInspectorEstimateRollerPopover`); iOS had
/// preset chips over two typed number fields. They were recorded as a deliberate split and were
/// not one — the same field, edited two ways, drifting apart in exactly the way the kanban cards
/// and the two estimate pickers already had. The roller won on the user's call, and it is the
/// better of the two on both surfaces: the columns show the neighbouring values, so a duration is
/// adjusted by looking rather than by clearing a field and retyping it. The presets are not a
/// concession to touch — this roller always had them, and they stay the one-tap path to "30m" on
/// every platform.
///
/// What iOS gives up is arbitrary minutes: the minutes column steps by 5, so a typed 7 is no
/// longer expressible there (it never was on macOS). An off-step value already on the task is
/// **shown** and not silently rounded — see `isSeeding`.
///
/// SwiftUI has no wheel picker on macOS, so each column is a `ScrollView` whose *centred* row is
/// read back through `scrollPosition(id:anchor:)`. That keeps real trackpad/scroll-wheel input
/// working — a custom drag-driven offset would only answer to click-drags, since SwiftUI exposes
/// no scroll-wheel event — while `.onKeyPress` on the focused column handles ↑/↓ to step it and
/// ←/→ to move between the two. On touch the same scroll view is dragged directly.
struct EstimatePickerPopoverContent: View {
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

    private static let hourValues = EstimateRollerMetrics.hourValues
    private static let minuteValues = EstimateRollerMetrics.minuteValues
    private static let presets = EstimateRollerMetrics.presets

    /// Plate height for the presets and the footer buttons — the same on both platforms, because
    /// the two surfaces are meant to look alike.
    private static let presetPlateHeight: CGFloat = 24
    private static let footerPlateHeight: CGFloat = 26

    private var total: Int { EstimateRollerMetrics.total(hours: hours, minutes: minutes) }

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
            SectionEyebrowLabel(text: title, size: .compact)

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
                        .frame(height: Self.presetPlateHeight)
                        .background(isSelected ? Theme.blue.opacity(0.14) : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .estimatePickerTouchTarget(plateHeight: Self.presetPlateHeight)
                }
                .buttonStyle(.plain)
                // One hover layer, at the plate's own radius — see the standing rule. It resolves
                // to nothing on touch, where there is no pointer to track.
                .cadenceHoverHighlight(cornerRadius: 6, fillColor: Theme.surfaceElevated, strokeColor: .clear)
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
                    .frame(height: Self.footerPlateHeight)
                    .estimatePickerTouchTarget(plateHeight: Self.footerPlateHeight)
            }
            .buttonStyle(.plain)
            .cadenceHoverHighlight(cornerRadius: 6, fillColor: Theme.surfaceElevated, strokeColor: .clear)

            Spacer(minLength: 0)

            Button {
                commit(force: true)
                onClose()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 12)
                    .frame(height: Self.footerPlateHeight)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .estimatePickerTouchTarget(plateHeight: Self.footerPlateHeight)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Edits

    private func seed(from minutesValue: Int) {
        let columns = EstimateRollerMetrics.columns(forTotal: minutesValue)
        hours = columns.hours
        minutes = columns.minutes
    }

    private func step(_ delta: Int, in values: [Int], selection: Binding<Int>) {
        isSeeding = false
        withAnimation(.easeOut(duration: 0.12)) {
            selection.wrappedValue = EstimateRollerMetrics.stepped(
                from: selection.wrappedValue,
                in: values,
                by: delta
            )
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

/// The **testable** half of the roller: the geometry and stepping rules the view reads, kept out
/// of the view so a macOS surface that cannot be screenshotted from an agent shell can still be
/// pinned by unit tests.
enum EstimateRollerMetrics {
    // MARK: Values

    static let hourValues = Array(0...24)
    static let minuteValues = Array(stride(from: 0, through: 55, by: 5))
    /// One tap for the durations actually chosen. The roller has always carried these; they are
    /// what a wheel alone does not give, and they are the reason the iOS preset chips could be
    /// dropped without losing anything.
    static let presets: [Int] = [15, 30, 45, 60, 90]
    /// Matches every other estimate entry point in the app: a duration field tops out at 24h.
    static let maxMinutes = 1440

    /// What the two columns read for a stored value, clamped to the range the roller can express.
    ///
    /// Minutes are **floored** to a step the column actually carries rather than rounded, so
    /// opening the picker on an off-step value (focus-logged "Actual" minutes are rarely multiples
    /// of five) can never round it *up* past what the user recorded.
    static func columns(forTotal minutes: Int) -> (hours: Int, minutes: Int) {
        let clamped = min(max(0, minutes), maxMinutes)
        return (clamped / 60, (clamped % 60) / 5 * 5)
    }

    /// The value the two columns add up to, clamped the same way.
    static func total(hours: Int, minutes: Int) -> Int {
        min(max(0, hours * 60 + minutes), maxMinutes)
    }

    /// One ↑/↓ press: move `delta` rows within `values` without wrapping, because a wheel that
    /// jumps from 24h to 0h on one more press is a wheel that loses a value by overshooting.
    static func stepped(from value: Int, in values: [Int], by delta: Int) -> Int {
        guard let index = values.firstIndex(of: value) else { return values.first ?? 0 }
        return values[min(max(0, index + delta), values.count - 1)]
    }

    // MARK: Geometry

    /// Row height in a roller column. Deliberately the same on pointer and touch: a roller is
    /// scrolled, not tapped row by row, so there is no per-row hit target to grow and no reason to
    /// make the wheel two and a half times taller on a phone.
    static let rowHeight: CGFloat = 26
    static let visibleRows: CGFloat = 5

    /// Apple's minimum comfortable touch target. Controls that *are* tapped — the presets, Clear,
    /// Done — reach this on touch without their plates growing.
    static let touchTargetHeight: CGFloat = 44

    /// Whether the running platform is driven by a finger. The two rules below take it as an
    /// argument so both branches are reachable from the macOS-only test target — this panel's
    /// touch behaviour would otherwise be unpinnable by anything but a screenshot.
    static let isTouchInput: Bool = {
        #if os(macOS)
        false
        #else
        true
        #endif
    }()

    /// How far one gesture may carry a column.
    ///
    /// `.viewAligned` snaps to a row but says nothing about distance, so on a trackpad a light
    /// flick's momentum crosses a dozen values, which reads as the control running away from you.
    /// Clamping the landing point keeps a flick feeling like a nudge.
    ///
    /// Touch needs a far larger allowance for the opposite reason: a finger drags the content 1:1,
    /// so a clamp tight enough to tame trackpad momentum makes a deliberate 200pt drag spring back
    /// to three rows under the finger that made it. Same rule, different input device — not a
    /// different design.
    static func maxRowsPerGesture(isTouch: Bool = isTouchInput) -> CGFloat {
        isTouch ? 12 : 3
    }

    /// The height a tappable control occupies so its hit area reaches `touchTargetHeight`, given
    /// the height of the plate actually drawn. On a pointer the answer is always the plate itself:
    /// the plate never changes size, only the region that answers for it.
    static func hitHeight(plateHeight: CGFloat, isTouch: Bool = isTouchInput) -> CGFloat {
        isTouch ? max(plateHeight, touchTargetHeight) : plateHeight
    }
}

private extension View {
    /// Grows the *hit area* around a control to `EstimateRollerMetrics.touchTargetHeight` on touch
    /// while leaving the drawn plate the size it is, so the panel looks identical on both
    /// platforms and only answers to a wider region on the one with fingers.
    func estimatePickerTouchTarget(plateHeight: CGFloat) -> some View {
        frame(height: EstimateRollerMetrics.hitHeight(plateHeight: plateHeight))
            .contentShape(Rectangle())
    }
}

/// Caps how far one gesture can carry the roller, and lands it on a whole row.
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

/// One roller column. The centre band is drawn *behind* the scrolling rows so it tints the well
/// rather than the glyphs sitting in it.
private struct EstimateRollerColumn: View {
    let values: [Int]
    let unit: String
    @Binding var selection: Int
    let isFocused: Bool

    private static let cornerRadius: CGFloat = 8

    private var rowHeight: CGFloat { EstimateRollerMetrics.rowHeight }
    private var viewportHeight: CGFloat { rowHeight * EstimateRollerMetrics.visibleRows }

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
                        .frame(height: rowHeight)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(
            EstimateRollerScrollBehavior(
                rowHeight: rowHeight,
                maxRowsPerGesture: EstimateRollerMetrics.maxRowsPerGesture()
            )
        )
        // Lets the first and last rows reach the centre band instead of stopping at the edges.
        .contentMargins(.vertical, (viewportHeight - rowHeight) / 2, for: .scrollContent)
        .scrollPosition(id: centeredValue, anchor: .center)
        .frame(height: viewportHeight)
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.blue.opacity(0.12))
                .frame(height: rowHeight)
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

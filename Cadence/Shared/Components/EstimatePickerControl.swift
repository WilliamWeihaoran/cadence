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
        CadenceTaskPresentationSupport.estimateValueLabel(minutes: value)
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
    /// **T-761(b).** `nil` on the draft form: `value`'s own setter is the only write, so nothing
    /// here can be refused and closing stays unconditional. Non-`nil` on the committing form: this
    /// answers whether the write landed, and every button below closes only when it does — same
    /// shape as `CadenceChoicePopoverList`'s two initialisers, and for the same reason a `Binding`
    /// beside it would be two write paths, and a mutation hidden in the binding's setter is exactly
    /// what T-656 could not see. Named `onCommit` rather than `select` (`CadenceChoicePopoverList`'s
    /// own name for the same role): `CadenceChoicePickerDismissalTests`' census counts a `select:`
    /// argument anywhere in a file as evidence of *that* component, and this is a different one.
    private let onCommit: ((Int) -> Bool)?
    /// Shown under the footer when `onCommit` refuses. `nil` on every draft caller.
    var failureNotice: String?

    /// The draft form. `value`'s setter is the only write, so every close is unconditional.
    init(value: Binding<Int>, title: String = "ESTIMATE", onClose: @escaping () -> Void = {}) {
        self._value = value
        self.title = title
        self.onClose = onClose
        self.onCommit = nil
        self.failureNotice = nil
    }

    /// The committing form. `value` is read-only here — it only seeds the rollers' starting
    /// position — and `onCommit` is the only write.
    init(
        value: Int,
        title: String = "ESTIMATE",
        failureNotice: String? = nil,
        onClose: @escaping () -> Void = {},
        onCommit: @escaping (Int) -> Bool
    ) {
        self._value = .constant(value)
        self.title = title
        self.onClose = onClose
        self.onCommit = onCommit
        self.failureNotice = failureNotice
    }

    private enum RollerColumn: Hashable { case hours, minutes }

    @State private var hours = 0
    @State private var minutes = 0
    /// The scroll positions report their centred row a beat *after* layout. Until that has
    /// settled, a reported change is the picker seeding itself rather than an edit — committing
    /// it would silently round an off-step value (focus-logged "Actual" minutes are rarely
    /// multiples of 5) merely because the popover was opened.
    @State private var isSeeding = true
    /// Whichever of `commit(force:)`'s three writers ran most recently. Read only by
    /// `closeIfLanded()`, so a caller that presses Done a beat after a live scroll's own commit
    /// was refused still gets the refusal rather than a stale success.
    @State private var lastCommitLanded = true
    @FocusState private var focusedColumn: RollerColumn?

    private static let hourValues = EstimateRollerMetrics.hourValues
    private static let minuteValues = EstimateRollerMetrics.minuteValues
    private static let presets = EstimateRollerMetrics.presets

    // The preset and footer plate heights used to be declared here. They are
    // `EstimateRollerMetrics.presetPlateHeight` / `.footerPlateHeight` now, beside the `at:scaling:`
    // forms the body actually reads — a base and its curve have to be one decision, and the macOS
    // test target can only reach the metrics type.

    /// **T-1410.** The panel declares `.cadenceScaledTypography()` below, so every number it draws
    /// names `.enabled` rather than reading a flag back: this is the declaration, and a converted
    /// panel is converted wherever it is opened from.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var total: Int { EstimateRollerMetrics.total(hours: hours, minutes: minutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: EstimateRollerMetrics.blockSpacing) {
            header
            rollers
            presetRow

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            footer
        }
        .padding(EstimateRollerMetrics.panelPadding)
        .frame(width: EstimateRollerMetrics.panelWidth(at: dynamicTypeSize, scaling: .enabled))
        .background(Theme.surfaceElevated)
        // **T-1410, replacing T-1398's pin.** T-1398 found the eyebrow in the header growing to
        // ~28pt over roller rows fixed at 26 inside a literal 260pt panel, and stopped it by saying
        // `.fixed` — which left the reader a scaled detail sheet opening an unscaled duration
        // editor. `EstimateRollerMetrics` grew with it now: the panel widens by what a roller label
        // gained, each row grows the same way and the column shows three of them instead of five,
        // the presets reflow to two columns, and the header stacks. Nothing in here is a literal
        // the type can outgrow.
        .cadenceScaledTypography()
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
        if EstimateRollerMetrics.headerIsStacked(at: dynamicTypeSize, scaling: .enabled) {
            VStack(alignment: .leading, spacing: 4) {
                headingLabel
                totalLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                headingLabel
                Spacer(minLength: 0)
                totalLabel
            }
        }
    }

    /// One call site for the shared eyebrow, not one per arrangement — the two branches above are
    /// a layout decision and must not become two spellings of the label.
    /// `CadenceCompactEyebrowConvergenceTests` counts this file's calls and is what says so.
    private var headingLabel: some View {
        SectionEyebrowLabel(text: title, size: .compact)
    }

    /// The live total. `lineLimit(1)` with **no** `minimumScaleFactor`: shrinking a duration back
    /// down to fit is the one thing a reader who enlarged their text did not ask for.
    private var totalLabel: some View {
        Text(total > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: total) : "None")
            .cadenceFont(.fieldValue, base: EstimateRollerMetrics.totalLabelSize)
            .foregroundStyle(total > 0 ? Theme.text : Theme.dim)
            .monospacedDigit()
            .lineLimit(1)
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
        .onKeyPress(.return) { closeIfLanded(); return .handled }
    }

    /// **A grid rather than a row, because five chips across one line is a count the type can
    /// outgrow.** At every size the app was drawn at this is five flexible columns with the same
    /// spacing the `HStack` had, so it lays out identically; at an accessibility size it is two,
    /// and the five presets wrap onto three lines instead of truncating to three characters each.
    @ViewBuilder
    private var presetRow: some View {
        let plateHeight = EstimateRollerMetrics.presetPlateHeight(at: dynamicTypeSize, scaling: .enabled)
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: EstimateRollerMetrics.presetSpacing),
                count: EstimateRollerMetrics.presetColumns(at: dynamicTypeSize, scaling: .enabled)
            ),
            spacing: EstimateRollerMetrics.presetSpacing
        ) {
            ForEach(Self.presets, id: \.self) { preset in
                let isSelected = total == preset
                Button {
                    apply(preset)
                    closeIfLanded()
                } label: {
                    Text(CadenceTaskPresentationSupport.estimateLabel(minutes: preset))
                        .cadenceFont(.metadata, base: EstimateRollerMetrics.presetLabelSize)
                        .foregroundStyle(isSelected ? Theme.blue : Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: plateHeight)
                        .background(isSelected ? Theme.blue.opacity(0.14) : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .estimatePickerTouchTarget(plateHeight: plateHeight)
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
        let plateHeight = EstimateRollerMetrics.footerPlateHeight(at: dynamicTypeSize, scaling: .enabled)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    apply(0)
                    closeIfLanded()
                } label: {
                    Text("Clear")
                        .cadenceFont(.metadata, base: EstimateRollerMetrics.footerLabelSize)
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 10)
                        .frame(height: plateHeight)
                        .estimatePickerTouchTarget(plateHeight: plateHeight)
                }
                .buttonStyle(.plain)
                .cadenceHoverHighlight(cornerRadius: 6, fillColor: Theme.surfaceElevated, strokeColor: .clear)

                Spacer(minLength: 0)

                Button {
                    commit(force: true)
                    closeIfLanded()
                } label: {
                    Text("Done")
                        .cadenceFont(.metadata, base: EstimateRollerMetrics.footerLabelSize, weight: .semibold)
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 12)
                        .frame(height: plateHeight)
                        .background(Theme.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .estimatePickerTouchTarget(plateHeight: plateHeight)
                }
                .buttonStyle(.plain)
            }

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
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

    /// **T-761(b).** Answers whether the value is in the store, and records it in
    /// `lastCommitLanded` so every button below can gate its own close on the same answer without
    /// re-deriving it. `true` when nothing needed writing — the draft form's old behaviour, and
    /// still correct for the committing form: nothing was written, so nothing could be refused.
    @discardableResult
    private func commit(force: Bool = false) -> Bool {
        guard force || !isSeeding else { return true }
        guard value != total else {
            lastCommitLanded = true
            return true
        }
        guard let onCommit else {
            value = total
            lastCommitLanded = true
            return true
        }
        let landed = onCommit(total)
        lastCommitLanded = landed
        return landed
    }

    /// The one place a button closes the popover, so a refusal recorded anywhere above — a live
    /// scroll's own commit, not just the tap that is closing now — keeps it open.
    private func closeIfLanded() {
        guard lastCommitLanded else { return }
        onClose()
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

    // MARK: Geometry once the reader has a text size (T-1410)
    //
    // **Why this panel is intrinsically sized and does NOT become a capped scroll.** Its two roller
    // columns are themselves vertical `ScrollView`s, so wrapping the panel in another one — which
    // is what `CadenceFittedPopover` does, and what that panel is right to do — would nest a
    // vertical scroll inside a vertical scroll over the control the reader is dragging. The height
    // is bounded a different way instead: each roller row grows with its type and the column shows
    // **fewer** of them, so the wheel never becomes a screen of its own. Everything else in here
    // grows additively, so the panel's whole height stays inside a phone at every size —
    // `EstimatePickerLargeTextLayoutTests` is what holds that rather than an eye.

    /// The panel's width at the default size, and what it widens to.
    static let panelWidth: CGFloat = 260
    /// Interior padding on all four sides, and the gap between stacked blocks.
    static let panelPadding: CGFloat = 10
    static let blockSpacing: CGFloat = 10
    /// The font the roller rows and the columns are drawn at.
    static let rowLabelSize: CGFloat = 13
    /// The live total beside the heading.
    static let totalLabelSize: CGFloat = 15
    static let presetLabelSize: CGFloat = 10
    static let footerLabelSize: CGFloat = 11
    static let presetPlateHeight: CGFloat = 24
    static let footerPlateHeight: CGFloat = 26
    static let presetSpacing: CGFloat = 5

    static func panelWidth(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(panelWidth, holding: .controlLabel, textBase: rowLabelSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// A roller row grows by what its label gained: 26pt around a 13pt value is 13pt of well, and
    /// a well does not need to triple for the value in it to stop overlapping its neighbour.
    static func rowHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(rowHeight, holding: .controlLabel, textBase: rowLabelSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// Five neighbouring values at the sizes the wheel was drawn at; three once each row is roughly
    /// twice as tall.
    ///
    /// This is the decision that keeps the panel a panel. A wheel is read by seeing the values
    /// *around* the chosen one, and three is the smallest count that still shows one either side —
    /// so the affordance survives while the viewport does not double.
    static func visibleRows(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) else { return visibleRows }
        return 3
    }

    static func viewportHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        rowHeight(at: dynamicTypeSize, scaling: scaling) * visibleRows(at: dynamicTypeSize, scaling: scaling)
    }

    static func presetPlateHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(presetPlateHeight, holding: .metadata, textBase: presetLabelSize, at: dynamicTypeSize, scaling: scaling)
    }

    static func footerPlateHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(footerPlateHeight, holding: .metadata, textBase: footerLabelSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// The presets reflow rather than shrink. Five "1h 30m" chips across a 285pt panel is 44pt
    /// each, which holds a 10pt label and not a 31pt one; two columns and three rows is the same
    /// five one-tap durations at a size they can be read at.
    static func presetColumns(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Int {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) else { return presets.count }
        return 2
    }

    static func presetRows(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Int {
        let columns = presetColumns(at: dynamicTypeSize, scaling: scaling)
        return (presets.count + columns - 1) / columns
    }

    /// The heading and the live total sit on one baseline until they stop fitting beside each
    /// other, and then the total moves under the heading.
    ///
    /// Measured against the panel rather than guessed: "ESTIMATE" is eight uppercase kerned
    /// characters and the total is up to six monospaced digits and units, and at an accessibility
    /// size the two together are wider than the panel they head.
    static func headerIsStacked(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Bool {
        scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
    }

    /// What the whole panel occupies, block by block, so "does the duration editor still fit on a
    /// phone at the largest text size" is a question a unit test can answer.
    static func panelHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let eyebrow = CadenceTypeScale.lineHeight(
            .sectionLabel,
            base: SectionEyebrowLabel.compactFontSize,
            at: dynamicTypeSize,
            scaling: scaling
        )
        let total = CadenceTypeScale.lineHeight(.fieldValue, base: totalLabelSize, at: dynamicTypeSize, scaling: scaling)
        let header = headerIsStacked(at: dynamicTypeSize, scaling: scaling)
            ? eyebrow + 4 + total
            : max(eyebrow, total)
        let presetBlock = CGFloat(presetRows(at: dynamicTypeSize, scaling: scaling))
            * presetPlateHeight(at: dynamicTypeSize, scaling: scaling)
            + CGFloat(presetRows(at: dynamicTypeSize, scaling: scaling) - 1) * presetSpacing
        return panelPadding * 2
            + header
            + blockSpacing + viewportHeight(at: dynamicTypeSize, scaling: scaling)
            + blockSpacing + presetBlock
            + blockSpacing + 1
            + blockSpacing + footerPlateHeight(at: dynamicTypeSize, scaling: scaling)
    }

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

    /// The column is drawn inside `EstimatePickerPopoverContent`'s declared scope, so these read
    /// the flag back rather than naming it: the panel is the declaration and this is a private part
    /// of it, which is why the two cannot disagree.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var rowHeight: CGFloat { EstimateRollerMetrics.rowHeight(at: dynamicTypeSize, scaling: scaling) }
    private var viewportHeight: CGFloat { EstimateRollerMetrics.viewportHeight(at: dynamicTypeSize, scaling: scaling) }

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
                        .cadenceFont(
                            .controlLabel,
                            base: EstimateRollerMetrics.rowLabelSize,
                            weight: item == selection ? .semibold : .regular
                        )
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
                .strokeBorder(isFocused ? Theme.blue.opacity(0.5) : Theme.borderSubtle, lineWidth: 1)
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

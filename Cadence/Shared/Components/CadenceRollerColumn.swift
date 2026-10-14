import SwiftUI

/// The roller **column** — one vertical wheel — pulled out of `EstimatePickerControl` so that the
/// app has one of them rather than one per thing that needs rolling (T-3169/[[T-3171]]).
///
/// **This mechanism already existed and was already right; the only thing wrong with it was that it
/// was private.** The estimate picker's own note states the hard part and the answer:
///
/// > *SwiftUI has no wheel picker on macOS, so each column is a `ScrollView` whose centred row is
/// > read back through `scrollPosition(id:anchor:)`. That keeps real trackpad/scroll-wheel input
/// > working — a custom drag-driven offset would only answer to click-drags, since SwiftUI exposes
/// > no scroll-wheel event — while `.onKeyPress` on the focused column handles ↑/↓ to step it and
/// > ←/→ to move between the two. On touch the same scroll view is dragged directly.*
///
/// A second hand-rolled wheel in the tree would have had to rediscover all of that, and would have
/// been the fourth near-copy this repository's standing rule exists to prevent. So the hour/minute
/// time roller is **this** column three times over, not a new one.
///
/// ## What was factored out, and what deliberately was not
///
/// Out: the column view and its `ScrollTargetBehavior`, with the one estimate-specific thing in the
/// row — a `unit` string appended to the number — replaced by a `label` closure, which is what lets
/// a column print `04`, `1`, `AM` or `45m` from the same code.
///
/// Not out: the **geometry**. `EstimateRollerMetrics` owns the row height, the viewport, the
/// type-scaling curve and the per-gesture row cap, every one of which is a fact about a roller
/// rather than about a duration, and all of it is already pinned by `EstimatePickerLargeTextLayoutTests`.
/// Moving those constants would churn a tested type for a rename and give the app two places a row
/// height could be set. `CadenceRollerMetrics` below is a name, not a copy: one type, read by both
/// rollers, so the shared column does not have to say "Estimate" to ask how tall a row is.
typealias CadenceRollerMetrics = EstimateRollerMetrics

/// Caps how far one gesture can carry a roller, and lands it on a whole row.
///
/// Moved verbatim from `EstimatePickerControl`; it was never about estimates.
struct CadenceRollerScrollBehavior: ScrollTargetBehavior {
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
///
/// The column decides nothing about writes: it reports its scroll phase and its centred row, and
/// the panel above it owns when either becomes a value. That separation is `EstimateRollerCommitGate`'s
/// and is why a roll is one write rather than one per row it crosses.
struct CadenceRollerColumn: View {
    let values: [Int]
    /// How a value is printed. The estimate roller passes `"\($0)h"`; the time roller passes a
    /// zero-padded minute, a bare hour, or `AM`/`PM`.
    let label: (Int) -> String
    @Binding var selection: Int
    let isFocused: Bool
    /// `ScrollPhase.isScrolling`, forwarded up.
    let reportScrollPhase: (Bool) -> Void
    /// Width hint for a narrow column — the meridiem wheel does not need an hour's worth of well.
    var minimumWidth: CGFloat?

    private static let cornerRadius: CGFloat = 8

    /// Read back rather than named: the column is drawn inside its panel's declared scope, so the
    /// two cannot disagree about whether type is scaling.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var rowHeight: CGFloat {
        CadenceRollerMetrics.rowHeight(at: dynamicTypeSize, scaling: scaling)
    }

    private var viewportHeight: CGFloat {
        CadenceRollerMetrics.viewportHeight(at: dynamicTypeSize, scaling: scaling)
    }

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
                    Text(label(item))
                        .cadenceFont(
                            .controlLabel,
                            base: CadenceRollerMetrics.rowLabelSize,
                            weight: item == selection ? .semibold : .regular
                        )
                        .foregroundStyle(item == selection ? Theme.text : Theme.muted)
                        .monospacedDigit()
                        .opacity(opacity(for: item))
                        // The ramp and the tint ease instead of switching in one frame, which is
                        // what made a scroll feel stepped while ↑/↓ did not. The weight swap above
                        // is a *font*, which SwiftUI cannot interpolate: it snaps as it always did
                        // rather than paying to re-lay-out the text on every row the centre crosses.
                        .animation(
                            .easeOut(duration: CadenceRollerMetrics.rowTransitionDuration),
                            value: selection
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(
            CadenceRollerScrollBehavior(
                rowHeight: rowHeight,
                maxRowsPerGesture: CadenceRollerMetrics.maxRowsPerGesture()
            )
        )
        // Lets the first and last rows reach the centre band instead of stopping at the edges.
        .contentMargins(.vertical, (viewportHeight - rowHeight) / 2, for: .scrollContent)
        .scrollPosition(id: centeredValue, anchor: .center)
        .onScrollPhaseChange { _, phase in
            reportScrollPhase(phase.isScrolling)
        }
        .frame(height: viewportHeight)
        .frame(minWidth: minimumWidth)
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

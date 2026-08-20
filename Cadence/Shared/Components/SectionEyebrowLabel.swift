import SwiftUI

/// Small-caps "eyebrow" section label (e.g. STATUS, COLOR, UNASSIGNED) used above
/// filter groups, form fields, and card headers. Consolidates several near-identical
/// one-off label styles into a single consistent size/weight/kerning.
struct SectionEyebrowLabel: View {
    /// The app's one eyebrow size. Exposed because things drawn *beside* an eyebrow have to agree
    /// with it — `CadenceBoardColumnHeaderMetrics.labelSize` and
    /// `CadenceTaskGroupHeadingMetrics.countSize` are both this number, and both were a
    /// hand-typed 10 or 11 before somebody noticed which one they were meant to match.
    /// `nonisolated` because `CadenceTaskGroupHeadingMetrics` is, and a nonisolated value type
    /// cannot read a main-actor-isolated static. A literal, so there is nothing to initialise from.
    nonisolated static let fontSize: CGFloat = 10

    let text: String
    var tint: Color = Theme.dim

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: Self.fontSize, weight: .semibold))
            .foregroundStyle(tint)
            .kerning(0.8)
    }
}

import SwiftUI

/// Small-caps "eyebrow" section label (e.g. STATUS, COLOR, UNASSIGNED) used above
/// filter groups, form fields, and card headers. Consolidates several near-identical
/// one-off label styles into a single consistent size/weight/kerning.
struct SectionEyebrowLabel: View {
    let text: String
    var tint: Color = Theme.dim

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .kerning(0.8)
    }
}

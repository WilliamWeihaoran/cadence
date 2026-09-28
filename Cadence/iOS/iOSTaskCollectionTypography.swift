import SwiftUI

/// Shared page chrome can be prepared before its callers opt into scaling.
nonisolated enum iOSTaskPageTypographyMetrics {
    static func stacksControls(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> Bool {
        scaling == .enabled && CadenceTypeScale.isAccessibilitySize(size)
    }

    static func segmentHeight(fillsWidth: Bool, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.height(fillsWidth ? 44 : 38, holding: .metadata, at: size, scaling: scaling)
    }

    static func glyphFrame(_ base: CGFloat, glyph: CGFloat, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.height(base, holding: .controlLabel, textBase: glyph, at: size, scaling: scaling)
    }

    static func swipeLabelLineLimit(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> Int {
        scaling == .enabled && size > .large ? 2 : 1
    }

    static func swipeTrayHeight(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        guard scaling == .enabled else { return 0 }
        let glyph = CadenceTypeScale.lineHeight(.metadata, base: 16, at: size, scaling: scaling)
        let label = stacksControls(at: size, scaling: scaling)
            ? 0 : CadenceTypeScale.lineHeight(.metadata, base: 11, at: size, scaling: scaling)
                * CGFloat(swipeLabelLineLimit(at: size, scaling: scaling))
        // The 4pt stack gap plus 2pt clearance above and below; one line still fits the old 44pt row.
        return max(44, glyph + label + 8)
    }
}

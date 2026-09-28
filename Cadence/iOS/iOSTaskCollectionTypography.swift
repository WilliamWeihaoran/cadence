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
}

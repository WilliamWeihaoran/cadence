import Foundation
import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexTaskPageTypographyTests {
    private let glyphFrames: [(CGFloat, CGFloat)] = [(30, 17), (38, 17), (38, 14), (30, 11), (44, 15)]

    @Test func codexPageChromeRetainsItsFixedMetricsAtAllTwelveSizes() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            #expect(!iOSTaskPageTypographyMetrics.stacksControls(at: size, scaling: .fixed))
            #expect(iOSTaskPageTypographyMetrics.segmentHeight(fillsWidth: false, at: size, scaling: .fixed) == 38)
            #expect(iOSTaskPageTypographyMetrics.segmentHeight(fillsWidth: true, at: size, scaling: .fixed) == 44)
            for (frame, glyph) in glyphFrames {
                #expect(iOSTaskPageTypographyMetrics.glyphFrame(frame, glyph: glyph, at: size, scaling: .fixed) == frame)
                #expect(CadenceTypeScale.size(.controlLabel, base: glyph, at: size, scaling: .fixed) == glyph)
            }
            for role in CadencePageHeaderRole.allCases {
                for regular in [false, true] {
                    let metrics = CadencePageHeaderMetrics.metrics(role: role, isRegularWidth: regular)
                    #expect(CadenceTypeScale.size(.editorTitle, base: metrics.titleSize, at: size, scaling: .fixed) == metrics.titleSize)
                    #expect(CadenceTypeScale.size(.sectionLabel, base: metrics.eyebrowSize, at: size, scaling: .fixed) == metrics.eyebrowSize)
                    #expect(CadenceTypeScale.size(.metadata, base: metrics.countSize, at: size, scaling: .fixed) == metrics.countSize)
                }
            }
            let labelBases: [CGFloat] = [11, 12]
            for base in labelBases {
                #expect(CadenceTypeScale.size(.metadata, base: base, at: size, scaling: .fixed) == base)
            }
        }
    }

    @Test func codexPageChromeHasARealScaledAlternativeAndRoomForItsGlyphs() {
        for size in DynamicTypeSize.allCases {
            #expect(iOSTaskPageTypographyMetrics.stacksControls(at: size, scaling: .enabled)
                == CadenceTypeScale.isAccessibilitySize(size))
            let line = CadenceTypeScale.lineHeight(.metadata, at: size, scaling: .enabled)
            let paddedLine: CGFloat = line + 12
            #expect(iOSTaskPageTypographyMetrics.segmentHeight(fillsWidth: false, at: size, scaling: .enabled) >= paddedLine)
            for (frame, glyph) in glyphFrames {
                #expect(iOSTaskPageTypographyMetrics.glyphFrame(frame, glyph: glyph, at: size, scaling: .enabled)
                    >= CadenceTypeScale.lineHeight(.controlLabel, base: glyph, at: size, scaling: .enabled))
            }
        }
        #expect(iOSTaskPageTypographyMetrics.segmentHeight(fillsWidth: false, at: .accessibility5, scaling: .enabled) > 38)
        #expect(iOSTaskPageTypographyMetrics.glyphFrame(30, glyph: 17, at: .accessibility5, scaling: .enabled) > 30)
    }

    @Test func codexPageChromeRoutesFontsAndFramesThroughTheSameScope() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let header = try read("Cadence/iOS/iOSFeatureComponents.swift")
        let controls = try read("Cadence/iOS/iOSDesignSystem.swift")
        #expect(header.contains("struct iOSPageHeader<Trailing: View>"))
        #expect(controls.contains("struct iOSSegmentedPill: View"))
        #expect(header.contains(".cadenceFont(.editorTitle, base: metrics.titleSize, weight: .bold)"))
        #expect(header.contains(".cadenceFont(.metadata, base: metrics.countSize, weight: .bold)"))
        #expect(header.contains(".cadenceFont(.sectionLabel, base: metrics.eyebrowSize, weight: .medium)"))
        #expect(header.contains(".lineLimit(stacksControls ? nil : 1)"))
        #expect(header.contains("if stacksControls {"))
        #expect(header.contains("iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)"))
        #expect(controls.contains("? AnyLayout(VStackLayout(spacing: 3))"))
        #expect(controls.contains(".lineLimit(stacks ? nil : (fillsWidth ? 2 : 1))"))
        #expect(controls.contains("minHeight: iOSTaskPageTypographyMetrics.segmentHeight(fillsWidth: fillsWidth, at: dynamicTypeSize, scaling: scaling)"))
        #expect(controls.contains(".cadenceFont(.metadata, weight: isSelected ? .bold : .semibold)"))
        #expect(controls.contains(".frame(width: side, height: side)"))
        #expect(controls.contains("iOSTaskPageTypographyMetrics.glyphFrame(plateSize, glyph: iconSize, at: dynamicTypeSize, scaling: scaling)"))
        #expect(controls.contains("width: iOSTaskPageTypographyMetrics.glyphFrame(30, glyph: 17, at: dynamicTypeSize, scaling: scaling)"))
        #expect(controls.contains("height: iOSTaskPageTypographyMetrics.glyphFrame(38, glyph: 17, at: dynamicTypeSize, scaling: scaling)"))
        #expect(controls.contains(".cadenceFont(.controlLabel, base: 17, weight: .semibold)"))
        #expect(controls.contains(".cadenceFont(.metadata, base: 11, weight: .semibold)"))
        for source in [header, controls] {
            #expect(source.contains("@Environment(\\.cadenceTypographyScaling)"))
            #expect(!source.contains(".cadenceScaledTypography()"))
            #expect(!source.contains(".cadenceFixedTypography()"))
        }
    }
}

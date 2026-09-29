import SwiftUI
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexLineHeightTests {
    private let sizes = DynamicTypeSize.allCases

    @Test func codexChipLineBoxUsesTheSharedRatioAtEverySize() {
        #expect(sizes.count == 12)
        let compact: [CGFloat] = [10, 11, 12, 12, 14, 15, 17, 20, 24, 29, 34, 37]
        let regular: [CGFloat] = [12, 13, 14, 15, 17, 18, 20, 24, 28, 34, 40, 45]
        for (index, size) in sizes.enumerated() {
            for chipSize in CadenceTagChipSize.allCases {
                for input in CadenceTagChipInput.allCases {
                    for scaling in CadenceTypographyScaling.allCases {
                        let style = CadenceTagChipStyle(size: chipSize, isArchived: false, input: input,
                                                       dynamicTypeSize: size, scaling: scaling)
                        let line: CGFloat = scaling == .fixed
                            ? (chipSize == .compact ? 12 : 15)
                            : (chipSize == .compact ? compact[index] : regular[index])
                        #expect(style.chipHeight(hasRemoveControl: false) == line + style.verticalPadding * 2)
                        let withControl: CGFloat = max(line, style.removeControlSize) + style.verticalPadding * 2
                        #expect(style.chipHeight(hasRemoveControl: true) == withControl)
                        let modeledLine = CadenceTypeScale.lineHeight(.metadata, base: style.baseFontSize,
                                                                     at: size, scaling: scaling)
                        #expect(style.chipHeight(hasRemoveControl: false) >= modeledLine + style.verticalPadding * 2)
                    }
                }
            }
        }
    }

    @Test func codexRatioConvergenceChangesTheModelNotTheChipFontOrPadding() {
        for size in sizes {
            for chipSize in CadenceTagChipSize.allCases {
                for input in CadenceTagChipInput.allCases {
                    let style = CadenceTagChipStyle(size: chipSize, isArchived: false, input: input,
                                                   dynamicTypeSize: size, scaling: .enabled)
                    let oldLine = ceil(style.fontSize * 1.25)
                    let oldHeight = oldLine + style.verticalPadding * 2
                    let delta = oldHeight - style.chipHeight(hasRemoveControl: false)
                    #expect(delta >= 0 && delta <= 2)
                    // Under touch the remove control, not either label estimate, binds the height.
                    if input == .touch {
                        let oldEditable: CGFloat = max(oldLine, style.removeControlSize) + style.verticalPadding * 2
                        #expect(style.chipHeight(hasRemoveControl: true) == oldEditable)
                    }
                }
            }
        }
        let compact = CadenceTagChipStyle(size: .compact, isArchived: false)
        #expect(compact.fontSize == 10)
        #expect(compact.verticalPadding == 3)
        #expect(compact.chipHeight(hasRemoveControl: false) == 18) // Previously 19.
        let regular = CadenceTagChipStyle(size: .regular, isArchived: false)
        #expect(regular.chipHeight(hasRemoveControl: false) == 25) // Unchanged at the default size.
    }

    @Test func codexTagPickerRowFloorChangesOnlyAtTheLastFourSizes() {
        for (index, size) in sizes.enumerated() {
            let style = CadenceTagChipStyle(size: .regular, isArchived: false, input: .touch,
                                           dynamicTypeSize: size, scaling: .enabled)
            let emptyLine = CadenceTypeScale.lineHeight(.rowTitle, at: size, scaling: .enabled)
            let oldChip = ceil(style.fontSize * 1.25) + style.verticalPadding * 2
            let oldRow = max(CadenceTagPickerMetrics.touchTargetHeight,
                             max(oldChip, emptyLine) + CadenceTagPickerMetrics.rowVerticalPadding * 2)
            let newRow = CadenceTagPickerMetrics.rowMinHeight(at: size, scaling: .enabled)
            #expect(oldRow - newRow == (index >= 8 ? 2 : 0))
        }
    }

    @Test func codexChipAndInspectorReadTheOneLineHeightRatio() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let chip = try read("Cadence/Shared/Components/CadenceTagChip.swift")
        let inspector = try read("Cadence/iOS/iOSTaskInspectorMetrics.swift")
        #expect(chip.contains("ceil(fontSize * CadenceTypeScale.lineHeightRatio)"))
        #expect(inspector.contains("titleSize * CadenceTypeScale.lineHeightRatio"))
        #expect(CadenceTypeScale.lineHeightRatio == 1.2)
        let duplicate = try CadenceScanInstrument(
            "literal font line-height ratio",
            fires: "let height = ceil(fontSize * 1.25)",
            andNotOn: "// fontSize * 1.25\nlet label = \"titleSize * 1.2\"",
            by: {
                CadenceSourceScan.codeOnly($0).range(
                    of: #"\b(?:fontSize|titleSize)\s*\*\s*1\.(?:25|2)\b"#,
                    options: .regularExpression
                ) != nil
            }
        )
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let hits = try duplicate.sweep(paths, atLeast: 300,
                                      including: "Cadence/Shared/Components/CadenceTagChip.swift", read: read)
        #expect(hits.isEmpty)
    }
}

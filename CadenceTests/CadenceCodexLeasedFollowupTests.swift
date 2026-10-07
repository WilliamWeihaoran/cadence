import Foundation
import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexLeasedFollowupTests {
    @Test func codexProductionDropTargetOwnsItsActivatedLifetimeButOnlyRetiresOnDisappear() throws {
        let source = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/iOS/iOSFloatingCreateTaskButton.swift"))
        let modifier = try cadenceFunctionBody("private struct iOSNewTaskDropTargetModifier", in: source)
        #expect(modifier.contains("@State private var registrationLifetime = iOSNewTaskDropFrameRegistry.shared.makeRegistrationLifetime()"))
        #expect(modifier.contains("private var registrationID: UUID { registrationLifetime.activate() }"))
        #expect(!modifier.contains("@State private var registrationID"))
        for publication in ["setFrame(", "setPlacement(", "setLive("] {
            #expect(modifier.contains(publication), "positive control: production must publish every retained fact")
        }
        let disappear = try cadenceFunctionBody(".onDisappear", in: modifier)
        #expect(disappear.contains(".retire(registrationID)"))
        #expect(!disappear.contains("destroy("))
    }

    @Test func codexBoardMetadataGlyphColumnPreservesFixedMetricsAndGrowsAdditively() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            #expect(CadenceBoardMetadataChipMetrics.iconColumnWidth(at: size, scaling: .fixed) == 11)
            #expect(CadenceTypeScale.size(.metadata, base: 10, at: size, scaling: .fixed) == 10)
            #expect(CadenceTypeScale.size(.metadata, base: 11, at: size, scaling: .fixed) == 11)
            let icon = CadenceTypeScale.size(.metadata, base: 10, at: size, scaling: .enabled)
            let column = CadenceBoardMetadataChipMetrics.iconColumnWidth(at: size, scaling: .enabled)
            #expect(abs(column - icon - 1) < 0.001)
        }
        #expect(CadenceBoardMetadataChipMetrics.iconColumnWidth(at: .large, scaling: .enabled) == 11)
        #expect(CadenceBoardMetadataChipMetrics.iconColumnWidth(at: .accessibility5, scaling: .enabled) > 11)
    }

    @Test func codexListsDeclareWholePagesAndMetadataWrapsWithoutAccessibilityShrinking() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let chip = try read("Cadence/Shared/Components/CadenceBoardMetadataChip.swift")
        #expect(chip.contains("struct CadenceBoardMetadataChip: View"))
        #expect(chip.contains(".cadenceFont(.metadata, base: CadenceBoardMetadataChipMetrics.iconSize"))
        #expect(chip.contains(".cadenceFont(.metadata, base: CadenceBoardMetadataChipMetrics.labelSize"))
        #expect(chip.contains(".lineLimit(wraps ? nil : 1)"))
        #expect(chip.contains(".minimumScaleFactor(wraps ? 1 : CadenceBoardMetadataChipMetrics.minimumScale)"))
        #expect(!chip.contains(".cadenceScaledTypography()"))
        for path in ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSListDetailView.swift"] {
            let source = try read(path)
            #expect(source.contains(".cadenceScaledTypography()"))
            #expect(source.contains("iOSListEditorSheet(mode: mode)\n                .cadenceFixedTypography()"))
        }
        let detail = try read("Cadence/iOS/iOSListDetailView.swift")
        #expect(detail.contains("iOSListNotesView(area: area, project: project)\n                .cadenceFixedTypography()"))
    }

    @Test func codexMarkdownKeepsPreferredBodyAndScalesCodeFontsWithTheirLineBoxes() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let styling = try read("Cadence/iOS/iOSMarkdownStylingSupport.swift")
        #expect(styling.contains("static var baseFont: UIFont { .preferredFont(forTextStyle: .body) }"))
        let mono = try cadenceFunctionBody("static var monoFont", in: styling)
        #expect(mono.contains("UIFontMetrics(forTextStyle: .body).scaledFont"))
        let canvas = try read("Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift")
        #expect(canvas.contains("struct iOSMarkdownLiveCodeBlockLayoutInfo"))
        #expect(canvas.contains("ceil(codeFont.lineHeight)"))
        #expect(canvas.contains("ceil(headerFont.lineHeight)"))
        #expect(canvas.contains("ceil(overflowFont.lineHeight)"))
        for font in ["codeFont", "headerFont", "overflowFont"] {
            let body = try cadenceFunctionBody("private var \(font)", in: canvas)
            #expect(body.contains("UIFontMetrics("))
            #expect(canvas.contains(".font: \(font)"))
        }
    }

    @Test func codexMarkdownTableMeasuresDrawsAndHitTestsTheSameResolvedFontSnapshot() throws {
        let source = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/iOS/iOSMarkdownTableGridRendering.swift"))
        #expect(source.contains("static var cellFont: UIFont"))
        #expect(source.contains("static var headerCellFont: UIFont"))
        #expect(source.contains("max(cellFont.lineHeight, headerFont.lineHeight)"))
        let make = try cadenceFunctionBody("static func make(grid:", in: source)
        #expect(make.contains("rowHeight(cellFont: cellFont, headerFont: headerFont)"))
        #expect(make.contains("intrinsicCellWidths(for: grid, cellFont: cellFont, headerFont: headerFont)"))
        #expect(make.contains("containerWidth: containerWidth, cellFont: cellFont, headerFont: headerFont"))
        let gridRect = try cadenceFunctionBody("func gridRect(inLineFragment", in: source)
        #expect(gridRect.contains("rowHeight: layout.rowHeight"))
        #expect(source.contains("font: rowIndex == 0 ? info.headerFont : info.cellFont"))
        #expect(!source.contains("static let rowHeight"))
    }

    @Test func codexMarkdownTextSizeInvalidatesUnchangedTextWithoutMovingItsSelection() throws {
        let source = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/iOS/iOSMarkdownEditor.swift"))
        #expect(source.contains("@Environment(\\.dynamicTypeSize)"))
        let refresh = try cadenceFunctionBody("func refreshStylingIfNeeded", in: source)
        #expect(refresh.contains("styledContentSizeCategory != textView.traitCollection.preferredContentSizeCategory"))
        #expect(refresh.contains("styledDynamicTypeSize != parent.dynamicTypeSize"))
        #expect(refresh.contains("let selection = textView.selectedRange"))
        #expect(refresh.contains("textView.selectedRange = clamped(selection, in: textView.textStorage)"))
        #expect(!refresh.contains("parent.text ="))
        let apply = try cadenceFunctionBody("func applyMarkdownStyle", in: source)
        #expect(apply.contains("textView.traitCollection.performAsCurrent"))
        #expect(apply.contains("styledContentSizeCategory = textView.traitCollection.preferredContentSizeCategory"))
        #expect(apply.contains("styledDynamicTypeSize = parent.dynamicTypeSize"))
        #expect(apply.contains("repositionTableCellEditor(in: textView)"))
        #expect(apply.contains("field.font = iOSMarkdownTableGridMetrics.font(isHeader: address.row == 0)"))
        #expect(apply.contains("field.selectedTextRange = selection"))
    }
}

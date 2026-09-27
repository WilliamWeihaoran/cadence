import Foundation
import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexDateSelectionTests {
    @Test func codexDateRowsReplaceTheGridAtEveryAccessibilitySize() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            let width = CadenceDateSelectionMetrics.width(at: size)
            #expect(width <= 343, "popover has less than 16pt margin on a 375pt phone")
            #expect(CadenceDateSelectionMetrics.usesDateRows(at: size, availableWidth: width)
                == CadenceTypeScale.isAccessibilitySize(size))
        }
        // Positive and negative controls for width-dependent inline fallback.
        #expect(CadenceDateSelectionMetrics.usesDateRows(at: .large, availableWidth: 200))
        #expect(!CadenceDateSelectionMetrics.usesDateRows(at: .large, availableWidth: 280))
        #expect(CadenceDateSelectionMetrics.usesDateRows(at: .xxxLarge, availableWidth: 280))
    }

    @Test func codexDateRowsReserveTheirLineAndPaddingWithoutCappingWrapping() {
        for size in DynamicTypeSize.allCases {
            let row = CadenceDateSelectionMetrics.dateRowHeight(at: size)
            let content: CGFloat = CadenceTypeScale.lineHeight(.metadata, at: size, scaling: .enabled) + 16
            #expect(row >= content)
            #expect(row >= 44)
        }
        #expect(CadenceDateSelectionMetrics.dateRowHeight(at: .accessibility5) > 44)
    }

    @Test func codexDatePanelTradesVisibleDatesForReadableShortcuts() {
        for size in DynamicTypeSize.allCases {
            for inline in [false, true] {
                // Worst case: all three shortcuts stack. Their hover wrappers add 4pt per row.
                let shortcuts = CadenceDateSelectionMetrics.quickActionHeight(at: size) * 3 + 12 + 18
                let footer = CadenceTypeScale.lineHeight(.controlLabel, base: 11, at: size, scaling: .enabled) + 20
                let viewport = CadenceDateSelectionMetrics.quickViewportHeight(at: size, inlineStyle: inline)
                let total = shortcuts + viewport + footer + 2
                #expect(total < 534, "worst-case panel needs \(total)pt at \(size)")
                #expect(viewport >= CadenceDateSelectionMetrics.dateRowHeight(at: size) * 2)
            }
        }
        #expect(CadenceDateSelectionMetrics.quickViewportHeight(at: .large, inlineStyle: false) == 294)
        #expect(CadenceDateSelectionMetrics.quickViewportHeight(at: .accessibility5, inlineStyle: false) < 294)
        // This is capacity for wrapping, not a claim that two full date rows are always visible.
        let threeLines: CGFloat = CadenceTypeScale.lineHeight(.metadata, at: .accessibility5, scaling: .enabled) * 3 + 16
        #expect(CadenceDateSelectionMetrics.quickViewportHeight(at: .accessibility5, inlineStyle: false) >= threeLines)
    }

    @Test func codexDateRedesignIsWiredForInlineAndPopoverWithoutInheritedScope() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/Shared/Components/CadenceDatePicker.swift")
        #expect(source.contains("struct MonthCalendarPanel"))
        #expect(source.contains("struct CadenceQuickDatePopover"))
        #expect(source.components(separatedBy: ".cadenceScaledTypography()").count - 1 == 2)
        #expect(!source.contains(".cadenceFixedTypography()"))
        for type in ["MonthCalendarPanel", "CadenceQuickDatePopover"] {
            let declaration = try #require(CadenceSourceScan.declarationBody("struct \(type): View", in: source))
            #expect(declaration.contains(".cadenceScaledTypography()"), "\(type) must declare independently")
        }
        #expect(source.contains("availableWidth: geometry.size.width"))
        #expect(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(source.contains(".frame(width: inlineStyle ? nil : CadenceDateSelectionMetrics.width(at: dynamicTypeSize))"))
        #expect(source.contains("viewportHeight: CadenceDateSelectionMetrics.quickViewportHeight(at: dynamicTypeSize, inlineStyle: inlineStyle)"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("VStack(spacing: 6) { quickActions }"))
        #expect(source.contains("DateFormatters.longDate.string(from: day)"))
        #expect(source.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(source.contains("PickerHoverHighlight(cornerRadius: cellSide / 2, padding: 0)"))
        #expect(!source.contains("minimumScaleFactor"))
        let row = try #require(CadenceSourceScan.functionBody(named: "dateRow", in: source))
        #expect(row.contains("selection = day"))
        #expect(row.contains("syncViewMonthToSelection()"))
        #expect(row.contains("isOpen = false"))
        #expect(row.contains("minHeight: CadenceDateSelectionMetrics.dateRowHeight(at: dynamicTypeSize)"))
        #expect(row.contains(".cadenceFont(.metadata,"))
        let shortcut = try #require(CadenceSourceScan.functionBody(named: "quickPill", in: source))
        #expect(shortcut.contains(".cadenceFont(.controlLabel, base: 11, weight: .medium)"))
        #expect(shortcut.contains(".padding(.vertical, 6)"))
        #expect(shortcut.contains("selection = target"))
        #expect(shortcut.contains("isOpen = false"))
    }
}

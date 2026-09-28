import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexTaskRowTypographyTests {
    @Test func codexCompletionFramesKeepTheirClearanceAndTouchTargetAtEverySize() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            for regular in [false, true] {
                let metrics = CadenceTaskRowMetrics.metrics(isRegularWidth: regular)
                for scaling in CadenceTypographyScaling.allCases {
                    let base = CadenceTaskRowMetrics.completionCircleDiameter
                    let glyph = CadenceTypeScale.size(.rowTitle, base: base, at: size, scaling: scaling)
                    let frame = CadenceTypeScale.height(metrics.completionGlyphSize, holding: .rowTitle,
                                                        textBase: base, at: size, scaling: scaling)
                    let inset = max(0, (44 - frame) / 2)
                    let clearance: CGFloat = metrics.completionGlyphSize - base
                    #expect(abs(frame - glyph - clearance) < 0.0001)
                    #expect(frame >= glyph)
                    #expect(frame + inset * 2 >= 44)
                    #expect(inset >= 0)
                    if scaling == .fixed {
                        #expect(frame == metrics.completionGlyphSize)
                        #expect(glyph == base)
                    }
                }
            }
        }
    }

    @Test func codexSwipeTrayReservesTwoLabelLinesOrAnAccessibilityGlyph() {
        for size in DynamicTypeSize.allCases {
            #expect(iOSTaskPageTypographyMetrics.swipeTrayHeight(at: size, scaling: .fixed) == 0)
            let height = iOSTaskPageTypographyMetrics.swipeTrayHeight(at: size, scaling: .enabled)
            let glyph = CadenceTypeScale.lineHeight(.metadata, base: 16, at: size, scaling: .enabled)
            let label = CadenceTypeScale.lineHeight(.metadata, base: 11, at: size, scaling: .enabled)
            let lines = iOSTaskPageTypographyMetrics.swipeLabelLineLimit(at: size, scaling: .enabled)
            #expect(lines == (size > .large ? 2 : 1))
            #expect(iOSTaskPageTypographyMetrics.swipeLabelLineLimit(at: size, scaling: .fixed) == 1)
            let expected: CGFloat = max(44, glyph + (CadenceTypeScale.isAccessibilitySize(size) ? 0 : label * CGFloat(lines)) + 8)
            #expect(height == expected)
            #expect(height >= glyph + 8)
        }
        #expect(iOSTaskPageTypographyMetrics.swipeTrayHeight(at: .large, scaling: .enabled) == 44)
        #expect(iOSTaskPageTypographyMetrics.swipeTrayHeight(at: .xxxLarge, scaling: .enabled) > 44)
        #expect(iOSTaskPageTypographyMetrics.swipeTrayHeight(at: .accessibility5, scaling: .enabled) > 44)
    }

    @Test func codexRowsWireScaledFramesWrappingAndEstimateRelocation() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let row = try read("Cadence/iOS/iOSTaskViews.swift")
        let reminder = try read("Cadence/iOS/iOSInboxRemindersSection.swift")
        for source in [row, reminder] {
            #expect(source.contains("@Environment(\\.dynamicTypeSize)"))
            #expect(source.contains("@Environment(\\.cadenceTypographyScaling)"))
            #expect(source.contains("CadenceTypeScale.height(metrics.completionGlyphSize, holding: .rowTitle, textBase: CadenceTaskRowMetrics.completionCircleDiameter, at: dynamicTypeSize, scaling: scaling)"))
            #expect(source.contains(".cadenceFont(.rowTitle, base: metrics.titleFontSize)"))
        }
        #expect(row.contains(".frame(width: completionFrame, height: completionFrame)"))
        #expect(row.contains(".iOSExpandedHitArea(max(0, (44 - completionFrame) / 2))"))
        #expect(reminder.contains(".frame(width: frame, height: frame)"))
        #expect(reminder.contains(".iOSExpandedHitArea(max(0, (44 - frame) / 2))"))
        #expect(row.contains(".lineLimit(wraps ? nil : CadenceTaskRowMetrics.titleLineLimit)"))
        #expect(row.contains(".lineLimit(wraps ? nil : metrics.secondaryLineLimit)"))
        #expect(row.contains("if task.estimatedMinutes > 0 && !wraps {"))
        #expect(row.contains("if task.estimatedMinutes > 0 && wraps {"))
        #expect(row.components(separatedBy: "iOSTaskRowEstimateChip(task: task)").count - 1 == 2)
    }

    @Test func codexSwipeTrayUsesItsMeasuredFloorAndNamesIconOnlyActions() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/iOS/iOSSwipeActionRow.swift")
        #expect(source.contains("struct iOSSwipeActionsModifier: ViewModifier"))
        #expect(source.contains(".frame(minHeight: iOSTaskPageTypographyMetrics.swipeTrayHeight(at: dynamicTypeSize, scaling: scaling))"))
        #expect(source.contains(".cadenceFont(.metadata, base: 16, weight: .semibold)"))
        #expect(source.contains("if !iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling) {"))
        #expect(source.contains(".cadenceFont(.metadata, base: 11, weight: .semibold)"))
        #expect(source.contains(".lineLimit(iOSTaskPageTypographyMetrics.swipeLabelLineLimit(at: dynamicTypeSize, scaling: scaling))"))
        #expect(source.contains(".accessibilityLabel(action.title)"))
        #expect(source.contains(".accessibilityActions {"))
    }

    @Test func codexSearchDeclaresItsPageWithoutOptingItsDestinationsIn() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift"))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
        #expect(body.contains("iOSSearchScopePicker("))
        #expect(body.contains("iOSEmptyPanel("))
        #expect(body.components(separatedBy: ".cadenceScaledTypography()").count - 1 == 1)
        for binding in ["$pushedListRoute", "$pushedDestination"] {
            let destination = try #require(CadenceSourceScan.declarationBody(".navigationDestination(item: \(binding))", in: body))
            #expect(destination.contains("switch "))
            #expect(destination.contains(".cadenceFixedTypography()"))
        }
        for binding in ["$selectedNote", "$selectedEvent"] {
            let sheet = try #require(CadenceSourceScan.declarationBody(".sheet(item: \(binding))", in: body))
            #expect(sheet.contains(".cadenceFixedTypography()"))
        }
        let inspector = try #require(CadenceSourceScan.declarationBody(".sheet(item: $selectedTask)", in: body))
        #expect(inspector.contains("iOSTaskInspectorSheet("))
        let inspectorSource = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheet.swift"))
        #expect(inspectorSource.contains(".cadenceScaledTypography()"))
        #expect(source.contains("iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: .enabled)"))
        #expect(source.contains("let layout = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))"))
        #expect(source.contains("if !stacks { Spacer(minLength: 0) }"))
    }

    @Test func codexPreparedTextUsesTheAdapterAndSearchRowsCanWrap() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let paths = [
            "Cadence/iOS/iOSDesignSystem.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
            "Cadence/iOS/iOSListSupportViews.swift",
            "Cadence/iOS/iOSSearchSupportViews.swift",
            "Cadence/iOS/iOSSearchView.swift",
            "Cadence/iOS/iOSSwipeActionRow.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTodayCompactViews.swift",
        ]
        let rawFont = try CadenceScanInstrument(
            "fixed point font in prepared text",
            fires: "Text(title).font(.system(size: 13))",
            andNotOn: "// .font(.system(size: 13))\nText(title).cadenceFont(.fieldLabel)",
            by: { CadenceSourceScan.codeOnly($0).contains(".font(.system(size:") }
        )
        let hits = try rawFont.sweep(paths, atLeast: 8,
                                    including: "Cadence/iOS/iOSSearchView.swift", read: read)
        #expect(hits.isEmpty)
        for path in paths {
            #expect(CadenceSourceScan.codeOnly(try read(path)).contains(".cadenceFont("), "no positive adapter use in \(path)")
        }
        let row = try #require(CadenceSourceScan.declarationBody("struct iOSSearchResultRow: View", in: try read("Cadence/iOS/iOSSearchSupportViews.swift")))
        #expect(row.contains(".lineLimit(wraps ? nil : 2)"))
        #expect(row.contains(".lineLimit(wraps ? nil : 1)"))
        #expect(row.contains("AnyLayout(VStackLayout(alignment: .leading, spacing: 12))"))
        #expect(row.contains(".fixedSize(horizontal: !wraps, vertical: true)"))
    }
}

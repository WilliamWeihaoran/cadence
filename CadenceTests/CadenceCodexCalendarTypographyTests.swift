import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexCalendarTypographyTests {
    static let calendarFiles = [
        "iOSCalendarChromeViews.swift", "iOSCalendarTimelineViews.swift",
        "iOSCalendarMonthViews.swift", "iOSCalendarMonthAgendaViews.swift",
        "iOSCalendarBoardView.swift", "iOSCalendarInspectorView.swift",
        "iOSCalendarEventEditSheet.swift", "iOSCalendarQuickCreateSheet.swift",
        "iOSBoardCards.swift", "iOSDateJumpTitle.swift",
    ].map { "Cadence/iOS/" + $0 }

    @Test func calendarTextUsesRolesAcrossEveryPresentation() throws {
        let instrument = try CadenceScanInstrument(
            "calendar numeric fonts",
            fires: "Text(title).font(.system(size: 12, weight: .medium))",
            andNotOn: "Text(title).cadenceFont(.metadata, base: 12, weight: .medium)",
            by: { CadenceSourceScan.codeOnly($0).contains(".font(.system(size:") }
        )
        let read = CadenceSourceScan.strippedSourceReader()
        let hits = try instrument.sweep(Self.calendarFiles, atLeast: Self.calendarFiles.count,
                                       including: "Cadence/iOS/iOSCalendarTimelineViews.swift", read: read)
        #expect(hits.isEmpty, "Calendar font literals remain: \(hits)")
        for path in Self.calendarFiles where !path.hasSuffix("iOSCalendarInspectorView.swift") && !path.hasSuffix("iOSCalendarQuickCreateSheet.swift") {
            #expect(try read(path).contains(".cadenceFont("), "Calendar text lost its role adapter: \(path)")
        }
        for path in ["iOSCalendarView.swift", "iOSCalendarEventEditSheet.swift", "iOSCalendarQuickCreateSheet.swift", "iOSDateJumpTitle.swift"] {
            let source = CadenceSourceScan.codeOnly(try read("Cadence/iOS/" + path))
            #expect(source.contains(".cadenceScaledTypography()"), "Missing independent calendar scope: \(path)")
        }
    }

    @Test func calendarLineBoxesReserveEveryRolesGainAtEverySize() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            for scaling in CadenceTypographyScaling.allCases {
                let chip = iOSCalendarTypographyMetrics.chipHeight(hasTime: false, at: size, scaling: scaling)
                let timed = iOSCalendarTypographyMetrics.chipHeight(hasTime: true, at: size, scaling: scaling)
                let titleLine = CadenceTypeScale.lineHeight(.metadata, base: 10, at: size, scaling: scaling)
                let clockLine = CadenceTypeScale.lineHeight(.metadata, base: 8, at: size, scaling: scaling)
                #expect(chip >= titleLine)
                let timedNeed: CGFloat = titleLine + clockLine + 1
                #expect(timed >= timedNeed)
                let circle = iOSCalendarTypographyMetrics.dayCircle(at: size, scaling: scaling)
                let numeral = CadenceTypeScale.lineHeight(.metadata, base: iOSCalendarTimelineMetrics.dayNumberSize, at: size, scaling: scaling)
                #expect(circle >= numeral)
                let date = iOSCalendarTypographyMetrics.dateBlock(at: size, scaling: scaling)
                let weekday = CadenceTypeScale.lineHeight(.sectionLabel, base: iOSCalendarTimelineMetrics.weekdaySize, at: size, scaling: scaling)
                let need = weekday + circle + iOSCalendarTimelineMetrics.dayLabelSpacing + 2 * iOSCalendarTimelineMetrics.dateBlockVerticalPadding
                let dateWithTolerance: CGFloat = date + 0.0001
                #expect(dateWithTolerance >= need)
                if scaling == .fixed {
                    #expect(chip == iOSCalendarTimelineMetrics.bandChipHeight)
                    #expect(date == iOSCalendarTimelineMetrics.dateBlockHeight)
                }
            }
        }
        let small = iOSCalendarTypographyMetrics.chipHeight(hasTime: true, at: .large, scaling: .enabled)
        let largest = iOSCalendarTypographyMetrics.chipHeight(hasTime: true, at: .accessibility5, scaling: .enabled)
        #expect(largest > small)
    }

    @Test func calendarBusyBandPricesTheSameChipRowsThatItDraws() {
        let split = CadenceCalendarAllDayBandPriority.split(allDayEvents: 20, unscheduledTasks: 20, capacity: 8)
        #expect(split.visible == 8)
        #expect(split.hidden > 0)
        for size in DynamicTypeSize.allCases {
            let band = iOSCalendarTypographyMetrics.bandHeight(for: [split], at: size, scaling: .enabled)
            let date = iOSCalendarTypographyMetrics.dateBlock(at: size, scaling: .enabled)
            let chip = iOSCalendarTypographyMetrics.chipHeight(hasTime: false, at: size, scaling: .enabled)
            let overflow = CadenceTypeScale.lineHeight(.metadata, base: iOSCalendarTimelineMetrics.overflowLabelSize, at: size, scaling: .enabled)
            let required = date + CGFloat(split.visible) * chip + overflow
                + CGFloat(split.visible) * iOSCalendarTimelineMetrics.bandLineSpacing + iOSCalendarTimelineMetrics.previewInset
            let bandWithTolerance: CGFloat = band + 0.0001
            #expect(bandWithTolerance >= required)
            let fixed = iOSCalendarTypographyMetrics.bandHeight(for: [split], at: size, scaling: .fixed)
            #expect(fixed == iOSCalendarTimelineMetrics.dayHeaderHeight(for: [split]))
        }
    }

    @Test func calendarColumnsAndQuarterHoursHoldTheirLargestLabels() {
        for size in DynamicTypeSize.allCases {
            let column = iOSCalendarTypographyMetrics.monthColumnWidth(at: size, scaling: .enabled)
            if CadenceTypeScale.isAccessibilitySize(size) {
                let day = CadenceTypeScale.lineHeight(.metadata, base: 15, at: size, scaling: .enabled)
                let twoDigits: CGFloat = 2 * day
                #expect(column >= twoDigits)
            }
            if size > .large {
                let quarter = iOSCalendarTypographyMetrics.hourHeight(at: size, scaling: .enabled) / 4 - 4
                let title = CadenceTypeScale.lineHeight(.metadata, base: 11, at: size, scaling: .enabled)
                let titleNeed: CGFloat = title + 4
                let quarterWithTolerance: CGFloat = quarter + 0.0001
                #expect(quarterWithTolerance >= titleNeed)
                let completionNeed: CGFloat = CadenceTypeScale.size(.metadata, base: 13, at: size, scaling: .enabled) + 6
                #expect(quarterWithTolerance >= completionNeed)
            }
            let row = iOSCalendarTypographyMetrics.compactRowHeight(44, at: size, scaling: .enabled)
            let line = CadenceTypeScale.lineHeight(.metadata, base: 15, at: size, scaling: .enabled)
            let rowNeed: CGFloat = line + 12
            #expect(row >= rowNeed)
        }
    }

    @Test func calendarDrawingReadsResolvedGeometryAndKeepsShortBlocksReadable() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let grid = try read("Cadence/iOS/iOSCalendarTimelineViews.swift")
        for binding in ["iOSCalendarTypographyMetrics.hourHeight(at: dynamicTypeSize, scaling: scaling)",
                        "iOSCalendarTypographyMetrics.bandHeight(for: splits, at: dynamicTypeSize, scaling: scaling)",
                        "iOSCalendarTypographyMetrics.dayCircle(at: dynamicTypeSize, scaling: scaling)",
                        "iOSCalendarTypographyMetrics.dateBlock(at: dynamicTypeSize, scaling: scaling)",
                        "iOSCalendarTypographyMetrics.railWidth(", "ViewThatFits(in: .vertical)",
                        "iOSCalendarTypographyMetrics.bandCapacity(isRegularWidth: isRegularWidth, at: dynamicTypeSize, scaling: scaling)"] {
            #expect(grid.contains(binding), "Calendar lost its font/layout relation: \(binding)")
        }
        for declaration in ["private struct iOSCalendarEventBlock: View", "struct iOSTimelineTaskBlock: View"] {
            let block = try #require(CadenceSourceScan.declarationBody(declaration, in: grid))
            #expect(block.contains(".fixedSize(horizontal: false, vertical: true)"))
            #expect(block.contains("private var titleLabel: some View"))
        }
        #expect(grid.contains("diameter: CadenceTypeScale.size(.metadata, base: 13, at: dynamicTypeSize, scaling: scaling)"))
        let month = try read("Cadence/iOS/iOSCalendarMonthViews.swift")
        #expect(month.contains(".frame(height: iOSCalendarTypographyMetrics.chipHeight(hasTime: timeLabel != nil, at: dynamicTypeSize, scaling: scaling))"))
        #expect(month.contains("iOSCalendarMiniChip.height(hasTime: false, at: dynamicTypeSize, scaling: scaling)"))
        #expect(month.contains("iOSCalendarTypographyMetrics.lineGain(9, at: dynamicTypeSize, scaling: scaling)"))
        #expect(month.contains("ScrollView(.horizontal)"))
        #expect(month.contains("7 * iOSCalendarTypographyMetrics.monthColumnWidth(at: dynamicTypeSize, scaling: scaling)"))
        let dateJump = try read("Cadence/iOS/iOSDateJumpTitle.swift")
        let datePanel = try #require(CadenceSourceScan.declarationBody("private struct iOSDateJumpPopover: View", in: dateJump))
        #expect(datePanel.contains(".cadenceScaledTypography()"))
        #expect(datePanel.contains("MonthCalendarPanel(selection: $selection, viewMonth: $viewMonth, isOpen: $isOpen, inlineStyle: true)"))
        #expect(CadenceDateSelectionMetrics.usesDateRows(at: .accessibility5, availableWidth: 280))
        let eventEditor = try read("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        let noteSheet = try #require(CadenceSourceScan.declarationBody(".sheet(item: $presentedEventNote)", in: eventEditor))
        #expect(noteSheet.contains(".cadenceFixedTypography()"))
        let references = try read("Cadence/iOS/iOSMarkdownReferenceSupport.swift")
        let noteReference = try #require(CadenceSourceScan.declarationBody(".sheet(item: $selectedReferenceNote)", in: references))
        #expect(noteReference.contains(".cadenceFixedTypography()"))
        let compact = try read("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        #expect(compact.contains("rowHeight: iOSCalendarTypographyMetrics.compactRowHeight(rowHeight, at: dynamicTypeSize, scaling: scaling)"))
    }


    @Test func calendarAllDayBudgetPreservesCountsWithoutConsumingTheClock() {
        for regular in [false, true] {
            let base = CadenceCalendarAllDayBandPriority.capacity(isRegularWidth: regular)
            for size in DynamicTypeSize.allCases {
                let count = iOSCalendarTypographyMetrics.bandCapacity(isRegularWidth: regular, at: size, scaling: .enabled)
                #expect(count > 0)
                #expect(count <= base)
                let fixed = iOSCalendarTypographyMetrics.bandCapacity(isRegularWidth: regular, at: size, scaling: .fixed)
                #expect(fixed == base)
                let split = CadenceCalendarAllDayBandPriority.split(allDayEvents: 20, unscheduledTasks: 20, capacity: count)
                #expect(split.visible == count)
                #expect(split.visible + split.hidden == 40)
                if size >= .large {
                    let band = iOSCalendarTypographyMetrics.bandHeight(for: [split], at: size, scaling: .enabled)
                    let date = iOSCalendarTypographyMetrics.dateBlock(at: size, scaling: .enabled)
                    let overflow = CadenceTypeScale.lineHeight(.metadata, base: iOSCalendarTimelineMetrics.overflowLabelSize, at: size, scaling: .enabled)
                    let previewBudget = CGFloat(base) * (iOSCalendarTimelineMetrics.bandChipHeight + iOSCalendarTimelineMetrics.bandLineSpacing) + overflow + iOSCalendarTimelineMetrics.previewInset
                    let preview = band - date
                    #expect(preview <= previewBudget)
                }
            }
            let largest = iOSCalendarTypographyMetrics.bandCapacity(isRegularWidth: regular, at: .accessibility5, scaling: .enabled)
            #expect(largest < base)
        }
    }

}

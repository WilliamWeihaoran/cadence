import Foundation
import SwiftUI
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexTaskSummaryTypographyTests {
    @Test func codexSharedTaskSummaryMetricsStayFixedAtEverySize() {
        #expect(DynamicTypeSize.allCases.count == 12)
        let fonts: [(CadenceTypographyRole, CGFloat)] = [
            (.bodyText, 26), (.bodyText, 15), (.fieldLabel, 13),
            (.controlLabel, 14), (.controlLabel, 13),
            (.metadata, 12), (.metadata, 11), (.metadata, 10), (.sectionLabel, 10)
        ]
        for size in DynamicTypeSize.allCases {
            #expect(CadenceEmptyStateMetrics.iconSide(at: size, scaling: .fixed) == 72)
            #expect(CadenceTodayRolloverMetrics.iconSide(at: size, scaling: .fixed) == 22)
            #expect(CadenceTodayRolloverMetrics.dotSide(at: size, scaling: .fixed) == 6)
            #expect(CadenceOverdueSummaryMetrics.iconSide(at: size, scaling: .fixed) == 30)
            for (role, base) in fonts {
                #expect(CadenceTypeScale.size(role, base: base, at: size, scaling: .fixed) == base)
            }
        }
    }

    @Test func codexSummaryGlyphFramesHoldTheirLinesIncludingTheSmallRolloverPlate() {
        for size in DynamicTypeSize.allCases {
            let emptyLine = CadenceTypeScale.lineHeight(.bodyText, base: 26, at: size, scaling: .enabled)
            let rolloverLine: CGFloat = CadenceTypeScale.lineHeight(.controlLabel, base: 14, at: size, scaling: .enabled) + 4
            let overdueLine = CadenceTypeScale.lineHeight(.controlLabel, at: size, scaling: .enabled)
            #expect(CadenceEmptyStateMetrics.iconSide(at: size, scaling: .enabled) >= emptyLine)
            #expect(CadenceTodayRolloverMetrics.iconSide(at: size, scaling: .enabled) >= rolloverLine)
            #expect(CadenceOverdueSummaryMetrics.iconSide(at: size, scaling: .enabled) >= overdueLine)
            let title = CadenceTypeScale.size(.metadata, at: size, scaling: .enabled)
            #expect(CadenceTodayRolloverMetrics.dotSide(at: size, scaling: .enabled) == title / 2)
        }
        #expect(CadenceEmptyStateMetrics.iconSide(at: .accessibility5, scaling: .enabled) > 72)
        #expect(CadenceOverdueSummaryMetrics.iconSide(at: .accessibility5, scaling: .enabled) > 30)
        // The old plate plus font growth alone is still too short for the glyph's line box.
        let additiveOnly = CadenceTypeScale.height(22, holding: .controlLabel, textBase: 14, at: .accessibility5, scaling: .enabled)
        let line = CadenceTypeScale.lineHeight(.controlLabel, base: 14, at: .accessibility5, scaling: .enabled)
        #expect(additiveOnly < line)
        #expect(CadenceTodayRolloverMetrics.iconSide(at: .accessibility5, scaling: .enabled) > additiveOnly)
    }

    @Test func codexWrappingOverdueCaptionsPreserveWordsAndTintOnlyTheDate() {
        let details: [(String?, String?)] = [(nil, nil), ("", ""), ("A long project name", nil), (nil, "3 open"), ("Project", "3 open")]
        for (leading, trailing) in details {
            for late in [false, true] {
                let line = CadenceOverdueSummaryLine(leadingDetail: leading, dateText: "3 days ago", trailingDetail: trailing, isLate: late)
                let caption = CadenceOverdueSummaryCaption.attributedCaption(line)
                #expect(String(caption.characters) == line.plainText)
                var redFragments: [String] = []
                for run in caption.runs {
                    if run.foregroundColor == Theme.red {
                        redFragments.append(String(caption[run.range].characters))
                    } else {
                        #expect(run.foregroundColor == Theme.dim)
                    }
                }
                #expect(redFragments == (late ? [line.dateText] : []))
            }
        }
    }

    @Test func codexNewlyLeasedComponentsUseTheirScaleAndKeepWrappingUncapped() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let empty = try read("Cadence/Shared/Components/EmptyStateView.swift")
        let group = try read("Cadence/Shared/Components/CadenceTaskGroupHeading.swift")
        let rollover = try read("Cadence/Shared/Components/CadenceTodayRolloverBanner.swift")
        let overdue = try read("Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift")
        for source in [empty, group, rollover, overdue] {
            #expect(source.contains("@Environment(\\.cadenceTypographyScaling)"))
            #expect(source.contains(".cadenceFont("))
            #expect(!source.contains(".font(.system(size:"))
            #expect(!source.contains(".cadenceScaledTypography()"))
            #expect(!source.contains(".cadenceFixedTypography()"))
            #expect(!source.contains("minimumScaleFactor"))
        }
        #expect(empty.contains("CadenceEmptyStateMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)"))
        #expect(empty.contains(".cadenceFont(.bodyText, base: 26, weight: .regular)"))
        #expect(empty.contains(".fixedSize(horizontal: false, vertical: scaling == .enabled)"))
        #expect(group.contains(".cadenceFont(.sectionLabel, base: CadenceTaskGroupHeadingMetrics.countSize, weight: .bold)"))
        #expect(group.contains("if CadenceTaskGroupHeadingMetrics.showsCapsule(for: count), let count"))
        #expect(rollover.contains("CadenceTodayRolloverMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)"))
        #expect(rollover.contains("CadenceTodayRolloverMetrics.dotSide(at: dynamicTypeSize, scaling: scaling)"))
        #expect(rollover.contains(".cadenceFont(.controlLabel, base: 14, weight: .semibold)"))
        #expect(rollover.contains("Button(action: onRollOver)"))
        #expect(rollover.contains("Text(failureNotice)"))
        #expect(rollover.contains(".fixedSize(horizontal: !wraps, vertical: true)"))
        #expect(rollover.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(overdue.contains("Text(Self.attributedCaption(line))"))
        #expect(overdue.contains("CadenceOverdueSummaryMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)"))
        #expect(overdue.contains("? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))"))
        #expect(overdue.contains(".cadenceFont(.sectionLabel, base: SectionEyebrowLabel.fontSize, weight: .semibold)"))
        for source in [group, rollover, overdue] {
            #expect(source.contains("scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)"))
            #expect(source.contains(".lineLimit(wraps ? nil : 1)"))
        }
    }

    @Test func codexTodayPinsOnlyEmbeddedNotesChromeAndLeavesItsUIKitBodyResponsive() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let today = try read("Cadence/iOS/iOSTodayView.swift")
        let inspector = try #require(CadenceSourceScan.declarationBody("private var inspectorPanelContent: some View", in: today))
        let notes = try #require(inspector.range(of: "case .notes:"))
        let timeline = try #require(inspector.range(of: "case .timeline:"))
        #expect(notes.lowerBound < timeline.lowerBound)
        let notesBranch = String(inspector[notes.lowerBound..<timeline.lowerBound])
        #expect(notesBranch.contains("iOSNotesView(showsTitle: false)"))
        #expect(notesBranch.contains(".cadenceFixedTypography()"))
        #expect(inspector.components(separatedBy: ".cadenceFixedTypography()").count - 1 == 1)
        #expect(inspector.contains("iOSSchedulePanel()"))
        let markdown = try read("Cadence/iOS/iOSMarkdownStylingSupport.swift")
        #expect(markdown.contains("static var baseFont: UIFont { .preferredFont(forTextStyle: .body) }"))
    }
}

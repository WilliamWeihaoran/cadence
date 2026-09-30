import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexPageCompletionTypographyTests {
    @Test func codexBoardAndGhostKeepFixedMetricsAndGrowWithClearance() {
        #expect(DynamicTypeSize.allCases.count == 12)
        let fonts: [(CadenceTypographyRole, CGFloat)] = [
            (.metadata, 8), (.metadata, 10), (.metadata, 11), (.metadata, 12),
            (.rowTitle, 13), (.rowTitle, 14), (.rowTitle, 15),
            (.sectionLabel, CadenceBoardColumnHeaderMetrics.countSize),
            (.sectionLabel, CadenceBoardColumnHeaderMetrics.labelSize)
        ]
        for size in DynamicTypeSize.allCases {
            for (role, base) in fonts {
                #expect(CadenceTypeScale.size(role, base: base, at: size, scaling: .fixed) == base)
            }
            for scaling in CadenceTypographyScaling.allCases {
                let disc = CadenceTypeScale.size(.rowTitle, base: 13, at: size, scaling: scaling)
                let frame = CadenceTypeScale.height(30, holding: .rowTitle, textBase: 13, at: size, scaling: scaling)
                #expect(abs(frame - disc - 17) < 0.0001)
                #expect(frame + max(0, (44 - frame) / 2) * 2 >= 44)
                let ghost = CadenceTypeScale.height(44, holding: .rowTitle, at: size, scaling: scaling)
                #expect(ghost >= CadenceTypeScale.lineHeight(.rowTitle, at: size, scaling: scaling))
                if scaling == .fixed {
                    #expect(frame == 30)
                    #expect(ghost == 44)
                }
            }
        }
        #expect(CadenceTypeScale.height(30, holding: .rowTitle, textBase: 13, at: .accessibility5, scaling: .enabled) > 30)
    }

    @Test func codexBoardCardAndColumnWireTheirPreparedFontsAndGeometry() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let cards = try read("Cadence/iOS/iOSBoardCards.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct iOSBoardTaskCard: View", in: cards))
        #expect(card.contains("CadenceTypeScale.size(.rowTitle, base: 13, at: dynamicTypeSize, scaling: scaling)"))
        #expect(card.contains("CadenceTypeScale.height(30, holding: .rowTitle, textBase: 13, at: dynamicTypeSize, scaling: scaling)"))
        #expect(card.contains("iOSTaskCompletionCircle(glyph: .resolve(task: task), diameter: completionDiameter)"))
        #expect(card.contains(".frame(width: completionFrame, height: completionFrame)"))
        #expect(card.contains(".iOSExpandedHitArea(max(0, (44 - completionFrame) / 2))"))
        #expect(card.contains(".cadenceFont(.rowTitle, base: isRegularWidth ? 15 : 14, weight: .medium)"))
        #expect(card.contains(".lineLimit(wraps ? nil : 2)"))
        #expect(card.contains("Array(repeating: GridItem(.flexible()), count: wraps ? 1 : 2)"))
        #expect(card.contains(".cadenceFont(.metadata, base: 12, weight: .medium)"))
        #expect(card.contains(".frame(minHeight: CadenceTypeScale.height(30, holding: .metadata, at: dynamicTypeSize, scaling: scaling))"))
        #expect(!card.contains(".font(.system(size:"))
        #expect(!card.contains(".cadenceScaledTypography()"))

        let column = try read("Cadence/Shared/Components/CadenceBoardColumnHeader.swift")
        #expect(column.contains("struct CadenceBoardColumnTitleRow<Trailing: View>"))
        #expect(column.contains(".cadenceUppercaseLabel("))
        #expect(column.contains(".cadenceFont(.sectionLabel, base: CadenceBoardColumnHeaderMetrics.countSize, weight: .medium)"))
        #expect(column.contains(".cadenceFont(.metadata, base: 8, weight: .semibold)"))
        #expect(column.contains(".cadenceFont(.metadata, base: 10, weight: .medium)"))
        #expect(column.contains(".lineLimit(wraps ? nil : 1)"))
        #expect(column.contains("scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)"))
        #expect(!column.contains(".font(.system(size:"))
        #expect(!column.contains(".cadenceScaledTypography()"))
    }

    @Test func codexInsertionGhostScalesButCapturePresenterIsAnIndependentFixedScope() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSFloatingCreateTaskButton.swift")
        let ghost = try #require(CadenceSourceScan.declarationBody("private struct iOSNewTaskGhostRow: View", in: source))
        #expect(ghost.contains("iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)"))
        #expect(ghost.contains(".cadenceFont(.rowTitle, base: 14, weight: .semibold)"))
        #expect(ghost.contains(".cadenceFont(.metadata, base: 12, weight: .bold)"))
        #expect(ghost.contains(".cadenceFont(.metadata, base: 11, weight: .medium)"))
        #expect(ghost.contains(".lineLimit(wraps ? nil : 1)"))
        #expect(ghost.contains(".frame(minHeight: CadenceTypeScale.height(44, holding: .rowTitle, at: dynamicTypeSize, scaling: scaling), alignment: .leading)"))
        #expect(!ghost.contains(".font(.system(size:"))
        let layer = try #require(CadenceSourceScan.declarationBody("private struct iOSFloatingCreateTaskLayer: ViewModifier", in: source))
        let compact = layer.filter { !$0.isWhitespace }
        #expect(compact.contains(".iOSCaptureHost(interaction,onCreated:onCreated).cadenceFixedTypography()"))
        #expect(compact.contains("interaction:interaction).cadenceFixedTypography()"))
        #expect(!layer.contains(".cadenceScaledTypography()"))
    }

    @Test func codexTaskPagesDeclareAfterTheirContentAndBeforeCapture() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for (path, content) in [
            ("iOSTaskCollectionPage.swift", "iOSTaskCollectionSections("),
            ("iOSTodayView.swift", "todayLayout(width:"),
            ("iOSTasksPageView.swift", "header"),
            ("iOSTasksTabView.swift", "iOSTasksTabHeader(")
        ] {
            let source = try read("Cadence/iOS/" + path)
            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
            let draw = try #require(body.range(of: content))
            let root = try #require(body.range(of: ".cadenceScaledTypography()"))
            #expect(draw.lowerBound < root.lowerBound)
            #expect(body.components(separatedBy: ".cadenceScaledTypography()").count - 1 == 1)
            if path == "iOSTodayView.swift" {
                let capture = try #require(body.range(of: ".iOSFloatingCreateTaskButton()"))
                #expect(root.lowerBound < capture.lowerBound)
                let sheet = try #require(CadenceSourceScan.declarationBody(".sheet(item: $pendingListOpen)", in: body))
                #expect(sheet.contains("iOSTodayOverdueListSheet(request: request)"))
                #expect(sheet.contains(".cadenceFixedTypography()"))
            }
        }
        for path in ["iOSInboxView.swift", "iOSTaskCollectionViews.swift"] {
            let source = try read("Cadence/iOS/" + path)
            #expect(source.contains("iOSTaskCollectionPage("))
            #expect(source.contains(".iOSFloatingCreateTaskButton()"))
        }
    }

    @Test func codexListsPinTheirEmbeddedNotesAndIndependentConfirmations() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let detail = try read("Cadence/iOS/iOSListDetailView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("private var pageBody: some View", in: detail))
        let documents = try #require(page.range(of: "case .documents:"))
        let links = try #require(page.range(of: "case .links:"))
        #expect(documents.lowerBound < links.lowerBound)
        let notes = String(page[documents.upperBound..<links.lowerBound]).filter { !$0.isWhitespace }
        #expect(notes.contains("iOSListNotesView(area:area,project:project).cadenceFixedTypography()"))
        for path in ["iOSListDetailView.swift", "iOSListViews.swift"] {
            let source = try read("Cadence/iOS/" + path)
            let sheet = try #require(CadenceSourceScan.declarationBody(".sheet(item: $editorMode)", in: source))
            #expect(sheet.filter { !$0.isWhitespace }.contains("iOSListEditorSheet(mode:mode).cadenceFixedTypography()"))
        }
        for (path, type, drawing) in [
            ("iOSListDeletionSupport.swift", "iOSListDeletionModifier", "iOSListDeleteConfirmationSheet("),
            ("iOSListWindDownSupport.swift", "iOSListWindDownModifier", "iOSWindDownConfirmationSheet(")
        ] {
            let source = try read("Cadence/iOS/" + path)
            let modifier = try #require(CadenceSourceScan.declarationBody("private struct \(type): ViewModifier", in: source))
            let sheet = try #require(CadenceSourceScan.declarationBody("content.sheet(item: $target)", in: modifier))
            #expect(sheet.contains(drawing))
            #expect(sheet.filter { !$0.isWhitespace }.contains("}.cadenceFixedTypography()"))
            #expect(!sheet.contains(".cadenceScaledTypography()"))
        }
    }
}

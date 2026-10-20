import SwiftUI
import Testing
@testable import Cadence

struct CadenceCodexSettingsTypographyTests {
    @Test func settingsTextUsesRolesAcrossEveryCategory() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/iOS").filter { $0.contains("Settings") }
        #expect(files.count == 16)
        let instrument = try CadenceScanInstrument(
            "settings numeric fonts",
            fires: "Text(title).font(.system(size: 12))",
            andNotOn: "Text(title).cadenceFont(.metadata, base: 12, weight: .regular)",
            by: { CadenceSourceScan.codeOnly($0).contains(".font(.system(size:") }
        )
        let hits = try instrument.sweep(files, atLeast: files.count,
                                       including: "Cadence/iOS/iOSSettingsView.swift", read: CadenceSourceScan.strippedSourceReader())
        #expect(hits.isEmpty, "Settings font literals remain: \(hits)")
        let read = CadenceSourceScan.strippedSourceReader()
        for name in ["iOSSettingsView.swift", "iOSSettingsContextSection.swift", "iOSArchiveImportSettingsSection.swift", "iOSDataResetSettingsSection.swift", "iOSListDeletionSupport.swift"] {
            let source = CadenceSourceScan.codeOnly(try read("Cadence/iOS/" + name))
            #expect(source.contains(".cadenceScaledTypography()"), "Missing independent settings scope: \(name)")
        }
        for name in ["CadenceFieldRows.swift", "CadenceAccentPalettePicker.swift"] {
            let source = CadenceSourceScan.codeOnly(try read("Cadence/Shared/Components/" + name))
            #expect(!source.contains(".font(.system(size:"))
            #expect(source.contains(".cadenceFont("))
        }
    }

    @Test func settingsStackingAndRailDecisionsFollowTheReadersSize() {
        #expect(DynamicTypeSize.allCases.count == 12)
        for size in DynamicTypeSize.allCases {
            #expect(!CadenceSettingsTypographyLayout.stacks(at: size, scaling: .fixed))
            #expect(CadenceSettingsTypographyLayout.stacks(at: size, scaling: .enabled) == CadenceTypeScale.isAccessibilitySize(size))
            #expect(!CadenceSettingsTypographyLayout.usesRail(isRegularWidth: false, at: size))
            #expect(CadenceSettingsTypographyLayout.usesRail(isRegularWidth: true, at: size) == !CadenceTypeScale.isAccessibilitySize(size))
        }
    }

    @Test func settingsGlyphFramesPreserveClearanceInsteadOfScalingThePadding() {
        for size in DynamicTypeSize.allCases {
            for scaling in CadenceTypographyScaling.allCases {
                for role in [CadenceTypographyRole.metadata, .controlLabel, .rowTitle, .editorTitle] {
                    let frame = CadenceSettingsTypographyLayout.glyphFrame(36, glyph: 13, role: role, at: size, scaling: scaling)
                    let line = CadenceTypeScale.lineHeight(role, base: 13, at: size, scaling: scaling)
                    let baseLine = CadenceTypeScale.lineHeight(role, base: 13, at: .large, scaling: .fixed)
                    let clearance = frame - line
                    let originalClearance: CGFloat = 36 - baseLine
                    #expect(abs(clearance - originalClearance) < 0.0001)
                    if scaling == .fixed {
                        let original = CadenceSettingsTypographyLayout.glyphFrame(36, glyph: 13, role: role, at: .large, scaling: .fixed)
                        #expect(frame == original)
                    }
                }
            }
        }
        let normal = CadenceSettingsTypographyLayout.glyphFrame(36, glyph: 13, at: .large, scaling: .enabled)
        let largest = CadenceSettingsTypographyLayout.glyphFrame(36, glyph: 13, at: .accessibility5, scaling: .enabled)
        #expect(largest > normal)
    }

    @Test func settingsDrawSitesReadTheReflowAndFrameDecisions() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let root = try read("Cadence/iOS/iOSSettingsView.swift")
        #expect(root.contains("CadenceSettingsTypographyLayout.usesRail(isRegularWidth: horizontalSizeClass == .regular, at: dynamicTypeSize)"))
        let templates = try read("Cadence/iOS/iOSSettingsTemplateAndListSections.swift")
        #expect(templates.contains("if CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling) { return .oneColumn }"))
        let ai = try #require(CadenceSourceScan.declarationBody("struct iOSAISettingsSection: View", in: templates))
        #expect(ai.contains(".frame(width: CadenceSettingsTypographyLayout.glyphFrame(42, glyph: 18, role: .rowTitle, at: dynamicTypeSize, scaling: scaling), height: CadenceSettingsTypographyLayout.glyphFrame(42, glyph: 18, role: .rowTitle, at: dynamicTypeSize, scaling: scaling))"))
        // A tile reserves the growth of the same role and base it draws, on both axes.
        for (path, declaration) in [
            ("Cadence/iOS/iOSSettingsComponents.swift", "struct iOSSettingsEmptyInlineRow: View"),
            ("Cadence/iOS/iOSSettingsContextSection.swift", "private struct iOSSettingsContextIcon: View")
        ] {
            let source = try read(path)
            let tile = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            #expect(tile.contains(".cadenceFont(.rowTitle, base: 15, weight: .semibold)"))
            #expect(tile.components(separatedBy: "CadenceSettingsTypographyLayout.glyphFrame(iOSSettingsMetrics.glyphSlot, glyph: 15, role: .rowTitle, at: dynamicTypeSize, scaling: scaling)").count - 1 == 2)
        }
        let calendars = try read("Cadence/iOS/iOSCalendarSettingsSection.swift")
        for declaration in ["private struct iOSMissingCalendarLinkRow: View", "private struct iOSCalendarSettingsRow: View"] {
            let row = try #require(CadenceSourceScan.declarationBody(declaration, in: calendars))
            let compact = row.filter { !$0.isWhitespace }
            #expect(compact.contains(".frame(minWidth:iOSSettingsMetrics.minimumTapTarget,minHeight:iOSSettingsMetrics.minimumTapTarget)"))
        }
        let rows = try read("Cadence/Shared/Components/CadenceFieldRows.swift")
        for declaration in ["struct CadenceSettingsNoticeRow<Trailing: View>: View", "struct CadenceFieldRow<Content: View>: View", "struct CadenceSettingsInfoRow: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: rows))
            #expect(body.contains("CadenceSettingsTypographyLayout.stacks(at: dynamicTypeSize, scaling: scaling)"))
            let compact = body.filter { !$0.isWhitespace }
            #expect(compact.contains("letlayout=CadenceSettingsTypographyLayout.stacks(at:dynamicTypeSize,scaling:scaling)?AnyLayout(VStackLayout("))
            #expect(body.contains("CadenceSettingsRowMetrics.rowHeight(at: dynamicTypeSize, scaling: scaling)"))
        }
    }
}

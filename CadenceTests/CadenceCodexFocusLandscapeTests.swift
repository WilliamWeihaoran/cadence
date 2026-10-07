import CoreGraphics
import Foundation
import Testing
@testable import Cadence

struct CadenceCodexFocusLandscapeTests {
    @Test func codexLandscapeReservesAReadablePickerBesideTheClock() {
        for width in [CGFloat(568), 667, 736, 812, 852, 932] {
            for height in [CGFloat(240), 274, 300, 393] {
                #expect(CadenceFocusLayout.usesLandscapeLayout(width: width, height: height))
                let timer = CadenceFocusLayout.timerWidth(availableWidth: width)
                let picker = width - CadenceFocusLayout.contentInset * 2 - CadenceFocusLayout.columnSpacing - timer
                #expect(timer >= 240)
                #expect(picker >= CadenceFocusLayout.minimumPickerWidth)
                #expect(timer > 44 * 3 + 16 * 2, "all existing transport controls must fit without shrinking")
            }
        }
        for size in [CGSize(width: 393, height: 852), CGSize(width: 1194, height: 834),
                     CGSize(width: 834, height: 1194), .zero] {
            #expect(!CadenceFocusLayout.usesLandscapeLayout(width: size.width, height: size.height))
        }
        #expect(!CadenceFocusLayout.usesLandscapeLayout(width: .infinity, height: 320))
        #expect(!CadenceFocusLayout.usesLandscapeLayout(width: 852, height: .nan))
        #expect(CadenceFocusLayout.timerWidth(availableWidth: 0) == 0)
    }

    @Test func codexLandscapeUsesTheExistingOwnerAndTransportWithoutAnotherPresentation() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSFocusView.swift")
        #expect(source.contains("struct iOSFocusView: View"))
        #expect(source.components(separatedBy: "@State private var timerState").count - 1 == 1)
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
        #expect(body.contains("GeometryReader { geometry in"))
        #expect(body.contains("if CadenceFocusLayout.usesLandscapeLayout(width: geometry.size.width, height: geometry.size.height)"))
        #expect(body.contains("landscapeLayout(width: geometry.size.width)"))
        #expect(body.contains("else if isCompact"))
        let landscape = try #require(CadenceSourceScan.declarationBody("private func landscapeLayout", in: source))
        #expect(landscape.contains("sessionClock(fontSize: 66)"))
        #expect(landscape.contains("focusControls(for: task)"))
        #expect(landscape.contains("bundleControls(for: bundle)"))
        #expect(landscape.contains("taskListPane"))
        #expect(landscape.contains(".cadenceFixedTypography()"))
        #expect(!landscape.contains("timerState ="))
        #expect(!landscape.contains("selectedTarget ="))
        #expect(!landscape.contains(".fullScreenCover"))
    }
}

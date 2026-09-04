import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The task row's metadata strip used to be a horizontal `ScrollView` that could not scroll,
/// because the row's tap gesture beat it — so chips past the right edge were unreachable. It wraps
/// now. The property that matters most here is the last test: wrapping must never drop an item.
///
/// This suite is also the whole test seam for `CadenceWrappingHStack` (T-883): that `Layout`
/// conformance has no public way to construct `Subviews`, so its `sizeThatFits`/`placeSubviews`
/// cannot be driven directly, and every line-breaking decision it makes is delegated to the
/// functions tested here.
struct CadenceFlowLayoutSupportTests {
    private let spacing: CGFloat = 6
    private let lineSpacing: CGFloat = 4

    private func sizes(_ widths: [CGFloat], height: CGFloat = 14) -> [CGSize] {
        widths.map { CGSize(width: $0, height: height) }
    }

    @Test
    func itemsThatFitStayOnOneLine() {
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 50, 60]),
            availableWidth: 200,
            spacing: spacing
        )

        #expect(lines.count == 1)
        #expect(lines[0].indices == [0, 1, 2])
        #expect(lines[0].width == 162)
        #expect(lines[0].height == 14)
    }

    @Test
    func aLineBreaksWhenTheNextItemWouldOverflow() {
        // 40 + 6 + 50 = 96 fits in 100; adding 60 would need 162.
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 50, 60]),
            availableWidth: 100,
            spacing: spacing
        )

        #expect(lines.count == 2)
        #expect(lines[0].indices == [0, 1])
        #expect(lines[1].indices == [2])
    }

    @Test
    func anItemWiderThanTheRowKeepsItsOwnLineRatherThanVanishing() {
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 500, 30]),
            availableWidth: 100,
            spacing: spacing
        )

        #expect(lines.map(\.indices) == [[0], [1], [2]])
    }

    @Test
    func anUnconstrainedProposalMeasuresAsASingleLine() {
        // SwiftUI proposes `nil` width while measuring ideal size; that must not wrap.
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 50, 60]),
            availableWidth: .infinity,
            spacing: spacing
        )

        #expect(lines.count == 1)
    }

    @Test
    func aDegenerateWidthDoesNotWrapEveryItemOrHang() {
        for width in [CGFloat(0), -50, .nan] {
            let lines = CadenceFlowLayoutSupport.lines(
                itemSizes: sizes([40, 50]),
                availableWidth: width,
                spacing: spacing
            )
            #expect(lines.count == 1)
        }
    }

    @Test
    func noItemsMeansNoLinesAndNoSize() {
        let lines = CadenceFlowLayoutSupport.lines(itemSizes: [], availableWidth: 100, spacing: spacing)
        #expect(lines.isEmpty)
        #expect(CadenceFlowLayoutSupport.size(ofLines: lines, lineSpacing: lineSpacing) == .zero)
    }

    @Test
    func sizeIsTheWidestLineNotTheProposal() {
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 50, 60]),
            availableWidth: 300,
            spacing: spacing
        )
        let size = CadenceFlowLayoutSupport.size(ofLines: lines, lineSpacing: lineSpacing)

        #expect(size.width == 162)
        #expect(size.height == 14)
    }

    @Test
    func stackedLinesAddTheirHeightsAndTheGapsBetweenThem() {
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes([40, 50, 60]),
            availableWidth: 100,
            spacing: spacing
        )
        let size = CadenceFlowLayoutSupport.size(ofLines: lines, lineSpacing: lineSpacing)

        #expect(size.height == 32)
    }

    @Test
    func aTallerChipDoesNotShoveItsNeighboursOffTheLine() {
        let itemSizes = [CGSize(width: 40, height: 14), CGSize(width: 40, height: 24)]
        let lines = CadenceFlowLayoutSupport.lines(itemSizes: itemSizes, availableWidth: 200, spacing: spacing)
        let points = CadenceFlowLayoutSupport.placements(
            itemSizes: itemSizes,
            lines: lines,
            origin: .zero,
            spacing: spacing,
            lineSpacing: lineSpacing
        )

        // Both centred in a 24pt line.
        #expect(points[0].y == 5)
        #expect(points[1].y == 0)
    }

    @Test
    func eachLineStartsBackAtTheLeadingEdge() {
        let itemSizes = sizes([40, 50, 60])
        let lines = CadenceFlowLayoutSupport.lines(itemSizes: itemSizes, availableWidth: 100, spacing: spacing)
        let points = CadenceFlowLayoutSupport.placements(
            itemSizes: itemSizes,
            lines: lines,
            origin: CGPoint(x: 12, y: 8),
            spacing: spacing,
            lineSpacing: lineSpacing
        )

        #expect(points[0].x == 12)
        #expect(points[1].x == 58)
        #expect(points[2].x == 12)
        #expect(points[2].y == 26)
    }

    @Test
    func wrappingNeverDropsAnItem() {
        // The bug this layout replaced: content the row silently refused to show. Whatever the
        // widths, every item must appear on exactly one line, in order.
        let widthSets: [[CGFloat]] = [
            [30, 40, 50, 60, 70, 80, 90],
            [200, 10, 200, 10],
            [12],
            Array(repeating: 44, count: 20),
        ]

        for widths in widthSets {
            for availableWidth in [CGFloat(60), 100, 180, 402] {
                let lines = CadenceFlowLayoutSupport.lines(
                    itemSizes: sizes(widths),
                    availableWidth: availableWidth,
                    spacing: spacing
                )
                let placed = lines.flatMap(\.indices)
                #expect(placed == Array(widths.indices))
            }
        }
    }
}

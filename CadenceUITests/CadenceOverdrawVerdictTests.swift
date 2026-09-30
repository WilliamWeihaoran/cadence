import CoreGraphics
import XCTest

/// **Proof that the one hole in `assertFixtureImageIsUndrawnOver` does not swallow the defect it
/// guards** — T-1723, asked of bitmaps this file draws rather than of a window.
///
/// ### Why a synthetic fixture, in a UI-test target, launching nothing
///
/// The reading this suite is about is taken from a real window, and the tolerance it checks was
/// added because a real product affordance — the markdown editor's image-edit badge — makes the
/// assertion's old sentence (*every pixel inside the picture's box is that colour*) false by
/// design. A tolerance is always one step from being the thing that hides the defect, so the
/// question *does it still refuse an overdraw* has to be answerable **without** the surface: the
/// live one needs an app launch, a seeded store, a full-screen transition and an unlocked Mac,
/// and on the day this was written it could not be obtained at all
/// (`CadenceUITests` launched an app that published no accessibility tree — see the ledger).
///
/// A bitmap is not a window, and this suite claims nothing about the product. What it pins is the
/// **decision**: given a picture and something drawn on it, `CadenceUITestPixel.overdraw` says yes
/// or no for the reasons `BadgeAllowance` states. Nothing here launches an app, takes the pointer
/// or reads the screen, so it carries neither the interactive opt-in nor the locked-screen guard
/// and runs in a default `-only-testing:CadenceUITests`.
@MainActor
final class CadenceOverdrawVerdictTests: XCTestCase {

    // MARK: - The fixture

    private enum Paint {
        /// The seeded picture's colour, as `CadenceUITestScenarioSeed` draws it.
        static let picture = CadenceUITestPixel.Colour(r: 255, g: 0, b: 255)
        /// A neutral field around it — not strongly saturated, so the block finder ignores it.
        static let field = CadenceUITestPixel.Colour(r: 60, g: 60, b: 62)
        /// The badge: blue, saturated, and drawn ON the picture.
        static let badge = CadenceUITestPixel.Colour(r: 30, g: 90, b: 220)
    }

    /// A 5:8 magenta block on a neutral field, plus whatever `marks` paint on top of it.
    ///
    /// The block is 640×400 because that is the size the live reading measured, so the allowance
    /// this exercises is the size the live one computes.
    private func makeBitmap(marks: [(rect: CGRect, colour: CadenceUITestPixel.Colour)]) throws
        -> (bitmap: CadenceUITestPixel.Bitmap, block: CadenceUITestPixel.Block)
    {
        let width = 900
        let height = 700
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)

        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CGContext's origin is bottom-left and `Bitmap` indexes top-down, so every rect below is
        // flipped once, here, rather than at each call site.
        func fill(_ rect: CGRect, _ colour: CadenceUITestPixel.Colour) {
            context.setFillColor(
                red: CGFloat(colour.r) / 255, green: CGFloat(colour.g) / 255,
                blue: CGFloat(colour.b) / 255, alpha: 1
            )
            context.fill(CGRect(
                x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height
            ))
        }
        fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), Paint.field)
        fill(picture, Paint.picture)
        for mark in marks { fill(mark.rect, mark.colour) }

        let image = try XCTUnwrap(context.makeImage())
        let bitmap = try XCTUnwrap(
            CadenceUITestPixel.Bitmap(cgImage: image, pointWidth: CGFloat(width)),
            "could not read the synthetic bitmap"
        )
        let block = try XCTUnwrap(
            CadenceUITestPixel.dominantSaturatedBlock(in: bitmap),
            "the fixture's own picture was not found, so nothing below is about the allowance"
        )
        // The instrument before the assertions: a block finder that had drifted onto the field, or
        // onto the badge, would make every verdict below a verdict about the wrong rectangle.
        XCTAssertEqual(block.colour, Paint.picture, "the block finder did not find the picture")
        XCTAssertEqual(block.bounds.width, picture.width, accuracy: 1, "the block is not the picture's width")
        XCTAssertEqual(block.bounds.height, picture.height, accuracy: 1, "the block is not the picture's height")
        return (bitmap, block)
    }

    /// A square of `side` at a corner of `block`, inset by `margin` from both edges — the shape
    /// the editor draws its badge in.
    private func badgeSquare(in block: CGRect, side: CGFloat, margin: CGFloat) -> CGRect {
        CGRect(x: block.maxX - margin - side, y: block.maxY - margin - side, width: side, height: side)
    }

    // MARK: - The control

    func testAPictureWithNothingOnItIsClean() throws {
        let (bitmap, block) = try makeBitmap(marks: [])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertEqual(verdict.outsideAllowance, 0, "an untouched picture reports pixels outside the allowance")
        XCTAssertEqual(verdict.insideAllowance, 0, "an untouched picture reports pixels inside the allowance")
        XCTAssertTrue(verdict.isClean, "an untouched picture is not clean, so every refusal below is meaningless")
    }

    // MARK: - What the allowance is FOR

    func testTheImageEditBadgeInItsCornerIsTolerated() throws {
        // 36pt on a side, 8pt in from both edges — the shape and scale the live reading measured
        // (1228 px, about 35 on a side).
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)
        let badge = badgeSquare(in: picture, side: 36, margin: 8)
        let (bitmap, block) = try makeBitmap(marks: [(badge, Paint.badge)])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)

        XCTAssertEqual(
            verdict.outsideAllowance, 0,
            "the badge spills outside its own allowance (\(verdict.outsideBounds) vs \(verdict.allowance)) — "
            + "the corner square is too small for the affordance it was sized for"
        )
        XCTAssertGreaterThan(
            verdict.insideAllowance, 0,
            "the allowance absorbed nothing, so this test would pass with the badge absent and proves nothing"
        )
        XCTAssertTrue(verdict.isClean, "the image-edit badge is refused, which is the false red T-1723 is about")
    }

    // MARK: - What it must still refuse

    /// **The discriminating case.** The same number of foreign pixels, the same colour, moved off
    /// the corner. A tolerance expressed as a COUNT passes this; one expressed as a PLACE does not.
    func testTheSameBadgeMovedOffTheCornerIsRefused() throws {
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)
        let corner = badgeSquare(in: picture, side: 36, margin: 8)
        let middle = CGRect(x: picture.midX - 18, y: picture.midY - 18, width: 36, height: 36)
        let (cornerBitmap, cornerBlock) = try makeBitmap(marks: [(corner, Paint.badge)])
        let (middleBitmap, middleBlock) = try makeBitmap(marks: [(middle, Paint.badge)])

        let tolerated = CadenceUITestPixel.overdraw(in: cornerBitmap, block: cornerBlock)
        let refused = CadenceUITestPixel.overdraw(in: middleBitmap, block: middleBlock)

        // Identical marks: same colour, same size, same pixel count. Only the place differs.
        XCTAssertEqual(
            tolerated.insideAllowance + tolerated.outsideAllowance,
            refused.insideAllowance + refused.outsideAllowance,
            "the two fixtures do not paint the same number of pixels, so the comparison is not about position"
        )
        XCTAssertTrue(tolerated.isClean, "the corner mark is refused")
        XCTAssertFalse(refused.isClean, "a mark in the MIDDLE of the picture is tolerated — the hole is a count, not a place")
        XCTAssertGreaterThan(refused.outsideAllowance, 0, "the refusal is not attributed to pixels outside the allowance")
    }

    /// The defect the whole reading exists for: something long and thin drawn across the picture,
    /// which is what text looks like to a pixel counter.
    func testTextShapedOverdrawAcrossThePictureIsRefused() throws {
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)
        let line = CGRect(x: picture.minX + 20, y: picture.midY, width: picture.width - 40, height: 14)
        let (bitmap, block) = try makeBitmap(marks: [(line, Paint.badge)])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertFalse(verdict.isClean, "a line drawn across the picture is tolerated")
        XCTAssertGreaterThan(verdict.outsideAllowance, 1000, "the refusal did not see most of the line")
    }

    /// A line drawn along the **bottom edge** — it passes through the allowance, so it is the case
    /// closest to slipping past, and the one a corner-shaped hole must still catch on its way in.
    func testAnOverdrawThatPassesThroughTheAllowanceIsStillRefused() throws {
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)
        let line = CGRect(x: picture.minX + 20, y: picture.maxY - 30, width: picture.width - 40, height: 14)
        let (bitmap, block) = try makeBitmap(marks: [(line, Paint.badge)])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertGreaterThan(
            verdict.insideAllowance, 0,
            "the line does not reach the allowance at all, so this is not the case it claims to be"
        )
        XCTAssertFalse(verdict.isClean, "an overdraw along the bottom edge is tolerated because it clips the corner")
    }

    /// And the corner is an allowance for a badge, not for a painted corner: something that fits
    /// **entirely inside** the square is still refused once it stops looking like a badge.
    func testACornerFilledRatherThanBadgedIsRefused() throws {
        let picture = CGRect(x: 130, y: 150, width: 640, height: 400)
        // The allowance is round(min(634, 394) * 0.15) = 59px square. A 56px mark tucked into the
        // corner sits inside it and fills 90% of it.
        let filled = badgeSquare(in: picture, side: 56, margin: 1)
        let (bitmap, block) = try makeBitmap(marks: [(filled, Paint.badge)])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertEqual(
            verdict.outsideAllowance, 0,
            "the mark is not wholly inside the allowance (\(verdict.outsideBounds)), so this is not the case it claims"
        )
        XCTAssertTrue(
            verdict.theAllowanceIsFilledRatherThanBadged,
            "\(verdict.insideAllowance) of \(verdict.maximumInsideTheAllowance) allowed did not trip the fill bound"
        )
        XCTAssertFalse(verdict.isClean, "a corner painted over is tolerated because it landed in the badge's square")
    }

    // MARK: - And the hole stays small

    func testTheAllowanceIsATinyShareOfThePicture() throws {
        let (bitmap, block) = try makeBitmap(marks: [])
        let verdict = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertFalse(verdict.theAllowanceHasGrownTooLarge, "the allowance is over its own cap on an untouched picture")
        XCTAssertLessThan(
            verdict.allowanceShareOfThePicture, 0.02,
            "the badge allowance is \(String(format: "%.2f%%", verdict.allowanceShareOfThePicture * 100)) of the "
            + "picture — the assertion outside it is no longer about most of the picture"
        )
        XCTAssertGreaterThan(verdict.allowanceShareOfThePicture, 0, "there is no allowance at all, so nothing is being sized")
    }
}

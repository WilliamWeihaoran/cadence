// **macOS only — T-2074/T-2075.** Until this target was asked to build for an iOS Simulator it
// had no platform guards at all, because it had never been built for anything but macOS: it reaches
// AppKit, `XCUIElement.rightClick()`, `CGSessionCopyCurrentDictionary` and identifiers only the
// desktop surface publishes. The guard is here rather than around the individual call sites because
// nothing in this file is about iOS; the iOS half of the target is `CadenceIOSSeededStoreUITests`.
#if os(macOS)
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
    /// The block defaults to 640×400 because that is the size the live reading measured, so the
    /// allowance this exercises is the size the live one computes. `picture` is a parameter because
    /// T-1892 turned on a question the fixed size cannot ask: the allowance is a *share* of the
    /// picture and the badge is a *fixed* size, so the two only agree above some picture size, and
    /// finding that size means drawing more than one.
    private func makeBitmap(
        picture: CGRect = CGRect(x: 130, y: 150, width: 640, height: 400),
        marks: [(rect: CGRect, colour: CadenceUITestPixel.Colour)]
    ) throws
        -> (bitmap: CadenceUITestPixel.Bitmap, block: CadenceUITestPixel.Block)
    {
        let width = Int(picture.maxX) + 130
        let height = Int(picture.maxY) + 150

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
        // **`pointWidth` is the width in POINTS, so this declares a 2x bitmap** — which is what the
        // fixture actually draws: every mark below is in the 2x pixels the live Retina reading
        // works in (the product's 18pt badge is painted 36px). Handing it the pixel width would
        // claim a 1x shot and the allowance, which is sized in points, would come out half size.
        let bitmap = try XCTUnwrap(
            CadenceUITestPixel.Bitmap(cgImage: image, pointWidth: CGFloat(width) / ProductBadge.scale),
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
        // The allowance is the badge's own 26pt square at 2x — 52px — at the corner of the region
        // examined. A 46px mark 4px in from the picture's corner sits wholly inside it and fills
        // 78% of it, against the 48% the product's own badge fills.
        let filled = badgeSquare(in: picture, side: 46, margin: 4)
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

    // MARK: - The floor T-1892 measured and T-1955 moved

    /// The product's own badge, restated — a UI-test bundle cannot import the app module.
    ///
    /// `CadenceTextView.resizeHandleRect(for:)`, `MarkdownEditorInteractionSupport.swift:519`:
    /// `NSRect(x: imageRect.maxX - 22, y: imageRect.maxY - 22, width: 18, height: 18)`. So **18pt
    /// on a side, 4pt in from both edges**, and at 2x that is the 36/8 the tolerated-badge case
    /// above already uses. These are the two numbers the allowance has to cover.
    private enum ProductBadge {
        static let sidePoints: CGFloat = 18
        static let marginPoints: CGFloat = 4
        static let scale: CGFloat = 2
        static var sidePixels: CGFloat { sidePoints * scale }
        static var marginPixels: CGFloat { marginPoints * scale }
    }

    /// `MarkdownImageAssetService.minDisplayWidth`, restated for the same reason. A picture this
    /// wide is not a degenerate case: it is the narrowest the product will ever draw one.
    private static let minimumLegalPictureWidthPoints: CGFloat = 120

    /// **The repair, stated as the property it buys (T-1955).** The square is the product's badge
    /// plus its own inset on the far side, and nothing about the picture enters into it — so two
    /// pictures a factor of three apart in area get the *same* allowance and the *same* fill bound.
    ///
    /// That is exactly the property T-1723's share-of-the-shorter-side did not have, and its
    /// absence is what put the floor at 148pt. A pin rather than a drawing assertion: if someone
    /// re-tunes the square back into a share of the picture, this says so by name before the sweep
    /// below has to re-derive it.
    func testTheAllowanceIsSizedFromTheProductsBadgeRatherThanFromThePicture() throws {
        let allowance = CadenceUITestPixel.BadgeAllowance.imageEditBadge
        XCTAssertEqual(
            allowance.badgeSidePoints, ProductBadge.sidePoints,
            "the allowance is not sized from resizeHandleRect's 18pt side"
        )
        XCTAssertEqual(
            allowance.badgeMarginPoints, ProductBadge.marginPoints,
            "the allowance is not sized from resizeHandleRect's 4pt inset"
        )

        let large = try verdictForTheProductsBadge(on: CGRect(x: 130, y: 150, width: 640, height: 400))
        let small = try verdictForTheProductsBadge(on: CGRect(x: 130, y: 150, width: 240, height: 150))
        XCTAssertEqual(
            large.allowance.width, small.allowance.width,
            "the allowance still moves with the picture's size — \(large.allowance) against \(small.allowance)"
        )
        XCTAssertEqual(
            large.allowance.width, allowance.sidePixels(atScale: ProductBadge.scale),
            "the allowance is not the badge's own square at this bitmap's scale"
        )
        XCTAssertEqual(
            large.maximumInsideTheAllowance, small.maximumInsideTheAllowance,
            "the fill bound still moves with the picture's size, so the two bounds are still coupled"
        )
    }

    /// **T-1955: the allowance now holds the product's own badge on the product's own narrowest
    /// picture.** Before the repair this was the defect — the same badge, on a picture at
    /// `MarkdownImageAssetService.minDisplayWidth`, was refused with nothing else drawn on it.
    ///
    /// Three readings, because one green reading would be indistinguishable from a verdict that had
    /// simply stopped discriminating: the small picture is clean, the large one T-1723 was built on
    /// is still clean, and **the same badge moved off the corner of the SMALL picture is still
    /// refused.** The last is the one that makes the first mean anything.
    func testTheBadgeAllowanceHoldsTheBadgeOnAPictureAtTheProductsMinimumWidth() throws {
        // The product's narrowest legal picture, at the fixture's 8:5, in 2x pixels.
        let shortSide = (Self.minimumLegalPictureWidthPoints * 5 / 8 * ProductBadge.scale).rounded()
        let longSide = (Self.minimumLegalPictureWidthPoints * ProductBadge.scale).rounded()
        let small = CGRect(x: 130, y: 150, width: longSide, height: shortSide)
        let large = CGRect(x: 130, y: 150, width: 640, height: 400)

        // The fixture is a legal rendering and not a degenerate one: the badge fits on it twice over.
        XCTAssertLessThan(
            ProductBadge.sidePixels + 2 * ProductBadge.marginPixels, shortSide,
            "the badge does not even fit on this picture, so the fixture is not a legal rendering"
        )

        let smallVerdict = try verdictForTheProductsBadge(on: small)
        let largeVerdict = try verdictForTheProductsBadge(on: large)

        XCTAssertGreaterThan(
            smallVerdict.insideAllowance, 0,
            "the allowance absorbed nothing on the small picture, so it would be clean with the badge "
            + "absent and this test proves nothing"
        )
        XCTAssertTrue(
            smallVerdict.isClean,
            "the product's own badge is STILL refused on a \(Int(longSide))×\(Int(shortSide))px picture — "
            + "outside \(smallVerdict.outsideAllowance) px at \(smallVerdict.outsideBounds); inside "
            + "\(smallVerdict.insideAllowance) of \(smallVerdict.maximumInsideTheAllowance) allowed; side share "
            + "\(String(format: "%.3f", smallVerdict.allowanceSideShareOfTheLongerSide))"
        )
        XCTAssertTrue(
            largeVerdict.isClean,
            "the badge is refused on the 640×400 picture T-1723 was built on, so the repair broke the case "
            + "that already worked"
        )

        // ── THE CONTROL ──────────────────────────────────────────────────────────────────────
        // The SAME badge, on the SAME narrow picture, moved off the corner. A verdict that bought
        // the green above by giving up on small pictures passes everything here too.
        let offCorner = CGRect(
            x: small.midX - ProductBadge.sidePixels / 2, y: small.midY - ProductBadge.sidePixels / 2,
            width: ProductBadge.sidePixels, height: ProductBadge.sidePixels
        )
        let (bitmap, block) = try makeBitmap(picture: small, marks: [(offCorner, Paint.badge)])
        let moved = CadenceUITestPixel.overdraw(in: bitmap, block: block)
        XCTAssertFalse(
            moved.isClean,
            "a \(Int(ProductBadge.sidePixels))px mark in the MIDDLE of the product's narrowest picture is "
            + "tolerated — the small picture's green was bought by making the verdict stop discriminating"
        )
        XCTAssertGreaterThan(
            moved.outsideAllowance, 0,
            "the refusal is not attributed to pixels outside the allowance"
        )
    }

    /// Where the floor actually is, measured rather than asserted at a point figure.
    ///
    /// Swept over the picture's shorter side, this prints the smallest one at which the product's
    /// own badge stops being refused, and asserts the only two things that are not this Mac's:
    /// **the threshold exists** (one side of it red, the other green) and **it is at or below the
    /// product's own minimum picture**, which is the inverse of what T-1892 measured and is the
    /// whole of T-1955.
    ///
    /// The sweep starts well below any legal picture on purpose. The floor is no longer the badge
    /// failing to fit — it fits at every size here — it is
    /// `maximumSideShareOfTheLongerSide` refusing to call a square that big a *corner*, and that
    /// bound only bites on pictures smaller than the product will draw.
    ///
    /// The figure this prints moved again under T-1957, from 55pt to 34pt, when that cap was asked
    /// of the longer side instead of the shorter one. Both readings are below the product's own
    /// minimum picture; what T-1957 changed is which *shapes* clear it, which the aspect sweep
    /// below is the measurement of.
    func testTheBadgeAllowanceOnlyHoldsAboveAPictureSizeThisSweepReports() throws {
        var firstClean: CGFloat?
        var lastRefused: CGFloat?
        for shortSide in stride(from: CGFloat(60), through: CGFloat(300), by: 2) {
            let picture = CGRect(x: 130, y: 150, width: (shortSide * 8 / 5).rounded(), height: shortSide)
            let verdict = try verdictForTheProductsBadge(on: picture)
            if verdict.isClean {
                if firstClean == nil { firstClean = shortSide }
            } else {
                lastRefused = shortSide
                // A clean reading followed by a refused one would mean the relation is not monotone
                // and the "threshold" below is not a threshold at all.
                XCTAssertNil(
                    firstClean,
                    "the verdict went clean at \(Int(firstClean ?? 0))px and refused again at \(Int(shortSide))px, "
                    + "so there is no single bound and the sweep's conclusion would be an artefact"
                )
            }
        }

        let threshold = try XCTUnwrap(
            firstClean,
            "the product's own badge is refused at every picture size up to 300px, so the allowance never holds"
        )
        let refused = try XCTUnwrap(lastRefused, "no picture size refused the badge, so there is no bound to report")
        XCTAssertLessThan(refused, threshold, "the sweep's two sides are not on opposite sides of each other")

        let thresholdPoints = threshold / ProductBadge.scale
        print(
            "T-1955 badge-allowance floor: the product's badge (\(Int(ProductBadge.sidePixels))px, "
            + "\(Int(ProductBadge.marginPixels))px in) is refused up to a shorter side of \(Int(refused))px and "
            + "tolerated from \(Int(threshold))px — \(Int(thresholdPoints))pt at \(Int(ProductBadge.scale))x. "
            + "The product's own minimum picture is \(Int(Self.minimumLegalPictureWidthPoints))pt wide. "
            + "T-1892 measured this floor at 294/296px — 148pt — before the allowance was sized from the badge."
        )

        // The finding, as a relation: the floor now sits AT OR BELOW the shorter side of the
        // narrowest picture the product will draw, so a legal rendering cannot be refused for being
        // small. T-1892's reading of the same relation was the other way round.
        let minimumLegalShortSide = (Self.minimumLegalPictureWidthPoints * 5 / 8 * ProductBadge.scale).rounded()
        XCTAssertLessThanOrEqual(
            threshold, minimumLegalShortSide,
            "the allowance still does not hold at the product's narrowest picture (\(Int(minimumLegalShortSide))px) "
            + "— the floor is \(Int(threshold))px and T-1955 is not fixed"
        )
    }

    // MARK: - The residue T-1955 left and T-1957 measured

    /// **T-1957, as the product varies it.** The sweep above moves the picture's *size* at a fixed
    /// 8:5. The product does not: `MarkdownImageAssetService.fittedSize` clamps the **width** to
    /// `minDisplayWidth` and takes the height from the image's own aspect, with **no height floor
    /// at all** — so at the clamp the picture's shorter side is `120 / ratio` points, and the free
    /// variable is the aspect ratio of the picture a user pasted.
    ///
    /// Swept over that, this reports the widest picture the allowance still holds on. The
    /// assertion is a relation and not a point figure: **every aspect the product can draw this
    /// badge on is tolerated**, where "can draw it on" is `resizeHandleRect`'s own requirement —
    /// `maxY - 22` with a height of 18 needs 22pt of picture or the badge is drawn off the top of
    /// the picture it belongs to, which is not a rendering to hold the verdict to.
    ///
    /// Before T-1957 this was red from 2.2:1 upward, which is where a 21:9 screenshot lives.
    func testTheBadgeAllowanceHoldsAtEveryAspectTheProductCanDrawTheBadgeOnAtItsMinimumWidth() throws {
        let widthPixels = (Self.minimumLegalPictureWidthPoints * ProductBadge.scale).rounded()

        // The widest picture the badge fits on at all, from the badge's own geometry.
        let badgeNeedsPoints = ProductBadge.sidePoints + ProductBadge.marginPoints
        let widestRatioTheBadgeFitsOn = Self.minimumLegalPictureWidthPoints / badgeNeedsPoints

        var widestClean: CGFloat?
        var narrowestRefused: CGFloat?
        for tenths in stride(from: 10, through: 80, by: 1) {
            let ratio = CGFloat(tenths) / 10
            let picture = CGRect(
                x: 130, y: 150, width: widthPixels, height: (widthPixels / ratio).rounded()
            )
            let verdict = try verdictForTheProductsBadge(on: picture)
            if verdict.isClean {
                // Refused-then-clean-again would mean the relation is not monotone and the
                // "widest tolerated" below would be an artefact of where the sweep stopped.
                XCTAssertNil(
                    narrowestRefused,
                    "the verdict refused at \(String(format: "%.1f", narrowestRefused ?? 0)):1 and went clean "
                    + "again at \(String(format: "%.1f", ratio)):1, so there is no single bound here"
                )
                widestClean = ratio
            } else if narrowestRefused == nil {
                narrowestRefused = ratio
            }
        }

        let widest = try XCTUnwrap(
            widestClean,
            "the product's own badge is refused at EVERY aspect ratio, so the allowance never holds"
        )
        let tolerated = String(format: "%.1f", widest)
        let refusedFrom: String
        if let narrowestRefused {
            refusedFrom = String(format: "%.1f", narrowestRefused) + ":1"
        } else {
            refusedFrom = "no ratio in this sweep"
        }
        let fitsTo = String(format: "%.2f", widestRatioTheBadgeFitsOn)
        let clampPoints = Int(Self.minimumLegalPictureWidthPoints)
        let clampPixels = Int(widthPixels)
        let scale = Int(ProductBadge.scale)
        print(
            "T-1957 badge-allowance aspect ceiling: at the product's minimum width "
            + "(\(clampPoints)pt, \(clampPixels)px at \(scale)x) the product's badge is tolerated up to "
            + "\(tolerated):1 and refused from \(refusedFrom). The badge itself stops fitting on the "
            + "picture at \(fitsTo):1. T-1955 left this ceiling at 2.2:1, which refuses a 21:9 "
            + "screenshot at the clamp."
        )

        XCTAssertGreaterThanOrEqual(
            widest, widestRatioTheBadgeFitsOn,
            "the allowance stops holding at \(String(format: "%.1f", widest)):1, below the "
            + "\(String(format: "%.2f", widestRatioTheBadgeFitsOn)):1 at which the product can still draw this "
            + "badge — a legal rendering is refused with nothing drawn on it, which is T-1957"
        )
    }

    /// **The green above is not bought by giving up on wide pictures.** The same three decisions
    /// the 640×400 cases make, remade on a 4:1 picture at the product's clamp — the shape T-1957
    /// is about and the one the shorter-side cap refused outright.
    ///
    /// Without this, a verdict that simply stopped refusing anything below some height would pass
    /// the sweep above and be worthless.
    func testTheVerdictStillDiscriminatesOnAWidePictureAtTheProductsMinimumWidth() throws {
        let widthPixels = (Self.minimumLegalPictureWidthPoints * ProductBadge.scale).rounded()
        let picture = CGRect(x: 130, y: 150, width: widthPixels, height: (widthPixels / 4).rounded())

        let badged = try verdictForTheProductsBadge(on: picture)
        XCTAssertGreaterThan(
            badged.insideAllowance, 0,
            "the allowance absorbed nothing, so this would be clean with the badge absent"
        )
        XCTAssertTrue(
            badged.isClean,
            "the product's own badge is refused on a 4:1 picture at the clamp — outside "
            + "\(badged.outsideAllowance) px at \(badged.outsideBounds); inside \(badged.insideAllowance) of "
            + "\(badged.maximumInsideTheAllowance) allowed; side share "
            + "\(String(format: "%.3f", badged.allowanceSideShareOfTheLongerSide))"
        )

        // ── CONTROL ONE: the same badge, off the corner. ──────────────────────────────────────
        let middle = CGRect(
            x: picture.midX - ProductBadge.sidePixels / 2, y: picture.midY - ProductBadge.sidePixels / 2,
            width: ProductBadge.sidePixels, height: ProductBadge.sidePixels
        )
        let (movedBitmap, movedBlock) = try makeBitmap(picture: picture, marks: [(middle, Paint.badge)])
        let moved = CadenceUITestPixel.overdraw(in: movedBitmap, block: movedBlock)
        XCTAssertFalse(moved.isClean, "a mark in the middle of a wide picture is tolerated")
        XCTAssertGreaterThan(
            moved.outsideAllowance, 0, "the refusal is not attributed to pixels outside the allowance"
        )

        // ── CONTROL TWO: the corner painted over rather than badged. ──────────────────────────
        let filled = badgeSquare(in: picture, side: 46, margin: 4)
        let (filledBitmap, filledBlock) = try makeBitmap(picture: picture, marks: [(filled, Paint.badge)])
        let painted = CadenceUITestPixel.overdraw(in: filledBitmap, block: filledBlock)
        XCTAssertEqual(
            painted.outsideAllowance, 0,
            "the mark is not wholly inside the allowance (\(painted.outsideBounds)), so this is not that case"
        )
        XCTAssertTrue(
            painted.theAllowanceIsFilledRatherThanBadged,
            "\(painted.insideAllowance) of \(painted.maximumInsideTheAllowance) allowed did not trip the fill "
            + "bound on a wide picture"
        )
        XCTAssertFalse(painted.isClean, "a corner painted over on a wide picture is tolerated")
    }

    /// **And the corner cap still fires**, which is the half of T-1955 that must survive T-1957
    /// moving which side it is asked of. A region the square would be half of by area is refused
    /// outright, whatever is drawn on it — there is nowhere else in such a picture for an overdraw
    /// to be, so a verdict about it would carry no information.
    ///
    /// Two readings, because a cap that refuses *everything* is as useless as one that refuses
    /// nothing: the picture below the cap is refused and the one above it is clean.
    func testTheCornerCapStillRefusesAPictureTheAllowanceWouldBeMostOf() throws {
        let below = try verdictForTheProductsBadge(on: CGRect(x: 130, y: 150, width: 96, height: 96))
        XCTAssertTrue(
            below.theAllowanceHasGrownTooLarge,
            "the corner cap did not fire on a 96×96px picture the 52px square is most of — side share "
            + "\(String(format: "%.3f", below.allowanceSideShareOfTheLongerSide))"
        )
        XCTAssertFalse(below.isClean, "a picture the allowance is most of is judged clean")

        let above = try verdictForTheProductsBadge(on: CGRect(x: 130, y: 150, width: 120, height: 120))
        XCTAssertFalse(
            above.theAllowanceHasGrownTooLarge,
            "the cap fires on a 120×120px picture too, so it is a blanket refusal and not a threshold"
        )
        XCTAssertTrue(above.isClean, "a 120×120px picture with only the product's badge on it is refused")
    }

    /// One picture, the product's badge in its corner, nothing else.
    private func verdictForTheProductsBadge(on picture: CGRect) throws -> CadenceUITestPixel.OverdrawVerdict {
        let badge = badgeSquare(in: picture, side: ProductBadge.sidePixels, margin: ProductBadge.marginPixels)
        let (bitmap, block) = try makeBitmap(picture: picture, marks: [(badge, Paint.badge)])
        return CadenceUITestPixel.overdraw(in: bitmap, block: block)
    }
}
#endif

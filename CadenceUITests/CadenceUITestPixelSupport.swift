import AppKit
import CoreGraphics
import XCTest

/// Reading a screenshot as **numbers**, so a composed-window test can say something falsifiable
/// about what was drawn rather than attach a picture for a human to squint at.
///
/// It exists because the four defects found by hand in the week before this was written were all
/// defects of *drawing* — a section that flickered, a divider lit as though focused, a header at
/// the wrong offset, text on top of a picture — and none of them is expressible in the
/// accessibility tree. The tree knows a row exists and where its box is. It does not know what
/// colour the box came out.
///
/// **This is the weakest kind of evidence in the suite and is labelled as such at every call
/// site.** A pixel assertion fails for reasons that have nothing to do with the code: a different
/// display profile, a stray notification window, the user's appearance setting. So the assertions
/// built on it are stated as *invariants of a fixture the test itself planted* — "every pixel
/// inside the magenta block is magenta" — never as "this screen looks like that reference image".
/// There is no golden image in this target and there should not be one.
enum CadenceUITestPixel {

    /// A screenshot flattened into 8-bit sRGB RGBA, so channel order and bit depth are this type's
    /// business rather than whatever `XCUIScreenshot` handed back on the day.
    struct Bitmap {
        let width: Int
        let height: Int
        /// Points per pixel of the element the shot was taken of — 2 on a Retina display. Needed to
        /// map an `XCUIElement.frame`, which is in points, onto this.
        let scale: CGFloat
        private let pixels: [UInt8]

        init?(screenshot: XCUIScreenshot, pointWidth: CGFloat) {
            let image = screenshot.image
            var proposed = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                return nil
            }
            self.init(cgImage: cgImage, pointWidth: pointWidth)
        }

        init?(cgImage: CGImage, pointWidth: CGFloat) {
            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drew: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drew else { return nil }
            self.width = width
            self.height = height
            self.pixels = buffer
            self.scale = pointWidth > 0 ? CGFloat(width) / pointWidth : 1
        }

        func colour(x: Int, y: Int) -> Colour? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let i = (y * width + x) * 4
            return Colour(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2])
        }
    }

    struct Colour: Hashable {
        let r: UInt8
        let g: UInt8
        let b: UInt8

        /// How far apart two colours are, as the largest per-channel difference. Chebyshev rather
        /// than Euclidean on purpose: the question asked of it is always "is anything *else* drawn
        /// here", and one channel moving is enough to mean yes.
        func distance(to other: Colour) -> Int {
            max(abs(Int(r) - Int(other.r)), max(abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b))))
        }

        /// Saturated in the crude sense the fixture needs: some channel much larger than another.
        /// Every neutral in Cadence's palette — every grey, every near-black background, every
        /// white — fails this, which is the whole point.
        var isStronglySaturated: Bool {
            let hi = Int(max(r, max(g, b)))
            let lo = Int(min(r, min(g, b)))
            return hi - lo >= 90 && hi >= 140
        }

        var description: String { "rgb(\(r),\(g),\(b))" }
    }

    struct Block {
        let colour: Colour
        /// In **pixels** of the bitmap it was found in, not points.
        let bounds: CGRect
        let pixelCount: Int
    }

    /// The largest run of one strongly saturated colour in the shot, which — given the fixture is
    /// the only saturated thing Cadence draws at any size — is the seeded picture.
    ///
    /// Found by search rather than by asking the accessibility tree where the picture is, because
    /// the picture is drawn *inside* an `NSTextView` and has no accessibility element of its own.
    /// That is not a gap to be filled by adding one: an identifier on a text attachment would
    /// describe where the layout manager thinks it put the image, and the defect being looked for
    /// is precisely a disagreement between that and what was painted.
    static func dominantSaturatedBlock(in bitmap: Bitmap) -> Block? {
        // **Two resolutions, for a reason that is not tidiness.** A full-screen Retina window is
        // about six million pixels, and this runs in an unoptimised test build; one dictionary
        // lookup per pixel per pass is tens of seconds of a UI test's budget spent counting. The
        // coarse pass strides, which is safe for *finding* a block hundreds of pixels across and
        // useless for measuring its edges — so the edges are measured at full resolution inside the
        // coarse box only.
        let step = 4
        var counts: [Colour: Int] = [:]
        var best: (colour: Colour, count: Int)?
        var coarse = CGRect.null

        for y in stride(from: 0, to: bitmap.height, by: step) {
            for x in stride(from: 0, to: bitmap.width, by: step) {
                guard let colour = bitmap.colour(x: x, y: y), colour.isStronglySaturated else { continue }
                let count = (counts[colour] ?? 0) + 1
                counts[colour] = count
                if count > (best?.count ?? 0) { best = (colour, count) }
            }
        }
        guard let best, best.count > 0 else { return nil }

        for y in stride(from: 0, to: bitmap.height, by: step) {
            for x in stride(from: 0, to: bitmap.width, by: step) {
                guard let colour = bitmap.colour(x: x, y: y), colour == best.colour else { continue }
                coarse = coarse.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        guard !coarse.isNull else { return nil }

        // Grow by more than the stride before refining, so a true edge that the coarse grid stepped
        // over is inside the window being searched.
        let pad = CGFloat(step * 2)
        let searchX0 = max(0, Int(coarse.minX - pad))
        let searchX1 = min(bitmap.width - 1, Int(coarse.maxX + pad))
        let searchY0 = max(0, Int(coarse.minY - pad))
        let searchY1 = min(bitmap.height - 1, Int(coarse.maxY + pad))

        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var exact = 0
        for y in searchY0...searchY1 {
            for x in searchX0...searchX1 {
                guard let colour = bitmap.colour(x: x, y: y), colour == best.colour else { continue }
                exact += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return Block(
            colour: best.colour,
            bounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
            pixelCount: exact
        )
    }

    /// Where the pixels inside `block` that are not the block's colour actually **are**, not just
    /// how many there are.
    ///
    /// The count alone was this reading's whole vocabulary until T-1723, and it could not tell the
    /// two findings apart that matter here: *the editor drew its image-edit badge on one corner*
    /// and *something is drawn across the picture*. Both are "1228 pixels are not magenta". A
    /// caller that knows where they landed can refuse the second while tolerating the first without
    /// widening its tolerance to a number that would swallow the defect too.
    ///
    /// `examined` is reported rather than re-derived by the caller because the inset that clears
    /// the block's own antialiased edge belongs to this function, and an allowance measured against
    /// the wrong rectangle is an allowance of the wrong size.
    struct ForeignPixels {
        let count: Int
        /// Bounding box of every foreign pixel, in the bitmap's **pixels**. `.null` when there are
        /// none — which is a different fact from a zero-sized box at the origin.
        let bounds: CGRect
        /// The region actually looked at: `block.bounds` inset on all four sides.
        let examined: CGRect

        var isEmpty: Bool { count == 0 }
    }

    /// Pixels inside `block`, inset to clear its own antialiased edge, that are not the block's
    /// colour, and where they are. **Zero is the assertion** everywhere except the one corner
    /// `CadenceTodayCompositionUITests` argues for explicitly.
    ///
    /// `excluding` is subtracted from the region examined, in bitmap pixels. The caller passes the
    /// region it has stated a reason to tolerate; this function does not know of any.
    static func foreignPixels(
        in bitmap: Bitmap,
        block: Block,
        inset: Int = 3,
        tolerance: Int = 12,
        excluding excluded: CGRect = .null
    ) -> ForeignPixels {
        let x0 = Int(block.bounds.minX) + inset
        let x1 = Int(block.bounds.maxX) - inset
        let y0 = Int(block.bounds.minY) + inset
        let y1 = Int(block.bounds.maxY) - inset
        let examined = CGRect(x: x0, y: y0, width: max(0, x1 - x0 + 1), height: max(0, y1 - y0 + 1))
        guard x0 <= x1, y0 <= y1 else {
            return ForeignPixels(count: 0, bounds: .null, examined: examined)
        }

        var foreign = 0
        var bounds = CGRect.null
        for y in y0...y1 {
            for x in x0...x1 {
                if !excluded.isNull, excluded.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))) { continue }
                guard let colour = bitmap.colour(x: x, y: y) else { continue }
                if colour.distance(to: block.colour) > tolerance {
                    foreign += 1
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return ForeignPixels(count: foreign, bounds: bounds, examined: examined)
    }

    /// The count alone, for callers that only ever wanted the number.
    static func foreignPixelCount(in bitmap: Bitmap, block: Block, inset: Int = 3, tolerance: Int = 12) -> Int {
        foreignPixels(in: bitmap, block: block, inset: inset, tolerance: tolerance).count
    }

    // MARK: - The one thing the product is allowed to draw on the picture (T-1723)

    /// **The allowance is a PLACE, not a number**, and that distinction is the whole of T-1723.
    ///
    /// `assertFixtureImageIsUndrawnOver` went red on its first ever execution — *1228 pixels
    /// inside (584, 500, 640, 400) are not rgb(255,0,255)* — and the window attached to that
    /// failure showed what they were: the markdown editor's small rounded **image-edit badge**, on
    /// the bottom-right corner of the picture. A product affordance. So the sentence the assertion
    /// was making, *every pixel inside the box is that colour*, was false by design and always had
    /// been.
    ///
    /// The obvious repair — raise a tolerance until 1228 pixels pass — **swallows the defect the
    /// assertion exists to catch**: text drawn over a picture is a few hundred pixels too. So
    /// nothing here is a count the picture as a whole is measured against. The allowance is one
    /// square at the corner the badge is drawn in; outside it the original assertion stands at
    /// zero, and the defect that motivated the reading — text across the picture — lands outside
    /// it by construction, because text spans the width it is drawn at.
    ///
    /// Two further bounds keep the hole from becoming the assertion:
    ///
    /// - the square may not exceed `maximumShareOfThePicture` of the block, so a mis-measured
    ///   block cannot quietly widen it, and
    /// - the badge may fill only `maximumFillOfTheAllowance` of the square, which is the cut
    ///   between *a badge sits in this corner* and *this corner has been painted over*.
    ///
    /// Every figure is argued from the measurement rather than being the measurement rounded: the
    /// badge measured 1228 px in a 640×400 block, about 35 px on a side, 0.5% of the picture.
    struct BadgeAllowance {

        /// The square's side, as a share of the picture's **shorter** side.
        ///
        /// 0.15 of the 400px-tall block measured is 60px against a ~35px badge. The multiple is
        /// deliberate: the badge draws at a fixed point size while the picture's pixel size moves
        /// with the window and the display, so a share that only just covered today's ratio would
        /// fail on a narrower pane for being narrow. A share rather than a pixel count for the
        /// reason every bound in `CadenceTodayRowCrushUITests` is a comparison — a pixel figure
        /// survives neither a display nor an Xcode major.
        let sideShareOfTheShorterSide: CGFloat

        /// And whatever that works out to, the hole may not exceed this share of the picture.
        /// 0.15² is 2.25% of a square block and less of an oblong one.
        let maximumShareOfThePicture: CGFloat

        /// How much of the square the badge may actually fill. The badge measured 1228 of the
        /// ~3600 px such a square holds — 34%. 0.7 is twice that.
        let maximumFillOfTheAllowance: CGFloat

        static let imageEditBadge = BadgeAllowance(
            sideShareOfTheShorterSide: 0.15,
            maximumShareOfThePicture: 0.03,
            maximumFillOfTheAllowance: 0.7
        )

        /// The square, at the **bottom-right** corner of the region examined. In the bitmap's
        /// pixels, whose origin is top-left, so that is max-x / max-y.
        func rect(over examined: CGRect) -> CGRect {
            guard examined.width > 0, examined.height > 0 else { return .null }
            let side = (min(examined.width, examined.height) * sideShareOfTheShorterSide).rounded()
            guard side > 0 else { return .null }
            return CGRect(x: examined.maxX - side, y: examined.maxY - side, width: side, height: side)
        }

        func maximumForeignPixels(in allowance: CGRect) -> Int {
            guard !allowance.isNull else { return 0 }
            return Int((allowance.width * allowance.height * maximumFillOfTheAllowance).rounded())
        }
    }

    /// What was drawn on the picture, where, and whether any of it is allowed.
    ///
    /// A verdict rather than three loose numbers at the call site, so the same decision can be put
    /// to a **synthetic** bitmap — one this target builds itself, with a badge placed deliberately
    /// — and shown to still refuse an overdraw. A tolerance whose discrimination has never been
    /// demonstrated is a tolerance nobody should believe, and the live surface this reading is
    /// taken from cannot be asked on demand.
    struct OverdrawVerdict {
        let allowance: CGRect
        let allowanceShareOfThePicture: CGFloat
        let insideAllowance: Int
        let outsideAllowance: Int
        /// Where the pixels outside the allowance are. `.null` when there are none.
        let outsideBounds: CGRect
        let maximumInsideTheAllowance: Int

        var somethingIsDrawnOutsideTheAllowance: Bool { outsideAllowance > 0 }
        var theAllowanceIsFilledRatherThanBadged: Bool { insideAllowance > maximumInsideTheAllowance }
        var theAllowanceHasGrownTooLarge: Bool { allowanceShareOfThePicture > allowanceCap }
        var isClean: Bool {
            !somethingIsDrawnOutsideTheAllowance
                && !theAllowanceIsFilledRatherThanBadged
                && !theAllowanceHasGrownTooLarge
        }

        fileprivate let allowanceCap: CGFloat
    }

    static func overdraw(
        in bitmap: Bitmap,
        block: Block,
        tolerating badge: BadgeAllowance = .imageEditBadge,
        inset: Int = 3,
        tolerance: Int = 12
    ) -> OverdrawVerdict {
        let all = foreignPixels(in: bitmap, block: block, inset: inset, tolerance: tolerance)
        let allowance = badge.rect(over: all.examined)
        let outside = foreignPixels(
            in: bitmap, block: block, inset: inset, tolerance: tolerance, excluding: allowance
        )
        let area = allowance.isNull ? 0 : allowance.width * allowance.height
        return OverdrawVerdict(
            allowance: allowance,
            allowanceShareOfThePicture: area / max(block.bounds.width * block.bounds.height, 1),
            insideAllowance: all.count - outside.count,
            outsideAllowance: outside.count,
            outsideBounds: outside.bounds,
            maximumInsideTheAllowance: badge.maximumForeignPixels(in: allowance),
            allowanceCap: badge.maximumShareOfThePicture
        )
    }

    /// The same question asked of one rectangle of the shot rather than the whole of it, in
    /// **pixels**. Used for the hover-release comparison, which must not be asked of the whole
    /// window: a window contains a clock, a caret and whatever the system decided to animate, and
    /// a comparison that includes them measures the desktop rather than the surface.
    static func differingPixelCount(_ lhs: Bitmap, _ rhs: Bitmap, in rect: CGRect, tolerance: Int = 8) -> Int? {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return nil }
        let x0 = max(0, Int(rect.minX)), x1 = min(lhs.width - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(lhs.height - 1, Int(rect.maxY))
        guard x0 <= x1, y0 <= y1 else { return nil }
        var differing = 0
        for y in y0...y1 {
            for x in x0...x1 {
                guard let a = lhs.colour(x: x, y: y), let b = rhs.colour(x: x, y: y) else { continue }
                if a.distance(to: b) > tolerance { differing += 1 }
            }
        }
        return differing
    }

    /// How many pixels differ between two shots of the same region — the hover-release check.
    ///
    /// Returns `nil` when the two bitmaps are different sizes, which is a *different* finding from
    /// "they differ" and must not be reported as a count of zero.
    static func differingPixelCount(_ lhs: Bitmap, _ rhs: Bitmap, tolerance: Int = 8) -> Int? {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return nil }
        var differing = 0
        for y in 0..<lhs.height {
            for x in 0..<lhs.width {
                guard let a = lhs.colour(x: x, y: y), let b = rhs.colour(x: x, y: y) else { continue }
                if a.distance(to: b) > tolerance { differing += 1 }
            }
        }
        return differing
    }
}

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

    // MARK: - The one thing the product is allowed to draw on the picture (T-1723, T-1955)

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
    /// ### The square is sized from the BADGE now, not from the picture (T-1955)
    ///
    /// T-1723 made the square a share of the picture's shorter side — `0.15` — and that is the one
    /// thing here that has been replaced rather than re-argued. Measured under T-1892 by the sweep
    /// in `CadenceOverdrawVerdictTests`: the product's own badge was **refused up to a shorter side
    /// of 294px and tolerated only from 296px — a 148pt floor at 2x** — while
    /// `MarkdownImageAssetService.minDisplayWidth` is **120pt**, 75pt tall at the seeded fixture's
    /// 8:5. So a legally sized picture failed the assertion with nothing drawn on it at all.
    ///
    /// And the floor was not where it looked. The purely *geometric* requirement — a square wide
    /// enough to hold a badge spanning `[maxX-44, maxX-8]` — clears at a shorter side of 286px, and
    /// 286px was still red. The binding bound was `maximumFillOfTheAllowance`: the badge is
    /// 36×36 = 1296px, `0.7 × side²` reaches 1296 only at `side = 44`, and
    /// `round(0.15 × (shorter − 5))` reaches 44 only at 295px. **At 290–294px the badge fitted
    /// inside its own square and was refused for overfilling it by two pixels** (1296 against
    /// 1294). Two bounds set one floor between them, so neither could be moved alone and moving
    /// either alone only lowered the floor to 286px.
    ///
    /// The repair **breaks the coupling rather than widening either bound**. The square is now the
    /// badge's own geometry — 18pt on a side with its own 4pt inset repeated on the far side, 26pt,
    /// scaled to the bitmap — which is a figure the product owns and which does not move with the
    /// picture's pixel size. The badge then fills 48% of it at *every* picture size and every
    /// scale, so `maximumFillOfTheAllowance` is back to meaning only what it was written to mean,
    /// and it is no longer half of a floor.
    ///
    /// Two bounds still keep the hole from becoming the assertion:
    ///
    /// - the square's side may not exceed `maximumSideShareOfTheLongerSide` of the region
    ///   examined, so a block mis-measured small cannot be swallowed by a corner that is most of
    ///   it, and
    /// - the badge may fill only `maximumFillOfTheAllowance` of the square, which is the cut
    ///   between *a badge sits in this corner* and *this corner has been painted over*.
    ///
    /// **The safeguard deliberately relaxed, and what it stops catching.** T-1723's first bound was
    /// an area cap, `maximumShareOfThePicture = 0.03`, and it is gone. It cost nothing, because it
    /// could never fire: with the side at `0.15 × shorter`, the area share is at most
    /// `0.0225 × shorter/longer`, which is **below 2.25% for every picture that has ever existed**
    /// and so below its own 3% cap unconditionally. A fixed-size square makes that question live
    /// again, and it is asked of a *side* rather than of the area because an area share moves with
    /// the picture's shape for reasons that have nothing to do with the allowance's size.
    ///
    /// ### The cap is asked of the LONGER side, not the shorter one (T-1957)
    ///
    /// T-1955 asked that cap of the **shorter** side, and that is the one thing here T-1957
    /// replaced rather than re-argued. The sentence the bound is making is *this square is a
    /// corner of this region and not most of it*, and a square is most of a region only when it is
    /// most of **both** of its sides. Asked of the shorter side alone, a 52px square on a
    /// 235×103px region — an ordinary wide picture — reads as over-large at 0.51 while being 11%
    /// of the region by area, and the picture is refused with nothing drawn on it.
    ///
    /// That was reachable, because `MarkdownImageAssetService.fittedSize` clamps the **width** to
    /// `minDisplayWidth` (120pt) and takes the height from the image's own aspect with **no height
    /// floor at all**. Measured over this file:
    ///
    /// - at the 120pt clamp the badge was tolerated up to **2.2:1** and refused from **2.3:1**
    ///   (exactly: anything wider than **2.222:1**, since a rendered height of 54pt or less leaves
    ///   an examined span under the 109px the cap needs), while `resizeHandleRect` can still be
    ///   drawn on a picture up to **5.45:1** — it needs 22pt of height. A 21:9 screenshot sits
    ///   inside that gap.
    /// - the refusal is a *band* of display widths, not a point: a picture of aspect `a` was
    ///   refused at every width in `[120pt, 54/a pt]` — **empty** at 16:9 and at 2:1, **9pt** wide
    ///   for a 3440×1440 ultrawide, **96pt** wide for a 4:1 panorama. T-1957 filed this as "about
    ///   2.18:1"; the arithmetic there insets the examined region by 3px on each side, and
    ///   `foreignPixels` takes `Int(maxX) - inset` against `minX + inset`, which is a span of
    ///   `side - 5` rather than `side - 6`.
    ///
    /// **Nothing was relaxed to close it.** The constant is still 0.5 and the square is still the
    /// badge's own geometry; only the side the question is asked of changed. What the old spelling
    /// cost was not strictness but information: on every picture it refused, it refused *for every
    /// input* — clean and overdrawn alike — so it could not pass, which is the mirror of the 3%
    /// area cap T-1955 deleted for never being able to fail.
    ///
    /// The cap still fires, and now fires only where the verdict genuinely cannot discriminate: a
    /// region whose **longer** side is under 104px is one the 52px square is at least half of by
    /// area, so there is nowhere else in it for an overdraw to be.
    ///
    /// ### What this allowance holds on a REAL window (T-1892, measured 2026-10-02)
    ///
    /// Every figure above was argued against synthetic bitmaps. The reading below is the first one
    /// ever taken against a window the window server actually drew — `CadenceUITests` on an
    /// unlocked Mac with the owner's interactive marker present, so
    /// `CadenceTodayCompositionUITests.testTodayHoldsItsGeometryAndItsPictureAcrossFullScreenAndHover`
    /// ran instead of skipping. Its activity log, in all three window states it checks:
    ///
    /// ```
    /// [windowed]    picture (584, 500, 640, 400) rgb(255,0,255); badge allowance (1170, 846, 52, 52)
    ///               (1.1% of the picture by area, 0.08 of its longer side)
    ///               held 1228 foreign px of 1893 allowed; outside it 0
    /// [full screen] picture (584, 436, 640, 400) rgb(255,0,255); badge allowance (1170, 782, 52, 52) …
    ///               held 1228 foreign px of 1893 allowed; outside it 0
    /// [restored]    picture (584, 500, 640, 400) rgb(255,0,255); badge allowance (1170, 846, 52, 52) …
    ///               held 1228 foreign px of 1893 allowed; outside it 0
    /// ```
    ///
    /// **Both of the questions that only a window could answer came back agreeing with the source
    /// reading, which is the less interesting of the two outcomes and is the one that happened.**
    ///
    /// - *Does a real window draw anything else inside the picture's box?* **No** —
    ///   `outside it 0`, three times, across a resize and a hover. `MarkdownEditorTextViewDecorations`
    ///   puts the backing plate at `insetBy(-1, -1)` and the selection ring at `insetBy(-2, -2)`
    ///   with `lineWidth 2`, both wholly outside `imageRect`, and `image.draw(in:)` is unclipped;
    ///   nothing contradicted that on the live surface. The editor draws exactly one thing inside
    ///   the picture's box and it is the resize handle.
    /// - *Does `dominantSaturatedBlock` pick the right block on a real surface?* **Yes** — it
    ///   returned 640×400px of `rgb(255,0,255)`, which is the fixture's 320×200pt at 2x to the
    ///   pixel, at the same origin before and after the full-screen round trip.
    ///
    /// The badge held **1228** foreign pixels. That is the figure a human read off a screenshot on
    /// 2026-09-29, reproduced here by the instrument, and it sits against the **1893** this
    /// allowance permits — so the live badge fills 45% of the square against the 70%
    /// `maximumFillOfTheAllowance` tolerates, and the hole is not being used up. Geometry predicted
    /// ~1210 for a 5pt-radius 36×36 rounded square; the extra 18px are its antialiased rim.
    struct BadgeAllowance {

        /// The badge's own side, in **points**: `CadenceTextView.resizeHandleRect(for:)`'s
        /// `width: 18, height: 18` (`MarkdownEditorInteractionSupport.swift:519`).
        let badgeSidePoints: CGFloat

        /// How far that rect is inset from the picture's corner, in **points** — the same line's
        /// `imageRect.maxX - 22` against a side of 18.
        let badgeMarginPoints: CGFloat

        /// The square's side may not exceed this share of the **longer** side of the region
        /// examined.
        ///
        /// This is the bound that says *a corner*. It replaces T-1723's unreachable 3%-of-the-area
        /// cap and it is reachable: with the side fixed at 52px at 2x, a region examined whose
        /// longer side is under 104px is refused outright, whatever is drawn on it — and such a
        /// region is one the square is at least half of by area, so a verdict about it would carry
        /// no information.
        ///
        /// **The longer side, not the shorter one (T-1957).** The share is unchanged at 0.5; only
        /// the side moved. Asked of the shorter side it refused any picture 54pt tall or less,
        /// which `fittedSize` reaches at the 120pt width clamp for anything wider than 2.222:1 — and it
        /// refused those pictures unconditionally, so it could not pass rather than could not
        /// fail. See the type's doc comment.
        ///
        /// Measured by
        /// `CadenceOverdrawVerdictTests.testTheBadgeAllowanceOnlyHoldsAboveAPictureSizeThisSweepReports`
        /// and `…HoldsAtEveryAspectTheProductCanDrawTheBadgeOnAtItsMinimumWidth`: the badge is
        /// refused up to a shorter side of 66px and tolerated from 68px — **34pt at 2x**, against
        /// 55pt under T-1955 and 148pt under T-1723 — and at the product's 120pt width clamp it is
        /// now tolerated at **every** aspect the badge can be drawn on, where it stopped at 2.2:1.
        /// The clamp puts the longer side at 240px, four times over the 109px this cap needs, so
        /// no legal rendering reaches it at any aspect.
        let maximumSideShareOfTheLongerSide: CGFloat

        /// How much of the square the badge may actually fill. At 2x the badge is 36×36 = 1296px
        /// and the square is 52×52 = 2704px, so the badge fills **48% at every picture size** —
        /// which is the property sizing the square from the badge buys. 0.7 is the cut between *a
        /// badge sits in this corner* and *this corner has been painted over*.
        let maximumFillOfTheAllowance: CGFloat

        static let imageEditBadge = BadgeAllowance(
            badgeSidePoints: 18,
            badgeMarginPoints: 4,
            maximumSideShareOfTheLongerSide: 0.5,
            maximumFillOfTheAllowance: 0.7
        )

        /// The square's side in the bitmap's pixels: the badge, with its own inset on **both**
        /// sides, at the bitmap's scale. 26pt, so 52px on a Retina shot and 26px on a 1x one — and
        /// it contains the badge at either, because both the badge and the square scale together.
        func sidePixels(atScale scale: CGFloat) -> CGFloat {
            ((badgeSidePoints + 2 * badgeMarginPoints) * max(scale, 1)).rounded()
        }

        /// The square, at the **bottom-right** corner of the region examined. In the bitmap's
        /// pixels, whose origin is top-left, so that is max-x / max-y.
        ///
        /// Clamped to `examined`, because a square hanging off the picture would tolerate pixels
        /// that are not in the picture at all.
        func rect(over examined: CGRect, scale: CGFloat) -> CGRect {
            guard examined.width > 0, examined.height > 0 else { return .null }
            let side = sidePixels(atScale: scale)
            guard side > 0 else { return .null }
            let square = CGRect(
                x: examined.maxX - side, y: examined.maxY - side, width: side, height: side
            )
            let clamped = square.intersection(examined)
            return clamped.isEmpty ? .null : clamped
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
        /// **Reported, not compared** — what share of the picture's area the hole came to, for the
        /// activity log of a green run. The bound is the side share below; this is the figure a
        /// reader wants when they ask how big the hole was.
        let allowanceShareOfThePicture: CGFloat
        /// **Compared.** The square the badge needs, against the **longer** side of the region
        /// examined. The unclamped side, so a square that had to be cut down to fit reads as
        /// over-large rather than as exactly fitting.
        ///
        /// The longer side is what makes this *a corner is not most of the picture* rather than
        /// *the picture is not short* — T-1957, argued on `maximumSideShareOfTheLongerSide`.
        let allowanceSideShareOfTheLongerSide: CGFloat
        let insideAllowance: Int
        let outsideAllowance: Int
        /// Where the pixels outside the allowance are. `.null` when there are none.
        let outsideBounds: CGRect
        let maximumInsideTheAllowance: Int

        var somethingIsDrawnOutsideTheAllowance: Bool { outsideAllowance > 0 }
        var theAllowanceIsFilledRatherThanBadged: Bool { insideAllowance > maximumInsideTheAllowance }
        var theAllowanceHasGrownTooLarge: Bool { allowanceSideShareOfTheLongerSide > allowanceSideCap }
        var isClean: Bool {
            !somethingIsDrawnOutsideTheAllowance
                && !theAllowanceIsFilledRatherThanBadged
                && !theAllowanceHasGrownTooLarge
        }

        fileprivate let allowanceSideCap: CGFloat
    }

    static func overdraw(
        in bitmap: Bitmap,
        block: Block,
        tolerating badge: BadgeAllowance = .imageEditBadge,
        inset: Int = 3,
        tolerance: Int = 12
    ) -> OverdrawVerdict {
        let all = foreignPixels(in: bitmap, block: block, inset: inset, tolerance: tolerance)
        let allowance = badge.rect(over: all.examined, scale: bitmap.scale)
        let outside = foreignPixels(
            in: bitmap, block: block, inset: inset, tolerance: tolerance, excluding: allowance
        )
        let area = allowance.isNull ? 0 : allowance.width * allowance.height
        let longerExamined = max(max(all.examined.width, all.examined.height), 1)
        return OverdrawVerdict(
            allowance: allowance,
            allowanceShareOfThePicture: area / max(block.bounds.width * block.bounds.height, 1),
            allowanceSideShareOfTheLongerSide: badge.sidePixels(atScale: bitmap.scale) / longerExamined,
            insideAllowance: all.count - outside.count,
            outsideAllowance: outside.count,
            outsideBounds: outside.bounds,
            maximumInsideTheAllowance: badge.maximumForeignPixels(in: allowance),
            allowanceSideCap: badge.maximumSideShareOfTheLongerSide
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

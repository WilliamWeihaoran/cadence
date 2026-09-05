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

    /// Pixels inside `block`, inset to clear its own antialiased edge, that are not the block's
    /// colour. **Zero is the assertion**: anything drawn over the picture lands here.
    static func foreignPixelCount(in bitmap: Bitmap, block: Block, inset: Int = 3, tolerance: Int = 12) -> Int {
        let x0 = Int(block.bounds.minX) + inset
        let x1 = Int(block.bounds.maxX) - inset
        let y0 = Int(block.bounds.minY) + inset
        let y1 = Int(block.bounds.maxY) - inset
        guard x0 <= x1, y0 <= y1 else { return 0 }

        var foreign = 0
        for y in y0...y1 {
            for x in x0...x1 {
                guard let colour = bitmap.colour(x: x, y: y) else { continue }
                if colour.distance(to: block.colour) > tolerance { foreign += 1 }
            }
        }
        return foreign
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

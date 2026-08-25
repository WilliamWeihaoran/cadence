import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// T-180. Three heading ramps for six levels, two of them on the same platform.
///
/// The macOS editor set `30/26/22/19/17/15`, the iOS editor `28/24/21/18/16/15`, and
/// `iOSMarkdownPreview` a third `25/21/18/16/15` whose `default:` swallowed level 5 *and* level 6.
/// So one note's H1 was 28pt with the caret in it and 25pt in the read-only preview, and an H5 came
/// out at body size.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning `MarkdownHeadingRamp`'s
/// numbers proves the ramp is right; it proves nothing about anybody *reading* it, and a ramp with
/// one reader is not a convergence. T-161 is the standing example — a committed fix reverted with
/// the whole suite green, because the tests pinned a helper while nothing observed the call sites.
/// So the ramp gets its values pinned *and* every surface that draws a heading gets a source scan
/// that fails the moment it goes back to a ramp of its own.
///
/// Source text is the only tool available for the iOS half: `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference. The
/// pattern follows `CadenceSharedTaskRowJobsTests` — exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan cannot make
/// the absence assertions pass silently.
struct MarkdownHeadingRampTests {

    // MARK: - The ramp itself

    /// The defect that was visible to a reader rather than to a diff: level 5 had no case, so an
    /// H5 in the preview rendered at the same size as an H6 *and* the same size as body text. Both
    /// surfaces answer all six levels now, and level 5 has its own answer.
    @Test func everyLevelHasItsOwnAnswerAndLevelFiveIsNotLevelSix() {
        for surface in MarkdownHeadingRamp.Surface.allCases {
            let sizes = MarkdownHeadingRamp.levels.map { MarkdownHeadingRamp.size(level: $0, surface: surface) }

            #expect(sizes.count == 6)
            #expect(Set(sizes).count == 6, "\(surface) reuses a size across two levels")
            #expect(
                MarkdownHeadingRamp.size(level: 5, surface: surface)
                    > MarkdownHeadingRamp.size(level: 6, surface: surface),
                "\(surface) H5 does not outrank H6"
            )
        }
    }

    /// A ramp that is not monotonic is not a hierarchy. Stated as a loop rather than six literals
    /// so a future platform tier cannot be added without satisfying it.
    @Test func aDeeperHeadingIsAlwaysSmaller() {
        for surface in MarkdownHeadingRamp.Surface.allCases {
            for level in 1..<6 {
                #expect(
                    MarkdownHeadingRamp.size(level: level, surface: surface)
                        > MarkdownHeadingRamp.size(level: level + 1, surface: surface),
                    "\(surface) H\(level) is not larger than H\(level + 1)"
                )
            }
        }
    }

    /// The figures, so a change to any of them is a deliberate change. iOS resolved to the
    /// **editor's** ramp: it was the only one of the two already complete at six levels, so
    /// adopting the preview's would have meant inventing the very H5 and H6 this ticket exists to
    /// supply — and its smaller numbers would have shrunk every heading in the surface the user
    /// actually types in.
    @Test func theTwoRampsAreTheEditorRampsTheyCameFrom() {
        #expect(MarkdownHeadingRamp.levels.map { MarkdownHeadingRamp.size(level: $0, surface: .mobile) }
            == [28, 25.5, 23.5, 21.5, 20, 18.5])
        #expect(MarkdownHeadingRamp.levels.map { MarkdownHeadingRamp.size(level: $0, surface: .desktop) }
            == [30, 26, 22, 19, 17, 15])
    }

    // MARK: - T-211: the ramp is quoted against a body, and on iOS the body moves

    /// **The T-211 defect, stated as the value it produced.** The mobile ramp was six absolute point
    /// sizes and its bottom two — H5 at 16 and H6 at 15 — were *smaller* than the ~17pt Dynamic Type
    /// body they head, so the two smallest headings rendered as small bold text. At an accessibility
    /// content size the body reaches 53pt and the whole ramp went under it.
    ///
    /// Asserted over a real span of `UIFont.preferredFont(forTextStyle: .body).pointSize` values
    /// (xSmall through AX5) rather than at the default alone, because "no fixed point size can stay
    /// above a body that scales" was the reason this was recorded as unfixable.
    @Test func everyMobileHeadingOutranksTheBodyItIsDrawnOn() {
        for body in Self.dynamicTypeBodyPointSizes {
            for level in MarkdownHeadingRamp.levels {
                let size = MarkdownHeadingRamp.size(level: level, surface: .mobile, bodyPointSize: body)
                #expect(size > body, "mobile H\(level) is \(size) on a \(body)pt body")
            }
        }
    }

    /// The same claim for macOS, which has always satisfied it — H6 at 15 over a fixed 14pt
    /// `NSFont`. Stated so the invariant belongs to the ramp rather than to one platform's numbers.
    @Test func everyDesktopHeadingOutranksItsFixedBody() {
        let body = MarkdownHeadingRamp.referenceBodyPointSize(for: .desktop)
        for level in MarkdownHeadingRamp.levels {
            #expect(MarkdownHeadingRamp.size(level: level, surface: .desktop) > body)
        }
    }

    /// A ramp that is a ratio scales; a ramp that is six constants does not. Doubling the body
    /// doubles every heading, which is the property that makes the assertion above hold at sizes
    /// nobody enumerated.
    @Test func theMobileRampScalesWithTheBodyItIsGiven() {
        let reference = MarkdownHeadingRamp.referenceBodyPointSize(for: .mobile)
        for level in MarkdownHeadingRamp.levels {
            let atReference = MarkdownHeadingRamp.size(level: level, surface: .mobile, bodyPointSize: reference)
            let atDouble = MarkdownHeadingRamp.size(level: level, surface: .mobile, bodyPointSize: reference * 2)
            #expect(abs(atDouble - atReference * 2) <= 0.5, "H\(level) did not scale: \(atReference) then \(atDouble)")
        }
    }

    /// Monotonicity is not a property of the quoted figures alone once they are scaled and rounded
    /// to half points, so it is asserted across the same span of bodies rather than once.
    @Test func theMobileRampStaysAHierarchyAtEveryTextSize() {
        for body in Self.dynamicTypeBodyPointSizes {
            for level in 1..<6 {
                #expect(
                    MarkdownHeadingRamp.size(level: level, surface: .mobile, bodyPointSize: body)
                        > MarkdownHeadingRamp.size(level: level + 1, surface: .mobile, bodyPointSize: body),
                    "H\(level) is not larger than H\(level + 1) on a \(body)pt body"
                )
            }
        }
    }

    /// Asking at a surface's own reference body must return the quoted figure *exactly*, not
    /// approximately — otherwise macOS's ramp would drift by a rounding step the moment the
    /// mechanism changed underneath it. This is what lets the desktop numbers above stay literals.
    @Test func askingAtTheReferenceBodyReturnsTheQuotedFigure() {
        for surface in MarkdownHeadingRamp.Surface.allCases {
            let reference = MarkdownHeadingRamp.referenceBodyPointSize(for: surface)
            for level in MarkdownHeadingRamp.levels {
                #expect(
                    MarkdownHeadingRamp.size(level: level, surface: surface, bodyPointSize: reference)
                        == MarkdownHeadingRamp.size(level: level, surface: surface)
                )
            }
        }
    }

    /// `scale` is the invariant in its own words: a heading is a multiple of body greater than one.
    /// It also pins the floor — the smallest mobile heading clears its body by at least as much as
    /// macOS's H6 clears its own, which is the margin this app already treats as legible.
    @Test func theSmallestHeadingClearsBodyByAtLeastTheMarginMacOSAlreadyUses() {
        let desktopFloor = MarkdownHeadingRamp.scale(level: 6, surface: .desktop)

        #expect(desktopFloor > 1)
        #expect(MarkdownHeadingRamp.scale(level: 6, surface: .mobile) >= desktopFloor)
    }

    /// A malformed level is clamped *before* it is scaled, so `#######` on a 53pt body is an H6 on a
    /// 53pt body rather than body text.
    @Test func aLevelOutsideMarkdownIsClampedOnAScaledBodyToo() {
        for body in Self.dynamicTypeBodyPointSizes {
            #expect(
                MarkdownHeadingRamp.size(level: 12, surface: .mobile, bodyPointSize: body)
                    == MarkdownHeadingRamp.size(level: 6, surface: .mobile, bodyPointSize: body)
            )
            #expect(
                MarkdownHeadingRamp.size(level: 0, surface: .mobile, bodyPointSize: body)
                    == MarkdownHeadingRamp.size(level: 1, surface: .mobile, bodyPointSize: body)
            )
        }
    }

    /// `UIFont.preferredFont(forTextStyle: .body).pointSize` across the eleven content size
    /// categories iOS ships, xSmall to AX5. Hard-coded because `CadenceTests` builds for macOS and
    /// cannot ask `UIFont` for them.
    private static let dynamicTypeBodyPointSizes: [CGFloat] = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]

    /// **The platforms keep separate ramps on purpose** — the same finding as
    /// `CadencePageHeaderSurface`'s third `.desktop` tier and `CadenceTaskRowSurface`'s. A ramp only
    /// means something against the body size under it, and the two bodies are not the same kind of
    /// measurement: a fixed 14pt `NSFont` against `UIFont.preferredFont(forTextStyle: .body)`, which
    /// is 17pt by default and larger at the accessibility sizes. This test exists so "the two ramps
    /// disagree" reads as a decision rather than as the next thing to tidy up.
    @Test func macOSKeepsItsOwnRamp() {
        let differing = MarkdownHeadingRamp.levels.filter {
            MarkdownHeadingRamp.size(level: $0, surface: .mobile)
                != MarkdownHeadingRamp.size(level: $0, surface: .desktop)
        }

        #expect(differing.count == MarkdownHeadingRamp.levels.count, "the desktop ramp has stopped being its own ramp")
    }

    /// Two tiers, not three. iPhone and iPad are one style, so a heading is the same size on both;
    /// a `.compact`/`.regular` split here would be a difference nobody asked for.
    @Test func thereIsOneRampPerPlatformAndNoPerWidthSplit() {
        #expect(MarkdownHeadingRamp.Surface.allCases.count == 2)
    }

    /// A `#######` line, or a parser that hands over a level it should not, gets H6 rather than
    /// falling through to body size — which is exactly how the preview lost its H5.
    @Test func aLevelOutsideMarkdownIsClamped() {
        for surface in MarkdownHeadingRamp.Surface.allCases {
            #expect(MarkdownHeadingRamp.size(level: 0, surface: surface) == MarkdownHeadingRamp.size(level: 1, surface: surface))
            #expect(MarkdownHeadingRamp.size(level: -3, surface: surface) == MarkdownHeadingRamp.size(level: 1, surface: surface))
            #expect(MarkdownHeadingRamp.size(level: 7, surface: surface) == MarkdownHeadingRamp.size(level: 6, surface: surface))
            #expect(MarkdownHeadingRamp.size(level: 99, surface: surface) == MarkdownHeadingRamp.size(level: 6, surface: surface))
        }
    }

    // MARK: - The call sites, which are the actual bug

    private static let mobileSurfaces = [
        "Cadence/iOS/iOSMarkdownStylingSupport.swift",
        "Cadence/iOS/iOSMarkdownPreview.swift",
    ]

    /// **The regression this file exists to catch.** The canvas and the read-only preview are the
    /// two surfaces that render the same note on the same device, so they have to resolve a heading
    /// through the same ramp *at the same tier*. Either one going back to a local `headingSize` is
    /// the T-180 bug again, and neither of them is a symbol this target can call.
    @Test func theIOSCanvasAndTheIOSPreviewBothResolveHeadingsThroughTheSharedRampAtTheSameTier() throws {
        for path in Self.mobileSurfaces {
            let code = strippingComments(try sourceFile(path))

            #expect(occurrences(of: "MarkdownHeadingRamp.size(", in: code) == 1, "\(path) does not read the shared ramp exactly once")
            #expect(code.contains("surface: .mobile"), "\(path) does not read the mobile tier")
            #expect(!code.contains("surface: .desktop"), "\(path) reads the desktop ramp")
            // T-211. `bodyPointSize` is optional so the desktop call site need not restate a
            // constant it owns; on iOS, omitting it silently pins the ramp to the *default* Dynamic
            // Type body and puts the bug straight back. Both mobile surfaces must state one, and
            // both must state `baseFont.pointSize` — a preview that quoted its own 15pt paragraph
            // size instead would render the same H1 at a different size from the canvas.
            #expect(code.contains("bodyPointSize:"), "\(path) resolves headings against the default body rather than the live one")
            #expect(code.contains("bodyPointSize: baseFont.pointSize")
                || code.contains("bodyPointSize: iOSMarkdownStyler.baseFont.pointSize"),
                "\(path) does not resolve headings against the canvas body")
        }
    }

    /// The macOS canvas is the third reader, and the only one on its tier. Its heading dispatch also
    /// stopped passing a marker length beside a point size — two parameters that had to agree, where
    /// `prefixLen` was always `level + 1` — so `prefixLen` gone is part of the fix, not a rename.
    @Test func theMacOSCanvasResolvesHeadingsThroughTheDesktopRamp() throws {
        let path = "Cadence/macOS/Editor/MarkdownEditorSupport.swift"
        let code = strippingComments(try sourceFile(path))

        #expect(occurrences(of: "MarkdownHeadingRamp.size(", in: code) == 1)
        #expect(code.contains("surface: .desktop"))
        #expect(!code.contains("surface: .mobile"))
        #expect(!code.contains("prefixLen"), "the heading dispatch still carries a marker length beside the level")
        #expect(occurrences(of: "level: 1", in: code) == 1, "the heading dispatch no longer passes six levels")
        #expect(occurrences(of: "level: 6", in: code) == 1)
    }

    /// A local ramp anywhere is the whole defect, so this looks for the *shape* of one rather than
    /// for the retired function names: a `switch` arm returning a heading point size. Every markdown
    /// surface on both platforms is scanned, and the file that is allowed to have one is named.
    @Test func nothingButTheRampDeclaresARamp() throws {
        let owner = "Cadence/Services/MarkdownHeadingRampSupport.swift"
        var offenders: [String] = []

        for path in try swiftFiles(under: "Cadence") where path != owner {
            let code = strippingComments(try sourceFile(path))
            guard code.contains("heading") || code.contains("Heading") else { continue }
            if code.range(of: "func headingSize", options: .regularExpression) != nil {
                offenders.append(path)
            }
        }

        #expect(offenders.isEmpty, "these files still declare a heading ramp: \(offenders)")
    }

    /// Exactly four files in the app know the ramp exists: the ramp, and its three readers. A fifth
    /// is not forbidden — a new markdown surface *should* read it — but it should show up here as a
    /// deliberate edit rather than as a silent fourth ramp somewhere.
    @Test func theRampHasExactlyThreeReaders() throws {
        var readers: [String] = []

        for path in try swiftFiles(under: "Cadence") {
            let code = strippingComments(try sourceFile(path))
            if code.contains("MarkdownHeadingRamp") { readers.append(path) }
        }

        #expect(readers.sorted() == [
            "Cadence/Services/MarkdownHeadingRampSupport.swift",
            "Cadence/iOS/iOSMarkdownPreview.swift",
            "Cadence/iOS/iOSMarkdownStylingSupport.swift",
            "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
        ].sorted(), "the ramp's readers changed: \(readers.sorted())")
    }

    /// Non-vacuity. Every assertion above is an absence or a count over files read off disk through
    /// `#filePath`; if that read silently returned nothing they would all pass. This one fails if
    /// the scanner is not looking at real bytes.
    @Test func theScannerIsReadingRealSource() throws {
        let ramp = try sourceFile("Cadence/Services/MarkdownHeadingRampSupport.swift")

        #expect(ramp.contains("case 1: return 28"))
        #expect(ramp.contains("case 1: return 30"))
        #expect(ramp.contains("roundedToHalfPoint"))
        #expect(try swiftFiles(under: "Cadence").count > 300)
        #expect(strippingComments("let x = 1 // case 1: return 9").contains("case 1") == false)
    }
}

private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var index = haystack.startIndex
    while let range = haystack.range(of: needle, range: index..<haystack.endIndex) {
        count += 1
        index = range.upperBound
    }
    return count
}

/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree), so read relative to it rather than resolving anything.
private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields absolute paths that `FileManager` has already resolved through that same symlink.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose — the ramp's own doc comment quotes all three retired ramps, and the doc comments at the
/// call sites name the numbers these tests forbid.
private func strippingComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}

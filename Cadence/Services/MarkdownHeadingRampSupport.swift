import CoreGraphics
import Foundation

/// **The markdown heading type ramp: one per platform, read by every surface that draws a heading.**
///
/// There were three ramps for six levels. The macOS editor set `30/26/22/19/17/15`, the iOS editor
/// `28/24/21/18/16/15`, and `iOSMarkdownPreview` a third `25/21/18/16/15` whose `default:` case
/// swallowed level 5 *and* level 6. Two of those three were on the same platform, so the same note's
/// H1 was 28pt with the caret in it and 25pt in the read-only preview, and an H5 came out at body
/// size — exactly the "canvas and preview render the same block differently" failure
/// `MarkdownRenderedBlockLimits` exists to stop.
///
/// **The two platforms keep separate ramps on purpose**, the same way `CadencePageHeaderSurface`
/// carries a third `.desktop` tier rather than aliasing `.regular`. A heading ramp is only
/// meaningful against the body size it sits above, and the two bodies are not even the same *kind*
/// of measurement: the macOS editor's is a fixed `NSFont.systemFont(ofSize: 14)`, the iOS editor's
/// is `UIFont.preferredFont(forTextStyle: .body)` — 17pt at the default Dynamic Type size and
/// larger at the accessibility sizes. Folding the two would flatten one platform's heading
/// hierarchy to make the other's numbers travel: macOS's ratios applied to a 17pt body put H1 at
/// 36pt, which is not a phone heading. Do not collapse `Surface` to a single ramp.
///
/// **iOS resolved to the editor's ramp, not the preview's.** Three reasons, in order of weight:
/// the editor's ramp is the only one of the two that is already complete at all six levels, so
/// adopting the preview's would have meant *inventing* an H5 and an H6 to close the very gap this
/// file exists to close; the editor is the surface the user spends time in and the preview is
/// read-only, so a disagreement should be resolved toward the canvas; and taking the preview's
/// smaller figures would have shrunk every heading in the editor, which is a visible regression
/// traded for nothing.
///
/// ## T-211: a size is quoted against a body, and on iOS the body moves
///
/// The mobile ramp used to be six absolute point sizes, and its bottom two — H5 at 16 and H6 at 15
/// — sat *below* the ~17pt Dynamic Type body they were supposed to head. The smallest two headings
/// read as small bold text, and at an accessibility text size the whole bottom half went under.
/// This file recorded that as a known asymmetry and declined to fix it.
///
/// It is fixed by making a size a **ratio**, not a number. Each surface quotes its ramp against a
/// reference body (`referenceBodyPointSize(for:)`) and `size(level:surface:bodyPointSize:)` scales
/// that quotation to whatever body the caller is actually drawing on. Two consequences worth
/// stating:
///
/// - **Desktop is unchanged, by construction.** Its body is a fixed 14pt `NSFont`, so it always
///   asks at its own reference and always gets `30/26/22/19/17/15` back.
/// - **Mobile's quoted figures moved**, and had to. Six levels that all outrank a 17pt body cannot
///   start at 18 — a monotone ramp whose floor is above body forces every level above it up. The
///   new quotation is an even ratio of roughly 1.09 per level from an H6 that clears body by the
///   same margin macOS's H6 clears its own (15/14 ≈ 1.07, the proven "smallest thing that still
///   reads as a heading" in this app). H1 is deliberately left at 28: the top of the ramp had no
///   defect and moving it would be a visible regression traded for nothing.
///
/// **Both iOS surfaces must pass the same body.** The canvas draws on
/// `UIFont.preferredFont(forTextStyle: .body)`; the preview's paragraph text is a fixed 15pt, but
/// it passes the canvas's body all the same, because "the same H1 is two sizes on one platform" is
/// the T-180 defect and a preview whose headings stopped scaling would be it again at every
/// non-default text size. `MarkdownHeadingRampTests` pins that both call sites pass a body size
/// rather than falling through to the default.
nonisolated enum MarkdownHeadingRamp {
    /// Which platform's ramp to read. Two cases, not three: iPhone and iPad are one style, so there
    /// is no `.compact`/`.regular` split here — a heading is the same size on both.
    enum Surface: CaseIterable {
        /// iOS and iPadOS — the `iOSMarkdownStyler` canvas and `iOSMarkdownPreview`.
        case mobile
        /// macOS — the `MarkdownEditorSupport` canvas. There is no macOS preview surface today; when
        /// one arrives it reads this and does not invent a fourth ramp.
        case desktop
    }

    /// The ATX heading levels markdown defines. Anything outside it is clamped, so a caller that
    /// hands over a level from a malformed `#######` line gets H6 rather than body size.
    static let levels = 1...6

    /// The body point size each surface's ramp is quoted against.
    ///
    /// This is not a style token — it is the denominator of the ratios below, and the only reason
    /// the quoted figures mean anything. macOS's is a real constant (`NSFont.systemFont(ofSize: 14)`
    /// in `MarkdownEditorSupport`); iOS's is the *default* Dynamic Type body, which is where
    /// `UIFont.preferredFont(forTextStyle: .body)` lands at the medium content size and not where it
    /// stays.
    static func referenceBodyPointSize(for surface: Surface) -> CGFloat {
        switch surface {
        case .mobile: return 17
        case .desktop: return 14
        }
    }

    /// The bold point size for an ATX heading at `level` on `surface`, drawn on a body of
    /// `bodyPointSize`.
    ///
    /// Passing `nil` asks at the surface's own reference body, which is right for a surface whose
    /// body does not move (macOS) and wrong for one whose body does (both iOS surfaces). The
    /// parameter is optional rather than required so the desktop call site does not have to restate
    /// a constant it already owns.
    static func size(level: Int, surface: Surface, bodyPointSize: CGFloat? = nil) -> CGFloat {
        let clamped = min(max(level, levels.lowerBound), levels.upperBound)
        let reference = referenceBodyPointSize(for: surface)
        let body = bodyPointSize ?? reference
        guard reference > 0, body > 0 else { return quotedSize(level: clamped, surface: surface) }
        return roundedToHalfPoint(quotedSize(level: clamped, surface: surface) * (body / reference))
    }

    /// How far above the body a heading at `level` sits, as a multiple of it. The invariant every
    /// level has to satisfy — and the one the old mobile ramp broke at levels 5 and 6 — is that this
    /// is greater than 1.
    static func scale(level: Int, surface: Surface) -> CGFloat {
        let clamped = min(max(level, levels.lowerBound), levels.upperBound)
        return quotedSize(level: clamped, surface: surface) / referenceBodyPointSize(for: surface)
    }

    /// The ramp as it is quoted — the point size each level takes on that surface's reference body.
    ///
    /// Written as plain numbers rather than as ratios because a reader checking this against a
    /// screenshot is holding point sizes, not multiples.
    private static func quotedSize(level: Int, surface: Surface) -> CGFloat {
        switch surface {
        case .mobile:
            // Against a 17pt body. Every one of these clears it; the smallest by 1.09x, which is
            // the margin macOS's H6 has always had over its own body.
            switch level {
            case 1: return 28
            case 2: return 25.5
            case 3: return 23.5
            case 4: return 21.5
            case 5: return 20
            default: return 18.5
            }
        case .desktop:
            // Against a fixed 14pt body, and unchanged since T-180.
            switch level {
            case 1: return 30
            case 2: return 26
            case 3: return 22
            case 4: return 19
            case 5: return 17
            default: return 15
            }
        }
    }

    /// Half a point is the finest distinction a rendered glyph carries here, and rounding to it
    /// keeps a scaled ramp from arriving as `23.6470588`. The quoted figures are already multiples
    /// of a half point, so asking at the reference body returns them untouched rather than
    /// approximately.
    private static func roundedToHalfPoint(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

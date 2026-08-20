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
/// larger at the accessibility sizes. So macOS's larger absolute ramp is the *steeper* one relative
/// to its text (30/14 against 28/17), and folding the two would flatten one platform's heading
/// hierarchy to make the other's numbers travel. Do not collapse `Surface` to a single ramp.
///
/// **iOS resolved to the editor's ramp, not the preview's.** Three reasons, in order of weight:
/// the editor's ramp is the only one of the two that is already complete at all six levels, so
/// adopting the preview's would have meant *inventing* an H5 and an H6 to close the very gap this
/// file exists to close; the editor is the surface the user spends time in and the preview is
/// read-only, so a disagreement should be resolved toward the canvas; and taking the preview's
/// smaller figures would have shrunk every heading in the editor, which is a visible regression
/// traded for nothing.
///
/// One known asymmetry this deliberately does **not** paper over: on iOS, H5 (16) and H6 (15) fall
/// *below* the editor's ~17pt Dynamic Type body, so the smallest two headings read as small bold
/// text rather than as headings. That is not a ramp bug — no fixed point size can stay above a body
/// that scales with the user's text size — and fixing it properly means making the iOS editor ramp
/// relative to `UIFont.preferredFont(forTextStyle: .body).pointSize` rather than absolute. Recorded
/// here rather than fixed, because it is a different change with a different blast radius.
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

    /// The bold point size for an ATX heading at `level` on `surface`.
    static func size(level: Int, surface: Surface) -> CGFloat {
        let clamped = min(max(level, levels.lowerBound), levels.upperBound)

        switch surface {
        case .mobile:
            switch clamped {
            case 1: return 28
            case 2: return 24
            case 3: return 21
            case 4: return 18
            case 5: return 16
            default: return 15
            }
        case .desktop:
            switch clamped {
            case 1: return 30
            case 2: return 26
            case 3: return 22
            case 4: return 19
            case 5: return 17
            default: return 15
            }
        }
    }
}

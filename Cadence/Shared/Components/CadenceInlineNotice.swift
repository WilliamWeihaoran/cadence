import SwiftUI

/// One line of text under a control, saying something about what just happened to it.
///
/// **Extracted from `CadenceInlineFailureNotice` (T-1077), which is now its `.failure` spelling.**
/// That component is 61 call sites of red text meaning *the thing you asked for did not happen*.
/// The reorder off-screen notice needs the same line in the same place and means the opposite —
/// the thing you asked for **did** happen, somewhere the current sort is not showing you. Drawing
/// that in `Theme.red` would say "error" in the app's own colour vocabulary about a store write
/// that succeeded, and hand-rolling a grey `Text` beside it would be the fourth copy of a stack
/// that exists precisely because there were four.
///
/// So the layout, the metrics and the dismissal rule are here once, and the tone is the parameter.
/// `CadenceInlineFailureNotice` keeps its name and its 61 call sites: the name carries the meaning
/// at those sites, and a rename would be churn in place of a decision.
///
/// Dismissal policy is unchanged and still stated on `CadenceInlineFailureNotice` — pass
/// `onDismiss` only when nothing the user does next clears the sentence.
struct CadenceInlineNotice: View {

    /// What the sentence is about, which is the only thing that varies between the two spellings.
    enum Tone {
        /// The act was refused. `Theme.red`, the app's one failure colour.
        case failure
        /// The act landed, and there is something about it the screen does not show. `Theme.dim`,
        /// the same weight as any other secondary line — deliberately *not* an accent, because an
        /// accent would compete with the row the sentence is about.
        case informational
        /// Nothing was refused and nothing is hidden — the state the user has just chosen is a
        /// legitimate one that is worth knowing about. `Theme.amber` (T-3169).
        ///
        /// **Why this is its own tier rather than one of the two above.** This file is deliberately
        /// opinionated about which colour means what, so a third one has to earn itself. `.failure`
        /// is the app's one refusal colour and would say "that did not happen" about a save that is
        /// about to succeed — the exact mis-statement that made the reorder notice need
        /// `.informational` in the first place. `.informational` is the opposite problem: `Theme.dim`
        /// is the weight of *any* secondary line, so a sentence saying a task is planned for after
        /// its own deadline would read as a caption rather than as something to look at. Amber is
        /// the colour this app already spends on "true, and worth your attention" — the work-hours
        /// band, the bundle-forming drop, the priority flag — and the notice is drawn at that weight
        /// for the same reason.
        ///
        /// A warning never gates the control it sits under. The caller keeps Save enabled and
        /// rewrites nothing; the sentence is expected to retire itself when the user changes what
        /// caused it, which is why no warning call site passes `onDismiss`.
        case warning

        var color: Color {
            switch self {
            case .failure: return Theme.red
            case .informational: return Theme.dim
            case .warning: return Theme.amber
            }
        }
    }

    let text: String
    var tone: Tone = .failure

    /// Supplied only by a caller whose notice has no next attempt to clear it.
    var onDismiss: (() -> Void)?

    /// **Converted for T-1410, because the panels that draw it are.** This sentence has no rigid
    /// geometry of its own — it is `fixedSize(vertical:)` inside whatever contains it — so it was
    /// safe to convert everywhere at once: on an unconverted surface the environment says `.fixed`
    /// and both figures below resolve to the 12 and the 22 they have always been. The one box here
    /// is the dismiss control, and it is derived from the glyph in it rather than left at 22.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    /// Size of the `x`, and of the square it is centred in. The square grows by what the glyph
    /// gained, not by what it was multiplied by.
    static let dismissGlyphSize: CGFloat = 10
    static let dismissControlSize: CGFloat = 22

    private var dismissControlBox: CGFloat {
        CadenceTypeScale.height(
            Self.dismissControlSize,
            holding: .metadata,
            textBase: Self.dismissGlyphSize,
            at: dynamicTypeSize,
            scaling: scaling
        )
    }

    @ViewBuilder
    var body: some View {
        if let onDismiss {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sentence
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .cadenceFont(.metadata, base: Self.dismissGlyphSize, weight: .bold)
                        .foregroundStyle(tone.color)
                        .frame(width: dismissControlBox, height: dismissControlBox)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .accessibilityLabel("Dismiss")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            sentence
        }
    }

    private var sentence: some View {
        Text(text)
            .cadenceFont(.metadata)
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

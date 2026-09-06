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

        var color: Color {
            switch self {
            case .failure: return Theme.red
            case .informational: return Theme.dim
            }
        }
    }

    let text: String
    var tone: Tone = .failure

    /// Supplied only by a caller whose notice has no next attempt to clear it.
    var onDismiss: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let onDismiss {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sentence
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tone.color)
                        .frame(width: 22, height: 22)
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

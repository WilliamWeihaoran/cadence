import Foundation

/// How long a deferred completion stays take-back-able.
///
/// **This is not an animation length** ([[T-8202]]). `TaskCompletionAnimationManager` and
/// `SectionCompletionAnimationManager` hold the `.done` write itself behind this interval, so it
/// is the undo window: a second tap inside it is a free take-back, and the ring the user watches
/// is that window drawn. Shortening it shortens how long a mis-tap can be withdrawn, which is why
/// the number is the owner's and is stated once.
///
/// **The owner's ruling, 2026-10-31 ([[T-9401]]): the window stays, the confirmation mark goes.**
/// Watching a completion run on an iOS Calendar timeline block, they ruled the behaviour good
/// except for the mark. The ring, the 1.2s window and the 168ms overlay fade are explicitly
/// approved and unchanged; only the check — and the cross a pending cancellation drew — is gone
/// from the fill. A filling ring now says nothing until it settles.
///
/// *What that supersedes, kept because the history explains the number:* the earlier ruling was
/// "1.2s total with the check mark at halfway, and move the section-completion constant to match".
/// 2.5s had read as slow for a reason that was not the total — the mark did not appear until 70%
/// of the way through, so the first 1.75s was ring with nothing said — and both halves were moved
/// together: 1.2s total, confirmation at 0.5, landing it at 0.6s. **The 1.2s half of that still
/// stands. The check-mark half does not**, so the three members that served the mark —
/// confirmationThreshold, confirmationDelay and showsConfirmation(at:), deliberately written
/// here without backticks because they resolve to nothing now — were removed with the behaviour
/// rather than left as an API describing a mark that never appears.
///
/// It lives in `Shared/` beside `CadenceTaskCompletionGlyph` because [[T-8203]] ports the deferred
/// completion to iOS; a second copy of this number is the drift that was already worth a ticket
/// when the two *managers* held one each. `TaskCompletionAnimationManager` is now in `Shared/`
/// beside it and drives the iOS rows, board cards and swipe as well ([[T-8203]]); the Kanban
/// column sweep (`SectionCompletionAnimationManager`) stays macOS's.
nonisolated enum CadenceTaskCompletionTiming {
    /// The whole deferral, and therefore the whole undo window.
    static let animationDuration: TimeInterval = 1.2
}

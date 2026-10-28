import Foundation

/// How long a deferred completion stays take-back-able, and when it says so.
///
/// **This is not an animation length** ([[T-8202]]). `TaskCompletionAnimationManager` and
/// `SectionCompletionAnimationManager` hold the `.done` write itself behind this interval, so it
/// is the undo window: a second tap inside it is a free take-back, and the ring the user watches
/// is that window drawn. Shortening it shortens how long a mis-tap can be withdrawn, which is why
/// the number is the owner's and is stated once.
///
/// **The owner's ruling:** "1.2s total with the check mark at halfway, and move the
/// section-completion constant to match." 2.5s read as slow for a reason that was not the total —
/// the confirmation mark did not appear until 70% of the way through, so the first 1.75s was ring
/// with nothing said. Both halves move together here: 1.2s total, confirmation at 0.5, which lands
/// it at 0.6s instead of 1.75s.
///
/// It lives in `Shared/` beside `CadenceTaskCompletionGlyph` because [[T-8203]] ports the deferred
/// completion to iOS; a second copy of these two numbers is the drift that was already worth a
/// ticket when the two *managers* held one number each. The managers themselves stay macOS-only —
/// iOS completes immediately today, and `CadenceTaskCompletionState.pendingCompletion` is
/// documented as macOS's alone until that port lands.
nonisolated enum CadenceTaskCompletionTiming {
    /// The whole deferral, and therefore the whole undo window.
    static let animationDuration: TimeInterval = 1.2

    /// The fraction of the window after which the control shows what it is about to do.
    ///
    /// "Halfway", literally: `showsConfirmation(at:)` is inclusive, so the mark lands *at* the
    /// midpoint rather than on the first frame after it.
    static let confirmationThreshold: Double = 0.5

    /// When the confirmation mark appears, in seconds from the tap. Derived so the two numbers
    /// above cannot disagree with the sentence that justifies them.
    static var confirmationDelay: TimeInterval { animationDuration * confirmationThreshold }

    /// Whether the completion control should be showing its check (or cross) yet.
    ///
    /// Takes raw progress and clamps it here, so no call site has to remember to: every caller
    /// already derives progress from `elapsed / animationDuration`, which runs past 1 whenever a
    /// frame lands after the window closed.
    static func showsConfirmation(at progress: Double) -> Bool {
        min(max(progress, 0), 1) >= confirmationThreshold
    }
}

#if os(macOS)
import Foundation

enum MarkdownEditorSyncTiming {
    static let derivedStateRefreshDelay: UInt64 = 150_000_000
    /// The idle debounce: a pause this long after the last keystroke commits the buffer.
    static let fallbackContentCommitDelay: UInt64 = 15_000_000_000
    /// **T-7810.** The ceiling on how long a buffer may stay uncommitted while typing continues.
    ///
    /// The fallback commit used to be a pure debounce, re-armed on every keystroke, so a user who
    /// never paused for 15 s never reached it, and an abrupt kill (RunningBoard's low-disk purge,
    /// [[T-7750]]; a crash; a force quit) lost everything since the last pause. With this ceiling
    /// the commit lands at most this long after the FIRST uncommitted keystroke, so the most an
    /// abrupt kill can lose is this window. Equal to the idle delay, so the commit rate under
    /// continuous typing is no higher than one per idle delay — the cost
    /// `NoteEditorPerformanceRegressionTests` guards.
    static let fallbackContentCommitMaxWait: UInt64 = 15_000_000_000

    /// When the next fallback commit should fire, for an edit made `now`.
    ///
    /// `pendingWindowStart` is when the oldest still-uncommitted edit was made, or `nil` when
    /// nothing is pending (the editor has no fallback task in flight) — then `now` opens a new
    /// window. The returned `windowStart` is what the editor keeps for the next keystroke; `delay`
    /// is the sleep for the re-armed task: the idle delay, cut short so the commit never lands
    /// later than `maxWait` after the window opened.
    static func fallbackContentCommitSchedule(
        pendingWindowStart: Date?,
        now: Date,
        idleDelay: UInt64 = fallbackContentCommitDelay,
        maxWait: UInt64 = fallbackContentCommitMaxWait
    ) -> (windowStart: Date, delay: UInt64) {
        let windowStart = min(pendingWindowStart ?? now, now)
        let elapsed = UInt64(max(0, now.timeIntervalSince(windowStart)) * 1_000_000_000)
        let remainingBeforeCeiling = maxWait > elapsed ? maxWait - elapsed : 0
        return (windowStart, min(idleDelay, remainingBeforeCeiling))
    }
}
#endif

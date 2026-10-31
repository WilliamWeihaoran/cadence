import Foundation

/// The markdown editors' commit timing, on both platforms.
///
/// macOS's five editors arm `fallbackContentCommitSchedule` with the 15 s idle delay and ceiling
/// ([[T-7810]]). **[[T-7873]]:** iOS's one editor, `iOSMarkdownEditingSurface`, arms the same
/// schedule through `iOSMarkdownEditorFlush` with its own 2.5 s idle delay and the
/// `iOSContentCommitMaxWait` ceiling, so this file moved from `Cadence/macOS/Views/` to `Shared/`.
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

    /// **[[T-7873]].** iOS's idle debounce: `iOSMarkdownEditingSurface` writes its binding this long
    /// after the last keystroke.
    static let iOSContentCommitDelay: TimeInterval = 2.5
    /// **[[T-7873]].** iOS's ceiling, measured from the first keystroke still held back.
    ///
    /// The surface's commit was a pure 2.5 s debounce, so typing that never paused for 2.5 s reached
    /// the binding only at the pause, and a crash or OS kill while the app was still active — when
    /// no scene hook runs ([[T-7871]]) — lost all of it. With this ceiling the most such a kill can
    /// lose is this window. It is not below the idle delay, so commits still land at least one
    /// idle delay apart and the highest commit rate a host whose binding saves the store can see
    /// (`CadenceCoreNoteSupport.update`) is unchanged; under unbroken typing such a host saves
    /// once per ceiling instead of not at all.
    static let iOSContentCommitMaxWait: TimeInterval = 10

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

    /// **[[T-7891]], the macOS half.** Whether a fallback commit armed with `delay` may sync the
    /// note's tags — mint a `Tag` for every inline `#name` in the body.
    ///
    /// Only a true idle commit may. One cut short by the ceiling fires while the user may still be
    /// typing, so a `#pro` of `#project` under the caret would be minted as a permanent orphan Tag.
    /// The macOS editors do not see the caret, so such a commit writes the body and defers the
    /// whole tag sync to the editor's next true flush point (idle, focus loss, switch, quit), which
    /// `NoteEditorPane` and `NotePanel` run even when the body is unchanged by then.
    static func fallbackCommitSyncsTags(
        delay: UInt64,
        idleDelay: UInt64 = fallbackContentCommitDelay
    ) -> Bool {
        delay >= idleDelay
    }
}

/// **[[T-7873]].** The ceiling's window for an editor whose held write lives in a handle rather than
/// in a `Task` it re-arms — `iOSMarkdownEditorFlush`.
///
/// `start` is when the oldest still-held keystroke was typed, or `nil` while nothing is held. A
/// keystroke made while the window is open keeps it; the handle closes it when the held write runs
/// or is dropped, so the next keystroke opens a new one. Restarting it on every keystroke would turn
/// the ceiling back into the pure debounce it replaces.
struct MarkdownEditorCommitWindow {
    private(set) var start: Date?

    /// The sleep before the write held at `now` should run: `idleDelay`, cut short so it never runs
    /// later than `maxWait` after the window opened. Opens the window when none is open.
    ///
    /// `deferringCeiling` ([[T-7891]]'s iOS half): the caret is inside an inline `#tag` still being
    /// typed, so a write now could mint the half-word (`#pro` of `#project`) as a permanent `Tag`
    /// through a host that syncs tags on write (`CadenceCoreNoteSupport.update`). The window still
    /// opens or stays open, but this edit gets only the idle delay; the first keystroke outside the
    /// token is capped again, so a ceiling that passed meanwhile fires on it at once.
    mutating func delay(
        forEditAt now: Date,
        idleDelay: TimeInterval,
        maxWait: TimeInterval,
        deferringCeiling: Bool = false
    ) -> TimeInterval {
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: start,
            now: now,
            idleDelay: Self.nanoseconds(idleDelay),
            maxWait: Self.nanoseconds(maxWait)
        )
        start = schedule.windowStart
        if deferringCeiling { return idleDelay }
        return TimeInterval(schedule.delay) / 1_000_000_000
    }

    /// The held write ran or was dropped.
    mutating func close() {
        start = nil
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }
}

/// **[[T-7891]], the iOS half.** Whether the caret is inside, or touching the end of, an inline
/// `#tag` — the token the user may still be typing.
///
/// Reads `MarkdownMetadataParser.inlineTagRegex`, the pattern tag sync mints from, over the caret's
/// line only, so the per-keystroke cost does not grow with the note. It may over-match (a `#`
/// inside inline code, which tag sync skips): that only defers a ceiling write to the idle delay.
enum MarkdownInlineTagCaret {
    static func isTypingInlineTag(in text: String, caret: Int) -> Bool {
        guard let regex = MarkdownMetadataParser.inlineTagRegex else { return false }
        let string = text as NSString
        let location = min(max(0, caret), string.length)
        let line = string.lineRange(for: NSRange(location: location, length: 0))
        for match in regex.matches(in: text, range: line) {
            let token = match.range
            if token.location <= location && location <= NSMaxRange(token) { return true }
        }
        return false
    }
}

/// **[[T-9123]].** What a buffered markdown editor does when the text it observes in the store
/// changes underneath it — a CloudKit import, an MCP write, another editor or panel on the same
/// record.
///
/// The macOS task-notes editors (`FocusNotesPanel`, `TaskDetailNotesSection`, `TaskNoteEditorPane`)
/// hold the typed text in a buffer and commit it on a fallback timer, focus loss, switch or quit.
/// They used to reload the buffer only on appear and on a record switch, so an outside change was
/// never drawn, and the next keystroke — or merely leaving the editor — wrote the stale buffer back
/// over it.
///
/// The rule:
/// - **Nothing pending** (no fallback commit armed): the buffer holds nothing the store lacks, so
///   it adopts the store's text. Returns that text, or `nil` when the buffer already matches.
/// - **A commit pending**: the buffer holds typing the store has not seen. It is kept, and the
///   pending commit writes it over the outside change when it fires — last writer wins, as before
///   this rule. Merging the two would need a three-way base the editors do not keep.
/// - **Buffer not loaded for this record**: the editor already draws the store's text; `nil`.
enum MarkdownEditorStoreAdoption {
    static func adoptedBuffer(
        storeText: String,
        buffer: String,
        bufferIsLoaded: Bool,
        commitIsPending: Bool
    ) -> String? {
        guard bufferIsLoaded, !commitIsPending, storeText != buffer else { return nil }
        return storeText
    }
}

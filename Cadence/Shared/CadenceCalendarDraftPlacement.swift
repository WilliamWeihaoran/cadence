import Foundation
import SwiftUI

/// **Where a drag-created draft is DRAWN** ([[T-8851]], under [[T-8201]]).
///
/// This is a question about the draft, not about the platform, so it is answered once here and
/// read by both timelines. Before it, the two surfaces answered it differently and neither
/// answered it well: iOS drew an all-day draft at `calendarStartHour * 60`, an hour tall, so a
/// draft begun at 7:30 AM jumped to the top of the column and off the visible pane; macOS left its
/// ghost on the pressed range, which reads as a timed block for something that is not timed.
///
/// The owner's call was neither: **an all-day draft belongs in the all-day strip**, where an
/// all-day item actually lives, on both platforms. The hour ladder then draws no block for it at
/// all — which is why this is an enum and not a `Bool` on a frame function: "no block here" and
/// "a block at this rect" are different answers, and a rect cannot carry the first one.
///
/// The draft **editor**'s anchor is a separate question and is deliberately not this one: it hangs
/// off the pressed range whatever the All day toggle says ([[T-8502]]), so that toggling All day
/// never moves the panel out from under the finger. See
/// `iOSCalendarTimelineBlockLayout.draftEditorAnchorFrame`.
nonisolated enum CadenceCalendarDraftPlacement: Equatable, Sendable {
    /// The timed canvas, at the draft's own pressed minute range.
    case hourLadder
    /// The day's all-day strip, as one chip. The hour ladder draws nothing.
    case allDayStrip

    static func placement(isAllDay: Bool) -> CadenceCalendarDraftPlacement {
        isAllDay ? .allDayStrip : .hourLadder
    }

    /// Whether the hour ladder draws a block for this draft at all.
    var drawsBlockInHourLadder: Bool { self == .hourLadder }
}

/// The all-day draft a day column is currently holding, published to the all-day strip ([[T-8851]]).
///
/// **It exists because the strip is the column's SIBLING, not its ancestor.** On both platforms the
/// strip is pinned outside the hour canvas's scroll view so that it stays put while the hours
/// scroll, and the draft is owned by the column the press landed in. There is no way for the
/// column to draw into the strip, so it says what it is drafting and the strip draws it — the same
/// shape `TimelineTaskDragSession` uses on the macOS canvas for the identical deep-writer,
/// sibling-reader problem.
///
/// One draft at a time, keyed by `yyyy-MM-dd`, because a press lands on exactly one day. A column
/// clears only the day it set, so a stale clear from a column that has already lost the draft
/// cannot take a live one down with it.
@MainActor
@Observable
final class CadenceCalendarAllDayDraftSession {
    /// The day whose strip is drawing a draft chip, or `nil` when no draft is all-day.
    private(set) var dateKey: String?
    /// The draft's title as last typed. Empty until the user types one.
    private(set) var title: String = ""

    init() {}

    func set(dateKey: String, title: String) {
        guard self.dateKey != dateKey || self.title != title else { return }
        self.dateKey = dateKey
        self.title = title
    }

    /// Clears the draft **only if this day still owns it**. A column that has already been
    /// replaced must not clear its successor's chip.
    func clear(dateKey: String) {
        guard self.dateKey == dateKey else { return }
        self.dateKey = nil
        title = ""
    }

    /// Clears whatever is there. For a host tearing the whole draft down.
    func clear() {
        guard dateKey != nil || !title.isEmpty else { return }
        dateKey = nil
        title = ""
    }

    func isDrafting(on dateKey: String) -> Bool {
        self.dateKey == dateKey
    }

    /// What the strip's chip says: the title the user has typed, or the one word that names what
    /// the chip is for while it is still blank.
    var chipTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CadenceCalendarAllDayDraftSession.blankChipTitle : trimmed
    }

    static let blankChipTitle = "All day"
}

extension EnvironmentValues {
    /// The day's all-day draft, installed by the page that owns both halves of a timeline — the
    /// hour canvas that holds the draft and the all-day strip that has to draw it ([[T-8851]]).
    ///
    /// Optional, and `nil` by default, for `timelineTaskDragSession`'s reason: a canvas drawn
    /// somewhere with no all-day strip is a legal thing, and should publish into nothing rather
    /// than require every host to invent a session it has no strip for.
    @Entry var calendarAllDayDraft: CadenceCalendarAllDayDraftSession? = nil
}

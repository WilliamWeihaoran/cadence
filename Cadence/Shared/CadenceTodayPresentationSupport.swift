import SwiftUI

struct CadenceTodaySummary: Hashable {
    let activeCount: Int
    let timedCount: Int
    let completedCount: Int

    /// The one quiet line that says what today holds, in the treatment
    /// `CadenceTodaySummary.line` follows: zeros omitted, `nil` when there is nothing to
    /// say, rendered as a single `Theme.dim` line rather than a rank of tinted chips.
    ///
    /// It replaced three `Theme.blue`/`Theme.purple`/`Theme.green` capsules reading
    /// "0 Active · 0 Timed · 0 Done" plus a second two-chip copy of the first two in the header —
    /// so an empty day, which is most days before it is planned, said "0" five times in three hues
    /// beside a header badge already reading 0.
    ///
    /// `activeCount` is deliberately absent: the header badge beside this line *is* the active
    /// count, and repeating it here is the duplication this replaced.
    var line: String? {
        var parts: [String] = []
        if timedCount > 0 { parts.append("\(timedCount) timed") }
        if completedCount > 0 { parts.append("\(completedCount) done") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum CadenceTodayPresentationSupport {
    static func summary(
        activeTasks: [AppTask],
        timedTasks: [AppTask],
        completedTasks: [AppTask]
    ) -> CadenceTodaySummary {
        CadenceTodaySummary(
            activeCount: activeTasks.count,
            timedCount: timedTasks.count,
            completedCount: completedTasks.count
        )
    }

    // `overdueSectionTitle` and `overdueSectionAccent` were here — the title and tint of the one
    // heading on Today that was not a list's name. The user removed the section, and neither
    // constant had a second reader, so both went with it rather than staying as a palette entry for
    // a heading that no longer exists. A task's lateness is stated by its row's own red flag.

    /// The heading over the day's finished work, on every Today. macOS said "Completed" and iOS
    /// said "Completed Today" for the same section over the same predicate — `completedAt` inside
    /// today, on both — so one of them was describing a logbook it was not showing.
    ///
    /// **That last clause was not true when it was written, and T-229 is what made it true.** iOS's
    /// `completedTodayTasks` also admitted anything do-dated or due-dated today, whatever day it
    /// was actually finished, so unifying the *title* had quietly put one heading over two
    /// predicates. Both platforms call `CadenceTaskQuerySupport.completedTodayTasks` now. Worth
    /// keeping as a warning about the shape: a comment asserting two call sites agree is not a
    /// check that they do.
    static let completedSectionTitle = "Completed Today"

    /// And its accent. `Theme.green` is `Theme.doneFill`'s hue and the completion circle's, so the
    /// heading agrees with the glyphs under it.
    // Computed, not stored: `Theme.green` is selectable (T-15) and a `static let` would
    // freeze on the palette active at first access.
    static var completedSectionAccent: Color { Theme.green }

    /// Today's empty state, on every platform. `iOSCompactTodayEmptyState` draws it on iOS and
    /// macOS's `TasksPanel` passes the same two strings to `EmptyStateView`; it is the only empty
    /// state Today has.
    ///
    /// macOS said "Nothing for today" over "Due-today and do-today tasks will appear here", which
    /// is a restatement of the page's scope rather than a next step. The name lost its `compact`
    /// qualifier when the third reader arrived — a shared constant named for one of its callers
    /// reads as that caller's private copy.
    ///
    /// The name is reused deliberately: an `emptyTitle` reading "Nothing planned for today" used to
    /// sit beside this, left over from the iPad's own five-card empty deck, and nothing had read it
    /// since that deck was deleted. Two spellings of one sentence, one of them unreachable, is how
    /// the hosts start saying different things again — so there is one, and it is this.
    static let emptyTitle = "Nothing planned"
    /// It said "Add a task above…" while the field it pointed at no longer existed on any width:
    /// compact capture is the tab bar's centre `+`, the iPad's is the floating one on this page,
    /// and macOS's is the `+ New Task` button on the task column's own header. A subtitle naming a
    /// control that is not on screen is worse than none.
    static let emptySubtitle = "Add a task with +, or schedule one from Inbox."

    // `emptyScheduleHint` used to sit here (T-520). It ends "…tap an hour to schedule one", which
    // is a sentence only a touch surface can say, and it had exactly one reader —
    // `iOSSchedulePanel`. macOS's own `SchedulePanel` draws no empty state at all, so nothing about
    // it was ever shared: it was iOS copy filed under `Shared/`, one Mac reader away from telling a
    // desktop user to tap. It lives in `Cadence/iOS/iOSSchedulePanelCopy.swift` now, and
    // `CadenceEmptyStateAuditTests.noMacReachableCopyAsksForATouchGesture` walks this folder as
    // well as `Cadence/macOS/`, so the next one cannot land here quietly.
}

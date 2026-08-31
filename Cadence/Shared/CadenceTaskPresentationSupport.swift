import Foundation
import SwiftUI

/// Which primary task row a figure is for.
///
/// `.compact` and `.regular` are iOS's two size classes. `.desktop` is macOS, and it is a third
/// tier rather than an alias for `.regular` for the same measured reason `CadencePageHeaderSurface`
/// has three: a Mac window is wider than an iPad and yet sets its rows *tighter*, because a pointer
/// can land on an 8pt-padded row and a finger cannot. `CadenceSidebarRowMetrics.rowHeight` is the
/// same split one column over, at 32 against 44.
///
/// It is a *tier*, not a knob: a host cannot pick one. A view gets the tier its platform and size
/// class report, which is the whole point of `CadenceTaskRowMetrics` having no density parameter.
nonisolated enum CadenceTaskRowSurface: String, CaseIterable, Sendable {
    case compact
    case regular
    case desktop
}

/// Every measurement a Cadence **primary task row** draws itself with: `iOSTaskRow` at either size
/// class, and `MacTaskRow` at `.desktop`.
///
/// This replaces `iOSTaskRowDensity`, a second axis each call site picked for itself. The two were
/// nearly the same thing: on a phone `.compact` and `.regular` resolved to the same horizontal
/// padding (11), the same completion glyph (20pt), the same row spacing (9) and the same secondary
/// line limit (1). They differed by 1pt of vertical padding, half a point of type — and the
/// **title line limit**, 1 against 2. So the axis' only real effect on a phone was that Today
/// truncated a task title to one line while Inbox and All Tasks, one tab of the same tab bar away,
/// wrapped it to two. It also inverted: `.compact` allowed *more* notes preview (80 characters)
/// than `.regular` did at that width (64), so Today showed less of the title and more of the note
/// about it.
///
/// There is deliberately **no density parameter here**, for the mirror of the reason
/// `CadenceTaskSurfaceOptions` has no size class: "iPhone Today's rows differ from iPhone Inbox's
/// rows" is no longer expressible. A host that wants a tighter row is describing a narrower *pane*,
/// and the pane is what size class already reports.
///
/// The cost, taken deliberately: the two hosts that passed `.compact` at *regular* width — the
/// calendar day inspector and the month agenda — now draw iPad-width rows in a fairly narrow pane.
/// That is one style at one width rather than a third setting, and they were the same rows that
/// made the iPad disagree with itself between its Today column and its Calendar tab.
///
/// **macOS reads six of these figures and pointedly not the rest, and that split is the finding.**
/// T-175 brought `MacTaskRow` onto this type; until then it hardcoded its own 14 / 8 / 15 / 11 / 6
/// inline while a shared metrics type sat here with five iOS readers and none on macOS — the same
/// shape `iOSPageHeaderMetrics` had before `5aa11dc` renamed it and gave macOS a tier. What macOS
/// takes: `horizontalPadding`, `verticalPadding`, `contentSpacing`, `badgeSpacing`,
/// `secondaryFontSize`, `titleFontSize`. What it deliberately does not, with the reason each time:
///
/// - **`titleLineLimit`.** macOS's row is a single `HStack` — title, `Spacer`, trailing metadata —
///   so its height is fixed and a two-line title reflows the entire row; iOS's is a `VStack` built
///   to grow. `titleLineLimit`'s own doc says "every surface", and it means every surface that
///   stacks. `MacTaskRow` is the exception it never named, so it is named here.
/// - **`completionGlyphSize` and `completionCircleDiameter`.** Not shared because they are not the
///   same measurement. iOS draws a real 16pt disc and ramps a *frame* around it to reach a 44pt
///   touch target, so the number is a layout box. macOS passes an SF Symbol **point size** to
///   `TaskCompletionProgressGlyph` — which is also its frame, and which its four macOS call sites
///   already set to 12 / 13 / 15 / 18 as a type ramp per surface. Folding them would push an iOS
///   touch-target ramp into a macOS type ramp and quietly resize four other controls. This is the
///   `cdf0896` pattern: an apparent fork that is two different jobs wearing one name.
/// - **`summarySpacing`, `secondaryLineLimit`, `notesPreviewLimit`.** The macOS row has no second
///   line and no notes preview, so nothing reads these on `.desktop`. They are still stated, at
///   `.compact`'s answers, because a macOS Today task column is a narrow pane and that is the tier
///   it would belong to — not left as a hole for the next agent to guess at.
///
/// `nonisolated` for the same reason `TaskOrdering` is: the project compiles with
/// `-default-isolation MainActor`, which would otherwise make even the synthesized `==`
/// main-actor isolated, and a value type describing paddings should not need an actor to compare.
nonisolated struct CadenceTaskRowMetrics: Equatable, Sendable {
    /// How many lines a task title gets. **One number, at every width and on every surface that
    /// stacks** — it is the thing T-78 was actually about. Two, because a truncated title on the
    /// screen you plan your day from is the worse of the two failures, and because it is what every
    /// task surface other than Today already showed. `MacTaskRow` is the one row that does not read
    /// it; the type's own doc above says why, and a test pins that the exception stays deliberate.
    static let titleLineLimit = 2

    /// The completion circle's drawn diameter. Constant: only its 44pt-reaching *frame* ramps.
    ///
    /// iOS only, and not because macOS was overlooked — macOS has no equivalent number to share.
    /// `TaskCompletionProgressGlyph` draws an SF Symbol, so the disc's diameter is a property of
    /// the glyph rather than a figure anybody sets.
    static let completionCircleDiameter: CGFloat = 16

    let horizontalPadding: CGFloat
    /// **The figure that has to stay split**, and the reason `.desktop` is a tier rather than a
    /// relabelling of `.regular`. 8pt is right under a pointer; a finger needs the 9–12 that keeps
    /// the row past 44pt tall. Flattening this to 12 would be the legible tidy-up and a real
    /// density regression on a Mac window showing three task columns at once — exactly what
    /// `CadenceSidebarRowMetrics.rowHeight` says about 32 against 44.
    let verticalPadding: CGFloat
    /// Between the completion circle, the task, and the estimate chip.
    let contentSpacing: CGFloat
    /// Between the title, the notes line, the chips, the tags and the subtask rows.
    let summarySpacing: CGFloat
    /// Between chips on one line of the attribute strip. The *line* spacing is not here — it is
    /// derived from the chip's own hit inset, and a layout ramp must not be able to shrink it.
    let badgeSpacing: CGFloat
    /// The layout size the completion glyph takes; its touch target is expanded to 44pt on top.
    let completionGlyphSize: CGFloat
    /// The task title.
    ///
    /// **15 on macOS against 13 on iOS, which reads inverted and is not.** 15pt is what every other
    /// macOS primary row and section title in this app is already set at (`InboxSupportViews`,
    /// `TasksPanelSectionViews`, `GlobalSearchSupportViews`), and 13 is what both iOS widths draw
    /// and what the chip ramp under it is measured against — `iOSTaskAttributeChipSize.row` is 11pt
    /// *because* the title above it is 13. Each platform's row title is in tune with its own type
    /// scale; one number would put it out of tune with one of them.
    let titleFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let secondaryLineLimit: Int
    /// How many characters of the notes preview the secondary line asks for.
    let notesPreviewLimit: Int

    static func metrics(for surface: CadenceTaskRowSurface) -> CadenceTaskRowMetrics {
        switch surface {
        case .compact: return .compactWidth
        case .regular: return .regularWidth
        case .desktop: return .desktop
        }
    }

    /// iOS's spelling: the two size classes, as the boolean every iOS row already has to hand. The
    /// same pairing `CadencePageHeaderMetrics` keeps beside its three-case surface.
    static func metrics(isRegularWidth: Bool) -> CadenceTaskRowMetrics {
        isRegularWidth ? .regularWidth : .compactWidth
    }

    static let regularWidth = CadenceTaskRowMetrics(
        horizontalPadding: 14,
        verticalPadding: 12,
        contentSpacing: 12,
        summarySpacing: 8,
        badgeSpacing: 6,
        completionGlyphSize: 24,
        titleFontSize: 13,
        secondaryFontSize: 12,
        secondaryLineLimit: 2,
        notesPreviewLimit: 120
    )

    static let compactWidth = CadenceTaskRowMetrics(
        horizontalPadding: 11,
        verticalPadding: 9,
        contentSpacing: 9,
        summarySpacing: 6,
        badgeSpacing: 5,
        completionGlyphSize: 20,
        titleFontSize: 13,
        secondaryFontSize: 11,
        secondaryLineLimit: 1,
        notesPreviewLimit: 64
    )

    /// macOS. Three of these ten figures land on `.regular`'s answer exactly —
    /// `horizontalPadding`, `badgeSpacing` and, in effect, `.compact`'s `secondaryFontSize` — which
    /// is the argument for stating all three tiers in one place: those are now literally one number
    /// each, and the two that had to differ say so beside themselves rather than being discovered
    /// later as drift.
    static let desktop = CadenceTaskRowMetrics(
        horizontalPadding: 14,
        verticalPadding: 8,
        contentSpacing: 8,
        // Stated, not read: the macOS row has no second line. See the type's doc comment.
        summarySpacing: 6,
        badgeSpacing: 6,
        // Stated, not read either, and for a sharper reason — on macOS this same number would also
        // be an SF Symbol point size. `MacTaskRow` leaves `TaskCompletionProgressGlyph`'s own
        // default alone, and a test pins that it keeps doing so.
        completionGlyphSize: 18,
        titleFontSize: 15,
        secondaryFontSize: 11,
        secondaryLineLimit: 1,
        notesPreviewLimit: 64
    )
}

struct CadenceSubtaskProgress: Hashable {
    let completed: Int
    let total: Int

    var compactLabel: String {
        "\(completed)/\(total)"
    }

    var label: String {
        total == 1 ? "\(completed)/1 subtask" : "\(completed)/\(total) subtasks"
    }
}

/// What a task row states about a task's **two** dates — asked once, by both rows.
///
/// **T-304.** The chips were drawn from two independent `isEmpty` checks with nothing between them,
/// so a task do-dated *and* due on the same day stated that day twice: the reported Today screenshot
/// has an Overdue row reading "17 days ago" beside "17 days ago". The fields are genuinely
/// different and each earns a chip when they differ; when they name one day there is one fact, so
/// there is one chip.
///
/// **The flag survives and the sun folds into it.** A deadline is the harder commitment — a do date
/// is when you mean to start, a due date is what you answer to — and the flag is the chip that
/// already goes red on both platforms once the day is past, which is the state the screenshot
/// caught. What the sun carried and the flag does not is one label tint: macOS drew a do date of
/// *today* in amber. That is the tint iOS deleted on purpose (a colour that fires on every row of
/// the Today screen marks nothing), and it only ever applied to the merged case when the deadline
/// was today as well — a task due today reads loudly enough.
///
/// **Nothing is stranded behind no control.** Both pills open pickers for their own field, so
/// dropping one would stand up a row that could no longer set a do date if that were the row's only
/// do-date affordance. It is not, on either platform: macOS answers ⌘T (do date to today) and ⌘⇧T
/// (the do-date picker) on the row under the pointer, iOS's row context menu carries a whole `Do
/// Date` submenu, and the task inspector on both states the two fields separately — which is also
/// where a user goes to *un*-merge them. The one affordance that does go with the pill is macOS's
/// ⌘⇧← / ⌘⇧→ nudge, which reads `HoveredTaskManager.hoveredDateKind` and so needs a chip to hover:
/// while merged, the nudge moves the deadline. ⌘⇧T still opens the do date's own picker.
nonisolated enum CadenceTaskRowDatePlan: String, Sendable, CaseIterable {
    /// Neither field is set. No date chip.
    case none
    /// A do date and no deadline. The sun, alone.
    case doDateOnly
    /// A deadline and no do date. The flag, alone.
    case dueDateOnly
    /// Both, naming **different** days. Two chips: two facts, two dates, two pickers.
    case separateDays
    /// Both, naming the **same** day. One chip — the flag — stating that day once.
    case oneSharedDay

    /// Whether the do date gets a chip of its own.
    var drawsDoDateChip: Bool {
        switch self {
        case .doDateOnly, .separateDays: return true
        case .none, .dueDateOnly, .oneSharedDay: return false
        }
    }

    /// Whether the deadline gets a chip. It survives the merge, so this is true in three cases.
    var drawsDueDateChip: Bool {
        switch self {
        case .dueDateOnly, .separateDays, .oneSharedDay: return true
        case .none, .doDateOnly: return false
        }
    }

    /// Whether the chip that is drawn stands for both fields. Stated separately from
    /// `drawsDoDateChip == false` because the two are different questions: a task with no do date
    /// draws no sun either, and nothing about that chip is speaking for a second field.
    var statesBothFieldsInOneChip: Bool { self == .oneSharedDay }
}

/// What the controls on a task row are **called**, as opposed to what they currently read.
///
/// Every one of these drew a glyph and a value and stated no name ([[T-594]]). A row's do-date pill
/// announced a bare "Tomorrow" with nothing saying *which* date it sets, its due-date pill
/// announced another bare "Tomorrow", and the estimate chip announced "45m" — three values, no
/// nouns, in one row.
///
/// The shape each call site uses is `.accessibilityLabel(name)` + `.accessibilityValue(reading)`,
/// which is the pair SwiftUI already has for exactly this: the label names the control and does not
/// change, the value is the figure the chip draws. Replacing the whole announcement with one string
/// would have had to re-state the value and would then own two spellings of it.
///
/// Stated once, in `Cadence/Shared/`, because **iOS has the same hole** — `iOSTaskRowActionViews`
/// carries one accessibility label in the whole file — and the next surface to fill it should take
/// these words rather than pick its own.
nonisolated enum CadenceTaskControlAccessibility: Sendable {
    /// The sun pill. "Do date" is the field's name everywhere else in the app.
    static let doDate = "Do date"
    static let dueDate = "Due date"
    static let estimate = "Estimate"
    /// The container badge — Inbox, an area or a project. "List" is what the picker it opens calls
    /// itself, and what `CadenceTaskComposerSupport.containerName` resolves.
    static let list = "List"
    static let startFocus = "Start focus session"
    /// The repeat chip (T-611). "Repeat" is what `iOSTaskRowContextMenu`'s submenu is already
    /// titled, so the two ways into the same field are named the same thing.
    static let recurrence = "Repeat"
    /// The goal chip. The app calls a goal a **milestone** everywhere it names one to the user —
    /// `CadenceTitleNormalization.defaultMilestoneTitle` is "Untitled Milestone" — so a chip that
    /// announced "Goal" would be the only place it is called that.
    static let milestone = "Milestone"
    /// The placement breadcrumb's second segment, which names a column inside the list. "Section"
    /// is `CadenceTaskInspectorSupport.sectionSegmentTitle`'s own word for it.
    static let section = "Section"
}

extension CadenceTaskCompletionState {
    /// What the completion circle is called, in the state it is in.
    ///
    /// **The primary control on every task row, and it had neither an accessible name nor a
    /// tooltip** ([[T-594]]) — VoiceOver read an unlabelled button and the pointer got nothing.
    ///
    /// An action phrase rather than a state reading, because that is what the repo's other named
    /// controls do ("Start focus session", "Open link", "Delete link") and because the state is
    /// already carried by the row's own strikethrough and dimming. It is keyed on the state rather
    /// than written at the call site because the action genuinely changes with it: mid-fill, a
    /// second tap on macOS converts a pending completion into a cancellation rather than undoing
    /// it — see `TaskCompletionButton.handleTap()`, whose branches these five mirror.
    var accessibilityActionLabel: String {
        switch self {
        case .todo:                return "Complete task"
        case .pendingCompletion:   return "Cancel task"
        case .pendingCancellation: return "Stop cancelling task"
        case .done, .cancelled:    return "Reopen task"
        }
    }
}

enum CadenceTaskPresentationSupport {
    static func plainPreviewText(from markdown: String, limit: Int? = nil) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown, limit: limit)
    }

    static func subtaskProgress(for task: AppTask) -> CadenceSubtaskProgress? {
        let subtasks = task.subtasks ?? []
        guard !subtasks.isEmpty else { return nil }
        return CadenceSubtaskProgress(
            completed: subtasks.filter(\.isDone).count,
            total: subtasks.count
        )
    }

    /// How many unfinished subtasks a row lists before it stops and says how many are left.
    ///
    /// Three, measured rather than guessed. Uncapped was tried first and shipped to a screenshot:
    /// one sample row with four subtasks stood ~290pt tall and iPhone Today fell from about five
    /// visible tasks to two and a half — a checklist on one task hiding the rest of the day. The
    /// row still names what is left rather than counting it, which is what the old `0/3` chip got
    /// wrong; it just stops naming at three.
    static let rowSubtaskLimit = 3

    /// How many tags a task row shows before collapsing the rest into a `+N`.
    ///
    /// **Three, and iOS had it.** macOS's `MacTaskRow` capped at two and iOS at three for the same
    /// strip of the same chips on the same task; neither number was argued for, and the narrower
    /// surface is not the one that was showing fewer — macOS's `CompactTagStrip` wraps the whole
    /// decision in `ViewThatFits`, so it already drops to one chip or to a bare `+N` when the row
    /// is genuinely tight. A fixed cap below the point where the row can no longer fit them is
    /// hiding a tag the row had room for.
    static let rowTagLimit = 3

    /// The subtasks a task row lists **beneath** itself, in `order`, capped at `rowSubtaskLimit`.
    ///
    /// Unfinished only. The iOS row used to say `0/3` in a chip, which named a number of things to
    /// do without naming any of them — so the checklist was only ever readable by opening the task.
    /// Finished subtasks stay out because they say nothing new: a row's job here is what is left.
    static func unfinishedSubtasks(for task: AppTask) -> [Subtask] {
        Array(allUnfinishedSubtasks(for: task).prefix(rowSubtaskLimit))
    }

    /// Everything `unfinishedSubtasks` would list if it did not cap — the denominator behind the
    /// overflow line, so the two cannot disagree about what "more" means.
    static func allUnfinishedSubtasks(for task: AppTask) -> [Subtask] {
        (task.subtasks ?? [])
            .filter { !$0.isDone }
            .sorted { $0.order < $1.order }
    }

    /// How many unfinished subtasks the row is **not** showing, or `nil` when it is showing them
    /// all. The row draws a "+N more" line from this; `nil` draws nothing rather than "+0 more".
    static func hiddenSubtaskCount(for task: AppTask) -> Int? {
        let hidden = allUnfinishedSubtasks(for: task).count - rowSubtaskLimit
        return hidden > 0 ? hidden : nil
    }

    /// What a dense task surface — a row on either platform, a board card on either platform —
    /// actually lists beneath the task, and the count it says is left over.
    ///
    /// The pair exists because `unfinishedSubtasks` alone is not the whole decision: **nothing is
    /// listed under a finished task.** A completed task's leftover checklist items are not work any
    /// more, and the surfaces these appear in — Today's Completed section, a board column's
    /// Completed footer — would otherwise fill with tappable items belonging to tasks that are over.
    /// That guard was applied at one call site (iOS's task row) and re-derived nowhere else, so the
    /// three surfaces that gained a subtask list under T-173 would each have had to remember it.
    /// It is a decision, not a shell, so it lives here with the cap it belongs to.
    static func listedSubtasks(for task: AppTask) -> [Subtask] {
        task.isDone ? [] : unfinishedSubtasks(for: task)
    }

    /// The "+N more" that goes with `listedSubtasks`, or `nil` when there is nothing more to say —
    /// including for a finished task, which lists none and therefore hides none.
    static func unlistedSubtaskCount(for task: AppTask) -> Int? {
        task.isDone ? nil : hiddenSubtaskCount(for: task)
    }

    /// Minutes → duration label for task chrome — "45m", "2h", "1h 24m", `"0m"` for nothing.
    ///
    /// The shape (and the non-breaking space that keeps it from wrapping into a wrong number) is
    /// `TimeFormatters.durationLabel(minutes:emptyPlaceholder:)`; only the empty sentinel is this
    /// surface's own. `emptyPlaceholder` lets the callers that want a dash instead of `"0m"` reach
    /// the same formatter rather than writing a fifth copy of it.
    static func estimateLabel(minutes: Int, emptyPlaceholder: String = "0m") -> String {
        TimeFormatters.durationLabel(minutes: minutes, emptyPlaceholder: emptyPlaceholder)
    }

    static func estimateLabel(for task: AppTask) -> String {
        estimateLabel(minutes: task.estimatedMinutes)
    }

    static func scheduledDateLabel(for task: AppTask, todayKey: String = DateFormatters.todayKey()) -> String {
        if task.scheduledStartMin >= 0 {
            let time = TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)
            if task.scheduledDate == todayKey {
                return time
            }
            return "\(DateFormatters.relativeDate(from: task.scheduledDate)) at \(time)"
        }
        return DateFormatters.relativeDate(from: task.scheduledDate)
    }

    /// The do date as a **day**, never a time — "Today", "3 days ago", "Aug 24".
    ///
    /// `scheduledDateLabel` folds the timeline slot into the same string ("3 days ago at 9:30 AM –
    /// 10 AM"), which is right for a surface with no timeline beside it and wrong for a task row:
    /// there the slot ran to three times the width of every other chip and pushed the row's
    /// metadata onto a second line. The iOS row shows the day here; the Today timeline pane and the
    /// task inspector are where the slot itself is read.
    static func scheduledDayLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.scheduledDate)
    }

    static func dueDateLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.dueDate)
    }

    /// Which date chips a row draws for `task`. See `CadenceTaskRowDatePlan` for why the merged
    /// case keeps the flag.
    static func rowDatePlan(for task: AppTask) -> CadenceTaskRowDatePlan {
        rowDatePlan(scheduledDate: task.scheduledDate, dueDate: task.dueDate)
    }

    /// The same question asked of two keys, so a surface that has already decided to suppress one
    /// field can pass `""` for it and get an answer that accounts for the suppression — macOS's
    /// `.todayGrouped` row drops the do-date pill by section, and a row with no sun to draw has
    /// nothing to merge.
    ///
    /// **Compared as days, not as strings.** The keys are `yyyy-MM-dd` and should be identical when
    /// they name one day, but `DateFormatter` is lenient enough to have stored `2026-8-20`
    /// somewhere (T-299), and two keys that print the same date through
    /// `DateFormatters.relativeDate(from:)` are exactly the pair the user sees twice. Anything that
    /// does not parse falls back to its own text, which keeps two identical unparseable keys merged
    /// and two different ones apart.
    static func rowDatePlan(scheduledDate: String, dueDate: String) -> CadenceTaskRowDatePlan {
        switch (scheduledDate.isEmpty, dueDate.isEmpty) {
        case (true, true):
            return .none
        case (false, true):
            return .doDateOnly
        case (true, false):
            return .dueDateOnly
        case (false, false):
            return namesTheSameDay(scheduledDate, dueDate) ? .oneSharedDay : .separateDays
        }
    }

    static func namesTheSameDay(_ oneKey: String, _ otherKey: String) -> Bool {
        normalizedDayKey(oneKey) == normalizedDayKey(otherKey)
    }

    private static func normalizedDayKey(_ key: String) -> String {
        guard let date = DateFormatters.date(from: key) else { return key }
        return DateFormatters.dateKey(from: date)
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        Theme.statusColor(status)
    }
}

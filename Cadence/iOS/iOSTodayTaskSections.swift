#if os(iOS)
import SwiftData
import SwiftUI

/// Today's rollover notice, as a surface opts into it: the tasks the banner lists and the action
/// its button runs, together, because the two are useless apart — the same shape as
/// `iOSBundleFormingDrop`.
struct iOSTodayRolloverNotice {
    let tasks: [AppTask]
    /// `CadenceTodayRolloverSupport.rollFailureNotice` when the last roll was refused (T-635).
    /// Part of the same opt-in for the same reason: a refused roll leaves the offer on screen, so
    /// the sentence travels with the offer rather than with a second piece of state.
    let failureNotice: String?
    let onRollOver: () -> Void
}

// `iOSTodayOverdueSummaries` was here, with the `PAST DUE LISTS` and `PAST DUE SECTIONS` bands it
// opted this view into, and `iOSTodayOverdueListSheet` was at the foot of this file as the page a
// tapped card opened. All of it is gone at the owner's direction — *"we should remove the banners
// that show the past due lists in today's view"*, and then *"my request on not showing past due
// sections and lists applies to mac os and ios as well"*. **Both** groups, on **both** platforms:
// the two runs were one visual treatment in one place, so keeping the columns while dropping the
// lists would have been half a decision.
//
// macOS's half was already removed and `TasksPanel` records the reasoning in the same words; what
// it also recorded was that iOS still drew both bands, because the owner had seen the Mac's Today
// and not the phone's. This is that sentence coming due. Today was stating overdue-ness three ways
// — a per-task section, these per-list and per-column summaries, and the red flag on the row
// itself — and only the last says it where you can act on it. The cards also navigated *away* from
// the day, which is the opposite of what a triage page is for.
//
// `CadenceTodayOverdueSummarySupport` and `CadenceTodayOverdueSummaryCards` are **not** deleted
// here. Removing a shared component is its own change with its own test fallout and the owner
// asked for the bands, not the files; they have no production caller left on either platform, and
// T-3076's ledger entry names them so the next pass does not have to rediscover that.

/// Today's list of counted task groups — **the** one, for both hosts.
///
/// The phone's Today and the iPad task column each drew their own copy of this: the same
/// `CadenceTodayTaskGroup`s, the same "Completed Today" group under them, and the same empty state,
/// stacked 14pt apart on one and 15pt on the other, padded 14 on one and 18 on the other. Two
/// copies of one list is how the previous round of this sweep found the iPad heading its groups
/// with a bare eyebrow while the phone counted them — a difference in what the screen *said*, from
/// a split nobody had chosen.
///
/// Everything that legitimately varies is `CadenceTodaySectionMetrics`, keyed on the layout rather
/// than the size class, so the iPad's narrow single-column fallback is drawn like the phone's Today
/// because it *is* the phone's Today, on the same `Theme.bg` page.
struct iOSTodayTaskSections: View {
    /// Which Today this is the list of. The only parameter that decides anything about appearance,
    /// and it decides it by asking `CadenceTodaySectionMetrics`.
    let layout: CadenceTodayLayout
    let taskGroups: [CadenceTodayTaskGroup]
    let completedTasks: [AppTask]
    /// Whether the day's finished work is **unfolded** — no longer whether it is on the page at
    /// all. Since the owner's *"show the completed today section (which is always folded until i
    /// unfold it) on the bottom of the list"* the section is always there and this bit is its
    /// disclosure. A `@Binding` rather than a `let` because the section's own heading writes it
    /// now; `iOSTodayCompletedSection` says why it is this bit and not a second `@State` beside it.
    @Binding var showsCompleted: Bool
    /// `nil` when there is nothing to roll over, or the day's notice has already been dismissed.
    /// The host decides — `CadenceTodayRolloverSupport.isNoticeVisible` — because the host is what
    /// holds the `@AppStorage` day key.
    var rolloverNotice: iOSTodayRolloverNotice?
    #if DEBUG
    /// Debug-only, and passed by both hosts. See `iOSCompactSampleDataCard`.
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    private var metrics: CadenceTodaySectionMetrics {
        .metrics(layout: layout)
    }

    /// Derived here rather than taken as a parameter, the same way `iOSSchedulePanel` derives it:
    /// both hosts of this view already compute their own from `DateFormatters.todayKey()`, and a
    /// sixth parameter that can only ever be handed today's key is a parameter that can be handed
    /// the wrong one. It exists for `dayAlreadyStatedBySurface` — see `iOSTaskRow`.
    private var todayKey: String {
        DateFormatters.todayKey()
    }

    /// The readable-column cap belongs to the **host**, not to this view: it has to hold the page
    /// header and the options bar as well, or a narrow iPad pane would cap the rows at 520 and let
    /// the header above them run the full width of the pane. Both hosts read it from here so it is
    /// still one number per layout.
    static func contentMaxWidth(layout: CadenceTodayLayout) -> CGFloat {
        CadenceTodaySectionMetrics.metrics(layout: layout).contentMaxWidth
    }

    /// The scroll container's own insets, for the same reason and with the same history: the cap
    /// above was hoisted so "the two hosts cannot drift apart again", and the three gutters beside
    /// it were left typed out in each host, where they promptly drifted (T-596). One call rather
    /// than three numbers, so there is nothing left at either call site to drift.
    static func contentPadding(layout: CadenceTodayLayout) -> EdgeInsets {
        let metrics = CadenceTodaySectionMetrics.metrics(layout: layout)
        return EdgeInsets(
            top: metrics.topPadding,
            leading: metrics.horizontalPadding,
            bottom: metrics.bottomPadding,
            trailing: metrics.horizontalPadding
        )
    }

    /// `CadenceTaskQuerySupport.todayListGroups` drops its empty groups, so an empty list of groups is
    /// an empty day — the two hosts each re-derived this from their own `todayTasks` array instead,
    /// which is one more chance for them to disagree about when Today is empty.
    ///
    /// **The rollover notice counts as content.** While it is up the grouped list is deliberately
    /// *missing* the tasks it is offering, so a day whose only open work is yesterday's leftovers
    /// has no groups — and without the last clause this view would draw "nothing planned" directly
    /// under a banner listing four things to do. Since T-305 the withheld rows are missing from
    /// *their lists'* groups rather than from a "Past Do" section, so confirming the roll makes a
    /// list group appear rather than moving rows between two date buckets — which is the whole
    /// point of the roll being visible.
    ///
    /// **Finished work counts as content whether or not it is unfolded.** This read
    /// `!showsCompleted || completedTasks.isEmpty`, which was right while a chip decided whether the
    /// Completed section existed at all. It is always on the page now, so a day whose only work is
    /// already done draws a folded "Completed Today" — and without this clause it would draw
    /// "Nothing planned" directly above it, which is the same defect the two removed clauses were
    /// here to prevent.
    private var isEmpty: Bool {
        taskGroups.isEmpty
            && completedTasks.isEmpty
            && rolloverNotice == nil
    }

    @ViewBuilder
    var body: some View {
        // The notice is the day's first thing to read whether or not anything is left in the
        // groups under it. The two runs of past-due cards used to be hoisted up here with it.
        if let rolloverNotice {
            VStack(alignment: .leading, spacing: metrics.groupSpacing) {
                CadenceTodayRolloverBanner(
                    tasks: rolloverNotice.tasks,
                    style: .card,
                    failureNotice: rolloverNotice.failureNotice
                ) {
                    rolloverNotice.onRollOver()
                }
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            // Not carded by `metrics`: `iOSCompactTodayEmptyState` draws its own card, at the one
            // fill that reads against both hosts. A second card around it would be the stacked
            // layers the standing rule rules out.
            VStack(alignment: .leading, spacing: 12) {
                iOSCompactTodayEmptyState()

                #if DEBUG
                iOSCompactSampleDataCard(
                    status: sampleDataStatus,
                    action: seedSampleData
                )
                #endif
            }
        } else {
            groupStack
        }
    }

    @ViewBuilder
    private var groupStack: some View {
        // Asked of the surface rather than decided here, so the phone's Today and the iPad's cannot
        // answer "does a row name its list" differently — the same reason Inbox asks. Read by the
        // Completed group below, which is flat; the list groups above it answer `false` outright.
        let showsContainer = CadenceTaskSurfaceOptions.showsContainerChip(on: .today)

        let stack = VStack(alignment: .leading, spacing: metrics.groupSpacing) {
            ForEach(taskGroups) { group in
                // Every group here is a list, so every group accepts a dropped `+` and inherits
                // its list. `CadenceTaskDropSupport.dropKey(forGroup:)` decides, once, for both
                // layouts.
                //
                // **`showsContainer: false`, flatly.** This was `showsContainer &&
                // group.showsContainerChip`, and the group's half was exactly "am I Overdue" — the
                // one group on Today drawn from every list at once, where the chip was the only
                // thing saying where the work lived. With Overdue gone every header prints its own
                // list's name, so a chip under it is that name twice. The surface option is still
                // read, by the Completed group, which is flat and does need it.
                // `dayAlreadyStatedBySurface: todayKey` drops a sun pill that would read "Today"
                // on the page called Today, and leaves every other reading — including a red "3
                // days ago" on a task this page is still holding — exactly where it was. macOS's
                // Today has answered this way since T-304's follow-up; this is the same knob
                // reading the same shared equality (T-1272).
                iOSTaskGroupSection(
                    title: group.title,
                    color: group.accent,
                    tasks: group.tasks,
                    showsContainer: false,
                    dayAlreadyStatedBySurface: todayKey,
                    dropIdentity: group.dropIdentity
                )
            }

            // **Always drawn, at the bottom of the list, folded until it is asked for.** This was
            // `if showsCompleted { iOSTaskGroupSection(…) }`, so the day's finished work existed
            // only while the options bar's "Completed" chip was lit — something you had to know was
            // behind a chip rather than a section you could see was closed. See
            // `iOSTodayCompletedSection` for why the disclosure is not `iOSTaskGroupSection`'s.
            //
            // Same day key as the groups above, and for the reason
            // `TasksPanelCompletedSectionView` states on macOS: a task finished today and planned
            // for today does not get to say "Today" on the Today page just because it is in the
            // Completed section.
            //
            // `dropIdentity: .completion` is no longer passed and nothing is lost by that:
            // completion is a status rather than a placement, so
            // `CadenceTaskDropSupport.dropKey(forGroup:)` answers nil for it — the drop target was
            // inert and `showsWhenEmpty` was already false, which is the predicate this section
            // keeps.
            iOSTodayCompletedSection(
                tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch),
                hiddenCount: CadenceTaskSurfaceOptions.hiddenCompletedCount(from: completedTasks, tier: .touch),
                showsContainer: showsContainer,
                dayAlreadyStatedBySurface: todayKey,
                isExpanded: $showsCompleted
            )
        }

        // No inset of its own. Both hosts already pad their own gutter — 14pt in
        // `iOSCompactTodayView` and in `iOSTodayView.todayTaskSections` — and this used to add a
        // further 12 on compact, for a `.cadenceCard()` that `85809ff` deleted on purpose. The
        // padding outlived the fill it was insetting from, which put the day's group headers 12pt
        // inside the page header and options bar stacked directly above them. See
        // `CadenceTodaySectionMetrics` (T-587).
        stack
    }
}

extension View {
    /// Today's scrolling task region as a destination for a dropped `+` (T-1276).
    ///
    /// **What it claims is the day, and only the day: "Do Today".** That is the one attribute every
    /// row on this page shares — Today groups by list, and the lists differ — so it is exactly what
    /// the group-header rule permits a container to hand over, read out of the same
    /// `CadenceTaskDropSupport.dropKey(forGroup:)` table as everything else. It deliberately names
    /// no list: the page draws work from all of them, and picking one would be inventing a
    /// placement the region never named. A task seeded this way lands in the Inbox, planned for
    /// today, and is therefore still on the page it was dropped on — the outcome
    /// `CadenceTaskGroupDropIdentity.todayList` exists to guarantee for the groups inside it.
    ///
    /// Anything narrower still wins: the list groups, their headers and their rows are all smaller
    /// frames inside this one, and `CadenceCaptureDropHitTest` takes the smallest. So this catches
    /// the gap between groups, the run of blank space under the last one, and the empty state —
    /// which is the whole of the complaint.
    ///
    /// Declared here, beside the list both hosts draw, rather than typed at the two call sites: the
    /// phone's Today and the iPad column have drifted apart on every number this file has since
    /// taken back, and "which region a drop lands in" is not a thing they may answer differently.
    func iOSTodayTaskRegionDropTarget() -> some View {
        iOSNewTaskDropRegion(.todayDate(.plannedToday))
    }
}

/// The list a past-due summary card opens, as Today presents it.
///
/// **Nothing opens it any more**, because nothing draws a past-due card (see the top of this
/// file). It is kept rather than deleted for one reason, recorded here so the next reader does not
/// have to re-derive it: `CadenceCodexPageCompletionTypographyTests` pins both this type and
/// `iOSTodayView`'s `.sheet(item: $pendingListOpen)`, and that file is held by another writer, so
/// this change cannot update it. Deleting this struct, the `@State` and the presenter is a
/// three-line follow-up once that lease lifts — T-3076's entry names it as the only dead plumbing
/// this change left behind.
///
/// It is `iOSListDetailView` and nothing else — the same page the Lists tab pushes, at the page the
/// request names, with the named column scrolled into view. Wrapping it rather than writing a
/// reduced "here are the overdue cards" panel is the point: the reason to tap the card is to *work
/// on* the column, and a read-only excerpt would send you to the Lists tab to do anything about it.
///
/// **It carries its own task-inspector host.** The root's host is already presenting this sheet, and
/// a host that is presenting cannot present again — a task row inside here would be a dead tap
/// without a nearer owner. `iOSTaskInspectorHost` records that the environment resolves to the
/// innermost host for exactly this case.
struct iOSTodayOverdueListSheet: View {
    let request: CadenceListOpenRequest
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        content
            .iOSTaskInspectorHost()
    }

    /// A list can be deleted or archived on another device between the card being drawn and the
    /// card being tapped, so the miss is a real state and not a defensive `else` — the same one
    /// `iOSRootView` and `iOSSearchView` already answer with this view.
    @ViewBuilder
    private var content: some View {
        switch request.target {
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(
                    area: area,
                    initialPage: request.page,
                    highlightedSectionName: request.sectionName,
                    isPresentedModally: true
                )
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(
                    project: project,
                    initialPage: request.page,
                    highlightedSectionName: request.sectionName,
                    isPresentedModally: true
                )
            } else {
                iOSMissingListView()
            }
        }
    }
}

/// Today's finished work: the one section on this page that is folded until you ask for it.
///
/// **It is always drawn now, at the bottom of the list, closed.** The owner asked for *"the
/// completed today section (which is always folded until i unfold it) on the bottom of the list"*.
/// Before this it was `if showsCompleted { … }` over the options bar's "Completed" chip, so the
/// day's finished work was not a closed section — it was a section that did not exist until you
/// found the control that made it.
///
/// **The fold is the host's `showsCompleted` bit, not a second `@State` in here.** That bit is
/// `@AppStorage(CadencePreferenceKeys.iosTodayShowCompleted)`, and it **defaults to `false`** —
/// that default is the whole of "always folded", and `CadenceTodayUnificationTests` pins it. One
/// bit matters because the options bar's chip still writes it: two controls for one disclosure is
/// ordinary, two sources of truth for it is how one of them starts lying — a chip reading
/// "Completed" over a section that is already open, or the reverse. When the chip goes (it is the
/// same bit, so it is a deletion and nothing else), this heading is already the control.
///
/// **Why this is not `iOSTaskGroupSection`, which every other group on this page is.** That
/// component draws its heading unconditionally and owns no disclosure: a chevron row above it would
/// print "Completed Today" twice, and a chevron inside it would put one on every task group in the
/// app. What should be shared still is — the heading is `CadenceTaskGroupHeading`, the same row the
/// list groups above and macOS's Today draw, and the rows are `iOSTaskRow` at the same 7pt spacing
/// in the same `LazyVStack` that T-2057 put them in. Only the fold and its chevron are local, which
/// is the same shape `iOSCalendarBoardView`'s completed footer already uses on the day columns.
struct iOSTodayCompletedSection: View {
    let tasks: [AppTask]
    /// Rows the caller capped away. Carried through unchanged from the call site that used to hand
    /// it to `iOSTaskGroupSection`: no tier caps completed rows since T-2057, so this is `nil` on
    /// every call and the caption below never draws. Removing it is T-2087's, not this change's.
    let hiddenCount: Int?
    /// Asked of `CadenceTaskSurfaceOptions`, by the caller. True here while the list groups above
    /// answer `false`: this section is flat, so its rows are the only thing that can say which list
    /// a finished task came from.
    let showsContainer: Bool
    /// Today's own `yyyy-MM-dd`. See `iOSTaskRow.dayAlreadyStatedBySurface`.
    let dayAlreadyStatedBySurface: String?
    @Binding var isExpanded: Bool

    /// Read once, from the shared constant macOS's Completed section reads — the heading, the
    /// accessibility label and the overflow caption are three renderings of one title, not three
    /// chances to spell it differently. `CadenceTodayUnificationTests` counts the call sites, so
    /// the indirection is also what keeps that count honest at one per platform.
    private static var title: String { CadenceTodayPresentationSupport.completedSectionTitle }

    /// The section's true size: the rows drawn plus the rows the cap withheld.
    private var totalCount: Int {
        tasks.count + (hiddenCount ?? 0)
    }

    var body: some View {
        // Nothing finished today is not "a closed section with nothing in it" — it is no section.
        // The same predicate `iOSTaskGroupSection.isVisible` applied to this group before, because
        // `.completion` is a status and resolves to no drop key, so the group was never one of the
        // "still add to me" groups that survive emptying.
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                disclosure

                if isExpanded {
                    rows
                }
            }
        }
    }

    /// The heading, as a control. `CadenceTaskGroupHeading` already spans its container, so the
    /// whole row is the target rather than the glyphs — the same reason it carries that frame for
    /// `iOSTaskGroupHeader`'s drop target.
    private var disclosure: some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .cadenceFont(.metadata, base: 10, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .frame(width: 12)

                CadenceTaskGroupHeading(
                    title: Self.title,
                    tint: CadenceTodayPresentationSupport.completedSectionAccent
                )
            }
            // The eyebrow's own 6pt top inset, the one `iOSTaskGroupHeader` applies, so this
            // heading sits where every other heading on the page does.
            .padding(.top, iOSTaskSectionHeader.topPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(Self.title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides the tasks you finished today" : "Shows the tasks you finished today")
    }

    /// Completed rows are dimmed as a whole rather than row by row — `iOSTaskGroupSection`'s
    /// `opacity` knob, at the one value Today ever passed it.
    private var rows: some View {
        LazyVStack(spacing: 7) {
            ForEach(tasks) { task in
                iOSTaskRow(
                    task: task,
                    showsContainer: showsContainer,
                    dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
                )
                .opacity(0.62)
            }

            if let caption = CadenceTaskSurfaceOptions.overflowCaption(
                shown: tasks.count,
                total: totalCount
            ) {
                Text(caption)
                    .cadenceFont(.metadata)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .accessibilityLabel("\(Self.title): \(caption)")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
#endif

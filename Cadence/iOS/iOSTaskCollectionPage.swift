#if os(iOS)
import SwiftUI

/// **The** All Tasks / Inbox page, at every width.
///
/// It replaces four views: `iOSCompactAllTasksView` and `iOSCompactInboxView`, which drew
/// `ScrollView` + `LazyVStack` + `iOSTaskGroupSection`, and `iOSAllTasksView.allTasksPanel` and
/// `iOSInboxView.inboxColumn`, which drew `List` + `Section` + `iOSTaskGroupHeader` +
/// `iOSTaskListRow`. Two scroll containers, two separator treatments and two sets of row insets,
/// for one screen — and the copies had drifted in every dimension nobody had decided: the group
/// stack was carded on the phone's Inbox and bare on its All Tasks, the empty state's card was
/// 220pt tall on one and 190 on the other, the options bar was padded 10 below on one panel and 12
/// on the other, and the page stacked its own chrome at 11pt, 12pt and 0.
///
/// **The `LazyVStack` won, and the `List` cost nothing to give up.** Every service a `List` renders
/// for free was already switched off here or replaced app-wide:
/// - **Separators** were `.listRowSeparator(.hidden)`. `iOSTaskRow` draws its own bottom hairline
///   so that it looks the same in either host.
/// - **Row backgrounds** were `.listRowBackground(Color.clear)`.
/// - **Swipe actions** are `iOSSwipeActionsModifier`, not `.swipeActions`, and deliberately so:
///   eight of that row's call sites render inside a `ScrollView`, where SwiftUI discards
///   `.swipeActions` silently. Complete / schedule / delete survive this change intact, on both
///   widths, because they never came from the `List` in the first place.
/// - **Row insets** were `.listRowInsets(…leading: 12, trailing: 12)` *on top of* the row's own
///   `CadenceTaskRowMetrics.horizontalPadding`, so the `List` hosts indented their rows twice.
///
/// What is genuinely lost is **pinned section headers**: `.listStyle(.plain)` sticks a section
/// header to the top of the scroll while its rows pass under it, and a `LazyVStack` does not. That
/// is a real behaviour and it is stated rather than dropped quietly — it did not exist at compact
/// width, and Today does not have it at either width, so keeping it would have meant one of the
/// three segments of this tab scrolling differently from the other two. What a `LazyVStack` gives
/// back is the thing the `List` could not express: `iOSTaskGroupSection.isVisible` — "a group you
/// can still add to does not vanish when it empties" — is a predicate inside the component, and the
/// two `List` hosts each had to re-spell it by hand and got it *different*: All Tasks guarded
/// `if !activeTasks.isEmpty`, Inbox guarded nothing.
struct iOSTaskCollectionPage: View {
    let collection: CadenceTaskCollection
    /// Off when the Tasks tab hosts this as one of its segments — see `iOSTodayView.showsCompactHeader`.
    var showsHeader = true
    let activeTasks: [AppTask]
    let completedTasks: [AppTask]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(RemindersManager.self) private var remindersManager

    private var metrics: iOSTaskCollectionMetrics {
        .metrics(isRegularWidth: horizontalSizeClass == .regular)
    }

    /// **The Reminders section is the Inbox's and only the Inbox's**, decided by the same function
    /// macOS's `TasksListView` asks — not by a `collection == .inbox` written out a second time
    /// here. `CadenceTasksPageScope.showsRemindersStrip` is the tested gate; a second condition
    /// beside it is exactly how the two platforms would come to disagree about when the strip
    /// appears.
    ///
    /// It reaches every route into the Inbox because it is on the *page*: the iPhone's Tasks tab,
    /// the iPad shell's Tasks destination, the More tab and Search all render `iOSInboxView`,
    /// which is this page. All Tasks answers `false` and is untouched.
    private var showsRemindersSection: Bool {
        CadenceTasksPageScope.showsRemindersStrip(
            scope: CadenceTasksPageScope(collection: collection),
            isAuthorized: remindersManager.isAuthorized,
            isLoading: remindersManager.isLoading,
            hasReminders: !remindersManager.reminders.isEmpty
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.stackSpacing) {
                if showsHeader {
                    header
                }

                optionsBar

                iOSTaskCollectionSections(
                    collection: collection,
                    activeTasks: activeTasks,
                    completedTasks: completedTasks,
                    showsCompleted: showCompleted,
                    metrics: metrics,
                    // The empty state and this section are alternatives, not neighbours: "Inbox is
                    // clear" over a list of open reminders says the opposite of what the screen is
                    // showing. macOS spells the same rule as an extra clause on its `isEmpty`, and
                    // the two are the same statement — its clause is the negation of this gate.
                    hidesEmptyState: showsRemindersSection
                )

                if showsRemindersSection {
                    iOSInboxRemindersSection(
                        remindersManager: remindersManager,
                        metrics: metrics
                    )
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        // **Access can change while this page is on screen, and on iOS it changes somewhere else.**
        // Appearance alone is not enough: revoking Reminders access happens in the Settings app,
        // so coming back to a page that never disappeared is a foreground transition rather than
        // an appearance. **T-253** folded both halves into the one shared modifier all four
        // reminders surfaces now apply, so no surface can carry half of it.
        //
        // The hook re-reads `EKEventStore.authorizationStatus`, which is the right thing *here*
        // and the wrong thing straight after a grant — see the comment on
        // `iOSInboxRemindersSection.perform(_:)`. That path does not go through this.
        //
        // `isEnabled` is All Tasks' exemption: that page never shows reminders, so touching
        // EventKit from it would be work with no surface behind it.
        .remindersAuthorizationLifecycle(
            remindersManager,
            isEnabled: CadenceTasksPageScope(collection: collection) == .inbox
        )
    }

    /// **The header scrolls with the content, at both widths.** The `List` hosts pinned it — header,
    /// divider, options bar, then a scrolling list — and that is what a header does when it is the
    /// top of one *column* beside a sibling pane, which is why Today's two-pane task column keeps
    /// its own. Neither of these is that: `iOSInboxView` documents itself as "one full-width
    /// column", the whole page, exactly the page the phone draws. So the divider under it goes with
    /// the pinning; there is nothing left for it to separate.
    ///
    /// No subtitle. A line under "All Tasks" saying it is where you review active work describes the
    /// page you are already looking at. The count rides in the header at both widths, which is where
    /// the metric strip it replaced used to put it.
    ///
    /// `onBack` **only** at compact width, following `iOSCompactTodayView`: the iPad shell hosts
    /// this page with no `NavigationStack` around it, so `dismiss()` would have nothing to dismiss
    /// and the chevron would be a control that looks wired and does nothing.
    private var header: some View {
        iOSCompactPageHeader(
            eyebrow: collection.eyebrow,
            title: collection.title,
            color: Theme.blue,
            count: activeTasks.count,
            onBack: horizontalSizeClass == .compact ? { dismiss() } : nil
        )
    }

    /// Gated on `CadenceTaskSurfaceOptions`, which the compact views consulted and the two panels
    /// did not — the same one-sided gate Today closed. That file exists so an exception is written
    /// per surface, once, for both widths at a time.
    ///
    /// There is no capture field above it on either width. The tab bar's centre `+` and the iPad's
    /// floating `+` open the full composer from every one of these screens, so a title-only field a
    /// thumb's width away was a second, weaker affordance for one action.
    @ViewBuilder
    private var optionsBar: some View {
        let options = CadenceTaskSurfaceOptions.options(for: collection.surface)
        if options.showsSort || options.showsCompletedToggle {
            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: completedTasks.count
            )
            .padding(.vertical, 2)
        }
    }
}

/// The page's counted groups — Active over Completed — or its empty state.
///
/// Split out from the page for the reason `iOSTodayTaskSections` is: the scroll container and its
/// gutters belong to the *page*, and the list of groups is the part a second host could ever want
/// to place differently.
struct iOSTaskCollectionSections: View {
    let collection: CadenceTaskCollection
    let activeTasks: [AppTask]
    let completedTasks: [AppTask]
    let showsCompleted: Bool
    let metrics: iOSTaskCollectionMetrics
    /// Set when the host is drawing something else in this collection's place — today that is the
    /// Inbox's Apple Reminders section, which is not a task group and so cannot be counted by
    /// `isEmpty`, but is very much content. Without it a cleared Inbox with three open reminders
    /// under it announced "Inbox is clear" directly above them.
    var hidesEmptyState = false
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager

    private var isEmpty: Bool {
        guard !hidesEmptyState else { return false }
        return activeTasks.isEmpty && (!showsCompleted || completedTasks.isEmpty)
    }

    var body: some View {
        if isEmpty {
            iOSEmptyPanel(
                systemImage: collection.emptyIcon,
                title: collection.emptyTitle,
                subtitle: collection.emptySubtitle
            )
            .frame(minHeight: metrics.emptyStateMinHeight)
            // **An empty collection still accepts a dropped `+` when it has a placement to give.**
            // `iOSTaskGroupSection.isVisible` already says a group you can add to does not vanish
            // when it empties — but this branch runs *first* and replaces the groups wholesale, so
            // a cleared Inbox showed "Inbox is clear" and no drop target at all, which is exactly
            // the moment the rule was written for. The panel takes the group's identity rather than
            // the page falling back to an "ACTIVE 0" heading over nothing: the empty state is the
            // better target anyway, being the whole card instead of one header row.
            //
            // All Tasks is unaffected and should be: its active group is `.completion`, which
            // resolves to no key, so `iOSNewTaskDropTarget(group:)` attaches nothing.
            .iOSNewTaskDropTarget(group: collection.activeGroupIdentity)
        } else {
            groupStack
        }
    }

    /// **Carded, at both widths and on both collections.** The rule is Today's, and it is about the
    /// host's background rather than the device: a `Theme.surface` card is what separates a list of
    /// rows from a `Theme.bg` page, and is invisible on a `Theme.surface` one. All four of the views
    /// this replaces painted `Theme.bg`, so all four should have drawn the card; only the phone's
    /// Inbox did. One layer, at one radius — the rows inside carry no background of their own.
    private var groupStack: some View {
        // Asked of the surface, not decided here, so the phone's Inbox and the iPad's cannot answer
        // "does a row name its list" differently.
        let showsContainer = CadenceTaskSurfaceOptions.showsContainerChip(on: collection.surface)

        return VStack(alignment: .leading, spacing: metrics.groupSpacing) {
            // No `if !activeTasks.isEmpty` guard: `iOSTaskGroupSection.isVisible` decides, from the
            // identity. Inbox's "Active" is a placement, so it survives emptying and stays a drop
            // target at the moment that is most useful; All Tasks' is completion status, so it goes.
            // See `CadenceTaskCollection.activeGroupIdentity`.
            iOSTaskGroupSection(
                title: "Active",
                color: Theme.blue,
                tasks: activeTasks,
                showsContainer: showsContainer,
                dropIdentity: collection.activeGroupIdentity
            )

            if showsCompleted {
                // `.completion` resolves to no key: done-ness is not something a new task can be
                // seeded with, so this header neither lights up nor survives emptying.
                iOSTaskGroupSection(
                    title: "Completed",
                    color: Theme.green,
                    // **T-375: the reveal has to survive the cap.** This tier stops at
                    // `completedRowLimit`, newest-settled first, so the deep links most in need of
                    // the reveal — work finished long enough ago that the user went looking for it
                    // through a widget — are exactly the ones the cap would drop. Expanding a
                    // section that still does not list the task is the original defect with an
                    // animation in front of it.
                    tasks: CadenceTaskSurfaceOptions.completedRows(
                        from: completedTasks,
                        tier: .touch,
                        revealing: deepLinkManager.revealedCompletedTaskID
                    ),
                    showsContainer: showsContainer,
                    opacity: 0.62,
                    dropIdentity: .completion,
                    hiddenCount: CadenceTaskSurfaceOptions.hiddenCompletedCount(from: completedTasks, tier: .touch)
                )
            }
        }
        .padding(metrics.cardPadding)
    }
}
#endif

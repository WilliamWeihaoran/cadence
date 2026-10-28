#if os(iOS)
import SwiftUI

/// A task group's header: the section eyebrow, and the drop target under it.
///
/// There were three private near-copies of this — one each in the compact Today, Inbox and All
/// Tasks views, at spacings 9/7, 9/7 and 10/8 — and the iPad versions of the same three screens
/// drew the eyebrow differently again. The row is `CadenceTaskGroupHeading` now; only the drop
/// target below is iOS's.
///
/// **It no longer draws how many rows are under it (T-2056).** The owner asked for the per-section
/// count capsule off iOS and iPadOS, and then off macOS too, so `CadenceTaskGroupHeading` has no
/// `count` to pass. What the capsule was the only surface for — a group whose rows are capped —
/// no longer exists: since T-2057 no group is capped, and every group lists every task it has.
///
/// Usable as a `List` section header as well as inside a `VStack`, which is what lets the
/// `List`-hosted iPad panels and the `ScrollView`-hosted compact ones share it.
struct iOSTaskGroupHeader: View {
    let title: String
    let color: Color
    /// What this group is, so a dropped `+` knows what to inherit from it. `nil` — or an identity
    /// that resolves to nothing — means the header is not a drop target and takes no highlight.
    /// See `CadenceTaskDropSupport.dropKey(forGroup:)`.
    var dropIdentity: CadenceTaskGroupDropIdentity?

    var body: some View {
        // `CadenceTaskGroupHeading`, in `Shared/Components/`, is the row itself now — macOS's Today
        // draws the same one. What stays here is the drop target below, which is iOS's alone.
        // The eyebrow keeps `iOSTaskSectionHeader`'s 6pt top inset, which the shared heading does
        // not carry because it is this host's spacing and not the heading's.
        CadenceTaskGroupHeading(title: title, tint: color)
            .padding(.top, iOSTaskSectionHeader.topPadding)
        // The second half of drag-to-create, and the half that reaches an **empty** group. A row
        // carries its group's attribute by construction, which covers every grouping — but a group
        // with no rows has no row to point at, and that is precisely the group you most want to put
        // the first task into.
        //
        // The ghost opens **below the header**, so on a filled group it parts the header from its
        // first row and on an empty one it *is* the group's body. Same block, same caption, same
        // resolver as the row's — see `iOSNewTaskDropTargetModifier`. Inset 0, not the row's 11:
        // the header shares the group's own leading edge, so the ghost lines up with it.
        //
        // The header itself takes no fill. One layer, at one radius, and it is the ghost's.
        .iOSNewTaskDropTarget(group: dropIdentity)
    }
}

/// One counted group of task rows: `iOSTaskGroupHeader` over the rows it counts.
///
/// The spacings are the majority spelling of the three components this replaced (9 between the
/// header and the rows, 7 between rows); All Tasks' 10/8 was the odd one out.
///
/// **The rows are a `LazyVStack` (T-2057).** No group is capped any more — the owner's answer was
/// *show every task in every group and let the page scroll* — so a group is as long as the store
/// makes it: All Tasks' or Inbox's Completed section is the whole logbook, and an Inbox with 2,000
/// open tasks was already 2,000 rows before the cap went. In a plain `VStack` every one of those
/// `iOSTaskRow`s is built, laid out and rendered on arrival. Lazy, only the rows near the visible
/// region are, and the nesting inside the group's own `VStack` and the page's `LazyVStack` does not
/// defeat that — measured on `Cadence-iPhone15`, see T-2057's ledger entry.
///
/// **Drop frames are unaffected, and that was measured rather than argued (T-2089).** Each row
/// publishes its frame to `iOSNewTaskDropFrameRegistry` on `onGeometryChange` and **retires** it
/// `onDisappear` — liveness only, since T-3008; the frame itself stays behind — and the registry
/// only offers frames clipped to the enclosing scroll view, so an eager stack's scrolled-out rows
/// were never candidates either. A row built *by* scrolling publishes all three of its facts on
/// arrival and is a full target: driven on `Cadence-iPadPro11`, a `+` released on a row that did
/// not exist at launch seeded that row's list, at a point an earlier row had occupied — so the
/// frame T-3011 deliberately leaves behind cannot win, because `candidates()` passes over anything
/// not live. The header is outside this stack, so `isVisible` is untouched.
struct iOSTaskGroupSection: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    /// Whether these rows name the list each task is in. Off on a surface already scoped to one
    /// list, where the chip names the page you are standing on — the Inbox drew "Inbox" on every
    /// row. Ask `CadenceTaskSurfaceOptions.showsContainerChip(on:)` rather than deciding here, so
    /// the answer cannot come out one way on the phone's Inbox and another on the iPad's.
    var showsContainer: Bool = true
    /// Forwarded to `iOSTaskRow.dayAlreadyStatedBySurface`. See there: Today hands its own
    /// `yyyy-MM-dd` down so no row on the page called Today draws a pill reading "Today". Every
    /// other surface leaves it `nil` and gets the full strip.
    var dayAlreadyStatedBySurface: String? = nil
    /// Completed groups are dimmed as a whole rather than row by row.
    var opacity: Double = 1
    /// See `iOSTaskGroupHeader.dropIdentity`. It also decides whether an *empty* group renders at
    /// all — `CadenceTaskDropSupport.showsWhenEmpty(_:)`.
    var dropIdentity: CadenceTaskGroupDropIdentity?

    /// **A group you can still add to does not vanish when it empties; a group you cannot does.**
    /// The call sites used to each guard `if !tasks.isEmpty` before drawing this, which is right for
    /// "Completed" — a heading over nothing, with nothing to do about it — and wrong for a group
    /// that is a drop target, because hiding it puts the one useful destination out of reach at
    /// exactly the moment it matters. One predicate, in the component, so no surface can answer it
    /// differently.
    private var isVisible: Bool {
        !tasks.isEmpty || CadenceTaskDropSupport.showsWhenEmpty(dropIdentity)
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 9) {
                iOSTaskGroupHeader(
                    title: title,
                    color: color,
                    dropIdentity: dropIdentity
                )

                if !tasks.isEmpty {
                    LazyVStack(spacing: 7) {
                        ForEach(tasks) { task in
                            iOSTaskRow(
                                task: task,
                                showsContainer: showsContainer,
                                dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
                            )
                            .opacity(opacity)
                        }
                    }
                }
            }
        }
    }
}

/// A task surface's finished work: the one group on these pages that is folded until you ask for
/// it, drawn at the very bottom of the list.
///
/// **It is always drawn, at the bottom of the list, closed.** The owner asked for *"the completed
/// today section (which is always folded until i unfold it) on the bottom of the list"* and then,
/// for All Tasks, for the same shape in place of the options bar's chip: *"we can remove the
/// completed button cuz we can just make it a foldable title section heading at the very bottom of
/// the list… i think on mac os we have/had something similar"* (T-2090). It does: this is the port
/// of `ListTasksCompletedSectionView` and `TasksPanelCompletedSectionView`, which head macOS's
/// Completed section with `TaskListGroupHeader`'s own collapse and draw the rows only when it is
/// open. Before this, finished work on three of the four iOS surfaces was not a closed section —
/// it was a section that did not exist until you found the control that made it.
///
/// **One component for all four surfaces, because the Mac has one.** Today reached this shape
/// first (T-3076) as a Today-only `iOSTodayCompletedSection`; All Tasks, Inbox and a list's Tasks
/// tab each still drew `if showsCompleted { iOSTaskGroupSection("Completed") }`. Generalising the
/// one that existed is the alternative to a second disclosure vocabulary beside it — the failure
/// the Mac guide calls a parallel mechanism. Only the words, the tint and the accessibility noun
/// differ per surface, and they are parameters.
///
/// **The fold is the host's `showCompleted` bit, not a second `@State` in here**, and that bit is
/// the `@AppStorage(CadencePreferenceKeys.ios*ShowCompleted)` the deleted chip used to write. It
/// **defaults to `false`**, which is the whole of "always folded", and it is why T-2090 is a
/// deletion rather than a state migration: the keys keep their meaning ("is the Completed section
/// open"), keep being written, and so keep riding `CadenceLookPreferenceStore`'s mirror table
/// unchanged. macOS's `@State private var isCompletedCollapsed = true` is the weaker precedent on
/// this one point: the Mac has no synced per-surface bit to follow, and iOS already had one wired
/// through its deep-link reveal (`iOSAllTasksView.revealCompletedIfLinked`, T-375) and its scroll
/// (T-2088), both of which keep working untouched.
///
/// **Why this is not `iOSTaskGroupSection`, which every other group on these pages is.** That
/// component draws its heading unconditionally and owns no disclosure: a chevron row above it would
/// print the title twice, and a chevron inside it would put one on every task group in the app.
/// What should be shared still is — the heading is `CadenceTaskGroupHeading`, the same row the
/// groups above and macOS draw, and the rows are `iOSTaskRow` at the same 7pt spacing in the same
/// `LazyVStack` that T-2057 put them in. Only the fold and its chevron are local, which is the
/// same shape `iOSCalendarBoardView`'s completed footer already uses on the day columns.
struct iOSCompletedTasksSection: View {
    /// The heading's words. Today passes `CadenceTodayPresentationSupport.completedSectionTitle`
    /// ("Completed Today"), which macOS's Today heads its own section with; the collection pages
    /// and a list's Tasks tab pass "Completed", which is what their `iOSTaskGroupSection` said.
    let title: String
    /// The eyebrow's tint, the one knob the two spellings genuinely differ on: Today's shared
    /// `completedSectionAccent`, and `Theme.green` on the surfaces whose group carried it inline.
    let tint: Color
    let tasks: [AppTask]
    /// Asked of `CadenceTaskSurfaceOptions` by the caller, never decided here — this section is
    /// flat, so its rows are the only thing that can say which list a finished task came from.
    let showsContainer: Bool
    /// The surface's own `yyyy-MM-dd`, where it has one. See `iOSTaskRow.dayAlreadyStatedBySurface`.
    var dayAlreadyStatedBySurface: String? = nil
    /// What the accessibility hint calls these rows — "the tasks you finished today" on Today,
    /// "the tasks you have finished" on a page that is not scoped to a day. A hint that named the
    /// wrong span is the only thing a shared disclosure could get wrong per surface.
    let accessibilityNoun: String
    @Binding var isExpanded: Bool

    var body: some View {
        // Nothing finished is not "a closed section with nothing in it" — it is no section. The
        // same predicate `iOSTaskGroupSection.isVisible` applied to this group before, because
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

                CadenceTaskGroupHeading(title: title, tint: tint)
            }
            // The eyebrow's own 6pt top inset, the one `iOSTaskGroupHeader` applies, so this
            // heading sits where every other heading on the page does.
            .padding(.top, iOSTaskSectionHeader.topPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides \(accessibilityNoun)" : "Shows \(accessibilityNoun)")
    }

    /// Completed rows are dimmed as a whole rather than row by row — `iOSTaskGroupSection`'s
    /// `opacity` knob, at the one value every caller ever passed it.
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
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
#endif

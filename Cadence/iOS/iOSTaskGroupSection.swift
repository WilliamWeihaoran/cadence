#if os(iOS)
import SwiftUI

/// A task group's header: the section eyebrow and how many rows are under it.
///
/// There were three private near-copies of this — one each in the compact Today, Inbox and All
/// Tasks views, at spacings 9/7, 9/7 and 10/8 — and the iPad versions of the same three screens
/// drew the eyebrow with no count at all. So "Active" told you how many on the phone and not on
/// the tablet, and the two phone screens that agreed only agreed by coincidence.
///
/// macOS was the fourth copy and the furthest out: its Today drew section titles in sentence case
/// at 11pt in neutral `Theme.dim`, with a red/neutral "3 / 7" pair beside them, so the same group
/// neither said the same thing nor looked the same. The row is `CadenceTaskGroupHeading` now and
/// both platforms draw it; only the drop target below is iOS's.
///
/// Usable as a `List` section header as well as inside a `VStack`, which is what lets the
/// `List`-hosted iPad panels and the `ScrollView`-hosted compact ones share it.
struct iOSTaskGroupHeader: View {
    let title: String
    let color: Color
    /// `nil` suppresses the count capsule — see `CadenceTaskGroupHeading.count` (T-264). Every
    /// group that always knows its size keeps passing a plain `Int`, which converts implicitly.
    let count: Int?
    /// What this group is, so a dropped `+` knows what to inherit from it. `nil` — or an identity
    /// that resolves to nothing — means the header is not a drop target and takes no highlight.
    /// See `CadenceTaskDropSupport.dropKey(forGroup:)`.
    var dropIdentity: CadenceTaskGroupDropIdentity?

    var body: some View {
        // `CadenceTaskGroupHeading`, in `Shared/Components/`, is the row itself now — macOS's Today
        // draws the same one. What stays here is the drop target below, which is iOS's alone.
        // The eyebrow keeps `iOSTaskSectionHeader`'s 6pt top inset, which the shared heading does
        // not carry because it is this host's spacing and not the heading's.
        CadenceTaskGroupHeading(title: title, tint: color, count: count)
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
struct iOSTaskGroupSection: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    /// Whether these rows name the list each task is in. Off on a surface already scoped to one
    /// list, where the chip names the page you are standing on — the Inbox drew "Inbox" on every
    /// row. Ask `CadenceTaskSurfaceOptions.showsContainerChip(on:)` rather than deciding here, so
    /// the answer cannot come out one way on the phone's Inbox and another on the iPad's.
    var showsContainer: Bool = true
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
                    count: tasks.count,
                    dropIdentity: dropIdentity
                )

                if !tasks.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(tasks) { task in
                            iOSTaskRow(task: task, showsContainer: showsContainer)
                                .opacity(opacity)
                        }
                    }
                }
            }
        }
    }
}
#endif

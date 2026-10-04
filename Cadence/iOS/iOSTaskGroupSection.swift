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
/// is still stated, by `CadenceTaskSurfaceOptions.overflowCaption` under the rows; see
/// `iOSTaskGroupSection.hiddenCount`.
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
    /// Rows the caller capped away, from
    /// `CadenceTaskSurfaceOptions.hiddenCompletedCount(from:tier:)`. `nil` is the ordinary case: a
    /// group that lists everything it has.
    ///
    /// **The group counts what it has, not what it drew (T-386).** `tasks` arrives already capped,
    /// so counting it made the header disagree with the options bar above it — "Completed 40" over
    /// a header reading 24. Adding the remainder back gives the section's true size and puts the
    /// difference in a caption under the rows.
    ///
    /// **This is now the *only* thing the true size feeds, and that is why it had to stay
    /// (T-2056).** The header's count capsule is gone on both platforms; the caption under the rows
    /// is what is left saying "there are more of these than you can see", and it is the better of
    /// the two for that job — "Showing 24 of 40" names both numbers, where the capsule named one
    /// and left the reader to count the rows. Deleting the cap instead was considered and is filed
    /// rather than done: these rows are built in a plain `VStack`, so an uncapped Completed section
    /// on All Tasks eagerly constructs one row per finished task, for as many as the store holds.
    var hiddenCount: Int?

    /// The section's true size: the rows drawn plus the rows the cap withheld.
    private var totalCount: Int {
        tasks.count + (hiddenCount ?? 0)
    }

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
                    VStack(spacing: 7) {
                        ForEach(tasks) { task in
                            iOSTaskRow(
                                task: task,
                                showsContainer: showsContainer,
                                dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
                            )
                            .opacity(opacity)
                        }

                        // The line that makes the cap disclosed rather than silent. Not a button:
                        // there is nowhere for it to lead — see
                        // `CadenceTaskSurfaceOptions.overflowCaption(shown:total:)`.
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
                                .accessibilityLabel("\(title): \(caption)")
                        }
                    }
                }
            }
        }
    }
}
#endif

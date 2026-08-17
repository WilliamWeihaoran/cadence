import CoreGraphics

/// One of the two flat task collections — every task, or the unfiled ones — and everything that
/// tells them apart.
///
/// All Tasks and Inbox are the same screen: a page header, the sort/completed bar, an "Active"
/// group and a "Completed" group. They were rendered two ways, and the two ways disagreed about
/// more than they agreed on. What *genuinely* differs between the two collections is here — the
/// words, the glyph, and the one real behavioural difference, which is what their identically
/// titled "Active" group means.
///
/// Deliberately **outside** `#if os(iOS)`, like `iOSPageHeaderMetrics` and for the same reason: the
/// macOS-built test target cannot see `Cadence/iOS/`, and the part worth pinning is the decisions,
/// not the drawing. Nothing in this file draws.
nonisolated enum CadenceTaskCollection: String, CaseIterable, Sendable {
    case allTasks
    case inbox

    /// Which task surface this is, for `CadenceTaskSurfaceOptions`. That file already states, with
    /// no size class in sight, which chrome controls a surface offers and whether its rows name
    /// their list — so the page asks it once instead of each width answering for itself.
    var surface: CadenceTaskSurface {
        switch self {
        case .allTasks: return .allTasks
        case .inbox: return .inbox
        }
    }

    var eyebrow: String {
        switch self {
        case .allTasks: return "Tasks"
        case .inbox: return "Capture"
        }
    }

    var title: String {
        switch self {
        case .allTasks: return "All Tasks"
        case .inbox: return "Inbox"
        }
    }

    /// The header's identity tile.
    var systemImage: String {
        switch self {
        case .allTasks: return "checklist"
        case .inbox: return "tray.fill"
        }
    }

    /// The empty state's glyph, which is the hollow twin of the header's — a page with nothing on
    /// it should not draw the filled tray the header does.
    var emptyIcon: String {
        switch self {
        case .allTasks: return "checklist"
        case .inbox: return "tray"
        }
    }

    // The empty state's *words* are `CadenceEmptyStateCopy`'s, and they are read in an extension in
    // `iOSTaskCollectionPage.swift` rather than here. `CadenceEmptyStateCopy` is main-actor isolated
    // — it was missed by the `nonisolated` pass in `f94361a` that unisolated 215 value types — so
    // reading it from this deliberately `nonisolated` file emits four isolation warnings against a
    // baseline of zero. Marking that enum `nonisolated` is the actual fix, in a file this change
    // does not own.

    /// What the "Active" heading *is*, so a dropped `+` knows what it can inherit from it.
    ///
    /// **The one difference between these two pages that is not a word.** Both head their live rows
    /// "Active", and the headings mean different things: on Inbox every row under it is in the Inbox
    /// by construction, so the header is a real placement and takes a dropped `+`; on All Tasks the
    /// rows span every list, so the heading is completion status and shares nothing a new task could
    /// start from. `CadenceTaskDropSupport.showsWhenEmpty(_:)` reads the same value, which is also
    /// why Inbox's "Active" survives emptying and All Tasks' does not.
    var activeGroupIdentity: CadenceTaskGroupDropIdentity {
        switch self {
        case .allTasks: return .completion
        case .inbox: return .list(key: "inbox", name: "Inbox")
        }
    }
}

/// Every measurement the All Tasks / Inbox page is drawn with, in one value.
///
/// The page existed twice: a `ScrollView` + `LazyVStack` + `iOSTaskGroupSection` at compact width
/// and a `List` + `Section` + `iOSTaskGroupHeader` + `iOSTaskListRow` at regular width — two scroll
/// containers, two separator treatments and two sets of row insets for one screen. The `List` is
/// gone; see `iOSTaskCollectionPage` for the accounting of what it was providing.
///
/// **Almost nothing here varies by width, and what does is not this file's decision.** The gutter
/// and the top inset are read straight off `iOSPageHeaderMetrics`, because the first thing in this
/// scroll view is a page header drawn `padded: false` — the page supplies the header's own inset, so
/// it had better be the header's own number. Everything else is one figure for both widths: the gap
/// between a header and the bar under it is not something a wider pane needs more of.
nonisolated struct iOSTaskCollectionMetrics: Equatable, Sendable {
    /// The page gutter, which is also the header's — see the note above.
    let horizontalPadding: CGFloat
    /// Where the content starts. Likewise the header's own top inset.
    let topPadding: CGFloat
    /// Breathing room at the end of the content, and **not** clearance for anything. The floating
    /// `+` insets scrollable content by its whole footprint through `contentMargins`, and the
    /// iPhone's tab bar is a `VStack` sibling of the content rather than an overlay.
    let bottomPadding: CGFloat
    /// Between the header, the options bar and the group stack.
    let stackSpacing: CGFloat
    /// Between one counted task group and the next.
    let groupSpacing: CGFloat
    /// The group card's inset.
    let cardPadding: CGFloat
    /// What the empty state's card is at least. Two numbers for one component — 220 on All Tasks
    /// and 190 on Inbox — became the larger: an empty page is the one state where the card has no
    /// content to give it height, and there was never a reason for the two to differ by 30pt.
    let emptyStateMinHeight: CGFloat

    /// **One number for both widths**, and the same one Today stacks its groups at
    /// (`CadenceTodaySectionMetrics`), so the three segments of the Tasks tab agree.
    static let groupSpacing: CGFloat = 14

    /// Today's page stack, which is the sibling segment of the same tab. All Tasks stacked its
    /// header, bar and groups 12pt apart and Inbox 11; neither was chosen.
    static let stackSpacing: CGFloat = 10

    static func metrics(isRegularWidth: Bool) -> iOSTaskCollectionMetrics {
        let header = iOSPageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegularWidth)
        return iOSTaskCollectionMetrics(
            horizontalPadding: header.horizontalPadding,
            topPadding: header.topPadding,
            bottomPadding: 16,
            stackSpacing: stackSpacing,
            groupSpacing: groupSpacing,
            cardPadding: 12,
            emptyStateMinHeight: 220
        )
    }
}

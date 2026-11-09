#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

enum iOSSearchScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case lists
    case notes
    case events
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .notes: return "Notes"
        case .events: return "Events"
        // [[T-6984]]: this chip opens the one section headed "Pages", and the Mac names the same
        // category "Pages", so the chip takes the section's own title rather than the "More" it
        // read until 2026-11-02.
        case .progress: return CadenceSearchSection.pages.title
        }
    }

    /// T-5013(b). What the idle line calls this scope, or `nil` on **All**, where there is no one
    /// kind of thing to name and "search all" would say less than "search".
    ///
    /// Spelled out rather than `title.lowercased()`, which would say "search lists" for a chip
    /// that also finds areas. The Pages chip gates the Pages section — the screens themselves — so
    /// that is what it says.
    var idleNoun: String? {
        switch self {
        case .all: return nil
        case .tasks: return "tasks"
        case .lists: return "lists and areas"
        case .notes: return "notes"
        case .events: return "calendar events"
        case .progress: return "pages"
        }
    }

    /// **Which of the shared sections this chip narrows to** ([[T-8765]]), in the one display
    /// order both platforms draw.
    ///
    /// The chips stay iOS-only — the owner's 2026-10-31 call under [[T-8201]], justified by
    /// narrow screens — but the sections under them are now `CadenceSearchSection`, so the phone
    /// and the Mac name a found thing the same way. Two chips cover two sections apiece:
    /// **Lists** is Areas and Projects, which the phone used to merge into one "Lists" heading,
    /// and **Notes** is Event Notes and Notes, which it used to merge into one "Notes" heading.
    ///
    /// **Pages** (the "More" chip until [[T-6984]]) is the odd one. It gated two sections —
    /// Pages, and the "Goals and Habits" one that merged `Goal` and `Habit` behind a destination
    /// apiece — and T-2076 took the second away with the two destinations. The chip stays, because Pages is what a reader looking for
    /// a *screen* rather than a row is searching for, and it is the one section nothing else
    /// shows.
    ///
    /// `.commands` is in no chip's list: it is the Mac palette's keyboard idiom and iOS draws no
    /// such section, which is why `CadenceSearchSection.touchSections` leaves it out.
    var sections: [CadenceSearchSection] {
        switch self {
        case .all: return CadenceSearchSection.touchSections
        case .tasks: return [.tasks]
        case .lists: return [.areas, .projects]
        case .notes: return [.meetingNotes, .notes]
        case .events: return [.events]
        case .progress: return [.pages]
        }
    }

    func shows(_ section: CadenceSearchSection) -> Bool {
        sections.contains(section)
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tasks: return "checkmark.circle"
        case .lists: return "folder"
        case .notes: return "note.text"
        case .events: return "calendar"
        case .progress: return "sparkles"
        }
    }
}

struct iOSSearchListCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let route: iOSListRoute
    let fields: [String]

    /// `CadenceSearchIdentity`'s spelling, which carries which table the row came from. The idle
    /// window is cut on the models by `CadenceSearchIdleSuggestions.lists` ([[T-11194]]), the
    /// order Cmd+K reads too, so this candidate no longer carries a suggestion rank of its own.
    var identity: String {
        switch route {
        case .area(let id): CadenceSearchIdentity.area(id)
        case .project(let id): CadenceSearchIdentity.project(id)
        }
    }

    /// Which of the two shared list sections this row is drawn under ([[T-8765]]). The phone used
    /// to merge both into one "Lists" heading while the Mac palette named Areas and Projects
    /// apart; `CadenceSearchSection` says why the splitting vocabulary won.
    var section: CadenceSearchSection {
        switch route {
        case .area: .areas
        case .project: .projects
        }
    }

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            id: identity,
            destination: .list(route),
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score
        )
    }
}

struct iOSSearchFeatureCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let destination: CadenceFeatureDestination
    let fields: [String]

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            id: CadenceSearchIdentity.page(destination.rawValue),
            destination: .feature(destination),
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score
        )
    }
}

struct iOSSearchResult: Identifiable {
    /// What tapping the row opens.
    ///
    /// This replaces a `Kind` enum that was assigned at eight construction sites and read at none,
    /// sitting beside five mutually exclusive optionals (`task`/`note`/`event`/`listRoute`/
    /// `featureDestination`) that it was supposed to agree with. `Kind` could not be promoted into
    /// driving the row, because everything it could have decided is already carried more precisely:
    /// the icon reflects a task's done state and a list's user-chosen glyph, the colour comes from
    /// the model's `colorHex` or its priority, and the section eyebrow is supplied by the caller.
    /// What it *was* good for is the one thing the row could not do safely — dispatch — so it is
    /// folded into the payload it duplicated. Building a result whose kind disagrees with its
    /// payload is now unrepresentable, and the row's dispatch is exhaustive instead of an ordered
    /// chain of `if let`s where a result carrying two of the five would silently take the first
    /// branch.
    enum Destination {
        case task(AppTask)
        case note(Note)
        case event(EKEvent)
        case list(iOSListRoute)
        case feature(CadenceFeatureDestination)
    }

    /// **T-479. A stable identity, not a fresh `UUID()`.**
    ///
    /// This was `let id = UUID()`, minted at construction. Two things followed. The rank tie-break
    /// `CadenceSearchMatcher.rank` needs an `identity` leg for, and a per-build UUID cannot be it:
    /// it *is* total, but it is a different total order on every recomputation, which is the
    /// nondeterminism the leg exists to remove rather than a fix for it. And SwiftUI got a brand
    /// new identity for every row on every keystroke, so no row was ever the same row twice.
    ///
    /// Spelled by `CadenceSearchIdentity`, the same strings macOS's palette rows carry, and
    /// **non-optional in the memberwise initialiser on purpose** — the T-372a rule applied one
    /// level down. An eighth construction site cannot be added without deciding what identifies
    /// the row it builds.
    let id: String
    let destination: Destination
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let score: Int
    /// Split out of `detail` rather than joined into it, for the same reason macOS's
    /// `GlobalSearchSubtitleParts` splits it out of the subtitle: the due date sits near the
    /// end of a bullet-joined metadata string, so a long list name plus tags truncated it
    /// away entirely. Carried separately, the row can lay it out with priority.
    var dueLabel: String?
}

/// The one funnel every scored section on this screen ranks through.
///
/// **T-479.** Each of the six sections used to end in a bare `.sorted { $0.score > $1.score }` —
/// no title leg and no identity leg — so two rows that merely tied on score came back in `@Query`
/// order. That is more partial than the state T-372 found macOS in, and T-372a's fix could not
/// reach it because nothing here called `rank` at all. It is deliberately one funnel rather than
/// six threaded closures, for the reason `GlobalSearchIndexSupport.rankedResults` is one: a
/// per-section comparator is a per-section opportunity to drop a leg, which is the defect.
///
/// The score is already computed — `CadenceSearchMatcher.matchScore` folds and regex-strips every
/// field on each call, and each section scores while it filters — so this takes the `score:`
/// overload rather than re-scoring from the query.
///
/// **Ranking happens before `prefix`, never after.** `resultSection` shows the first 24 rows, and
/// on a partial order the *window* is nondeterministic too, not just the arrangement inside it:
/// tied rows past the cut are dropped by fetch order. Same rule
/// `GlobalSearchIndexSupport.eventResults` records for macOS.
enum iOSSearchIndexSupport {
    static func rankedResults(_ results: [iOSSearchResult]) -> [iOSSearchResult] {
        CadenceSearchMatcher.rank(
            results,
            score: { $0.score },
            title: { $0.title },
            identity: { $0.id }
        )
    }

    /// The searching Events section's funnel ([[T-14622]]): `CadenceCalendarEventSearchSupport
    /// .rankMatches`, the comparator Cmd+K's `eventResults` ranks through, so a recurring series
    /// lists its next occurrence first on both platforms. Takes the matched event beside its row
    /// because the time leg reads the event, which the row does not carry as a date.
    static func rankedEventResults(
        _ matches: [(event: EKEvent, row: iOSSearchResult)],
        now: Date
    ) -> [iOSSearchResult] {
        CadenceCalendarEventSearchSupport.rankMatches(
            matches,
            now: now,
            event: { $0.event },
            score: { $0.row.score },
            title: { $0.row.title },
            identity: { $0.row.id }
        )
        .map(\.row)
    }
}

/// The filter row above the results. macOS's palette has no scope filter — it is a
/// keyboard surface where you type to narrow — so this has no counterpart to copy;
/// it borrows the shared `iOSSegmentedPill` so it reads as the same control family as the
/// calendar's mode switch instead of inventing a fourth chip.
struct iOSSearchScopePicker: View {
    @Binding var selection: iOSSearchScope
    @Binding var includeCompletedTasks: Bool
    let showsCompletedToggle: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(iOSSearchScope.allCases) { scope in
                    iOSSegmentedPill(
                        title: scope.title,
                        systemImage: scope.icon,
                        isSelected: selection == scope,
                        minWidth: 0
                    ) {
                        withAnimation(.snappy(duration: 0.16)) {
                            selection = scope
                        }
                    }
                }

                if showsCompletedToggle {
                    // A filter, not a scope — separated by a rule so the single-select
                    // pills and this toggle do not read as one seven-way choice.
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 4)

                    iOSSegmentedPill(
                        title: "Completed",
                        systemImage: "checkmark.circle",
                        isSelected: includeCompletedTasks,
                        tint: Theme.green,
                        minWidth: 0
                    ) {
                        withAnimation(.snappy(duration: 0.16)) {
                            includeCompletedTasks.toggle()
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// One search section: an uppercased eyebrow over a single card of rows, matching macOS's
/// grouped palette sections and iOS settings' grouped cards. Each result used to be its own
/// shadowed card, so a ten-result section read as ten unrelated objects rather than one list.
struct iOSSearchResultGroup<Row: View>: View {
    let title: String
    let count: Int
    /// The row that ends a capped section: what it reads, and what tapping it does. `nil` when the
    /// section is already listing every match, so a section drawing all of its results cannot
    /// accidentally draw a "0 more results" row.
    var continuation: iOSSearchResultContinuation?
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrowLabel(text: title)
                .padding(.horizontal, SectionEyebrowLabel.cardListInset)

            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    row(index)

                    // The continuation row is inside the same card as the results, so the last
                    // result needs a rule under it too when one follows.
                    if index < count - 1 || continuation != nil {
                        iOSRowDivider(leadingInset: 46)
                    }
                }

                if let continuation {
                    iOSSearchMoreResultsRow(continuation: continuation)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
        }
    }
}

/// The count row at the foot of a capped search section (T-3089).
struct iOSSearchResultContinuation {
    /// `CadenceSearchResultCap.continuationLabel(hidden:)`'s sentence — "38 more results".
    ///
    /// The sentence rather than the number, and the row below reads it for its accessibility
    /// label too: a second copy of the count here is a second place for the row and the
    /// announcement to disagree about how many results are waiting.
    let label: String
    /// Whether the hardware keyboard's highlight rests here ([[T-11196]] (2)).
    var isHighlighted: Bool = false
    /// Reveals the rest **in place**. There is no screen to push; see `CadenceSearchResultCap`.
    let reveal: () -> Void
}

/// Ends a section whose results were capped, and expands it where it stands.
///
/// It is drawn inside the same card as the rows it is talking about rather than under it: the
/// thing the user is deciding about is this list, and a control floating beside the card would
/// read as a page-level action.
///
/// [[T-12601]]: neutral, in `CadenceSearchResultCap.continuationTint` as Cmd+K's row is -- it is not
/// a result and must not read as one. It drew in `Theme.blue` until then, for no stated reason.
private struct iOSSearchMoreResultsRow: View {
    let continuation: iOSSearchResultContinuation

    var body: some View {
        Button(action: continuation.reveal) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.down")
                    // The companion text's role, which is `CadenceTypography`'s rule for a glyph:
                    // there is no separate glyph curve, and a chevron that grew on a different
                    // ramp from the sentence it points at would stop lining up with it. The base
                    // stays the 13 it already drew — a role owns a curve and a default base, not
                    // the only base — so this is a no-op at `DynamicTypeSize.large`.
                    .cadenceFont(.rowTitle, base: 13, weight: .semibold)
                    .foregroundStyle(CadenceSearchResultCap.continuationTint)
                    // The icon tile's width, so the label starts on the same vertical as every
                    // result title above it.
                    .frame(width: 34)

                Text(continuation.label)
                    .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                    .foregroundStyle(CadenceSearchResultCap.continuationTint)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .searchKeyboardHighlight(continuation.isHighlighted, tint: CadenceSearchResultCap.continuationTint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Show \(continuation.label)")
        .accessibilityHint("Adds the remaining results to this section.")
    }
}

struct iOSSearchResultRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let result: iOSSearchResult
    /// Whether the hardware keyboard's highlight rests on this row ([[T-11196]] (2)). Only an
    /// arrow key sets it, so a touch-only reader never sees one.
    var isHighlighted: Bool = false

    var body: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            iOSIconTile(systemImage: result.icon, color: result.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .cadenceFont(.rowTitle, base: 16, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(wraps ? nil : 2)
                    .fixedSize(horizontal: false, vertical: wraps)
                    .multilineTextAlignment(.leading)

                if !result.subtitle.isEmpty {
                    // `subdued`, not `dim`: this is the destination the row leads to, which
                    // is ordinary reading text, not de-emphasized chrome.
                    Text(result.subtitle)
                        .cadenceFont(.fieldLabel, weight: .regular)
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(wraps ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wraps)
                }

                if !result.detail.isEmpty || result.dueLabel != nil {
                    let detailLayout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                    detailLayout {
                        if !result.detail.isEmpty {
                            Text(result.detail)
                                .cadenceFont(.metadata, weight: .regular)
                                .foregroundStyle(Theme.dim)
                                .lineLimit(wraps ? nil : 1)
                                .fixedSize(horizontal: false, vertical: wraps)
                                .truncationMode(.tail)
                        }

                        if let dueLabel = result.dueLabel {
                            iOSMetaChip(label: dueLabel, color: Theme.amber)
                                .fixedSize(horizontal: !wraps, vertical: true)
                                .layoutPriority(1)
                        }
                    }
                }
            }

            if !wraps { Spacer(minLength: 0) }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .searchKeyboardHighlight(isHighlighted, tint: result.color)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Cmd+K's highlight plate ([[T-11196]] (2)), widened into the card's 12pt gutter so the plate
    /// has room around the icon tile, and narrowed back so the row's layout is unchanged.
    func searchKeyboardHighlight(_ isHighlighted: Bool, tint: Color) -> some View {
        padding(.horizontal, 6)
            .cadenceSearchHighlightPlate(isHighlighted: isHighlighted, tint: tint)
            .padding(.horizontal, -6)
    }
}
#endif

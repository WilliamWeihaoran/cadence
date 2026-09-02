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
        case .progress: return "More"
        }
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
    /// The row's `Area.order` / `Project.order` — the user's own arrangement, which is what the
    /// **idle** suggestion list is cut from. See `suggestionRank`.
    let suggestionOrder: Int
    let fields: [String]

    /// Areas and projects are one section here, so the identity has to carry which table the row
    /// came from — `CadenceSearchIdentity`'s prefix is exactly that.
    var identity: String {
        switch route {
        case .area(let id): CadenceSearchIdentity.area(id)
        case .project(let id): CadenceSearchIdentity.project(id)
        }
    }

    /// Areas before projects, then the user's manual order. Derived from `route` rather than
    /// passed in for the same reason `identity` is: a table half that disagrees with the row's
    /// destination is not representable.
    var suggestionRank: CadenceSearchSuggestionRank {
        switch route {
        case .area: CadenceSearchSuggestionRank(table: 0, order: suggestionOrder)
        case .project: CadenceSearchSuggestionRank(table: 1, order: suggestionOrder)
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

/// A Goals-and-Habits row plus the key its **idle** window is cut on.
///
/// That section merges two tables behind one destination apiece, so — unlike the other four — its
/// candidates are already finished `iOSSearchResult`s by the time they are concatenated, and the
/// `Goal.order` / `Habit.order` they were drawn in is gone. This carries it the two lines to the
/// cut. The searching branch reads `result` alone and ignores the rank, which is correct: a typed
/// query is scored, not arranged.
struct iOSSearchProgressCandidate {
    let result: iOSSearchResult
    let suggestionRank: CadenceSearchSuggestionRank
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
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrowLabel(text: title)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    row(index)

                    if index < count - 1 {
                        iOSRowDivider(leadingInset: 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
        }
    }
}

struct iOSSearchResultRow: View {
    let result: iOSSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iOSIconTile(systemImage: result.icon, color: result.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !result.subtitle.isEmpty {
                    // `subdued`, not `dim`: this is the destination the row leads to, which
                    // is ordinary reading text, not de-emphasized chrome.
                    Text(result.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                }

                if !result.detail.isEmpty || result.dueLabel != nil {
                    HStack(spacing: 6) {
                        if !result.detail.isEmpty {
                            Text(result.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if let dueLabel = result.dueLabel {
                            iOSMetaChip(label: dueLabel, color: Theme.amber)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct iOSNoteDetailSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var isEditorFocused = false
    /// Set when Done could not flush the note. See `flushBeforeDismissing()`.
    @State private var saveFailureNotice: String?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let saveFailureNotice {
                    CadenceInlineFailureNotice(text: saveFailureNotice)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                iOSMarkdownEditingSurface(
                    text: Binding(
                        get: { note.content },
                        set: { updateContent($0) }
                    ),
                    isFocused: $isEditorFocused,
                    placeholder: "Start writing...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    editingNote: note,
                    onOpenReference: openMarkdownReference
                )
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(note.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        guard flushBeforeDismissing() else { return }
                        isEditorFocused = false
                        dismiss()
                    }
                }
            }
            .onChange(of: note.content) { _, _ in
                note.updatedAt = Date()
                try? modelContext.save()
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    /// The fifth note-editor host, and it was spelling the commit itself: `content`, `updatedAt`,
    /// `save()` — the body of `CadenceCoreNoteSupport.update` minus the two things that make it a
    /// commit rather than an assignment. So a note opened from Search neither synced its inline
    /// `#tags` nor renamed itself from its `# H1` (T-223), while the same note opened from the
    /// Notes tab did both.
    private func updateContent(_ content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    /// **T-497.** Done used to end `try? modelContext.save(); dismiss()`, and the dismissal is what
    /// claimed the note was written. The user is still in the field here, so there is nothing to
    /// undo and nothing to un-insert — the sheet simply stays open over the sentence, with what
    /// they typed still in it. See `CadenceInPlaceEditFlush` for the decision this follows.
    private func flushBeforeDismissing() -> Bool {
        note.updatedAt = Date()
        guard CadenceInPlaceEditFlush.flush(in: modelContext) else {
            saveFailureNotice = CadenceInPlaceEditFlush.failureNotice
            return false
        }
        saveFailureNotice = nil
        return true
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }
}
#endif

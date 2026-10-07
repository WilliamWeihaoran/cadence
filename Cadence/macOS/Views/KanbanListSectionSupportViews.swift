#if os(macOS)
import SwiftData
import SwiftUI

struct ListSectionsKanbanView: View {
    let tasks: [AppTask]
    var universeTasks: [AppTask]? = nil
    var area: Area? = nil
    var project: Project? = nil
    var showArchived: Binding<Bool>? = nil
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending
    var highlightedSectionName: String? = nil

    @State private var localShowArchived = false
    @State private var draggingSectionName: String?
    @State private var activeHighlightSectionName: String?
    /// Set when the store refused a column drag (T-870). The columns are already back in their old
    /// order by then, so the board and this sentence agree.
    @State private var reorderFailureNotice: String?
    /// Set when the store refused a column *creation* (T-885). Separate from the drag's notice
    /// because they are different sentences about different gestures — "nothing was moved" is a
    /// lie about a column that was never added — and because a stale one of either would otherwise
    /// be cleared by the other's success. Both reach the board through `boardFailureNotice`.
    @State private var addFailureNotice: String?

    @Environment(\.modelContext) private var modelContext

    private var baseSectionConfigs: [TaskSectionConfig] {
        area?.sectionConfigs ?? project?.sectionConfigs ?? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
    }

    private var sectionConfigs: [TaskSectionConfig] {
        let configs = baseSectionConfigs
        return showArchivedBinding.wrappedValue ? configs.filter(\.isArchived) : configs.filter { !$0.isArchived }
    }

    private var allowsSectionEditing: Bool {
        area != nil || project != nil
    }

    private var showArchivedBinding: Binding<Bool> {
        showArchived ?? $localShowArchived
    }

    /// The board's one report line. A refused *drag* leads, because it is the more recent gesture
    /// whenever both are set: the notices are each cleared by their own next attempt, so the only
    /// way to hold two at once is to have a refused creation still up when a drag is refused too,
    /// and the drag is then what the user just did.
    private var boardFailureNotice: String? {
        reorderFailureNotice ?? addFailureNotice
    }

    var body: some View {
        // T-3020: the columns and their cards are derived ONCE per render. Each column used to run
        // its own filter over the board's whole task list from inside the `ForEach` content
        // closure — O(columns x tasks) over an eager `HStack` — and now indexes one grouping pass.
        let columns = sectionConfigs
        let cardsBySectionName = Self.columnCards(
            from: tasks,
            sections: columns,
            sortField: sortField,
            direction: sortDirection
        )
        ZStack {
            Theme.bg

            VStack(alignment: .leading, spacing: 0) {
                if let boardFailureNotice {
                    CadenceInlineFailureNotice(text: boardFailureNotice)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(columns, id: \.id) { section in
                                let sectionTasks = cardsBySectionName[section.name] ?? []
                                ListSectionKanbanColumn(
                                    section: section,
                                    tasks: sectionTasks,
                                    universeTasks: universeTasks ?? tasks,
                                    // The same array as above, answering a different question: the
                                    // board's whole list, which is the sequence a card drop in any
                                    // one of these columns renumbers (T-1175).
                                    spanTasks: universeTasks ?? tasks,
                                    sortField: sortField,
                                    sortDirection: sortDirection,
                                    area: area,
                                    project: project,
                                    isBeingDragged: draggingSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                    isAnotherSectionBeingDragged: draggingSectionName != nil && draggingSectionName?.caseInsensitiveCompare(section.name) != .orderedSame,
                                    isHighlighted: activeHighlightSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                    onReorderBefore: { movingName in
                                        let reordered = reorderSection(named: movingName, before: section.name)
                                        DispatchQueue.main.async {
                                            draggingSectionName = nil
                                        }
                                        return reordered
                                    }
                                )
                                .id(section.id)
                                .onDrag {
                                    draggingSectionName = section.name
                                    return NSItemProvider(object: NSString(string: "\(kanbanSectionDragPrefix)\(section.name)"))
                                } preview: {
                                    columnDragPreview(for: section)
                                }
                            }

                            if allowsSectionEditing && !showArchivedBinding.wrappedValue {
                                addSectionRail
                            }
                        }
                        .padding(20)
                        .background(Theme.bg)
                    }
                    .background(Theme.bg)
                    .onAppear {
                        applyHighlightIfNeeded(with: proxy)
                    }
                    .onChange(of: highlightedSectionName) { _, _ in
                        applyHighlightIfNeeded(with: proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func applyHighlightIfNeeded(with proxy: ScrollViewProxy) {
        guard let highlightedSectionName,
              let matchingSection = sectionConfigs.first(where: {
                  $0.name.caseInsensitiveCompare(highlightedSectionName) == .orderedSame
              }) else {
            activeHighlightSectionName = nil
            return
        }

        activeHighlightSectionName = matchingSection.name
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(matchingSection.id, anchor: .center)
        }

        let highlightedName = matchingSection.name
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard activeHighlightSectionName?.caseInsensitiveCompare(highlightedName) == .orderedSame else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                activeHighlightSectionName = nil
            }
        }
    }

    /// **Every column's cards in one pass over `tasks` (T-3020), keyed by the column's exact
    /// `name`.**
    ///
    /// The value for a section is exactly what the retired per-column filter produced:
    ///
    ///     tasks.filter {
    ///         !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
    ///     }.taskSorted(by: sortField, direction: direction)
    ///
    /// and it is that by construction rather than by an equivalence argument. The membership test
    /// is still `caseInsensitiveCompare` — never a folded dictionary key, whose agreement with
    /// `NSString`'s comparison (`ß`/`SS`, canonical equivalence) would be a claim to prove — but it
    /// is asked once per *distinct* task section name rather than once per task, and the answer is
    /// cached. Cancelled work is dropped before anything else, so no column ever sees it (T-381).
    /// A task joins every column its name matches, so two columns whose names differ only by case
    /// each draw it, as they did before. Each bucket is filled in `tasks` order and then sorted
    /// once, so the sort sees the same input in the same order and ties land where they did.
    ///
    /// Columns are keyed by exact `name` rather than by `id` because two columns with one name
    /// have one bucket by definition; a column no task names is absent and reads as empty.
    static func columnCards(
        from tasks: [AppTask],
        sections: [TaskSectionConfig],
        sortField: TaskSortField,
        direction: TaskSortDirection
    ) -> [String: [AppTask]] {
        var columnNames: [String] = []
        var seenColumnNames = Set<String>()
        for section in sections where seenColumnNames.insert(section.name).inserted {
            columnNames.append(section.name)
        }

        var columnsByTaskSectionName: [String: [String]] = [:]
        var buckets: [String: [AppTask]] = [:]
        for task in tasks where !task.isCancelled {
            let taskSectionName = task.resolvedSectionName
            let matches: [String]
            if let cached = columnsByTaskSectionName[taskSectionName] {
                matches = cached
            } else {
                matches = columnNames.filter {
                    taskSectionName.caseInsensitiveCompare($0) == .orderedSame
                }
                columnsByTaskSectionName[taskSectionName] = matches
            }
            for columnName in matches {
                buckets[columnName, default: []].append(task)
            }
        }
        return buckets.mapValues { $0.taskSorted(by: sortField, direction: direction) }
    }

    @ViewBuilder
    private var addSectionRail: some View {
        Button {
            addSection()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface.opacity(0.72))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.borderSubtle.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 42)
            .frame(minHeight: 360)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.cadencePlain)
    }

    /// **The new column reaches the store, and says so when it does not (T-885).**
    ///
    /// This rewrote the list's `sectionConfigsRaw` blob and committed nothing at all: the column
    /// appeared on the board, the user renamed it, and next launch had never heard of it. The same
    /// defect as T-870 one door along — and worse, because a reorder that reverts still leaves
    /// every column the user made.
    ///
    /// `.declined` is unreachable from here and is not treated as a failure: the name comes from
    /// `KanbanBoardSupport.nextSectionName`, which is chosen precisely so that no existing column
    /// holds it. It is answered rather than ignored so that a future caller passing a user-typed
    /// name gets told which of the two things happened.
    private func addSection() {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }
        let trimmed = KanbanBoardSupport.nextSectionName(from: baseSectionConfigs)
        let tint = area?.colorHex ?? project?.colorHex ?? TaskSectionDefaults.defaultColorHex
        let outcome = container.addSectionConfig(
            TaskSectionConfig(name: trimmed, colorHex: tint),
            in: modelContext
        )
        addFailureNotice = outcome == .refused ? CadenceSectionConfigAddOutcome.refusalNotice : nil
    }

    /// Column order is one array with no per-column position field, so two devices reordering the
    /// same board cannot both win: this is last-writer-wins, deliberately (`docs/TODO.md` T-358).
    /// What the merge does buy is that a *non*-reordering save from the other device — a rename, a
    /// colour, a wind-down — no longer clobbers an order this one just set.
    /// **It reached no commit at all until T-870.** The blob was rewritten, the board redrew the
    /// column where it was dropped, and the store still held the old order — a rearrangement the
    /// user can see reporting a success that had not happened (T-614). No `\.order` sweep would
    /// ever have found it: a column's position *is* its index in this array, and there is no order
    /// field on a `TaskSectionConfig` to sweep for.
    private func reorderSection(named movingName: String, before targetName: String) -> Bool {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return false }
        let reordered = withAnimation(kanbanColumnReorderAnimation) {
            container.reorderSectionConfigs(in: modelContext) {
                KanbanBoardSupport.reorderedSectionConfigs(
                    $0,
                    movingName: movingName,
                    targetName: targetName
                )
            }
        }
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
        return reordered
    }

    @ViewBuilder
    private func columnDragPreview(for section: TaskSectionConfig) -> some View {
        let tint = section.isDefault ? Theme.dim : Color(hex: section.colorHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(section.isDefault ? 0.55 : 0.9))
                    .frame(width: 8, height: 8)
                Text(section.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surfaceElevated.opacity(0.95))
                .frame(height: 54)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(section.isDefault ? 0.18 : 0.24))
                        .frame(width: 86, height: 10)
                        .padding(10)
                }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(section.isDefault ? 0.06 : 0.11))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.25))
        }
        .shadow(color: Theme.overlayCardShadow, radius: 18, y: 10)
    }
}

#endif

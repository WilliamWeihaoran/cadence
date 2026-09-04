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

    var body: some View {
        ZStack {
            Theme.bg

            VStack(alignment: .leading, spacing: 0) {
                if let reorderFailureNotice {
                    CadenceInlineFailureNotice(text: reorderFailureNotice)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(sectionConfigs, id: \.id) { section in
                                let sectionTasks = sortedTasksForSection(section)
                                ListSectionKanbanColumn(
                                    section: section,
                                    tasks: sectionTasks,
                                    universeTasks: universeTasks ?? tasks,
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

    private func sortedTasksForSection(_ section: TaskSectionConfig) -> [AppTask] {
        let source = tasks.filter {
            !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
        return source.taskSorted(by: sortField, direction: sortDirection)
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

    private func addSection() {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }
        let trimmed = KanbanBoardSupport.nextSectionName(from: baseSectionConfigs)
        let tint = area?.colorHex ?? project?.colorHex ?? TaskSectionDefaults.defaultColorHex
        container.addSectionConfig(TaskSectionConfig(name: trimmed, colorHex: tint))
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

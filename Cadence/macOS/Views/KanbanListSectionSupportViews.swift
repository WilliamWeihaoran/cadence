#if os(macOS)
import SwiftUI

struct ListSectionsKanbanView: View {
    let tasks: [AppTask]
    var universeTasks: [AppTask]? = nil
    var area: Area? = nil
    var project: Project? = nil
    var explicitSectionConfigs: [TaskSectionConfig]? = nil
    var showArchived: Binding<Bool>? = nil
    var onTaskDroppedIntoColumn: ((AppTask, String) -> Void)? = nil
    var assignSectionOnDrop: Bool = true
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending
    var sectionTaskProvider: ((TaskSectionConfig) -> [AppTask])? = nil
    var highlightedSectionName: String? = nil

    @State private var localShowArchived = false
    @State private var draggingSectionName: String?
    @State private var activeHighlightSectionName: String?

    private var baseSectionConfigs: [TaskSectionConfig] {
        explicitSectionConfigs ?? area?.sectionConfigs ?? project?.sectionConfigs ?? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
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
                                onTaskDroppedIntoColumn: onTaskDroppedIntoColumn,
                                assignSectionOnDrop: assignSectionOnDrop,
                                isBeingDragged: draggingSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                isAnotherSectionBeingDragged: draggingSectionName != nil && draggingSectionName?.caseInsensitiveCompare(section.name) != .orderedSame,
                                isHighlighted: activeHighlightSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                onReorderBefore: { movingName in
                                    reorderSection(named: movingName, before: section.name)
                                    DispatchQueue.main.async {
                                        draggingSectionName = nil
                                    }
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
        let source = sectionTaskProvider?(section) ?? tasks.filter {
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
        let trimmed = KanbanBoardSupport.nextSectionName(from: baseSectionConfigs)
        if let area {
            var configs = area.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: area.colorHex))
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: project.colorHex))
            project.sectionConfigs = configs
        }
    }

    private func reorderSection(named movingName: String, before targetName: String) {
        if let area {
            withAnimation(kanbanColumnReorderAnimation) {
                area.sectionConfigs = KanbanBoardSupport.reorderedSectionConfigs(
                    area.sectionConfigs,
                    movingName: movingName,
                    targetName: targetName
                )
            }
        } else if let project {
            withAnimation(kanbanColumnReorderAnimation) {
                project.sectionConfigs = KanbanBoardSupport.reorderedSectionConfigs(
                    project.sectionConfigs,
                    movingName: movingName,
                    targetName: targetName
                )
            }
        }
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
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }
}

struct KanbanFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenTasks: [AppTask]?
    let columnTaskIDs: Set<UUID>
    let capturedTasks: [AppTask]
    private let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if let newID, columnTaskIDs.contains(newID) {
                    if frozenTasks == nil { frozenTasks = capturedTasks }
                } else if frozenTasks != nil {
                    withAnimation(releaseAnimation) {
                        frozenTasks = nil
                    }
                }
            }
    }
}
#endif

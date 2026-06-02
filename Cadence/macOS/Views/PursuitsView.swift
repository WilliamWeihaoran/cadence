#if os(macOS)
import SwiftUI
import SwiftData

struct PursuitsView: View {
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPursuitID: UUID?
    @State private var showCreatePursuit = false
    @State private var editingPursuit: Pursuit?
    @State private var searchText = ""

    private var filteredPursuits: [Pursuit] {
        pursuits.filter { pursuit in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return pursuit.title.lowercased().contains(query)
                || pursuit.desc.lowercased().contains(query)
                || pursuit.kind.label.lowercased().contains(query)
                || (pursuit.context?.name.lowercased().contains(query) ?? false)
        }
    }

    private var pursuitGroups: [PursuitContextGroup] {
        var groups: [PursuitContextGroup] = contexts.compactMap { context in
            let items = filteredPursuits.filter { $0.context?.id == context.id }
            guard !items.isEmpty else { return nil }
            return PursuitContextGroup(
                id: context.id.uuidString,
                title: context.name,
                icon: context.icon,
                colorHex: context.colorHex,
                pursuits: items
            )
        }

        let loose = filteredPursuits.filter { $0.context == nil }
        if !loose.isEmpty {
            groups.append(
                PursuitContextGroup(
                    id: "none",
                    title: "No Context",
                    icon: "circle.dashed",
                    colorHex: "#6b7a99",
                    pursuits: loose
                )
            )
        }
        return groups
    }

    private var selectedPursuit: Pursuit? {
        if let selectedPursuitID {
            return pursuits.first { $0.id == selectedPursuitID }
        }
        return filteredPursuits.first ?? pursuits.first
    }

    private var unassignedGoals: [Goal] {
        PursuitAssignmentRules.unassignedMilestones(from: goals)
    }

    private var unassignedHabits: [Habit] {
        PursuitAssignmentRules.unassignedHabits(from: habits)
    }

    private var hasUnassignedItems: Bool {
        !unassignedGoals.isEmpty || !unassignedHabits.isEmpty
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider().background(Theme.borderSubtle)
                pursuitList
            }
            .frame(minWidth: 360, idealWidth: 440)
            .background(Theme.surface)

            if let pursuit = selectedPursuit {
                PursuitDetailView(
                    pursuit: pursuit,
                    onEdit: { editingPursuit = pursuit }
                )
                .frame(minWidth: 560, idealWidth: 720)
            } else {
                CommitmentEmptyDetail(
                    icon: "sparkles",
                    title: "No pursuits yet",
                    subtitle: "Create a pursuit for ongoing directions like learning, strength, or craft.",
                    background: Theme.bg
                )
                .frame(minWidth: 560, idealWidth: 720)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreatePursuit) {
            CreatePursuitSheet()
        }
        .sheet(item: $editingPursuit) { pursuit in
            CreatePursuitSheet(pursuit: pursuit)
        }
        .onAppear {
            if selectedPursuitID == nil {
                selectedPursuitID = filteredPursuits.first?.id ?? pursuits.first?.id
            }
        }
        .onChange(of: filteredPursuits.map(\.id)) {
            guard let selectedPursuitID,
                  filteredPursuits.contains(where: { $0.id == selectedPursuitID }) || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                self.selectedPursuitID = filteredPursuits.first?.id ?? pursuits.first?.id
                return
            }
        }
    }

    private var header: some View {
        CommitmentPageHeader(
            title: "Pursuits",
            subtitle: "Directions powered by milestones and habits."
        ) {
            CadenceActionButton(
                title: "New Pursuit",
                systemImage: "plus",
                role: .primary,
                size: .compact
            ) {
                showCreatePursuit = true
            }
        } controls: {
            CommitmentSearchField(
                placeholder: "Search pursuits",
                text: $searchText
            )
        }
    }

    @ViewBuilder
    private var pursuitList: some View {
        if pursuitGroups.isEmpty && !hasUnassignedItems {
            Spacer()
            EmptyStateView(
                message: searchText.isEmpty ? "No pursuits yet" : "No matching pursuits",
                subtitle: searchText.isEmpty ? "Use pursuits for ongoing directions, then add milestones and habits inside them." : "Try a different search.",
                icon: "sparkles"
            )
            Spacer()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if hasUnassignedItems {
                        PursuitUnassignedReviewCard(
                            goalCount: unassignedGoals.count,
                            habitCount: unassignedHabits.count
                        )
                    }

                    ForEach(pursuitGroups) { group in
                        PursuitContextGroupView(
                            group: group,
                            selectedPursuitID: selectedPursuitID,
                            onSelect: { selectedPursuitID = $0.id }
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}
#endif

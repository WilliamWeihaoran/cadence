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
        PursuitAssignmentRules.unassignedGoals(from: goals)
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
                EmptyStateView(
                    message: "No pursuits yet",
                    subtitle: "Create a pursuit for ongoing directions like learning, strength, or craft.",
                    icon: "sparkles"
                )
                .frame(minWidth: 560, idealWidth: 720)
                .background(Theme.bg)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pursuits")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Directions powered by goals and habits.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                CadenceActionButton(
                    title: "New Pursuit",
                    systemImage: "plus",
                    role: .primary,
                    size: .compact
                ) {
                    showCreatePursuit = true
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                TextField("Search pursuits", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
        }
        .padding(20)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var pursuitList: some View {
        if pursuitGroups.isEmpty && !hasUnassignedItems {
            Spacer()
            EmptyStateView(
                message: searchText.isEmpty ? "No pursuits yet" : "No matching pursuits",
                subtitle: searchText.isEmpty ? "Use pursuits for ongoing directions, then add goals and habits inside them." : "Try a different search.",
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

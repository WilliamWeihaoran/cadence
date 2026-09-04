#if os(macOS)
import SwiftUI
import SwiftData

struct AttachWorkSheet: View {
    let goal: Goal
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// Grouping, ordering and search all come from `GoalLinkPresentation.candidateGroups`, which
    /// is outside every platform conditional so iOS's `iOSGoalAttachListsSheet` offers the same
    /// candidates in the same order — and so `CadenceTests` can assert what they are. This was a
    /// private computed property here, which is why iOS had nothing to reuse.
    private var groupedLists: [GoalLinkCandidateGroup] {
        GoalLinkPresentation.candidateGroups(
            contexts: contexts,
            areas: areas,
            projects: projects,
            query: searchText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attach Lists")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(goal.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                CadenceActionButton(title: "Done", role: .secondary, size: .compact) {
                    dismiss()
                }
            }
            .padding(20)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                TextField("Search lists", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.borderSubtle, lineWidth: 1))
            .padding(16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    attachListsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 620, height: 700)
        .background(Theme.surface)
    }

    private var attachListsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GoalSectionHeading(title: "Lists", count: GoalLinkPresentation.candidateCount(in: groupedLists))
            if groupedLists.isEmpty {
                CadenceInlineEmpty(text: "No matching lists.", surface: .desktop)
            } else {
                ForEach(groupedLists) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrowLabel(
                            text: group.title,
                            size: .compact,
                            tint: group.context.map { Color(hex: $0.colorHex) } ?? Theme.dim
                        )
                            .padding(.top, 4)
                        ForEach(group.targets) { target in
                            AttachListCandidateRow(
                                icon: target.icon,
                                title: target.displayName,
                                subtitle: target.openTaskLabel,
                                color: Color(hex: target.colorHex),
                                isAttached: GoalLinkPresentation.isAttached(target, to: goal),
                                onToggle: { modelContext.toggleGoalListLink(target, on: goal) }
                            )
                        }
                    }
                }
            }
        }
    }
}
#endif

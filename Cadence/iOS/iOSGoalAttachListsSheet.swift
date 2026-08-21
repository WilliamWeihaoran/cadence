#if os(iOS)
import SwiftData
import SwiftUI

/// Attach or detach the areas and projects whose tasks count toward a goal — iOS's route to the
/// links `GoalContributionResolver` has always folded into a goal's percentage.
///
/// **A sheet, not a popover.** `iOSChoicePopoverList` is the app's inline picker and is
/// single-selection by construction; this is a multi-select over a context-grouped list that can
/// be as long as the sidebar, and it needs a search field. That is the shape macOS's
/// `AttachWorkSheet` already has, and the shape `iOSMarkdownReferencePickerSheet` already
/// establishes on iOS — `NavigationStack`, `.searchable`, a scrolling column of rows rather than a
/// `List` (a `List` brings its own inset, separator and selection plate, so every row would carry
/// system chrome at a system radius under the app's own). One sheet serves both size classes: the
/// phone gets a full-height sheet, the iPad a form sheet, and the rows are identical.
///
/// Nothing here decides anything. The grouping, the filtering and the writes are
/// `GoalLinkPresentation` / `ModelContext.toggleGoalListLink`, which is what macOS calls too.
struct iOSGoalAttachListsSheet: View {
    let goal: Goal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var query = ""

    private var groups: [GoalLinkCandidateGroup] {
        GoalLinkPresentation.candidateGroups(
            contexts: contexts,
            areas: areas,
            projects: projects,
            query: query
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    // A picker empty state keeps its subtitle — it says something the screen does
                    // not.
                    iOSEmptyPanel(
                        systemImage: "folder.badge.questionmark",
                        title: query.isEmpty ? "No lists yet" : "No matching lists",
                        subtitle: query.isEmpty
                            ? "Create an area or project first, then attach it here."
                            : "Nothing matches that search."
                    )
                } else {
                    candidateList
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search lists")
            .navigationTitle("Attach Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .tint(Color(hex: goal.colorHex))
        }
        .preferredColorScheme(.dark)
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        SectionEyebrowLabel(
                            text: group.title,
                            tint: group.context.map { Color(hex: $0.colorHex) } ?? Theme.dim
                        )
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                        ForEach(group.targets) { target in
                            iOSGoalLinkCandidateRow(
                                target: target,
                                isAttached: GoalLinkPresentation.isAttached(target, to: goal),
                                onToggle: { modelContext.toggleGoalListLink(target, on: goal) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

/// One attachable list. The checkmark is the state, so the row is a toggle rather than a
/// navigation — nothing is pushed and the sheet stays open, which is what makes attaching three
/// lists three taps.
private struct iOSGoalLinkCandidateRow: View {
    let target: GoalLinkTarget
    let isAttached: Bool
    let onToggle: () -> Void

    var body: some View {
        let color = Color(hex: target.colorHex)

        Button(action: onToggle) {
            HStack(spacing: 11) {
                iOSIconTile(systemImage: target.icon, color: color, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(target.openTaskLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isAttached ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isAttached ? color : Theme.dim)
            }
            // One layer, one radius: the row's own fill is the only selection treatment on it.
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isAttached ? color.opacity(0.12) : Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }
}
#endif

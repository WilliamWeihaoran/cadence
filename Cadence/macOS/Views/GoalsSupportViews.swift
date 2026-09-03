#if os(macOS)
import SwiftUI
import SwiftData

// `Goal.dependsOnGoalIDsJSON` had a full JSON get/set accessor here with zero readers and zero
// writers — a goal-dependency feature that never shipped. The accessor is gone; the stored
// property stays, because there is no `SchemaMigrationPlan` and dropping a stored SwiftData
// property discards whatever is already on disk and in CloudKit rather than tidying it up.

enum GoalStatusFilter: CaseIterable {
    case active, paused, done, all

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        case .all: return "All"
        }
    }

    func matches(_ status: GoalStatus) -> Bool {
        switch self {
        case .all: return true
        case .active: return status == .active
        case .paused: return status == .paused
        case .done: return status == .done
        }
    }

    /// Whether this selection can hide a goal that exists.
    ///
    /// Read by the Goals page and the roadmap to tell "you have no goals" apart from "the filter
    /// matched none of them". The default is `.active`, so a reader whose only goals are finished
    /// was being told to create their first one.
    var narrowsResults: Bool { self != .all }
}

/// One top-level goal (a direction) plus the milestones nested under it. `parentGoal` is nil only
/// for synthetic buckets that aren't backed by a real goal.
struct GoalMissionGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    var parentGoal: Goal? = nil
    /// Milestones that survived the page's filter, i.e. the ones actually rendered.
    let goals: [Goal]
    /// Milestones the direction owns that the current filter dropped.
    ///
    /// Without this the header counted only the surviving milestones while the percentage beside
    /// it was resolved from *all* of them, so the default `.active` filter over a direction whose
    /// milestones are all done read "0 milestones · 50%" directly above "No milestones under this
    /// goal yet" — the screen quoting progress from work it simultaneously said did not exist.
    var hiddenMilestoneCount: Int = 0

    /// Owned milestones, filtered or not. This is what the percentage is computed over.
    var ownedMilestoneCount: Int { goals.count + hiddenMilestoneCount }

    /// Label for the header's milestone count. Says "N of M" whenever the filter is hiding some,
    /// so the count and the percentage next to it are talking about the same set of milestones.
    var milestoneCountLabel: String {
        guard hiddenMilestoneCount > 0 else {
            return goals.count == 1 ? "1 milestone" : "\(goals.count) milestones"
        }
        return "\(goals.count) of \(ownedMilestoneCount) milestones"
    }

    /// Shown in place of the milestone list when nothing survived the filter. "No milestones yet"
    /// is only true when the direction genuinely owns none; otherwise it names the hidden ones.
    var emptyMilestonesText: String {
        guard hiddenMilestoneCount > 0 else {
            return "No milestones under this goal yet."
        }
        return hiddenMilestoneCount == 1
            ? "1 milestone is hidden by the current filter."
            : "\(hiddenMilestoneCount) milestones are hidden by the current filter."
    }
}

/// Builds the Goals page's direction/milestone grouping. Lives here, out of `GoalsView`, so the
/// agreement between what a group counts and what it renders is testable without a view.
enum GoalMissionGrouping {
    /// Top-level goals become groups; everything nested beneath one is shown as its milestones.
    /// Descendants are flattened depth-first so a deeper chain can never hide a goal entirely.
    static func groups(from allGoals: [Goal], matches: (Goal) -> Bool) -> [GoalMissionGroup] {
        GoalAssignmentRules
            .topLevelGoals(from: allGoals)
            .compactMap { parent in
                let owned = nestedGoals(under: parent)
                let milestones = owned.filter(matches)
                guard matches(parent) || !milestones.isEmpty else { return nil }
                return GoalMissionGroup(
                    id: parent.id.uuidString,
                    title: parent.title,
                    icon: parent.icon,
                    colorHex: parent.colorHex,
                    parentGoal: parent,
                    goals: milestones,
                    hiddenMilestoneCount: owned.count - milestones.count
                )
            }
    }

    static func nestedGoals(under goal: Goal) -> [Goal] {
        var visited: Set<UUID> = [goal.id]
        var result: [Goal] = []

        func walk(_ parent: Goal) {
            for child in GoalAssignmentRules.milestones(of: parent) where !visited.contains(child.id) {
                visited.insert(child.id)
                result.append(child)
                walk(child)
            }
        }

        walk(goal)
        return result
    }
}

struct GoalMissionGroupView: View {
    let group: GoalMissionGroup
    let selectedGoalID: UUID?
    let onSelect: (Goal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let parentGoal = group.parentGoal {
                GoalDirectionHeaderCard(
                    goal: parentGoal,
                    milestoneCountLabel: group.milestoneCountLabel,
                    isSelected: selectedGoalID == parentGoal.id,
                    onSelect: { onSelect(parentGoal) }
                )
            } else {
                CommitmentGroupHeader(
                    title: group.title,
                    icon: group.icon,
                    color: Color(hex: group.colorHex),
                    trailingText: "\(group.goals.count)"
                )
            }

            Group {
                if group.goals.isEmpty {
                    CadenceInlineEmpty(text: group.emptyMilestonesText, surface: .desktop)
                } else {
                    VStack(spacing: 10) {
                        ForEach(group.goals) { goal in
                            GoalMissionCard(
                                goal: goal,
                                isSelected: selectedGoalID == goal.id,
                                onSelect: { onSelect(goal) }
                            )
                        }
                    }
                }
            }
            .padding(.leading, group.parentGoal == nil ? 0 : 16)
        }
    }
}

/// Header card for a top-level goal. Selectable so the inspector can show the direction itself,
/// not just its milestones.
struct GoalDirectionHeaderCard: View {
    let goal: Goal
    /// Pre-rendered by `GoalMissionGroup` so the count can say "1 of 4" when the filter is hiding
    /// milestones whose work the percentage on the same row is still counting.
    let milestoneCountLabel: String
    let isSelected: Bool
    let onSelect: () -> Void

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var tint: Color {
        Color(hex: goal.colorHex)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                CommitmentIconTile(
                    systemImage: goal.icon,
                    color: tint,
                    size: 34,
                    iconSize: 15
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(goal.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        GoalKindBadge(kind: goal.kind)
                        GoalStatusBadge(status: goal.status)
                    }

                    HStack(spacing: 10) {
                        Text(milestoneCountLabel)
                        Text((goal.habits ?? []).count == 1 ? "1 habit" : "\((goal.habits ?? []).count) habits")
                        if let context = goal.context {
                            Text(context.name)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(summary.percentLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .padding(14)
            .cadenceCard(
                background: isSelected ? Theme.surfaceElevated : Theme.surface,
                cornerRadius: Theme.radiusCard,
                shadowRadius: 12,
                shadowY: 5
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(tint.opacity(0.65), lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GoalMissionCard: View {
    let goal: Goal
    let isSelected: Bool
    let onSelect: () -> Void

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        // One walk per body pass. `GoalContributionResolver.summary` recurses the goal's
        // sub-goals, dedupes through a `Set`, sorts every open task and parses a date string
        // per open task — and the card reads eight different fields off it.
        let summary = self.summary

        return Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(goal.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            GoalStatusBadge(status: goal.status)
                        }
                        Text(goal.desc.isEmpty ? "No definition of done yet" : goal.desc)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(summary.percentLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }

                GoalProgressBar(progress: summary.progress, color: Color(hex: goal.colorHex), height: 4)

                HStack(spacing: 12) {
                    Label(summary.linkedListCount == 0 ? "No lists" : "\(summary.linkedListCount) lists", systemImage: "folder")
                    Label(summary.totalTasks == 0 ? "No tasks" : summary.taskCountLabel, systemImage: "checklist")
                    Spacer(minLength: 0)
                    Text(goal.daysSummary)
                        .foregroundStyle(goal.isOverdue ? Theme.red : Theme.dim)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

                if let nextAction = summary.nextActionTitle {
                    HStack(spacing: 6) {
                        Text(nextAction)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        GoalDueDateLabel(dueDateKey: summary.nextActionDueDate ?? "")
                    }
                    .padding(.top, 1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 14, shadowY: 6)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.75), lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

struct GoalSignalTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(14)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.65), cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
    }
}

struct GoalSectionHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            SectionEyebrowLabel(text: title)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.text.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
            Spacer()
        }
    }
}

struct GoalLinkedListRow: View {
    let link: GoalListLink
    let onDetach: () -> Void

    // T-673: `link.title` falls back to "Missing List" only when neither relationship is set —
    // an area or project with a blank *name* passes that empty string straight through. Route it
    // through the same normalisation the area/project pickers use, keyed on which side is set.
    private var normalizedTitle: String {
        CadenceTitleNormalization.display(
            link.title,
            fallback: link.area != nil
                ? CadenceTitleNormalization.defaultAreaName
                : CadenceTitleNormalization.defaultProjectName
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: link.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: link.colorHex))
                .frame(width: 26, height: 26)
                .background(Color(hex: link.colorHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(GoalLinkPresentation.contributionLabel(for: link))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action: onDetach) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.cadencePlain)
            // T-673: the glyph already says what it removes; the subject is this row's own list.
            .accessibilityLabel("Detach")
            .accessibilityValue(normalizedTitle)
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

/// Due-date chip for goal surfaces, matching `MacTaskRow`'s flag-plus-relative-date treatment.
/// Renders nothing for a task with no due date, so "no deadline" stays distinct from a real one;
/// `fixedSize` keeps the date from being truncated by whatever text shares its row.
private struct GoalDueDateLabel: View {
    let dueDateKey: String
    var fontSize: CGFloat = 11

    var body: some View {
        let key = dueDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let isOverdue = key < DateFormatters.todayKey()
            HStack(spacing: 3) {
                Image(systemName: "flag.fill")
                    .font(.system(size: fontSize - 2, weight: .semibold))
                Text(DateFormatters.relativeDate(from: key))
                    .font(.system(size: fontSize, weight: .medium))
            }
            .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
            .lineLimit(1)
            .fixedSize()
        }
    }
}

struct GoalTaskContributorRow: View {
    let task: AppTask
    let onDetach: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.containerName.isEmpty ? "Inbox" : task.containerName)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    GoalDueDateLabel(dueDateKey: task.dueDate, fontSize: 10)
                }
            }
            Spacer()
            if let onDetach {
                Button(action: onDetach) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.cadencePlain)
                // T-673: this contributor is the task above; hand its own normalised title down
                // rather than letting an untitled task announce as a blank line.
                .accessibilityLabel("Detach")
                .accessibilityValue(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultDisplayTitle))
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

struct AttachListCandidateRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isAttached: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Label(isAttached ? "Attached" : "Attach", systemImage: isAttached ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAttached ? Theme.green : Theme.blue)
            }
            .padding(11)
            .background(isAttached ? Theme.green.opacity(0.1) : Theme.surfaceElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
    }
}

struct GoalStatusBadge: View {
    let status: GoalStatus

    var body: some View {
        CommitmentMetaChip(
            label: GoalStatusPalette.badgeLabel(for: status),
            color: GoalStatusPalette.color(for: status)
        )
    }
}


struct GoalsEmptyDetail: View {
    var body: some View {
        CommitmentEmptyDetail(
            icon: "flag.fill",
            title: "Select a goal",
            subtitle: "The inspector shows contributors, next actions, and momentum."
        )
    }
}

#endif

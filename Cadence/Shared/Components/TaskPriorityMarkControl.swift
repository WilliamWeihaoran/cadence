import SwiftUI

/// Header priority affordance: the shared "!" mark convention on a tinted, clickable surface.
/// Deliberately not a flag glyph — the marks are the app-wide priority language.
///
/// **Shared rather than copied (T-1278).** This lived in `macOS/Views/TaskInspectorFieldSupportViews`
/// and the iOS inspector had a "Priority" field row with a `flag.fill` glyph instead. T-1278 put the
/// marks on both inspectors' title rows, and the owner's stated reason for choosing marks over a
/// flag was *consistency across devices* — so the two platforms draw this one view rather than two
/// that agree by hand. A flag would also have collided with the Due row's own `flag.fill` one line
/// below it, which on macOS is what a flag already means.
///
/// The glyph itself is `TaskTitleSupport.priorityMark(for:)`, the same function the create sheet,
/// the kanban card menu and the priority popovers read, so `!` / `!!` / `!!!` is spelled once for
/// the whole app.
///
/// **28pt is the drawn size, not the touch target.** On macOS a 28pt tile is a comfortable pointer
/// target; on iOS the call site wraps this in `iOSExpandedHitArea` to reach 44 without changing a
/// pixel of what is drawn — the shape is the shared thing, the hit region is the platform's.
struct TaskPriorityMarkControl: View {
    /// The drawn tile's side, and the one place it is spelled (T-1600).
    ///
    /// macOS's `TaskDetailHeaderSection` used to indent everything under the task title by this,
    /// and had once written the 28 out again — two files holding one fact about a view only one of
    /// them draws. That header was deleted as dead code ([[T-6232]]); the side stays named here so
    /// the next reader borrows it rather than retyping it.
    static let side: CGFloat = 28

    let priority: TaskPriority

    private var isSet: Bool { priority != .none }
    private var tint: Color { isSet ? Theme.priorityColor(priority) : Theme.dim }

    var body: some View {
        Text(TaskTitleSupport.priorityMark(for: priority))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(minWidth: Self.side, minHeight: Self.side)
            .background(isSet ? tint.opacity(0.10) : Theme.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                    .strokeBorder(isSet ? tint.opacity(0.30) : Theme.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            .contentShape(Rectangle())
    }
}

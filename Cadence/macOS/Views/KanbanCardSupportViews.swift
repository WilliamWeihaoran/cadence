#if os(macOS)
import SwiftUI
import SwiftData

/// One token of a Ledger card's metadata run, as a macOS picker.
///
/// **The owner's amendment to [[T-8181]], and the reason it is an underline.** macOS board chips
/// were real pickers — do, due and list opened popovers and the estimate badge opened the roller —
/// and a bare text run has no edges to click, so dropping the pills would have regressed editing to
/// the context menu and the inspector. Each token therefore stays a hit target and says so under
/// the pointer with an underline and a link cursor.
///
/// **Nothing here may change the card's height.** Each macOS card is itself a `dropDestination`
/// drawing a 2pt rule at its own top edge (`KanbanDraggableCard`), so a token that grew, gained a
/// pill or picked up padding on hover would slide that rule out from under the pointer mid-drag.
/// `.underline(_:)` draws inside the text's existing line box and `.pointerStyle` draws nothing at
/// all, so the card is byte-for-byte the same size hovered and not.
///
/// This replaced the card's pill chrome: the grey meta chip and the blue duration badge.
struct KanbanLedgerTokenButton: View {
    let token: CadenceLedgerToken
    /// Drawn-focused while this token's picker is open, so a token does not stop looking live the
    /// moment the pointer leaves it for the popover it just opened.
    var isActive: Bool = false
    let accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    let help: String
    var onHoverChanged: (Bool) -> Void = { _ in }
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            CadenceLedgerTokenLabel(token: token, isUnderlined: isHovered || isActive)
        }
        .buttonStyle(.cadencePlain)
        .pointerStyle(.link)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(token.text)
        .modifier(CadenceOptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
        .help(help)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

/// The card's start-time picker ([[T-8185]]): the inspector's `CadenceTimeRoller`, in the same
/// padded panel `CadenceTimeRollerFieldRow` presents it in, with the inspector's "Clear time" under
/// it. Not a new control — the slot token was the one token on the card with nothing to open, and
/// this is what the task's own editor already uses for the same field.
///
/// The roller edits `draftMinutes`, not the task; the minute lands once, in `onDisappear`, through
/// `KanbanCardStateSupport.commitStartMinute`. See that function for why a live binding is wrong.
struct KanbanStartTimePickerPopover: View {
    let task: AppTask
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var draftMinutes: Int
    /// Set by Clear, so the close that follows does not write the draft back over the cleared time.
    @State private var didClear = false

    init(task: AppTask, isPresented: Binding<Bool>) {
        self.task = task
        self._isPresented = isPresented
        self._draftMinutes = State(initialValue: max(0, task.scheduledStartMin))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CadenceTimeRoller(minutes: $draftMinutes) {
                isPresented = false
            }

            Button {
                didClear = true
                CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext)
                isPresented = false
            } label: {
                Text("Clear time")
                    .cadenceFont(.metadata, weight: .semibold)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(CadenceRollerMetrics.panelPadding)
        .background(Theme.surfaceElevated)
        .onDisappear {
            guard !didClear else { return }
            KanbanCardStateSupport.commitStartMinute(draftMinutes, for: task, in: modelContext)
        }
    }
}

struct KanbanCompletionButton: View {
    let icon: String
    let color: Color
    var progress: Double?
    /// The drawn diameter, from `CadenceLedgerCardMetrics` so the two platforms' rings are one
    /// size. This was a local `15` against iOS's `13`; nothing about a pointer needs a bigger
    /// *drawn* circle, and the hit area is a separate question each platform already answers.
    var diameter: CGFloat = CadenceLedgerCardMetrics.ringBase
    /// The state's action phrase, `CadenceTaskCompletionState.accessibilityActionLabel` ([[T-7083]]).
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskCompletionProgressGlyph(
                icon: icon,
                color: color,
                progress: progress,
                size: diameter,
                lineWidth: 1.8
            )
        }
        .buttonStyle(.cadencePlain)
        // T-7083: the list row's circle has said "Complete task" since T-594, and iOS's board card
        // says it too; the Mac card's was an unnamed button.
        .accessibilityLabel(accessibilityLabel)
    }
}

struct KanbanPriorityPickerPopover: View {
    @Binding var priority: TaskPriority
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { value in
                Button {
                    priority = value
                    isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                        Text(TaskTitleSupport.priorityMark(for: value))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(value == .none ? Theme.dim : Theme.priorityColor(value))
                            .frame(width: 24, alignment: .leading)
                        Text(value.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if priority == value {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 150)
        .background(Theme.surfaceElevated)
    }
}

/// Apply an accessibility identifier **only when there is one**.
///
/// `accessibilityIdentifier(_:)` takes a non-optional `String`, and passing `""` is a real
/// assignment rather than a no-op — it clears whatever the element would otherwise publish. A
/// control that takes its identifier from a caller that may not have one therefore needs the
/// modifier to be absent, not empty, and a `ViewModifier` is the only way to say that without
/// erasing the view through `AnyView`.
private struct CadenceOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import SwiftData

/// The rule list behind `MacTaskRow`'s repeat chip ([[T-5015]] (b)).
///
/// **The macOS half of the owner's 2026-10-24 decision on the row marks.** The entry called the
/// iOS row's two marks "chips" and asked whether macOS should gain them or iOS shed them; read
/// side by side they turned out to be different kinds of thing — In Progress a read-only label,
/// the repeat mark an interactive picker — and the owner sent them opposite ways. In Progress went
/// (see `CadenceInProgressStatusRetirement`). The picker comes here: removing it from iOS was
/// explicitly declined, because it is a working control the owner uses and deleting it would push
/// recurrence editing back into the inspector.
///
/// **It is `iOSTaskRowRepeatPickerContent` with the platform swapped, deliberately so.** Same
/// shared `CadenceChoicePopoverList` committing form, same every-case row list, same inline
/// failure notice — because the ask was parity, and a Mac picker that merely did the same *job*
/// through its own list, its own selection mark and its own refusal path is how two platforms
/// start answering the same question differently. The one platform difference is the writer
/// beneath it, below.
///
/// **The write is `MacTaskRowContextMenu.selectRecurrenceRule` and nothing else.** That static is
/// already the Repeat submenu's writer, and it carries the branch that matters: a task belonging
/// to a series must not have its rule changed without first answering "this one" or "this and
/// future". Routing both Mac controls through it means the chip cannot acquire a different answer
/// to that question than the menu has — the drift this repository keeps re-finding whenever one
/// behaviour grows a second implementation.
///
/// **The committing form, so a refused write is reported where it happened ([[T-656]]).** The
/// popover is the only thing on screen that changes, so closing *is* the success report: it stays
/// open over a refusal with the notice under the rows, exactly as the iOS chip does. The menu gets
/// `MacTaskRowMenuOutcomeModifier`'s alert instead only because a menu has already closed by the
/// time its action runs and has nowhere to put a notice. A scope question is not a refusal — the
/// write has not been attempted yet — so that one closes and hands the rule to the row's dialog.
///
/// **`@Query` lives here rather than on the row**, for the reason `MacTaskRowContextMenu` gives
/// about its own: the row exists once per visible task, and a store-wide query per row is a cost
/// a list pays on every one of them. A popover exists only while it is open.
struct MacTaskRowRepeatPickerPopover: View {
    let task: AppTask
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    /// The sentence under the rows when the store refused the rule, as on iOS ([[T-656]]).
    @State private var ruleFailure: String?

    var body: some View {
        // Every case, `.none` included — "Never" is how recurrence is turned *off*, and a picker
        // that cannot unset the field it names is a dead end. `TaskRecurrenceRule.label`'s own
        // comment records that `.none` reads "Never" in exactly this position. The chip that opens
        // this still hides on `.none`; the list does not.
        CadenceChoicePopoverList(
            rows: TaskRecurrenceRule.allCases.map { rule in
                CadenceChoiceRow(value: rule, title: rule.label, systemImage: rule.systemImage, color: Theme.dim)
            },
            selection: task.recurrenceRule,
            isPresented: $isPresented,
            failureNotice: ruleFailure,
            select: { rule in select(rule) }
        )
    }

    private func select(_ rule: TaskRecurrenceRule) -> Bool {
        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            rule,
            for: task,
            allTasks: allTasks,
            modelContext: modelContext
        )
        if case .needsRecurrenceScope(let pending) = outcome {
            pendingRecurrenceRule = pending
        }
        ruleFailure = Self.failureNotice(for: outcome)
        return Self.closesPopover(for: outcome)
    }

    /// **Whether the writer's answer closes the popover, as a function rather than three `return`s
    /// inside a view** — so the one thing that can silently regress here is a thing a test can
    /// drive. `MacTaskRowContextMenu`'s own actions are `static` for the same reason, recorded
    /// there: SwiftUI cannot be presented from a unit test, so anything only reachable through a
    /// view body is only reachable through a UI test.
    ///
    /// Settled and "needs a scope answer" both close. The first because the write landed; the
    /// second because the row's confirmation dialog is what asks next, and a popover left open
    /// underneath it is a stacked presentation. **Only a refusal keeps it open**, which is the
    /// whole of [[T-656]]'s committing form: the close is the success report, so a popover that
    /// closed over a refusal would report a write that did not happen.
    static func closesPopover(for outcome: MacTaskRowContextMenu.ActionOutcome) -> Bool {
        switch outcome {
        case .settled, .needsRecurrenceScope: return true
        case .refused: return false
        }
    }

    /// The sentence to show under the rows, or `nil` to clear one an earlier pick left. Paired with
    /// `closesPopover` deliberately: a popover that stays open **must** say why, and one that
    /// closes must not leave a stale notice behind to greet the next open.
    static func failureNotice(for outcome: MacTaskRowContextMenu.ActionOutcome) -> String? {
        switch outcome {
        case .settled, .needsRecurrenceScope: return nil
        case .refused: return CadenceTaskFieldEditCommit.saveFailureNotice
        }
    }
}
#endif

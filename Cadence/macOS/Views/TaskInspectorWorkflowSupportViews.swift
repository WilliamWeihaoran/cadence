#if os(macOS)
import SwiftUI
import SwiftData

/// The inspector's Repeat field: a row that states the rule *and* how the series ends, plus a
/// two-section popover (REPEATS / ENDS) for editing both.
///
/// Every write — rule or end condition — funnels through `pendingChange`, so a task that belongs
/// to a series always gets the "this task vs this and future" confirmation before anything is
/// persisted. `applyRecurrenceEnd` takes the same `scope:` as `applyRecurrenceRule` precisely so
/// the end condition can honor that choice too; writing the end fields directly here would both
/// bypass the scope and skip the off-mode normalization the model layer does.
struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask
    @Query private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext

    @State private var showPicker = false
    @State private var pendingChange: PendingRecurrenceChange?

    /// One pending edit awaiting the scope confirmation. Rule and end changes share a single case
    /// list so they cannot drift into two dialogs with different wording — or worse, one of them
    /// silently skipping the dialog.
    private enum PendingRecurrenceChange {
        case rule(TaskRecurrenceRule)
        case end(mode: TaskRecurrenceEndMode, dateKey: String, count: Int)
    }

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            rowLabel
                .contentShape(Rectangle())
        }
        // `.plain`, matching `TaskInspectorFieldButtonRow`: the well carries exactly one hover
        // layer (`InspectorPickerHover`, radius 6) so this row cannot read heavier than the
        // Do/Due/Estimate rows sitting directly above it.
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            TaskRecurrencePickerPanel(
                rule: task.recurrenceRule,
                endMode: task.effectiveRecurrenceEndMode,
                endDateKey: task.recurrenceEndDate,
                endCount: task.recurrenceEndCount,
                onSelectRule: selectRule,
                onSelectEnd: selectEnd
            )
        }
        .confirmationDialog(
            "Change repeating task?",
            isPresented: Binding(
                get: { pendingChange != nil },
                set: { if !$0 { pendingChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(TaskRecurrenceEditScope.thisTask.label) {
                applyPendingChange(scope: .thisTask)
            }
            Button(TaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingChange(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingChange = nil
            }
        } message: {
            Text("Choose whether this repeat change applies only here or to this task and future instances.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskInspectorFieldRow(
                label: "Repeat",
                icon: "repeat",
                iconColor: task.isRecurring ? Theme.blue : Theme.dim
            ) {
                TaskInspectorFieldValueText(text: recurrenceLabel, isSet: task.isRecurring)
            }

            if let endSummary {
                Text(endSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    // Aligns under the label, not the glyph — the icon column is a fixed slot.
                    .padding(.leading, TaskInspectorFieldRowMetrics.iconSlot)
                    .padding(.bottom, TaskInspectorFieldRowMetrics.verticalPadding)
            }
        }
    }

    private var recurrenceLabel: String {
        guard task.isRecurring else { return "Never" }
        return TaskRecurrencePresentation.ruleSentence(task.recurrenceRule)
    }

    /// Second line under the row. Only meaningful for a repeating task.
    ///
    /// `.never` deliberately shows nothing: the only next-occurrence date math in the app
    /// (`plannedNextDates` / `nextRecurrenceDateKey` in `CadenceTaskRecurrenceWorkflowSupport`) is
    /// private to the spawn path and can't be reused from here, and reimplementing the shift
    /// rules in a view is exactly the kind of drift that makes the row lie about the series.
    private var endSummary: String? {
        guard task.isRecurring else { return nil }
        switch task.effectiveRecurrenceEndMode {
        case .never:
            return nil
        case .onDate:
            return "Until \(DateFormatters.shortDateString(from: task.recurrenceEndDate))"
        case .afterCount:
            // "N of M" over "M left": the inspector describes *this* occurrence, and the position
            // in the series is the fact the user can't get anywhere else. "M left" throws away
            // where you are and can't be reconstructed from the row.
            return "\(task.recurrenceOccurrenceNumber) of \(task.recurrenceEndCount)"
        }
    }

    // MARK: - Edits

    private func selectRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        stage(.rule(rule))
    }

    private func selectEnd(mode: TaskRecurrenceEndMode, dateKey: String, count: Int) {
        let normalizedDate = mode == .onDate ? dateKey : ""
        let normalizedCount = mode == .afterCount ? max(1, count) : 0
        guard mode != task.recurrenceEndMode
                || normalizedDate != task.recurrenceEndDate
                || normalizedCount != task.recurrenceEndCount else { return }
        stage(.end(mode: mode, dateKey: normalizedDate, count: normalizedCount))
    }

    /// A task already in a series has to ask before it rewrites its siblings; a standalone task
    /// applies straight away.
    private func stage(_ change: PendingRecurrenceChange) {
        if task.isRecurrenceSeriesMember {
            pendingChange = change
        } else {
            apply(change, scope: .thisTask)
        }
    }

    private func applyPendingChange(scope: TaskRecurrenceEditScope) {
        guard let pendingChange else { return }
        apply(pendingChange, scope: scope)
        self.pendingChange = nil
    }

    private func apply(_ change: PendingRecurrenceChange, scope: TaskRecurrenceEditScope) {
        switch change {
        case .rule(let rule):
            TaskWorkflowService.applyRecurrenceRule(rule, to: task, allTasks: allTasks, scope: scope)
            if rule == .none {
                // An end condition on a non-repeating task is meaningless, and leaving it behind
                // would silently re-arm the moment the user turns repeating back on.
                CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                    mode: .never,
                    to: task,
                    allTasks: allTasks,
                    scope: sharedScope(scope)
                )
            }
        case .end(let mode, let dateKey, let count):
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                mode: mode,
                endDateKey: dateKey,
                endCount: count,
                to: task,
                allTasks: allTasks,
                scope: sharedScope(scope)
            )
        }
        try? modelContext.save()
    }

    private func sharedScope(_ scope: TaskRecurrenceEditScope) -> CadenceTaskRecurrenceEditScope {
        switch scope {
        case .thisTask: return .thisTask
        case .thisAndFuture: return .thisAndFuture
        }
    }
}

// MARK: - Presentation helpers

enum TaskRecurrencePresentation {
    /// Row wording: "Every week" reads as a sentence about the task, where the bare enum label
    /// ("Weekly") reads as a setting name.
    static func ruleSentence(_ rule: TaskRecurrenceRule) -> String {
        switch rule {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }

    /// Segment titles for the REPEATS control — the unit alone, since the control's own heading
    /// already supplies the "repeats" half of the phrase.
    static let repeatSegments: [(title: String, rule: TaskRecurrenceRule)] = [
        ("Day", .daily),
        ("Week", .weekly),
        ("Month", .monthly),
        ("Year", .yearly)
    ]
}

// MARK: - Picker panel

/// REPEATS (frequency) stacked over ENDS (stop condition).
///
/// **"Never" is a clear action, not a fifth segment.** The segmented control is a single axis —
/// how often — and "never" isn't a frequency; as a segment it would also be the one segment whose
/// selection blanks the section below it, which reads as a bug. Modelling it as a destructive
/// "Don't repeat" footer matches how the app already clears an optional field (see
/// `TaskInspectorDateControl`'s "Clear date"), and leaves the segmented control unselected — an
/// honest depiction of a task with no recurrence.
private struct TaskRecurrencePickerPanel: View {
    let rule: TaskRecurrenceRule
    let endMode: TaskRecurrenceEndMode
    let endDateKey: String
    let endCount: Int
    let onSelectRule: (TaskRecurrenceRule) -> Void
    let onSelectEnd: (TaskRecurrenceEndMode, String, Int) -> Void

    @State private var showEndDatePicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var countText: String = ""
    /// Snapshot taken when the count field gains focus, so a blur can tell "the user typed
    /// something" from "the user tabbed through". Without it, closing the popover would commit
    /// `.afterCount` over whatever mode was actually selected.
    @State private var countTextAtFocus: String = ""
    @FocusState private var countFocused: Bool

    private let cal = Calendar.current

    private var isRepeating: Bool { rule != .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Repeats")
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            repeatSegmentedControl
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            // The ENDS section is hidden outright while the task doesn't repeat: an end condition
            // on a one-off task has nothing to end.
            if isRepeating {
                Divider().background(Theme.borderSubtle)

                sectionLabel("Ends")
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                endOptions
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                Divider().background(Theme.borderSubtle)

                clearRepeatButton
            }
        }
        .frame(width: 268)
        .background(Theme.surfaceElevated)
        .onAppear {
            countText = String(resolvedCount)
            countTextAtFocus = countText
            viewMonth = monthStart(for: resolvedEndDate)
        }
        .onChange(of: endCount) { _, newValue in
            guard !countFocused else { return }
            countText = String(max(1, newValue))
            countTextAtFocus = countText
        }
        .onDisappear { commitCount(force: false) }
    }

    // MARK: REPEATS

    @ViewBuilder
    private var repeatSegmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(TaskRecurrencePresentation.repeatSegments, id: \.rule) { segment in
                let isSelected = rule == segment.rule
                Button {
                    onSelectRule(segment.rule)
                } label: {
                    Text(segment.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.onColor : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? Theme.blue : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(InspectorPickerHover(cornerRadius: 5))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.surfaceRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: ENDS

    @ViewBuilder
    private var endOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskRecurrenceEndOptionRow(
                title: TaskRecurrenceEndMode.never.label,
                isSelected: endMode == .never
            ) {
                showEndDatePicker = false
                onSelectEnd(.never, "", 0)
            } trailing: {
                EmptyView()
            }

            TaskRecurrenceEndOptionRow(
                title: TaskRecurrenceEndMode.onDate.label,
                isSelected: endMode == .onDate
            ) {
                selectOnDate()
            } trailing: {
                Button {
                    selectOnDate(togglingPicker: true)
                } label: {
                    Text(endDateKey.isEmpty
                         ? DateFormatters.shortDateString(from: defaultEndDateKey)
                         : DateFormatters.shortDateString(from: endDateKey))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(endMode == .onDate ? Theme.text : Theme.dim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.surface)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(InspectorPickerHover(cornerRadius: 5))
            }

            if showEndDatePicker {
                MonthCalendarPanel(
                    selection: Binding(
                        get: { resolvedEndDate },
                        set: { newDate in
                            showEndDatePicker = false
                            onSelectEnd(.onDate, DateFormatters.dateKey(from: newDate), endCount)
                        }
                    ),
                    viewMonth: $viewMonth,
                    isOpen: $showEndDatePicker,
                    inlineStyle: true
                )
                .padding(.vertical, 4)
            }

            TaskRecurrenceEndOptionRow(
                title: TaskRecurrenceEndMode.afterCount.label,
                isSelected: endMode == .afterCount
            ) {
                showEndDatePicker = false
                onSelectEnd(.afterCount, "", resolvedCount)
            } trailing: {
                HStack(spacing: 5) {
                    TextField("", text: $countText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(endMode == .afterCount ? Theme.text : Theme.dim)
                        .multilineTextAlignment(.center)
                        .frame(width: 30)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.surface)
                        )
                        .focused($countFocused)
                        // Committed on submit / focus loss, never per keystroke: each commit can
                        // raise the series scope dialog, and one dialog per typed digit would be
                        // unusable.
                        .onSubmit { commitCount(force: true) }
                        .onChange(of: countFocused) { _, focused in
                            if focused {
                                countTextAtFocus = countText
                            } else {
                                commitCount(force: false)
                            }
                        }

                    Text("times")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    @ViewBuilder
    private var clearRepeatButton: some View {
        Button {
            showEndDatePicker = false
            onSelectRule(.none)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Don't repeat")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            // ~0.05em at 9pt.
            .kerning(0.45)
    }

    /// Picking "On date" on a series that has no end date yet would otherwise store an empty key,
    /// which `effectiveRecurrenceEndMode` correctly degrades back to `.never` — the radio would
    /// appear to refuse the click. Seed a usable date and open the calendar so the choice sticks
    /// and is immediately adjustable.
    private func selectOnDate(togglingPicker: Bool = false) {
        let key = endDateKey.isEmpty ? defaultEndDateKey : endDateKey
        viewMonth = monthStart(for: DateFormatters.date(from: key) ?? Date())
        if endMode == .onDate && !endDateKey.isEmpty {
            showEndDatePicker = togglingPicker ? !showEndDatePicker : true
        } else {
            showEndDatePicker = true
            onSelectEnd(.onDate, key, endCount)
        }
    }

    private var defaultEndDateKey: String {
        let target = cal.date(byAdding: .month, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        return DateFormatters.dateKey(from: target)
    }

    private var resolvedEndDate: Date {
        DateFormatters.date(from: endDateKey)
            ?? DateFormatters.date(from: defaultEndDateKey)
            ?? Date()
    }

    /// A stored 0 means "never configured"; 1 would end the series on its very first occurrence,
    /// so seeding the field with the clamp value would be a trap.
    private var resolvedCount: Int { endCount >= 1 ? endCount : 10 }

    /// `force` is Enter — an unambiguous "use this number", which also selects `.afterCount` if it
    /// wasn't already the mode. A blur or a closing popover only commits when the text actually
    /// changed while focused.
    private func commitCount(force: Bool) {
        let parsed = max(1, Int(countText.filter(\.isNumber)) ?? resolvedCount)
        let normalized = String(parsed)
        let textChanged = countText != countTextAtFocus
        if countText != normalized { countText = normalized }
        countTextAtFocus = normalized
        guard force || textChanged else { return }
        guard endMode != .afterCount || parsed != endCount else { return }
        onSelectEnd(.afterCount, "", parsed)
    }

    private func monthStart(for date: Date) -> Date {
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        return cal.date(from: comps) ?? date
    }
}

/// One ENDS radio row: indicator + label on the left, the mode's value control on the right.
/// The whole label area selects the mode; the trailing control edits that mode's value.
private struct TaskRecurrenceEndOptionRow<Trailing: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    TaskRecurrenceRadioIndicator(isSelected: isSelected)

                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailing
        }
        .padding(.vertical, 5)
        .modifier(InspectorPickerHover(cornerRadius: 6))
    }
}

private struct TaskRecurrenceRadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Theme.blue : Theme.dim, lineWidth: 1)

            if isSelected {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 11, height: 11)
    }
}
#endif

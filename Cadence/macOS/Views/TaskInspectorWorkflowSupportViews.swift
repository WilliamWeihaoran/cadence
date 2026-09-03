#if os(macOS)
import SwiftUI
import SwiftData

/// The inspector's Repeat field: a row that states the rule *and* how the series ends, plus a
/// popover (APPLY TO / REPEATS / ENDS) for editing all three.
///
/// The scope used to be a `confirmationDialog` raised after each edit — a system alert that looked
/// nothing like the app and asked the question *after* the choice was made. It is now an "Apply
/// to" row at the top of the popover, so the scope is picked before the edit and travels with it.
/// Every write — rule or end condition — still funnels through `apply`, and both
/// `applyRecurrenceRule` and `applyRecurrenceEnd` take the same `scope:`; writing the recurrence
/// fields directly here would bypass both the series propagation and the off-mode normalization
/// the workflow helpers do.
struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask
    @Query private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext

    @State private var showPicker = false

    /// One recurrence edit. Rule and end changes share a single case list so they cannot drift
    /// into two paths where one of them forgets the scope.
    private enum RecurrenceChange {
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
                // A task that isn't in a series has no siblings to spill onto, so there is no
                // scope question to ask and the row stays hidden.
                showsScope: task.isRecurrenceSeriesMember,
                onSelectRule: selectRule,
                onSelectEnd: selectEnd
            )
        }
    }

    // MARK: - Row

    @ViewBuilder
    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskInspectorFieldRow(
                label: "Repeat",
                icon: "repeat",
                // Amber: the app's "recurring / in cycle" colour. Fixed rather than gated on
                // `isRecurring` so the glyph names the field, not its current value — the value
                // text beside it already says "Never".
                iconColor: Theme.amber
            ) {
                TaskInspectorFieldValueText(text: recurrenceLabel, isSet: task.isRecurring)
            }

            if let endSummary {
                Text(endSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    // Aligns under the label, not the glyph — the icon column is a fixed slot
                    // sitting inside the row's own horizontal inset.
                    .padding(.leading, TaskInspectorFieldRowMetrics.groupHorizontalPadding
                             + TaskInspectorFieldRowMetrics.iconSlot)
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
    /// The wording is `CadenceTaskRecurrenceEndPresentation.summary` rather than a `switch` here,
    /// because iOS's Schedule well now states the same bound and two inline spellings of "3 of 5"
    /// is how they drift apart. See that type for why "N of M" over "M left", and why `.never`
    /// says nothing at all.
    private var endSummary: String? {
        guard task.isRecurring else { return nil }
        return CadenceTaskRecurrenceEndPresentation.summary(
            mode: task.effectiveRecurrenceEndMode,
            endDateKey: task.recurrenceEndDate,
            occurrenceNumber: task.recurrenceOccurrenceNumber,
            endCount: task.recurrenceEndCount
        )
    }

    // MARK: - Edits

    private func selectRule(_ rule: TaskRecurrenceRule, scope: CadenceTaskRecurrenceEditScope) {
        guard task.recurrenceRule != rule else { return }
        apply(.rule(rule), scope: resolvedScope(scope))
    }

    private func selectEnd(mode: TaskRecurrenceEndMode, dateKey: String, count: Int, scope: CadenceTaskRecurrenceEditScope) {
        let normalizedDate = mode == .onDate ? dateKey : ""
        let normalizedCount = mode == .afterCount ? CadenceTaskRecurrenceEndPresentation.normalizedEndCount(count) : 0
        guard mode != task.recurrenceEndMode
                || normalizedDate != task.recurrenceEndDate
                || normalizedCount != task.recurrenceEndCount else { return }
        apply(.end(mode: mode, dateKey: normalizedDate, count: normalizedCount), scope: resolvedScope(scope))
    }

    /// A standalone task has no siblings to propagate to, and the panel hides the scope row for
    /// it — so whatever the panel reports is pinned back to `.thisTask` rather than trusted.
    private func resolvedScope(_ scope: CadenceTaskRecurrenceEditScope) -> CadenceTaskRecurrenceEditScope {
        task.isRecurrenceSeriesMember ? scope : .thisTask
    }

    private func apply(_ change: RecurrenceChange, scope: CadenceTaskRecurrenceEditScope) {
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
                    scope: scope
                )
            }
        case .end(let mode, let dateKey, let count):
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                mode: mode,
                endDateKey: dateKey,
                endCount: count,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        try? modelContext.save()
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

/// APPLY TO (scope, series members only) stacked over REPEATS (frequency) and ENDS (stop
/// condition).
///
/// The scope sits **first** because it qualifies everything below it: the panel applies each edit
/// the moment it is made, so asking afterwards — which is what the old confirmation dialog did —
/// put the question on the wrong side of the answer.
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
    let showsScope: Bool
    let onSelectRule: (TaskRecurrenceRule, CadenceTaskRecurrenceEditScope) -> Void
    let onSelectEnd: (TaskRecurrenceEndMode, String, Int, CadenceTaskRecurrenceEditScope) -> Void

    /// Resets to "this task only" every time the popover opens — the safe default, and the one
    /// the old dialog listed first.
    @State private var scope: CadenceTaskRecurrenceEditScope = .thisTask
    @State private var showEndDatePicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var countText: String = ""
    /// Snapshot taken when the count field gains focus, so a blur can tell "the user typed
    /// something" from "the user tabbed through". Without it, closing the popover would commit
    /// `.afterCount` over whatever mode was actually selected.
    @State private var countTextAtFocus: String = ""
    @FocusState private var countFocused: Bool

    private let cal = Calendar.current

    private var isRepeating: Bool {
        CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsScope {
                sectionLabel("Apply to")
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                scopeOptions
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                Divider().background(Theme.borderSubtle)
            }

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

    // MARK: APPLY TO

    @ViewBuilder
    private var scopeOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wording is deliberately the short inline form, not `CadenceTaskRecurrenceEditScope.label`
            // ("Only This Task" / "This And Future Tasks") — those are title-cased for the alert
            // buttons this row replaced.
            scopeRow("This task only", value: .thisTask)
            scopeRow("This and future", value: .thisAndFuture)
        }
    }

    @ViewBuilder
    private func scopeRow(_ title: String, value: CadenceTaskRecurrenceEditScope) -> some View {
        let isSelected = scope == value
        Button {
            scope = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 11)

                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: 6))
    }

    // MARK: REPEATS

    @ViewBuilder
    private var repeatSegmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(TaskRecurrencePresentation.repeatSegments, id: \.rule) { segment in
                let isSelected = rule == segment.rule
                Button {
                    onSelectRule(segment.rule, scope)
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
            RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                .fill(Theme.surfaceRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
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
                onSelectEnd(.never, "", 0, scope)
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
                            onSelectEnd(.onDate, DateFormatters.dateKey(from: newDate), endCount, scope)
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
                onSelectEnd(.afterCount, "", resolvedCount, scope)
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
            onSelectRule(.none, scope)
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
        SectionEyebrowLabel(text: title, size: .compact)
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
            onSelectEnd(.onDate, key, endCount, scope)
        }
    }

    private var defaultEndDateKey: String {
        CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(calendar: cal)
    }

    private var resolvedEndDate: Date {
        CadenceTaskRecurrenceEndPresentation.resolvedEndDate(endDateKey, calendar: cal)
    }

    /// A stored 0 means "never configured"; 1 would end the series on its very first occurrence,
    /// so seeding the field with the clamp value would be a trap. Both figures — the seed and the
    /// floor — are `CadenceTaskRecurrenceEndPresentation`'s, so iOS's stepper starts where this
    /// field does.
    private var resolvedCount: Int {
        CadenceTaskRecurrenceEndPresentation.resolvedEndCount(endCount)
    }

    /// `force` is Enter — an unambiguous "use this number", which also selects `.afterCount` if it
    /// wasn't already the mode. A blur or a closing popover only commits when the text actually
    /// changed while focused.
    private func commitCount(force: Bool) {
        let parsed = CadenceTaskRecurrenceEndPresentation.normalizedEndCount(
            Int(countText.filter(\.isNumber)) ?? resolvedCount
        )
        let normalized = String(parsed)
        let textChanged = countText != countTextAtFocus
        if countText != normalized { countText = normalized }
        countTextAtFocus = normalized
        guard force || textChanged else { return }
        guard endMode != .afterCount || parsed != endCount else { return }
        onSelectEnd(.afterCount, "", parsed, scope)
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

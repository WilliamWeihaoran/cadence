import SwiftUI

struct CadenceScheduleCaptureOptions {
    var tagChoices: [CadenceSchedulePanelChoice] = []
    var selectedTagIDs: Binding<Set<String>> = .constant([])
    var createTag: ((String) -> String?)?
}

enum CadenceCaptureField: String, CaseIterable, Identifiable {
    case doDate, dueDate, list, tags, repeatRule, priority, estimate, calendar, location

    var id: String { rawValue }
    var title: String {
        switch self {
        case .doDate: return "Do"
        case .dueDate: return "Due"
        case .list: return "List"
        case .tags: return "Tags"
        case .repeatRule: return "Repeat"
        case .priority: return "Priority"
        case .estimate: return "Estimate"
        case .calendar: return "Calendar"
        case .location: return "Location"
        }
    }
    var symbol: String {
        switch self {
        case .doDate, .calendar: return "calendar"
        case .dueDate: return "flag"
        case .list: return "tray.full"
        case .tags: return "tag"
        case .repeatRule: return "repeat"
        case .priority: return "exclamationmark"
        case .estimate: return "clock"
        case .location: return "mappin.and.ellipse"
        }
    }
}

/// The same ordered inventory drives icons and chips; setting one closes a gap, never reorders it.
enum CadenceCaptureFieldInventory {
    static let taskIcons: [CadenceCaptureField] = [.doDate, .dueDate, .list, .tags]
    static let overflow: [CadenceCaptureField] = [.repeatRule, .priority, .estimate]

    static func isSet(_ field: CadenceCaptureField, draft: CadenceScheduleDraft, tagIDs: Set<String>) -> Bool {
        switch field {
        case .doDate: return !draft.startDateKey.isEmpty
        case .dueDate: return !draft.dueDateKey.isEmpty
        case .list: return CadenceTaskComposerSupport.selection(fromToken: draft.listToken) != .inbox
        case .tags: return !tagIDs.isEmpty
        case .repeatRule: return draft.repeatRule != .none
        case .priority: return (TaskTitleSupport.priorityShortcut(in: draft.title)?.priority ?? draft.priority) != .none
        case .estimate: return draft.estimateIsExplicit
        case .calendar: return !draft.calendarID.isEmpty
        case .location: return !draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func fields(for kind: CadenceScheduleDraftKind) -> [CadenceCaptureField] {
        kind == .task ? taskIcons + overflow : [.doDate, .calendar, .location, .repeatRule]
    }

    /// Whether the host can actually serve `field`, as opposed to merely leaving it unset.
    ///
    /// **Tags are the one row a host can genuinely not serve** ([[T-3171]]). The calendar's
    /// drag-create offers no tag and cannot make one, because the create helper it shares with the
    /// iPad timeline writes none — so its tag icon would open a popover with an empty list and
    /// nothing to type into, which is a control that does nothing rather than a field waiting to
    /// be filled. Every other field is unconditional: an empty List picker is still a picker, and
    /// a Calendar row with nothing in it already says so in words.
    ///
    /// Applied to `fields(for:)`'s result rather than folded into it, so the inventory stays the
    /// one ordered list every presentation reads and the host's answer is a separate, testable
    /// question.
    static func isOffered(_ field: CadenceCaptureField, by options: CadenceScheduleCaptureOptions) -> Bool {
        guard field == .tags else { return true }
        return !options.tagChoices.isEmpty || options.createTag != nil
    }

    static func clear(_ field: CadenceCaptureField, draft: inout CadenceScheduleDraft) {
        switch field {
        case .doDate: draft.clearDoDate()
        case .dueDate: draft.dueDateKey = ""
        case .list:
            draft.listToken = CadenceTaskComposerSupport.token(for: .inbox)
            draft.sectionName = TaskSectionDefaults.defaultName
        case .repeatRule:
            draft.repeatRule = .none
            draft.seriesEndMode = .never
            draft.seriesEndDateKey = ""
            draft.seriesEndCount = 0
        case .priority:
            draft.title = CadenceTaskComposerSupport.titleClearingPriorityMarker(draft.title)
            draft.priority = .none
        case .estimate:
            draft.setEstimate(CadenceTaskComposerSupport.defaultEstimatedMinutes)
            draft.estimateIsExplicit = false
        case .calendar: draft.calendarID = ""
        case .location: draft.location = ""
        case .tags: break // Tag selection is host-owned, not a second copy in the schedule draft.
        }
    }
}

/// A mode switch must not turn an untimed task into a scheduled task merely by visiting Event.
struct CadenceCaptureKindMemory {
    private var task: CadenceScheduleDraft?
    private var event: CadenceScheduleDraft?

    mutating func select(_ kind: CadenceScheduleDraftKind, draft: inout CadenceScheduleDraft) {
        guard draft.kind != kind else { return }
        if draft.kind == .task { task = draft } else { event = draft }
        let remembered = kind == .task ? task : event
        var next = remembered ?? draft
        next.kind = kind
        next.title = draft.title
        next.notes = draft.notes
        if kind == .event, remembered == nil {
            next.isAllDay = false
            if next.startDateKey.isEmpty {
                next.startDateKey = DateFormatters.todayKey()
                next.endDateKey = next.startDateKey
            }
        }
        draft = next
    }
}

/// A presentation of CadenceSchedulePanel. Pickers edit its value; only its host can commit.
struct CadenceScheduleCaptureCard<NotesField: View>: View {
    @Binding var draft: CadenceScheduleDraft
    var listChoices: [CadenceSchedulePanelChoice]
    var sectionChoices: [String]
    var calendarChoices: [CadenceSchedulePanelChoice]
    var calendarUnavailableNotice: String?
    var failureNotice: String?
    var canCommit: Bool
    var options: CadenceScheduleCaptureOptions
    var actions: CadenceSchedulePanelActions
    var notesField: NotesField?

    @State private var activeField: CadenceCaptureField?
    @State private var dateMonth = Date()
    @State private var repeatEndMonth = Date()
    @State private var showsCustomRepeat = false
    @State private var kindMemory = CadenceCaptureKindMemory()
    @State private var actionError: String?
    @State private var newTagName = ""
    @FocusState private var titleIsFocused: Bool
    @FocusState private var notesIsFocused: Bool

    private var selectedTags: Set<String> { options.selectedTagIDs.wrappedValue }
    private var fields: [CadenceCaptureField] {
        CadenceCaptureFieldInventory.fields(for: draft.kind)
            .filter { CadenceCaptureFieldInventory.isOffered($0, by: options) }
    }
    private func isSet(_ field: CadenceCaptureField) -> Bool {
        CadenceCaptureFieldInventory.isSet(field, draft: draft, tagIDs: selectedTags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CadenceScheduleKindSwitch(kind: kindBinding, isEditing: false, identifierPrefix: "capture-kind")
                    .frame(maxWidth: 240)
                Spacer(minLength: 0)
                Button(action: actions.cancel) { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel capture")
                    .accessibilityIdentifier("capture-cancel")
                    .help("Cancel capture")
                    .frame(width: 44, height: 44)
            }
            TextField(draft.kind.titlePlaceholder, text: $draft.title)
                .textFieldStyle(.plain)
                .cadenceFont(.composerTitle)
                .focused($titleIsFocused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("capture-title")
            if let notesField { notesField }
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .cadenceFont(.bodyText)
                .lineLimit(notesIsFocused || !draft.notes.isEmpty ? 3...6 : 1...1)
                .focused($notesIsFocused)

            let chips = fields.filter(isSet)
            if !chips.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(chips) { field in
                        Button { open(field) } label: {
                            Label(chipTitle(field), systemImage: field.symbol)
                                .cadenceFont(.metadata)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
                        }
                        .accessibilityLabel("\(field.title): \(chipTitle(field))")
                        .accessibilityIdentifier("capture-chip-\(field.rawValue)")
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(fields.filter { !isSet($0) && !CadenceCaptureFieldInventory.overflow.contains($0) }) { field in
                    Button { open(field) } label: {
                        Image(systemName: field.symbol).frame(width: 44, height: 44)
                    }
                    .help(field.title)
                    .accessibilityLabel("Set \(field.title)")
                    .accessibilityIdentifier("capture-set-\(field.rawValue)")
                }
                Menu {
                    Button("Repeat", systemImage: "repeat") { open(.repeatRule) }
                    if draft.kind == .task {
                        Button("Priority", systemImage: "exclamationmark") { open(.priority) }
                        Button("Estimate", systemImage: "clock") { open(.estimate) }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .help("More capture options")
                .accessibilityLabel("More capture options")
                .accessibilityIdentifier("capture-more")
                Button(action: commit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .cadenceFont(.composerTitle)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Create \(draft.kind.title.lowercased())")
                .accessibilityIdentifier("capture-create")
                .help("Create \(draft.kind.title.lowercased())")
                .disabled(!canCommit || TaskTitleSupport.normalized(draft.title).isEmpty)
            }
            if draft.kind == .event, let calendarUnavailableNotice {
                CadenceInlineNotice(text: calendarUnavailableNotice, tone: .informational)
            }
            if let notice = actionError ?? failureNotice {
                CadenceInlineNotice(text: notice, tone: .failure)
            }
            if draft.kind == .task, let notice = draft.doAfterDueNotice {
                CadenceInlineNotice(text: notice, tone: .warning)
            }
        }
        .padding(16)
        .foregroundStyle(Theme.text)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        .buttonStyle(.cadencePlain)
        .cadenceFont(.controlLabel)
        .cadenceScaledTypography()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-card")
        // The popover belongs to the card, not to an icon that disappears when its field is set.
        .popover(item: $activeField) { field in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(field.title).cadenceFont(.controlLabel, weight: .semibold)
                        Spacer()
                        Button("Done") { activeField = nil }
                    }
                    editor(field)
                    if let actionError { CadenceInlineNotice(text: actionError, tone: .failure) }
                    if isSet(field), field != .calendar, !(field == .doDate && draft.kind == .event) {
                        Button("Clear \(field.title)") { clear(field) }
                            .foregroundStyle(Theme.red)
                    }
                }
                .padding(12)
            }
            .frame(idealWidth: 320, maxHeight: 520)
            .background(Theme.surfaceElevated)
            .cadenceScaledTypography()
            .presentationCompactAdaptation(.popover)
        }
        .onAppear { titleIsFocused = true }
        .onChange(of: activeField) { _, field in if field == nil { titleIsFocused = true } }
        .onChange(of: draft.title) { _, _ in actionError = nil }
    }

    private var kindBinding: Binding<CadenceScheduleDraftKind> {
        Binding(get: { draft.kind }, set: { kind in
            kindMemory.select(kind, draft: &draft)
            activeField = nil
            actionError = nil
        })
    }

    private func chipTitle(_ field: CadenceCaptureField) -> String {
        switch field {
        case .doDate:
            if draft.kind == .event { return draft.scheduleLabel }
            return draft.scheduledStartMin < 0 ? draft.doRowLabel : "\(draft.doRowLabel) · \(draft.doTimeLabel)"
        case .dueDate: return "Due \(draft.dueRowLabel)"
        case .list:
            let list = listChoices.first { $0.id == draft.listToken }?.name ?? "Inbox"
            return draft.sectionName == TaskSectionDefaults.defaultName ? list : "\(list) · \(draft.sectionName)"
        case .tags:
            return options.tagChoices.filter { selectedTags.contains($0.id) }.map(\.name).joined(separator: ", ")
        case .repeatRule:
            switch draft.seriesEndMode {
            case .never: return draft.repeatRule.label
            case .onDate: return "\(draft.repeatRule.label) until \(DateFormatters.shortDateString(from: draft.seriesEndDateKey))"
            case .afterCount: return "\(draft.repeatRule.label) · \(draft.seriesEndCount) times"
            }
        case .priority: return "\((TaskTitleSupport.priorityShortcut(in: draft.title)?.priority ?? draft.priority).label) priority"
        case .estimate: return "\(draft.estimateMinutes) min"
        case .calendar: return calendarChoices.first { $0.id == draft.calendarID }?.name ?? "Calendar"
        case .location: return draft.location
        }
    }

    private func open(_ field: CadenceCaptureField) {
        titleIsFocused = false
        notesIsFocused = false
        let key = field == .dueDate ? draft.dueDateKey : draft.startDateKey
        dateMonth = DateFormatters.date(from: key) ?? Date()
        repeatEndMonth = DateFormatters.date(from: draft.seriesEndDateKey) ?? dateMonth
        showsCustomRepeat = false
        activeField = field
    }

    private func clear(_ field: CadenceCaptureField) {
        if field == .tags { options.selectedTagIDs.wrappedValue = [] }
        else { CadenceCaptureFieldInventory.clear(field, draft: &draft) }
        activeField = nil
    }

    private func commit() {
        guard canCommit, !TaskTitleSupport.normalized(draft.title).isEmpty else { return }
        actionError = actions.commit()
    }

    @ViewBuilder
    private func editor(_ field: CadenceCaptureField) -> some View {
        switch field {
        case .doDate, .dueDate:
            CadenceQuickDatePopover(
                selection: dateBinding(field), viewMonth: $dateMonth, isOpen: .constant(true),
                showsClear: false, inlineStyle: true
            )
            if field == .doDate {
                Toggle(draft.kind == .event ? "All day" : "Without time", isOn: $draft.isAllDay)
                if !draft.isAllDay {
                    CadenceTimeRoller(minutes: Binding(get: { draft.startMin }, set: { draft.moveStart(toMinute: $0) })) {}
                }
                if draft.kind == .event {
                    Text("Ends").cadenceFont(.controlLabel)
                    CadenceQuickDatePopover(
                        selection: endDateBinding, viewMonth: $repeatEndMonth, isOpen: .constant(true),
                        showsClear: false, inlineStyle: true
                    )
                    if !draft.isAllDay {
                        CadenceTimeRoller(minutes: Binding(get: { draft.endMin }, set: { draft.setEndMinute($0) })) {}
                    }
                }
            }
        case .list:
            CadenceChoicePopoverList(
                rows: listChoices.map {
                    CadenceChoiceRow(value: $0.id, title: $0.name, systemImage: $0.systemImage, color: $0.color)
                },
                selection: $draft.listToken,
                isPresented: .constant(true)
            )
            if !sectionChoices.isEmpty {
                Divider()
                CadenceChoicePopoverList(
                    rows: sectionChoices.map { CadenceChoiceRow(value: $0, title: $0, color: Theme.blue) },
                    selection: $draft.sectionName,
                    isPresented: .constant(true)
                )
            }
        case .tags:
            ForEach(options.tagChoices) { choice in
                Button {
                    var ids = selectedTags
                    if !ids.insert(choice.id).inserted { ids.remove(choice.id) }
                    options.selectedTagIDs.wrappedValue = ids
                } label: { choiceLabel(choice, selected: selectedTags.contains(choice.id)) }
            }
            if let createTag = options.createTag {
                HStack {
                    TextField("New tag", text: $newTagName)
                    Button("Add") {
                        actionError = createTag(newTagName)
                        if actionError == nil { newTagName = "" }
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        case .repeatRule:
            CadenceChoicePopoverList(
                rows: TaskRecurrenceRule.allCases.map { CadenceChoiceRow(value: $0, title: $0.label, color: Theme.blue) },
                selection: Binding(get: { draft.repeatRule }, set: { rule in
                    draft.repeatRule = rule
                    if rule == .none { CadenceCaptureFieldInventory.clear(.repeatRule, draft: &draft) }
                }),
                isPresented: editorIsOpen
            )
            Button("Custom…") { showsCustomRepeat = true }
            if showsCustomRepeat { customRepeat }
        case .priority:
            CadenceChoicePopoverList(
                rows: TaskPriority.allCases.filter { $0 != .none }.map {
                    CadenceChoiceRow(value: $0, title: $0.label, color: Theme.priorityColor($0))
                },
                selection: Binding(get: { TaskTitleSupport.priorityShortcut(in: draft.title)?.priority ?? draft.priority }, set: { priority in
                    draft.title = CadenceTaskComposerSupport.titleClearingPriorityMarker(draft.title)
                    draft.priority = priority
                }),
                isPresented: editorIsOpen
            )
        case .estimate:
            EstimatePickerPopoverContent(value: Binding(
                get: { draft.estimateMinutes },
                set: { value in
                    if value == 0 { CadenceCaptureFieldInventory.clear(.estimate, draft: &draft) }
                    else {
                        draft.setEstimate(value)
                        draft.estimateIsExplicit = true
                    }
                }
            ), unsetValueLabel: "Clear estimate", onClose: { activeField = nil })
        case .calendar:
            CadenceChoicePopoverList(
                rows: calendarChoices.map {
                    CadenceChoiceRow(value: $0.id, title: $0.name, systemImage: $0.systemImage, color: $0.color)
                },
                selection: $draft.calendarID,
                isPresented: editorIsOpen
            )
            if let calendarUnavailableNotice { Text(calendarUnavailableNotice) }
        case .location:
            TextField("Location", text: $draft.location)
                .textFieldStyle(.plain)
                .frame(minHeight: 44)
        }
    }

    private var customRepeat: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrowLabel(text: "Frequency")
            CadenceChoicePopoverList(
                rows: TaskRecurrenceRule.allCases.map { CadenceChoiceRow(value: $0, title: $0.label, color: Theme.blue) },
                selection: $draft.repeatRule,
                isPresented: .constant(true)
            )
            if draft.repeatRule != .none {
                SectionEyebrowLabel(text: "Ends")
                CadenceChoicePopoverList(
                    rows: TaskRecurrenceEndMode.allCases.map { CadenceChoiceRow(value: $0, title: $0.label, color: Theme.blue) },
                    selection: $draft.seriesEndMode,
                    isPresented: .constant(true)
                )
                if draft.seriesEndMode == .onDate {
                    CadenceQuickDatePopover(
                        selection: recurrenceEndBinding, viewMonth: $repeatEndMonth, isOpen: .constant(true),
                        showsClear: false, inlineStyle: true
                    )
                } else if draft.seriesEndMode == .afterCount {
                    Stepper("\(max(1, draft.seriesEndCount)) occurrences", value: $draft.seriesEndCount, in: 1...999)
                }
            }
        }
        .onChange(of: draft.seriesEndMode) { _, mode in
            if mode == .onDate, draft.seriesEndDateKey.isEmpty {
                draft.seriesEndDateKey = draft.startDateKey.isEmpty ? DateFormatters.todayKey() : draft.startDateKey
            }
            if mode == .afterCount { draft.seriesEndCount = max(1, draft.seriesEndCount) }
        }
    }

    private func choiceLabel(_ choice: CadenceSchedulePanelChoice, selected: Bool) -> some View {
        HStack {
            Label(choice.name, systemImage: choice.systemImage).foregroundStyle(choice.color)
            Spacer()
            if selected { Image(systemName: "checkmark") }
        }
        .cadenceFont(.controlLabel)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }

    private func dateBinding(_ field: CadenceCaptureField) -> Binding<Date> {
        Binding(get: {
            DateFormatters.date(from: field == .dueDate ? draft.dueDateKey : draft.startDateKey) ?? Date()
        }, set: { date in
            let key = DateFormatters.dateKey(from: date)
            if field == .dueDate { draft.dueDateKey = key }
            else {
                draft.startDateKey = key
                if draft.kind == .task { draft.endDateKey = key }
                draft.keepEndAfterStart()
            }
        })
    }

    private var endDateBinding: Binding<Date> {
        Binding(get: { DateFormatters.date(from: draft.endDateKey) ?? Date() }, set: {
            let key = DateFormatters.dateKey(from: $0)
            draft.endDateKey = max(key, draft.startDateKey)
            draft.keepEndAfterStart()
        })
    }

    private var recurrenceEndBinding: Binding<Date> {
        Binding(get: { DateFormatters.date(from: draft.seriesEndDateKey) ?? Date() }, set: {
            draft.seriesEndDateKey = DateFormatters.dateKey(from: $0)
        })
    }

    private var editorIsOpen: Binding<Bool> {
        Binding(get: { activeField != nil }, set: { if !$0 { activeField = nil } })
    }
}

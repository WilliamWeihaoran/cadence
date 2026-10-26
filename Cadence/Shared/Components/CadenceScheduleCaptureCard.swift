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
    /// **The relative-date window, stated because the ticket left it to be chosen** ([[T-3237]]
    /// item 3). Seven days each way, then an absolute `Oct 19`.
    ///
    /// A week is the span a person is already holding: inside it `in 4 days` and `Yesterday` are
    /// read directly, and they are shorter than the date. Past it they stop being shorter in the
    /// only sense that matters — `in 23 days` is arithmetic the reader has to undo before they know
    /// which day it is, while `Nov 11` is the answer. Seven rather than fourteen because a chip is
    /// glanced at rather than read, and because a week is a boundary the reader already has.
    ///
    /// Symmetric, unlike `DateFormatters.relativeDate(from:)`'s own unbounded backward arm: a do
    /// date thirty days gone is a date, not a measure of how late it is.
    static let relativeDateCutoffDays = 7

    static let taskIcons: [CadenceCaptureField] = [.doDate, .dueDate, .list, .tags]
    static let overflow: [CadenceCaptureField] = [.repeatRule, .priority, .estimate]

    static func priority(for draft: CadenceScheduleDraft) -> TaskPriority {
        draft.subject.isEditing ? draft.priority : (TaskTitleSupport.priorityShortcut(in: draft.title)?.priority ?? draft.priority)
    }

    static func isSet(_ field: CadenceCaptureField, draft: CadenceScheduleDraft, tagIDs: Set<String>) -> Bool {
        switch field {
        case .doDate: return !draft.startDateKey.isEmpty
        case .dueDate: return !draft.dueDateKey.isEmpty
        case .list: return CadenceTaskComposerSupport.selection(fromToken: draft.listToken) != .inbox
        case .tags: return !tagIDs.isEmpty
        case .repeatRule: return draft.repeatRule != .none
        case .priority: return priority(for: draft) != .none
        case .estimate: return draft.estimateIsExplicit
        case .calendar: return !draft.calendarID.isEmpty
        case .location: return !draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func fields(
        for kind: CadenceScheduleDraftKind,
        offersTaskRepeat: Bool = true,
        offersEventRepeat: Bool = true
    ) -> [CadenceCaptureField] {
        let fields = kind == .task ? taskIcons + overflow : [.doDate, .calendar, .location, .repeatRule]
        return fields.filter { field in
            switch field {
            case .repeatRule: return kind == .task ? offersTaskRepeat : offersEventRepeat
            default: return true
            }
        }
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
            if !draft.subject.isEditing {
                draft.title = CadenceTaskComposerSupport.titleClearingPriorityMarker(draft.title)
            }
            draft.priority = .none
        case .estimate:
            draft.setEstimate(draft.subject.isEditing ? 0 : CadenceTaskComposerSupport.defaultEstimatedMinutes)
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
        guard !draft.subject.isEditing, draft.kind != kind else { return }
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

extension CadenceScheduleDraft {
    /// What choosing an Ends mode in the capture card stores, before the user touches its picker.
    ///
    /// T-3233: `.onDate` used to seed the draft's own START day, which is a series that ends the
    /// day it begins -- and since T-3229 an event's end is written to EventKit as
    /// `EKRecurrenceEnd(end:)`, so a weekly event switched to *On Date* and committed untouched was
    /// a one-occurrence series in Apple Calendar. Every other Ends control seeds
    /// `CadenceTaskRecurrenceEndPresentation.defaultEndDateKey()` (one month ahead); this one now
    /// does too. It is anchored on the later of today and the draft's start, because a capture
    /// draft can start months out, and a month-from-today end before a future start would be a
    /// series with no occurrences at all. A key the user already chose is kept.
    mutating func seedSeriesEnd(
        for mode: TaskRecurrenceEndMode,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        switch mode {
        case .onDate where seriesEndDateKey.isEmpty:
            let today = calendar.startOfDay(for: reference)
            let start = DateFormatters.date(from: startDateKey, in: calendar).map { calendar.startOfDay(for: $0) }
            let anchor = max(today, start ?? today)
            seriesEndDateKey = CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(from: anchor, calendar: calendar)
        case .afterCount:
            // T-6931: this stored `max(1, seriesEndCount)`, so a fresh After seeded a series that
            // ends on its first occurrence. Seed like every other Ends control instead.
            seriesEndCount = CadenceTaskRecurrenceEndPresentation.resolvedEndCount(
                seriesEndCount,
                occurrenceNumber: seriesOccurrenceNumber
            )
        default:
            break
        }
    }

    /// The capture card's repeat chip. T-3233's secondary: a count of one read "1 times".
    var captureRepeatSummary: String {
        switch seriesEndMode {
        case .never: return repeatRule.label
        case .onDate: return "\(repeatRule.label) until \(DateFormatters.shortDateString(from: seriesEndDateKey))"
        case .afterCount:
            return "\(repeatRule.label) · \(seriesEndCount) \(seriesEndCount == 1 ? "time" : "times")"
        }
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
    var readOnlyNotice: String?
    var titleStatus: CadenceSchedulePanelTitleStatus?
    var offersTaskRepeat: Bool
    var offersEventRepeat: Bool
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
    private var isReadOnly: Bool { readOnlyNotice != nil }
    private var fields: [CadenceCaptureField] {
        CadenceCaptureFieldInventory.fields(
            for: draft.kind, offersTaskRepeat: offersTaskRepeat, offersEventRepeat: offersEventRepeat
        ).filter { CadenceCaptureFieldInventory.isOffered($0, by: options) }
    }
    private func isSet(_ field: CadenceCaptureField) -> Bool {
        CadenceCaptureFieldInventory.isSet(field, draft: draft, tagIDs: selectedTags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CadenceScheduleKindSwitch(kind: kindBinding, isEditing: draft.subject.isEditing, identifierPrefix: "capture-kind")
                    .frame(maxWidth: 240)
                Spacer(minLength: 0)
                Button(action: actions.cancel) { Image(systemName: "xmark") }
                    .accessibilityLabel(isReadOnly ? "Done" : "Cancel")
                    .accessibilityIdentifier("capture-cancel")
                    .help(isReadOnly ? "Done" : "Cancel")
                    .frame(width: 44, height: 44)
            }
            if let readOnlyNotice {
                CadenceInlineNotice(text: readOnlyNotice, tone: .informational)
            }
            if let eyebrow = titleStatus?.eyebrow {
                Text(eyebrow).cadenceFont(.metadata).foregroundStyle(titleStatus?.eyebrowTint ?? Theme.dim)
            }
            // **Wraps onto a second and third line rather than truncating** ([[T-3237]] item 1).
            // `CadenceSchedulePanel.titleField` has read `axis: .vertical` + `lineLimit(1...3)`
            // since it was built; this card was the near-copy that kept the single-line form, so a
            // long title lost its tail at the one moment the reader is still composing it. Matching
            // the panel rather than inventing a height keeps one title treatment across the two
            // presentations, and keeps Return on `onSubmit` the way the panel documents at its own
            // field: a vertical-axis field still submits, and the submit is deliberately unguarded.
            TextField(draft.kind.titlePlaceholder, text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .cadenceFont(.composerTitle)
                .lineLimit(1...3)
                .focused($titleIsFocused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("capture-title")
                .strikethrough(titleStatus?.isSettled == true)
                .foregroundStyle(titleStatus?.isSettled == true ? Theme.dim : Theme.text)
                .disabled(isReadOnly)
            if !draft.subject.isEditing, let notesField { notesField }
            if notesField == nil || !draft.subject.isEditing {
                // **The focus jump, fixed at its cause** ([[T-3237]] item 2). The limit used to
                // read `notesIsFocused || !draft.notes.isEmpty ? 3...6 : 1...1`, so focusing an
                // EMPTY field moved the lower bound from one line to three and the card grew by two
                // lines with nothing typed into it; blurring moved it back and the card dropped.
                // The lower bound was answering "is this field focused", which is not a question
                // about how much text there is. A single `1...6` asks only the content: empty is one
                // line whether focused or not, and the field grows a line at a time as it fills, so
                // there is no transition left to jump on. Deliberately NOT a fixed height — that
                // would hide the reflow behind reserved space rather than stop it.
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .cadenceFont(.bodyText)
                    .lineLimit(1...6)
                    .focused($notesIsFocused)
                    .disabled(isReadOnly)
            }

            chipPlacement
            HStack(spacing: 0) {
                if !isReadOnly, let delete = actions.delete {
                    Button("Delete", role: .destructive) { actionError = delete() }
                        .foregroundStyle(Theme.red)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("capture-delete")
                }
                Spacer(minLength: 0)
                ForEach(fields.filter { !isSet($0) && !CadenceCaptureFieldInventory.overflow.contains($0) }) { field in
                    Button { open(field) } label: {
                        Image(systemName: field.symbol).frame(width: 44, height: 44)
                    }
                    .help(field.title)
                    .accessibilityLabel("Set \(field.title)")
                    .accessibilityIdentifier("capture-set-\(field.rawValue)")
                    .disabled(isReadOnly)
                }
                if draft.kind == .task || fields.contains(.repeatRule) {
                    Menu {
                        if fields.contains(.repeatRule) {
                            Button("Repeat", systemImage: "repeat") { open(.repeatRule) }
                        }
                        if draft.kind == .task {
                            Button("Priority", systemImage: "exclamationmark") { open(.priority) }
                            Button("Estimate", systemImage: "clock") { open(.estimate) }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .help("More capture options")
                    .accessibilityLabel("More capture options")
                    .accessibilityIdentifier("capture-more")
                    .disabled(isReadOnly)
                }
                if !isReadOnly {
                    Button(action: commit) {
                        if draft.subject.isEditing {
                            Text("Save").cadenceFont(.controlLabel, weight: .semibold)
                                .frame(minWidth: 44, minHeight: 44)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .cadenceFont(.editorTitle)
                                .imageScale(.large)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .accessibilityLabel(draft.subject.isEditing ? "Save" : "Create \(draft.kind.title.lowercased())")
                    .accessibilityIdentifier(draft.subject.isEditing ? "capture-save" : "capture-create")
                    .help(draft.subject.isEditing ? "Save" : "Create \(draft.kind.title.lowercased())")
                    .disabled(!canCommit || TaskTitleSupport.normalized(draft.title).isEmpty)
                }
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
            if draft.subject.isEditing, let notesField { notesField }
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
        .onAppear { titleIsFocused = !draft.subject.isEditing && !isReadOnly }
        .onChange(of: activeField) { _, field in if field == nil { titleIsFocused = !draft.subject.isEditing && !isReadOnly } }
        .onChange(of: draft.title) { _, _ in actionError = nil }
    }

    // MARK: - Where the set fields sit

    /// **Three bounded places rather than one row that grows** ([[T-3237]] item 4).
    ///
    /// The complaint was not that the chips were ugly: it was that setting a field pushed the card
    /// around, because every set field joined one adaptive grid and that grid reflowed each time.
    /// Splitting it by *what the chip is about* gives three places whose shape is known before you
    /// fill anything in:
    ///
    /// 1. **The dates line.** Do and due, together, on their own line, as the owner asked —
    ///    at most two chips and never more, with the priority mark parked at its trailing end.
    /// 2. **The tags row.** Tags are off the chip row entirely. They are the one field whose count
    ///    is unbounded, which is exactly what made the single row grow, and they read as
    ///    identity rather than as schedule — so they get a row of their own and wrap inside it.
    /// 3. **The rest.** List, repeat, calendar and location, which are at most four and each at
    ///    most one.
    ///
    /// Each place draws nothing at all when it holds nothing, so an empty card is still an empty
    /// card.
    @ViewBuilder
    private var chipPlacement: some View {
        let dates = fields.filter { ($0 == .doDate || $0 == .dueDate) && isSet($0) }
        let showsPriority = fields.contains(.priority) && isSet(.priority)
        let rest = fields.filter(restCarriesChip)

        if !dates.isEmpty || showsPriority {
            HStack(alignment: .top, spacing: 6) {
                ForEach(dates) { chip($0) }
                Spacer(minLength: 0)
                if showsPriority { priorityChip }
            }
        }
        if fields.contains(.tags), isSet(.tags) { tagRow }
        if !rest.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(rest) { chip($0) }
            }
        }
    }

    /// Which fields the third place draws, which is every set field the first two did not take.
    ///
    /// **The estimate is the one conditional.** It rides the do-date chip (`Oct 19 · 30m`), so
    /// drawing it again here would state the duration twice. With no do date there is no chip for
    /// it to ride, and a duration that vanished the moment you cleared the date would be the
    /// appear-and-disappear behaviour the owner rejected — so it falls back to a chip of its own
    /// exactly then, and tapping it still opens the same estimate picker.
    private func restCarriesChip(_ field: CadenceCaptureField) -> Bool {
        switch field {
        case .doDate, .dueDate, .tags, .priority: return false
        case .estimate: return isSet(.estimate) && !isSet(.doDate)
        case .list, .repeatRule, .calendar, .location: return isSet(field)
        }
    }

    private func chip(_ field: CadenceCaptureField) -> some View {
        Button { open(field) } label: {
            Label {
                Text(chipTitle(field))
            } icon: {
                Image(systemName: chipSymbol(field)).foregroundStyle(chipTint(field))
            }
                .cadenceFont(.metadata)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .padding(.horizontal, 8)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .accessibilityLabel("\(field.title): \(chipTitle(field))")
        .accessibilityIdentifier("capture-chip-\(field.rawValue)")
        .disabled(isReadOnly)
    }

    /// **The bare tinted mark, no word** — the owner's answer to the open question, and already the
    /// app's priority language: `TaskPriorityMarkControl` is the shared `!` / `!!` / `!!!` tile that
    /// both inspectors and the schedule panel draw, tinted blue / amber / red by level. Reading it
    /// rather than drawing a glyph here is the same choice T-1278 made when it refused a second
    /// priority vocabulary. "Medium priority" in words is gone; the colour says it.
    ///
    /// The words survive where they are still needed: VoiceOver reads the label, which is the one
    /// reader a tint says nothing to.
    private var priorityChip: some View {
        Button { open(.priority) } label: {
            TaskPriorityMarkControl(priority: CadenceCaptureFieldInventory.priority(for: draft))
        }
        .accessibilityLabel("\(CadenceCaptureField.priority.title): \(CadenceCaptureFieldInventory.priority(for: draft).label)")
        .accessibilityIdentifier("capture-chip-priority")
        .disabled(isReadOnly)
    }

    /// Tags, in the place of their own the owner asked for.
    ///
    /// Drawn here rather than with `CadenceTagChip` because the card never holds `Tag` models: its
    /// host hands it `CadenceSchedulePanelChoice` values, and inventing a `Tag` to satisfy a view
    /// would be the larger near-copy. The construction is that chip's, though — the dot, the tint
    /// and the border carry the colour and the label stays on a `Theme` token, so a tag reads the
    /// same here as it does on a board card.
    private var tagRow: some View {
        let selected = options.tagChoices.filter { selectedTags.contains($0.id) }
        return Button { open(.tags) } label: {
            // 110, not the chip row's 130 and not something tighter: a tag name is shorter than a
            // chip's sentence but longer than the glyph-sized column a small minimum produces, and
            // at 72 the second column was narrow enough to truncate `leadership` to `leaders…`.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(selected) { tagPill($0) }
            }
        }
        .accessibilityLabel("\(CadenceCaptureField.tags.title): \(chipTitle(.tags))")
        .accessibilityIdentifier("capture-chip-tags")
        .disabled(isReadOnly)
    }

    private func tagPill(_ choice: CadenceSchedulePanelChoice) -> some View {
        HStack(spacing: 4) {
            Circle().fill(choice.color).frame(width: 6, height: 6)
            Text(choice.name).cadenceFont(.metadata).lineLimit(1)
        }
        // Hugs its name rather than filling the column, so a short tag is a short pill and the row
        // reads as tags rather than as a table of equal cells.
        .frame(minHeight: 28, alignment: .leading)
        .padding(.horizontal, 8)
        .background(choice.color.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                .strokeBorder(choice.color.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
    }

    private var kindBinding: Binding<CadenceScheduleDraftKind> {
        Binding(get: { draft.kind }, set: { kind in
            kindMemory.select(kind, draft: &draft)
            activeField = nil
            actionError = nil
        })
    }

    private var doDayText: String {
        draft.startDateKey.isEmpty ? draft.doRowLabel
            : DateFormatters.relativeDate(from: draft.startDateKey, withinDays: CadenceCaptureFieldInventory.relativeDateCutoffDays)
    }

    /// Whether the do date is today, which is the one day it gets its own glyph and hue.
    private var doDateIsToday: Bool {
        !draft.startDateKey.isEmpty && draft.startDateKey == DateFormatters.todayKey()
    }

    /// The glyph a chip draws, which is the field's own except on the day the do date is today.
    ///
    /// `CadenceBoardCardMetadata.doDateIcon` is read rather than respelled — `sun.max.fill` is the
    /// do date's glyph everywhere in this app and this is not the place to type it a tenth time.
    private func chipSymbol(_ field: CadenceCaptureField) -> String {
        field == .doDate && draft.kind == .task && doDateIsToday
            ? CadenceBoardCardMetadata.doDateIcon : field.symbol
    }

    /// **The glyph's colour, and only the glyph's** ([[T-3237]] item 3).
    ///
    /// Every hue here is one the app already owns: `Theme.red`, `Theme.amber`, the list's own
    /// `colorHex` through its choice, and `Theme.priorityColor` for the marks. Nothing new is
    /// invented, and a field with nothing to say in colour says it in `Theme.dim` rather than
    /// borrowing a meaning from a neighbour.
    ///
    /// **The do date is red by default and amber only on today**, which is the owner's call and is
    /// deliberately NOT `CadenceBoardCardMetadata`'s always-amber identity. The board card is a
    /// readout of a saved task; this card is the thing you are composing, where the do date is the
    /// commitment you are making and today is the one answer worth singling out.
    private func chipTint(_ field: CadenceCaptureField) -> Color {
        switch field {
        case .doDate:
            guard draft.kind == .task else { return Theme.dim }
            return doDateIsToday ? Theme.amber : Theme.red
        case .dueDate: return Theme.red
        case .list: return listChoices.first { $0.id == draft.listToken }?.color ?? Theme.dim
        case .priority: return Theme.priorityColor(CadenceCaptureFieldInventory.priority(for: draft))
        case .tags, .repeatRule, .estimate, .calendar, .location: return Theme.dim
        }
    }

    private func chipTitle(_ field: CadenceCaptureField) -> String {
        switch field {
        case .doDate:
            if draft.kind == .event { return draft.scheduleLabel }
            // **The duration rides this chip** ([[T-3237]] item 4): `Oct 19 · 30m`. It belongs to
            // the do date, it costs no row of its own, and one tap opens both.
            //
            // A timed task takes it through `doTimeLabel`, which has always appended the length
            // after the clock time. An UNTIMED one has no such label, so the estimate is appended
            // here — and only when it was set deliberately, since the draft carries a default
            // estimate that nobody chose and an all-day task has no length to state.
            guard draft.scheduledStartMin >= 0 else {
                guard isSet(.estimate) else { return doDayText }
                return "\(doDayText) · \(CadenceTaskPresentationSupport.estimateLabel(minutes: draft.estimateMinutes))"
            }
            return "\(doDayText) · \(draft.doTimeLabel)"
        case .dueDate:
            // No "Due" in front of it. The glyph beside it is the app's red due-date flag, and on
            // a line that sits the two dates side by side a word on one chip and not the other
            // reads as a difference between the fields rather than as a label.
            return draft.dueDateKey.isEmpty ? draft.dueRowLabel
                : DateFormatters.relativeDate(from: draft.dueDateKey, withinDays: CadenceCaptureFieldInventory.relativeDateCutoffDays)
        case .list:
            let list = listChoices.first { $0.id == draft.listToken }?.name ?? "Inbox"
            return draft.sectionName == TaskSectionDefaults.defaultName ? list : "\(list) · \(draft.sectionName)"
        case .tags:
            return options.tagChoices.filter { selectedTags.contains($0.id) }.map(\.name).joined(separator: ", ")
        case .repeatRule:
            return draft.captureRepeatSummary
        case .priority: return "\(CadenceCaptureFieldInventory.priority(for: draft).label) priority"
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
        guard !isReadOnly else { return }
        guard draft.hasCommittableTitle else {
            actionError = "Add a title first."
            return
        }
        guard canCommit else { return }
        actionError = actions.commit()
    }

    @ViewBuilder
    private func editor(_ field: CadenceCaptureField) -> some View {
        switch field {
        case .doDate, .dueDate:
            CadenceQuickDatePopover(
                selection: dateBinding(field), viewMonth: $dateMonth, isOpen: .constant(true),
                showsClear: false, inlineStyle: true,
                markedDay: field == .doDate && draft.kind == .task
                    ? DateFormatters.date(from: draft.dueDateKey) : nil
            )
            if field == .doDate {
                Toggle(draft.kind == .event ? "All day" : "Without time", isOn: Binding(
                    get: { draft.isAllDay },
                    set: { isAllDay in
                        if draft.kind == .task, !isAllDay { draft.addTime() }
                        else { draft.isAllDay = isAllDay }
                    }
                ))
                if !draft.isAllDay {
                    CadenceTimeRoller(minutes: Binding(get: { draft.startMin }, set: { draft.moveStart(toMinute: $0) })) {}
                }
                if draft.kind == .task {
                    // **Reachable from inside the card, not only from `...`** ([[T-3237]] item 4).
                    // The chip states the date and the length together, so the editor the chip
                    // opens has to offer both — otherwise the duration is readable where it is not
                    // settable. `.estimate` stays in the overflow menu as well: that is the way in
                    // for a task with no do date, whose chip does not exist yet.
                    Divider()
                    Text(CadenceCaptureField.estimate.title).cadenceFont(.controlLabel)
                    EstimatePickerPopoverContent(value: estimateBinding, unsetValueLabel: "Clear estimate", onClose: {})
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
                selection: Binding(get: { CadenceCaptureFieldInventory.priority(for: draft) }, set: { priority in
                    if !draft.subject.isEditing {
                        draft.title = CadenceTaskComposerSupport.titleClearingPriorityMarker(draft.title)
                    }
                    draft.priority = priority
                }),
                isPresented: editorIsOpen
            )
        case .estimate:
            EstimatePickerPopoverContent(
                value: estimateBinding, unsetValueLabel: "Clear estimate", onClose: { activeField = nil }
            )
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
                    Stepper(CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(draft.seriesEndCount), value: $draft.seriesEndCount, in: 1...999)
                }
            }
        }
        .onChange(of: draft.seriesEndMode) { _, mode in
            draft.seedSeriesEnd(for: mode)
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

    /// Spelled once, because the estimate is now editable from two places — its own popover and
    /// the do-date editor the chip opens.
    private var estimateBinding: Binding<Int> {
        Binding(get: { draft.estimateMinutes }, set: { value in
            if value == 0 { CadenceCaptureFieldInventory.clear(.estimate, draft: &draft) }
            else {
                draft.setEstimate(value)
                draft.estimateIsExplicit = true
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

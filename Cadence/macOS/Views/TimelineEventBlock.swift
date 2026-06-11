#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

// MARK: - Timeline Event Block

struct TimelineEventBlock: View {
    private enum ResizeEdge { case start, end }
    private enum PendingEventMutation {
        case move(startMin: Int)
        case resize(startMin: Int, durationMinutes: Int)
        case delete
    }

    let item: CalendarEventItem
    let layout: TimelineEventLayout
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedEventID: String?
    @Binding var selectedTaskID: UUID?

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    // Live drag/resize state — cleared when the item refreshes from iCal
    @State private var liveStartMin: Int? = nil
    @State private var liveDurationMinutes: Int? = nil
    @State private var dragGrabOffset: CGFloat = 0
    @State private var activeResizeEdge: ResizeEdge? = nil
    @State private var resizeOriginStartMin: Int? = nil
    @State private var resizeOriginEndMin: Int? = nil
    @State private var isHovered = false
    @State private var pendingMutation: PendingEventMutation?

    private let resizeHandleHeight: CGFloat = 8

    private var effectiveStartMin: Int  { liveStartMin      ?? item.startMin       }
    private var effectiveDuration: Int  { liveDurationMinutes ?? item.durationMinutes }

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: effectiveStartMin,
            durationMinutes: effectiveDuration,
            column: layout.column,
            totalColumns: layout.totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var isSelected: Bool { selectedEventID == item.id }

    var body: some View {
        eventBlockBody
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    hoveredEditableManager.beginHovering(id: "timeline-event-\(item.id)") {
                        selectedTaskID = nil
                        selectedEventID = item.id
                    } onDelete: {
                        deleteConfirmationManager.present(
                            title: "Delete Calendar Event?",
                            message: "This will permanently delete \"\(item.title)\" from your calendar."
                        ) {
                            requestEventMutation(.delete)
                        }
                    }
                } else {
                    hoveredEditableManager.endHovering(id: "timeline-event-\(item.id)")
                }
            }
            .onTapGesture {
                guard liveStartMin == nil else { return }   // ignore tap during drag
                selectedTaskID = nil
                selectedEventID = isSelected ? nil : item.id
            }
            // MARK: Move gesture — uses named canvas coordinate space so drag speed
            // is 1:1 with cursor even as the block repositions during the gesture.
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("timelineCanvas"))
                    .onChanged { value in
                        guard activeResizeEdge == nil else { return }
                        selectedEventID = nil
                        if liveStartMin == nil {
                            // Record where in the block the user grabbed it
                            dragGrabOffset = value.startLocation.y - metrics.yOffset(for: item.startMin)
                        }
                        let eventTopY = value.location.y - dragGrabOffset
                        liveStartMin = metrics.snappedMinute(fromY: max(0, eventTopY))
                    }
                    .onEnded { _ in
                        guard activeResizeEdge == nil else { return }
                        if let newStart = liveStartMin {
                            requestEventMutation(.move(startMin: newStart))
                            // Keep liveStartMin set until item refreshes from iCal (onChange clears it)
                        }
                        dragGrabOffset = 0
                    }
            )
            // MARK: Resize handles
            .overlay(alignment: .top)    { resizeHandle(edge: .start) }
            .overlay(alignment: .bottom) { resizeHandle(edge: .end)   }
            // MARK: Detail popover
            .popover(
                isPresented: Binding(
                    get: { isSelected },
                    set: { if !$0 && selectedEventID == item.id { selectedEventID = nil } }
                )
            ) {
                CalendarEventEditPopover(
                    item: item,
                    onSave: { title, startMin, duration, calendarID, scope in
                        if let range = item.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration) {
                            calendarManager.updateEvent(
                                item.ekEvent,
                                title: title,
                                startDate: range.start,
                                endDate: range.end,
                                calendarID: calendarID,
                                scope: scope
                            )
                        }
                        selectedEventID = nil
                    },
                    onDelete: { scope in
                        deleteConfirmationManager.present(
                            title: "Delete Calendar Event?",
                            message: "This will permanently delete \"\(item.title)\" from your calendar."
                        ) {
                            calendarManager.deleteEvent(item.ekEvent, scope: scope)
                            selectedEventID = nil
                        }
                    }
                )
            }
            .position(x: frame.centerX, y: frame.centerY)
            // Clear live state once the item refreshes from iCal
            .onChange(of: item.startMin) {
                liveStartMin = nil
                liveDurationMinutes = nil
                dragGrabOffset = 0
            }
            .confirmationDialog(
                "Change recurring event?",
                isPresented: Binding(
                    get: { pendingMutation != nil },
                    set: { if !$0 { cancelPendingEventMutation() } }
                ),
                titleVisibility: .visible
            ) {
                Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                    applyPendingEventMutation(scope: .thisOccurrence)
                }
                Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                    applyPendingEventMutation(scope: .futureOccurrences)
                }
                Button("Cancel", role: .cancel) {
                    cancelPendingEventMutation()
                }
            } message: {
                Text("Choose whether this calendar change applies only to this occurrence or to this and future events.")
            }
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay {
                let isEmphasized = activeResizeEdge == edge || isHovered || isSelected
                Capsule()
                    .fill(.white.opacity(isEmphasized ? 0.5 : 0.18))
                    .frame(width: min(18, max(10, frame.width - 18)), height: 2)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        beginResizeIfNeeded(edge: edge)
                        updateResize(edge: edge, localY: value.location.y)
                    }
                    .onEnded { value in
                        updateResize(edge: edge, localY: value.location.y)
                        endResize()
                    }
            )
    }

    private func beginResizeIfNeeded(edge: ResizeEdge) {
        guard activeResizeEdge == nil else { return }
        selectedEventID = nil
        activeResizeEdge = edge
        resizeOriginStartMin = effectiveStartMin
        resizeOriginEndMin   = effectiveStartMin + max(effectiveDuration, 5)
    }

    private func updateResize(edge: ResizeEdge, localY: CGFloat) {
        guard let originStart = resizeOriginStartMin,
              let originEnd   = resizeOriginEndMin else { return }
        let localYOffset: CGFloat
        switch edge {
        case .start: localYOffset = localY
        case .end:   localYOffset = max(0, frame.height - resizeHandleHeight) + localY
        }
        let snapped = metrics.snappedMinute(fromY: frame.y + localYOffset)
        switch edge {
        case .start:
            let nextStart = min(snapped, originEnd - 5)
            liveStartMin        = nextStart
            liveDurationMinutes = max(5, originEnd - nextStart)
        case .end:
            let nextEnd = max(snapped, originStart + 5)
            liveStartMin        = originStart
            liveDurationMinutes = max(5, nextEnd - originStart)
        }
    }

    private func endResize() {
        let finalStart    = liveStartMin        ?? effectiveStartMin
        let finalDuration = liveDurationMinutes ?? effectiveDuration
        requestEventMutation(.resize(startMin: finalStart, durationMinutes: finalDuration))
        // Keep live state until item refreshes (onChange clears it)
        activeResizeEdge    = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin   = nil
    }

    private func requestEventMutation(_ mutation: PendingEventMutation) {
        if item.isRecurringSeriesMember {
            pendingMutation = mutation
        } else {
            applyEventMutation(mutation, scope: .thisOccurrence)
        }
    }

    private func applyPendingEventMutation(scope: CalendarRecurrenceEditScope) {
        guard let pendingMutation else { return }
        self.pendingMutation = nil
        applyEventMutation(pendingMutation, scope: scope)
    }

    private func cancelPendingEventMutation() {
        pendingMutation = nil
        liveStartMin = nil
        liveDurationMinutes = nil
        dragGrabOffset = 0
        activeResizeEdge = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin = nil
    }

    private func applyEventMutation(_ mutation: PendingEventMutation, scope: CalendarRecurrenceEditScope) {
        switch mutation {
        case .move(let startMin):
            updateEventRange(item.eventDateRangeForMovedSegment(startMin: startMin), scope: scope)
        case .resize(let startMin, let durationMinutes):
            updateEventRange(
                item.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: durationMinutes),
                scope: scope
            )
        case .delete:
            deleteConfirmationManager.present(
                title: "Delete Calendar Event?",
                message: scope == .futureOccurrences
                    ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                    : "This will permanently delete \"\(item.title)\" from your calendar."
            ) {
                calendarManager.deleteEvent(item.ekEvent, scope: scope)
            }
        }
    }

    private func updateEventRange(_ range: (start: Date, end: Date)?, scope: CalendarRecurrenceEditScope) {
        guard let range else {
            cancelPendingEventMutation()
            return
        }
        calendarManager.updateEvent(
            item.ekEvent,
            title: item.title,
            startDate: range.start,
            endDate: range.end,
            scope: scope
        )
    }

    // MARK: - Block Body

    private var eventBlockBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            if frame.height >= 36 {
                Text(timeRangeLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if item.isRecurringSeriesMember {
                    Image(systemName: "repeat")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            if frame.height >= 54 && !item.calendarTitle.isEmpty {
                Text(item.calendarTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(item.calendarColor.opacity(CalendarEventVisualStyle.blockFillOpacity(isSelected: isSelected, isHovered: isHovered)))
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(TimelineHoverVisuals.hoverFill(tint: .white, isHovered: isHovered && !isSelected, opacity: 0.04))
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(.white.opacity(CalendarEventVisualStyle.blockHighlightOpacity(isSelected: isSelected, isHovered: isHovered)))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    TimelineHoverVisuals.borderColor(
                        tint: item.calendarColor,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        selectedOpacity: CalendarEventVisualStyle.chipBorderOpacity(isActive: true),
                        hoverOpacity: CalendarEventVisualStyle.chipBorderOpacity(),
                        idleOpacity: 0.12
                    ),
                    lineWidth: isHovered || isSelected ? 1.2 : 1
                )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(CalendarEventVisualStyle.blockAccentOpacity(isSelected: isSelected, isHovered: isHovered)))
                .frame(height: isSelected ? 2 : 1)
                .padding(.horizontal, 8)
        }
        .shadow(
            color: TimelineHoverVisuals.shadowColor(isActive: isHovered || isSelected),
            radius: TimelineHoverVisuals.shadowRadius(isActive: isHovered || isSelected, active: 12, idle: 8),
            x: 0,
            y: TimelineHoverVisuals.shadowY(isActive: isHovered || isSelected, active: 5, idle: 3)
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: effectiveStartMin,
                                 endMin: effectiveStartMin + effectiveDuration)
    }
}

// MARK: - Calendar Event Edit Popover

struct CalendarEventEditPopover: View {
    let item: CalendarEventItem
    let onSave: (String, Int, Int, String, CalendarRecurrenceEditScope) -> Void
    let onDelete: (CalendarRecurrenceEditScope) -> Void
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var title: String
    @State private var startMin: Int
    @State private var endMin: Int
    @State private var startText: String
    @State private var endText: String
    @State private var selectedCalendarID: String
    @State private var presentedEventNote: Note?
    @State private var pendingAction: PendingAction?

    private enum PendingAction {
        case save
        case delete
    }

    init(
        item: CalendarEventItem,
        onSave: @escaping (String, Int, Int, String, CalendarRecurrenceEditScope) -> Void,
        onDelete: @escaping (CalendarRecurrenceEditScope) -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        let s = item.startMin
        let e = item.startMin + item.durationMinutes
        _title = State(initialValue: item.title)
        _startMin = State(initialValue: s)
        _endMin   = State(initialValue: e)
        _startText = State(initialValue: TimeFormatters.timeString(from: s))
        _endText   = State(initialValue: TimeFormatters.timeString(from: e))
        _selectedCalendarID = State(initialValue: item.ekEvent.calendar.calendarIdentifier)
    }

    private var durationMinutes: Int { max(0, endMin - startMin) }
    private var eventNotes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var linkedEventNote: Note? {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        return EventNoteSupport.note(
            for: item.id,
            eventTitle: item.title,
            calendarID: item.ekEvent.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            in: eventNotes
        )
    }

    private var durationLabel: String {
        let mins = durationMinutes
        if mins <= 0 { return "–" }
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60; let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        editorContent
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .sheet(isPresented: Binding(
            get: { presentedEventNote != nil },
            set: { if !$0 { presentedEventNote = nil } }
        )) {
            if let presentedEventNote {
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: item.title, nativeEvent: item.ekEvent)
            }
        }
        .confirmationDialog(
            "Change recurring event?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                applyPendingAction(scope: .thisOccurrence)
            }
            Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                applyPendingAction(scope: .futureOccurrences)
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Choose whether this calendar change applies only to this occurrence or to this and future events.")
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                timeCard
                calendarCard
                linkedNoteCard
                actionButtons
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.calendarColor.opacity(0.2))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.calendarColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Event title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                calendarLabel
            }

            Spacer()

            Text(durationLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var calendarLabel: some View {
        if !item.calendarTitle.isEmpty || item.isRecurringSeriesMember {
            HStack(spacing: 5) {
                if !item.calendarTitle.isEmpty {
                    Circle()
                        .fill(item.calendarColor)
                        .frame(width: 7, height: 7)
                    Text(item.calendarTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                if item.isRecurringSeriesMember {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                    Text("Repeats")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var timeCard: some View {
        infoCard {
            timeFieldRow(label: "Start", icon: "clock", text: $startText) {
                if let parsed = parseTime(startText) { startMin = parsed }
                startText = TimeFormatters.timeString(from: startMin)
            }
            timeFieldRow(label: "End", icon: "clock.badge.checkmark", text: $endText) {
                if let parsed = parseTime(endText) { endMin = parsed }
                endText = TimeFormatters.timeString(from: endMin)
            }
        }
    }

    private var calendarCard: some View {
        infoCard {
            HStack(spacing: 10) {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 88, alignment: .leading)
                CadenceCalendarPickerButton(
                    calendars: calendarManager.writableCalendars,
                    selectedID: $selectedCalendarID
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var linkedNoteCard: some View {
        infoCard {
            HStack(alignment: .center, spacing: 10) {
                Label("Note", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 88, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(linkedEventNote?.displayTitle ?? "No linked note yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(linkedEventNote == nil ? Theme.dim : Theme.text)
                        .lineLimit(1)
                    Text(linkedEventNote == nil ? "Create a markdown note for this event." : "Open the note linked to this event.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(linkedEventNote == nil ? "Create" : "Open") {
                    openEventNote()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { requestAction(.save) } label: {
                Label("Save", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.cadencePlain)

            Button { requestAction(.delete) } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.cadencePlain)
        }
    }

    private func requestAction(_ action: PendingAction) {
        if item.isRecurringSeriesMember {
            pendingAction = action
        } else {
            applyAction(action, scope: .thisOccurrence)
        }
    }

    private func applyPendingAction(scope: CalendarRecurrenceEditScope) {
        guard let pendingAction else { return }
        self.pendingAction = nil
        applyAction(pendingAction, scope: scope)
    }

    private func applyAction(_ action: PendingAction, scope: CalendarRecurrenceEditScope) {
        switch action {
        case .save:
            onSave(title, startMin, durationMinutes, selectedCalendarID, scope)
        case .delete:
            onDelete(scope)
        }
    }

    @ViewBuilder
    private func timeFieldRow(label: String, icon: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 88, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .onSubmit(onCommit)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(Theme.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    /// Parses a time string like "4:55 PM", "16:55", "4 PM" → minutes from midnight.
    private func parseTime(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let isPM = s.contains("pm")
        let isAM = s.contains("am")
        let digits = s.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces)
        let parts = digits.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let h = parts.first ?? nil else { return nil }
        let m = parts.count > 1 ? (parts[1] ?? 0) : 0
        var hour = h
        if isPM && hour != 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard hour >= 0, hour < 24, m >= 0, m < 60 else { return nil }
        return hour * 60 + m
    }

    private func openEventNote() {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        presentedEventNote = EventNoteSupport.noteForEditing(
            calendarEventID: item.id,
            eventTitle: item.title,
            calendarID: item.ekEvent.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            nativeNotes: item.ekEvent.notes,
            notes: eventNotes
        ) { modelContext.insert($0) }
    }
}
#endif

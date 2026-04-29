#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

// MARK: - Timeline Event Block

struct TimelineEventBlock: View {
    private enum ResizeEdge { case start, end }

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
                            calendarManager.deleteEvent(item.ekEvent)
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
                            let dateKey = DateFormatters.dateKey(from: item.ekEvent.startDate)
                            calendarManager.updateEvent(item.ekEvent, title: item.title,
                                                        startMin: newStart,
                                                        durationMinutes: item.durationMinutes,
                                                        dateKey: dateKey)
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
                    onSave: { title, startMin, duration, calendarID, notes in
                        let dateKey = DateFormatters.dateKey(from: item.ekEvent.startDate)
                        calendarManager.updateEvent(item.ekEvent, title: title,
                                                    startMin: startMin,
                                                    durationMinutes: duration,
                                                    dateKey: dateKey,
                                                    calendarID: calendarID,
                                                    notes: notes)
                        selectedEventID = nil
                    },
                    onDelete: {
                        deleteConfirmationManager.present(
                            title: "Delete Calendar Event?",
                            message: "This will permanently delete \"\(item.title)\" from your calendar."
                        ) {
                            calendarManager.deleteEvent(item.ekEvent)
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
        let dateKey = DateFormatters.dateKey(from: item.ekEvent.startDate)
        calendarManager.updateEvent(item.ekEvent, title: item.title,
                                    startMin: finalStart,
                                    durationMinutes: finalDuration,
                                    dateKey: dateKey)
        // Keep live state until item refreshes (onChange clears it)
        activeResizeEdge    = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin   = nil
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
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
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
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(item.calendarColor.opacity(isSelected ? 0.52 : 0.36))
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(.white.opacity(isSelected ? 0.05 : 0.025))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(.white.opacity(isSelected ? 0.22 : 0.07), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(isSelected ? 0.55 : 0.18))
                .frame(height: isSelected ? 2 : 1)
                .padding(.horizontal, 8)
        }
        .shadow(
            color: isSelected ? CalendarVisualStyle.selectedCardShadow : CalendarVisualStyle.cardShadow,
            radius: isSelected ? 12 : 8,
            x: 0,
            y: isSelected ? 5 : 3
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
    let onSave: (String, Int, Int, String, String) -> Void
    let onDelete: () -> Void
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var title: String
    @State private var startMin: Int
    @State private var endMin: Int
    @State private var startText: String
    @State private var endText: String
    @State private var selectedCalendarID: String
    @State private var notes: String
    @State private var presentedEventNote: Note?

    init(item: CalendarEventItem, onSave: @escaping (String, Int, Int, String, String) -> Void, onDelete: @escaping () -> Void) {
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
        _notes = State(initialValue: item.ekEvent.notes ?? "")
    }

    private var durationMinutes: Int { max(0, endMin - startMin) }
    private var eventNotes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var linkedEventNote: Note? {
        EventNoteSupport.note(for: item.id, in: eventNotes)
    }

    private var durationLabel: String {
        let mins = durationMinutes
        if mins <= 0 { return "–" }
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60; let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
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
                        if !item.calendarTitle.isEmpty {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(item.calendarColor)
                                    .frame(width: 7, height: 7)
                                Text(item.calendarTitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
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

                // Time card
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

                infoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 96)
                            .padding(8)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Actions
                HStack(spacing: 10) {
                    Button { onSave(title, startMin, durationMinutes, selectedCalendarID, notes) } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.cadencePlain)

                    Button { onDelete() } label: {
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
            .padding(18)
        }
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
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: item.title)
            }
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
            notes: eventNotes
        ) { modelContext.insert($0) }
    }
}
#endif

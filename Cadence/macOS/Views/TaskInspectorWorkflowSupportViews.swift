#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask

    var body: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                Button {
                    task.recurrenceRule = rule
                } label: {
                    Label(rule.label, systemImage: rule.systemImage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: task.recurrenceRule.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(task.isRecurring ? Theme.blue : Theme.dim)
                Text(task.recurrenceRule.shortLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.isRecurring ? Theme.text : Theme.dim)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.surfaceElevated.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }
}

struct TaskInspectorDependencyControl: View {
    @Bindable var task: AppTask
    let allTasks: [AppTask]

    @State private var showPicker = false
    @State private var searchQuery = ""

    private var selectedDependencies: [AppTask] {
        let ids = Set(task.dependencyTaskIDs)
        return allTasks.filter { ids.contains($0.id) }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var candidates: [AppTask] {
        let selectedIDs = Set(task.dependencyTaskIDs)
        return scopedTasks
            .filter { $0.id != task.id && !selectedIDs.contains($0.id) }
            .filter {
                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return $0.title.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var scopedTasks: [AppTask] {
        if let area = task.area {
            return allTasks.filter { $0.area?.id == area.id }
        }
        if let project = task.project {
            return allTasks.filter { $0.project?.id == project.id }
        }
        return allTasks.filter { $0.area == nil && $0.project == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedDependencies.isEmpty {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add dependency")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            } else {
                FlowLayout(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(selectedDependencies) { dependency in
                        HStack(spacing: 6) {
                            Image(systemName: dependency.isDone ? "checkmark.circle.fill" : "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(dependency.isDone ? Theme.green : Theme.amber)
                            Text(dependency.title.isEmpty ? "Untitled" : dependency.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Button {
                                var updated = task.dependencyTaskIDs
                                updated.removeAll { $0 == dependency.id }
                                task.dependencyTaskIDs = updated
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.dim)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceElevated.opacity(0.85))
                        .clipShape(Capsule())
                    }
                }

                Button {
                    showPicker = true
                } label: {
                    Text("Add another")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .popover(isPresented: $showPicker, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Blocked By")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)

                TextField("Search tasks...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(candidates) { candidate in
                            Button {
                                var updated = task.dependencyTaskIDs
                                updated.append(candidate.id)
                                task.dependencyTaskIDs = updated
                                searchQuery = ""
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: candidate.containerColor))
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if !candidate.containerName.isEmpty {
                                            Text(candidate.containerName)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.dim)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceElevated.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 300, height: 280)
            .background(Theme.surface)
        }
    }
}

struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 280
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > containerWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            maxWidth = max(maxWidth, currentX + size.width)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct TaskInspectorEventAttachmentControl: View {
    @Bindable var task: AppTask
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EventNote.updatedAt, order: .reverse) private var eventNotes: [EventNote]

    @State private var showPicker = false
    @State private var searchQuery = ""
    @State private var presentedEventNote: EventNote?

    private var linkedEvent: EKEvent? {
        calendarManager.event(withIdentifier: task.calendarEventID)
    }

    private var linkedEventNote: EventNote? {
        EventNoteSupport.note(for: task.calendarEventID, in: eventNotes)
    }

    private var results: [EKEvent] {
        calendarManager.searchEvents(matching: searchQuery)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let linkedEvent {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkedEvent.title?.isEmpty == false ? linkedEvent.title! : "Linked event")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(linkedEventSummary(linkedEvent))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }

                    Button(linkedEventNote == nil ? "Create linked note" : "Open linked note") {
                        openEventNote(for: linkedEvent)
                    }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                }

                Spacer(minLength: 8)

                Button("Change") {
                    showPicker = true
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.blue)

                Button("Detach") {
                    task.calendarEventID = ""
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
            } else {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Attach existing event")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(calendarManager.isAuthorized ? Theme.blue : Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .disabled(!calendarManager.isAuthorized)

                if !calendarManager.isAuthorized {
                    Spacer(minLength: 8)
                    Text("Calendar access needed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { presentedEventNote != nil },
            set: { if !$0 { presentedEventNote = nil } }
        )) {
            if let linkedEvent = linkedEvent, let presentedEventNote {
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: linkedEvent.title ?? "Linked Event")
            }
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    TextField("Search calendar events...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Theme.borderSubtle)

                if results.isEmpty {
                    Text("No matching events")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(results.prefix(10), id: \.eventIdentifier) { event in
                                Button {
                                    attach(event)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title?.isEmpty == false ? event.title! : "Untitled Event")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(linkedEventSummary(event))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.dim)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 260)
                }
            }
            .frame(width: 280)
            .background(Theme.surface)
        }
    }

    private func attach(_ event: EKEvent) {
        task.calendarEventID = event.eventIdentifier
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task.title = event.title ?? ""
        }
        calendarManager.syncTaskFromLinkedEvent(task)
        searchQuery = ""
        showPicker = false
    }

    private func linkedEventSummary(_ event: EKEvent) -> String {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        let startComps = Calendar.current.dateComponents([.hour, .minute], from: start)
        let endComps = Calendar.current.dateComponents([.hour, .minute], from: end)
        let startMin = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
        let endMin = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)
        return "\(DateFormatters.shortDate.string(from: start)) • \(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))"
    }

    private func openEventNote(for event: EKEvent) {
        let eventID = event.eventIdentifier ?? task.calendarEventID
        presentedEventNote = EventNoteSupport.noteForEditing(
            calendarEventID: eventID,
            eventTitle: event.title ?? "Linked Event",
            notes: eventNotes
        ) { modelContext.insert($0) }
    }
}
#endif

#if os(macOS)
import SwiftData
import SwiftUI

struct CalendarBoardEventCard: View {
    let item: CalendarBoardEventDisplayItem

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var showPopover = false
    @State private var isHovered = false
    @State private var actionFailureNotice: String?

    private var tint: Color {
        item.calendarColor
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            label
        }
        .buttonStyle(.cadencePlain)
        .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        // T-1843: the card is its own popover's `.rect(.bounds)` anchor, so a test reading where
        // that popover lands needs the card's box and the content inside it. Same `.contain`
        // reasoning, and the same pair of modifiers, as `CalendarBoardBundleCard` above.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CadenceAccessibilityIdentifiers.boardEventCard(title: item.title))
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            let editItem = item.editItem
            CalendarEventEditPopover(
                item: editItem,
                onSave: { request, scope in
                    // Both refusals used to close the popover: the unformable range silently, and
                    // the rejected write behind a global alert with nothing to retype into. The
                    // range branch has no cause to name — EventKit was never asked — so it passes
                    // `nil`, the way `iOSCalendarQuickCreateSheet` does for an unparseable date key.
                    // The range is the whole event's, from the shared panel's draft ([[T-3171]]).
                    guard let range = request.range else {
                        calendarManager.report(
                            .refused(notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)),
                            into: $actionFailureNotice
                        )
                        return
                    }
                    let failure = calendarManager.updateEvent(
                        item.ekEvent,
                        title: request.title,
                        startDate: range.start,
                        endDate: range.end,
                        calendarID: request.calendarID,
                        notes: request.notes,
                        scope: scope,
                        isAllDay: request.isAllDay,
                        location: request.location
                    )
                    calendarManager.report(
                        CadenceCalendarEventEditingSupport.saveOutcome(for: failure),
                        into: $actionFailureNotice
                    ) { showPopover = false }
                },
                onDelete: { scope in
                    deleteConfirmationManager.presentRefusable(
                        title: "Delete Calendar Event?",
                        message: scope == .futureOccurrences
                            ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                            : "This will permanently delete \"\(item.title)\" from your calendar."
                    ) {
                        // There is no draft to keep here — nothing was typed — and by the time
                        // this runs there is no popover either: unlike `TimelineEventBlock`, this
                        // site never clears `showPopover` itself, so it is the one that genuinely
                        // relies on the overlay's Delete button being a click outside a still-open
                        // `.popover(isPresented: $showPopover)` (confirmed: this modifier carries
                        // no `.interactiveDismissDisabled()`, so the platform's default
                        // outside-click dismissal is live). T-768 stopped there and left the
                        // refusal on the window-wide alert. What is still on screen is the
                        // confirmation overlay, so T-919 puts the typed reason in it and closes
                        // the popover state only on a delete that happened.
                        let outcome = calendarManager.deleteOutcome(
                            for: calendarManager.deleteEvent(item.ekEvent, scope: scope)
                        )
                        if outcome == .deleted { showPopover = false }
                        return outcome
                    }
                },
                actionFailureNotice: $actionFailureNotice
            )
        }
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isAllDay ? "calendar" : "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    CadenceBoardMetadataChip(
                        title: subtitle,
                        systemImage: item.isAllDay ? "sun.max" : "clock",
                        tint: tint,
                        cardCornerRadius: kanbanCardCornerRadius
                    )
                    if item.isRecurringSeriesMember {
                        CadenceBoardMetadataChip(
                            title: "Repeats",
                            systemImage: "repeat",
                            tint: tint,
                            cardCornerRadius: kanbanCardCornerRadius
                        )
                    }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .strokeBorder(
                    tint.opacity(CalendarEventVisualStyle.borderOpacity(isSelected: showPopover, isHovered: isHovered)),
                    lineWidth: isHovered || showPopover ? 1.25 : 1
                )
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(CalendarEventVisualStyle.surfaceOpacity(isActive: isHovered || showPopover)))
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(tint.opacity(CalendarEventVisualStyle.tintOpacity(isSelected: showPopover, isHovered: isHovered)))
        }
    }

    private var subtitle: String {
        if item.isAllDay { return "All day" }
        return TimeFormatters.timeRange(startMin: item.startMin, endMin: item.startMin + max(item.durationMinutes, 5))
    }
}

// The event/bundle chip is `CadenceBoardMetadataChip` in
// `Shared/Components/CadenceBoardMetadataChip.swift`. `CalendarBoardMetadataChip` was declared
// here beside a `private iOSCalendarBoardMetadataChip` in `Cadence/iOS/iOSBoardCards.swift` that
// said "Matches macOS's `CalendarBoardMetadataChip`" and had no way to keep matching it.

#endif

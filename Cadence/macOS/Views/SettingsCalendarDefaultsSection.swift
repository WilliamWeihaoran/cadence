#if os(macOS)
import SwiftUI

/// Settings → Navigation's calendar rows: the Calendar page's view and its timeline density
/// ([[T-8737]], owner decision 2026-10-31 — these are app-wide defaults).
///
/// iOS Settings → Navigation → Defaults has offered both since T-7074 folded "Calendar style" into
/// "Calendar view"; the Mac had neither, and its Calendar page forgot its view and style at every
/// launch. The two rows here write the same keys as iOS's and as the Calendar page's own toolbar
/// (`CadenceCalendarPreferences`, `CadenceCalendarZoom.storageKey`), so what is picked here is what
/// the page opens on, and what the page was last left on is what this reads.
struct SettingsCalendarDefaultsSection: View {
    @AppStorage(CadenceCalendarPreferences.viewModeKey) private var viewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage(CadenceCalendarPreferences.presentationKey) private var presentationRaw = CadenceCalendarPresentation.timeline.rawValue
    @AppStorage(CadenceCalendarZoom.storageKey) private var zoom = CadenceCalendarZoom.defaultZoom
    @State private var openPicker: DefaultsPicker?

    private enum DefaultsPicker: Hashable {
        case calendarView
        case timelineDensity
    }

    private var viewMode: CadenceCalendarViewMode {
        CadenceCalendarViewMode(rawValue: viewModeRaw) ?? .week
    }

    private var presentation: CadenceCalendarPresentation {
        CadenceCalendarPresentation(rawValue: presentationRaw) ?? .timeline
    }

    var body: some View {
        CadenceFieldSection(title: "Calendar Opening") {
            calendarViewRow
            timelineDensityRow
        }
    }

    private var calendarViewRow: some View {
        CadenceFieldRow(label: "Calendar view", systemImage: "calendar") {
            CadenceChoiceValueButton(
                title: CadenceCalendarPageView.settingsTitle(presentation: presentation, viewMode: viewMode),
                minHeight: CadenceSettingsRowMetrics.rowHeight
            ) {
                openPicker = .calendarView
            }
            .popover(isPresented: isPresented(.calendarView)) {
                CadenceChoicePopoverList(
                    rows: CadenceCalendarPageView.allCases.map { choice in
                        CadenceChoiceRow(
                            value: choice,
                            title: choice.title,
                            subtitle: choice.settingsSubtitle,
                            systemImage: choice.systemImage,
                            color: Theme.purple
                        )
                    },
                    selection: calendarViewSelection,
                    isPresented: isPresented(.calendarView)
                )
            }
        }
    }

    /// The stored pair as the one choice, written back the way the toolbar writes it. Only the
    /// key that changes is written, so picking Board keeps the timeline range to return to.
    private var calendarViewSelection: Binding<CadenceCalendarPageView> {
        Binding(
            get: { CadenceCalendarPageView(presentation: presentation, viewMode: viewMode) ?? .week },
            set: { choice in
                var newPresentation = presentation
                var newViewMode = viewMode
                choice.apply(presentation: &newPresentation, viewMode: &newViewMode)
                if newViewMode != viewMode { viewModeRaw = newViewMode.rawValue }
                if newPresentation != presentation { presentationRaw = newPresentation.rawValue }
            }
        )
    }

    /// The phone's three presets over the same `Double`. A pinched zoom between two presets reads
    /// as Custom with no row checked, as it does on iOS, rather than being rounded here; the Mac
    /// grid itself shows the nearest step (`CadenceCalendarZoom.timelineLevel(for:)`).
    private var timelineDensityRow: some View {
        CadenceFieldRow(label: "Timeline density", systemImage: "arrow.up.and.down") {
            CadenceChoiceValueButton(
                title: CadenceCalendarZoom.densityTitle(for: zoom),
                minHeight: CadenceSettingsRowMetrics.rowHeight
            ) {
                openPicker = .timelineDensity
            }
            .popover(isPresented: isPresented(.timelineDensity)) {
                CadenceChoicePopoverList(
                    rows: CadenceCalendarZoom.densityPresets.map { preset in
                        CadenceChoiceRow(
                            value: preset.zoom,
                            title: preset.title,
                            systemImage: "arrow.up.and.down",
                            color: Theme.amber
                        )
                    },
                    selection: $zoom,
                    isPresented: isPresented(.timelineDensity)
                )
            }
        }
    }

    private func isPresented(_ picker: DefaultsPicker) -> Binding<Bool> {
        Binding(
            get: { openPicker == picker },
            set: { if !$0, openPicker == picker { openPicker = nil } }
        )
    }
}
#endif

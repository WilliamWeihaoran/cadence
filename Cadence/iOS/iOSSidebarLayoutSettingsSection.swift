#if os(iOS)
import SwiftData
import SwiftUI

/// Settings → Navigation on iPhone and iPad: which sidebar rows appear, and in what order.
///
/// **The same layout macOS's Settings → Sidebar edits, because it is the same record.** T-1274
/// made the layout a synced `SidebarLayoutPreference` rather than a device-local preference, on the
/// owner's answer to the one open question — *across devices* — so a row hidden here is hidden on
/// the Mac. Filed under Navigation rather than a category of its own: iOS has no "Sidebar"
/// category, and adding one for two controls would put a heading over a card that already says what
/// it is.
///
/// **Not `.onMove`**, for the reason the contexts card records: that needs a `List` in edit mode
/// and this is a card of rows. A one-step move through `CadenceOrderReassignment.neighbourStep` is
/// the same primitive macOS's drag calls, so the two platforms renumber identically.
///
/// It honours the *whole* customisable set, Focus included, which on this platform means the footer
/// glyph — the row that hides it is the only control for it on iPhone, where there is no Mac to
/// reach for.
struct iOSSidebarLayoutSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference
    /// Set when a change was refused — by the store, or by the one-visible-row floor.
    @State private var failureNotice: String?

    private var layout: CadenceSidebarLayoutPreferenceStore.Layout {
        CadenceSidebarLayoutPreferenceStore.layout(from: sidebarLayoutPreferences)
    }

    private var rows: [CadenceFeatureDestination] {
        CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: layout)
    }

    var body: some View {
        let rows = rows
        let hidden = layout.hidden

        return VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Sidebar Rows")

            iOSSettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, destination in
                        row(destination, isVisible: !hidden.contains(destination), in: rows)

                        if index < rows.count - 1 {
                            iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                        }
                    }
                }
            }

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
        }
    }

    private func row(
        _ destination: CadenceFeatureDestination,
        isVisible: Bool,
        in rows: [CadenceFeatureDestination]
    ) -> some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: destination.systemImage,
                color: Color(hex: CadenceSidebarTint.hex(for: destination, overridesRaw: sidebarTabColorsRaw)),
                size: 34,
                iconSize: 16
            )

            Text(CadenceSidebarLayout.rowTitle(for: destination))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer(minLength: 0)

            // The label is hidden from the layout and kept as the control's accessible name, the
            // shape every settings toggle in the app wears.
            Toggle(
                "Show \(CadenceSidebarLayout.rowTitle(for: destination))",
                isOn: Binding(
                    get: { isVisible },
                    set: { setVisibility($0, for: destination) }
                )
            )
            .labelsHidden()
            .tint(Theme.blue)
        }
        .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
        .contextMenu {
            Button {
                move(destination, by: -1, in: rows)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(rows.first == destination)

            Button {
                move(destination, by: 1, in: rows)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(rows.last == destination)
        }
    }

    private func setVisibility(_ visible: Bool, for destination: CadenceFeatureDestination) {
        let layout = layout
        guard let hidden = CadenceSidebarLayoutPreferenceStore.hidden(
            setting: destination,
            visible: visible,
            in: layout
        ) else {
            failureNotice = CadenceSidebarLayoutPreferenceStore.lastVisibleRowNotice
            return
        }
        write(.init(order: layout.order, hidden: hidden))
    }

    private func move(_ destination: CadenceFeatureDestination, by offset: Int, in rows: [CadenceFeatureDestination]) {
        let layout = layout
        guard let step = CadenceOrderReassignment.neighbourStep(
            moving: destination,
            by: offset,
            within: rows
        ),
        let order = CadenceSidebarLayoutPreferenceStore.order(
            in: layout,
            moving: step.dragged,
            before: step.target
        ) else { return }
        write(.init(order: order, hidden: layout.hidden))
    }

    /// The one commit path for both controls. Not `try?`: the first edit inserts the synced row,
    /// and a row that stays where you put it is a success claim.
    private func write(_ layout: CadenceSidebarLayoutPreferenceStore.Layout) {
        do {
            try CadenceSidebarLayoutPreferenceStore.write(
                layout,
                records: sidebarLayoutPreferences,
                in: modelContext
            )
            failureNotice = nil
        } catch {
            failureNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }
}
#endif

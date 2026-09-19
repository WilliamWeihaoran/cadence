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
/// reach for. **What Focus's row does not get is the move menu** (T-1292): the footer draws its two
/// glyphs from `CadenceSidebarLayout.footerGlyphDestinations` in that list's own order, so the
/// stored order has never reached it. That is `isOrderable`, the predicate T-1287 added for the
/// Mac's drag handle, asked here of a menu instead.
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

    /// The subset of `rows` the stored order actually places, in the same sequence — the list a
    /// one-step move is measured in (T-1292).
    ///
    /// The footer glyphs are not in it, so Focus is neither a destination for a step nor the owner
    /// of one, and the last labelled nav row is genuinely last.
    private var orderableRows: [CadenceFeatureDestination] {
        rows.filter { CadenceSidebarLayout.isOrderable($0) }
    }

    var body: some View {
        let rows = rows
        let orderable = orderableRows
        let hidden = layout.hidden

        return VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Sidebar Rows")

            iOSSettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, destination in
                        row(destination, isVisible: !hidden.contains(destination), in: orderable)

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

    /// A row, and the move menu only where a move exists (T-1292).
    ///
    /// **Branched rather than disabled, which is macOS's answer to the same question (T-1287).**
    /// Focus is drawn by the sidebar footer from `CadenceSidebarLayout.footerGlyphDestinations`,
    /// in that list's own order, so the stored order has never reached it; two menu items that can
    /// never become enabled are a promise the row cannot keep, and the Mac's Settings row answers
    /// it by dropping the drag handle rather than greying it. A context menu costs no layout until
    /// it is summoned, so the absent one is the whole cost.
    @ViewBuilder
    private func row(
        _ destination: CadenceFeatureDestination,
        isVisible: Bool,
        in orderable: [CadenceFeatureDestination]
    ) -> some View {
        if CadenceSidebarLayout.isOrderable(destination) {
            rowContent(destination, isVisible: isVisible)
                .contextMenu {
                    Button {
                        move(destination, by: -1, in: orderable)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(!canMove(destination, by: -1, in: orderable))

                    Button {
                        move(destination, by: 1, in: orderable)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(!canMove(destination, by: 1, in: orderable))
                }
        } else {
            rowContent(destination, isVisible: isVisible)
        }
    }

    /// The row itself — icon, title, visibility toggle. Shared by both branches above so the two
    /// spellings cannot drift.
    private func rowContent(
        _ destination: CadenceFeatureDestination,
        isVisible: Bool
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
    }

    /// Whether a one-step move exists — **asked of the same primitive that performs it**, which is
    /// the shape `iOSSettingsView.canMoveContext(_:by:)` already uses (T-1292).
    ///
    /// The old spelling was `rows.first == destination` / `rows.last == destination`, a second copy
    /// of the rule over the *whole* customisable list, and the copy was wrong at one end: a step
    /// down means *move the row below me above me*, so Move Down on the last labelled nav row named
    /// Focus, which the footer draws in its own order. The item was enabled, the sidebar redrew
    /// identically, and the store took a new `orderRaw` and a fresh `updatedAt` to every device.
    private func canMove(
        _ destination: CadenceFeatureDestination,
        by offset: Int,
        in orderable: [CadenceFeatureDestination]
    ) -> Bool {
        CadenceOrderReassignment.neighbourStep(
            moving: destination,
            by: offset,
            within: orderable
        ) != nil
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

    /// Moves one step **within the orderable rows**. The write itself still renumbers the whole
    /// customisable list — `order(in:moving:before:)` does that — so the footer glyph keeps its
    /// place in the stored string rather than being dropped out of it.
    private func move(
        _ destination: CadenceFeatureDestination,
        by offset: Int,
        in orderable: [CadenceFeatureDestination]
    ) {
        let layout = layout
        guard let step = CadenceOrderReassignment.neighbourStep(
            moving: destination,
            by: offset,
            within: orderable
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

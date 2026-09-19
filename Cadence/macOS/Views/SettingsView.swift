#if os(macOS)
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(AppleAccountManager.self) private var appleAccountManager
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NotificationManager.notificationsEnabledDefaultsKey) private var notificationsEnabled = false
    @AppStorage(CadencePreferenceKeys.listDetailDefaultPage) private var listDetailDefaultPage = ListDetailPage.tasks.rawValue
    /// The device-local values the synced layout replaced (T-1274), read only as the fallback for
    /// a store with no synced row yet. The first edit here writes the whole resolved layout into
    /// the row, so a Mac customised before the change carries its layout across rather than
    /// resetting to the declared one.
    @AppStorage(CadencePreferenceKeys.sidebarHiddenTabs) private var sidebarHiddenTabsRaw = ""
    @AppStorage(CadencePreferenceKeys.sidebarTabOrder) private var sidebarTabOrderRaw = ""
    /// Still device-local: T-1274 synced the rows and their order, which is what the owner asked
    /// for. Colour is a separate preference and stayed where it was.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = ""
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]
    @State private var selectedCategory: SettingsCategory = .navigation
    @State private var pendingDeleteArea: Area?
    @State private var pendingDeleteProject: Project?
    @State private var pendingDeleteContext: Context?
    /// Set when a list cascade failed (T-291). It sits under the detail header rather than in the
    /// dialog, because the `confirmationDialog` has already closed by the time the delete runs and
    /// the section it was about is what the user is still looking at.
    @State private var deleteFailureNotice: String?
    /// Set when a context reorder was refused by the store. See `moveContext(_:before:)` — the
    /// rows have already been put back by then, so the pane and this sentence agree.
    @State private var contextOrderFailureNotice: String?
    /// Set when a sidebar layout edit was refused — by the store, or by the one-visible-row floor.
    /// It sits under the detail header for the same reason the two above do: the pane it is about
    /// is what the user is still looking at.
    @State private var sidebarLayoutNotice: String?
    @State private var showCreateContext = false
    @State private var editingSidebarTab: SidebarStaticDestination?
    @State private var aiAPIKeyDraft = ""
    /// The CloudKit account check behind Settings → iCloud Sync, shared with iOS's own sync
    /// section rather than re-rolled here — see `CadenceCloudAccountProbe`.
    @State private var cloudAccount = CadenceCloudAccountProbe()

    var body: some View {
        HStack(spacing: 0) {
            SettingsRail(selectedCategory: $selectedCategory)

            // The rail's edge, on the shared hairline (T-286). It was a two-line
            // `Divider().background(Theme.borderSubtle)` — the palette colour painted *under* the
            // system separator, so the rule is neither — and the two-line spelling is why the sweep
            // written for the one-line form never saw it.
            CadenceRowDivider(axis: .vertical)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHeader
                    if let deleteFailureNotice {
                        CadenceInlineFailureNotice(text: deleteFailureNotice)
                    }
                    if let contextOrderFailureNotice {
                        CadenceInlineFailureNotice(text: contextOrderFailureNotice)
                    }
                    if let sidebarLayoutNotice {
                        CadenceInlineFailureNotice(text: sidebarLayoutNotice)
                    }
                    selectedSectionContent
                }
                .frame(maxWidth: 1040, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .cadenceSoftPageBounce()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.settings")
        .confirmationDialog(
            "Delete Area?",
            isPresented: Binding(
                get: { pendingDeleteArea != nil },
                set: { if !$0 { pendingDeleteArea = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Area", role: .destructive) {
                if let area = pendingDeleteArea { deleteArea(area) }
                pendingDeleteArea = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteArea = nil }
        } message: {
            Text(CadenceListDeletionKind.area.cascadeSentence)
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = pendingDeleteProject { deleteProject(project) }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
        } message: {
            Text(CadenceListDeletionKind.project.cascadeSentence)
        }
        .confirmationDialog(
            "Delete Context?",
            isPresented: Binding(
                get: { pendingDeleteContext != nil },
                set: { if !$0 { pendingDeleteContext = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Context", role: .destructive) {
                if let context = pendingDeleteContext { deleteContext(context) }
                pendingDeleteContext = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteContext = nil }
        } message: {
            Text(CadenceListDeletionKind.context.cascadeSentence)
        }
        .onAppear { cloudAccount.refreshIfNeeded() }
        // T-361: the toggle used to write `UserDefaults` and stop, leaving pending notifications
        // alive until the next scene-phase sweep. Both directions are handled in one shared place.
        .onChange(of: notificationsEnabled) { _, enabled in
            HabitNotificationReconcileSupport.notificationsEnabledDidChange(to: enabled, in: modelContext)
        }
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $editingSidebarTab) { destination in
            SidebarTabEditorSheet(
                destination: destination,
                tintHex: Binding(
                    get: { destination.resolvedColorHex(from: sidebarTabColorsRaw) },
                    set: { setTabColor(destination, hex: $0) }
                ),
                isVisible: Binding(
                    get: { !hiddenTabs.contains(destination) },
                    set: { newValue in
                        let isCurrentlyVisible = !hiddenTabs.contains(destination)
                        if newValue != isCurrentlyVisible {
                            toggleTab(destination)
                        }
                    }
                )
            )
        }
    }

    /// The category's name and nothing else.
    ///
    /// This was a nine-case `switch` feeding a `SettingsStatusBadge` into the header's trailing
    /// slot, and every case restated the first line of the card directly underneath — `Connected`
    /// over a Calendar card reading Connected, `Key saved` over an AI card reading Key saved,
    /// `3 backups` over a Data Safety card listing three backups. iOS deleted the same slot in
    /// `775833d`; T-20 removed it here. The switch went with the slot rather than being left
    /// computing values nothing drew.
    private var detailHeader: some View {
        SettingsDetailHeader(category: selectedCategory)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedCategory {
        case .account:
            SettingsAccountSection(
                appleAccountManager: appleAccountManager,
                onDeleteAccount: { selectedCategory = .dataSafety }
            )
        case .dataSafety:
            SettingsDataSafetySection()
        case .sync:
            SettingsSyncSection(probe: cloudAccount)
        case .appearance:
            SettingsAppearanceSection()
        case .navigation:
            SettingsNavigationSection(listDetailDefaultPage: $listDetailDefaultPage)
        case .sidebar:
            SettingsSidebarSection(
                orderedSidebarTabs: orderedSidebarTabs,
                hiddenTabs: hiddenTabs,
                sidebarTabColorsRaw: sidebarTabColorsRaw,
                onEdit: { editingSidebarTab = $0 },
                onDropBefore: moveSidebarTab(_:before:)
            )
        case .contexts:
            SettingsContextsSection(
                activeContexts: contexts.filter { !$0.isArchived },
                archivedContexts: contexts.filter(\.isArchived),
                onMoveContext: moveContext(_:before:),
                onArchiveContext: archiveContext(_:),
                onDeleteContext: { pendingDeleteContext = $0 },
                onRestoreContext: restoreContext(_:),
                onCreateContext: { showCreateContext = true }
            )
        case .tags:
            SettingsTagsSection(tags: tags)
        case .templates:
            SettingsTemplatesSection(templateOverridesRaw: $noteTemplateOverridesRaw)
        case .lists:
            SettingsListsSection(
                completedAreas: areas.filter(\.isDone),
                archivedAreas: areas.filter(\.isArchived),
                completedProjects: projects.filter(\.isDone),
                archivedProjects: projects.filter(\.isArchived),
                pausedProjects: projects.filter { $0.status == .paused },
                cancelledProjects: projects.filter { $0.status == .cancelled },
                onReopenArea: reopenArea(_:),
                onDeleteArea: { pendingDeleteArea = $0 },
                onReopenProject: reopenProject(_:),
                onDeleteProject: { pendingDeleteProject = $0 }
            )
        case .ai:
            SettingsAISection(
                aiSettingsManager: aiSettingsManager,
                aiAPIKeyDraft: $aiAPIKeyDraft
            )
        case .calendar:
            SettingsCalendarSection(
                calendarManager: calendarManager,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
        case .reminders:
            SettingsRemindersSection(remindersManager: remindersManager)
        case .notifications:
            SettingsNotificationsSection(
                notificationManager: notificationManager,
                notificationsEnabled: $notificationsEnabled
            )
        case .about:
            SettingsAboutSection()
        }
    }

    /// The layout the sidebar is drawing: the synced row if there is one, the device-local values
    /// otherwise. Both this screen and `SidebarView` read it through the same helper, so the list
    /// here is the column's own order rather than a second guess at it.
    private var sidebarLayout: CadenceSidebarLayoutPreferenceStore.Layout {
        CadenceSidebarLayoutPreferenceStore.layout(
            from: sidebarLayoutPreferences,
            legacyOrderRaw: sidebarTabOrderRaw,
            legacyHiddenRaw: sidebarHiddenTabsRaw
        )
    }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarLayout.hidden.compactMap(\.sidebarStaticDestination))
    }

    private var orderedSidebarTabs: [SidebarStaticDestination] {
        CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: sidebarLayout)
            .compactMap(\.sidebarStaticDestination)
    }

    /// Shows or hides a row, unless that would hide the last visible one — see
    /// `CadenceSidebarLayoutPreferenceStore.hidden(setting:visible:in:)`. The refusal is a sentence
    /// on screen rather than a switch that flips itself back, which says nothing.
    private func toggleTab(_ destination: SidebarStaticDestination) {
        let layout = sidebarLayout
        let shouldBecomeVisible = layout.hidden.contains(destination.feature)
        guard let hidden = CadenceSidebarLayoutPreferenceStore.hidden(
            setting: destination.feature,
            visible: shouldBecomeVisible,
            in: layout
        ) else {
            sidebarLayoutNotice = CadenceSidebarLayoutPreferenceStore.lastVisibleRowNotice
            return
        }
        writeSidebarLayout(.init(order: layout.order, hidden: hidden))
    }

    /// The one commit path for both sidebar-layout controls.
    ///
    /// Not `try?`: this inserts the synced row on the first edit, and the row moving under the
    /// cursor — or the toggle staying off — is the success claim, which is the pair the save-commit
    /// rule forbids swallowing.
    private func writeSidebarLayout(_ layout: CadenceSidebarLayoutPreferenceStore.Layout) {
        do {
            try CadenceSidebarLayoutPreferenceStore.write(
                layout,
                records: sidebarLayoutPreferences,
                in: modelContext
            )
            sidebarLayoutNotice = nil
        } catch {
            sidebarLayoutNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }

    private func setTabColor(_ destination: SidebarStaticDestination, hex: String) {
        var colors = SidebarStaticDestination.colorHexMap(from: sidebarTabColorsRaw)
        colors[destination] = hex
        sidebarTabColorsRaw = SidebarStaticDestination.rawColorString(from: colors)
    }

    private func moveSidebarTab(_ dragged: SidebarStaticDestination, before target: SidebarStaticDestination) {
        let layout = sidebarLayout
        guard let order = CadenceSidebarLayoutPreferenceStore.order(
            in: layout,
            moving: dragged.feature,
            before: target.feature
        ) else { return }
        writeSidebarLayout(.init(order: order, hidden: layout.hidden))
    }

    /// The drop half of the contexts pane's drag reorder.
    ///
    /// The arithmetic moved to `CadenceOrderReassignment` in T-581 rather than being copied for
    /// iPhone: the same "insert before" is `toIndex` upwards and `toIndex - 1` downwards, and a
    /// second hand-written copy of that on the other platform is how two lists come to disagree
    /// about where a dropped row lands.
    ///
    /// **The commit is reported, and the swallow that used to be here was the wrong half of a
    /// split decision (T-614).** T-583 recorded this `try?` as deliberate — `order` is a field on
    /// rows the store already holds, nothing after the save says it worked — while T-581 gave iOS
    /// the opposite treatment. Both read the rule correctly; the rule was underdetermined, and the
    /// user settled it: **a row that stays where you dropped it is the strongest success claim this
    /// app can make**, stronger than the dismissed sheet the rule already counts. "It is only an
    /// `order` field" answers the rule's first condition and ignores its second.
    ///
    /// So this side matches iOS's `moveContext(_:by:)`: `commitEdit(in:undo:)` puts every `order`
    /// back on a refusal, `@Query(sort: \Context.order)` re-sorts the pane to the store, and the
    /// notice under the header says so. Otherwise a refused reorder is a rearrangement the next
    /// launch silently undoes, with nothing to retry — the exact failure the rule exists to catch.
    ///
    /// `archiveContext` below is **not** the same shape and keeps its `try?`: an archived row
    /// leaves the list either way, so the pane makes no claim the store has not taken.
    ///
    /// The renumber runs over **every** context, archived rows included, for the reason iOS's
    /// copy records: `order` is one sequence, and numbering only the visible slice hands them
    /// indices the archived rows already hold.
    private func moveContext(_ draggedID: UUID, before targetID: UUID) {
        let snapshot = contexts
        guard let ordered = CadenceOrderReassignment.moved(snapshot, draggedID, before: targetID) else { return }

        let previousOrders = snapshot.map(\.order)
        for (index, context) in ordered.enumerated() {
            context.order = index
        }

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                for (context, order) in zip(snapshot, previousOrders) {
                    context.order = order
                }
            }
        } catch {
            contextOrderFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        contextOrderFailureNotice = nil
    }

    /// Archive a context, and commit it.
    ///
    /// **The convention these panes follow, stated once (T-583).** Every mutation made here commits
    /// where it happens; existence changes report, field edits commit quietly.
    ///
    /// - *Commit where it happens.* These two used to be inline `{ $0.isArchived = true }` closures
    ///   with no save at all, twelve lines above four siblings that all save. Autosave is not a
    ///   defence: no `autosaveEnabled` is set anywhere, so the default `true` does apply, but
    ///   "eventually" is the whole problem — `CadenceSavedLinkPersistence` measured it in T-327,
    ///   where a delete flushed by nobody came back on next launch.
    /// - *Quietly.* `try?` rather than `CadencePendingChangePersistence` because neither site
    ///   inserts, deletes, or claims success afterwards — the case `AGENTS.md`'s `try? save()` rule
    ///   explicitly leaves alone. `reopenArea` and `reopenProject` are the same shape, and so are
    ///   iOS's `archive(_:)`/`restore(_:)` and macOS's own
    ///   `SettingsTagsSection.archive(_:)`/`restore(_:)`; a fifth spelling here would be the
    ///   deviation, not the fix. **`moveContext` left this list in T-614** — a reorder the user can
    ///   see is a success report, which is the rule's second condition and not this one.
    /// - *Existence changes report.* Deleting a context is not a field edit, so it goes through
    ///   `report(.context)` and says so under the header. That contrast is the point: the panes are
    ///   consistent, not uniformly silent.
    private func archiveContext(_ context: Context) {
        context.isArchived = true
        try? modelContext.save()
    }

    /// Unarchive a context. See `archiveContext(_:)` for why the commit is here and why it is `try?`.
    private func restoreContext(_ context: Context) {
        context.isArchived = false
        try? modelContext.save()
    }

    private func reopenArea(_ area: Area) {
        area.status = .active
        try? modelContext.save()
    }

    private func reopenProject(_ project: Project) {
        project.status = .active
        try? modelContext.save()
    }

    /// T-291: `try? modelContext.save()` on top of a cascade that had already returned `false` was
    /// the worst of the three call sites — a settings row that simply stayed put, with no sheet to
    /// keep open and nothing said. `commitCascade` rolls a partial cascade back and throws;
    /// `report` puts the sentence where the row is.
    private func deleteContext(_ context: Context) {
        report(.context) { modelContext.deleteContext(context) }
    }

    private func deleteArea(_ area: Area) {
        report(.area) { modelContext.deleteArea(area) }
    }

    private func deleteProject(_ project: Project) {
        report(.project) { modelContext.deleteProject(project) }
    }

    private func report(_ kind: CadenceListDeletionKind, cascade: () -> Bool) {
        do {
            try CadencePendingChangePersistence.commitCascade(in: modelContext, cascade: cascade)
            deleteFailureNotice = nil
        } catch {
            deleteFailureNotice = kind.deleteFailureNotice
        }
    }
}
#endif

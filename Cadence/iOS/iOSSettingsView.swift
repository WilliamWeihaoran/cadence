#if os(iOS)
import SwiftData
import SwiftUI

struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NotificationManager.notificationsEnabledDefaultsKey) private var notificationsEnabled = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @AppStorage("ios.calendar.viewMode") private var calendarViewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var calendarPresentationRaw = CadenceCalendarPresentation.timeline.rawValue
    /// The same `Double` the calendar's pinch writes, through the same shared key. It was
    /// `@AppStorage("ios.calendar.zoomLevel") ... = 1` — the key re-spelled as a literal and
    /// typed `Int`, which is how the two ends of one preference drifted apart (T-392).
    @AppStorage(CadenceCalendarZoom.storageKey) private var calendarZoomLevel = CadenceCalendarZoom.defaultZoom
    @Query private var tasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var areas: [Area]
    @Query private var projects: [Project]
    @Query private var notes: [Note]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var cloudAccount = CadenceCloudAccountProbe()
    @State private var contextEditorMode: iOSContextEditorMode?
    @State private var pendingDeletion: iOSListDeletionTarget?
    /// What the iPad rail is pointing at. On iPad a category is always selected — the rail is
    /// beside the content, so there is no "no category" state to be in.
    @State private var selectedCategory: iOSSettingsCategory = .navigation
    /// The category the phone has drilled into, or `nil` for the category list.
    ///
    /// Deliberately local state rather than a `NavigationLink`: this same view is hosted with a
    /// navigation stack around it on iPhone and without one in the iPad shell, and a link whose
    /// destination is only sometimes reachable is the kind of control that looks tappable and
    /// does nothing.
    @State private var drilledCategory: iOSSettingsCategory?
    @State private var aiAPIKeyDraft = ""
    #if DEBUG
    @State private var sampleDataStatus: String?
    #endif

    private var appVersion: String { CadenceAppBuildIdentity.version }

    private var buildNumber: String { CadenceAppBuildIdentity.build }

    private var bundleID: String { CadenceAppBuildIdentity.bundleID }

    private var calendarViewMode: CadenceCalendarViewMode {
        CadenceCalendarViewMode(rawValue: calendarViewModeRaw) ?? .week
    }

    private var calendarPresentation: CadenceCalendarPresentation {
        CadenceCalendarPresentation(rawValue: calendarPresentationRaw) ?? .timeline
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                settingsRegularLayout
            } else {
                settingsCompactLayout
            }
        }
        .iOSHidesCompactNavigationBar()
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $contextEditorMode) { mode in
            iOSContextEditorSheet(mode: mode)
        }
        .iOSListDeletion(target: $pendingDeletion)
        .onAppear { cloudAccount.refreshIfNeeded() }
        // T-361: the toggle used to write `UserDefaults` and stop, leaving pending notifications
        // alive until the next scene-phase sweep. Both directions are handled in one shared place.
        .onChange(of: notificationsEnabled) { _, enabled in
            HabitNotificationReconcileSupport.notificationsEnabledDidChange(to: enabled, in: modelContext)
        }
    }

    /// iPhone: a list of categories, and one category at a time when you pick one.
    @ViewBuilder
    private var settingsCompactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let category = drilledCategory {
                    iOSSettingsPageHeader(
                        title: category.title,
                        tint: category.tint,
                        onBack: { drilledCategory = nil }
                    )

                    sectionContent(for: category)
                } else {
                    iOSSettingsPageHeader(
                        title: "Settings",
                        tint: Theme.blue,
                        onBack: { dismiss() }
                    )

                    iOSSettingsCategoryList { category in
                        drilledCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // Swapping the content inside one `ScrollView` keeps its offset, so drilling in from a
        // scrolled-down category list landed you mid-page on the category — with the header, and
        // therefore the way back, above the top of the screen.
        .id(drilledCategory)
    }

    private var settingsRegularLayout: some View {
        HStack(spacing: 0) {
            iOSSettingsRail(selectedCategory: $selectedCategory)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)

            settingsDetailScroll
        }
        .background(Theme.bg)
    }

    private var settingsDetailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The rail beside this already says "Settings" and names the selected category,
                // so the header here is the category's own title and glyph and nothing more.
                iOSSettingsPageHeader(
                    title: selectedCategory.title,
                    tint: selectedCategory.tint
                )

                sectionContent(for: selectedCategory)
            }
            .frame(maxWidth: 920, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func sectionContent(for category: iOSSettingsCategory) -> some View {
        switch category {
        case .appearance:
            iOSAppearanceSettingsSection()
        case .navigation:
            iOSNavigationSettingsSection(
                calendarViewMode: Binding(
                    get: { calendarViewMode },
                    set: { calendarViewModeRaw = $0.rawValue }
                ),
                calendarPresentation: Binding(
                    get: { calendarPresentation },
                    set: { calendarPresentationRaw = $0.rawValue }
                ),
                calendarZoomLevel: $calendarZoomLevel
            )
        case .sync:
            iOSSyncSettingsSection(probe: cloudAccount)
        case .calendar:
            iOSCalendarSettingsSection(
                calendarManager: calendarManager,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
        case .reminders:
            iOSRemindersSettingsSection(remindersManager: remindersManager)
        case .notifications:
            iOSNotificationsSettingsSection(
                notificationManager: notificationManager,
                notificationsEnabled: $notificationsEnabled
            )
        case .organization:
            organizationSection
        case .tags:
            iOSTagsSettingsSection(tags: tags)
        case .templates:
            iOSTemplatesSettingsSection(templateOverridesRaw: $noteTemplateOverridesRaw)
        case .lists:
            listsSection
        case .ai:
            iOSAISettingsSection(
                aiSettingsManager: aiSettingsManager,
                aiAPIKeyDraft: $aiAPIKeyDraft
            )
        case .data:
            dataSafetySection
        case .about:
            iOSAboutSettingsSection(
                appVersion: appVersion,
                buildNumber: buildNumber,
                bundleID: bundleID
            )
        }
    }

    /// Data Safety: what the store holds, and the route out of it.
    ///
    /// The delete action is the second half deliberately — the shipped privacy policy and App
    /// Review notes both promise it here, and for a long time this screen was count tiles alone.
    private var dataSafetySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if DEBUG
            iOSLocalDataSettingsSection(
                activeTaskCount: activeTaskCount,
                completedTaskCount: completedTaskCount,
                inboxTaskCount: inboxTaskCount,
                activeContextCount: activeContextCount,
                activeAreaCount: activeAreaCount,
                activeProjectCount: activeProjectCount,
                noteCount: notes.count,
                sampleDataStatus: sampleDataStatus,
                seedSampleData: seedSampleData
            )
            #else
            iOSLocalDataSettingsSection(
                activeTaskCount: activeTaskCount,
                completedTaskCount: completedTaskCount,
                inboxTaskCount: inboxTaskCount,
                activeContextCount: activeContextCount,
                activeAreaCount: activeAreaCount,
                activeProjectCount: activeProjectCount,
                noteCount: notes.count
            )
            #endif

            // Keep-a-copy before delete-everything: the export is the only route on this device
            // to data that outlives the app, and it belongs above the control that ends it.
            iOSDataExportSettingsSection()
            iOSDataResetSettingsSection()
        }
    }

    private var listsSection: some View {
        iOSListsLifecycleSettingsSection(
            completedAreas: areas.filter(\.isDone),
            archivedAreas: areas.filter(\.isArchived),
            completedProjects: projects.filter(\.isDone),
            archivedProjects: projects.filter(\.isArchived),
            onReopenArea: reopen(_:),
            onReopenProject: reopen(_:),
            onDeleteArea: { pendingDeletion = .area($0) },
            onDeleteProject: { pendingDeletion = .project($0) }
        )
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                CadenceSettingsSectionLabel(text: "Active Contexts")
                Spacer()
                iOSActionButton(
                    title: "New Context",
                    systemImage: "plus",
                    role: .primary,
                    size: .compact
                ) {
                    contextEditorMode = .new
                }
            }

            iOSSettingsCard {
                VStack(spacing: 0) {
                    if activeContexts.isEmpty {
                        iOSSettingsEmptyRow(
                            title: "No active contexts",
                            subtitle: "Create one here, then use it when making areas and projects."
                        )
                    } else {
                        ForEach(activeContexts) { context in
                            Button {
                                contextEditorMode = .edit(context)
                            } label: {
                                iOSSettingsContextRow(context: context)
                            }
                            .buttonStyle(.iosPressable)
                            .contextMenu {
                                Button {
                                    contextEditorMode = .edit(context)
                                } label: {
                                    Label("Edit Context", systemImage: "square.and.pencil")
                                }

                                Button(role: .destructive) {
                                    archive(context)
                                } label: {
                                    Label("Archive Context", systemImage: "archivebox")
                                }

                                iOSListDeleteMenuButton(target: .context(context)) { pendingDeletion = $0 }
                            }

                            if context.id != activeContexts.last?.id {
                                iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                            }
                        }
                    }
                }
            }

            if !archivedContexts.isEmpty {
                CadenceSettingsSectionLabel(text: "Archived Contexts")
                iOSSettingsCard {
                    VStack(spacing: 0) {
                        ForEach(archivedContexts) { context in
                            iOSSettingsArchivedContextRow(
                                context: context,
                                restore: { restore(context) },
                                delete: { pendingDeletion = .context(context) }
                            )

                            if context.id != archivedContexts.last?.id {
                                iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeTaskCount: Int {
        CadenceTaskQuerySupport.openTaskCount(from: tasks)
    }

    private var completedTaskCount: Int {
        CadenceTaskQuerySupport.completedTaskCount(from: tasks)
    }

    private var inboxTaskCount: Int {
        CadenceTaskQuerySupport.openInboxTaskCount(from: tasks)
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var archivedContexts: [Context] {
        contexts.filter(\.isArchived)
    }

    private var activeContextCount: Int {
        activeContexts.count
    }

    private var activeAreaCount: Int {
        areas.filter(\.isActive).count
    }

    private var activeProjectCount: Int {
        projects.filter(\.isActive).count
    }

    #if DEBUG
    private func seedSampleData() {
        do {
            let inserted = try iOSSampleDataSupport.seedReviewTasks(
                allTasks: tasks,
                modelContext: modelContext
            )
            sampleDataStatus = inserted == 0 ? "Sample review data already exists." : "Added \(inserted) sample review items."
        } catch {
            sampleDataStatus = "Could not add sample tasks."
        }
    }
    #endif

    private func archive(_ context: Context) {
        context.isArchived = true
        try? modelContext.save()
    }

    private func restore(_ context: Context) {
        context.isArchived = false
        try? modelContext.save()
    }

    private func reopen(_ area: Area) {
        area.status = .active
        try? modelContext.save()
    }

    private func reopen(_ project: Project) {
        project.status = .active
        try? modelContext.save()
    }
}

#endif

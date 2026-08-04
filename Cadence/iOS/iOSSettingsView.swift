#if os(iOS)
import CloudKit
import SwiftData
import SwiftUI

struct iOSSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @AppStorage("ios.today.layoutMode") private var todayLayoutModeRaw = iPadTodayLayoutMode.focus.rawValue
    @AppStorage("ios.calendar.viewMode") private var calendarViewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var calendarPresentationRaw = CadenceCalendarPresentation.timeline.rawValue
    @AppStorage("ios.calendar.zoomLevel") private var calendarZoomLevel = 1
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var notesEditorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @Query private var tasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var areas: [Area]
    @Query private var projects: [Project]
    @Query private var notes: [Note]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var accountStatus: CKAccountStatus?
    @State private var accountError: String?
    @State private var isCheckingAccount = false
    @State private var lastChecked: Date?
    @State private var contextEditorMode: iOSContextEditorMode?
    @State private var selectedCategory: iOSSettingsCategory = .appearance
    @State private var aiAPIKeyDraft = ""
    #if DEBUG
    @State private var sampleDataStatus: String?
    #endif

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var todayLayoutMode: iPadTodayLayoutMode {
        iPadTodayLayoutMode(rawValue: todayLayoutModeRaw) ?? .focus
    }

    private var calendarViewMode: CadenceCalendarViewMode {
        CadenceCalendarViewMode(rawValue: calendarViewModeRaw) ?? .week
    }

    private var calendarPresentation: CadenceCalendarPresentation {
        CadenceCalendarPresentation(rawValue: calendarPresentationRaw) ?? .timeline
    }

    private var notesEditorMode: iOSMarkdownEditorMode {
        iOSMarkdownEditorPreferences.mode(from: notesEditorModeRaw)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                settingsRegularLayout
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsHeader
                        iOSSettingsCompactCategoryPicker(selectedCategory: $selectedCategory)
                        selectedSectionContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Settings")
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $contextEditorMode) { mode in
            iOSContextEditorSheet(mode: mode)
        }
        .onAppear {
            if accountStatus == nil && !isCheckingAccount {
                refreshAccountStatus()
            }
        }
    }

    private var settingsRegularLayout: some View {
        HStack(spacing: 0) {
            iOSSettingsRail(selectedCategory: $selectedCategory)

            Divider()
                .background(Theme.borderSubtle)

            settingsDetailScroll
        }
        .background(Theme.bg)
    }

    private var settingsDetailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader
                selectedSectionContent
            }
            .frame(maxWidth: 920, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsHeader: some View {
        iOSSettingsPageHeader(
            title: selectedCategory.title,
            subtitle: selectedCategory.detailDescription,
            icon: selectedCategory.icon,
            tint: selectedCategory.tint
        ) {
            switch selectedCategory {
            case .appearance:
                CadenceSettingsStatusBadge(title: themeManager.selectedTheme.title, isActive: true)
            case .navigation:
                CadenceSettingsStatusBadge(title: todayLayoutMode.title, isActive: true)
            case .sync:
                CadenceSettingsStatusBadge(
                    title: cloudStatusPresentation.title,
                    isActive: accountStatus == .available && accountError == nil
                )
            case .calendar:
                CadenceSettingsStatusBadge(title: calendarManager.isAuthorized ? "Connected" : "Not connected", isActive: calendarManager.isAuthorized)
            case .organization:
                CadenceSettingsStatusBadge(title: "\(activeContextCount) contexts", isActive: activeContextCount > 0)
            case .tags:
                CadenceSettingsStatusBadge(title: "\(activeTagCount) active", isActive: activeTagCount > 0)
            case .templates:
                CadenceSettingsStatusBadge(title: "\(customTemplateCount) customized", isActive: customTemplateCount > 0)
            case .lists:
                CadenceSettingsStatusBadge(title: "\(inactiveListCount) inactive", isActive: inactiveListCount > 0)
            case .ai:
                CadenceSettingsStatusBadge(title: aiSettingsManager.hasAPIKey ? "Key saved" : "No key", isActive: aiSettingsManager.hasAPIKey)
            case .data:
                CadenceSettingsStatusBadge(title: "\(activeTaskCount) active", isActive: activeTaskCount > 0)
            case .coverage:
                CadenceSettingsStatusBadge(title: "Companion", isActive: true)
            case .about:
                CadenceSettingsStatusBadge(title: "Build \(buildNumber)", isActive: true)
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedCategory {
        case .appearance:
            iOSAppearanceSettingsSection(
                selectedTheme: themeManager.selectedTheme,
                onSelectTheme: { themeManager.selectedTheme = $0 }
            )
        case .navigation:
            iOSNavigationSettingsSection(
                todayLayoutMode: Binding(
                    get: { todayLayoutMode },
                    set: { todayLayoutModeRaw = $0.rawValue }
                ),
                calendarViewMode: Binding(
                    get: { calendarViewMode },
                    set: { calendarViewModeRaw = $0.rawValue }
                ),
                calendarPresentation: Binding(
                    get: { calendarPresentation },
                    set: { calendarPresentationRaw = $0.rawValue }
                ),
                calendarZoomLevel: $calendarZoomLevel,
                notesEditorMode: Binding(
                    get: { notesEditorMode },
                    set: { notesEditorModeRaw = $0.rawValue }
                )
            )
        case .sync:
            iOSSyncSettingsSection(
                accountStatus: accountStatus,
                accountError: accountError,
                isCheckingAccount: isCheckingAccount,
                lastChecked: lastChecked,
                refreshAccountStatus: refreshAccountStatus
            )
        case .calendar:
            iOSCalendarSettingsSection(
                calendarManager: calendarManager,
                areas: areas,
                projects: projects,
                modelContext: modelContext
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
        case .coverage:
            iOSMobileCoverageSettingsSection()
        case .about:
            iOSAboutSettingsSection(
                appVersion: appVersion,
                buildNumber: buildNumber,
                bundleID: bundleID
            )
        }
    }

    private var listsSection: some View {
        iOSListsLifecycleSettingsSection(
            completedAreas: areas.filter(\.isDone),
            archivedAreas: areas.filter(\.isArchived),
            completedProjects: projects.filter(\.isDone),
            archivedProjects: projects.filter(\.isArchived),
            onReopenArea: reopen(_:),
            onReopenProject: reopen(_:)
        )
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CadenceSettingsSectionLabel(text: "Contexts")
                Spacer()
                Button {
                    contextEditorMode = .new
                } label: {
                    Label("New Context", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
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
                            .buttonStyle(.plain)
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
                            }

                            if context.id != activeContexts.last?.id {
                                Divider().background(Theme.borderSubtle)
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
                            iOSSettingsArchivedContextRow(context: context) {
                                restore(context)
                            }

                            if context.id != archivedContexts.last?.id {
                                Divider().background(Theme.borderSubtle)
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

    private var activeTagCount: Int {
        tags.filter { !$0.isArchived }.count
    }

    private var customTemplateCount: Int {
        NoteTemplateLibrary.overrides(from: noteTemplateOverridesRaw).count
    }

    private var inactiveListCount: Int {
        areas.filter { $0.isDone || $0.isArchived }.count +
            projects.filter { $0.isDone || $0.isArchived }.count
    }

    private var activeAreaCount: Int {
        areas.filter(\.isActive).count
    }

    private var activeProjectCount: Int {
        projects.filter(\.isActive).count
    }

    private var cloudStatusPresentation: iOSCloudStatusPresentation {
        iOSCloudStatusPresentation(
            accountStatus: accountStatus,
            accountError: accountError,
            isCheckingAccount: isCheckingAccount
        )
    }

    private func refreshAccountStatus() {
        isCheckingAccount = true
        accountError = nil

        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                accountStatus = status
                accountError = error?.localizedDescription
                isCheckingAccount = false
                lastChecked = Date()
            }
        }
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

private struct iOSTagsSettingsSection: View {
    let tags: [Tag]

    @Environment(\.modelContext) private var modelContext
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newColorHex = TagSupport.colorOptions[2]

    private var activeTags: [Tag] {
        TagSupport.sorted(tags.filter { !$0.isArchived })
    }

    private var archivedTags: [Tag] {
        TagSupport.sorted(tags.filter(\.isArchived))
    }

    private var newSlug: String {
        TagSupport.slug(for: newName)
    }

    private var hasDuplicate: Bool {
        guard !TagSupport.displayName(for: newName).isEmpty else { return false }
        return activeTags.contains { $0.slug == newSlug }
    }

    private var matchingArchived: Tag? {
        guard !TagSupport.displayName(for: newName).isEmpty else { return nil }
        return archivedTags.first { $0.slug == newSlug }
    }

    private var canCreate: Bool {
        let display = TagSupport.displayName(for: newName)
        return !display.isEmpty &&
            display.rangeOfCharacter(from: .alphanumerics) != nil &&
            !hasDuplicate &&
            matchingArchived == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Create Tag")
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("Optional description", text: $newDescription)
                        .textFieldStyle(.roundedBorder)

                    iOSTagColorPicker(selectedHex: $newColorHex)

                    if let matchingArchived {
                        iOSTagNoticeRow(
                            icon: "archivebox.fill",
                            text: "\"\(matchingArchived.name)\" is archived.",
                            actionTitle: "Restore",
                            action: {
                                restore(matchingArchived)
                                clearDraft()
                            }
                        )
                    } else if hasDuplicate {
                        iOSTagNoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            text: "A tag with this name already exists.",
                            actionTitle: nil,
                            action: {}
                        )
                    }

                    HStack {
                        Button {
                            TagSupport.seedDefaultTags(in: modelContext)
                        } label: {
                            Label("Add Defaults", systemImage: "arrow.clockwise")
                        }
                        .font(.system(size: 12, weight: .semibold))

                        Spacer()

                        Button {
                            createTag()
                        } label: {
                            Label("Create", systemImage: "plus")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blue)
                        .disabled(!canCreate)
                    }
                }
            }

            CadenceSettingsSectionLabel(text: "Active Tags")
            iOSSettingsCard {
                if activeTags.isEmpty {
                    iOSSettingsEmptyRow(title: "No active tags", subtitle: "Create one or add the default set.")
                } else {
                    iOSTagList(tags: activeTags, isArchivedList: false, archive: archive(_:), restore: restore(_:))
                }
            }

            if !archivedTags.isEmpty {
                CadenceSettingsSectionLabel(text: "Archived Tags")
                iOSSettingsCard {
                    iOSTagList(tags: archivedTags, isArchivedList: true, archive: archive(_:), restore: restore(_:))
                }
            }
        }
        .onAppear {
            TagSupport.seedDefaultTags(in: modelContext)
        }
    }

    private func createTag() {
        guard canCreate else { return }
        let displayName = TagSupport.displayName(for: newName)
        let tag = Tag(
            name: displayName,
            slug: TagSupport.slug(for: displayName),
            desc: newDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: TagSupport.normalizedColorHex(newColorHex),
            order: (tags.map(\.order).max() ?? -1) + 1
        )
        modelContext.insert(tag)
        try? modelContext.save()
        clearDraft()
    }

    private func clearDraft() {
        newName = ""
        newDescription = ""
        newColorHex = TagSupport.colorOptions[2]
    }

    private func archive(_ tag: Tag) {
        tag.isArchived = true
        tag.updatedAt = Date()
        try? modelContext.save()
    }

    private func restore(_ tag: Tag) {
        tag.isArchived = false
        tag.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct iOSTagList: View {
    let tags: [Tag]
    let isArchivedList: Bool
    let archive: (Tag) -> Void
    let restore: (Tag) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                iOSTagSettingsRow(
                    tag: tag,
                    isArchivedList: isArchivedList,
                    archive: { archive(tag) },
                    restore: { restore(tag) }
                )

                if index < tags.count - 1 {
                    Divider().background(Theme.borderSubtle)
                }
            }
        }
    }
}

private struct iOSTagSettingsRow: View {
    let tag: Tag
    let isArchivedList: Bool
    let archive: () -> Void
    let restore: () -> Void

    private var usageText: String {
        let taskCount = tag.tasks?.count ?? 0
        let noteCount = tag.notes?.count ?? 0
        return "\(taskCount) task\(taskCount == 1 ? "" : "s"), \(noteCount) note\(noteCount == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(alignment: tag.desc.isEmpty ? .center : .top, spacing: 11) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, tag.desc.isEmpty ? 0 : 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("#\(tag.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tag.isArchived ? Theme.muted : Theme.text)
                    .lineLimit(1)

                Text(usageText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)

                if !tag.desc.isEmpty {
                    Text(tag.desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                isArchivedList ? restore() : archive()
            } label: {
                Image(systemName: isArchivedList ? "arrow.uturn.backward" : "archivebox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isArchivedList ? Theme.blue : Theme.amber)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .opacity(tag.isArchived ? 0.72 : 1)
    }
}

private struct iOSTagColorPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 9) {
            ForEach(TagSupport.colorOptions, id: \.self) { option in
                Button {
                    selectedHex = option
                } label: {
                    Circle()
                        .fill(Color(hex: option))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if TagSupport.normalizedColorHex(selectedHex).caseInsensitiveCompare(option) == .orderedSame {
                                Circle().strokeBorder(Theme.text.opacity(0.78), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct iOSTagNoticeRow: View {
    let icon: String
    let text: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum iOSContextEditorMode: Identifiable {
    case new
    case edit(Context)

    var id: String {
        switch self {
        case .new:
            return "new-context"
        case .edit(let context):
            return "context-\(context.id)"
        }
    }
}

private struct iOSContextEditorSheet: View {
    let mode: iOSContextEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @State private var name = ""
    @State private var icon = "square.stack.fill"
    @State private var colorHex = "#4a9eff"
    @State private var hasLoaded = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Context") {
                    TextField("Name", text: $name)
                    TextField("SF Symbol", text: $icon)
                        .textInputAutocapitalization(.never)
                    TextField("Color hex", text: $colorHex)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    iOSSettingsContextPreview(
                        name: trimmedName.isEmpty ? "Context" : trimmedName,
                        icon: normalizedIcon,
                        colorHex: normalizedColor
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isEditing ? "Edit Context" : "New Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .new:
            name = ""
            icon = "square.stack.fill"
            colorHex = "#4a9eff"
        case .edit(let context):
            name = context.name
            icon = context.icon
            colorHex = context.colorHex
        }
    }

    private func save() {
        switch mode {
        case .new:
            let context = Context(name: trimmedName, colorHex: normalizedColor, icon: normalizedIcon)
            context.order = nextContextOrder()
            modelContext.insert(context)
        case .edit(let context):
            context.name = trimmedName
            context.icon = normalizedIcon
            context.colorHex = normalizedColor
        }

        try? modelContext.save()
        dismiss()
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "square.stack.fill" : trimmed
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return "#4a9eff"
        }
        return trimmed
    }

    private func nextContextOrder() -> Int {
        (contexts.map(\.order).max() ?? -1) + 1
    }
}

private struct iOSSettingsContextRow: View {
    let context: Context

    var body: some View {
        iOSSettingsContextPreview(
            name: context.name.isEmpty ? "Untitled Context" : context.name,
            icon: context.icon,
            colorHex: context.colorHex
        )
    }
}

private struct iOSSettingsArchivedContextRow: View {
    let context: Context
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex, opacity: 0.42)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.name.isEmpty ? "Untitled Context" : context.name)
                    .foregroundStyle(Theme.muted)
                Text("Archived")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }

            Spacer()

            Button("Restore", action: restore)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 10)
    }
}

private struct iOSSettingsContextPreview: View {
    let name: String
    let icon: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 12) {
            iOSSettingsContextIcon(icon: icon, colorHex: colorHex)

            Text(name)
                .foregroundStyle(Theme.text)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct iOSSettingsContextIcon: View {
    let icon: String
    let colorHex: String
    var opacity: Double = 1

    var body: some View {
        let tint = Color(hex: colorHex)

        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint.opacity(opacity))
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12 * opacity))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#endif

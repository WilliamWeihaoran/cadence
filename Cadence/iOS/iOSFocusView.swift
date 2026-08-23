#if os(iOS)
import SwiftData
import SwiftUI

struct iOSFocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @State private var selectedTarget: CadenceFocusTarget?
    @State private var selectedBundleTaskIDs: Set<UUID> = []
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var timerState = CadenceFocusTimerState()

    private var todayKey: String { DateFormatters.todayKey() }

    private var readyTasks: [AppTask] {
        CadenceFocusSupport.readyTasks(from: allTasks, todayKey: todayKey)
    }

    /// Ready tasks **and** the blocks you could sit down and work through, in one list, ordered by
    /// the one rule both platforms use (`CadenceFocusPickItem`).
    ///
    /// `limit: nil` because this picker has no search field: macOS caps its unfiltered list at 18
    /// on the understanding that you can type past the cap, and applying that here would just hide
    /// the nineteenth ready task with no way to reach it.
    private var pickItems: [CadenceFocusPickItem] {
        CadenceFocusPickItem.filtered(
            tasks: readyTasks,
            bundles: allBundles,
            query: "",
            todayKey: todayKey,
            limit: nil
        )
    }

    /// The row the session is running against. An explicitly chosen subject wins even after it
    /// leaves the ready list — finishing the last member of a block, or completing the focused
    /// task, must not silently re-point the clock at something else mid-session — and with nothing
    /// chosen the head of the list is offered.
    private var selectedItem: CadenceFocusPickItem? {
        guard let selectedTarget else { return pickItems.first }
        if let match = pickItems.first(where: { $0.target == selectedTarget }) { return match }
        switch selectedTarget {
        case .task(let id):
            return allTasks.first { $0.id == id }.map(CadenceFocusPickItem.task)
        case .bundle(let id):
            return allBundles.first { $0.id == id }.map(CadenceFocusPickItem.bundle)
        }
    }

    /// The same subject with the bundle's member ticks attached, which is what the commit path
    /// needs to know where a block's minutes go.
    private var selectedSubject: CadenceFocusSubject? {
        switch selectedItem {
        case .task(let task): return .task(task)
        case .bundle(let bundle): return .bundle(bundle, selectedTaskIDs: selectedBundleTaskIDs)
        case nil: return nil
        }
    }

    private var elapsedSeconds: Int {
        timerState.elapsedSeconds()
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
        .onAppear {
            if selectedTarget == nil, let first = pickItems.first {
                adopt(first)
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
    }

    /// The narrow fallback is the phone's own stacked form. It pushes nothing, so unlike Goals and
    /// Habits it needs no `NavigationStack` of its own.
    private var horizontalLayout: some View {
        iOSFeatureSplitLayout(
            list: { taskListPane },
            detail: { focusDetailPane },
            narrow: { compactLayout }
        )
    }

    /// The eyebrow carries the session's state, because the title already says "Focus" and a
    /// header that describes the screen you are on twice tells the reader nothing.
    private var statusEyebrow: String {
        if timerState.isRunning { return "Session running" }
        if elapsedSeconds > 0 { return "Session paused" }
        return pickItems.isEmpty ? "Nothing ready" : "\(pickItems.count) ready"
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                iOSCompactPageHeader(
                    eyebrow: statusEyebrow,
                    title: "Focus",
                    color: Theme.red,
                    // This layout is also the regular-width narrow fallback, where it is the page
                    // the sidebar selected and there is nothing behind it to go back to.
                    onBack: isCompact ? { dismiss() } : nil
                )

                if pickItems.isEmpty {
                    // A single consolidated empty state avoids showing two
                    // near-duplicate "nothing here" messages stacked on top
                    // of each other (task list pane + focus detail pane).
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: CadenceEmptyStateCopy.focusTitle,
                        subtitle: CadenceEmptyStateCopy.focusSubtitle
                    )
                    .frame(minHeight: 360)
                    .background(Theme.surface)
                    .iOSCompactPanelCard()
                } else {
                    focusDetailPane
                        .iOSCompactPanelCard()

                    taskListPane
                        .frame(minHeight: 280, maxHeight: 380)
                        .iOSCompactPanelCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Picker

    private var taskListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Ready to focus", title: "Pick a session", count: pickItems.count)
            Divider().background(Theme.borderSubtle)

            if pickItems.isEmpty {
                iOSEmptyPanel(
                    systemImage: "timer",
                    title: CadenceEmptyStateCopy.focusTitle,
                    subtitle: CadenceEmptyStateCopy.focusSubtitle
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pickItems) { item in
                            pickRow(item)
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.surface)
    }

    /// One row struct for both kinds of session. A bundle differs from a task in its tint, its
    /// leading glyph and what its detail line says — not in how it is picked or started — so it is
    /// the same row parameterised, not a second copy of it.
    private func pickRow(_ item: CadenceFocusPickItem) -> some View {
        let target = item.target
        return iOSFocusPickRow(
            title: title(of: item),
            detail: detail(of: item),
            tint: tint(of: item),
            glyph: glyph(of: item),
            isSelected: selectedItem?.target == target,
            isRunning: timerState.isRunning && selectedItem?.target == target,
            select: { select(item) },
            toggleSession: { toggleSession(for: item) }
        )
    }

    private func title(of item: CadenceFocusPickItem) -> String {
        switch item {
        case .task(let task): return task.title.isEmpty ? "Untitled Task" : task.title
        case .bundle(let bundle): return bundle.displayTitle
        }
    }

    private func detail(of item: CadenceFocusPickItem) -> String {
        switch item {
        case .task(let task):
            return CadenceFocusSupport.sidebarDetail(for: task, todayKey: todayKey)
        case .bundle(let bundle):
            return CadenceFocusBundlePresentation.summaryLine(for: bundle, todayKey: todayKey)
        }
    }

    /// A block has no list of its own, so it takes the amber the rest of the app already uses for
    /// bundles — the timeline block, macOS's picker row, and the member panel's own heading.
    private func tint(of item: CadenceFocusPickItem) -> Color {
        switch item {
        case .task(let task): return Color(hex: task.containerColor)
        case .bundle: return Theme.amber
        }
    }

    /// `nil` means the task's list colour as a dot; a glyph is what marks the row as something
    /// other than a single task. Same `tray.full` macOS's picker draws.
    private func glyph(of item: CadenceFocusPickItem) -> String? {
        switch item {
        case .task: return nil
        case .bundle: return "tray.full"
        }
    }

    // MARK: - Session

    private var focusDetailPane: some View {
        VStack(spacing: isCompact ? 16 : 20) {
            switch selectedItem {
            case .task(let task):
                selectedTaskHeader(task)
                timerPanel(accent: Color(hex: task.containerColor), controls: { focusControls(for: task) })
                taskNotes(task)
                Spacer(minLength: 0)
            case .bundle(let bundle):
                selectedBundleHeader(bundle)
                timerPanel(accent: Theme.amber, controls: { bundleControls(for: bundle) })
                bundleMembers(bundle)
                Spacer(minLength: 0)
            case nil:
                iOSEmptyPanel(
                    systemImage: "timer",
                    title: "Ready when you are",
                    subtitle: "Today tasks will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 16 : 22)
        .background(Theme.bg)
    }

    private func selectedTaskHeader(_ task: AppTask) -> some View {
        sessionHeader(title: task.title.isEmpty ? "Untitled Task" : task.title) {
            if !task.containerName.isEmpty {
                iOSMetaChip(label: task.containerName, color: Color(hex: task.containerColor))
            }
            if task.priority != .none {
                iOSMetaChip(label: task.priority.label, color: Theme.priorityColor(task.priority))
            }
            if let estimate = estimateLabel(for: task) {
                iOSMetaChip(label: estimate, color: Theme.dim)
            }
        }
    }

    /// The block's own facts, from the same helper the picker row's line comes from — minus the
    /// leading "Bundle" label, because the title above these chips already is one.
    private func selectedBundleHeader(_ bundle: TaskBundle) -> some View {
        sessionHeader(title: bundle.displayTitle) {
            ForEach(
                Array(
                    CadenceFocusBundlePresentation
                        .summaryParts(for: bundle, todayKey: todayKey)
                        .dropFirst()
                        .enumerated()
                ),
                id: \.offset
            ) { _, part in
                iOSMetaChip(label: part, color: Theme.amber)
            }
        }
    }

    private func sessionHeader<Chips: View>(
        title: String,
        @ViewBuilder chips: () -> Chips
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: isCompact ? 22 : 25, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(3)

            HStack(spacing: 8) {
                chips()
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerPanel<Controls: View>(
        accent: Color,
        @ViewBuilder controls: @escaping () -> Controls
    ) -> some View {
        iOSFocusTimerPanel(
            accent: accent,
            isRunning: timerState.isRunning,
            isCompact: isCompact,
            clock: {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let seconds = elapsedSeconds
                    VStack(spacing: 6) {
                        Text(CadenceFocusSupport.clockDisplay(elapsedSeconds: seconds))
                            .font(.system(size: isCompact ? 56 : 66, weight: .ultraLight, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(timerState.isRunning ? Theme.text : Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .contentTransition(.numericText())

                        // The stopwatch silently rounds to whole minutes when it is logged, so
                        // the amount that will actually land on the task is spelled out rather
                        // than left to be discovered after the fact.
                        Text(logHint(elapsedSeconds: seconds))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.subdued)
                    }
                }
            },
            controls: controls
        )
    }

    /// Same "actual/estimate" pill macOS's focus header shows, minus the empty `-/-` case.
    private func estimateLabel(for task: AppTask) -> String? {
        let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        return label == "-/-" ? nil : label
    }

    private func logHint(elapsedSeconds seconds: Int) -> String {
        let minutes = CadenceFocusSupport.minutes(fromElapsedSeconds: seconds)
        guard minutes > 0 else { return "Nothing to log yet" }
        return "Logs \(minutes)m when you finish"
    }

    private func focusControls(for task: AppTask) -> some View {
        HStack(spacing: 16) {
            resetButton

            playButton(accent: Color(hex: task.containerColor))

            iOSFocusControlButton(
                systemImage: "checkmark",
                accessibilityLabel: "Log session and mark done",
                // Always green: the button works at zero elapsed (it completes the task), so
                // greying it promised a disabled control that was not disabled.
                foreground: Theme.green,
                background: Theme.surfaceElevated,
                diameter: 48
            ) {
                complete(task)
            }
        }
    }

    /// A block's third control **logs**; it does not complete.
    ///
    /// Finishing a task is one decision about one thing. "Finish the block" would be a decision
    /// about every member at once — including the ones you unticked precisely because you were not
    /// working on them — so the control that would do it does not exist, and the glyph deliberately
    /// is not the checkmark beside it on the task session. Completion stays where it is honest: the
    /// member's own circle in the block's inspector.
    private func bundleControls(for bundle: TaskBundle) -> some View {
        HStack(spacing: 16) {
            resetButton

            playButton(accent: Theme.amber)

            iOSFocusControlButton(
                systemImage: "tray.and.arrow.down",
                accessibilityLabel: "Log session to the selected tasks",
                foreground: Theme.amber,
                background: Theme.surfaceElevated,
                diameter: 48
            ) {
                logBundleSession(bundle)
            }
        }
    }

    private var resetButton: some View {
        iOSFocusControlButton(
            systemImage: "arrow.counterclockwise",
            accessibilityLabel: "Reset session",
            foreground: Theme.muted,
            background: Theme.surfaceElevated,
            diameter: 48,
            action: resetTimer
        )
    }

    private func playButton(accent: Color) -> some View {
        iOSFocusControlButton(
            systemImage: timerState.isRunning ? "pause.fill" : "play.fill",
            accessibilityLabel: timerState.isRunning ? "Pause session" : "Start session",
            foreground: Theme.onColor,
            background: accent,
            diameter: 64,
            glowColor: accent.opacity(0.45),
            action: toggleTimer
        )
    }

    /// Which members receive the session's minutes. macOS's `FocusBundleTasksPanel` in touch
    /// clothes: the same three facts per row, from the same `CadenceBundleTaskRowSupport`, and the
    /// same square-not-circle tick, because this control includes a task in the time log and the
    /// app's circle already means completed.
    private func bundleMembers(_ bundle: TaskBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SectionEyebrowLabel(text: "Bundle tasks", tint: Theme.amber)
                Text(CadenceFocusBundlePresentation.selectionSummary(for: bundle, selectedTaskIDs: selectedBundleTaskIDs))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subdued)
            }

            if bundle.sortedTasks.isEmpty {
                Text("This block is empty.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(bundle.sortedTasks) { task in
                    iOSFocusBundleMemberRow(
                        task: task,
                        isSelected: selectedBundleTaskIDs.contains(task.id),
                        toggle: { toggleMember(task) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }

    @ViewBuilder
    private func taskNotes(_ task: AppTask) -> some View {
        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            iOSMarkdownPreview(
                markdown: task.notes,
                imageAssets: imageAssets,
                taskEmbeds: taskEmbedInfos,
                onOpenReference: openMarkdownReference
            )
            // No `minHeight`. A two-line note was drawn in a 140pt card with ninety points of
            // empty surface under it; the cap is what this needs, not a floor.
            .frame(maxWidth: .infinity, maxHeight: isCompact ? 260 : 320, alignment: .topLeading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
    }

    private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(uniqueKeysWithValues: allTasks.map { task in
            (task.id, MarkdownTaskEmbedRenderInfo.task(task))
        })
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    /// Picking another session banks the seconds the one being left earned, before the clock is
    /// cleared for the new one. This used to be `selectedTaskID = task.id; resetTimer()`, which
    /// dropped them — see `CadenceFocusSupport.commitElapsed(leaving:switchingTo:state:...)`. It
    /// passes the whole *subject*, not an id, because leaving a block has to know which members
    /// were ticked to know where its minutes go.
    private func select(_ item: CadenceFocusPickItem) {
        timerState = CadenceFocusSupport.commitElapsed(
            leaving: selectedSubject,
            switchingTo: item.target,
            state: timerState,
            modelContext: modelContext
        )
        adopt(item)
    }

    /// Start, or pause, from the row itself — the second way the selection can move, so it commits
    /// the outgoing subject's seconds first for the same reason `select(_:)` does. The
    /// reset-on-switch rule lives in `CadenceFocusSupport.timerState(afterPlayTapOn:…)` so it can be
    /// asserted on; carrying another subject's elapsed seconds across would log them onto this one.
    ///
    /// Both read `selectedItem`, not `selectedTarget`: with nothing explicitly picked the session
    /// runs against the head of the list, and passing the `nil` target would treat leaving that
    /// subject as leaving nothing.
    private func toggleSession(for item: CadenceFocusPickItem) {
        timerState = CadenceFocusSupport.commitElapsed(
            leaving: selectedSubject,
            switchingTo: item.target,
            state: timerState,
            modelContext: modelContext
        )
        timerState = CadenceFocusSupport.timerState(
            afterPlayTapOn: item.target,
            selectedTarget: selectedItem?.target,
            state: timerState
        )
        adopt(item)
    }

    /// Point the session at `item`, seeding a block's member ticks **only when the block itself
    /// changes**. Re-selecting the block already loaded must not undo the ticks you just made — the
    /// picker row stays tappable while its own session runs.
    private func adopt(_ item: CadenceFocusPickItem) {
        let previous = selectedTarget
        selectedTarget = item.target

        switch item {
        case .task:
            selectedBundleTaskIDs = []
        case .bundle(let bundle):
            if previous != item.target {
                selectedBundleTaskIDs = CadenceFocusSupport.defaultSelectedTaskIDs(for: bundle)
            }
        }
    }

    private func toggleMember(_ task: AppTask) {
        if selectedBundleTaskIDs.contains(task.id) {
            selectedBundleTaskIDs.remove(task.id)
        } else {
            selectedBundleTaskIDs.insert(task.id)
        }
    }

    private func toggleTimer() {
        timerState.toggle()
    }

    private func resetTimer() {
        timerState.reset()
    }

    private func complete(_ task: AppTask) {
        CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: modelContext)
        resetTimer()
        if let next = pickItems.first(where: { $0.target != .task(task.id) }) {
            adopt(next)
        } else {
            selectedTarget = nil
            selectedBundleTaskIDs = []
        }
    }

    /// Hand the block's minutes to the ticked members, weighted by estimate, through the one helper
    /// macOS's bundle timer also commits through.
    private func logBundleSession(_ bundle: TaskBundle) {
        CadenceFocusSupport.logElapsedSeconds(
            elapsedSeconds,
            across: CadenceFocusSupport.selectedTasks(in: bundle, selectedTaskIDs: selectedBundleTaskIDs)
        )
        try? modelContext.save()
        resetTimer()
    }
}

// MARK: - Focus chrome

/// iOS counterpart of macOS's `FocusTimerPanel`: a `Theme.surface` panel with an accent rule
/// across its top that brightens while the session runs, the running/paused state named in words,
/// and the clock as the one large thing on the screen.
private struct iOSFocusTimerPanel<Clock: View, Controls: View>: View {
    let accent: Color
    let isRunning: Bool
    let isCompact: Bool
    @ViewBuilder let clock: () -> Clock
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isRunning ? "timer" : "pause.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(isRunning ? "Running" : "Paused")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isRunning ? accent : Theme.dim)

            clock()
                // The glow is the only cue that survives being glanced at from across a desk.
                .shadow(color: accent.opacity(isRunning ? 0.34 : 0), radius: 24)

            controls()
        }
        .padding(isCompact ? 18 : 22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(isRunning ? 0.72 : 0.24))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 6)
    }
}

/// iOS counterpart of macOS's `FocusIconButton`. Circular, tinted, and never smaller than the
/// 44pt touch floor even when the plate itself is drawn smaller.
private struct iOSFocusControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let foreground: Color
    let background: Color
    var diameter: CGFloat = 48
    var glowColor: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter > 56 ? 22 : 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
                .shadow(color: glowColor, radius: 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Touch size of the pick row's transport control. The plate it draws is smaller; this is the part
/// a finger has to hit.
private let iOSFocusTransportSize: CGFloat = 44

/// iOS counterpart of macOS's `FocusPickItemRow`: a leading medallion, the title, one detail line,
/// and the transport control. **One row for both a ready task and a bundle** — a block differs in
/// its tint and its glyph, not in how it is picked or started.
///
/// The two controls are **siblings in an `HStack`**, not a small button layered over a full-width
/// one. Layering is how `iOSHabitsView` does its check-in circle and it works there, but this row
/// declares a `contentShape` over its whole card, so an overlaid button on top of it ended up with
/// the row swallowing the tap: pressing play selected the task and left the clock at 00:00 — the
/// same dead affordance the play glyph was before it became a button at all. Side by side there is
/// no overlap for the hit test to resolve, and no "reserve exactly N points" coupling between the
/// row and the thing sitting on it.
private struct iOSFocusPickRow: View {
    let title: String
    let detail: String
    let tint: Color
    /// `nil` draws the list-colour dot a task row has always shown; a glyph marks a row that is not
    /// a single task.
    let glyph: String?
    let isSelected: Bool
    let isRunning: Bool
    let select: () -> Void
    let toggleSession: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 12) {
                    medallion

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.subdued)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Focus \(title)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: toggleSession) {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRunning ? Theme.onColor : tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isRunning ? tint : tint.opacity(0.14)))
                    .frame(width: iOSFocusTransportSize, height: iOSFocusTransportSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(isRunning ? "Pause \(title)" : "Start focus session for \(title)")
            .padding(.trailing, 4)
        }
        // One selection layer, at the row's own radius: the card fill lifts and a hairline in the
        // row's colour marks the selected row. No second background underneath.
        .cadenceCard(
            background: isSelected ? Theme.surfaceElevated : Theme.surface,
            cornerRadius: Theme.radiusCard,
            shadowRadius: 10,
            shadowY: 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                .opacity(isSelected ? 1 : 0)
        )
    }

    @ViewBuilder
    private var medallion: some View {
        if let glyph {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))
        } else {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Circle().fill(tint).frame(width: 9, height: 9)
            }
            .frame(width: 28, height: 28)
        }
    }
}

/// One member of the block being focused, with the tick that includes it in the time log.
///
/// The three facts and their metrics come from `CadenceBundleTaskRowSupport` /
/// `CadenceBundleTaskRowMetrics`, which is what the macOS focus panel, the timeline inspector and
/// the iOS block sheet all read — those three disagreed about every one of them once, and the
/// shared decision is why they no longer can.
///
/// **The tick is a square, not a circle.** It includes the task in this session's time log; it does
/// not finish it. The circle is the app's completion glyph — it is what the same task's row draws
/// in `iOSCalendarBundleDetailSheet` — so the one control in the app whose leading mark means
/// something else is drawn as a checkbox in the panel's own amber.
private struct iOSFocusBundleMemberRow: View {
    let task: AppTask
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.amber : Theme.dim)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: CadenceBundleTaskRowMetrics.summarySpacing) {
                    Text(task.title.isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: CadenceBundleTaskRowMetrics.titleSize, weight: CadenceBundleTaskRowMetrics.titleWeight))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(CadenceBundleTaskRowMetrics.titleLineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // `includesLoggedTime` — this panel hands the session's minutes to the tasks
                    // you tick, so `45/60m` is the number it is about. Every other bundle member
                    // row states the estimate alone.
                    CadenceTaskDetailLineLabel(
                        parts: CadenceBundleTaskRowSupport.detailParts(for: task, includesLoggedTime: true),
                        fontSize: CadenceBundleTaskRowMetrics.detailSize
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if task.isDone {
                    Text("Done")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(isSelected ? "Exclude from time log" : "Include in time log")
        .accessibilityValue(task.title.isEmpty ? "Untitled Task" : task.title)
    }
}
#endif

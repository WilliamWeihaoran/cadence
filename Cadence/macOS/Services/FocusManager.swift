#if os(macOS)
import AppKit
import Foundation
import OSLog
import SwiftData
import SwiftUI

@Observable
final class FocusManager {
    /// [[T-19095]]: the app's manager keeps its session note in `CadenceDefaults.store`; a test
    /// host (and a UI-test launch) keeps none, so no test's session is resumed into the next
    /// launch -- the gate `CadenceExternalWriteReminderWatch` starts behind.
    static let shared = FocusManager(
        sessionDefaults: NotificationManager.isTestEnvironment ? nil : CadenceDefaults.store
    )

    enum ActiveSession {
        case task(AppTask)
    }

    /// Re-arms the settled-task watch on every assignment (T-5310), so whatever sets the session —
    /// `startFocus`, a deletion, a context swap re-resolving it — is watched without remembering to.
    var activeSession: ActiveSession? = nil {
        didSet {
            watchActiveTaskStatus()
            persistSession()
        }
    }
    var wantsNavToFocus: Bool = false

    /// **T-1103.** The stopwatch itself, and the only copy of it.
    ///
    /// `isRunning` and `elapsed` used to be stored here and *incremented from a view*: the whole
    /// product's single `elapsed +=` was a one-second `onReceive` closure inside `FocusView`,
    /// adding exactly one second per delivery and ignoring the delivery's own timestamp.
    /// `RootDetailContent` builds `FocusView` only for `selection == .focus`,
    /// so navigating to Notes or Calendar tore down the subscriber while this manager still said
    /// `isRunning == true` — the session kept "running" with nothing counting for it, and the
    /// minutes spent away were simply absent from the number `commitElapsed` later banked into
    /// `actualMinutes` and the list's `loggedMinutes`. No failure condition and no unusual data
    /// were needed: leaving the screen and coming back was enough.
    ///
    /// It is a `CadenceFocusTimerState` — the same shape iOS's focus screen has always used —
    /// so elapsed time is *derived* from a start instant rather than accumulated one tick at a
    /// time. A view timer can now only ask for a redraw; it has nothing to add to.
    private var timerState = CadenceFocusTimerState() {
        didSet { persistSession() }
    }

    /// The clock `timerState` is read against. Injectable so a test can advance time by 90 seconds
    /// with zero display ticks and see the session bank 90 seconds — which is the whole claim.
    @ObservationIgnored var clock: () -> Date = { Date() }

    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// Whether system sleep is what stopped the clock, so waking may start it again. A clock the
    /// *user* paused must stay paused across a sleep.
    @ObservationIgnored private var resumesOnWake = false

    /// Where the session note goes ([[T-19095]]); `nil` keeps none. Internal rather than private
    /// so a test builds a manager over its own suite -- `shared` is still the one the app runs.
    init(sessionDefaults: UserDefaults? = nil) {
        self.sessionDefaults = sessionDefaults
        startObservingSystemSleep()
    }

    /// Seconds on the stopwatch now.
    ///
    /// Read-only on purpose. The defect this replaced was a caller *writing* to it once a second;
    /// with no setter there is no second counter for a view to drive, and every reading in the app
    /// comes from one start instant. Tests move `clock`, not this.
    var elapsed: Int {
        elapsedSeconds(at: clock())
    }

    /// The same reading taken at a supplied instant, for a display that refreshes on a tick: the
    /// tick decides *when* to redraw, this decides what the number is. A tick that never arrives
    /// (the screen is not on stage, the main run loop is late) costs a redraw, not a minute.
    func elapsedSeconds(at instant: Date) -> Int {
        timerState.elapsedSeconds(now: instant)
    }

    /// Running or paused. Assigning banks or resumes through `CadenceFocusTimerState.toggle`, so
    /// the play/pause button keeps working as `focusManager.isRunning.toggle()`.
    var isRunning: Bool {
        get { timerState.isRunning }
        set {
            guard newValue != timerState.isRunning else { return }
            timerState.toggle(now: clock())
            resumesOnWake = false
        }
    }

    var activeTask: AppTask? {
        get {
            guard case .task(let task) = activeSession else { return nil }
            return task
        }
        set {
            activeSession = newValue.map { .task($0) }
        }
    }

    /// Begin focusing on a task, navigating to the focus view.
    /// If switching to a different task, commits any accumulated elapsed time first.
    ///
    /// **Throws on a refused switch, and does not switch over one (T-654).** `commitElapsed` now
    /// actually commits (it used to write the pending bank and never call `save()` at all — the
    /// worst of the three shapes this ticket found, since not even a swallowed `try?` sat between
    /// the write and the caller). Starting the new task anyway would show its clock at zero while
    /// the outgoing one's session — still running, un-banked — had nothing left pointing at it.
    func startFocus(
        task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let isSameSession = activeTask?.id == task.id
        if !isSameSession {
            try commitElapsed(in: modelContext, commit: commit)
        }
        activeSession = .task(task)
        // A different task gets a fresh stopwatch; the one already being focused gets its own back.
        if isSameSession { resumeClock() } else { startClock() }
        wantsNavToFocus = true
    }

    /// Commits elapsed seconds into the task's `actualMinutes` **and its list's `loggedMinutes`**.
    /// Pauses and resets the stopwatch so the next session starts fresh.
    ///
    /// This used to add to `actualMinutes` only, so running the timer never moved
    /// `project.loggedMinutes` — which an hours-mode goal reads. Two things made that hard to
    /// notice: macOS's *manual* "log session" sheet does roll up, so typing 25 minutes and
    /// running the timer for 25 minutes produced different totals on the same Mac. It now goes
    /// through the same shared helper iOS uses.
    ///
    /// **It takes a `ModelContext` because banking now inserts.** Since T-621 each increment is a
    /// `FocusSessionLog` row, so this is a pending change and the rule that governs one
    /// (`AGENTS.md`, "The `try? save()` rule") requires the caller to own the commit rather than
    /// this helper to reach for an ambient store. That is why `startFocus` and `endSession` take
    /// one too: they are the frames that bank on the user's behalf.
    ///
    /// **Throws and takes `commit:` now (T-654).** It used to write the bank and stop — no `save()`
    /// of any kind, swallowed or otherwise, which is why `FocusView.timerControls` was held in
    /// `CadenceSaveCommitRule.commitReachExemptions` rather than `existenceExemptions`: there was
    /// no commit for half 1/2 to find. Routes through the same
    /// `CadenceFocusSupport.logElapsedSeconds(_:across:in:commit:)` iOS uses — a single active task
    /// is a one-element credit list — so both platforms share one commit-and-undo shape. `isRunning`
    /// and `elapsed` are only cleared once that commit actually lands.
    func commitElapsed(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        // One reading, taken once. `elapsed` is derived from the clock now, so asking twice — once
        // for the guard and once for the amount — could bank a different number than it checked.
        let seconds = elapsed
        guard seconds > 0 else { return }
        let creditedTasks: [AppTask]
        switch activeSession {
        case .task(let task):
            creditedTasks = [task]
        case nil:
            return
        }
        try CadenceFocusSupport.logElapsedSeconds(seconds, across: creditedTasks, in: modelContext, commit: commit)
        reset()
    }

    /// Leave the current session the way switching to another one leaves it: bank the elapsed
    /// time against the task that earned it, then clear the session.
    ///
    /// Clearing `activeSession` directly is what the close buttons used to do, and it stranded the
    /// stopwatch: `isRunning` stayed `true`, so `FocusView`'s one-second timer kept incrementing
    /// `elapsed` with no session attached — the idle "Pick a task" card showed a clock still
    /// counting up. Picking the next task then called `startFocus`, whose `commitElapsed()` hit the
    /// `case nil` branch and zeroed `elapsed`, so a 25-minute session closed rather than switched
    /// away from logged nothing at all. `startFocus` already commits on a switch; closing is the
    /// same act of leaving a session, so it commits too.
    ///
    /// **Throws, and does not clear the session over a refusal (T-654).** The close button's own
    /// `onClose` names the refusal; leaving `activeSession` alone means the timer is still there,
    /// still running, if the user tries again rather than closing over lost minutes.
    func endSession(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try commitElapsed(in: modelContext, commit: commit)
        activeSession = nil
        reset()
    }

    /// **T-5305.** Bank the running (or paused) session before the app quits.
    ///
    /// The stopwatch lived only in memory, so a Cmd+Q — or an update restart after a sleep, which
    /// pauses the clock but keeps its reading — used to drop every minute not yet banked. Quitting
    /// is leaving the session, so it banks the way `endSession` does, into the context the active
    /// task lives in (`macOSRootDataRefreshSupport.adoptReplacementContext` keeps that the live
    /// one). There is no screen left to name a refusal on, so it is logged; the refused bank has
    /// already been undone by `commitElapsed`. Whether to *warn* before quitting is an owner
    /// decision and is not made here. What no delegate reaches -- a Force Quit, a crash -- is
    /// covered by the session note instead ([[T-19095]], `adoptPersistedSession`).
    func bankBeforeTermination(commit: (ModelContext) throws -> Void = { try $0.save() }) {
        guard let modelContext = activeTask?.modelContext else { return }
        do {
            try commitElapsed(in: modelContext, commit: commit)
        } catch {
            Self.logger.error("Focus session could not be banked on quit: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - T-5310: a session on a task that was finished somewhere else

    /// Bumped on every arm, so a watch armed for an earlier session (or an earlier arm of this one)
    /// drops its callback instead of acting on, or re-arming over, the current one.
    @ObservationIgnored private var statusWatchGeneration = 0

    /// **T-5310.** Watch the focused task's status for as long as it is the session.
    ///
    /// Before this, only `endSession`, task deletion and Log Session's own "Mark task as complete"
    /// (T-5303) ever cleared the session, so ticking the focused task from a list row, the
    /// inspector, the keyboard, the status menu or MCP left a finished task under the "Ready" chip,
    /// and the next ▶ timed it. Hooking each of those writers would be six hooks and a seventh
    /// forgotten; the task's own status is the one thing they all change. The callback runs on
    /// the main actor *after* the write, so a settle that was refused and put back reads open
    /// again by then and nothing is released.
    private func watchActiveTaskStatus() {
        statusWatchGeneration += 1
        guard let task = activeTask else { return }
        let generation = statusWatchGeneration
        withObservationTracking {
            _ = task.statusRaw
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.statusWatchGeneration == generation else { return }
                if !self.releaseIfActiveTaskSettled() {
                    self.watchActiveTaskStatus()
                }
            }
        }
    }

    /// If the focused task is done or cancelled, bank its elapsed time against it and move on the
    /// way Log Session's completion does (T-5303): adopt the next ready task, else end the
    /// session. Returns whether it released the session.
    ///
    /// A refused bank is logged, not shown — the write that finished the task happened on another
    /// screen, and `commitElapsed` has already undone the refused bank. The session still moves
    /// on: a finished task is not something to keep timing.
    @discardableResult
    func releaseIfActiveTaskSettled(commit: (ModelContext) throws -> Void = { try $0.save() }) -> Bool {
        guard let task = activeTask, CadenceTaskQuerySupport.isFinishedTask(task) else { return false }
        let context = task.modelContext
        if let context {
            do {
                try commitElapsed(in: context, commit: commit)
            } catch {
                Self.logger.error("Focus session could not be banked for a finished task: \(error.localizedDescription, privacy: .public)")
            }
        }
        reset()
        activeTask = context.flatMap { Self.nextReadyTask(after: task, in: $0) }
        return true
    }

    /// The same next task `FocusView` offers: the head of `readyTasks`, which ranks on its own.
    private static func nextReadyTask(after task: AppTask, in context: ModelContext) -> AppTask? {
        let all = (try? context.fetch(FetchDescriptor<AppTask>())) ?? []
        return FocusSessionSupport.readyTasks(from: all, todayKey: DateFormatters.todayKey())
            .first { $0.id != task.id }
    }

    @ObservationIgnored private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "FocusManager")

    func reset() {
        timerState.reset()
        resumesOnWake = false
    }

    /// Put the stopwatch back to zero and start it from now, for a session that is genuinely a
    /// *different* one. `commitElapsed` has already reset the clock on every path that banked
    /// anything, so the `reset()` here is the defensive half: it is what stops a new session
    /// inheriting the previous one's start instant on the `elapsed == 0` path, where `commitElapsed`
    /// had nothing to bank and returned early.
    private func startClock() {
        timerState.reset()
        timerState.toggle(now: clock())
        resumesOnWake = false
    }

    /// Start the clock again **without** zeroing it.
    ///
    /// The hover ▶ on a task row calls `startFocus` for whatever task it belongs to, including the
    /// one already being focused (`FocusSidebar` filters the current task out of its list;
    /// `MacTaskRow.focusButtonSlot` does not). Before this ticket that path read
    /// `isRunning = true` on an unchanged session and left `elapsed` alone, so pressing ▶ on the
    /// task you were already focusing resumed a paused clock and did nothing to a running one.
    /// Zeroing it here instead would discard minutes that were never banked — a data loss T-1103
    /// had no business introducing while fixing a different one.
    private func resumeClock() {
        guard !timerState.isRunning else { return }
        timerState.toggle(now: clock())
        resumesOnWake = false
    }

    // MARK: - [[T-19095]]: a session that outlives a Force Quit or a crash

    @ObservationIgnored private let sessionDefaults: UserDefaults?
    @ObservationIgnored private var heartbeat: Timer?
    /// Held while `adoptPersistedSession` sets the subject and the clock one after the other, so
    /// the half-set state between them never reaches disk.
    @ObservationIgnored private var holdsPersistence = false

    /// How often a running session re-stamps its record's `lastSeenAt`.
    static let sessionHeartbeatInterval: TimeInterval = 60

    /// **The Mac half of [[T-6001]].** `bankBeforeTermination` runs from `applicationWillTerminate`,
    /// which no Force Quit, crash or signal reaches, so the clock -- held only here in memory -- went
    /// with the process and the relaunch showed no session. Every change to the subject or the clock
    /// now writes the shared `CadenceFocusSessionRecord` (an idle clock removes it), exactly as
    /// `CadenceFocusSessionOwner` does on iOS, and `adoptPersistedSession` puts it back at launch.
    /// Like iOS this persists and never banks: minutes still reach the store only through
    /// `commitElapsed`, and a clean quit's bank resets the clock, which removes the note.
    ///
    /// **`lastSeenAt` is "this process was alive then", stamped on every write and by a heartbeat
    /// while the clock runs.** iOS learns of an absence from `scenePhase` leaving the foreground,
    /// which precedes any eviction; a Mac app gets no such event before a Force Quit or a crash,
    /// so the last instant it was known alive has to be written while it is. That is the only
    /// difference, and it is the hardware/OS constraint: the resume rule is iOS's own.
    private func persistSession() {
        guard let sessionDefaults, !holdsPersistence else { return }
        let now = clock()
        CadenceFocusSessionPersistence.write(
            CadenceFocusSessionPersistence.record(
                target: activeTask.map { .task($0.id) },
                state: timerState,
                lastSeenAt: now
            ),
            to: sessionDefaults,
            key: CadencePreferenceKeys.macFocusSession
        )
        updateHeartbeat()
    }

    /// One heartbeat: re-stamp the running session as seen now. Callable so a test steps it
    /// without a run loop.
    func noteSessionSeen() {
        guard timerState.isRunning else { return }
        persistSession()
    }

    private func updateHeartbeat() {
        guard timerState.isRunning else {
            heartbeat?.invalidate()
            heartbeat = nil
            return
        }
        guard heartbeat == nil else { return }
        let timer = Timer(timeInterval: Self.sessionHeartbeatInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.noteSessionSeen()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// **Puts back the session a Force Quit or a crash left on disk**, called by the root view as
    /// it appears, before anything can start a session of its own.
    ///
    /// Through `CadenceFocusSessionPersistence.resumed` -- iOS's resume, unchanged: a task gone,
    /// done or cancelled resolves to nothing and the note is cleared without banking (T-276), and
    /// a gap since the last heartbeat longer than `CadenceFocusAbsenceRule.unobservedGapThreshold`
    /// brings the session back **paused at the last instant it was seen** ([[T-6223]]), so a crash
    /// at night does not reopen crediting the night. A shorter gap resumes live, as iOS's does.
    ///
    /// **The cold route only**: a session already in memory is the live one.
    func adoptPersistedSession(in modelContext: ModelContext) {
        guard let sessionDefaults, activeSession == nil, !timerState.isRunning,
              timerState.accumulatedSeconds == 0,
              let record = CadenceFocusSessionPersistence.read(
                  from: sessionDefaults,
                  key: CadencePreferenceKeys.macFocusSession
              ) else { return }
        let taskID = record.taskID
        let tasks = (try? modelContext.fetch(
            FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == taskID })
        )) ?? []
        guard let resumed = CadenceFocusSessionPersistence.resumed(from: record, tasks: tasks, now: clock()),
              let task = tasks.first else {
            CadenceFocusSessionPersistence.clear(in: sessionDefaults, key: CadencePreferenceKeys.macFocusSession)
            return
        }
        holdsPersistence = true
        timerState = resumed.state
        resumesOnWake = false
        activeSession = .task(task)
        holdsPersistence = false
        persistSession()
    }

    // MARK: - System sleep

    /// **T-1103, the other half of the policy.** Navigating away no longer stops the clock — but
    /// the clock is wall-clock now, so without this a lid closed overnight would come back reading
    /// fourteen hours of "focus" and offer to log it. The view-owned tick never did that, because
    /// a `Timer` does not fire while the machine is asleep, and preserving that is not a new rule:
    /// it is the behaviour the fix would otherwise have quietly changed.
    ///
    /// Sleeping **pauses** the session — it banks nothing, the reading is kept in memory — and
    /// waking starts it again, only if sleep is what stopped it. (This said "banks" until T-5305;
    /// it never did. A quit after a sleep is covered by `bankBeforeTermination`.)
    func startObservingSystemSleep() {
        guard sleepObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }
    }

    /// The freeze is `CadenceFocusAbsenceRule.frozen`, the rule iOS applies past its unobserved-gap
    /// threshold ([[T-6223]]); sleep is an explicit signal, so the Mac's threshold is zero.
    func handleSystemWillSleep() {
        guard timerState.isRunning else { return }
        timerState = CadenceFocusAbsenceRule.frozen(timerState, at: clock())
        resumesOnWake = true
    }

    func handleSystemDidWake() {
        guard resumesOnWake, !timerState.isRunning else { return }
        timerState.toggle(now: clock())
        resumesOnWake = false
    }
}
#endif

import Foundation
import Observation
import SwiftData

/// **[[T-15548]]: iOS's one Focus session, held for the app rather than for the screen.**
///
/// The session used to live in `iOSFocusView`'s own `@State`, so the view's teardown was the
/// session's: backing out of Focus, or picking another iPad sidebar destination, banked the minutes
/// and put the clock back at 00:00. The Mac's session is the app-wide `FocusManager.shared`, and
/// [[T-1103]] made leaving the Focus page keep it running on purpose. Nothing about a touch screen
/// asks for the difference, so under [[T-8201]] it was drift. This is the iOS counterpart of that
/// owner: the screen reads and writes its clock here, and leaving the screen ends nothing. The
/// session ends only on the screen's own paths — Log Session, Discard, a switch to another subject
/// — or when its task is finished elsewhere.
///
/// It is **not** a second timer authority beside `FocusManager` (T-242): macOS never reads it, and
/// it holds no tick. Every rule it applies is the shared one the screen already used —
/// `CadenceFocusAbsenceRule` for an unobserved gap ([[T-6223]]), `CadenceFocusSessionPersistence`
/// for eviction ([[T-6001]]), `CadenceFocusSupport.releaseIfSettled` for a finished subject
/// ([[T-12691]]).
@MainActor
@Observable
final class CadenceFocusSessionOwner {
    static let shared = CadenceFocusSessionOwner()

    /// The subject the screen is pointing at, `nil` for "the head of the ready list".
    var selectedTarget: CadenceFocusTarget?
    var timerState = CadenceFocusTimerState()
    /// **[[T-6223]].** When the app last left the foreground, `nil` while it is in front. It rides
    /// in the persisted record, so a resume after eviction can measure the gap, and is read back on
    /// return so a suspended-not-evicted app measures the same one.
    var lastSeenAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    /// How many Focus screens are standing. While one is, the screen's own
    /// `.onChange(of: selectedSubjectIsSettled)` answers a finished subject; the watch below covers
    /// only the stretch where none is, and a count rather than a flag because a size-class change
    /// can build the new screen before the old one has gone.
    @ObservationIgnored private var standingScreens = 0
    /// Bumped whenever the settle watch is re-armed or stood down, so a superseded callback drops
    /// itself instead of acting — `FocusManager.watchActiveTaskStatus`'s shape.
    @ObservationIgnored private var settleWatchGeneration = 0
    /// The subject the watch is on, held here rather than captured, because the watch's callback
    /// is `@Sendable` and a model is not.
    @ObservationIgnored private var watchedTask: AppTask?

    init(defaults: UserDefaults = CadenceDefaults.store, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
    }

    /// Whether there is a clock to bank: running, or paused over a reading. What the session
    /// header's close control ([[T-15572]]) is drawn on.
    var hasLiveSession: Bool {
        timerState.isRunning || timerState.accumulatedSeconds > 0
    }

    // MARK: - [[T-15572]]: the session header's close

    /// **The Mac's one-tap "bank and end", on iOS** — `FocusManager.endSession(in:)`, which the Mac
    /// session header's close button calls. The elapsed seconds are banked against `subject` by the
    /// shared `CadenceFocusSupport.endSession` (rounded to the nearest minute; under one writes
    /// nothing), then the clock is reset, the subject released and the persisted record cleared,
    /// so the screen falls back to the head of the ready list at 00:00. No confirmation, as on the
    /// Mac: nothing is thrown away — Discard is the control that does that.
    ///
    /// **Throws, and ends nothing over a refusal** (T-654's rule, the Mac's too): the clock,
    /// subject and record are left exactly as they were so the session is still there to retry.
    func endSession(
        leaving subject: CadenceFocusSubject?,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        timerState = try CadenceFocusSupport.endSession(
            leaving: subject,
            state: timerState,
            modelContext: modelContext,
            now: clock(),
            commit: commit
        )
        selectedTarget = nil
        CadenceFocusSessionPersistence.clear(in: defaults)
    }

    // MARK: - [[T-18514]]: the subject deleted

    /// Whether deleting `taskIDs` takes this session's subject with it. Asked by the shared delete
    /// core **before** the rows go, as the Mac's `deferFocusTeardown` asks `FocusManager`: after
    /// the commit there is no row left to compare against.
    func isSubject(amongDeleted taskIDs: Set<UUID>) -> Bool {
        guard let subjectID = selectedTarget?.taskID else { return false }
        return taskIDs.contains(subjectID)
    }

    /// **The Mac's delete teardown, on iOS** -- `FocusManager.activeSession = nil` and `reset()`.
    /// Run by the shared delete core only once the delete has committed. Nothing is banked: the
    /// task the seconds would be logged against is gone. The clock goes to zero, the subject is
    /// released so the screen falls back to the head of the ready list, the record is cleared so
    /// an eviction does not resume a session against nothing, and the settle watch is stood down
    /// because the row it observes is deleted.
    func endSessionForDeletedSubject() {
        standDownSettleWatch()
        timerState.reset()
        selectedTarget = nil
        CadenceFocusSessionPersistence.clear(in: defaults)
    }

    /// **[[T-19093]]: the subject deleted on another device.** A CloudKit import's delete never
    /// passes through the delete core, so nothing called `endSessionForDeletedSubject()` and the
    /// screen fell to "No session selected" under a header still reading "Session running". The
    /// screen asks this when its subject stops resolving; the store, not the screen's query, decides,
    /// and the teardown is the delete core's -- nothing banked. Returns whether it ended the session.
    @discardableResult
    func endSessionIfSubjectGone(in modelContext: ModelContext) -> Bool {
        guard let subjectID = selectedTarget?.taskID,
              CadenceFocusSupport.subjectIsGone(taskID: subjectID, in: modelContext) else { return false }
        endSessionForDeletedSubject()
        return true
    }

    // MARK: - [[T-18252]]: the Log Session form's two exits

    /// **Log Session's confirm, run here rather than on the screen** ([[T-18252]]). The form is
    /// presented by the root's `iOSPageEditorHost`, because an iPad size-class swap rebuilds the
    /// Focus screen and SwiftUI dismisses a sheet its view presented, typed figures and all; its
    /// confirm therefore cannot close over the screen, which may be a different instance by the
    /// time it is tapped.
    ///
    /// The write is the shared `CadenceFocusSupport.logSession` ([[T-8732]]). **The clock is cleared
    /// only once the store has the session (T-636(c))**: a refusal throws before anything here
    /// moves, so the seconds and the form are both still there to retry. A ticked "Mark task as
    /// complete" moves the session to the next ready task, else to nothing -- macOS's rule; logging
    /// without completing leaves it on the same task.
    func logSession(
        hours: Int,
        minutes: Int,
        complete: Bool,
        task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceFocusSupport.logSession(
            hours: hours,
            minutes: minutes,
            complete: complete,
            task: task,
            modelContext: modelContext,
            commit: commit
        )
        timerState.reset()
        if complete {
            selectedTarget = nextReadyTarget(after: task, in: modelContext)
        }
        writeRecord()
    }

    /// **The form's Discard** -- the Mac's: the stopwatch is thrown away and nothing is banked.
    func discardSession() {
        timerState.reset()
        writeRecord()
    }

    /// The head of the ready list other than `task`, read from the store the way the screen's
    /// `@Query` reads it, so the move-on is the same with the screen standing or not.
    private func nextReadyTarget(after task: AppTask, in modelContext: ModelContext) -> CadenceFocusTarget? {
        let tasks = (try? modelContext.fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let todayKey = DateFormatters.todayKey()
        return CadenceFocusPickItem.filtered(
            tasks: CadenceFocusSupport.readyTasks(from: tasks, todayKey: todayKey),
            query: "",
            todayKey: todayKey,
            limit: nil
        )
        .first { $0.target != .task(task.id) }?
        .target
    }

    /// The record for the session as it now stands -- removed when the clock is at zero. The
    /// screen's own writer says the same thing while it stands; this covers a swap's gap.
    private func writeRecord() {
        CadenceFocusSessionPersistence.write(
            CadenceFocusSessionPersistence.record(target: selectedTarget, state: timerState, lastSeenAt: lastSeenAt),
            to: defaults
        )
    }

    // MARK: - The screen coming and going

    func screenDidAppear() {
        standingScreens += 1
        standDownSettleWatch()
    }

    /// **Leaving the screen ends nothing** — the whole of [[T-15548]]. The clock keeps its reading
    /// and the persisted record stays, exactly as the Mac's session survives a page change. What
    /// the screen can no longer do while it is gone is notice its subject being finished somewhere
    /// else, so that watch is handed here.
    func screenDidDisappear(leaving subject: CadenceFocusSubject?) {
        standingScreens = max(0, standingScreens - 1)
        watchForSettle(subject)
    }

    // MARK: - [[T-6223]]: the foreground coming and going

    /// Notes the instant and banks nothing: a glance at another app is not the end of a session
    /// ([[T-6001]] declined that). Called by the root view, so it runs with the screen gone too.
    func leaveForeground() {
        lastSeenAt = clock()
        persistLiveSession()
    }

    /// The same absence rule a cold resume applies, so an app iOS merely suspended overnight does
    /// not credit the night either.
    func returnToForeground() {
        timerState = CadenceFocusAbsenceRule.afterAbsence(timerState, lastSeenAt: lastSeenAt, now: clock())
        lastSeenAt = nil
        persistLiveSession()
    }

    // MARK: - [[T-18715]]: adopting the record when the app comes to the front

    /// **Puts the session an eviction left on disk back in memory as the app comes to the front**,
    /// not when Focus is next opened. Called by the root view on its first appearance and on each
    /// return to `.active`, ahead of `returnToForeground`.
    ///
    /// Until this ran at the front, the record was read only by the Focus screen's
    /// `restorePersistedSession`, so the time spent in the app before opening Focus was never
    /// noted as seen: the absence rule measured from the backgrounding *before* the eviction to
    /// the moment Focus opened, and froze a session the warm path keeps running -- 9:10 evicted,
    /// 10:30 reopened, Focus at 11:30 read "paused at 0:10" instead of a running 2:30:00. Adopting
    /// here applies the rule to the real gap (9:10..10:30), clears `lastSeenAt` because the app is
    /// in front now, and rewrites the record with it cleared, exactly as `returnToForeground` does
    /// for a suspended-not-evicted app. The subject also becomes visible to everything that asks
    /// the owner -- the delete core's `isSubject(amongDeleted:)` and the settle watch, armed
    /// here because no screen has appeared to arm it.
    ///
    /// **The cold route only**, as on the screen: a clock already in memory is the live session.
    /// The record is read before anything is fetched, so a launch with no session costs a
    /// defaults read. A record whose task is gone, done or cancelled is cleared without banking --
    /// `CadenceFocusSessionPersistence.resumed`'s rule (T-276), unchanged.
    func adoptPersistedSession(in modelContext: ModelContext) {
        guard !hasLiveSession,
              let record = CadenceFocusSessionPersistence.read(from: defaults) else { return }
        let taskID = record.taskID
        let tasks = (try? modelContext.fetch(
            FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == taskID })
        )) ?? []
        guard let resumed = CadenceFocusSessionPersistence.resumed(from: record, tasks: tasks, now: clock()) else {
            CadenceFocusSessionPersistence.clear(in: defaults)
            return
        }
        selectedTarget = resumed.target
        timerState = resumed.state
        lastSeenAt = nil
        persistLiveSession()
        if let task = tasks.first {
            watchForSettle(.task(task))
        }
    }

    /// The screen's `.onChange(of: sessionRecord)` is the writer while it stands; with it gone the
    /// sighting has to reach the record from here or an eviction would forget it. **Never clears**:
    /// an empty clock in memory may simply be a cold launch that has not visited Focus yet, whose
    /// record on disk is the session.
    private func persistLiveSession() {
        guard let record = CadenceFocusSessionPersistence.record(
            target: selectedTarget,
            state: timerState,
            lastSeenAt: lastSeenAt
        ) else { return }
        CadenceFocusSessionPersistence.write(record, to: defaults)
    }

    // MARK: - [[T-12691]] with the screen gone

    private func standDownSettleWatch() {
        settleWatchGeneration += 1
        watchedTask = nil
    }

    private func watchForSettle(_ subject: CadenceFocusSubject?) {
        standDownSettleWatch()
        guard standingScreens == 0, hasLiveSession, case .task(let task)? = subject else { return }
        watchedTask = task
        let generation = settleWatchGeneration
        withObservationTracking {
            _ = task.statusRaw
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // A screen appearing stands the watch down, so a standing screen's own release is the only one.
                guard let self, self.settleWatchGeneration == generation,
                      let task = self.watchedTask else { return }
                if !self.releaseIfSettled(task) {
                    self.watchForSettle(.task(task))
                }
            }
        }
    }

    /// Bank a finished subject's seconds against it at the moment it was finished and end the
    /// session, as the Mac's `FocusManager.releaseIfActiveTaskSettled` does. The next visit to
    /// Focus adopts the head of the ready list, which is where the screen's own release would have
    /// moved on to. A refused bank is named and the clock still stops: a finished task is not
    /// something to keep timing.
    @discardableResult
    func releaseIfSettled(
        _ task: AppTask,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard let context = task.modelContext,
              let release = CadenceFocusSupport.releaseIfSettled(
                  .task(task),
                  state: timerState,
                  readyItems: [],
                  modelContext: context,
                  now: clock(),
                  commit: commit
              ) else { return false }
        if release.bankRefused {
            CadenceTaskSettleFailureCenter.shared.record()
        }
        timerState = release.state
        selectedTarget = nil
        CadenceFocusSessionPersistence.clear(in: defaults)
        return true
    }
}

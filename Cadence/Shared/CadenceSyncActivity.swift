import Foundation

/// What CloudKit mirroring has actually *done*, as opposed to whether it *could* — the second half
/// of "is iCloud working", and the half this app had no answer for at all.
///
/// **Why this is beside `CadenceSyncHealth` and not inside it (T-2000).** The two types answer
/// different questions and folding them together would make the existing banner lie in both
/// directions. `CadenceSyncHealth` is a *capability* verdict: which store this launch opened, what
/// `CKAccountStatus` says, whether this device subscribed to change pushes. Every one of those is
/// a precondition, known synchronously, and a bad answer means nothing can sync. This is a
/// *history* verdict: when a pass last completed and whether it failed. A healthy capability
/// verdict over a store that has never imported anything is exactly the state the owner was in
/// when they filed this — iOS stopped talking to CloudKit at 19:25:39Z while the Mac carried on to
/// 19:45:34Z, and every in-app surface said "iCloud available" throughout.
///
/// Merging them would have two costs, and both are real rather than theoretical:
///
/// - **Upwards.** A single transient failure would turn the banner red. The one real error in a
///   week of the owner's logs was a `RecordSave` / `BAD_REQUEST` on `_pcs_data` lasting 105 ms,
///   surrounded by successful operations in the same second — a key-setup race, not a
///   misconfiguration. `CadenceSyncHealth.level` drives `badgeTitle` and the startup banner;
///   "Not syncing" is not what that was.
/// - **Downwards.** An empty history would have to resolve to *something*, and the only honest
///   answer — "nothing has happened yet" — is not a point on `CadenceSyncHealthLevel`'s scale,
///   which runs from `syncing` to `notSyncing` with no room for "no news". It would be rendered
///   as whichever end of the scale the fold picked, and both are wrong.
///
/// So: two types, two rows, one card. The capability row keeps its own verdict and its own tone;
/// this one states the timeline underneath it.
nonisolated enum CadenceSyncActivityPhase: CaseIterable, Hashable, Sendable {
    /// `NSPersistentCloudKitContainer` preparing the store's CloudKit schema and subscriptions.
    /// Distinct from the two below because a setup failure means the *other two never run*,
    /// which reads completely differently from an import that was attempted and refused.
    case setup
    /// A pass pulling this device's changes down from CloudKit.
    case `import`
    /// A pass pushing this device's changes up to CloudKit.
    case export

    /// Sentence case, for a headline: "Setup failed", "Import failed".
    var noun: String {
        switch self {
        case .setup: return "Setup"
        case .import: return "Import"
        case .export: return "Export"
        }
    }

    /// Lower case, for mid-sentence use: "Last import", "No export yet".
    var lowercasedNoun: String {
        switch self {
        case .setup: return "setup"
        case .import: return "import"
        case .export: return "export"
        }
    }
}

/// One mirroring pass, in the terms this app cares about.
///
/// A platform-neutral mirror of `NSPersistentCloudKitContainer.Event`, the same way
/// `CadenceCloudAccountState` mirrors `CKAccountStatus`. The translation happens once, in
/// `CadenceCloudKitMirroringEventStream`, so that everything below here — the fold, the summary,
/// the copy, and every test over them — is reachable without a CloudKit container, without an
/// iCloud account, and without a store.
///
/// `identifier` is load-bearing and is not decoration. **CloudKit posts each pass twice**: once
/// when it begins, with `endDate == nil`, and once when it ends, carrying the same identifier. A
/// reader that treats those as two events leaves the begin-half in flight forever, so a device
/// that finished importing an hour ago still renders "Syncing now".
nonisolated struct CadenceSyncActivityEvent: Equatable, Sendable {
    let identifier: UUID
    let phase: CadenceSyncActivityPhase
    let startDate: Date
    /// `nil` while the pass is still running.
    let endDate: Date?
    /// CloudKit reports `false` on an unfinished pass as well as a failed one, so this is only
    /// meaningful once `endDate` is set. `CadenceSyncActivitySummary` never reads it without
    /// checking.
    let succeeded: Bool
    let errorDescription: String?

    init(
        identifier: UUID = UUID(),
        phase: CadenceSyncActivityPhase,
        startDate: Date,
        endDate: Date? = nil,
        succeeded: Bool = false,
        errorDescription: String? = nil
    ) {
        self.identifier = identifier
        self.phase = phase
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }

    var isFinished: Bool { endDate != nil }
}

/// The reader: what the stream of events adds up to.
///
/// A fold rather than a query over a stored array, for two reasons. It is O(1) in memory, so a
/// long-running Mac cannot accumulate a day of passes; and more importantly a cap on a stored
/// array is a cap on the *answer* — trim the oldest hundred events and the last successful import
/// can go with them, leaving a surface that says "No import yet" about a device that imported this
/// morning.
///
/// **The three rules, each of which is a decision rather than an implementation detail:**
///
/// 1. `lastSuccess(_:)` is the most recent **successful, finished** pass of that phase. Not the
///    most recent attempt: "Last import 3:25 PM" has to mean data arrived at 3:25, or the line is
///    worse than no line.
/// 2. `failure(_:)` is set when the most recent **finished** pass of that phase failed — per
///    phase, and only the latest one. A failure that a later success in the same phase superseded
///    is not reported, which is what keeps a 105 ms transient from painting the card amber for the
///    rest of the launch. A failure in one phase is **not** cleared by a success in another: an
///    export that is failing while imports succeed is precisely the asymmetry the owner needed to
///    see and could not.
/// 3. `observedEventCount == 0` is its own state, and the copy for it shares no wording with the
///    healthy state. "Nothing has happened yet" and "everything succeeded" are the two readings a
///    status surface is most likely to render identically, and a surface that does is worse than
///    none: it is the failure being reported as its own absence.
nonisolated struct CadenceSyncActivitySummary: Equatable, Sendable {
    /// Notifications observed, not passes completed — CloudKit posts twice per pass, so a single
    /// finished import counts 2. It is a "has anything at all happened" flag with a number
    /// attached, and nothing reads it as a pass count.
    private(set) var observedEventCount: Int
    /// The latest **finished** pass per phase, successful or not. Rule 2 reads this.
    private(set) var latestFinished: [CadenceSyncActivityPhase: CadenceSyncActivityEvent]
    /// The end date of the latest **successful** pass per phase. Rule 1 reads this.
    private(set) var latestSuccessDates: [CadenceSyncActivityPhase: Date]
    /// Passes that have begun and not yet reported an end, keyed by identifier so the end half
    /// can retire the right one.
    private(set) var runningEventPhases: [UUID: CadenceSyncActivityPhase]

    static let empty = CadenceSyncActivitySummary(
        observedEventCount: 0,
        latestFinished: [:],
        latestSuccessDates: [:],
        runningEventPhases: [:]
    )

    /// True once anything at all has been observed, including a pass still in flight.
    var hasHistory: Bool { observedEventCount > 0 }

    /// When the latest successful pass of `phase` ended, or `nil` if there has never been one.
    func lastSuccess(_ phase: CadenceSyncActivityPhase) -> Date? { latestSuccessDates[phase] }

    /// Why the latest finished pass of `phase` failed, or `nil` if it did not fail.
    ///
    /// A failed pass that carried no error still returns a sentence. CloudKit's `Event.error` is
    /// optional and a `succeeded == false` with a `nil` error is the one shape that would let a
    /// real failure fall out of the summary entirely.
    func failure(_ phase: CadenceSyncActivityPhase) -> String? {
        guard let event = latestFinished[phase], !event.succeeded else { return nil }
        if let errorDescription = event.errorDescription, !errorDescription.isEmpty {
            return errorDescription
        }
        return "CloudKit reported no reason."
    }

    /// Every failing phase, in declaration order so the line is stable between renders.
    var failingPhases: [CadenceSyncActivityPhase] {
        CadenceSyncActivityPhase.allCases.filter { failure($0) != nil }
    }

    /// Phases with a pass in flight right now.
    var phasesInProgress: Set<CadenceSyncActivityPhase> { Set(runningEventPhases.values) }

    var isWorking: Bool { !runningEventPhases.isEmpty }

    /// Folds one event in. Order-independent for the parts that matter: a late-delivered older
    /// event cannot overwrite a newer answer, because both `latestFinished` and
    /// `latestSuccessDates` only move forward in `endDate`.
    func applying(_ event: CadenceSyncActivityEvent) -> CadenceSyncActivitySummary {
        var result = self
        result.observedEventCount += 1

        guard let endDate = event.endDate else {
            result.runningEventPhases[event.identifier] = event.phase
            return result
        }

        result.runningEventPhases[event.identifier] = nil

        let previousEnd = result.latestFinished[event.phase]?.endDate
        if previousEnd == nil || previousEnd! <= endDate {
            result.latestFinished[event.phase] = event
        }

        if event.succeeded {
            let previousSuccess = result.latestSuccessDates[event.phase]
            if previousSuccess == nil || previousSuccess! <= endDate {
                result.latestSuccessDates[event.phase] = endDate
            }
        }

        return result
    }

    /// The whole history at once. Used by tests and by anything replaying a recorded stream;
    /// the live log folds events in one at a time as they arrive.
    static func summarize(_ events: [CadenceSyncActivityEvent]) -> CadenceSyncActivitySummary {
        events.reduce(.empty) { $0.applying($1) }
    }
}

// MARK: - Copy

extension CadenceSyncActivitySummary {
    /// The row's title. Deliberately a different sentence in every state — see rule 3.
    var headline: String {
        guard hasHistory else { return "No sync activity yet" }
        let failing = failingPhases
        if failing.count == 1 { return "\(failing[0].noun) failed" }
        if failing.count > 1 { return "iCloud sync is failing" }
        if isWorking { return "Syncing now" }
        return "iCloud sync is running"
    }

    /// The line this ticket exists to produce:
    /// *"Last import 3:25 PM · Last export 3:45 PM · No errors"*.
    ///
    /// `now` and `calendar` are parameters rather than reads of the clock for the [[T-1115]]
    /// reason — a surface whose copy depends on the host's longitude is a surface whose tests pass
    /// on the author's. They are also what makes the stale half of the owner's report visible:
    /// a bare "7:25 PM" on a stamp from four days ago is the same string as one from four minutes
    /// ago, and the four-day-old one is the entire defect.
    func statusLine(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard hasHistory else {
            // Shares no phrase with any other state. In particular it does not say "no errors",
            // which would be true and completely misleading.
            return "Cadence has not seen iCloud start, import or export since it launched."
        }

        var segments = [CadenceSyncActivityPhase.import, .export].map { phase -> String in
            guard let date = lastSuccess(phase) else { return "No \(phase.lowercasedNoun) yet" }
            let stamp = CadenceSyncActivityStamp.string(
                for: date,
                now: now,
                calendar: calendar,
                locale: locale
            )
            return "Last \(phase.lowercasedNoun) \(stamp)"
        }

        let failing = failingPhases
        if failing.isEmpty {
            segments.append(isWorking ? "Syncing now" : "No errors")
        } else {
            // Named per phase, so a setup failure cannot be read as an import failure. They mean
            // opposite things: setup failing means the other two never ran at all.
            segments.append(contentsOf: failing.map { "\($0.noun) failed: \(failure($0) ?? "")" })
        }

        return segments.joined(separator: " · ")
    }

    var tone: CadenceSyncHealthTone {
        // Not `.positive`. An empty history is no news, and no news rendered green is the lie
        // this whole type is here to stop telling.
        guard hasHistory else { return .neutral }
        if !failingPhases.isEmpty { return .caution }
        if isWorking { return .info }
        return .positive
    }

    /// Distinct from every glyph `CadenceSyncHealth` uses, so the two rows of one card cannot be
    /// mistaken for each other at a glance.
    var iconName: String {
        guard hasHistory else { return "clock.badge.questionmark" }
        if !failingPhases.isEmpty { return "exclamationmark.arrow.triangle.2.circlepath" }
        if isWorking { return "arrow.triangle.2.circlepath" }
        return "clock.arrow.circlepath"
    }
}

/// "3:25 PM", "yesterday 3:25 PM", "4 days ago".
///
/// Built from `calendar`'s own components and `TimeFormatters`, with **no `DateFormatter`
/// anywhere**, which is not only the house rule — it is what lets the caller's `calendar` be the
/// single source of the time zone. A shared `DateFormatter` reads `TimeZone.current` whatever
/// calendar it is handed, so a stamp assembled from both would be two zones in one string.
///
/// Anything older than yesterday drops the clock time entirely. "Last import 3:25 PM" four days
/// after the fact is not a stale reading, it is a wrong one; "4 days ago" is the answer the owner
/// spent half an hour in the CloudKit Console to get.
nonisolated enum CadenceSyncActivityStamp {
    static func string(
        for date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let time = TimeFormatters.timeString(from: minutes, locale: locale)

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        // A stamp from the future is clock skew between this device and CloudKit, not a date to
        // narrate. Show the time and say nothing about the day.
        case ..<0: return time
        case 0: return time
        case 1: return "yesterday \(time)"
        default: return "\(days) days ago"
        }
    }
}

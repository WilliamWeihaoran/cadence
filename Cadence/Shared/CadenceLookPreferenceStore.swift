import Foundation
import SwiftData

/// Reading and writing the synced look (T-1307, [[T-1288]]).
///
/// Everything above `MARK: - Writing` is pure, so `CadenceLookPreferenceTests` can pin the pair
/// grammar, the duplicate rule, the two vocabularies and the don't-clobber rule without a model
/// container and without a second device.
///
/// ## Two layers, and why the local one is not removed
///
/// Every surface that draws one of these settings reads the device-local default it has always
/// read — `@AppStorage("allTasksSortField")`, `CadencePreferenceKeys.sidebarTabColors`, the
/// app-group `cadence.appearance.accentPaletteID`. That layer is synchronous, reachable from the
/// widget process, and already correct; replacing it with a `@Query` at thirty call sites would
/// have been the change, not the feature. So the record is the **source of truth across devices**
/// and the local default is its **mirror on this one**, and `CadenceLookPreferenceSync` is the
/// single thing that carries values between them: the record is read *down* whenever it changes,
/// and the mirrors are written *up* whenever one of them changes.
///
/// ## The two platforms' sort vocabularies, and what a phone does with a direction
///
/// macOS's All Tasks and Inbox store a `TaskSortField` **and** a `TaskSortDirection`; iOS stores
/// one `CadenceTaskSortMode`. They are the **same setting**, and that is not a new judgement:
/// T-606 already mapped one onto the other for Today, read off the two comparators rather than the
/// two labels, and pinned the mapping in
/// `TaskOrderingTests.everyMigratedMacOSTodaySortModeAgreesWithItsRetiredComparator`. This reuses
/// `CadenceTaskSortMode.migratedFromMacOSTodaySortField` rather than writing a second mapping.
///
/// `CadenceTaskSortMode` is the canonical value because it is the vocabulary that survives the
/// round trip: it names do-date and due-date separately, which macOS's single `Date` cannot.
/// Direction is stored **beside** it under its own key and is written only by the platform that
/// has the control — so a phone changing All Tasks' sort leaves `allTasks.direction` exactly as
/// the Mac left it, and a Mac that chose *Priority, Ascending* keeps drawing low-priority-first
/// while the phone, which has no such mode, draws high-first. The setting is shared as far as both
/// devices can express it and the remainder is preserved rather than reset.
///
/// The other direction is the dangerous one and is handled by
/// ``publishedPairs(currentMirrors:stored:on:)``. A Mac shown a stored `.dueDate` has no field for
/// it and projects it onto `Date` — the nearest of its three — so the two devices very nearly
/// agree. If the Mac then wrote that projection back it would silently destroy the phone's choice,
/// which is precisely the failure this ticket was warned about. It does not: a mirror whose value
/// is *already the projection of what is stored* is treated as unchanged and the stored mode is
/// left alone. The Mac overwrites a mode only when the user has actually moved the chip somewhere
/// other than where it was drawn.
///
/// Unknown pairs survive the same way, and more cheaply: a publish starts from the stored map and
/// overrides only the keys this platform owns, so `allTasks.showCompleted` — an iOS key with no
/// macOS control — rides through a Mac's write untouched.
enum CadenceLookPreferenceStore {

    // MARK: - The pair grammar

    /// `key=value` pairs joined by `;`. Blank and malformed segments are skipped; a repeated key
    /// keeps the last spelling, so the map is a function however the string was assembled.
    static func pairs(fromRaw raw: String) -> [String: String] {
        raw.split(separator: ";").reduce(into: [String: String]()) { partial, segment in
            guard let separator = segment.firstIndex(of: "=") else { return }
            let key = String(segment[segment.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(segment[segment.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }
    }

    /// Keys sorted, so the same map always produces the same string and a no-op write cannot look
    /// like a change to another device. Values carrying a `;` or `=` are dropped rather than
    /// escaped: no setting in the table can contain either, and an escaping scheme is a grammar
    /// every future reader would have to agree about.
    static func raw(from pairs: [String: String]) -> String {
        pairs.keys.sorted()
            .compactMap { key -> String? in
                guard let value = pairs[key],
                      !key.contains(";"), !key.contains("="),
                      !value.contains(";"), !value.contains("=") else { return nil }
                return "\(key)=\(value)"
            }
            .joined(separator: ";")
    }

    // MARK: - Which record

    /// The row every device must agree on when more than one exists. Newest edit wins;
    /// `id.uuidString` breaks a tie so two devices reading the same pair pick the same row rather
    /// than each picking its own and writing over the other forever.
    static func current(from records: [LookPreference]) -> LookPreference? {
        records.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - The mirror table

    /// Which platform owns a mirror. Named rather than `#if`-ed so a test on the Mac can exercise
    /// the iOS table too — the half that decides what happens to a value this device cannot set.
    nonisolated enum Platform: String, CaseIterable, Sendable {
        case macOS
        case iOS

        /// The platform this build is.
        static var current: Platform {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }
    }

    /// How a mirror's value is spelled locally.
    enum Kind: Sendable, Equatable {
        /// A `String` default, read and written as one.
        case string
        /// A `Bool` default. `UserDefaults.string(forKey:)` answers `nil` for one of these, so the
        /// mirror reads it as `"true"` / `"false"` through `object(forKey:)` and writes it back as
        /// a real `Bool` — otherwise every `@AppStorage(…) var showCompleted = false` would read
        /// the record's value as unset.
        case bool
    }

    /// How a mirror's value relates to the record's.
    enum Codec: Sendable {
        /// The same vocabulary on both sides.
        case verbatim
        /// macOS's `TaskSortField` on the mirror side, `CadenceTaskSortMode` on the record side.
        case macOSSortField
    }

    struct MirroredSetting: Sendable {
        /// The key inside `LookPreference.taskPresentationRaw`.
        let recordKey: String
        /// The `UserDefaults` key in `CadenceDefaults.store` this platform already reads.
        let defaultsKey: String
        let kind: Kind
        let codec: Codec

        init(_ recordKey: String, _ defaultsKey: String, kind: Kind = .string, codec: Codec = .verbatim) {
            self.recordKey = recordKey
            self.defaultsKey = defaultsKey
            self.kind = kind
            self.codec = codec
        }
    }

    /// The task-surface mirrors this platform owns.
    ///
    /// macOS Today's `todaySortMode` is here even though the owner's audit counted `@AppStorage`
    /// keys and that one is a bare `UserDefaults` key: iOS Today's sort is in the list, and syncing
    /// one Today and not the other would leave the single page both devices open on visibly
    /// unsynced, which is the whole complaint. It is one row of this table.
    ///
    /// **When an adopted value appears.** Every mirror but one is read through `@AppStorage`, which
    /// observes its own key, so a palette or a sort arriving from another device repaints the
    /// surface at once. `todaySortMode` is the exception: `TasksPanel` seeds `@State` from it in
    /// `init`, so a Today sort adopted while that panel is on screen is drawn at the next launch
    /// rather than immediately. Left alone rather than rewired — moving Today's chip onto
    /// `@AppStorage` is a change to a surface this ticket was not asked to touch.
    ///
    /// macOS's per-list `_sortField` / `_sortDir` keys are deliberately absent. They are keyed by
    /// list id — a different setting from iOS's one app-wide `ios.listDetail.sortMode`, not the
    /// same one spelled differently — and folding them together would pick a winner per list.
    static func mirrors(on platform: Platform) -> [MirroredSetting] {
        switch platform {
        case .macOS:
            return [
                MirroredSetting("today.mode", CadencePreferenceKeys.todaySortMode),
                MirroredSetting("allTasks.mode", CadencePreferenceKeys.allTasksSortField, codec: .macOSSortField),
                MirroredSetting("allTasks.direction", CadencePreferenceKeys.allTasksSortDirection),
                MirroredSetting("allTasks.grouping", CadencePreferenceKeys.allTasksGroupingMode),
                MirroredSetting("inbox.mode", CadencePreferenceKeys.inboxSortField, codec: .macOSSortField),
                MirroredSetting("inbox.direction", CadencePreferenceKeys.inboxSortDirection),
                MirroredSetting("inbox.grouping", CadencePreferenceKeys.inboxGroupingMode),
            ]
        case .iOS:
            return [
                MirroredSetting("today.mode", CadencePreferenceKeys.iosTodaySortMode),
                MirroredSetting("today.showCompleted", CadencePreferenceKeys.iosTodayShowCompleted, kind: .bool),
                MirroredSetting("allTasks.mode", CadencePreferenceKeys.iosAllTasksSortMode),
                MirroredSetting("allTasks.showCompleted", CadencePreferenceKeys.iosAllTasksShowCompleted, kind: .bool),
                MirroredSetting("inbox.mode", CadencePreferenceKeys.iosInboxSortMode),
                MirroredSetting("inbox.showCompleted", CadencePreferenceKeys.iosInboxShowCompleted, kind: .bool),
                MirroredSetting("listDetail.mode", CadencePreferenceKeys.iosListDetailSortMode),
                MirroredSetting("listDetail.showCompleted", CadencePreferenceKeys.iosListDetailShowCompleted, kind: .bool),
            ]
        }
    }

    // MARK: - The two vocabularies

    /// A mirror value as the record spells it.
    static func recordValue(fromMirror value: String, codec: Codec) -> String {
        switch codec {
        case .verbatim:
            return value
        case .macOSSortField:
            return CadenceTaskSortMode.migratedFromMacOSTodaySortField(value).rawValue
        }
    }

    /// A record value as this mirror spells it, or `nil` when the record holds something the
    /// mirror's own vocabulary cannot name at all.
    ///
    /// `.dueDate` and `.newest` have no `TaskSortField`, and they **project onto `Date`** rather
    /// than answering `nil`: a Mac drawing the nearest of its three modes is a Mac that very nearly
    /// agrees with the phone, and a Mac that refused the value would leave the two devices showing
    /// unrelated orders with nothing on screen saying why. The projection is safe to draw only
    /// because `publishedPairs` refuses to write it back — see this type's note.
    static func mirrorValue(fromRecord value: String, codec: Codec) -> String? {
        switch codec {
        case .verbatim:
            return value
        case .macOSSortField:
            guard let mode = CadenceTaskSortMode(rawValue: value) else { return nil }
            switch mode {
            case .listOrder: return TaskSortField.custom.rawValue
            case .priority: return TaskSortField.priority.rawValue
            case .doDate, .dueDate, .newest: return TaskSortField.date.rawValue
            }
        }
    }

    // MARK: - Adopting: the record, read down into this device's mirrors

    /// What each mirrored default should hold, given the record. Keys absent from the record are
    /// absent here: a record that has never carried `inbox.grouping` leaves this device's grouping
    /// exactly as the person left it rather than resetting it to a default nobody chose.
    static func mirrorWrites(
        forTaskPresentation raw: String,
        on platform: Platform = .current
    ) -> [String: String] {
        let stored = pairs(fromRaw: raw)
        return mirrors(on: platform).reduce(into: [String: String]()) { partial, mirror in
            guard let value = stored[mirror.recordKey],
                  let local = mirrorValue(fromRecord: value, codec: mirror.codec) else { return }
            partial[mirror.defaultsKey] = local
        }
    }

    // MARK: - Publishing: this device's mirrors, written up into the record

    /// This device's mirrored defaults, as the record would spell them.
    static func currentMirrors(
        in defaults: UserDefaults,
        on platform: Platform = .current
    ) -> [String: String] {
        mirrors(on: platform).reduce(into: [String: String]()) { partial, mirror in
            switch mirror.kind {
            case .string:
                guard let value = defaults.string(forKey: mirror.defaultsKey) else { return }
                partial[mirror.defaultsKey] = value
            case .bool:
                guard defaults.object(forKey: mirror.defaultsKey) != nil else { return }
                partial[mirror.defaultsKey] = defaults.bool(forKey: mirror.defaultsKey) ? "true" : "false"
            }
        }
    }

    /// The pair map to store, given what this device's mirrors hold and what the record holds.
    ///
    /// Starts from `stored`, so every pair this platform has no mirror for — an iOS
    /// `showCompleted` on a Mac, a macOS `grouping` on a phone, a key some future build adds —
    /// survives the write untouched.
    ///
    /// **A projected value is not a change.** When the mirror holds exactly what
    /// `mirrorValue(fromRecord:)` would have drawn from the stored value, the stored value is kept.
    /// Without that, a Mac opening a list whose stored mode is `.dueDate` would draw `Date`,
    /// publish `doDate`, and destroy a setting it never had a control for.
    static func publishedPairs(
        currentMirrors: [String: String],
        stored: [String: String],
        on platform: Platform = .current
    ) -> [String: String] {
        var result = stored
        for mirror in mirrors(on: platform) {
            guard let local = currentMirrors[mirror.defaultsKey] else { continue }
            if let storedValue = result[mirror.recordKey],
               mirrorValue(fromRecord: storedValue, codec: mirror.codec) == local {
                continue
            }
            result[mirror.recordKey] = recordValue(fromMirror: local, codec: mirror.codec)
        }
        return result
    }

    // MARK: - Writing

    /// The whole look as this device would store it, or `nil` when the record already says exactly
    /// that.
    ///
    /// `nil` is the common answer — a publish runs on every `UserDefaults` change in the app, and
    /// almost none of them touch one of these keys. Returning `nil` rather than an equal record is
    /// what keeps a sort chip from bumping `updatedAt` on three devices for nothing.
    static func pendingWrite(
        accentPaletteID: String,
        sidebarTabColorsRaw: String,
        currentMirrors: [String: String],
        record: LookPreference?,
        on platform: Platform = .current
    ) -> (accentPaletteID: String, sidebarTabColorsRaw: String, taskPresentationRaw: String)? {
        let storedPairs = pairs(fromRaw: record?.taskPresentationRaw ?? "")
        let taskPresentationRaw = raw(
            from: publishedPairs(currentMirrors: currentMirrors, stored: storedPairs, on: platform)
        )
        // **An empty local value is "never chosen here", never "chosen to be nothing".** Without
        // this, a publish that ran before this launch's first adopt — any `UserDefaults` write
        // during startup is enough to trigger one — would read this device's unset accent as `""`
        // and erase the palette the owner picked on another device. The same reading is already
        // why `adopt` ignores an empty stored value and why `currentMirrors` omits an unset key
        // rather than reporting a default for it; this is the third face of one rule.
        //
        // The cost is that neither field can be cleared back to unset from a device, which no
        // surface offers anyway: the palette picker always names one of three, and the tint sheet
        // always writes a hex.
        let candidate = (
            accentPaletteID: accentPaletteID.isEmpty ? (record?.accentPaletteID ?? "") : accentPaletteID,
            sidebarTabColorsRaw: sidebarTabColorsRaw.isEmpty
                ? (record?.sidebarTabColorsRaw ?? "")
                : sidebarTabColorsRaw,
            taskPresentationRaw: taskPresentationRaw
        )
        guard let record else {
            // Nothing stored yet. A record is worth minting only once this device actually holds
            // something to say — three devices each seeding a row of pure defaults is three rows to
            // reconcile and nothing gained.
            let isEmpty = candidate.accentPaletteID.isEmpty
                && candidate.sidebarTabColorsRaw.isEmpty
                && candidate.taskPresentationRaw.isEmpty
            return isEmpty ? nil : candidate
        }
        guard record.accentPaletteID != candidate.accentPaletteID
                || record.sidebarTabColorsRaw != candidate.sidebarTabColorsRaw
                || record.taskPresentationRaw != candidate.taskPresentationRaw else { return nil }
        return candidate
    }

    /// Writes a look, creating the synced row the first time.
    ///
    /// Commits through `CadencePendingChangePersistence` rather than `try? save()`: this inserts on
    /// the first write, so a swallowed failure would leave the insert pending for the next
    /// unrelated `save()` to take or a `rollback()` to discard. It **throws** instead, and the one
    /// caller — `CadenceLookPreferenceSync` — keeps the failure and retries on the next change.
    /// Nothing tells the user it worked, because nothing needs to: the mirror was already written,
    /// so the person's own device already looks the way they asked and only the sync is deferred.
    @MainActor
    static func write(
        accentPaletteID: String,
        sidebarTabColorsRaw: String,
        taskPresentationRaw: String,
        records: [LookPreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard let record = current(from: records) else {
            let created = LookPreference(
                accentPaletteID: accentPaletteID,
                sidebarTabColorsRaw: sidebarTabColorsRaw,
                taskPresentationRaw: taskPresentationRaw,
                updatedAt: now
            )
            modelContext.insert(created)
            try CadencePendingChangePersistence.commitInsert(of: created, in: modelContext, commit: commit)
            return
        }

        let previousAccent = record.accentPaletteID
        let previousColors = record.sidebarTabColorsRaw
        let previousPresentation = record.taskPresentationRaw
        let previousUpdatedAt = record.updatedAt
        record.accentPaletteID = accentPaletteID
        record.sidebarTabColorsRaw = sidebarTabColorsRaw
        record.taskPresentationRaw = taskPresentationRaw
        record.updatedAt = now
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            record.accentPaletteID = previousAccent
            record.sidebarTabColorsRaw = previousColors
            record.taskPresentationRaw = previousPresentation
            record.updatedAt = previousUpdatedAt
        }
    }
}

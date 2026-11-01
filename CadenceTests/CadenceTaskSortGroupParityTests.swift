import Foundation
import SwiftData
import Testing

@testable import Cadence

/// **One Sort / Order / Group model on the Inbox and All Tasks, on both platforms** ([[T-8731]],
/// owner decision 2026-10-31 under [[T-8201]]).
///
/// What was there: macOS drew three `CadenceEnumPickerBadge`s — Sort (Custom / Date / Priority),
/// Order (Ascending / Descending), Group (None / By Date / By List / By Priority) — and the iPhone
/// and iPad drew one chip of five `CadenceTaskSortMode`s with no direction and no grouping, over a
/// single fixed section. The owner chose the Mac's model for iOS, the deciding fact being that iOS
/// could not reverse a sort or group at all.
///
/// **Which vocabulary won, and why.** The Mac's, wholesale: `TaskSortField` + `TaskSortDirection`
/// + `TaskGroupingMode`, with `TaskGroupingMode` moved out of `macOS/Views/` into `Shared/` so
/// `Cadence/iOS/` can see it.
///
/// **And the Mac's vocabulary then grew, which is [[T-9742]].** Adopting it cost the iOS Inbox and
/// All Tasks two modes: `CadenceTaskSortMode.dueDate` and `.newest` had no field, and
/// `macOSSortPair` flattened both onto Date + Ascending — the same projection
/// `CadenceLookPreferenceStore` had applied to these preferences since the look record landed,
/// because the Mac's three fields were already the smaller vocabulary a synced phone choice was
/// drawn as. The owner ruled on 2026-11-01 that the loss was not to be accepted: `TaskSortField`
/// gained `.dueDate` and `.newest`, both platforms now offer five fields, and the projection below
/// is a one-to-one correspondence rather than a flattening.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the iOS half is a
/// source reading and the shared half is run.
struct CadenceTaskSortGroupParityTests {

    private static let inboxPath = "Cadence/iOS/iOSInboxView.swift"
    private static let allTasksPath = "Cadence/iOS/iOSTaskCollectionViews.swift"
    private static let barPath = "Cadence/iOS/iOSTaskViews.swift"
    private static let macPagePath = "Cadence/macOS/Views/macOSRootSupportViews.swift"

    /// Raw source with comments blanked, which is **not** `code(_:)`: `codeOnly` blanks the
    /// contents of a string literal too, so a control title a user reads — `"Sort"` — is not in the
    /// text it returns. Use this when the needle is a literal, that one when it is code.
    private func literalBearingCode(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "non-vacuity: comments were not stripped in \(path)")
        return code
    }

    private func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "non-vacuity: comments were not stripped in \(path)")
        return code
    }

    // MARK: - The vocabulary is one set, in one place

    /// `TaskGroupingMode` is reachable from shared code — the whole point of moving it out of
    /// `macOS/Views/TasksPanelSupport.swift`, which `Cadence/iOS/` cannot import. Asserted as the
    /// full ordered list: a case added on one platform is the drift this pins.
    @Test func theGroupingVocabularyIsOneSharedOrderedSet() {
        #expect(TaskGroupingMode.allCases.map(\.rawValue) == ["None", "By Date", "By List", "By Priority"])
        #expect(TaskGroupingMode.allCases.map(\.id) == TaskGroupingMode.allCases.map(\.rawValue))
    }

    /// It is declared in `Shared/` and no longer in `macOS/Views/`, which is the half that decides
    /// whether iOS can see it at all. A second declaration anywhere would compile and diverge.
    @Test func theGroupingVocabularyIsDeclaredOnceAndNotUnderMacOS() throws {
        let shared = try code("Cadence/Shared/CadenceTaskPlanningSupport.swift")
        #expect(shared.contains("enum TaskGroupingMode: String, CaseIterable, Identifiable, Sendable"))

        let mac = try code("Cadence/macOS/Views/TasksPanelSupport.swift")
        #expect(!mac.contains("enum TaskGroupingMode"))
    }

    // MARK: - Both platforms' Inbox controls offer the same cases

    /// **The ticket's own acceptance test.** The three controls, over the three vocabularies, with
    /// the Order control gated the same way on both — and no fourth vocabulary on either side.
    @Test func bothPlatformsDrawTheSameThreeControlsOverTheSameThreeVocabularies() throws {
        let touch = try code(Self.barPath)
        let bar = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskSortGroupBar: View", in: touch),
            "iOSTaskSortGroupBar is gone from \(Self.barPath)"
        )
        #expect(bar.contains("@Binding var sortField: TaskSortField"))
        #expect(bar.contains("@Binding var sortDirection: TaskSortDirection"))
        #expect(bar.contains("@Binding var groupingMode: TaskGroupingMode"))
        // The phone's own five-mode vocabulary is not on this bar.
        #expect(!bar.contains("CadenceTaskSortMode"))

        // Read RAW, not `codeOnly`: the three control titles are string literals, and `codeOnly`
        // blanks a literal's contents, so the stripped text cannot carry the word a user reads.
        let macRaw = try CadenceSourceScan.sourceFile(Self.macPagePath)
        let page = try #require(
            CadenceSourceScan.declarationBody("struct TasksPageView: View", in: CadenceSourceScan.strippingComments(macRaw)),
            "TasksPageView is gone from \(Self.macPagePath)"
        )
        #expect(page.contains("CadenceEnumPickerBadge(title: \"Sort\", selection: sortField)"))
        #expect(page.contains("CadenceEnumPickerBadge(title: \"Order\", selection: sortDirection)"))
        #expect(page.contains("CadenceEnumPickerBadge(title: \"Group\", selection: groupingMode)"))
    }

    /// Order is drawn only where the field honours one, on both — `TaskSortField.honorsDirection`,
    /// asked rather than re-spelled. A touch bar that drew the pill unconditionally would offer a
    /// control that does nothing beside Sort: Custom, which is the Inbox's default.
    @Test func theOrderControlIsGatedOnHonorsDirectionOnBothPlatforms() throws {
        let touch = try code(Self.barPath)
        let bar = try #require(CadenceSourceScan.declarationBody("struct iOSTaskSortGroupBar: View", in: touch))
        #expect(bar.contains("if sortField.honorsDirection {"))

        let mac = try code(Self.macPagePath)
        #expect(mac.contains("if sortField.wrappedValue.honorsDirection {"))

        // And the rule itself, run: Custom is the only field a direction cannot reverse.
        #expect(!TaskSortField.custom.honorsDirection)
        for field in TaskSortField.allCases where field != .custom {
            #expect(field.honorsDirection, "\(field.rawValue)")
        }
    }

    /// One stored preference per setting, not two — the ticket's last named consequence ("the two
    /// platforms keep separate preference keys, so the choice cannot follow the owner between
    /// devices"). Both hosts name `CadencePreferenceKeys`' Mac keys, and neither reads the retired
    /// `ios.*.sortMode` any more.
    @Test func bothPlatformsStoreTheChoiceUnderOneKeyPerSetting() throws {
        let inbox = try code(Self.inboxPath)
        #expect(inbox.contains("@AppStorage(CadencePreferenceKeys.inboxSortField)"))
        #expect(inbox.contains("@AppStorage(CadencePreferenceKeys.inboxSortDirection)"))
        #expect(inbox.contains("@AppStorage(CadencePreferenceKeys.inboxGroupingMode)"))
        #expect(!inbox.contains("CadencePreferenceKeys.iosInboxSortMode"))

        let allTasks = try code(Self.allTasksPath)
        #expect(allTasks.contains("@AppStorage(CadencePreferenceKeys.allTasksSortField)"))
        #expect(allTasks.contains("@AppStorage(CadencePreferenceKeys.allTasksSortDirection)"))
        #expect(allTasks.contains("@AppStorage(CadencePreferenceKeys.allTasksGroupingMode)"))
        #expect(!allTasks.contains("CadencePreferenceKeys.iosAllTasksSortMode"))

        // The macOS page is the non-vacuity anchor: the same six constants, already there.
        let mac = try code(Self.macPagePath)
        for key in ["inboxSortField", "inboxSortDirection", "inboxGroupingMode",
                    "allTasksSortField", "allTasksSortDirection", "allTasksGroupingMode"] {
            #expect(mac.contains("CadencePreferenceKeys.\(key)"), "\(key)")
        }
    }

    /// The cross-device record carries all six on both platforms now. A mirror missing on one side
    /// is a setting that silently stops syncing, which is invisible from either device.
    @Test func theLookRecordMirrorsAllSixTaskPresentationKeysOnBothPlatforms() {
        for platform in CadenceLookPreferenceStore.Platform.allCases {
            let keys = Set(CadenceLookPreferenceStore.mirrors(on: platform).map(\.recordKey))
            for recordKey in ["allTasks.mode", "allTasks.direction", "allTasks.grouping",
                              "inbox.mode", "inbox.direction", "inbox.grouping"] {
                #expect(keys.contains(recordKey), "\(platform.rawValue) is missing \(recordKey)")
            }
        }
    }

    // MARK: - The grouping is one function

    /// **Which groups exist is `CadenceTaskQuerySupport.displayGroups`' answer on both platforms.**
    /// Run rather than read: each mode's groups must be the shared builder's, so a touch surface
    /// cannot bucket a task into a day the Mac would not.
    @Test func everyGroupingModeAnswersTheSharedBuckets() throws {
        let todayKey = "2026-11-01"
        let overdue = AppTask(title: "Overdue")
        overdue.dueDate = "2026-10-30"
        let doToday = AppTask(title: "Do today")
        doToday.scheduledDate = todayKey
        let unscheduled = AppTask(title: "Unscheduled")
        unscheduled.priority = .high
        let tasks = [overdue, doToday, unscheduled]

        let none = CadenceTaskQuerySupport.displayGroups(from: tasks, mode: .none, todayKey: todayKey, contexts: [])
        #expect(none.map(\.title) == [CadenceTaskQuerySupport.ungroupedGroupTitle])
        #expect(none.first?.tasks.count == 3)
        // An empty page draws no heading over nothing.
        #expect(CadenceTaskQuerySupport.displayGroups(from: [], mode: .none, todayKey: todayKey, contexts: []).isEmpty)

        let byDate = CadenceTaskQuerySupport.displayGroups(from: tasks, mode: .byDate, todayKey: todayKey, contexts: [])
        #expect(byDate.map(\.id) == CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey).map(\.id))
        // Non-vacuity: the fixture reaches more than one bucket.
        #expect(byDate.count >= 2)

        let byPriority = CadenceTaskQuerySupport.displayGroups(from: tasks, mode: .byPriority, todayKey: todayKey, contexts: [])
        #expect(byPriority.map(\.id) == CadenceTaskQuerySupport.priorityDisplayGroups(from: tasks).map(\.id))
        #expect(!byPriority.isEmpty)
    }

    /// By List buckets and orders through the one list-grouping rule, and its headers carry the
    /// `list:` drop key the Mac's By List headers accept.
    @Test func theByListGroupsAreTheSharedListGroupsWithListDropKeys() throws {
        let filed = AppTask(title: "Filed")
        let loose = AppTask(title: "Loose")
        let tasks = [filed, loose]

        let groups = CadenceTaskQuerySupport.displayGroups(from: tasks, mode: .byList, todayKey: "2026-11-01", contexts: [])
        let shared = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [])

        #expect(!groups.isEmpty, "non-vacuity: the fixture produced no list group")
        #expect(groups.map(\.id) == shared.map(\.id))
        #expect(groups.map(\.title) == shared.map(\.title))
        for (group, source) in zip(groups, shared) {
            #expect(group.dropKey == "list:\(source.listKey)")
        }
    }

    /// The touch page draws the shared groups rather than its own, and keeps the ungrouped section
    /// on `activeTasks` so an emptied Inbox still offers its drop target.
    @Test func theTouchPageDrawsTheSharedGroupsAndKeepsTheUngroupedDropTarget() throws {
        let page = try code("Cadence/iOS/iOSTaskCollectionPage.swift")
        #expect(page.contains("CadenceTaskQuerySupport.displayGroups("))
        #expect(page.contains("if groupingMode == .none {"))
        #expect(page.contains("title: CadenceTaskQuerySupport.ungroupedGroupTitle"))
        #expect(page.contains("dropIdentity: collection.activeGroupIdentity"))
        #expect(page.contains("ForEach(activeGroups) { group in"))
        // The hand-spelled heading is gone; it is the shared constant or nothing.
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift")
        #expect(!raw.contains("title: \"Active\""))
    }

    // MARK: - Order actually orders

    /// The touch pages sort through `TaskOrdering`, the Mac's comparator, and the Order control
    /// genuinely reverses — the capability the owner's decision was made to give iOS.
    @Test func theDirectionReversesTheInboxAndAllTasksOrder() {
        let early = AppTask(title: "Early")
        early.scheduledDate = "2026-11-01"
        let late = AppTask(title: "Late")
        late.scheduledDate = "2026-11-09"
        let tasks = [late, early]

        let ascending = CadenceTaskQuerySupport.activeInboxTasks(from: tasks, sortField: .date, sortDirection: .ascending)
        let descending = CadenceTaskQuerySupport.activeInboxTasks(from: tasks, sortField: .date, sortDirection: .descending)
        #expect(ascending.map(\.title) == ["Early", "Late"])
        #expect(descending.map(\.title) == ["Late", "Early"])

        // All Tasks answers the same comparator over its own membership rule.
        #expect(
            CadenceTaskQuerySupport.activeTasks(from: tasks, sortField: .date, sortDirection: .descending).map(\.title)
                == ["Late", "Early"]
        )
        // And the field/direction form agrees with the shared array comparator rather than
        // re-implementing it.
        #expect(
            ascending.map(\.id)
                == CadenceTaskQuerySupport.openInboxTasks(from: tasks)
                    .taskSorted(by: .date, direction: .ascending)
                    .map(\.id)
        )
    }

    // MARK: - The retired phone preference

    /// The projection, case by case, and **every one of the five now has an exact twin**
    /// ([[T-9742]]). This used to pin `.dueDate` and `.newest` onto `(.date, .ascending)`; that was
    /// the loss, not an invariant, and it is replaced with the new truth rather than relaxed.
    ///
    /// The direction each of the two carries is the one its branch in
    /// `CadenceTaskQuerySupport.sortKeyOrder` used to hard-code, so no list re-sorts: `.dueDate`
    /// was `lhs.dueDate < rhs.dueDate`, which is Ascending; `.newest` was
    /// `lhs.createdAt > rhs.createdAt`, which is Descending.
    @Test func everySortModeProjectsOntoTheSharedFieldPair() {
        #expect(CadenceTaskSortMode.listOrder.macOSSortPair == (.custom, .ascending))
        #expect(CadenceTaskSortMode.priority.macOSSortPair == (.priority, .descending))
        #expect(CadenceTaskSortMode.doDate.macOSSortPair == (.date, .ascending))
        #expect(CadenceTaskSortMode.dueDate.macOSSortPair == (.dueDate, .ascending))
        #expect(CadenceTaskSortMode.newest.macOSSortPair == (.newest, .descending))

        // **All five round-trip now**, so the two directions of one correspondence cannot drift
        // apart — and so that nothing can quietly re-flatten two modes onto a third's field: a
        // projection that collides is exactly what fails this loop.
        for mode in CadenceTaskSortMode.allCases {
            #expect(
                CadenceTaskSortMode.migratedFromMacOSTodaySortField(mode.macOSSortPair.field.rawValue) == mode,
                "\(mode.rawValue)"
            )
        }
        #expect(Set(CadenceTaskSortMode.allCases.map(\.macOSSortPair.field)).count
                    == CadenceTaskSortMode.allCases.count)
        // And it is the record's own projection, not a second rule.
        for mode in CadenceTaskSortMode.allCases {
            #expect(
                CadenceLookPreferenceStore.mirrorValue(fromRecord: mode.rawValue, codec: .macOSSortField)
                    == mode.macOSSortPair.field.rawValue,
                "\(mode.rawValue)"
            )
        }
    }

    // MARK: - The two fields the owner's 2026-11-01 decision added ([[T-9742]])

    /// **Both platforms offer all five fields, and neither control filters the set.**
    ///
    /// The Mac's Sort pill and the touch Sort chip are both generic over `T.allCases`, so widening
    /// the enum widens both — unless a call site passes `excluded:`, which is the one way a field
    /// could exist in the vocabulary and be unreachable on screen. None does, and this is what
    /// says so. Counted over every Sort control rather than spot-checked, because the failure is a
    /// control quietly offering fewer options than the comparator supports.
    @Test func everySortControlOffersTheWholeVocabulary() throws {
        #expect(TaskSortField.allCases.count == 5)

        for path in [Self.macPagePath, "Cadence/macOS/Views/ListDetailView.swift"] {
            let page = try literalBearingCode(path)
            let sortBadges = page.components(separatedBy: "CadenceEnumPickerBadge(title: \"Sort\"").count - 1
            #expect(sortBadges >= 1, "\(path) lost its Sort pill")
            #expect(!page.contains("excluded:"), "\(path) filters a picker's cases")
        }

        let bar = try #require(CadenceSourceScan.declarationBody(
            "struct iOSTaskSortGroupBar: View", in: try literalBearingCode(Self.barPath)
        ))
        #expect(bar.contains("iOSEnumChoiceChip(title: \"Sort\", glyph: \"arrow.up.arrow.down\", selection: $sortField)"))
    }

    /// **Both controls print the field's label, not its stored spelling.**
    ///
    /// `TaskSortField.date` is stored as `"Date"` and has to stay stored that way — the raw values
    /// *are* the preference strings, so renaming one orphans every saved sort. It is drawn as
    /// "Do Date", because "Date" beside "Due Date" names no date at all. The two controls ask the
    /// same protocol for that, so one of them cannot start printing `rawValue` again on its own.
    @Test func bothSortControlsPrintTheLabelRatherThanTheStoredRawValue() throws {
        #expect((TaskSortField.date as CadenceLabelledPickerValue).pickerLabel == "Do Date")
        #expect(TaskSortField.date.rawValue == "Date")

        let chip = try #require(CadenceSourceScan.declarationBody(
            "struct iOSEnumChoiceChip<", in: try code(Self.barPath)
        ))
        #expect(chip.contains("(value as? CadenceLabelledPickerValue)?.pickerLabel ?? value.rawValue"))
        // Non-vacuity, and the regression: the chip drew `selection.rawValue` in all three places
        // before [[T-9742]], and a single one left behind would show "Date" beside "Due Date".
        #expect(!chip.contains("selection.rawValue"))
        #expect(chip.components(separatedBy: "label(for:").count - 1 == 3)
    }

    /// **A build that does not know these raw values must fall back, not break** — the part most
    /// likely to bite in the wild, because a device on the previous build reads the same
    /// `UserDefaults` and the same look record.
    ///
    /// Every decode site is `TaskSortField(rawValue:)` behind a `guard`/`if let`, so the question
    /// is what the fallback *is*, not whether one exists. Measured from the other side: a value
    /// this build has never heard of stands in for what "Due Date" looks like to the old build,
    /// and it lands on the surface's own default rather than on a different field.
    @Test func aSortFieldThisBuildCannotNameFallsBackRatherThanPickingAnotherField() {
        for unknown in ["", "Due date", "dueDate", "Start Date", "\u{1F600}"] {
            #expect(TaskSortField(rawValue: unknown) == nil, "\(unknown) decoded")
            #expect(
                CadenceTaskSortMode.migratedFromMacOSTodaySortField(unknown) == .macOSTodayDefault,
                "\(unknown) did not fall back"
            )
        }
        #expect(CadenceTaskSortMode.migratedFromMacOSTodaySortField(nil) == .macOSTodayDefault)

        // The two new spellings decode on *this* build, which is the other half of the same claim:
        // the fallback above is reached by an unknown value, not by every value.
        #expect(TaskSortField(rawValue: "Due Date") == .dueDate)
        #expect(TaskSortField(rawValue: "Newest") == .newest)

        // And the record needs no migration, because the record's vocabulary was always the larger
        // one: `dueDate` and `newest` have been legal `allTasks.mode` values since it landed, and
        // an older build reading one still draws `Date` — the behaviour it had before this change,
        // not a new one.
        #expect(CadenceLookPreferenceStore.mirrorValue(fromRecord: "dueDate", codec: .macOSSortField)
                    == TaskSortField.dueDate.rawValue)
        #expect(CadenceLookPreferenceStore.mirrorValue(fromRecord: "newest", codec: .macOSSortField)
                    == TaskSortField.newest.rawValue)
        #expect(CadenceLookPreferenceStore.mirrorValue(fromRecord: "quarterlyReview", codec: .macOSSortField) == nil)
    }

    /// **The two fields sort by their own columns**, which is the behaviour the projection used to
    /// throw away: before this, choosing Due Date on a phone drew do-date order on both devices.
    ///
    /// Stated as the orders themselves rather than as a pair of mappings, so a branch that
    /// compiled but read the wrong column would fail here.
    @Test func dueDateAndNewestOrderByTheirOwnColumns() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [(String, String, String, Double)] = [
            // title, scheduledDate (do date), dueDate, createdAt offset
            ("soonest", "2026-06-03", "2026-06-01", 0),
            ("middle", "2026-06-02", "2026-06-02", 60),
            ("latest", "2026-06-01", "2026-06-03", 120),
            ("undated", "2026-06-04", "", 180)
        ]
        let tasks: [AppTask] = rows.enumerated().map { index, row in
            let task = AppTask(title: row.0)
            task.scheduledDate = row.1
            task.dueDate = row.2
            task.order = index
            task.createdAt = base.addingTimeInterval(row.3)
            return task
        }

        // Due Date reads `dueDate`, not `scheduledDate` — the two run in opposite orders here, so
        // a branch that read the do date would produce the reverse of this.
        #expect(tasks.taskSorted(by: .dueDate, direction: .ascending).map(\.title)
                    == ["soonest", "middle", "latest", "undated"])
        // Undated work stays at the bottom when the direction flips. Only the dated rows reverse.
        #expect(tasks.taskSorted(by: .dueDate, direction: .descending).map(\.title)
                    == ["latest", "middle", "soonest", "undated"])
        // Newest reads `createdAt`, most recent first, and Ascending is the oldest-first list that
        // makes the Order chip beside it a real control rather than a decoration.
        #expect(tasks.taskSorted(by: .newest, direction: .descending).map(\.title)
                    == ["undated", "latest", "middle", "soonest"])
        #expect(tasks.taskSorted(by: .newest, direction: .ascending).map(\.title)
                    == ["soonest", "middle", "latest", "undated"])

        // And each is exactly what the phone's own mode answers, which is what "no list re-sorts"
        // means: the mode delegates to this field now instead of carrying a second key.
        for (mode, field, direction) in [
            (CadenceTaskSortMode.dueDate, TaskSortField.dueDate, TaskSortDirection.ascending),
            (CadenceTaskSortMode.newest, TaskSortField.newest, TaskSortDirection.descending)
        ] {
            #expect(
                tasks.sorted { CadenceTaskQuerySupport.sortTasks($0, $1, sortMode: mode) }.map(\.title)
                    == tasks.taskSorted(by: field, direction: direction).map(\.title),
                "\(mode.rawValue)"
            )
        }
    }

    /// The migration writes once, never over a value the new control already holds, and is a no-op
    /// on a device that never stored the old one.
    @Test func theLegacyPhoneSortModeIsProjectedOnceAndNeverOverAChoiceAlreadyMade() throws {
        try withTemporaryDefaults("cadence.taskpresentation") { defaults in
            defaults.set(CadenceTaskSortMode.priority.rawValue, forKey: CadencePreferenceKeys.iosInboxSortMode)
            defaults.set(CadenceTaskSortMode.dueDate.rawValue, forKey: CadencePreferenceKeys.iosAllTasksSortMode)

            let first = CadenceTaskPresentationPreferences.migrateLegacyIOSSortModes(in: defaults)
            #expect(Set(first) == [
                CadencePreferenceKeys.inboxSortField,
                CadencePreferenceKeys.inboxSortDirection,
                CadencePreferenceKeys.allTasksSortField,
                CadencePreferenceKeys.allTasksSortDirection
            ])
            #expect(defaults.string(forKey: CadencePreferenceKeys.inboxSortField) == TaskSortField.priority.rawValue)
            #expect(defaults.string(forKey: CadencePreferenceKeys.inboxSortDirection) == TaskSortDirection.descending.rawValue)
            // **Due Date now survives the migration as Due Date** ([[T-9742]]). This asserted
            // `.date` until the owner's 2026-11-01 decision, because the projection had nowhere
            // else to put it: a phone that had chosen Due Date came out of the migration sorting
            // by do date. The new line is the point of the change, not a relaxation of the old one.
            #expect(defaults.string(forKey: CadencePreferenceKeys.allTasksSortField) == TaskSortField.dueDate.rawValue)
            #expect(defaults.string(forKey: CadencePreferenceKeys.allTasksSortDirection) == TaskSortDirection.ascending.rawValue)

            // Idempotent: a second pass writes nothing and changes nothing.
            #expect(CadenceTaskPresentationPreferences.migrateLegacyIOSSortModes(in: defaults).isEmpty)
            #expect(defaults.string(forKey: CadencePreferenceKeys.inboxSortField) == TaskSortField.priority.rawValue)

            // The retired value is left on disk, as macOS Today's retired keys are.
            #expect(defaults.string(forKey: CadencePreferenceKeys.iosInboxSortMode) == CadenceTaskSortMode.priority.rawValue)
        }
    }

    /// A device with no legacy value, or a choice already made on the new control, is untouched.
    @Test func theMigrationIsANoOpWithoutALegacyValueOrOverAnExistingChoice() throws {
        try withTemporaryDefaults("cadence.taskpresentation") { defaults in
            #expect(CadenceTaskPresentationPreferences.migrateLegacyIOSSortModes(in: defaults).isEmpty)
            #expect(defaults.string(forKey: CadencePreferenceKeys.inboxSortField) == nil)

            defaults.set(TaskSortField.custom.rawValue, forKey: CadencePreferenceKeys.inboxSortField)
            defaults.set(CadenceTaskSortMode.priority.rawValue, forKey: CadencePreferenceKeys.iosInboxSortMode)
            #expect(!CadenceTaskPresentationPreferences.migrateLegacyIOSSortModes(in: defaults)
                .contains(CadencePreferenceKeys.inboxSortField))
            #expect(defaults.string(forKey: CadencePreferenceKeys.inboxSortField) == TaskSortField.custom.rawValue)
        }
    }

    /// It is reached at launch. A migration nothing calls is the defect, not the mapping.
    @Test func theMigrationRunsAtLaunch() throws {
        let app = try code("Cadence/CadenceApp.swift")
        #expect(app.contains("CadenceTaskPresentationPreferences.migrateLegacyIOSSortModes()"))
    }
}

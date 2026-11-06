import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import StudyOS

private final class TestClock: ClockProvider {
    var now: Date
    init(_ now: Date) { self.now = now }
}
@Suite(.serialized) @MainActor struct StudyOSTests {
    @Test func increasingAvailabilityRaisesMaximumAndPersistsIt() throws {
        let (store, _, container) = try rig()
        store.commit {
            store.preferences.maxDailyMinutes = 214
            store.preferences.availability = [0, 180, 300, 180, 180, 0, 0]
        }
        #expect(store.preferences.maxDailyMinutes == 300)
        let saved = try ModelContext(container).fetch(FetchDescriptor<UserPreferences>())
        #expect(saved.first?.maxDailyMinutes == 300)
        store.commit { store.preferences.maxDailyMinutes = 200 }
        #expect(store.preferences.maxDailyMinutes == 300)
    }

    @Test func decreasingAvailabilityDoesNotEraseHigherChosenMaximum() throws {
        let (store, _, _) = try rig()
        store.commit {
            store.preferences.maxDailyMinutes = 420
            store.preferences.availability = Array(repeating: 300, count: 7)
        }
        store.commit { store.preferences.availability = Array(repeating: 120, count: 7) }
        #expect(store.preferences.maxDailyMinutes == 420)
    }

    @Test func existingContradictoryPreferencesAreRepairedWithoutChangingAvailability() throws {
        let container = try Persistence.container(inMemory: true)
        let preferences = UserPreferences(maxDailyMinutes: 214, availability: Array(repeating: 300, count: 7))
        container.mainContext.insert(preferences)
        try container.mainContext.save()
        let store = try StudyStore(context: ModelContext(container))
        #expect(store.preferences.maxDailyMinutes == 300)
        #expect(store.preferences.availability == Array(repeating: 300, count: 7))
    }

    @Test func monthGridRespectsFirstWeekdayAndIncludesAdjacentDays() throws {
        let november = date("2026-11-15T12:00:00Z")
        var sunday = utc; sunday.firstWeekday = 1
        let sundayDays = CalendarLayout.monthDays(containing: november, calendar: sunday)
        #expect(sundayDays.count == 35)
        #expect(sundayDays.first == date("2026-11-01T00:00:00Z"))
        #expect(sundayDays.last == date("2026-12-05T00:00:00Z"))
        var monday = utc; monday.firstWeekday = 2
        let mondayDays = CalendarLayout.monthDays(containing: november, calendar: monday)
        #expect(mondayDays.count == 42)
        #expect(mondayDays.first == date("2026-10-26T00:00:00Z"))
        #expect(mondayDays.last == date("2026-12-06T00:00:00Z"))
    }

    @Test func monthGridIncludesLeapDayAndYearBoundaryWithoutDuplicates() {
        let february = CalendarLayout.monthDays(containing: date("2024-02-15T12:00:00Z"), calendar: utc)
        #expect(february.filter { utc.component(.month, from: $0) == 2 }.count == 29)
        #expect(february.contains(date("2024-02-29T00:00:00Z")))
        let december = CalendarLayout.monthDays(containing: date("2026-12-31T12:00:00Z"), calendar: utc)
        #expect(december.contains { utc.component(.year, from: $0) == 2027 })
        #expect(Set(december).count == december.count && december.count % 7 == 0)
    }

    @Test func monthAndWeekGridsUseCalendarDaysAcrossDST() {
        var cal = utc; cal.timeZone = TimeZone(identifier: "America/Denver")!; cal.firstWeekday = 2
        let spring = cal.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let days = CalendarLayout.monthDays(containing: spring, calendar: cal)
        #expect(Set(days.map { StudyTime.dayKey($0, calendar: cal) }).count == days.count)
        for (a, b) in zip(days, days.dropFirst()) { #expect(cal.date(byAdding: .day, value: 1, to: a) == b) }
        let week = CalendarLayout.weekDays(containing: spring, calendar: cal)
        #expect(week.count == 7 && cal.component(.weekday, from: week[0]) == 2)
        #expect(week.contains { cal.isDate($0, inSameDayAs: spring) })
    }

    private func date(_ text: String = "2026-11-05T09:00:00Z") -> Date { ISO8601DateFormatter().date(from: text)! }
    private var utc: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
    private func rig() throws -> (StudyStore, TestClock, ModelContainer) {
        let c = try Persistence.container(inMemory: true)
        let clock = TestClock(date())
        return (try StudyStore(context: c.mainContext, clock: clock), clock, c)
    }
    private func plan(capacity: Int = 120, tasks: [StudyTaskSnapshot], blocks: [StudyPlanBlockSnapshot] = [], now: Date? = nil) -> PlanningResult {
        let p = UserPreferences(availability: Array(repeating: capacity, count: 7)).snapshot
        return PlanningEngine.generate(tasks: tasks, goals: [], blocks: blocks, sessions: [], preferences: p, now: now ?? date(), calendar: utc)
    }
    @Test func urgentPriorityOutranksDistantAndUndated() {
        let urgent = PlanningEngine.priority(due: date().addingTimeInterval(3600), remaining: 60, capacity: 120, priority: 2, now: date())
        let distant = PlanningEngine.priority(due: date().addingTimeInterval(86400 * 100), remaining: 60, capacity: 120, priority: 2, now: date())
        let undated = PlanningEngine.priority(due: nil, remaining: 60, capacity: 120, priority: 2, now: date())
        #expect(urgent > distant && urgent > undated)
    }
    @Test func zeroCapacityDoesNotInventTime() {
        let result = plan(capacity: 0, tasks: [StudyTask(title: "Read").snapshot])
        #expect(result.suggestions.isEmpty); #expect(!result.warnings.isEmpty)
    }
    @Test func planIsDeterministicAndSplitsWork() {
        let task = StudyTask(title: "Long task", estimatedMinutes: 180).snapshot
        let a = plan(tasks: [task]), b = plan(tasks: [task])
        #expect(a.suggestions == b.suggestions)
        #expect(a.suggestions.reduce(0) { $0 + $1.minutes } == 180)
        #expect(a.suggestions.allSatisfy { $0.minutes <= 60 && $0.minutes % 15 == 0 })
    }
    @Test func insufficientCapacityWarns() {
        let result = plan(capacity: 15, tasks: [StudyTask(title: "Large", estimatedMinutes: 1000).snapshot])
        #expect(result.suggestions.reduce(0) { $0 + $1.minutes } == 105)
        #expect(!result.warnings.isEmpty)
    }
    @Test func fixedBlocksArePreservedAndDoNotOverlap() {
        let task = StudyTask(title: "Read", estimatedMinutes: 240).snapshot
        let block = StudyPlanBlock(taskID: UUID(), day: date(), startAt: date(), durationMinutes: 60, isLocked: true).snapshot
        let result = plan(tasks: [task], blocks: [block])
        #expect(result.suggestions.allSatisfy { !PlanningEngine.overlaps(start: $0.startAt!, minutes: $0.minutes, otherStart: block.startAt!, otherMinutes: 60) })
        #expect(block.isLocked && block.startAt == date())
    }
    @Test func existingReservationsPreventDuplicatePlanning() {
        let task = StudyTask(title: "Read", estimatedMinutes: 30).snapshot
        let block = StudyPlanBlock(taskID: task.id, day: date(), startAt: date(), durationMinutes: 30).snapshot
        #expect(plan(tasks: [task], blocks: [block]).suggestions.isEmpty)
    }
    @Test func deadlineIsNeverExceeded() {
        let due = date().addingTimeInterval(3600)
        let result = plan(tasks: [StudyTask(title: "Exam", estimatedMinutes: 300, deadline: due, deadlineDateOnly: false).snapshot])
        #expect(!result.suggestions.isEmpty)
        #expect(result.suggestions.allSatisfy { $0.startAt!.addingTimeInterval(Double($0.minutes * 60)) <= due })
    }
    @Test func overdueTasksAreWarnedAndNotPlacedAfterDeadline() {
        let result = plan(tasks: [StudyTask(title: "Old", deadline: date().addingTimeInterval(-60), deadlineDateOnly: false).snapshot])
        #expect(result.suggestions.isEmpty); #expect(!result.warnings.isEmpty)
    }
    @Test func noPastStartAndQuarterHourRounding() {
        let now = date("2026-11-05T09:00:01Z")
        let result = plan(tasks: [StudyTask(title: "Read").snapshot], now: now)
        #expect(result.suggestions.first?.startAt == date("2026-11-05T09:15:00Z"))
    }
    @Test func recurringTaskStaysOnOccurrenceDay() {
        let tomorrow = date("2026-11-06T00:00:00Z")
        let task = StudyTask(title: "Habit", scheduledDay: tomorrow, recurrenceID: UUID()).snapshot
        #expect(plan(tasks: [task]).suggestions.allSatisfy { utc.isDate($0.day, inSameDayAs: tomorrow) })
    }
    @Test func manualFlexibleDayIsHonoredAndMissedHabitsDoNotBecomeDebt() {
        let tomorrow = date("2026-11-06T00:00:00Z")
        let pinned = StudyTask(title: "Chosen day", scheduledDay: tomorrow).snapshot
        #expect(plan(tasks: [pinned]).suggestions.allSatisfy { utc.isDate($0.day, inSameDayAs: tomorrow) })
        let missed = StudyTask(title: "Missed habit", scheduledDay: date().addingTimeInterval(-86400), recurrenceID: UUID()).snapshot
        #expect(plan(tasks: [missed]).suggestions.isEmpty)
    }
    @Test func confirmedBlockReplacesFlexibleDayWithoutDuplicateTaskDisplay() throws {
        let (store, clock, _) = try rig()
        let old = Calendar.current.date(byAdding: .day, value: -1, to: clock.now)!
        let task = StudyTask(title: "Moved", scheduledDay: old)
        store.commit {
            store.context.insert(task)
            store.context.insert(StudyPlanBlock(taskID: task.id, day: clock.now, durationMinutes: 30))
        }
        #expect(store.dayTasks(old).isEmpty)
        #expect(store.dayTasks(clock.now).count == 1)
    }
    @Test func recurrenceIsIdempotentAcrossCompletionAndWeeks() throws {
        let (store, clock, _) = try rig()
        let rule = RecurrenceRule(title: "English", startDate: clock.now)
        store.commit { store.context.insert(rule) }
        store.expandRecurrences(); let count = store.tasks.count
        #expect(count == 14)
        store.complete(store.tasks[0]); store.expandRecurrences()
        #expect(store.tasks.count == count)
        clock.now = clock.now.addingTimeInterval(86400 * 7); store.expandRecurrences()
        #expect(store.tasks.count == 21)
        #expect(Set(store.tasks.compactMap(\.occurrenceKey)).count == 21)
    }
    @Test func fourDayHabitExpandsExactlyFourTimesPerWeek() throws {
        let (store, clock, _) = try rig()
        store.commit { store.context.insert(RecurrenceRule(title: "NeetCode", weekdays: [2,3,5,7], duration: 45, startDate: clock.now)) }
        store.expandRecurrences(); #expect(store.tasks.count == 8)
    }
    @Test func zeroTaskProgressIsUndefined() {
        #expect(ProgressCalculator.completion(done: 0, total: 0) == nil)
        #expect(ProgressCalculator.completion(done: 1, total: 4) == 0.25)
    }
    @Test func negativeClockChangesAreClamped() {
        #expect(SessionClock.elapsed(accumulated: 5, intervalStart: date(), now: date().addingTimeInterval(-50)) == 5)
    }
    @Test func timerExcludesPausesAndPreventsDoubleFinish() throws {
        let (store, clock, _) = try rig()
        let task = StudyTask(title: "Focus")
        store.commit { store.context.insert(task) }; store.start(task); store.start(task)
        #expect(store.sessions.count == 1)
        let s = try #require(store.activeSession)
        clock.now = clock.now.addingTimeInterval(60); store.pause(s)
        clock.now = clock.now.addingTimeInterval(300); #expect(store.elapsed(s) == 60)
        store.resume(s); clock.now = clock.now.addingTimeInterval(30)
        #expect(store.finish(s, rating: 2, note: "Review", markComplete: false))
        #expect(s.accumulatedActiveSeconds == 90 && task.completedAt == nil)
        #expect(!store.finish(s, rating: nil, note: "", markComplete: true))
        #expect(s.accumulatedActiveSeconds == 90)
    }
    @Test func zeroSecondSessionCannotBeSavedAndDiscardDoesNotCount() throws {
        let (store, _, _) = try rig(); let task = StudyTask(title: "Focus")
        store.commit { store.context.insert(task) }; store.start(task)
        let s = try #require(store.activeSession)
        #expect(!store.finish(s, rating: nil, note: "", markComplete: true))
        store.discard(s)
        #expect(ProgressCalculator.actual(store.sessions.map(\.snapshot)) == 0)
        #expect(task.firstCompletedAt == nil)
    }
    @Test func dropIsCountedOnlyOnceAndArchivePreservesHistory() throws {
        let (store, _, _) = try rig(); let t = StudyTask(title: "Read")
        store.commit { store.context.insert(t) }; store.complete(t)
        let first = t.firstCompletedAt
        store.complete(t); store.complete(t); store.archive(t)
        #expect(t.firstCompletedAt == first && t.isArchived)
        #expect(store.tasks.filter { $0.firstCompletedAt != nil }.count == 1)
    }
    @Test func diskPersistenceRestoresNotesStepsAndPausedCheckpoint() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let taskID: UUID
        do {
            let c = try Persistence.container(url: url), clock = TestClock(date())
            let store = try StudyStore(context: c.mainContext, clock: clock)
            let task = StudyTask(title: "Persistent", steps: [ChecklistItem(title: "First", isDone: true)])
            taskID = task.id
            store.commit { store.context.insert(task) }; store.start(task)
            let s = try #require(store.activeSession)
            clock.now = clock.now.addingTimeInterval(42)
            store.commit { s.accumulatedActiveSeconds = store.elapsed(s); s.activeIntervalStartedAt = clock.now; s.sessionNote = "Keep me" }
        }
        let reopened = try Persistence.container(url: url)
        let store = try StudyStore(context: reopened.mainContext, clock: TestClock(date().addingTimeInterval(10000)))
        #expect(store.task(taskID)?.steps.first?.isDone == true)
        #expect(store.activeSession?.sessionNote == "Keep me")
        #expect(store.activeSession?.status == "paused")
        #expect(store.activeSession?.accumulatedActiveSeconds == 42)
    }
    @Test func exportImportIsIdempotentAndPreservesMetrics() throws {
        let (a, clock, _) = try rig(); let t = StudyTask(title: "Complete me")
        a.commit { a.context.insert(t) }; a.start(t); clock.now = clock.now.addingTimeInterval(600)
        #expect(a.finish(try #require(a.activeSession), rating: 4, note: "Done", markComplete: true))
        let backup = try StudyBackup.decode(StudyBackup(store: a).encoded())
        let (b, _, _) = try rig()
        #expect(backup.merge(into: b)); #expect(backup.merge(into: b))
        #expect(b.tasks.count == 1 && b.sessions.count == 1)
        #expect(ProgressCalculator.actual(b.sessions.map(\.snapshot)) == 600)
        #expect(b.tasks.first?.firstCompletedAt != nil)
    }
    @Test func corruptAndUnsupportedBackupsPreserveExistingData() throws {
        let (store, _, _) = try rig(); store.commit { store.context.insert(StudyTask(title: "Keep")) }
        #expect(throws: (any Error).self) { try StudyBackup.decode(Data("broken".utf8)) }
        var backup = StudyBackup(store: store); backup.schemaVersion = 999
        #expect(!backup.merge(into: store)); #expect(store.tasks.count == 1)
        backup.schemaVersion = 1; backup.tasks[0].estimatedMinutes = -1
        #expect(!backup.merge(into: store)); #expect(store.tasks.first?.estimatedMinutes == 30)
    }
    @Test func emptyBackupAndInvalidReferences() throws {
        let (store, _, _) = try rig()
        let empty = try StudyBackup.decode(StudyBackup(store: store).encoded())
        #expect(empty.tasks.isEmpty && empty.merge(into: store))
        var bad = empty
        bad.tasks = [StudyTask(subjectID: UUID(), title: "Orphan").snapshot]
        bad.recordCounts["tasks"] = 1
        #expect(!bad.merge(into: store)); #expect(store.tasks.isEmpty)
    }
    @Test func completedTaskNotificationsAreRemovedAndQuietHoursRespected() throws {
        let (store, _, _) = try rig(); let task = StudyTask(title: "Study")
        let p = store.preferences.snapshot
        let block = StudyPlanBlock(taskID: task.id, day: date(), startAt: date().addingTimeInterval(3600)).snapshot
        let before = NotificationSnapshot(preferences: p, blocks: [block], tasks: [task.snapshot], goals: [])
        #expect(NotificationService.requests(before, now: date(), calendar: utc).contains { $0.identifier == "block.\(block.id)" })
        task.completedAt = date()
        let after = NotificationSnapshot(preferences: p, blocks: [block], tasks: [task.snapshot], goals: [])
        #expect(!NotificationService.requests(after, now: date(), calendar: utc).contains { $0.identifier == "block.\(block.id)" })
        #expect(NotificationService.isQuiet(30, start: 1320, end: 480))
        #expect(!NotificationService.isQuiet(600, start: 1320, end: 480))
    }
    @Test func calendarDSTAndYearBoundaries() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Denver")!
        let spring = cal.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let fall = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        #expect(StudyTime.endOfDay(spring, calendar: cal).timeIntervalSince(spring) == 23 * 3600 - 1)
        #expect(StudyTime.endOfDay(fall, calendar: cal).timeIntervalSince(fall) == 25 * 3600 - 1)
        let end = date("2026-12-31T23:59:59Z"), next = end.addingTimeInterval(1)
        #expect(StudyTime.dayKey(end, calendar: utc) != StudyTime.dayKey(next, calendar: utc))
    }
    @Test func consistencyAndActualExcludeUnfinishedSessions() {
        let finished = FocusSession(startedAt: date(), endedAt: date(), accumulatedActiveSeconds: 600, status: "finished").snapshot
        let running = FocusSession(startedAt: date(), accumulatedActiveSeconds: 10000, status: "running").snapshot
        #expect(ProgressCalculator.actual([finished, running]) == 600)
        #expect(ProgressCalculator.consistency([finished, running], now: date(), calendar: utc) == 1)
    }
    @Test func completeVerticalWorkflowRequiresApprovalAndKeepsArchiveHistory() throws {
        let (store, clock, _) = try rig()
        let subject = Subject(name: "ECE 2280")
        let goal = StudyGoal(subjectID: subject.id, title: "Exam", dueAt: clock.now.addingTimeInterval(86400 * 5))
        let task = StudyTask(subjectID: subject.id, goalID: goal.id, title: "MOSFET regions", estimatedMinutes: 90)
        #expect(store.commit { store.context.insert(subject); store.context.insert(goal); store.context.insert(task) })
        let proposal = store.propose()
        #expect(!proposal.suggestions.isEmpty && store.blocks.isEmpty)
        #expect(store.propose().suggestions == proposal.suggestions && store.blocks.isEmpty)
        #expect(store.approve(proposal.suggestions))
        let count = store.blocks.count
        #expect(!store.approve(proposal.suggestions)); #expect(store.blocks.count == count)
        store.start(task); clock.now = clock.now.addingTimeInterval(900)
        #expect(store.finish(try #require(store.activeSession), rating: 3, note: "Review AC next", markComplete: true))
        #expect(store.blocks.allSatisfy { $0.status != "confirmed" })
        store.commit { subject.isArchived = true; goal.isArchived = true }
        store.archive(task)
        let backup = try StudyBackup.decode(StudyBackup(store: store).encoded())
        let (restored, _, _) = try rig()
        #expect(backup.merge(into: restored))
        #expect(restored.tasks.first?.firstCompletedAt != nil)
        #expect(ProgressCalculator.actual(restored.sessions.map(\.snapshot)) == 900)
        #expect(restored.sessions.first?.sessionNote == "Review AC next")
    }
    @Test func backupRejectsCountTamperingAndOccurrenceCollisionsAtomically() throws {
        let (store, _, _) = try rig()
        let rule = RecurrenceRule(title: "Habit")
        let task = StudyTask(title: "Original", recurrenceID: rule.id, occurrenceKey: "stable-key")
        store.commit { store.context.insert(rule); store.context.insert(task) }
        var backup = StudyBackup(store: store)
        backup.recordCounts["tasks"] = 999
        #expect(!backup.merge(into: store)); #expect(store.tasks.count == 1)
        backup.recordCounts["tasks"] = 1; backup.tasks[0].id = UUID()
        #expect(!backup.merge(into: store)); #expect(store.tasks.count == 1)
        #expect(store.tasks[0].title == "Original")
    }
    @Test func asyncProposalUsesTheSameSavedInputWithoutMutatingPlans() async throws {
        let (store, _, _) = try rig()
        store.commit { store.context.insert(StudyTask(title: "Background planning", estimatedMinutes: 90)) }
        let expected = store.propose()
        let result = await store.proposeAsync()
        #expect(result.suggestions == expected.suggestions)
        #expect(store.blocks.isEmpty)
    }
    @Test func urlValidationRejectsExecutableAndMalformedSchemes() {
        #expect(StudyTime.validURL("javascript:alert(1)") == nil)
        #expect(StudyTime.validURL("https://") == nil)
        #expect(StudyTime.validURL("https://elllo.org") != nil)
    }

    // MARK: Review fixes (2026-11-06)
    @Test func taskDueTooSoonDoesNotEndTheDayForOtherTasks() {
        // Due 10 minutes after the 09:00 window start: too short for a 15-minute block, and highest urgency.
        let soon = StudyTask(title: "Due soon", estimatedMinutes: 60, priority: 3, deadline: date("2026-11-05T09:10:00Z"), deadlineDateOnly: false).snapshot
        let other = StudyTask(title: "Other", estimatedMinutes: 60).snapshot
        let result = plan(tasks: [soon, other])
        #expect(!result.suggestions.contains { $0.taskID == soon.id })
        #expect(result.suggestions.contains { $0.taskID == other.id && utc.isDate($0.day, inSameDayAs: date()) })
    }
    @Test func smallRemainderStillGetsAQuarterHourBlock() {
        let task = StudyTask(title: "Short", estimatedMinutes: 10).snapshot
        let other = StudyTask(title: "Other", estimatedMinutes: 30).snapshot
        let result = plan(tasks: [task, other])
        #expect(result.suggestions.filter { $0.taskID == task.id }.map(\.minutes) == [15])
        #expect(result.suggestions.contains { $0.taskID == other.id })
    }
    @Test func overdueAndFarFutureTasksDoNotTriggerCapacityWarning() {
        let overdue = StudyTask(title: "Old", deadline: date().addingTimeInterval(-60), deadlineDateOnly: false).snapshot
        let later = StudyTask(title: "Later", scheduledDay: date("2026-11-20T00:00:00Z")).snapshot
        let result = plan(tasks: [overdue, later])
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("deadline has passed") == true)
    }
    @Test func timeBeforeTerminationIsOfferedButNeverAutoCredited() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        do {
            let c = try Persistence.container(url: url), clock = TestClock(date())
            let store = try StudyStore(context: c.mainContext, clock: clock)
            let task = StudyTask(title: "Locked phone")
            store.commit { store.context.insert(task) }; store.start(task)
            let s = try #require(store.activeSession)
            clock.now = clock.now.addingTimeInterval(300)
            store.commit { s.accumulatedActiveSeconds = store.elapsed(s); s.activeIntervalStartedAt = clock.now }
        }
        let reopened = try Persistence.container(url: url)
        let store = try StudyStore(context: reopened.mainContext, clock: TestClock(date().addingTimeInterval(300 + 3600)))
        #expect(store.activeSession?.accumulatedActiveSeconds == 300)
        #expect(store.recoveredGap?.seconds == 3600)
        store.resolveRecoveredGap(include: true)
        #expect(store.activeSession?.accumulatedActiveSeconds == 3900)
        #expect(store.recoveredGap == nil)
        store.resolveRecoveredGap(include: true)
        #expect(store.activeSession?.accumulatedActiveSeconds == 3900)
    }
    @Test func declinedOrImplausibleGapsAddNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        do {
            let c = try Persistence.container(url: url)
            let store = try StudyStore(context: c.mainContext, clock: TestClock(date()))
            let task = StudyTask(title: "Forgot timer")
            store.commit { store.context.insert(task) }; store.start(task)
        }
        let reopened = try Persistence.container(url: url)
        let overnight = try StudyStore(context: reopened.mainContext, clock: TestClock(date().addingTimeInterval(20 * 3600)))
        #expect(overnight.recoveredGap == nil)
        #expect(overnight.activeSession?.accumulatedActiveSeconds == 0)
        let pendingSession = try #require(overnight.activeSession)
        overnight.commit { pendingSession.pendingRecoveryStartedAt = date(); pendingSession.pendingRecoveryEndedAt = date().addingTimeInterval(600) }
        overnight.resolveRecoveredGap(include: false)
        #expect(overnight.activeSession?.accumulatedActiveSeconds == 0)
    }
    @Test func importedReviewForExistingDayDoesNotDuplicate() throws {
        let (a, _, _) = try rig(), (b, _, _) = try rig()
        let key = StudyTime.dayKey(date())
        a.saveReview("From the other device", dayKey: key)
        a.saveReview("Only in backup", dayKey: "1-2026-11-1")
        b.saveReview("Written here", dayKey: key)
        let backup = try StudyBackup.decode(StudyBackup(store: a).encoded())
        #expect(backup.merge(into: b))
        #expect(b.reviews.filter { $0.dayKey == key }.map(\.reflection) == ["Written here"])
        #expect(b.reviews.count == 2)
        let (c, _, _) = try rig()
        c.saveReview("  ", dayKey: key)
        #expect(backup.merge(into: c))
        #expect(c.reviews.filter { $0.dayKey == key }.map(\.reflection) == ["From the other device"])
    }
    @Test func todaysUnfinishedHabitDoesNotTriggerLowCompletionAdvice() {
        let rule = UUID(), today = utc.startOfDay(for: date())
        let yesterday = utc.date(byAdding: .day, value: -1, to: today)!
        let tasks = [
            StudyTask(title: "Habit", scheduledDay: yesterday, completedAt: yesterday, recurrenceID: rule).snapshot,
            StudyTask(title: "Habit", scheduledDay: today, recurrenceID: rule).snapshot,
        ]
        let p = UserPreferences().snapshot
        let notes = CoachingEngine.notes(tasks: tasks, goals: [], blocks: [], sessions: [], preferences: p, now: date(), calendar: utc)
        #expect(!notes.contains { $0.contains("fewer than half") })
        let missed = [StudyTask(title: "Habit", scheduledDay: utc.date(byAdding: .day, value: -2, to: today)!, recurrenceID: rule).snapshot] + tasks.map { var t = $0; t.completedAt = nil; return t }
        let after = CoachingEngine.notes(tasks: missed, goals: [], blocks: [], sessions: [], preferences: p, now: date(), calendar: utc)
        #expect(after.contains { $0.contains("fewer than half") })
    }

    // MARK: Convenience automation (2026-11-06)
    @Test func pastBlocksBecomeMissedAndOneOffWorkIsOfferedForToday() throws {
        let (store, _, _) = try rig()
        let cal = Calendar.current, today = cal.startOfDay(for: date()), yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let task = StudyTask(title: "Essay"), habit = StudyTask(title: "Habit", scheduledDay: yesterday, recurrenceID: UUID())
        let block = StudyPlanBlock(taskID: task.id, day: yesterday, startAt: nil, durationMinutes: 30)
        store.commit { store.context.insert(task); store.context.insert(habit); store.context.insert(block) }
        #expect(block.status == "missed")
        #expect(task.scheduledDay == yesterday)
        #expect(store.carriedOverTasks(now: date()).map(\.id) == [task.id])
        #expect(!store.dayTasks(today).contains { $0.id == task.id })
        store.carryOver([task], toToday: true)
        #expect(task.scheduledDay == today)
        #expect(store.dayTasks(today).contains { $0.id == task.id })
        #expect(store.dayTasks(yesterday).contains { $0.id == task.id })  // history stays on the missed day
        #expect(store.carriedOverTasks(now: date()).isEmpty)
        store.undoLastAction()
        #expect(task.scheduledDay == yesterday)
        store.carryOver([task], toToday: false)
        #expect(task.scheduledDay == nil && store.carriedOverTasks(now: date()).isEmpty)
    }
    @Test func runningSessionSchedulesGoalReminderOnlyWhileRunning() throws {
        let (store, clock, _) = try rig()
        let task = StudyTask(title: "Read", estimatedMinutes: 45)
        store.commit { store.context.insert(task) }; store.start(task)
        let s = try #require(store.activeSession)
        clock.now = clock.now.addingTimeInterval(600)
        func snapshot() -> NotificationSnapshot {
            var p = store.preferences.snapshot; p.quietStart = 0; p.quietEnd = 1439
            return NotificationSnapshot(preferences: p, blocks: [], tasks: store.tasks.map(\.snapshot), goals: [], sessions: store.sessions.map(\.snapshot))
        }
        let running = NotificationService.requests(snapshot(), now: clock.now).first { $0.identifier == "focus.\(s.id)" }
        let trigger = try #require(running?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(abs(trigger.timeInterval - 35 * 60) < 1)  // quiet hours do not hide it
        store.pause(s)
        #expect(!NotificationService.requests(snapshot(), now: clock.now).contains { $0.identifier.hasPrefix("focus.") })
    }
    @Test func deadlineConflictsMoveBeforeDueKeepingStudiedHistory() throws {
        let (store, _, _) = try rig()
        let cal = Calendar.current, today = cal.startOfDay(for: date())
        let later = cal.date(byAdding: .day, value: 3, to: today)!
        let task = StudyTask(title: "Report", estimatedMinutes: 120)
        let a = StudyPlanBlock(taskID: task.id, day: later, startAt: StudyTime.atMinute(store.preferences.windowStart, on: later), durationMinutes: 60)
        let b = StudyPlanBlock(taskID: task.id, day: later, startAt: StudyTime.atMinute(store.preferences.windowStart + 60, on: later), durationMinutes: 60)
        let studied = FocusSession(taskID: task.id, startedAt: date().addingTimeInterval(-900), endedAt: date().addingTimeInterval(-300), accumulatedActiveSeconds: 600, status: "finished", planBlockID: b.id)
        store.commit { store.context.insert(task); store.context.insert(a); store.context.insert(b); store.context.insert(studied) }
        let due = StudyTime.endOfDay(cal.date(byAdding: .day, value: 1, to: today)!)
        #expect(store.commit { try store.resolveDeadlineConflicts([a, b], due: due, move: true); task.deadline = due; task.deadlineDateOnly = false })
        let live = store.blocks.filter { $0.taskID == task.id && $0.status == "confirmed" }
        #expect(live.count == 2)
        #expect(live.allSatisfy { ($0.startAt!.addingTimeInterval(Double($0.durationMinutes * 60))) <= due })
        #expect(live.map(\.durationMinutes).sorted() == [50, 60])
        #expect(!PlanningEngine.overlaps(start: live[0].startAt!, minutes: live[0].durationMinutes, otherStart: live[1].startAt!, otherMinutes: live[1].durationMinutes))
        #expect(b.status == "completed" && b.durationMinutes == 10)
    }
    @Test func deadlineConflictsCanBeRemovedOrFailAtomically() throws {
        let (store, _, _) = try rig()
        let cal = Calendar.current, today = cal.startOfDay(for: date())
        let later = cal.date(byAdding: .day, value: 3, to: today)!
        let task = StudyTask(title: "Quiz")
        let block = StudyPlanBlock(taskID: task.id, day: later, startAt: StudyTime.atMinute(store.preferences.windowStart, on: later), durationMinutes: 30)
        store.commit { store.context.insert(task); store.context.insert(block) }
        // No room before a deadline that has already started passing: nothing changes.
        #expect(!store.commit { try store.resolveDeadlineConflicts([block], due: date().addingTimeInterval(60), move: true) })
        #expect(block.status == "confirmed" && cal.isDate(block.day, inSameDayAs: later))
        store.error = nil
        #expect(store.commit { try store.resolveDeadlineConflicts([block], due: date().addingTimeInterval(60), move: false) })
        #expect(block.status == "canceled")
    }
}

import Foundation
import SwiftData
import Testing
@testable import StudyOS

private final class UsabilityClock: ClockProvider {
    var now: Date
    init() { now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))! }
}
private final class FixtureBundle: NSObject {}

@Suite(.serialized) @MainActor struct UsabilityTests {
    private func rig() throws -> (StudyStore, UsabilityClock) {
        let c = try Persistence.container(inMemory: true), clock = UsabilityClock()
        return (try StudyStore(context: c.mainContext, clock: clock), clock)
    }
    private func tomorrow(_ clock: UsabilityClock) -> Date { Calendar.current.date(byAdding: .day, value: 1, to: clock.now)! }
    @Test func completionReleasesFutureLockedReservationsWithoutFakeStudyTime() throws {
        let (s,c) = try rig(), task = StudyTask(title: "Done early", estimatedMinutes: 90)
        let block = StudyPlanBlock(taskID: task.id, day: tomorrow(c), startAt: tomorrow(c), durationMinutes: 90, isLocked: true)
        s.commit { s.context.insert(task); s.context.insert(block) }; s.complete(task)
        #expect(block.status == "canceled" && s.dayTasks(tomorrow(c)).isEmpty)
        #expect(ProgressCalculator.actual(s.sessions.map(\.snapshot)) == 0)
        #expect(s.tasks.filter { $0.firstCompletedAt != nil }.count == 1)
    }
    @Test func undoCompletionRestoresReservationAndMistakenDropExactlyOnce() throws {
        let (s,c) = try rig(), task = StudyTask(title: "Undo me")
        let block = StudyPlanBlock(taskID: task.id, day: tomorrow(c), startAt: tomorrow(c), durationMinutes: 30)
        s.commit { s.context.insert(task); s.context.insert(block) }; s.complete(task); s.undoLastAction()
        #expect(task.completedAt == nil && task.firstCompletedAt == nil && block.status == "confirmed")
        s.undoLastAction(); #expect(s.tasks.count == 1 && s.blocks.count == 1)
    }
    @Test func undoWillNotOverwriteNewConflictingReservations() throws {
        let (s,c) = try rig(), a = StudyTask(title: "Original"), b = StudyTask(title: "New work")
        let first = StudyPlanBlock(taskID: a.id, day: tomorrow(c), startAt: tomorrow(c))
        s.commit { s.context.insert(a); s.context.insert(b); s.context.insert(first) }; s.archive(a)
        s.commit { s.context.insert(StudyPlanBlock(taskID: b.id, day: tomorrow(c), startAt: tomorrow(c))) }
        s.undoLastAction()
        #expect(a.isArchived && first.status == "canceled" && s.error != nil)
    }
    @Test func taskCompletionDuringFocusOpensFinishInsteadOfLeavingHiddenRunningTime() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Active")
        s.commit { s.context.insert(t) }; s.start(t); c.now = c.now.addingTimeInterval(60); s.toggleCompletion(t)
        #expect(t.completedAt == nil && s.focusRoute?.finishRequested == true)
        let session = try #require(s.activeSession)
        #expect(s.finish(session, rating: nil, note: "Kept", markComplete: true))
        #expect(t.completedAt != nil && s.activeSession == nil && session.accumulatedActiveSeconds == 60)
    }
    @Test func archiveParentIncludesChildrenGoalLinkedHabitsAndFutureBlocks() throws {
        let (s,c) = try rig(), subject = Subject(name: "Course")
        let goal = StudyGoal(subjectID: subject.id, title: "Project")
        let rule = RecurrenceRule(goalID: goal.id, title: "Practice")
        let t = StudyTask(subjectID: subject.id, goalID: goal.id, title: "Child")
        let block = StudyPlanBlock(taskID: t.id, day: tomorrow(c), startAt: tomorrow(c))
        s.commit { s.context.insert(subject); s.context.insert(goal); s.context.insert(rule); s.context.insert(t); s.context.insert(block) }
        s.applyArchive(ArchiveRequest(kind: .subject, recordID: subject.id), includeRelated: true)
        #expect(subject.isArchived && goal.isArchived && t.isArchived && !rule.isEnabled && block.status == "canceled")
        s.undoLastAction()
        #expect(!subject.isArchived && !goal.isArchived && !t.isArchived && rule.isEnabled && block.status == "confirmed")
    }
    @Test func parentOnlyArchiveHonorsExplicitChoice() throws {
        let (s,_) = try rig(), subject = Subject(name: "Course"), t = StudyTask(title: "Keep")
        t.subjectID = subject.id
        s.commit { s.context.insert(subject); s.context.insert(t) }
        s.applyArchive(ArchiveRequest(kind: .subject, recordID: subject.id), includeRelated: false)
        #expect(subject.isArchived && !t.isArchived)
    }
    @Test func archivingActiveWorkSavesTimeAndUndoNeverRestartsTheTimer() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Archive safely")
        s.commit { s.context.insert(t) }; s.start(t); c.now = c.now.addingTimeInterval(120)
        s.applyArchive(ArchiveRequest(kind: .task, recordID: t.id), includeRelated: true)
        #expect(t.isArchived && s.activeSession == nil && s.sessions.first?.accumulatedActiveSeconds == 120)
        s.undoLastAction(); #expect(!t.isArchived && s.activeSession == nil && s.sessions.first?.status == "finished")
    }
    @Test func missedRoutineExpiresButKeepsRealSessionsAndCreatesNoCatchup() throws {
        let (s,c) = try rig(), rule = RecurrenceRule(title: "Daily")
        let old = Calendar.current.date(byAdding: .day, value: -1, to: c.now)!
        let t = StudyTask(title: "Yesterday", scheduledDay: old, recurrenceID: rule.id, occurrenceKey: "old")
        s.commit {
            s.context.insert(rule); s.context.insert(t)
            s.context.insert(FocusSession(taskID: t.id, startedAt: old, endedAt: old.addingTimeInterval(600), accumulatedActiveSeconds: 600, status: "finished"))
        }
        #expect(t.skippedAt != nil && t.completedAt == nil && t.firstCompletedAt == nil)
        #expect(s.propose().suggestions.isEmpty)
        #expect(ProgressCalculator.actual(s.sessions.map(\.snapshot)) == 600)
    }
    @Test func explicitFutureMakeupBlockProtectsRoutineFromExpiration() throws {
        let (s,c) = try rig(), rule = RecurrenceRule(title: "Routine")
        let old = Calendar.current.date(byAdding: .day, value: -1, to: c.now)!
        let t = StudyTask(title: "Explicit catchup", scheduledDay: old, recurrenceID: rule.id)
        s.commit { s.context.insert(rule); s.context.insert(t); s.context.insert(StudyPlanBlock(taskID: t.id, day: tomorrow(c), startAt: tomorrow(c), isLocked: true)) }
        #expect(t.skippedAt == nil && s.dayTasks(tomorrow(c)).count == 1)
    }
    @Test func unfinishedOneOffWorkIsNotAutomaticallySkipped() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Assignment", scheduledDay: c.now.addingTimeInterval(-86400))
        s.commit { s.context.insert(t) }
        #expect(t.skippedAt == nil && !s.propose().suggestions.isEmpty)
    }
    @Test func pauseAndResumeRoutineDoesNotDuplicateOccurrences() throws {
        let (s,c) = try rig(), r = RecurrenceRule(title: "English", startDate: c.now)
        s.commit { s.context.insert(r) }; s.expandRecurrences(); let count = s.tasks.count
        var definition = HabitDefinition(); definition.title = "English"; definition.start = c.now; definition.enabled = false
        #expect(s.updateHabit(r, definition: definition, removeFuture: false))
        #expect(s.tasks.allSatisfy { $0.skippedAt != nil })
        definition.enabled = true
        #expect(s.updateHabit(r, definition: definition, removeFuture: false)); s.expandRecurrences()
        #expect(s.tasks.count == count && s.tasks.allSatisfy { $0.skippedAt == nil })
    }
    @Test func pauseKeepsConfirmedWorkUnlessRemovalWasExplicit() throws {
        let (s,c) = try rig(), r = RecurrenceRule(title: "Habit", startDate: c.now)
        let t = StudyTask(title: "Planned", scheduledDay: tomorrow(c), recurrenceID: r.id)
        let b = StudyPlanBlock(taskID: t.id, day: tomorrow(c), startAt: tomorrow(c), isLocked: true)
        s.commit { s.context.insert(r); s.context.insert(t); s.context.insert(b) }
        var d = HabitDefinition(); d.title = "Habit"; d.start = c.now; d.enabled = false
        #expect(s.updateHabit(r, definition: d, removeFuture: false)); #expect(b.status == "confirmed" && t.skippedAt == nil)
        #expect(s.updateHabit(r, definition: d, removeFuture: true)); #expect(b.status == "canceled" && t.skippedAt != nil)
    }
    @Test func selectedBlockControlsTargetAndPartialStudyLeavesOnlyRemainderReserved() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Large task", estimatedMinutes: 120)
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now, durationMinutes: 30)
        s.commit { s.context.insert(t); s.context.insert(b) }; s.start(t, blockID: b.id)
        let session = try #require(s.activeSession)
        #expect(session.targetMinutes == 30)
        c.now = c.now.addingTimeInterval(600)
        #expect(s.finish(session, rating: nil, note: "Partial", markComplete: false))
        #expect(s.remainingMinutes(b) == 20)
        s.start(t, blockID: b.id); #expect(s.activeSession?.targetMinutes == 20)
    }
    @Test func finishingBlockDoesNotAutomaticallyCompleteTheTask() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Keep open", estimatedMinutes: 120)
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now, durationMinutes: 15)
        s.commit { s.context.insert(t); s.context.insert(b) }; s.start(t, blockID: b.id); c.now = c.now.addingTimeInterval(900)
        #expect(s.finish(try #require(s.activeSession), rating: 5, note: "Good", markComplete: false))
        #expect(b.status == "completed" && t.completedAt == nil && t.firstCompletedAt == nil)
    }
    @Test func plannedAndActualTimeDoNotDoubleSubtractRemainingWork() throws {
        let (s,c) = try rig(), t = StudyTask(title: "One hour", estimatedMinutes: 60)
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now, durationMinutes: 60)
        s.commit { s.context.insert(t); s.context.insert(b) }; s.start(t, blockID: b.id); c.now = c.now.addingTimeInterval(1800)
        #expect(s.finish(try #require(s.activeSession), rating: nil, note: "Half", markComplete: false))
        #expect(s.remainingMinutes(b) == 30)
        #expect(s.propose().suggestions.filter { $0.taskID == t.id }.isEmpty)
    }
    @Test func movingUnstudiedBlockEditsItsIDInsteadOfAddingAnother() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Move")
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now.addingTimeInterval(3600))
        s.commit { s.context.insert(t); s.context.insert(b) }
        let p = PlanSuggestion(taskID: t.id, day: tomorrow(c), startAt: tomorrow(c), minutes: 30, reason: "Move")
        #expect(s.saveBlock(b, suggestion: p, locked: false))
        #expect(s.blocks.count == 1 && s.blocks.first?.id == b.id)
        #expect(s.dayTasks(c.now).isEmpty && s.dayTasks(tomorrow(c)).count == 1)
    }
    @Test func movingPartiallyStudiedBlockKeepsStudiedHistoryAndMovesOnlyRemainder() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Partial move", estimatedMinutes: 60)
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now, durationMinutes: 60)
        s.commit { s.context.insert(t); s.context.insert(b) }; s.start(t, blockID: b.id); c.now = c.now.addingTimeInterval(1800)
        #expect(s.finish(try #require(s.activeSession), rating: nil, note: "Keep", markComplete: false))
        let p = PlanSuggestion(taskID: t.id, day: Calendar.current.startOfDay(for: tomorrow(c)), startAt: StudyTime.atMinute(540,on: tomorrow(c)), minutes: 30, reason: "Remaining")
        #expect(s.saveBlock(b, suggestion: p, locked: false))
        #expect(b.status == "completed" && b.durationMinutes == 30 && s.blocks.count == 2)
        #expect(s.sessions.first?.planBlockID == b.id && s.sessions.first?.accumulatedActiveSeconds == 1800)
    }
    @Test func legalSlotFinderAvoidsPastTimeConflictsAndRestDays() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Find slot")
        s.commit { s.context.insert(t); s.context.insert(StudyPlanBlock(taskID: UUID(), day: c.now, startAt: c.now, durationMinutes: 60)) }
        let slot = try #require(s.nextAvailableSlot(taskID: t.id, minutes: 30, from: c.now))
        #expect(slot.startAt! >= c.now.addingTimeInterval(3600))
        #expect(throws: Never.self) { try s.validate([slot]) }
    }
    @Test func switchingFocusSavesCurrentTimeAndNotesWithoutCompletingIt() throws {
        let (s,c) = try rig(), a = StudyTask(title: "First"), b = StudyTask(title: "Second")
        s.commit { s.context.insert(a); s.context.insert(b) }; s.presentFocus(a)
        let first = try #require(s.activeSession); first.sessionNote = "Important"
        c.now = c.now.addingTimeInterval(60); s.presentFocus(b)
        #expect(s.pendingFocusSwitch?.taskID == b.id && s.activeSession?.taskID == a.id)
        s.saveAndSwitchFocus()
        #expect(first.status == "finished" && first.accumulatedActiveSeconds == 60 && first.sessionNote == "Important")
        #expect(a.completedAt == nil && s.activeSession?.taskID == b.id && s.sessions.count == 2)
    }
    @Test func optionalReviewIsDeduplicatedAndNeverScheduledAutomatically() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Review source", resources: [ResourceLink(title: "Reading",url: "https://example.com")])
        s.commit { s.context.insert(t) }; s.start(t); c.now = c.now.addingTimeInterval(60)
        let session = try #require(s.activeSession)
        #expect(s.finish(session, rating: 1, note: "Try again", markComplete: false, createReview: true))
        let review = try #require(s.tasks.first { $0.reviewSourceID == session.id })
        s.commit { _ = s.addReview(for: session) }
        #expect(s.tasks.count == 2 && review.estimatedMinutes == 15 && review.scheduledDay == nil && s.blocks.isEmpty)
        #expect(review.resources == t.resources && t.completedAt == nil)
    }
    @Test func lowRatingAloneCreatesNoReviewAndHighRatingDoesNotCompleteWork() throws {
        let (s,c) = try rig(), t = StudyTask(title: "No surprises")
        s.commit { s.context.insert(t) }; s.start(t); c.now = c.now.addingTimeInterval(60)
        #expect(s.finish(try #require(s.activeSession), rating: 1, note: "", markComplete: false))
        s.start(t); c.now = c.now.addingTimeInterval(60)
        #expect(s.finish(try #require(s.activeSession), rating: 5, note: "", markComplete: false))
        #expect(s.tasks.count == 1 && t.completedAt == nil)
    }
    @Test func completedReflectionAndStartedBlockSuppressOnlyRelevantReminders() throws {
        let (s,c) = try rig(), t = StudyTask(title: "Early start")
        let b = StudyPlanBlock(taskID: t.id, day: c.now, startAt: c.now.addingTimeInterval(3600))
        s.commit { s.context.insert(t); s.context.insert(b) }; s.start(t, blockID: b.id); s.saveReview("Done today")
        let snapshot = NotificationSnapshot(preferences: s.preferences.snapshot, blocks: s.blocks.map(\.snapshot), tasks:s.tasks.map(\.snapshot),goals:[],sessions:s.sessions.map(\.snapshot),reviews:s.reviews.map(\.snapshot))
        let requests = NotificationService.requests(snapshot,now:c.now)
        #expect(!requests.contains { $0.identifier == "block.\(b.id)" })
        #expect(!requests.contains { $0.identifier == "review.\(StudyTime.dayKey(c.now))" })
        #expect(requests.contains { $0.identifier.hasPrefix("review.") })
    }
    @Test func draftsSurviveReopenAndConsumedFormsCannotResurrect() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:url) }
        let repo = DraftRepository(url:url), lease = UUID()
        repo.begin("task:new",lease:lease);repo.stage(ResourceDraft(title:"Draft",url:"https://example.com"),for:"task:new",lease:lease);repo.flush()
        let reopened = DraftRepository(url:url)
        #expect(reopened.value(ResourceDraft.self,for:"task:new")?.title == "Draft")
        repo.consume("task:new");repo.stage(ResourceDraft(title:"Stale",url:""),for:"task:new",lease:lease);repo.flush()
        #expect(DraftRepository(url:url).value(ResourceDraft.self,for:"task:new") == nil)
    }
    @Test func restoringTaskNotesDoesNotOverwriteStepsCompletedElsewhere() {
        let original = StudyTask(title:"Merge",steps:[ChecklistItem(title:"Step")]).snapshot
        var draft = TaskFormDraft(task:original);draft.task.notes = "Unsaved note"
        var latest = original;latest.steps[0].isDone = true
        let merged = draft.merged(over:latest)
        #expect(merged.task.notes == "Unsaved note" && merged.task.steps[0].isDone)
    }
    @Test func resourceDefaultsAndDuplicateKeysAreSafe() throws {
        let r = try StudyTime.resource(title:"",url:" https://EXAMPLE.com ")
        #expect(r.title.lowercased() == "example.com")
        #expect(StudyTime.resourceKey(r.url) == StudyTime.resourceKey("https://example.com/"))
        #expect(StudyTime.resourceKey("https://example.com/a") != StudyTime.resourceKey("https://example.com/b"))
        #expect(throws:(any Error).self) { try StudyTime.resource(title:"Bad",url:"javascript:alert(1)") }
    }
    @Test func oldActualSwiftDataStoreMigratesWithoutLosingTasksOrSessions() throws {
        let bundle = Bundle(for:FixtureBundle.self)
        let source = try #require(bundle.url(forResource:"Legacy",withExtension:"store",subdirectory:"Fixtures") ?? bundle.url(forResource:"Legacy",withExtension:"store"))
        let expectedURL = try #require(bundle.url(forResource:"LegacyExpected",withExtension:"json",subdirectory:"Fixtures") ?? bundle.url(forResource:"LegacyExpected",withExtension:"json"))
        struct Expected:Decodable { var taskCount:Int;var sessionCount:Int;var titles:[String] }
        let expected = try JSONDecoder().decode(Expected.self,from:Data(contentsOf:expectedURL))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let dest = folder.appendingPathComponent("migrated.store")
        try FileManager.default.copyItem(at:source,to:dest)
        let container = try Persistence.container(url:dest)
        let s = try StudyStore(context:container.mainContext)
        #expect(s.tasks.count == expected.taskCount && s.sessions.count == expected.sessionCount)
        #expect(s.sessions.allSatisfy { $0.pendingRecoveryStartedAt == nil && $0.pendingRecoveryEndedAt == nil })
        #expect(s.tasks.map(\.title).sorted() == expected.titles)
        #expect(s.tasks.allSatisfy { $0.skippedAt == nil && $0.reviewSourceID == nil })
    }
    @Test func olderJSONWithoutOptionalNewFieldsImportsAndNewFieldsRoundTrip() throws {
        let (s,c) = try rig(), t = StudyTask(title:"Backup")
        s.commit { s.context.insert(t) };s.start(t);c.now = c.now.addingTimeInterval(60)
        #expect(s.finish(try #require(s.activeSession),rating:2,note:"Keep",markComplete:false,createReview:true))
        let data = try StudyBackup(store:s).encoded()
        let decoded = try StudyBackup.decode(data)
        let (other,_) = try rig();#expect(decoded.merge(into:other));#expect(other.tasks.count == 2)
        var object = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        object["tasks"] = (object["tasks"] as! [[String:Any]]).map { row in var r = row;r.removeValue(forKey:"skippedAt");r.removeValue(forKey:"reviewSourceID");return r }
        object["sessions"] = (object["sessions"] as! [[String:Any]]).map { row in var r = row;r.removeValue(forKey:"planBlockID");r.removeValue(forKey:"targetMinutes");return r }
        let legacy = try StudyBackup.decode(JSONSerialization.data(withJSONObject:object))
        #expect(legacy.tasks.allSatisfy { $0.skippedAt == nil && $0.reviewSourceID == nil })
    }
}

@Suite(.serialized) @MainActor struct GoalAndUndoTests {
    private func rig() throws -> (StudyStore, UsabilityClock) {
        let c = try Persistence.container(inMemory: true), clock = UsabilityClock()
        return (try StudyStore(context:c.mainContext,clock:clock), clock)
    }
    @Test func goalCompletionCanArchiveRemainingWorkAndUndoKeepsStudyTime() throws {
        let (s,c) = try rig(), g = StudyGoal(title:"Close scope"), r = RecurrenceRule(title:"Habit")
        r.goalID = g.id
        let t = StudyTask(goalID:g.id,title:"Unfinished")
        s.commit { s.context.insert(g);s.context.insert(r);s.context.insert(t) };s.start(t);c.now = c.now.addingTimeInterval(60)
        var d = GoalDefinition();d.title = g.title;d.complete = true
        #expect(s.updateGoal(g,definition:d,remaining:.archive) != nil)
        #expect(g.completedAt != nil && t.isArchived && !r.isEnabled && s.activeSession == nil)
        s.undoLastAction()
        #expect(g.completedAt == nil && !t.isArchived && r.isEnabled)
        #expect(s.sessions.first?.accumulatedActiveSeconds == 60 && s.activeSession == nil)
    }
    @Test func keepingRemainingGoalWorkDetachesItAndUndoRestoresTheLink() throws {
        let (s,_) = try rig(), g = StudyGoal(title:"Goal"), t = StudyTask(title:"Keep independently")
        t.goalID = g.id;s.commit { s.context.insert(g);s.context.insert(t) }
        var d = GoalDefinition();d.title = g.title;d.complete = true
        #expect(s.updateGoal(g,definition:d,remaining:.detach) != nil)
        #expect(t.goalID == nil && !t.isArchived)
        s.undoLastAction();#expect(t.goalID == g.id && g.completedAt == nil)
    }
    @Test func undoSessionCompletionKeepsActualTimeAndDoesNotReReserveConsumedBlock() throws {
        let (s,c) = try rig(), t = StudyTask(title:"Task")
        let b = StudyPlanBlock(taskID:t.id,day:c.now,startAt:c.now,durationMinutes:15)
        s.commit { s.context.insert(t);s.context.insert(b) };s.start(t,blockID:b.id);c.now = c.now.addingTimeInterval(900)
        #expect(s.finish(try #require(s.activeSession),rating:5,note:"Done",markComplete:true))
        s.undoLastAction()
        #expect(t.completedAt == nil && t.firstCompletedAt == nil && b.status == "completed")
        #expect(ProgressCalculator.actual(s.sessions.map(\.snapshot)) == 900)
    }
    @Test func newFormLeaseRejectsDelayedWritesFromAnOlderPresentation() {
        let r = DraftRepository(url:nil), first = UUID(), second = UUID()
        r.begin("form",lease:first);r.stage(ResourceDraft(title:"Old",url:""),for:"form",lease:first)
        r.begin("form",lease:second);r.stage(ResourceDraft(title:"New",url:""),for:"form",lease:second)
        r.stage(ResourceDraft(title:"Late old",url:""),for:"form",lease:first)
        #expect(r.value(ResourceDraft.self,for:"form")?.title == "New")
    }
}

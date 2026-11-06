import Foundation
import SwiftData
import Testing
@testable import StudyOS

@Suite(.serialized) @MainActor struct DraftMergeTests {
    @Test func restoredGoalNotesDoNotReopenAnExternallyCompletedGoal() {
        var base=GoalDefinition();base.title="Goal"
        var draft=GoalFormDraft(base:base,value:base);draft.value.details="Unfinished note"
        var current=base;current.complete=true
        let restored=draft.merged(over:current)
        #expect(restored.value.complete && restored.value.details == "Unfinished note")
    }
    @Test func restoredHabitDurationDoesNotUndoAnExternalPause() {
        var base=HabitDefinition();base.title="Habit"
        var draft=HabitFormDraft(base:base,value:base);draft.value.minutes=45
        var current=base;current.enabled=false
        let restored=draft.merged(over:current)
        #expect(!restored.value.enabled && restored.value.minutes == 45)
    }
    @Test func restoringNotesPreservesAnExternallyAddedDeadlineAndDeletedStep() {
        let original=StudyTask(title:"Task",steps:[ChecklistItem(title:"Remove externally")]).snapshot
        var draft=TaskFormDraft(task:original);draft.task.notes="Notes"
        var current=original;current.deadline=Date();current.steps=[]
        let restored=draft.merged(over:current)
        #expect(restored.hasDue && restored.task.deadline != nil && restored.task.steps.isEmpty && restored.task.notes == "Notes")
    }
    @Test func explicitLocalStepEditSurvivesOtherStepUpdates() {
        let original=StudyTask(title:"Task",steps:[ChecklistItem(title:"Old"),ChecklistItem(title:"Other")]).snapshot
        var draft=TaskFormDraft(task:original);draft.task.steps[0].title="Edited"
        var current=original;current.steps[1].isDone=true
        let restored=draft.merged(over:current)
        #expect(restored.task.steps[0].title == "Edited" && restored.task.steps[1].isDone)
    }
    @Test func malformedDraftFileIsPreservedBeforeNewDraftsAreWritten() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("drafts.json"), data=Data("broken".utf8)
        try data.write(to:url)
        let repo=DraftRepository(url:url)
        #expect(repo.error != nil)
        repo.stage(ResourceDraft(title:"New",url:""),for:"resource");repo.flush()
        let backup=try #require(FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).first { $0.lastPathComponent.hasPrefix("Drafts-recovery-") })
        #expect(try Data(contentsOf:backup) == data)
        #expect(DraftRepository(url:url).value(ResourceDraft.self,for:"resource")?.title == "New")
    }
    @Test func oneMalformedDraftIsRecoverableAfterReplacingItWithoutLosingOtherDrafts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("drafts.json"), bad = Data("unreadable draft".utf8)
        let good = try JSONEncoder().encode(ResourceDraft(title: "Other draft", url: "https://example.com"))
        try JSONEncoder().encode(["broken": bad, "other": good]).write(to: url)
        let repo = DraftRepository(url: url)
        #expect(repo.value(ResourceDraft.self, for: "broken") == nil)
        repo.stage(ResourceDraft(title: "Replacement", url: ""), for: "broken"); repo.flush()
        let reopened = DraftRepository(url: url)
        #expect(reopened.value(ResourceDraft.self, for: "other")?.title == "Other draft")
        #expect(reopened.value(ResourceDraft.self, for: "broken")?.title == "Replacement")
        let recovery = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.pathExtension == "bin" })
        #expect(try Data(contentsOf: recovery) == bad)
    }
    @Test func goalSubjectChangeUpdatesPendingWorkButPreservesSessionSubjectHistory() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext)
        let a=Subject(name:"Old"),b=Subject(name:"New"),g=StudyGoal(title:"Move goal")
        g.subjectID=a.id
        let t=StudyTask(subjectID:a.id,goalID:g.id,title:"Pending")
        let session=FocusSession(taskID:t.id,subjectID:a.id,startedAt:Date().addingTimeInterval(-60),endedAt:Date(),accumulatedActiveSeconds:60,status:"finished")
        s.commit { s.context.insert(a);s.context.insert(b);s.context.insert(g);s.context.insert(t);s.context.insert(session) }
        var d=GoalDefinition(goal:g);d.subjectID=b.id
        #expect(s.updateGoal(g,definition:d) != nil)
        #expect(t.subjectID == b.id && session.subjectID == a.id)
    }
    @Test func reflectionSavedAcrossMidnightStaysOnItsOpenedDay() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext)
        let old="1-2026-11-5"
        s.saveReview("Yesterday's reflection",dayKey:old)
        #expect(s.reviews.first?.dayKey == old)
    }
    @Test func aRoutineThatExpiredSinceTheLastRefreshCannotStart() throws {
        final class Clock:ClockProvider { var now=Calendar.current.startOfDay(for:Date()).addingTimeInterval(3600) }
        let c=try Persistence.container(inMemory:true),clock=Clock(),s=try StudyStore(context:c.mainContext,clock:clock)
        let task=StudyTask(title:"Habit",scheduledDay:clock.now,recurrenceID:UUID())
        s.commit { s.context.insert(task) }
        clock.now=Calendar.current.date(byAdding:.day,value:1,to:clock.now)!
        #expect(!s.start(task) && s.activeSession == nil)
    }
}

@Suite(.serialized) @MainActor struct HistoryMoveTests {
    @Test func reschedulingMissedWorkKeepsTheOldDayAndMakesOnlyOneNewReservation() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext)
        let now=s.clock.now,cal=Calendar.current
        let old=cal.date(byAdding:.day,value:-1,to:now)!,future=cal.date(byAdding:.day,value:1,to:now)!
        let task=StudyTask(title:"Missed assignment"),b=StudyPlanBlock(day:old,startAt:old)
        b.taskID=task.id
        s.commit { s.context.insert(task);s.context.insert(b) }
        let p=PlanSuggestion(taskID:task.id,day:cal.startOfDay(for:future),startAt:StudyTime.atMinute(540,on:future),minutes:30,reason:"Move missed work")
        #expect(s.saveBlock(b,suggestion:p,locked:false))
        #expect(b.status == "missed" && cal.isDate(b.day,inSameDayAs:old))
        #expect(s.blocks.filter { $0.status == "confirmed" }.count == 1)
    }
}

@Suite(.serialized) @MainActor struct RestoreTests {
    @Test func returningToALegacyArchivedActiveSessionDoesNotCreateAnotherSession() throws {
        let c = try Persistence.container(inMemory: true), s = try StudyStore(context: c.mainContext)
        let task = StudyTask(title: "Legacy active task")
        s.commit { s.context.insert(task) }
        #expect(s.start(task))
        let sessionID = try #require(s.activeSession?.id)
        // Previous versions allowed archiving without settling the active session.
        task.isArchived = true
        try s.context.save()
        s.presentFocus(task, resume: false)
        #expect(s.focusRoute?.taskID == task.id && s.activeSession?.id == sessionID && s.sessions.count == 1)
        #expect(!s.start(task))
    }
    @Test func restoringAnArchivedTaskDoesNotReopenItsClosedGoal() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext)
        let g=StudyGoal(title:"Closed",isArchived:true),t=StudyTask(title:"Restore",isArchived:true)
        t.goalID=g.id;s.commit { s.context.insert(g);s.context.insert(t) }
        s.restoreTask(t)
        #expect(!t.isArchived && t.goalID == nil && g.isArchived)
    }
}

@Suite(.serialized) @MainActor struct NotificationNavigationTests {
    @Test func notificationReceivedBeforeTheUIIsReadyIsDeliveredOnceAfterBinding() {
        let service=NotificationService(),id=UUID();var received:[UUID]=[]
        service.navigate(taskID:id,goalID:nil,blockID:nil)
        service.route = { task,_,_ in if let task { received.append(task) } }
        #expect(received == [id] && service.receivedNotification)
        service.route = { task,_,_ in if let task { received.append(task) } }
        #expect(received == [id])
    }
    @Test func taskNotificationNavigatesWithoutStartingOrInventingStudyTime() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext),t=StudyTask(title:"Notification")
        s.commit { s.context.insert(t) }
        #expect(s.openNotification(taskID:t.id,goalID:nil,blockID:nil) == 1)
        #expect(s.taskDestination?.taskID == t.id && s.sessions.isEmpty && s.focusRoute == nil)
    }
    @Test func navigatingToOtherWorkPausesTheCurrentTimerWithoutDiscardingIt() throws {
        let c=try Persistence.container(inMemory:true),s=try StudyStore(context:c.mainContext),a=StudyTask(title:"Current"),b=StudyTask(title:"Other")
        s.commit { s.context.insert(a);s.context.insert(b) };s.start(a)
        _ = s.openNotification(taskID:b.id,goalID:nil,blockID:nil)
        #expect(s.activeSession?.taskID == a.id && s.activeSession?.status == "paused" && s.taskDestination?.taskID == b.id)
    }
}

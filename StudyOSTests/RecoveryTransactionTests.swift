import Foundation
import SwiftData
import Testing
@testable import StudyOS

private final class RecoveryClock: ClockProvider {
    var now: Date
    init(_ now: Date) { self.now = now }
}
@MainActor private final class RecoverySaveFailure { var fails = false }

@Suite(.serialized) @MainActor struct RecoveryTransactionTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func seed(_ url: URL) throws {
        let c = try Persistence.container(url: url), clock = RecoveryClock(start), s = try StudyStore(context: c.mainContext, clock: clock)
        let t = StudyTask(title: "Recover actual time")
        #expect(s.commit { s.context.insert(t) }); #expect(s.start(t))
        let active = try #require(s.activeSession)
        clock.now = start.addingTimeInterval(300)
        #expect(s.commit { active.accumulatedActiveSeconds = s.elapsed(active); active.activeIntervalStartedAt = clock.now })
    }
    private func assertFailedResolutionCanRetry(include: Bool) throws {
        let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
        let url = f.appendingPathComponent("Study.store"); try seed(url)
        let c = try Persistence.container(url: url), failure = RecoverySaveFailure()
        let s = try StudyStore(context: c.mainContext, clock: RecoveryClock(start.addingTimeInterval(3900)), saveContext: { context in
            if failure.fails { throw StudyError.invalid("Simulated disk write failure") }
            try context.save()
        })
        let gap = try #require(s.recoveredGap)
        failure.fails = true
        #expect(!s.resolveRecoveredGap(include: include))
        #expect(s.activeSession?.accumulatedActiveSeconds == 300 && s.recoveredGap == gap)
        failure.fails = false; s.error = nil
        #expect(s.resolveRecoveredGap(include: include))
        let expected = include ? 3900.0 : 300.0
        #expect(s.activeSession?.accumulatedActiveSeconds == expected && s.recoveredGap == nil)
        #expect(!s.resolveRecoveredGap(include: true))
        let reopened = try Persistence.container(url: url), again = try StudyStore(context: reopened.mainContext, clock: RecoveryClock(start.addingTimeInterval(4500)))
        #expect(again.recoveredGap == nil && again.activeSession?.accumulatedActiveSeconds == expected)
    }
    @Test func failedAcceptanceRollsBackAndRemainsRetryableWithoutDoubleCredit() throws {
        try assertFailedResolutionCanRetry(include: true)
    }
    @Test func failedDeclineRollsBackAndRemainsRetryableAcrossDiskPersistence() throws {
        try assertFailedResolutionCanRetry(include: false)
    }
    @Test func pendingChoiceCannotBeBypassedByResumeFinishOrParentArchive() throws {
        let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
        let url = f.appendingPathComponent("Study.store"); try seed(url)
        let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: RecoveryClock(start.addingTimeInterval(3900)))
        let gap = try #require(s.recoveredGap), session = try #require(s.activeSession), task = try #require(s.task(session.taskID))
        s.presentFocus(task)
        #expect(session.status == "paused" && s.focusRoute?.taskID == task.id)
        #expect(!s.resume(session))
        #expect(!s.finish(session, rating: nil, note: "", markComplete: true))
        s.applyArchive(ArchiveRequest(kind: .task, recordID: task.id), includeRelated: true)
        #expect(!task.isArchived && session.status == "paused" && s.recoveredGap == gap)
        #expect(session.accumulatedActiveSeconds == 300)
    }
    @Test func explicitDiscardClearsPendingChoiceAndNeverCreditsItsTime() throws {
        let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
        let url = f.appendingPathComponent("Study.store"); try seed(url)
        let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: RecoveryClock(start.addingTimeInterval(3900)))
        let session = try #require(s.activeSession)
        #expect(s.discard(session))
        #expect(s.recoveredGap == nil && session.pendingRecoveryStartedAt == nil && session.pendingRecoveryEndedAt == nil)
        #expect(ProgressCalculator.actual(s.sessions.map(\.snapshot)) == 0)
        let reopened = try Persistence.container(url: url), again = try StudyStore(context: reopened.mainContext)
        #expect(again.recoveredGap == nil && again.activeSession == nil)
    }
    @Test func backupRetainsThePendingChoiceButImportNeverCreditsOrRevivesIt() throws {
        let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
        let url = f.appendingPathComponent("Study.store"); try seed(url)
        let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: RecoveryClock(start.addingTimeInterval(3900)))
        let encoded = try StudyBackup(store: s).encoded(), decoded = try StudyBackup.decode(encoded)
        #expect(decoded.sessions.first?.pendingRecoveryStartedAt == s.recoveredGap?.start)
        let other = try Persistence.container(inMemory: true), destination = try StudyStore(context: other.mainContext)
        #expect(decoded.merge(into: destination))
        #expect(destination.activeSession == nil && destination.recoveredGap == nil)
        #expect(destination.sessions.allSatisfy { $0.pendingRecoveryStartedAt == nil && $0.pendingRecoveryEndedAt == nil })
        #expect(ProgressCalculator.actual(destination.sessions.map(\.snapshot)) == 0)
        var invalid = decoded; invalid.sessions[0].pendingRecoveryEndedAt = nil
        #expect(throws: StudyError.self) { try invalid.validate() }
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["sessions"] = (legacy["sessions"] as! [[String: Any]]).map { value in var item = value; item.removeValue(forKey: "pendingRecoveryStartedAt"); item.removeValue(forKey: "pendingRecoveryEndedAt"); return item }
        let old = try StudyBackup.decode(JSONSerialization.data(withJSONObject: legacy))
        #expect(old.sessions.allSatisfy { $0.pendingRecoveryStartedAt == nil && $0.pendingRecoveryEndedAt == nil })
    }
    @Test func deliveredFocusReminderIsRemovedAfterPauseFinishDiscardOrDisable() {
        let task = StudyTask(title: "Notification cleanup")
        let session = FocusSession(taskID: task.id, status: "running")
        var preferences = UserPreferences().snapshot; preferences.notificationsEnabled = true
        func snapshot() -> NotificationSnapshot { NotificationSnapshot(preferences: preferences, blocks: [], tasks: [task.snapshot], goals: [], sessions: [session.snapshot]) }
        let id = "focus.\(session.id)"
        #expect(!NotificationService.shouldRemoveDeliveredFocus(id, snapshot: snapshot()))
        for status in ["paused", "finished", "discarded"] {
            session.status = status
            #expect(NotificationService.shouldRemoveDeliveredFocus(id, snapshot: snapshot()))
        }
        session.status = "running"
        #expect(NotificationService.shouldRemoveDeliveredFocus("focus.\(UUID())", snapshot: snapshot()))
        preferences.notificationsEnabled = false
        #expect(NotificationService.shouldRemoveDeliveredFocus(id, snapshot: snapshot()))
    }
    @Test func carryOverKeepsTimerAndPastHistoryAndUndoRestoresTheDate() throws {
        let cal = Calendar.current, today = cal.startOfDay(for: start), yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let c = try Persistence.container(inMemory: true), clock = RecoveryClock(yesterday.addingTimeInterval(3600)), s = try StudyStore(context: c.mainContext, clock: clock)
        let task = StudyTask(title: "Overnight", scheduledDay: yesterday), b = StudyPlanBlock(day: yesterday)
        b.taskID = task.id; s.commit { s.context.insert(task); s.context.insert(b) }; s.start(task, blockID: b.id)
        let session = try #require(s.activeSession), id = session.id
        #expect(s.pause(session)); clock.now = today.addingTimeInterval(3600); s.commit {}
        s.carryOver([task], toToday: true)
        #expect(s.dayTasks(today).contains { $0.id == task.id })
        #expect(s.dayTasks(yesterday).contains { $0.id == task.id })
        #expect(s.activeSession?.id == id && b.day == yesterday && b.status == "confirmed")
        s.undoLastAction()
        #expect(task.scheduledDay == yesterday && !s.dayTasks(today).contains { $0.id == task.id })
    }
}

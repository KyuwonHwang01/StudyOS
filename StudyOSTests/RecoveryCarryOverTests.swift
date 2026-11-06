import Foundation
import SwiftData
import Testing
@testable import StudyOS

private final class ReviewClock: ClockProvider {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@Suite(.serialized) @MainActor struct RecoveryCarryOverTests {
    @Test func unansweredRecoveryOfferSurvivesAnotherLaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Review.store")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: ReviewClock(start))
            let t = StudyTask(title: "Pending recovery")
            #expect(s.commit { s.context.insert(t) }); #expect(s.start(t))
        }
        var offer: RecoveredGap?
        do {
            let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: ReviewClock(start.addingTimeInterval(3600)))
            offer = try #require(s.recoveredGap)
            #expect(s.activeSession?.status == "paused")
        }
        do {
            let c = try Persistence.container(url: url), s = try StudyStore(context: c.mainContext, clock: ReviewClock(start.addingTimeInterval(3660)))
            #expect(s.recoveredGap == offer, "An unanswered choice should remain available after another launch, without extending its interval.")
            #expect(s.activeSession?.accumulatedActiveSeconds == 0)
        }
    }
    @Test func realStudyLeavingTwentyMinutesStillSchedulesTwoQuarterHours() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))!
        let t = StudyTask(title: "Twenty minutes left", estimatedMinutes: 30)
        let other = StudyTask(title: "Next task", estimatedMinutes: 30)
        let saved = FocusSession(taskID: t.id, startedAt: now.addingTimeInterval(-1200), endedAt: now.addingTimeInterval(-600), accumulatedActiveSeconds: 600, status: "finished")
        let p = UserPreferences(availability: Array(repeating: 120, count: 7)).snapshot
        let result = PlanningEngine.generate(tasks: [t.snapshot, other.snapshot], goals: [], blocks: [], sessions: [saved.snapshot], preferences: p, now: now, calendar: cal)
        #expect(result.suggestions.filter { $0.taskID == t.id }.reduce(0) { $0 + $1.minutes } == 30)
        #expect(result.suggestions.contains { $0.taskID == other.id })
    }
    @Test func carryingAnActivePreviousDayTaskActuallyAppearsToday() throws {
        let cal = Calendar.current, now = Date(), today = cal.startOfDay(for: now), yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        let c = try Persistence.container(inMemory: true), clock = ReviewClock(yesterday.addingTimeInterval(3600)), s = try StudyStore(context: c.mainContext, clock: clock)
        let task = StudyTask(title: "Overnight active task", scheduledDay: yesterday)
        let b = StudyPlanBlock(taskID: task.id, day: yesterday, durationMinutes: 30)
        s.commit { s.context.insert(task); s.context.insert(b) }; s.start(task, blockID: b.id)
        clock.now = today.addingTimeInterval(3600); s.commit {}
        #expect(s.carriedOverTasks(now: clock.now).contains { $0.id == task.id })
        s.carryOver([task], toToday: true)
        #expect(s.dayTasks(today).contains { $0.id == task.id }, "Move to today must show the task on Today even while its previous-day session is open.")
    }

}

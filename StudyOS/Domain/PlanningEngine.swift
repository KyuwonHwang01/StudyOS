import Foundation

struct PlanSuggestion: Identifiable, Equatable, Sendable {
    var id: String { "\(taskID)-\(StudyTime.dayKey(day))-\(startAt?.timeIntervalSince1970 ?? 0)" }
    var taskID: UUID
    var day: Date
    var startAt: Date?
    var minutes: Int
    var reason: String
}
struct PlanningResult: Sendable { var suggestions: [PlanSuggestion]; var warnings: [String] }

enum PlanningEngine {
    static func reservedMinutes(_ block: StudyPlanBlockSnapshot, sessions: [FocusSessionSnapshot]) -> Int {
        guard block.status == "confirmed" else { return 0 }
        let spent = sessions.filter { $0.status == "finished" && $0.planBlockID == block.id }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
        return max(0, Int(ceil((Double(block.durationMinutes * 60) - spent) / 60)))
    }
    static func isExpiredRoutine(_ task: StudyTaskSnapshot, blocks: [StudyPlanBlockSnapshot], sessions: [FocusSessionSnapshot], now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        return task.recurrenceID != nil && task.deadline == nil && task.scheduledDay.map { $0 < today } == true &&
            !blocks.contains { $0.taskID == task.id && $0.status == "confirmed" && calendar.startOfDay(for: $0.day) >= today } &&
            !sessions.contains { $0.taskID == task.id && ["running", "paused"].contains($0.status) }
    }

    static func priority(due: Date?, remaining: Int, capacity: Int, priority: Int, now: Date) -> Double {
        let urgency = due.map { max(0, min(1, 1 - $0.timeIntervalSince(now) / (14 * 86400))) } ?? 0.1
        let risk = min(1, Double(remaining) / Double(max(1, capacity)))
        return 0.45 * urgency + 0.35 * risk + 0.2 * Double(priority) / 3
    }
    static func overlaps(start: Date, minutes: Int, otherStart: Date, otherMinutes: Int) -> Bool {
        start < otherStart.addingTimeInterval(Double(otherMinutes * 60)) &&
        otherStart < start.addingTimeInterval(Double(minutes * 60))
    }
    static func generate(tasks: [StudyTaskSnapshot], goals: [StudyGoalSnapshot], blocks: [StudyPlanBlockSnapshot],
                         sessions: [FocusSessionSnapshot], preferences: UserPreferencesSnapshot,
                         now: Date, calendar: Calendar = .current) -> PlanningResult {
        let today = calendar.startOfDay(for: now)
        let live = tasks.filter { !$0.isArchived && $0.completedAt == nil && $0.skippedAt == nil && !isExpiredRoutine($0, blocks: blocks, sessions: sessions, now: now, calendar: calendar) }
        let preserved = blocks.filter { $0.status == "confirmed" }
        var suggestions: [PlanSuggestion] = []
        var warnings: [String] = []
        var remaining: [UUID: Int] = [:]
        func due(_ task: StudyTaskSnapshot) -> Date? {
            let taskDue = task.deadline.map { task.deadlineDateOnly ? StudyTime.endOfDay($0, calendar: calendar) : $0 }
            let goal = goals.first { $0.id == task.goalID && !$0.isArchived }
            let goalDue = goal?.dueAt.map { goal!.isDateOnly ? StudyTime.endOfDay($0, calendar: calendar) : $0 }
            return [taskDue, goalDue].compactMap { $0 }.min()
        }
        for task in live {
            let actual = sessions.filter { $0.taskID == task.id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
            let reserved = preserved.filter { $0.taskID == task.id && $0.day >= today }.reduce(0) { $0 + reservedMinutes($1, sessions: sessions) }
            remaining[task.id] = max(0, max(15, task.estimatedMinutes - Int(actual / 60)) - reserved)
            if let d = due(task), d < now, remaining[task.id, default: 0] > 0 {
                warnings.append("\(task.title): deadline has passed. Update the deadline before planning.")
            }
        }
        for offset in 0..<7 {
            if Task.isCancelled { return PlanningResult(suggestions: [], warnings: []) }
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let weekday = calendar.component(.weekday, from: day) - 1
            let dailyLimit = min(preferences.maxDailyMinutes, preferences.availability[weekday])
            let existing = preserved.filter { calendar.isDate($0.day, inSameDayAs: day) }
            let spent = sessions.filter { $0.status == "finished" && calendar.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
            var budget = max(0, dailyLimit - Int(ceil(spent / 60)) - existing.reduce(0) { $0 + reservedMinutes($1, sessions: sessions) })
            let windowEnd = StudyTime.atMinute(preferences.windowEnd, on: day, calendar: calendar)
            var cursor = max(StudyTime.atMinute(preferences.windowStart, on: day, calendar: calendar), now)
            // Round up to a calendar quarter hour; never suggest a past start.
            let minuteOfDay = calendar.component(.hour, from: cursor) * 60 + calendar.component(.minute, from: cursor)
            let rounded = ((minuteOfDay + (calendar.component(.second, from: cursor) > 0 ? 1 : 0) + 14) / 15) * 15
            guard rounded < 1440 else { continue }
            cursor = StudyTime.atMinute(rounded, on: day, calendar: calendar)
            var allocated: [UUID: Int] = [:]
            while budget >= 15 && cursor < windowEnd {
                if Task.isCancelled { return PlanningResult(suggestions: [], warnings: []) }
                let candidates = live.filter { task in
                    remaining[task.id, default: 0] > 0 && (due(task) == nil || due(task)! > cursor) &&
                    (task.scheduledDay.map { $0 < today || calendar.isDate($0, inSameDayAs: day) } ?? true)
                }.sorted { a, b in
                    func score(_ t: StudyTaskSnapshot) -> Double {
                        priority(due: due(t), remaining: remaining[t.id, default: 0], capacity: max(1, dailyLimit * 7), priority: t.priority, now: now)
                        - Double(allocated[t.subjectID ?? t.id, default: 0]) / 90
                    }
                    let x = score(a), y = score(b)
                    return x == y ? a.id.uuidString < b.id.uuidString : x > y
                }
                let nextFixed = existing.compactMap { block -> Date? in
                    guard let start = block.startAt, start.addingTimeInterval(Double(block.durationMinutes * 60)) > cursor else { return nil }
                    return start
                }.min()
                if let fixed = nextFixed, fixed <= cursor {
                    let end = existing.filter { $0.startAt != nil && $0.startAt! <= cursor }.map { $0.startAt!.addingTimeInterval(Double($0.durationMinutes * 60)) }.max()!
                    cursor = end; continue
                }
                var slot = min(60, budget, Int(windowEnd.timeIntervalSince(cursor) / 60))
                if let fixed = nextFixed { slot = min(slot, Int(fixed.timeIntervalSince(cursor) / 60)) }
                guard slot >= 15 else {
                    if let fixed = nextFixed, let block = existing.first(where: { $0.startAt == fixed }) {
                        cursor = fixed.addingTimeInterval(Double(block.durationMinutes * 60)); continue
                    }
                    break
                }
                // A task that cannot fit a 15-minute block here (e.g. due in 10 minutes) must not end the day for the others.
                func fitted(_ task: StudyTaskSnapshot) -> Int {
                    var length = min(slot, (remaining[task.id, default: 0] + 14) / 15 * 15)
                    if let dueDate = due(task) { length = min(length, Int(dueDate.timeIntervalSince(cursor) / 60)) }
                    return length / 15 * 15
                }
                guard let task = candidates.first(where: { fitted($0) >= 15 }) else { break }
                let length = fitted(task)
                let reason = "\(task.priority == 3 ? "High priority. " : "")\(due(task) != nil ? "Deadline-aware allocation. " : "Balanced subject allocation. ")\(length) min within your availability."
                suggestions.append(PlanSuggestion(taskID: task.id, day: day, startAt: cursor, minutes: length, reason: reason))
                remaining[task.id] = max(0, remaining[task.id, default: 0] - length)
                allocated[task.subjectID ?? task.id, default: 0] += length
                budget -= length
                cursor = cursor.addingTimeInterval(Double(length * 60))
            }
        }
        let horizon = calendar.date(byAdding: .day, value: 7, to: today)!
        // Only tasks the planner could place count: overdue tasks already have their own warning, and tasks dated past the 7-day window are not due for planning yet.
        let unplaced = live.filter { task in
            remaining[task.id, default: 0] > 0 && !(due(task).map { $0 < now } ?? false) && !(task.scheduledDay.map { $0 >= horizon } ?? false)
        }
        if !unplaced.isEmpty { warnings.append("Not enough available study time. Adjust availability, deadlines, or task estimates.") }
        return PlanningResult(suggestions: suggestions, warnings: warnings)
    }
}

enum ProgressCalculator {
    static func completion(done: Int, total: Int) -> Double? { total == 0 ? nil : Double(done) / Double(total) }
    static func actual(_ sessions: [FocusSessionSnapshot]) -> Double {
        sessions.filter { $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
    }
    static func consistency(_ sessions: [FocusSessionSnapshot], now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let groups = Dictionary(grouping: sessions.filter { $0.status == "finished" && ($0.endedAt ?? $0.startedAt) >= start && ($0.endedAt ?? $0.startedAt) <= now }) {
            StudyTime.dayKey($0.endedAt ?? $0.startedAt, calendar: calendar)
        }
        return groups.values.filter { $0.reduce(0) { $0 + $1.accumulatedActiveSeconds } >= 600 }.count
    }
}

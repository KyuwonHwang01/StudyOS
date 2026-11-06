import Foundation

enum CoachingEngine {
    static func notes(tasks: [StudyTaskSnapshot], goals: [StudyGoalSnapshot], blocks: [StudyPlanBlockSnapshot],
                      sessions: [FocusSessionSnapshot], preferences: UserPreferencesSnapshot, now: Date,
                      calendar: Calendar = .current) -> [String] {
        var notes: [String] = []
        let active = tasks.filter { !$0.isArchived && $0.completedAt == nil }
        for goal in goals where !goal.isArchived && goal.completedAt == nil {
            guard let date = goal.dueAt else { continue }
            let due = goal.isDateOnly ? StudyTime.endOfDay(date, calendar: calendar) : date
            let remaining = active.filter { $0.goalID == goal.id }.reduce(0) { $0 + $1.estimatedMinutes }
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0)
            var capacity = 0
            if days <= 365 {
                for offset in 0...days {
                    let day = calendar.date(byAdding: .day, value: offset, to: now)!
                    capacity += min(preferences.maxDailyMinutes, preferences.availability[calendar.component(.weekday, from: day) - 1])
                }
            } else { capacity = Int.max }
            if due < now { notes.append("\(goal.title): its deadline has passed. Review the goal and set a realistic next step.") }
            else if remaining > capacity { notes.append("\(goal.title): \(remaining) estimated minutes exceed your \(capacity) available minutes before the deadline. Reduce scope or revise the plan.") }
            else if days <= 3 && remaining >= 60 { notes.append("\(goal.title) is due within three days. Consider an early focus block for the remaining \(remaining) estimated minutes.") }
        }
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        // Today's occurrences are still in progress, so only finished days count toward the completion rate.
        let recent = tasks.filter { $0.recurrenceID != nil && ($0.scheduledDay ?? .distantPast) >= weekStart && ($0.scheduledDay ?? .distantFuture) < calendar.startOfDay(for: now) && !$0.isArchived }
        let groups = Dictionary(grouping: recent) { $0.recurrenceID! }
        for items in groups.values where items.count >= 2 && items.filter({ $0.completedAt != nil }).count * 2 < items.count {
            notes.append("\(items[0].title): fewer than half of recent occurrences are complete. Try a shorter, manageable block.")
        }
        let recentBlocks = blocks.filter { $0.day >= weekStart && $0.day < calendar.startOfDay(for: now) && $0.status != "canceled" }
        if recentBlocks.count >= 3 && recentBlocks.filter({ $0.status == "completed" }).count * 2 < recentBlocks.count {
            notes.append("Less than half of your recent planned blocks are complete. Smaller blocks or a lighter daily plan may help.")
        }
        let lowRatings = sessions.filter { $0.status == "finished" && ($0.endedAt ?? .distantPast) >= weekStart && (1...2).contains($0.understandingRating ?? 0) }
        if lowRatings.count >= 2 { notes.append("You rated understanding 1–2 in \(lowRatings.count) recent sessions. Consider a short review block. This reflects self-ratings, not a measured skill level.") }
        return Array(notes.prefix(5))
    }
}

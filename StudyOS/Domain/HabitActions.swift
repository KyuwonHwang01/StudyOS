import Foundation

struct HabitDefinition: Codable, Equatable {
    var title = ""; var subjectID: UUID?; var minutes = 30; var weekdays = Set(1...7)
    var enabled = true; var start = Date(); var end = Date(); var hasEnd = false
}

@MainActor extension StudyStore {
    func updateHabit(_ rule: RecurrenceRule?, definition: HabitDefinition, removeFuture: Bool) -> Bool {
        let r = rule ?? RecurrenceRule()
        let result = commit({
            let today = Calendar.current.startOfDay(for: clock.now)
            for t in tasks where t.recurrenceID == r.id && t.firstCompletedAt == nil && (t.scheduledDay ?? .distantPast) >= today && !t.isArchived {
                let planned = blocks.contains { $0.taskID == t.id && $0.status == "confirmed" }
                if planned && !removeFuture { continue }
                if removeFuture, let s = activeSession, s.taskID == t.id {
                    s.accumulatedActiveSeconds = elapsed(s); s.activeIntervalStartedAt = nil; s.status = s.accumulatedActiveSeconds >= 1 ? "finished" : "discarded"; s.endedAt = max(s.startedAt, clock.now)
                    settleBlock(for: s)
                }
                if activeSession?.taskID == t.id { continue }
                if removeFuture {
                    for b in blocks where b.taskID == t.id && b.status == "confirmed" { b.status = "canceled" }
                    t.skippedAt = clock.now
                }
                let day = t.scheduledDay!
                let valid = definition.enabled && definition.weekdays.contains(Calendar.current.component(.weekday, from: day)) && day >= Calendar.current.startOfDay(for: definition.start) && (!definition.hasEnd || day <= StudyTime.endOfDay(definition.end))
                if sessions.contains(where: { $0.taskID == t.id && $0.status == "finished" }) {
                    if valid { t.skippedAt = nil }
                    continue
                }
                t.skippedAt = valid ? nil : clock.now
                t.title = definition.title; t.subjectID = definition.subjectID; t.estimatedMinutes = definition.minutes
            }
            r.title = definition.title; r.subjectID = definition.subjectID; r.duration = definition.minutes; r.weekdays = definition.weekdays.sorted()
            r.isEnabled = definition.enabled; r.startDate = definition.start; r.endDate = definition.hasEnd ? definition.end : nil
            if rule == nil { context.insert(r) }
        })
        return result
    }
}

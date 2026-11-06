import Foundation

struct GoalDefinition: Codable, Equatable {
    var title = ""; var details = ""; var subjectID: UUID?
    var hasDue = false; var due = Date(); var dateOnly = true; var priority = 2; var target = 0; var complete = false
}
enum RemainingGoalWork { case keep, archive, detach }

@MainActor extension StudyStore {
    func updateGoal(_ goal: StudyGoal?, definition: GoalDefinition, remaining: RemainingGoalWork = .keep) -> StudyGoal? {
        let g = goal ?? StudyGoal(), before = StudyUndo.capture(self)
        let closing = definition.complete && g.completedAt == nil
        let affected = tasks.filter { $0.goalID == g.id && $0.completedAt == nil && !$0.isArchived && $0.skippedAt == nil }
        if commit({
            if g.subjectID != definition.subjectID {
                for t in affected { t.subjectID = definition.subjectID }
                for r in rules where r.goalID == g.id { r.subjectID = definition.subjectID }
            }
            g.title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines); g.details = definition.details; g.subjectID = definition.subjectID
            g.dueAt = definition.hasDue ? definition.due : nil; g.isDateOnly = definition.dateOnly; g.priority = definition.priority; g.targetMinutes = definition.target
            g.completedAt = definition.complete ? (g.completedAt ?? clock.now) : nil
            if goal == nil { context.insert(g) }
            if closing {
                for r in rules where r.goalID == g.id { r.isEnabled = false }
                if remaining == .archive {
                    let ids = Set(affected.map(\.id))
                    if let s = activeSession, ids.contains(s.taskID) {
                        s.accumulatedActiveSeconds = elapsed(s); s.activeIntervalStartedAt = nil
                        s.status = s.accumulatedActiveSeconds >= 1 ? "finished" : "discarded"; s.endedAt = max(clock.now, s.startedAt); settleBlock(for: s)
                    }
                    for t in affected { t.isArchived = true }
                    for b in blocks where ids.contains(b.taskID) && b.status == "confirmed" { b.status = "canceled" }
                } else if remaining == .detach { for t in affected { t.goalID = nil } }
            }
        }) {
            if closing && goal != nil { showToast("Goal completed", undo: before) }
            return g
        }
        return nil
    }
}

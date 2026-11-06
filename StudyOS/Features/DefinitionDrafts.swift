import Foundation

private func mergeField<Root, Value: Equatable>(_ key: WritableKeyPath<Root, Value>, base: Root, edited: Root, into current: inout Root) {
    if edited[keyPath:key] != base[keyPath:key] { current[keyPath:key] = edited[keyPath:key] }
}
struct GoalFormDraft: Codable, Equatable {
    var base: GoalDefinition
    var value: GoalDefinition
    func merged(over current: GoalDefinition) -> GoalFormDraft {
        var v = current
        mergeField(\.title,base:base,edited:value,into:&v);mergeField(\.details,base:base,edited:value,into:&v)
        mergeField(\.subjectID,base:base,edited:value,into:&v);mergeField(\.hasDue,base:base,edited:value,into:&v)
        mergeField(\.due,base:base,edited:value,into:&v);mergeField(\.dateOnly,base:base,edited:value,into:&v)
        mergeField(\.priority,base:base,edited:value,into:&v);mergeField(\.target,base:base,edited:value,into:&v)
        mergeField(\.complete,base:base,edited:value,into:&v)
        return GoalFormDraft(base:current,value:v)
    }
}
struct HabitFormDraft: Codable, Equatable {
    var base: HabitDefinition
    var value: HabitDefinition
    func merged(over current: HabitDefinition) -> HabitFormDraft {
        var v = current
        mergeField(\.title,base:base,edited:value,into:&v);mergeField(\.subjectID,base:base,edited:value,into:&v)
        mergeField(\.minutes,base:base,edited:value,into:&v);mergeField(\.weekdays,base:base,edited:value,into:&v)
        mergeField(\.enabled,base:base,edited:value,into:&v);mergeField(\.start,base:base,edited:value,into:&v)
        mergeField(\.end,base:base,edited:value,into:&v);mergeField(\.hasEnd,base:base,edited:value,into:&v)
        return HabitFormDraft(base:current,value:v)
    }
}
extension GoalDefinition {
    init(goal: StudyGoal?, subjectID: UUID? = nil) {
        self.init();self.subjectID = subjectID
        if let g = goal { title = g.title; details = g.details; self.subjectID = g.subjectID; hasDue = g.dueAt != nil; due = g.dueAt ?? Date(); dateOnly = g.isDateOnly; priority = g.priority; target = g.targetMinutes; complete = g.completedAt != nil }
    }
}
extension HabitDefinition {
    init(rule: RecurrenceRule?) {
        self.init()
        if let r = rule { title = r.title; subjectID = r.subjectID; minutes = r.duration; weekdays = Set(r.weekdays); enabled = r.isEnabled; start = r.startDate; end = r.endDate ?? Date(); hasEnd = r.endDate != nil }
    }
}

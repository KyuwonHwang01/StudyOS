import Foundation
import SwiftData

struct ChecklistItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var isDone = false
}
struct ResourceLink: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var url: String
}

@Model
final class Subject {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var symbol: String
    var isArchived: Bool
    var isSample: Bool
    init(id: UUID = UUID(), createdAt: Date = Date(), name: String = "", symbol: String = "book.closed", isArchived: Bool = false, isSample: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.symbol = symbol
        self.isArchived = isArchived
        self.isSample = isSample
    }
    var snapshot: SubjectSnapshot {
        SubjectSnapshot(id: id, createdAt: createdAt, name: name, symbol: symbol, isArchived: isArchived, isSample: isSample)
    }
}
struct SubjectSnapshot: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var name: String
    var symbol: String
    var isArchived: Bool
    var isSample: Bool
    func model() -> Subject {
        Subject(id: id, createdAt: createdAt, name: name, symbol: symbol, isArchived: isArchived, isSample: isSample)
    }
}

@Model
final class StudyGoal {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var title: String
    var details: String
    var dueAt: Date?
    var isDateOnly: Bool
    var priority: Int
    var targetMinutes: Int
    var isArchived: Bool
    var completedAt: Date?
    init(id: UUID = UUID(), createdAt: Date = Date(), subjectID: UUID? = nil, title: String = "", details: String = "", dueAt: Date? = nil, isDateOnly: Bool = true, priority: Int = 2, targetMinutes: Int = 0, isArchived: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.subjectID = subjectID
        self.title = title
        self.details = details
        self.dueAt = dueAt
        self.isDateOnly = isDateOnly
        self.priority = priority
        self.targetMinutes = targetMinutes
        self.isArchived = isArchived
        self.completedAt = completedAt
    }
    var snapshot: StudyGoalSnapshot {
        StudyGoalSnapshot(id: id, createdAt: createdAt, subjectID: subjectID, title: title, details: details, dueAt: dueAt, isDateOnly: isDateOnly, priority: priority, targetMinutes: targetMinutes, isArchived: isArchived, completedAt: completedAt)
    }
}
struct StudyGoalSnapshot: Codable, Sendable, Equatable {
    var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var title: String
    var details: String
    var dueAt: Date?
    var isDateOnly: Bool
    var priority: Int
    var targetMinutes: Int
    var isArchived: Bool
    var completedAt: Date?
    func model() -> StudyGoal {
        StudyGoal(id: id, createdAt: createdAt, subjectID: subjectID, title: title, details: details, dueAt: dueAt, isDateOnly: isDateOnly, priority: priority, targetMinutes: targetMinutes, isArchived: isArchived, completedAt: completedAt)
    }
}

@Model
final class StudyTask {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var goalID: UUID?
    var title: String
    var notes: String
    var estimatedMinutes: Int
    var priority: Int
    var deadline: Date?
    var deadlineDateOnly: Bool
    var scheduledDay: Date?
    var isArchived: Bool
    var completedAt: Date?
    var firstCompletedAt: Date?
    var recurrenceID: UUID?
    var occurrenceKey: String?
    var skippedAt: Date?
    var reviewSourceID: UUID?
    var steps: [ChecklistItem]
    var resources: [ResourceLink]
    init(id: UUID = UUID(), createdAt: Date = Date(), subjectID: UUID? = nil, goalID: UUID? = nil, title: String = "", notes: String = "", estimatedMinutes: Int = 30, priority: Int = 2, deadline: Date? = nil, deadlineDateOnly: Bool = true, scheduledDay: Date? = nil, isArchived: Bool = false, completedAt: Date? = nil, firstCompletedAt: Date? = nil, recurrenceID: UUID? = nil, occurrenceKey: String? = nil, steps: [ChecklistItem] = [], resources: [ResourceLink] = [], skippedAt: Date? = nil, reviewSourceID: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.subjectID = subjectID
        self.goalID = goalID
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.deadline = deadline
        self.deadlineDateOnly = deadlineDateOnly
        self.scheduledDay = scheduledDay
        self.isArchived = isArchived
        self.completedAt = completedAt
        self.firstCompletedAt = firstCompletedAt
        self.recurrenceID = recurrenceID
        self.occurrenceKey = occurrenceKey
        self.steps = steps
        self.resources = resources
        self.skippedAt = skippedAt
        self.reviewSourceID = reviewSourceID
    }
    var snapshot: StudyTaskSnapshot {
        StudyTaskSnapshot(id: id, createdAt: createdAt, subjectID: subjectID, goalID: goalID, title: title, notes: notes, estimatedMinutes: estimatedMinutes, priority: priority, deadline: deadline, deadlineDateOnly: deadlineDateOnly, scheduledDay: scheduledDay, isArchived: isArchived, completedAt: completedAt, firstCompletedAt: firstCompletedAt, recurrenceID: recurrenceID, occurrenceKey: occurrenceKey, skippedAt: skippedAt, reviewSourceID: reviewSourceID, steps: steps, resources: resources)
    }
}
struct StudyTaskSnapshot: Codable, Sendable, Equatable {
    var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var goalID: UUID?
    var title: String
    var notes: String
    var estimatedMinutes: Int
    var priority: Int
    var deadline: Date?
    var deadlineDateOnly: Bool
    var scheduledDay: Date?
    var isArchived: Bool
    var completedAt: Date?
    var firstCompletedAt: Date?
    var recurrenceID: UUID?
    var occurrenceKey: String?
    var skippedAt: Date?
    var reviewSourceID: UUID?
    var steps: [ChecklistItem]
    var resources: [ResourceLink]
    func model() -> StudyTask {
        StudyTask(id: id, createdAt: createdAt, subjectID: subjectID, goalID: goalID, title: title, notes: notes, estimatedMinutes: estimatedMinutes, priority: priority, deadline: deadline, deadlineDateOnly: deadlineDateOnly, scheduledDay: scheduledDay, isArchived: isArchived, completedAt: completedAt, firstCompletedAt: firstCompletedAt, recurrenceID: recurrenceID, occurrenceKey: occurrenceKey, steps: steps, resources: resources, skippedAt: skippedAt, reviewSourceID: reviewSourceID)
    }
}

@Model
final class RecurrenceRule {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var goalID: UUID?
    var title: String
    var weekdays: [Int]
    var duration: Int
    var startDate: Date
    var endDate: Date?
    var isEnabled: Bool
    init(id: UUID = UUID(), createdAt: Date = Date(), subjectID: UUID? = nil, goalID: UUID? = nil, title: String = "", weekdays: [Int] = [1,2,3,4,5,6,7], duration: Int = 30, startDate: Date = Date(), endDate: Date? = nil, isEnabled: Bool = true) {
        self.id = id
        self.createdAt = createdAt
        self.subjectID = subjectID
        self.goalID = goalID
        self.title = title
        self.weekdays = weekdays
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
        self.isEnabled = isEnabled
    }
    var snapshot: RecurrenceRuleSnapshot {
        RecurrenceRuleSnapshot(id: id, createdAt: createdAt, subjectID: subjectID, goalID: goalID, title: title, weekdays: weekdays, duration: duration, startDate: startDate, endDate: endDate, isEnabled: isEnabled)
    }
}
struct RecurrenceRuleSnapshot: Codable, Sendable, Equatable {
    var id: UUID
    var createdAt: Date
    var subjectID: UUID?
    var goalID: UUID?
    var title: String
    var weekdays: [Int]
    var duration: Int
    var startDate: Date
    var endDate: Date?
    var isEnabled: Bool
    func model() -> RecurrenceRule {
        RecurrenceRule(id: id, createdAt: createdAt, subjectID: subjectID, goalID: goalID, title: title, weekdays: weekdays, duration: duration, startDate: startDate, endDate: endDate, isEnabled: isEnabled)
    }
}

@Model
final class StudyPlanBlock {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var taskID: UUID
    var day: Date
    var startAt: Date?
    var durationMinutes: Int
    var status: String
    var isLocked: Bool
    var userEdited: Bool
    init(id: UUID = UUID(), createdAt: Date = Date(), taskID: UUID = UUID(), day: Date = Date(), startAt: Date? = nil, durationMinutes: Int = 30, status: String = "confirmed", isLocked: Bool = false, userEdited: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.taskID = taskID
        self.day = day
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.status = status
        self.isLocked = isLocked
        self.userEdited = userEdited
    }
    var snapshot: StudyPlanBlockSnapshot {
        StudyPlanBlockSnapshot(id: id, createdAt: createdAt, taskID: taskID, day: day, startAt: startAt, durationMinutes: durationMinutes, status: status, isLocked: isLocked, userEdited: userEdited)
    }
}
struct StudyPlanBlockSnapshot: Codable, Sendable, Equatable {
    var id: UUID
    var createdAt: Date
    var taskID: UUID
    var day: Date
    var startAt: Date?
    var durationMinutes: Int
    var status: String
    var isLocked: Bool
    var userEdited: Bool
    func model() -> StudyPlanBlock {
        StudyPlanBlock(id: id, createdAt: createdAt, taskID: taskID, day: day, startAt: startAt, durationMinutes: durationMinutes, status: status, isLocked: isLocked, userEdited: userEdited)
    }
}

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var taskID: UUID
    var subjectID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var accumulatedActiveSeconds: Double
    var activeIntervalStartedAt: Date?
    var status: String
    var understandingRating: Int?
    var sessionNote: String
    var planBlockID: UUID?
    var targetMinutes: Int?
    var pendingRecoveryStartedAt: Date? = nil
    var pendingRecoveryEndedAt: Date? = nil
    init(id: UUID = UUID(), createdAt: Date = Date(), taskID: UUID = UUID(), subjectID: UUID? = nil, startedAt: Date = Date(), endedAt: Date? = nil, accumulatedActiveSeconds: Double = 0, activeIntervalStartedAt: Date? = nil, status: String = "paused", understandingRating: Int? = nil, sessionNote: String = "", planBlockID: UUID? = nil, targetMinutes: Int? = nil, pendingRecoveryStartedAt: Date? = nil, pendingRecoveryEndedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.taskID = taskID
        self.subjectID = subjectID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.accumulatedActiveSeconds = accumulatedActiveSeconds
        self.activeIntervalStartedAt = activeIntervalStartedAt
        self.status = status
        self.understandingRating = understandingRating
        self.sessionNote = sessionNote
        self.planBlockID = planBlockID
        self.targetMinutes = targetMinutes
        self.pendingRecoveryStartedAt = pendingRecoveryStartedAt
        self.pendingRecoveryEndedAt = pendingRecoveryEndedAt
    }
    var snapshot: FocusSessionSnapshot {
        FocusSessionSnapshot(id: id, createdAt: createdAt, taskID: taskID, subjectID: subjectID, startedAt: startedAt, endedAt: endedAt, accumulatedActiveSeconds: accumulatedActiveSeconds, activeIntervalStartedAt: activeIntervalStartedAt, status: status, understandingRating: understandingRating, sessionNote: sessionNote, planBlockID: planBlockID, targetMinutes: targetMinutes, pendingRecoveryStartedAt: pendingRecoveryStartedAt, pendingRecoveryEndedAt: pendingRecoveryEndedAt)
    }
}
struct FocusSessionSnapshot: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var taskID: UUID
    var subjectID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var accumulatedActiveSeconds: Double
    var activeIntervalStartedAt: Date?
    var status: String
    var understandingRating: Int?
    var sessionNote: String
    var planBlockID: UUID?
    var targetMinutes: Int?
    var pendingRecoveryStartedAt: Date? = nil
    var pendingRecoveryEndedAt: Date? = nil
    func model() -> FocusSession {
        FocusSession(id: id, createdAt: createdAt, taskID: taskID, subjectID: subjectID, startedAt: startedAt, endedAt: endedAt, accumulatedActiveSeconds: accumulatedActiveSeconds, activeIntervalStartedAt: activeIntervalStartedAt, status: status, understandingRating: understandingRating, sessionNote: sessionNote, planBlockID: planBlockID, targetMinutes: targetMinutes, pendingRecoveryStartedAt: pendingRecoveryStartedAt, pendingRecoveryEndedAt: pendingRecoveryEndedAt)
    }
}

@Model
final class DailyReview {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var dayKey: String
    var reflection: String
    init(id: UUID = UUID(), createdAt: Date = Date(), dayKey: String = "", reflection: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.dayKey = dayKey
        self.reflection = reflection
    }
    var snapshot: DailyReviewSnapshot {
        DailyReviewSnapshot(id: id, createdAt: createdAt, dayKey: dayKey, reflection: reflection)
    }
}
struct DailyReviewSnapshot: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var dayKey: String
    var reflection: String
    func model() -> DailyReview {
        DailyReview(id: id, createdAt: createdAt, dayKey: dayKey, reflection: reflection)
    }
}

@Model
final class UserPreferences {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var onboardingCompleted: Bool
    var hasAcceptedSampleData: Bool
    var appearance: String
    var dailyMinutes: Int
    var maxDailyMinutes: Int
    var availability: [Int]
    var windowStart: Int
    var windowEnd: Int
    var notificationsEnabled: Bool
    var startReminders: Bool
    var deadlineThreeDays: Bool
    var deadlineOneDay: Bool
    var eveningReview: Bool
    var reviewMinute: Int
    var quietStart: Int
    var quietEnd: Int
    init(id: UUID = UUID(), createdAt: Date = Date(), onboardingCompleted: Bool = false, hasAcceptedSampleData: Bool = false, appearance: String = "system", dailyMinutes: Int = 180, maxDailyMinutes: Int = 240, availability: [Int] = [180,180,180,180,180,180,180], windowStart: Int = 540, windowEnd: Int = 1260, notificationsEnabled: Bool = false, startReminders: Bool = true, deadlineThreeDays: Bool = true, deadlineOneDay: Bool = true, eveningReview: Bool = true, reviewMinute: Int = 1230, quietStart: Int = 1320, quietEnd: Int = 480) {
        self.id = id
        self.createdAt = createdAt
        self.onboardingCompleted = onboardingCompleted
        self.hasAcceptedSampleData = hasAcceptedSampleData
        self.appearance = appearance
        self.dailyMinutes = dailyMinutes
        self.maxDailyMinutes = maxDailyMinutes
        self.availability = availability
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.notificationsEnabled = notificationsEnabled
        self.startReminders = startReminders
        self.deadlineThreeDays = deadlineThreeDays
        self.deadlineOneDay = deadlineOneDay
        self.eveningReview = eveningReview
        self.reviewMinute = reviewMinute
        self.quietStart = quietStart
        self.quietEnd = quietEnd
    }
    var snapshot: UserPreferencesSnapshot {
        UserPreferencesSnapshot(id: id, createdAt: createdAt, onboardingCompleted: onboardingCompleted, hasAcceptedSampleData: hasAcceptedSampleData, appearance: appearance, dailyMinutes: dailyMinutes, maxDailyMinutes: maxDailyMinutes, availability: availability, windowStart: windowStart, windowEnd: windowEnd, notificationsEnabled: notificationsEnabled, startReminders: startReminders, deadlineThreeDays: deadlineThreeDays, deadlineOneDay: deadlineOneDay, eveningReview: eveningReview, reviewMinute: reviewMinute, quietStart: quietStart, quietEnd: quietEnd)
    }
}
struct UserPreferencesSnapshot: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var onboardingCompleted: Bool
    var hasAcceptedSampleData: Bool
    var appearance: String
    var dailyMinutes: Int
    var maxDailyMinutes: Int
    var availability: [Int]
    var windowStart: Int
    var windowEnd: Int
    var notificationsEnabled: Bool
    var startReminders: Bool
    var deadlineThreeDays: Bool
    var deadlineOneDay: Bool
    var eveningReview: Bool
    var reviewMinute: Int
    var quietStart: Int
    var quietEnd: Int
    func model() -> UserPreferences {
        UserPreferences(id: id, createdAt: createdAt, onboardingCompleted: onboardingCompleted, hasAcceptedSampleData: hasAcceptedSampleData, appearance: appearance, dailyMinutes: dailyMinutes, maxDailyMinutes: maxDailyMinutes, availability: availability, windowStart: windowStart, windowEnd: windowEnd, notificationsEnabled: notificationsEnabled, startReminders: startReminders, deadlineThreeDays: deadlineThreeDays, deadlineOneDay: deadlineOneDay, eveningReview: eveningReview, reviewMinute: reviewMinute, quietStart: quietStart, quietEnd: quietEnd)
    }
}

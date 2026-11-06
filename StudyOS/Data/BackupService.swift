import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw StudyError.invalid("Unable to read file.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct StudyBackup: Codable, Sendable {
    var schemaVersion = 1
    var exportedAt = Date()
    var recordCounts: [String: Int]
    var subjects: [SubjectSnapshot]
    var goals: [StudyGoalSnapshot]
    var tasks: [StudyTaskSnapshot]
    var rules: [RecurrenceRuleSnapshot]
    var blocks: [StudyPlanBlockSnapshot]
    var sessions: [FocusSessionSnapshot]
    var reviews: [DailyReviewSnapshot]
    var preferences: [UserPreferencesSnapshot]
    var recordCount: Int { subjects.count + goals.count + tasks.count + rules.count + blocks.count + sessions.count + reviews.count + preferences.count }
    var summary: String { "\(subjects.count) subjects, \(goals.count) goals, \(tasks.count) tasks, \(sessions.count) sessions. Existing IDs are kept; only new records are added. Imported unfinished sessions are archived without credit." }
    @MainActor init(store: StudyStore) {
        subjects = store.subjects.map(\.snapshot)
        goals = store.goals.map(\.snapshot)
        tasks = store.tasks.map(\.snapshot)
        rules = store.rules.map(\.snapshot)
        blocks = store.blocks.map(\.snapshot)
        sessions = store.sessions.map(\.snapshot)
        reviews = store.reviews.map(\.snapshot)
        preferences = [store.preferences.snapshot]
        recordCounts = ["subjects": subjects.count, "goals": goals.count, "tasks": tasks.count, "rules": rules.count,
                        "blocks": blocks.count, "sessions": sessions.count, "reviews": reviews.count, "preferences": preferences.count]
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> StudyBackup {
        guard data.count <= 20_000_000 else { throw StudyError.invalid("Backup exceeds the 20 MB limit.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StudyBackup.self, from: data)
        try backup.validate()
        return backup
    }
    func validate() throws {
        guard schemaVersion == 1 else { throw StudyError.invalid("Unsupported backup schema version.") }
        guard recordCounts == ["subjects": subjects.count, "goals": goals.count, "tasks": tasks.count, "rules": rules.count,
                               "blocks": blocks.count, "sessions": sessions.count, "reviews": reviews.count, "preferences": preferences.count] else {
            throw StudyError.invalid("Backup record counts do not match its contents.")
        }
        guard recordCount <= 100_000, preferences.count <= 1 else { throw StudyError.invalid("Invalid record count.") }
        guard Set(subjects.map(\.id)).count == subjects.count else { throw StudyError.invalid("Duplicate subjects identifiers.") }
        guard Set(goals.map(\.id)).count == goals.count else { throw StudyError.invalid("Duplicate goals identifiers.") }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw StudyError.invalid("Duplicate tasks identifiers.") }
        guard Set(rules.map(\.id)).count == rules.count else { throw StudyError.invalid("Duplicate rules identifiers.") }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw StudyError.invalid("Duplicate blocks identifiers.") }
        guard Set(sessions.map(\.id)).count == sessions.count else { throw StudyError.invalid("Duplicate sessions identifiers.") }
        guard Set(reviews.map(\.id)).count == reviews.count else { throw StudyError.invalid("Duplicate reviews identifiers.") }
        guard Set(preferences.map(\.id)).count == preferences.count else { throw StudyError.invalid("Duplicate preferences identifiers.") }
        let subjectIDs = Set(subjects.map(\.id)), goalIDs = Set(goals.map(\.id)), taskIDs = Set(tasks.map(\.id)), ruleIDs = Set(rules.map(\.id))
        func check(_ valid: Bool) throws { if !valid { throw StudyError.invalid("Backup contains invalid values or missing references.") } }
        func subject(_ id: UUID?) -> Bool { id.map { subjectIDs.contains($0) } ?? true }
        for item in subjects { try check(!item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        try check(Set(reviews.map(\.dayKey)).count == reviews.count)
        for g in goals { try check(subject(g.subjectID) && !g.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...3).contains(g.priority) && g.targetMinutes >= 0) }
        for t in tasks {
            try check(subject(t.subjectID) && (t.goalID.map { goalIDs.contains($0) } ?? true) && (t.recurrenceID.map { ruleIDs.contains($0) } ?? true))
            try check(t.reviewSourceID.map { id in sessions.contains { $0.id == id } } ?? true)
            try check(!t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...14400).contains(t.estimatedMinutes) && (1...3).contains(t.priority))
            try check(t.resources.allSatisfy { StudyTime.validURL($0.url) != nil } && Set(t.steps.map(\.id)).count == t.steps.count)
        }
        try check(Set(tasks.compactMap(\.occurrenceKey)).count == tasks.compactMap(\.occurrenceKey).count)
        for r in rules { try check(subject(r.subjectID) && (r.goalID.map { goalIDs.contains($0) } ?? true) && !r.title.isEmpty && (1...1440).contains(r.duration) && !r.weekdays.isEmpty && r.weekdays.allSatisfy { (1...7).contains($0) }) }
        for b in blocks { try check(taskIDs.contains(b.taskID) && (1...1440).contains(b.durationMinutes) && ["confirmed", "completed", "canceled", "missed"].contains(b.status)) }
        for s in sessions {
            try check(taskIDs.contains(s.taskID) && subject(s.subjectID) && s.accumulatedActiveSeconds.isFinite && s.accumulatedActiveSeconds >= 0)
            try check(["running", "paused", "finished", "discarded"].contains(s.status) && (s.understandingRating.map { (1...5).contains($0) } ?? true))
            try check(s.targetMinutes.map { (1...14400).contains($0) } ?? true)
            try check((s.pendingRecoveryStartedAt == nil) == (s.pendingRecoveryEndedAt == nil))
            if let start = s.pendingRecoveryStartedAt, let end = s.pendingRecoveryEndedAt {
                try check(["running", "paused"].contains(s.status) && RecoveredGap(sessionID: s.id, start: start, end: end).isValid)
            }
            try check(s.planBlockID.map { id in blocks.contains { $0.id == id && $0.taskID == s.taskID } } ?? true)
            try check(s.status != "finished" || (s.endedAt != nil && s.accumulatedActiveSeconds >= 1))
            try check(s.endedAt.map { $0 >= s.startedAt } ?? true)
        }
        for p in preferences {
            try check(p.availability.count == 7 && p.availability.allSatisfy { (0...1440).contains($0) } && (0...1440).contains(p.maxDailyMinutes))
            try check((0..<1440).contains(p.windowStart) && (1...1439).contains(p.windowEnd) && p.windowStart < p.windowEnd)
            try check([p.reviewMinute, p.quietStart, p.quietEnd].allSatisfy { (0..<1440).contains($0) } && ["system", "light", "dark"].contains(p.appearance))
        }
    }
    @MainActor func merge(into store: StudyStore) -> Bool {
        do { try validate() } catch { store.error = error.localizedDescription; return false }
        for item in tasks {
            if let key = item.occurrenceKey, store.tasks.contains(where: { $0.occurrenceKey == key && $0.id != item.id }) {
                store.error = "A recurring occurrence has conflicting IDs. No records were imported."
                return false
            }
        }
        return store.commit {
            let existingSubject = Set(store.subjects.map(\.id))
            for item in subjects where !existingSubject.contains(item.id) {
                store.context.insert(item.model())
            }
            let existingStudyGoal = Set(store.goals.map(\.id))
            for item in goals where !existingStudyGoal.contains(item.id) {
                store.context.insert(item.model())
            }
            let existingStudyTask = Set(store.tasks.map(\.id))
            for item in tasks where !existingStudyTask.contains(item.id) {
                if let key = item.occurrenceKey, store.tasks.contains(where: { $0.occurrenceKey == key }) { continue }
                store.context.insert(item.model())
            }
            let existingRecurrenceRule = Set(store.rules.map(\.id))
            for item in rules where !existingRecurrenceRule.contains(item.id) {
                store.context.insert(item.model())
            }
            let existingStudyPlanBlock = Set(store.blocks.map(\.id))
            for item in blocks where !existingStudyPlanBlock.contains(item.id) {
                store.context.insert(item.model())
            }
            let existingFocusSession = Set(store.sessions.map(\.id))
            for item in sessions where !existingFocusSession.contains(item.id) {
                var recovered = item
                if ["running", "paused"].contains(recovered.status) { recovered.status = "discarded"; recovered.activeIntervalStartedAt = nil; recovered.endedAt = exportedAt; recovered.pendingRecoveryStartedAt = nil; recovered.pendingRecoveryEndedAt = nil }
                store.context.insert(recovered.model())
            }
            let existingDailyReview = Set(store.reviews.map(\.id))
            for item in reviews where !existingDailyReview.contains(item.id) {
                // One review per day: a review written on this device for the same day wins; an empty local one is filled in.
                if let local = store.reviews.first(where: { $0.dayKey == item.dayKey }) {
                    if local.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { local.reflection = item.reflection }
                    continue
                }
                store.context.insert(item.model())
            }
            // Keep local device settings and notification consent. Preferences remain in the backup for portability.
        }
    }
}

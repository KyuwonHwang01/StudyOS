import Foundation
import SwiftData
import Observation

@MainActor @Observable
final class StudyStore {
    let container: ModelContainer
    let context: ModelContext
    let clock: any ClockProvider
    var subjects: [Subject] = []
    var goals: [StudyGoal] = []
    var tasks: [StudyTask] = []
    var rules: [RecurrenceRule] = []
    var blocks: [StudyPlanBlock] = []
    var sessions: [FocusSession] = []
    var reviews: [DailyReview] = []
    var preferences: UserPreferences
    var error: String?
    var toast: ToastNotice?
    var undoBefore: StudyUndo?
    var undoAfter: StudyUndo?
    var focusRoute: FocusRoute?
    var pendingFocusSwitch: FocusRoute?
    var archiveRequest: ArchiveRequest?
    var goalDestination: StudyGoal?
    var taskDestination: TaskNavigationRoute?
    var reviewDestination = false
    /// Time between the last checkpoint and this launch for a session that was running when the app was terminated.
    /// It is never credited automatically; the user decides in Focus.
    var recoveredGap: RecoveredGap? {
        guard let session = activeSession, let start = session.pendingRecoveryStartedAt, let end = session.pendingRecoveryEndedAt else { return nil }
        let gap = RecoveredGap(sessionID: session.id, start: start, end: end)
        return gap.isValid ? gap : nil
    }
    private let saveContext: @MainActor (ModelContext) throws -> Void
    var navigationEpoch = UUID()
    let drafts: DraftRepository
    var revision = 0
    var notificationService = NotificationService()

    init(context: ModelContext, clock: any ClockProvider = SystemClock(), draftURL: URL? = nil, saveContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws {
        self.saveContext = saveContext
        self.drafts = DraftRepository(url: draftURL)
        self.container = context.container
        self.context = context; self.clock = clock
        context.autosaveEnabled = false
        preferences = try context.fetch(FetchDescriptor<UserPreferences>()).first ?? UserPreferences()
        if preferences.modelContext == nil { context.insert(preferences) }
        normalizeAvailability()
        try saveContext(context)
        try reload()
        // Never silently credit an interval across process termination. Recovery starts paused.
        for session in sessions where session.status == "running" {
            if session.pendingRecoveryStartedAt == nil && session.pendingRecoveryEndedAt == nil, let checkpoint = session.activeIntervalStartedAt {
                let gap = RecoveredGap(sessionID: session.id, start: checkpoint, end: clock.now)
                if gap.isValid {
                    session.pendingRecoveryStartedAt = checkpoint
                    session.pendingRecoveryEndedAt = gap.end
                }
            }
            session.activeIntervalStartedAt = nil; session.status = "paused"
        }
        try maintenance()
        try saveContext(context)
    }
    func reload() throws {
        subjects = try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.createdAt)]))
        goals = try context.fetch(FetchDescriptor<StudyGoal>(sortBy: [SortDescriptor(\.createdAt)]))
        tasks = try context.fetch(FetchDescriptor<StudyTask>(sortBy: [SortDescriptor(\.createdAt)]))
        rules = try context.fetch(FetchDescriptor<RecurrenceRule>())
        blocks = try context.fetch(FetchDescriptor<StudyPlanBlock>())
        sessions = try context.fetch(FetchDescriptor<FocusSession>())
        reviews = try context.fetch(FetchDescriptor<DailyReview>())
        revision += 1
    }
    @discardableResult func commit(_ change: () throws -> Void) -> Bool {
        do {
            try change()
            normalizeAvailability()
            try maintenance()
            try saveContext(context); try reload()
            refreshNotifications()
            return true
        } catch {
            context.rollback()
            do { try reload() } catch { self.error = "Could not reload saved data: \(error.localizedDescription)" }
            self.error = "Changes could not be saved. Your last saved data is preserved. \(error.localizedDescription)"
            return false
        }
    }
    private func normalizeAvailability() {
        // Enforce the same rule for existing data and every write, not just form controls.
        preferences.maxDailyMinutes = max(preferences.maxDailyMinutes, preferences.availability.max() ?? 0)
    }
    func persistEdits() {
        do { try saveContext(context) }
        catch { context.rollback(); self.error = "Changes could not be saved: \(error.localizedDescription)" }
    }
    func refreshNotifications() {
        let snapshot = NotificationSnapshot(preferences: preferences.snapshot, blocks: blocks.map(\.snapshot), tasks: tasks.map(\.snapshot), goals: goals.map(\.snapshot), sessions: sessions.map(\.snapshot), reviews: reviews.map(\.snapshot))
        Task { await notificationService.refresh(snapshot) }
    }
    var activeSession: FocusSession? { sessions.first { $0.status == "running" || $0.status == "paused" } }
    func subjectName(_ id: UUID?) -> String { subjects.first { $0.id == id }?.name ?? "Independent study" }
    func task(_ id: UUID) -> StudyTask? { tasks.first { $0.id == id } }
    func dayTasks(_ day: Date) -> [StudyTask] {
        let ids = Set(blocks.filter { $0.status != "canceled" && Calendar.current.isDate($0.day, inSameDayAs: day) }.map(\.taskID))
        // A previous-day active block is history for calendar placement, even while its timer is protected.
        let today = Calendar.current.startOfDay(for: clock.now)
        let plannedIDs = Set(blocks.filter { $0.status == "confirmed" && Calendar.current.startOfDay(for: $0.day) >= today }.map(\.taskID))
        return tasks.filter { task in
            guard !task.isArchived && task.skippedAt == nil else { return false }
            if let done = task.completedAt, Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: done) { return false }
            if task.completedAt.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true { return true }
            return ids.contains(task.id) || (!plannedIDs.contains(task.id) && task.scheduledDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true)
        }
    }
    func complete(_ task: StudyTask) {
        guard activeSession?.taskID != task.id || task.completedAt != nil else {
            presentFocus(task, finish: true, resume: false); return
        }
        let before = StudyUndo.capture(self), first = task.firstCompletedAt == nil
        if commit({
            if task.completedAt == nil { finishTaskRecords(task) }
            else { task.completedAt = nil }
        }) { showToast(task.completedAt == nil ? "Task reopened" : first ? "1 drop collected" : "Task completed", undo: before) }
    }
    func archive(_ task: StudyTask) {
        let request = ArchiveRequest(kind: .task, recordID: task.id)
        guard activeSession?.taskID != task.id else { archiveRequest = request; return }
        applyArchive(request, includeRelated: true)
    }
    @discardableResult func start(_ task: StudyTask, blockID: UUID? = nil) -> Bool {
        guard activeSession == nil, !task.isArchived, task.completedAt == nil, task.skippedAt == nil,
              !PlanningEngine.isExpiredRoutine(task.snapshot, blocks: blocks.map(\.snapshot), sessions: sessions.map(\.snapshot), now: clock.now, calendar: .current) else { return false }
        let block = blockID.flatMap { id in blocks.first { $0.id == id && $0.taskID == task.id && $0.status == "confirmed" } }
        let actual = sessions.filter { $0.taskID == task.id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
        let target = block.map { max(1, remainingMinutes($0)) } ?? max(15, task.estimatedMinutes - Int(actual / 60))
        return commit {
            context.insert(FocusSession(taskID: task.id, subjectID: task.subjectID, startedAt: clock.now,
                                        activeIntervalStartedAt: clock.now, status: "running", planBlockID: block?.id, targetMinutes: target))
        }
    }
    func elapsed(_ session: FocusSession) -> Double {
        SessionClock.elapsed(accumulated: session.accumulatedActiveSeconds, intervalStart: session.status == "running" ? session.activeIntervalStartedAt : nil, now: clock.now)
    }
    @discardableResult func pause(_ session: FocusSession) -> Bool {
        guard session.status == "running" else { return session.status == "paused" }
        return commit { session.accumulatedActiveSeconds = elapsed(session); session.activeIntervalStartedAt = nil; session.status = "paused" }
    }
    @discardableResult func resume(_ session: FocusSession) -> Bool {
        guard session.status == "paused" else { return session.status == "running" }
        guard recoveredGap?.sessionID != session.id else { error = "Review your recovered time in Focus before resuming."; return false }
        return commit { session.status = "running"; session.activeIntervalStartedAt = clock.now }
    }
    @discardableResult func finish(_ session: FocusSession, rating: Int?, note: String, markComplete: Bool, createReview: Bool = false) -> Bool {
        guard recoveredGap?.sessionID != session.id else { error = "Review your recovered time in Focus before saving this session."; return false }
        guard ["running", "paused"].contains(session.status), elapsed(session) >= 1 else {
            error = "This session has no active time. Resume the timer or discard it."; return false
        }
        guard rating.map({ (1...5).contains($0) }) ?? true else { error = "Choose an understanding rating from 1 to 5, or leave it unrated."; return false }
        let before = markComplete ? StudyUndo.capture(self) : nil
        let success = commit {
            session.accumulatedActiveSeconds = elapsed(session); session.activeIntervalStartedAt = nil
            session.status = "finished"; session.endedAt = max(clock.now, session.startedAt)
            session.understandingRating = rating; session.sessionNote = note
            settleBlock(for: session)
            if markComplete, let task = task(session.taskID), task.completedAt == nil { finishTaskRecords(task) }
            if createReview { _ = addReview(for: session) }

        }
        if success { drafts.remove("finish:\(session.id)"); showToast(markComplete ? "Time saved · task completed" : "Session saved", undo: before) }
        return success
    }
    /// Credit and removal of the pending choice share the same save and rollback boundary.
    @discardableResult func resolveRecoveredGap(include: Bool) -> Bool {
        guard let gap = recoveredGap, let session = sessions.first(where: { $0.id == gap.sessionID }) else { return false }
        return commit {
            if include { session.accumulatedActiveSeconds += gap.seconds }
            session.pendingRecoveryStartedAt = nil; session.pendingRecoveryEndedAt = nil
        }
    }
    @discardableResult func discard(_ session: FocusSession) -> Bool {
        let success = commit { session.pendingRecoveryStartedAt = nil; session.pendingRecoveryEndedAt = nil; session.status = "discarded"; session.activeIntervalStartedAt = nil; session.endedAt = max(clock.now, session.startedAt) }
        if success { drafts.remove("finish:\(session.id)") }
        return success
    }
    func expandRecurrences() {
        let now = clock.now, cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var keys = Set(tasks.compactMap(\.occurrenceKey))
        commit {
            for rule in rules where rule.isEnabled {
                for offset in 0..<14 {
                    let day = cal.date(byAdding: .day, value: offset, to: today)!
                    guard day >= cal.startOfDay(for: rule.startDate), rule.endDate.map({ day <= StudyTime.endOfDay($0) }) ?? true,
                          rule.weekdays.contains(cal.component(.weekday, from: day)) else { continue }
                    let key = "\(rule.id)-\(StudyTime.dayKey(day))"
                    guard keys.insert(key).inserted else { continue }
                    context.insert(StudyTask(subjectID: rule.subjectID, goalID: rule.goalID, title: rule.title,
                                             estimatedMinutes: rule.duration, scheduledDay: day, recurrenceID: rule.id, occurrenceKey: key))
                }
            }
        }
    }
    func propose() -> PlanningResult {
        PlanningEngine.generate(tasks: tasks.map(\.snapshot), goals: goals.map(\.snapshot), blocks: blocks.map(\.snapshot),
                                sessions: sessions.map(\.snapshot), preferences: preferences.snapshot, now: clock.now)
    }
    func proposeAsync() async -> PlanningResult {
        let tasks = tasks.map(\.snapshot), goals = goals.map(\.snapshot), blocks = blocks.map(\.snapshot)
        let sessions = sessions.map(\.snapshot), preferences = preferences.snapshot, now = clock.now
        let worker = Task.detached(priority: .userInitiated) {
            PlanningEngine.generate(tasks: tasks, goals: goals, blocks: blocks, sessions: sessions, preferences: preferences, now: now)
        }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }
    func approve(_ suggestions: [PlanSuggestion]) -> Bool {
        do { try validate(suggestions) } catch { self.error = error.localizedDescription; return false }
        return commit {
            for s in suggestions {
                context.insert(StudyPlanBlock(taskID: s.taskID, day: s.day, startAt: s.startAt, durationMinutes: s.minutes))
            }
        }
    }
    func validate(_ suggestions: [PlanSuggestion], excluding: UUID? = nil, excludingIDs: Set<UUID> = [], allowStarted: Bool = false) throws {
        let cal = Calendar.current, now = clock.now
        var reservations = blocks.filter { $0.id != excluding && !excludingIDs.contains($0.id) && $0.status == "confirmed" }.map(\.snapshot)
        for s in suggestions {
            guard let task = task(s.taskID), !task.isArchived, task.completedAt == nil, task.skippedAt == nil,
                  s.minutes > 0, s.minutes <= 1440, s.day >= cal.startOfDay(for: now) else { throw StudyError.invalid("Invalid or stale proposal. Generate a new plan.") }
            let effectiveEnd = s.startAt?.addingTimeInterval(Double(s.minutes * 60)) ?? StudyTime.endOfDay(s.day)
            var deadlines = [task.deadline.map { task.deadlineDateOnly ? StudyTime.endOfDay($0) : $0 }].compactMap { $0 }
            if let goal = goals.first(where: { $0.id == task.goalID }), let d = goal.dueAt { deadlines.append(goal.isDateOnly ? StudyTime.endOfDay(d) : d) }
            if let deadline = deadlines.min(), effectiveEnd > deadline { throw StudyError.invalid("A block extends beyond its deadline.") }
            guard !reservations.contains(where: { $0.taskID == s.taskID && cal.isDate($0.day, inSameDayAs: s.day) && $0.startAt == s.startAt && $0.durationMinutes == s.minutes }) else {
                throw StudyError.invalid("This block is already in your plan.")
            }
            let sameDay = reservations.filter { cal.isDate($0.day, inSameDayAs: s.day) }
            let limit = min(preferences.maxDailyMinutes, preferences.availability[cal.component(.weekday, from: s.day) - 1])
            guard sameDay.reduce(0, { $0 + PlanningEngine.reservedMinutes($1, sessions: sessions.map(\.snapshot)) }) + s.minutes +
                  Int(ceil(sessions.filter { $0.status == "finished" && cal.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: s.day) }.reduce(0) { $0 + $1.accumulatedActiveSeconds } / 60)) <= limit else { throw StudyError.invalid("This day exceeds your study availability.") }
            if let start = s.startAt {
                guard (allowStarted || start >= now), cal.isDate(start, inSameDayAs: s.day),
                      start >= StudyTime.atMinute(preferences.windowStart, on: s.day),
                      effectiveEnd <= StudyTime.atMinute(preferences.windowEnd, on: s.day) else { throw StudyError.invalid("Choose a future time inside your study window.") }
                guard !sameDay.contains(where: { b in b.startAt.map { PlanningEngine.overlaps(start: start, minutes: s.minutes, otherStart: $0, otherMinutes: b.durationMinutes) } ?? false }) else { throw StudyError.invalid("This block overlaps an existing block.") }
            }
            reservations.append(StudyPlanBlockSnapshot(id: UUID(), createdAt: now, taskID: s.taskID, day: s.day, startAt: s.startAt, durationMinutes: s.minutes, status: "confirmed", isLocked: false, userEdited: true))
        }
    }
    func saveReview(_ text: String, dayKey: String? = nil) {
        let key = dayKey ?? StudyTime.dayKey(clock.now)
        commit {
            if let review = reviews.first(where: { $0.dayKey == key }) { review.reflection = text }
            else { context.insert(DailyReview(dayKey: key, reflection: text)) }
        }
    }
}
struct RecoveredGap: Equatable {
    static let minimumSeconds: Double = 60
    static let maximumSeconds: Double = 12 * 3600
    var sessionID: UUID
    var start: Date
    var end: Date
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
    var isValid: Bool {
        start.timeIntervalSinceReferenceDate.isFinite && end.timeIntervalSinceReferenceDate.isFinite &&
        (Self.minimumSeconds...Self.maximumSeconds).contains(end.timeIntervalSince(start))
    }
}
enum StudyError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { message } else { "Invalid data" } }
}

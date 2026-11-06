import Foundation
import SwiftData

struct ToastNotice: Identifiable {
    let id = UUID()
    var message: String
    var canUndo = false
}
struct FocusRoute: Identifiable {
    let id = UUID()
    var taskID: UUID
    var blockID: UUID?
    var finishRequested = false
    var resumeOnOpen = true
    var transitionID: UUID?
}
struct TaskNavigationRoute: Identifiable, Hashable {
    let id = UUID()
    var taskID: UUID
    var blockID: UUID?
}
struct ArchiveRequest: Identifiable {
    enum Kind { case task, subject, goal }
    let id = UUID()
    var kind: Kind
    var recordID: UUID
}

@MainActor struct StudyUndo {
    var tasks: [StudyTaskSnapshot]
    var blocks: [StudyPlanBlockSnapshot]
    var subjects: [SubjectSnapshot]
    var goals: [StudyGoalSnapshot]
    var rules: [RecurrenceRuleSnapshot]
    static func capture(_ store: StudyStore) -> StudyUndo {
        StudyUndo(tasks: store.tasks.map(\.snapshot), blocks: store.blocks.map(\.snapshot), subjects: store.subjects.map(\.snapshot), goals: store.goals.map(\.snapshot), rules: store.rules.map(\.snapshot))
    }
}

@MainActor extension StudyStore {
    func showToast(_ message: String, undo before: StudyUndo? = nil) {
        undoBefore = before
        undoAfter = before == nil ? nil : StudyUndo.capture(self)
        toast = ToastNotice(message: message, canUndo: before != nil)
    }
    func clearToast(_ id: UUID) {
        guard toast?.id == id else { return }
        toast = nil; undoBefore = nil; undoAfter = nil
    }
    func undoLastAction() {
        guard let before = undoBefore, let after = undoAfter else { return }
        if commit({
            for b in before.tasks {
                guard let a = after.tasks.first(where: { $0.id == b.id }),
                      b.isArchived != a.isArchived || b.completedAt != a.completedAt || b.skippedAt != a.skippedAt || b.firstCompletedAt != a.firstCompletedAt || b.goalID != a.goalID || b.subjectID != a.subjectID || b.scheduledDay != a.scheduledDay,
                      let t = task(b.id) else { continue }
                guard t.isArchived == a.isArchived && t.completedAt == a.completedAt && t.skippedAt == a.skippedAt && t.firstCompletedAt == a.firstCompletedAt && t.goalID == a.goalID && t.subjectID == a.subjectID && t.scheduledDay == a.scheduledDay else { throw StudyError.invalid("This task changed after that action. Its newer changes have been kept.") }
                t.isArchived = b.isArchived; t.completedAt = b.completedAt; t.skippedAt = b.skippedAt; t.firstCompletedAt = b.firstCompletedAt; t.goalID = b.goalID; t.subjectID = b.subjectID; t.scheduledDay = b.scheduledDay
            }
            var restored: [StudyPlanBlock] = []
            for b in before.blocks {
                guard let a = after.blocks.first(where: { $0.id == b.id }), b != a,
                      let current = blocks.first(where: { $0.id == b.id }) else { continue }
                guard current.snapshot == a else { throw StudyError.invalid("This block changed after that action. Its newer schedule has been kept.") }
                current.day = b.day; current.startAt = b.startAt; current.durationMinutes = b.durationMinutes
                current.status = b.status; current.isLocked = b.isLocked; current.userEdited = b.userEdited
                if b.status == "confirmed", remainingMinutes(current) == 0 {
                    current.status = Calendar.current.startOfDay(for: current.day) > Calendar.current.startOfDay(for: clock.now) ? "canceled" : "completed"
                }
                if current.status == "confirmed" && b.day >= Calendar.current.startOfDay(for: clock.now) { restored.append(current) }
            }
            for b in before.subjects {
                guard let a = after.subjects.first(where: { $0.id == b.id }), b.isArchived != a.isArchived,
                      let current = subjects.first(where: { $0.id == b.id }), current.isArchived == a.isArchived else { continue }
                current.isArchived = b.isArchived
            }
            for b in before.goals {
                guard let a = after.goals.first(where: { $0.id == b.id }), b != a, let current = goals.first(where: { $0.id == b.id }) else { continue }
                guard current.snapshot == a else { throw StudyError.invalid("This goal changed after that action. Its newer changes have been kept.") }
                current.title = b.title; current.details = b.details; current.subjectID = b.subjectID; current.dueAt = b.dueAt
                current.isDateOnly = b.isDateOnly; current.priority = b.priority; current.targetMinutes = b.targetMinutes; current.isArchived = b.isArchived; current.completedAt = b.completedAt
            }
            for b in before.rules {
                guard let a = after.rules.first(where: { $0.id == b.id }), b != a, let current = rules.first(where: { $0.id == b.id }) else { continue }
                guard current.snapshot == a else { throw StudyError.invalid("This habit changed after that action. Its newer changes have been kept.") }
                current.title = b.title; current.subjectID = b.subjectID; current.goalID = b.goalID; current.weekdays = b.weekdays
                current.duration = b.duration; current.startDate = b.startDate; current.endDate = b.endDate; current.isEnabled = b.isEnabled
            }
            let proposals = restored.map { PlanSuggestion(taskID: $0.taskID, day: $0.day, startAt: $0.startAt, minutes: remainingMinutes($0), reason: "Undo") }
            try validate(proposals.filter { $0.minutes > 0 }, excludingIDs: Set(restored.map(\.id)), allowStarted: true)
        }) { showToast("Action undone") }
    }

    @discardableResult func openNotification(taskID: UUID?, goalID: UUID?, blockID: UUID?) -> Int {
        navigationEpoch = UUID()
        reviewDestination = false; focusRoute = nil; archiveRequest = nil
        if let active = activeSession, active.taskID != taskID, active.status == "running" { pause(active) }
        if let taskID, let task = task(taskID), !task.isArchived && task.completedAt == nil && task.skippedAt == nil {
            taskDestination = TaskNavigationRoute(taskID:taskID,blockID:blockID); return 1
        }
        if let goalID, let goal = goals.first(where: { $0.id == goalID }) { goalDestination = goal; return 1 }
        if taskID == nil && goalID == nil {
            let epoch = navigationEpoch
            Task { [weak self] in
                do { try await Task.sleep(for:.milliseconds(450)) } catch { return }
                guard let self, self.navigationEpoch == epoch else { return }
                self.reviewDestination = true
            }
        }
        return 0
    }
    func remainingTaskMinutes(_ task: StudyTask) -> Int {
        let actual = sessions.filter { $0.taskID == task.id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
        return max(15, task.estimatedMinutes - Int(actual / 60))
    }
    func nextBlock(for taskID: UUID) -> StudyPlanBlock? {
        blocks.filter { $0.taskID == taskID && $0.status == "confirmed" && $0.day >= Calendar.current.startOfDay(for: clock.now) }
            .sorted { ($0.startAt ?? StudyTime.endOfDay($0.day)) < ($1.startAt ?? StudyTime.endOfDay($1.day)) }.first
    }
    func remainingMinutes(_ block: StudyPlanBlock) -> Int {
        PlanningEngine.reservedMinutes(block.snapshot, sessions: sessions.map(\.snapshot))
    }
    func presentFocus(_ task: StudyTask, blockID: UUID? = nil, finish: Bool = false, resume: Bool = true, sourceID: UUID? = nil) {
        let returningToSession = activeSession?.taskID == task.id
        guard returningToSession || (!task.isArchived && task.skippedAt == nil && task.completedAt == nil) else { return }
        let route = FocusRoute(taskID: task.id, blockID: blockID ?? nextBlock(for: task.id)?.id, finishRequested: finish, resumeOnOpen: resume, transitionID: sourceID)
        if let active = activeSession, active.taskID != task.id { pendingFocusSwitch = route; return }
        if activeSession == nil { guard start(task, blockID: route.blockID) else { return } }
        if !finish && resume, let active = activeSession, active.status == "paused", recoveredGap?.sessionID != active.id { self.resume(active) }
        focusRoute = route
    }
    func saveAndSwitchFocus() {
        guard let route = pendingFocusSwitch, let destination = task(route.taskID) else { return }
        guard !destination.isArchived && destination.completedAt == nil && destination.skippedAt == nil else { pendingFocusSwitch = nil; return }
        if let s = activeSession {
            if elapsed(s) >= 1 {
                guard finish(s, rating: s.understandingRating, note: s.sessionNote, markComplete: false) else { return }
            } else { guard discard(s) else { return } }
        }
        pendingFocusSwitch = nil
        presentFocus(destination, blockID: route.blockID)
    }
    func toggleCompletion(_ task: StudyTask) {
        if task.completedAt == nil, activeSession?.taskID == task.id { presentFocus(task, finish: true, resume: false) }
        else { complete(task) }
    }
    func finishTaskRecords(_ task: StudyTask) {
        task.completedAt = clock.now
        task.firstCompletedAt = task.firstCompletedAt ?? clock.now
        for b in blocks where b.taskID == task.id && b.status == "confirmed" {
            let future = Calendar.current.startOfDay(for: b.day) > Calendar.current.startOfDay(for: clock.now) || (b.startAt.map { $0 > clock.now } ?? false)
            b.status = future ? "canceled" : "completed"
        }
    }
    func restoreTask(_ task: StudyTask) {
        if commit({
            task.isArchived = false
            if task.completedAt == nil, let goal = goals.first(where: { $0.id == task.goalID }), goal.isArchived || goal.completedAt != nil { task.goalID = nil }
        }) { showToast(task.skippedAt == nil ? "Task restored" : "Restored to habit history") }
    }
    func requestArchive(_ task: StudyTask) {
        if activeSession?.taskID == task.id { archiveRequest = ArchiveRequest(kind: .task, recordID: task.id) }
        else { archive(task) }
    }
    func archiveMembers(_ request: ArchiveRequest) -> [StudyTask] {
        switch request.kind {
        case .task: return tasks.filter { $0.id == request.recordID }
        case .subject:
            let goalIDs = Set(goals.filter { $0.subjectID == request.recordID }.map(\.id))
            return tasks.filter { ($0.subjectID == request.recordID || $0.goalID.map { goalIDs.contains($0) } == true) && $0.completedAt == nil && !$0.isArchived && $0.skippedAt == nil }
        case .goal: return tasks.filter { $0.goalID == request.recordID && $0.completedAt == nil && !$0.isArchived && $0.skippedAt == nil }
        }
    }
    func applyArchive(_ request: ArchiveRequest, includeRelated: Bool) {
        let members = request.kind == .task || includeRelated ? archiveMembers(request) : []
        let ids = Set(members.map(\.id)), before = StudyUndo.capture(self)
        if commit({
            if let s = activeSession, ids.contains(s.taskID) {
                s.accumulatedActiveSeconds = elapsed(s); s.activeIntervalStartedAt = nil
                s.status = s.accumulatedActiveSeconds >= 1 ? "finished" : "discarded"; s.endedAt = max(clock.now, s.startedAt)
                settleBlock(for: s)
            }
            if request.kind == .subject {
                subjects.first { $0.id == request.recordID }?.isArchived = true
                if includeRelated {
                    for g in goals where g.subjectID == request.recordID && g.completedAt == nil { g.isArchived = true }
                }
            }
            if request.kind == .goal { goals.first { $0.id == request.recordID }?.isArchived = true }
            if includeRelated {
                let parentGoals = Set(goals.filter { $0.subjectID == request.recordID }.map(\.id))
                for rule in rules where (request.kind == .subject && (rule.subjectID == request.recordID || rule.goalID.map { parentGoals.contains($0) } == true)) || (request.kind == .goal && rule.goalID == request.recordID) { rule.isEnabled = false }
            }
            for t in members { t.isArchived = true }
            for b in blocks where ids.contains(b.taskID) && b.status == "confirmed" { b.status = "canceled" }
        }) { archiveRequest = nil; showToast("Archived · study history kept", undo: before) }
    }
    func cancelBlock(_ block: StudyPlanBlock) {
        let before = StudyUndo.capture(self)
        if commit({ block.status = "canceled" }) { showToast("Block removed", undo: before) }
    }
    func settleBlock(for session: FocusSession) {
        guard let id = session.planBlockID, let block = blocks.first(where: { $0.id == id }), block.status == "confirmed" else { return }
        let total = sessions.filter { $0.planBlockID == id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
        if total >= Double(block.durationMinutes * 60) {
            block.status = Calendar.current.startOfDay(for: block.day) > Calendar.current.startOfDay(for: clock.now) ? "canceled" : "completed"
        }
    }
    func maintenance() throws {
        // Fetch pending inserts too: an import or recurrence edit may create task/block/session together.
        let currentTasks = try context.fetch(FetchDescriptor<StudyTask>())
        let currentBlocks = try context.fetch(FetchDescriptor<StudyPlanBlock>())
        let currentSessions = try context.fetch(FetchDescriptor<FocusSession>())
        for session in currentSessions where session.pendingRecoveryStartedAt != nil || session.pendingRecoveryEndedAt != nil {
            guard ["running", "paused"].contains(session.status) else { throw StudyError.invalid("Review your recovered time in Focus before ending this session.") }
            guard let start = session.pendingRecoveryStartedAt, let end = session.pendingRecoveryEndedAt,
                  RecoveredGap(sessionID: session.id, start: start, end: end).isValid else { throw StudyError.invalid("The saved recovery interval is invalid. Your saved studies have been kept.") }
        }
        let activeIDs = Set(currentSessions.filter { ["running", "paused"].contains($0.status) }.map(\.taskID))
        let lookup = Dictionary(currentTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let today = Calendar.current.startOfDay(for: clock.now)
        for t in currentTasks where t.completedAt == nil && !t.isArchived && t.skippedAt == nil && t.recurrenceID != nil && t.deadline == nil {
            guard let day = t.scheduledDay, day < today, !activeIDs.contains(t.id),
                  !currentBlocks.contains(where: { $0.taskID == t.id && $0.status == "confirmed" && Calendar.current.startOfDay(for: $0.day) >= today }) else { continue }
            t.skippedAt = clock.now
            for b in currentBlocks where b.taskID == t.id && b.status == "confirmed" { b.status = "missed" }
        }
        // Past reservations that were never studied in full become "missed" history automatically, and their
        // one-off task stays dated on that day so Today can offer to carry it over (habits never become debt).
        let activeBlockIDs = Set(currentSessions.filter { ["running", "paused"].contains($0.status) }.compactMap(\.planBlockID))
        for b in currentBlocks where b.status == "confirmed" && Calendar.current.startOfDay(for: b.day) < today && !activeBlockIDs.contains(b.id) {
            b.status = "missed"
            if let t = lookup[b.taskID], t.recurrenceID == nil, t.completedAt == nil, !t.isArchived, t.skippedAt == nil,
               (t.scheduledDay.map { $0 < b.day } ?? true) {
                t.scheduledDay = Calendar.current.startOfDay(for: b.day)
            }
        }
        // Repair historical future blocks marked completed by the previous app version.
        for b in currentBlocks where b.status == "completed" {
            if let t = lookup[b.taskID], let finished = t.completedAt,
               Calendar.current.startOfDay(for: b.day) > Calendar.current.startOfDay(for: finished) || (b.startAt.map { $0 > finished } ?? false) { b.status = "canceled" }
        }
    }
    func addReview(for session: FocusSession) -> StudyTask? {
        if let existing = tasks.first(where: { $0.reviewSourceID == session.id }) { return existing }
        guard let source = task(session.taskID) else { return nil }
        let activeGoal = goals.first { $0.id == source.goalID && !$0.isArchived && $0.completedAt == nil }
        let t = StudyTask(subjectID: source.subjectID, goalID: activeGoal?.id, title: "Review · \(source.title)", notes: session.sessionNote,
                          estimatedMinutes: 15, resources: source.resources, reviewSourceID: session.id)
        context.insert(t)
        return t
    }
    /// Unfinished one-off tasks dated before today with nothing reserved ahead: offered once on Today.
    func carriedOverTasks(now: Date) -> [StudyTask] {
        let today = Calendar.current.startOfDay(for: now)
        return tasks.filter { t in
            !t.isArchived && t.completedAt == nil && t.skippedAt == nil && t.recurrenceID == nil &&
            (t.scheduledDay.map { $0 < today } ?? false) &&
            !blocks.contains { $0.taskID == t.id && $0.status == "confirmed" && $0.day >= today }
        }.sorted { ($0.priority, $1.scheduledDay ?? .distantPast) > ($1.priority, $0.scheduledDay ?? .distantPast) }
    }
    func carryOver(_ items: [StudyTask], toToday: Bool) {
        guard !items.isEmpty else { return }
        let before = StudyUndo.capture(self), today = Calendar.current.startOfDay(for: clock.now)
        if commit({ for t in items { t.scheduledDay = toToday ? today : nil } }) {
            let count = items.count == 1 ? "1 task" : "\(items.count) tasks"
            showToast(toToday ? "\(count) moved to today" : "\(count) kept for later", undo: before)
        }
    }
    func completeGoal(_ goal: StudyGoal) {
        let linked = tasks.filter { $0.goalID == goal.id && !$0.isArchived && $0.skippedAt == nil }
        guard !linked.isEmpty, linked.allSatisfy({ $0.completedAt != nil }) else { return }
        let before = StudyUndo.capture(self)
        if commit({ goal.completedAt = clock.now; for rule in rules where rule.goalID == goal.id { rule.isEnabled = false } }) { showToast("Goal completed", undo: before) }
    }
}

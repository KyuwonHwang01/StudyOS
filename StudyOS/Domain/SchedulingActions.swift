import Foundation

@MainActor extension StudyStore {
    func nextAvailableSlot(taskID: UUID, minutes: Int, from date: Date, excluding: UUID? = nil, before limit: Date? = nil) -> PlanSuggestion? {
        let cal = Calendar.current, first = max(cal.startOfDay(for: date), cal.startOfDay(for: clock.now))
        guard let task = task(taskID) else { return nil }
        let goal = goals.first { $0.id == task.goalID }
        let due = [task.deadline.map { task.deadlineDateOnly ? StudyTime.endOfDay($0) : $0 }, goal?.dueAt.map { goal!.isDateOnly ? StudyTime.endOfDay($0) : $0 }, limit].compactMap { $0 }.min()
        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: offset, to: first)!
            if let due, StudyTime.atMinute(preferences.windowStart, on: day) > due { return nil }
            let limit = min(preferences.maxDailyMinutes, preferences.availability[cal.component(.weekday, from: day) - 1])
            let dayBlocks = blocks.filter { $0.id != excluding && $0.status == "confirmed" && cal.isDate($0.day, inSameDayAs: day) }
            let spent = Int(ceil(sessions.filter { $0.status == "finished" && cal.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.accumulatedActiveSeconds } / 60))
            if spent + dayBlocks.reduce(0, { $0 + remainingMinutes($1) }) + minutes > limit { continue }
            var cursor = max(StudyTime.atMinute(preferences.windowStart, on: day), clock.now)
            let m = cal.component(.hour, from: cursor) * 60 + cal.component(.minute, from: cursor) + (cal.component(.second, from: cursor) > 0 ? 1 : 0)
            let rounded = (m + 14) / 15 * 15
            if rounded >= 1440 { continue }
            cursor = StudyTime.atMinute(rounded, on: day)
            let end = StudyTime.atMinute(preferences.windowEnd, on: day)
            while cursor.addingTimeInterval(Double(minutes * 60)) <= end {
                if let due, cursor.addingTimeInterval(Double(minutes * 60)) > due { return nil }
                let candidate = PlanSuggestion(taskID: taskID, day: day, startAt: cursor, minutes: minutes, reason: "Next available time")
                if (try? validate([candidate], excluding: excluding)) != nil { return candidate }
                if let busy = dayBlocks.first(where: { b in b.startAt.map { PlanningEngine.overlaps(start: cursor, minutes: minutes, otherStart: $0, otherMinutes: b.durationMinutes) } ?? false }), let start = busy.startAt {
                    cursor = max(cursor.addingTimeInterval(900), start.addingTimeInterval(Double(busy.durationMinutes * 60)))
                } else { cursor = cursor.addingTimeInterval(900) }
            }
        }
        return nil
    }
    /// Call inside `commit`. Moves each block to the earliest free time that ends by `due`, or removes them.
    /// Already-studied time stays behind as completed history, exactly like moving a block by hand.
    func resolveDeadlineConflicts(_ conflicts: [StudyPlanBlock], due: Date, move: Bool) throws {
        if let s = activeSession, conflicts.contains(where: { $0.id == s.planBlockID }) {
            throw StudyError.invalid("Save your open focus session before changing this deadline.")
        }
        for block in conflicts {
            guard move else { block.status = "canceled"; continue }
            let spent = sessions.filter { $0.planBlockID == block.id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
            let minutes = max(1, remainingMinutes(block))
            guard let slot = nextAvailableSlot(taskID: block.taskID, minutes: minutes, from: clock.now, excluding: block.id, before: due) else {
                throw StudyError.invalid("There is no free time before the new deadline. Remove the blocks instead, or choose a later deadline.")
            }
            if spent > 0 {
                // The studied part keeps its sessions as history; only the remainder is reserved again.
                block.durationMinutes = max(1, Int(ceil(spent / 60))); block.status = "completed"
                let moved = StudyPlanBlock(taskID: block.taskID, day: slot.day, startAt: slot.startAt, durationMinutes: minutes, userEdited: true)
                context.insert(moved); blocks.append(moved)  // visible to the next slot search in this same change
            } else {
                block.day = slot.day; block.startAt = slot.startAt; block.durationMinutes = minutes; block.userEdited = true; block.isLocked = false
            }
        }
    }
    func saveBlock(_ block: StudyPlanBlock?, suggestion: PlanSuggestion, locked: Bool) -> Bool {
        guard activeSession?.planBlockID != block?.id || block == nil else { error = "Save your active focus time before moving this block."; return false }
        do { try validate([suggestion], excluding: block?.id) } catch { self.error = error.localizedDescription; return false }
        return commit {
            if let block {
                let spent = sessions.filter { $0.planBlockID == block.id && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
                if spent > 0 {
                    // Keep the studied portion in history and move only the remaining reservation.
                    block.durationMinutes = max(1, Int(ceil(spent / 60))); block.status = "completed"
                    context.insert(StudyPlanBlock(taskID: suggestion.taskID, day: suggestion.day, startAt: suggestion.startAt, durationMinutes: suggestion.minutes, isLocked: locked, userEdited: true))
                } else if block.day < Calendar.current.startOfDay(for: clock.now) {
                    block.status = "missed"
                    context.insert(StudyPlanBlock(taskID:suggestion.taskID,day:suggestion.day,startAt:suggestion.startAt,durationMinutes:suggestion.minutes,isLocked:locked,userEdited:true))
                } else {
                    block.day = suggestion.day; block.startAt = suggestion.startAt; block.durationMinutes = suggestion.minutes; block.isLocked = locked; block.userEdited = true
                }
            } else { context.insert(StudyPlanBlock(taskID: suggestion.taskID, day: suggestion.day, startAt: suggestion.startAt, durationMinutes: suggestion.minutes, isLocked: locked, userEdited: true)) }
        }
    }
}

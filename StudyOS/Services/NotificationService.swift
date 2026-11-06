import Foundation
import UserNotifications

struct NotificationSnapshot: Sendable {
    let preferences: UserPreferencesSnapshot
    let blocks: [StudyPlanBlockSnapshot]
    let tasks: [StudyTaskSnapshot]
    let goals: [StudyGoalSnapshot]
    var sessions: [FocusSessionSnapshot] = []
    var reviews: [DailyReviewSnapshot] = []
}

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private struct DeferredRoute { var taskID: UUID?; var goalID: UUID?; var blockID: UUID? }
    private var deferredRoute: DeferredRoute?
    private(set) var receivedNotification = false
    var route: ((UUID?, UUID?, UUID?) -> Void)? {
        didSet {
            if let pending = deferredRoute, let route {
                deferredRoute = nil; route(pending.taskID,pending.goalID,pending.blockID)
            }
        }
    }
    private var deferredFocus = false
    /// Opens the running Focus session (from the "session goal reached" reminder) without touching the timer.
    var openFocus: (() -> Void)? {
        didSet { if deferredFocus, let openFocus { deferredFocus = false; openFocus() } }
    }
    func navigateToFocus() {
        if let openFocus { openFocus() } else { deferredFocus = true }
    }
    func navigate(taskID: UUID?, goalID: UUID?, blockID: UUID?) {
        receivedNotification = true
        if let route { route(taskID,goalID,blockID) }
        else { deferredRoute = DeferredRoute(taskID:taskID,goalID:goalID,blockID:blockID) }
    }
    var onError: ((String) -> Void)?
    private var refreshTask: Task<Void, Never>?
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    func authorization() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func refresh(_ snapshot: NotificationSnapshot) async {
        let previous = refreshTask
        previous?.cancel()
        refreshTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await schedule(snapshot)
        }
        await refreshTask?.value
    }
    private func schedule(_ snapshot: NotificationSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let status = await authorization()
        guard !Task.isCancelled else { return }
        center.removeAllPendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let obsolete = delivered.filter { notification in
            let info = notification.request.content.userInfo
            if info["focus"] as? Bool == true {
                return Self.shouldRemoveDeliveredFocus(notification.request.identifier, snapshot: snapshot)
            }
            if let raw = info["blockID"] as? String, let id = UUID(uuidString: raw) {
                if snapshot.blocks.first(where: { $0.id == id })?.status != "confirmed" || snapshot.sessions.contains(where: { $0.planBlockID == id && $0.status != "discarded" }) { return true }
            }
            if let raw = info["taskID"] as? String, let id = UUID(uuidString: raw) {
                return snapshot.tasks.first { $0.id == id }.map { $0.isArchived || $0.completedAt != nil || $0.skippedAt != nil } ?? true
            }
            if let raw = info["goalID"] as? String, let id = UUID(uuidString: raw) {
                return snapshot.goals.first { $0.id == id }.map { $0.isArchived || $0.completedAt != nil } ?? true
            }
            return snapshot.reviews.contains { !$0.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && notification.request.identifier == "review.\($0.dayKey)" }
        }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: obsolete)
        guard snapshot.preferences.notificationsEnabled, [.authorized, .provisional].contains(status) else { return }
        let requests = Self.requests(snapshot, now: Date())
        for request in requests.prefix(60) {
            guard !Task.isCancelled else { return }
            do { try await center.add(request) } catch { if !Task.isCancelled { onError?("A reminder could not be scheduled: \(error.localizedDescription)") }; return }
        }
    }
    static func shouldRemoveDeliveredFocus(_ identifier: String, snapshot: NotificationSnapshot) -> Bool {
        !snapshot.preferences.notificationsEnabled || !snapshot.sessions.contains { $0.status == "running" && identifier == "focus.\($0.id)" }
    }
    static func isQuiet(_ minute: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? minute >= start && minute < end : minute >= start || minute < end
    }
    static func requests(_ snapshot: NotificationSnapshot, now: Date, calendar: Calendar = .current) -> [UNNotificationRequest] {
        let p = snapshot.preferences
        var result: [(Date, UNNotificationRequest)] = []
        func add(id: String, title: String, body: String, date: Date, taskID: UUID? = nil, goalID: UUID? = nil, blockID: UUID? = nil) {
            let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            guard date > now, !isQuiet(minute, start: p.quietStart, end: p.quietEnd) else { return }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            if let taskID { content.userInfo["taskID"] = taskID.uuidString }
            if let blockID { content.userInfo["blockID"] = blockID.uuidString }
            if let goalID { content.userInfo["goalID"] = goalID.uuidString }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            result.append((date, UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))))
        }
        // While a timer runs, remind when this session's goal is reached. Pausing or finishing refreshes and removes it.
        // The user is actively studying, so quiet hours do not apply.
        if let s = snapshot.sessions.first(where: { $0.status == "running" }), let target = s.targetMinutes, let interval = s.activeIntervalStartedAt,
           let t = snapshot.tasks.first(where: { $0.id == s.taskID }) {
            let date = interval.addingTimeInterval(Double(target * 60) - s.accumulatedActiveSeconds)
            if date > now {
                let content = UNMutableNotificationContent()
                content.title = "Session goal reached · \(target) min"; content.body = "\(t.title) — keep going or save your progress."; content.sound = .default
                content.userInfo["focus"] = true
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
                result.append((date, UNNotificationRequest(identifier: "focus.\(s.id)", content: content, trigger: trigger)))
            }
        }
        if p.startReminders {
            for b in snapshot.blocks where b.status == "confirmed" {
                guard let start = b.startAt, let t = snapshot.tasks.first(where: { $0.id == b.taskID && !$0.isArchived && $0.completedAt == nil }) else { continue }
                guard t.skippedAt == nil,
                      !snapshot.sessions.contains(where: { s in
                          s.planBlockID == b.id && s.status != "discarded"
                      }) else { continue }
                add(id: "block.\(b.id)", title: "Time for your next drop", body: t.title, date: start, taskID: t.id, blockID: b.id)
            }
        }
        for goal in snapshot.goals where !goal.isArchived && goal.completedAt == nil {
            guard let due = goal.dueAt else { continue }
            for days in [1, 3] where (days == 1 ? p.deadlineOneDay : p.deadlineThreeDays) {
                guard let date = calendar.date(byAdding: .day, value: -days, to: due) else { continue }
                let reminder = goal.isDateOnly ? StudyTime.atMinute(540, on: date, calendar: calendar) : date
                add(id: "goal.\(goal.id).\(days)", title: "\(goal.title) · \(days)d to go", body: "Review the remaining steps in your plan.", date: reminder, goalID: goal.id)
            }
        }
        if p.eveningReview {
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: now)!
                guard !snapshot.reviews.contains(where: { $0.dayKey == StudyTime.dayKey(day, calendar: calendar) && !$0.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
                add(id: "review.\(StudyTime.dayKey(day, calendar: calendar))", title: "A moment to reflect", body: "Save a short note about today's flow.", date: StudyTime.atMinute(p.reviewMinute, on: day, calendar: calendar))
            }
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if info["focus"] as? Bool == true { await MainActor.run { navigateToFocus() }; return }
        let task = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
        let goal = (info["goalID"] as? String).flatMap(UUID.init(uuidString:))
        let block = (info["blockID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run { navigate(taskID:task,goalID:goal,blockID:block) }
    }
}

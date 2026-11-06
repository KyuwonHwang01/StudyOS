import SwiftUI
import Charts

struct OceanView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var period = 0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let cal = Calendar.current
            let start = period == 0 ? cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))! : cal.dateInterval(of: .month, for: now)!.start
            let sessions = store.sessions.filter { $0.status == "finished" && ($0.endedAt ?? $0.startedAt) >= start && ($0.endedAt ?? $0.startedAt) <= now }
            let actual = sessions.reduce(0) { $0 + $1.accumulatedActiveSeconds }
            let goalMinutes = period == 0 ? store.preferences.availability.reduce(0) { $0 + min($1, store.preferences.maxDailyMinutes) } : monthlyCapacity(now)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Every drop becomes an ocean.").font(.subheadline).foregroundStyle(Water.secondary)
                    Picker("Period", selection: $period) { Text("Last 7 days").tag(0); Text("This month").tag(1) }.pickerStyle(.segmented)
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(StudyTime.duration(actual)).font(.system(.largeTitle, design: .rounded, weight: .medium))
                            Text("actual focus time").font(.subheadline).foregroundStyle(Water.secondary)
                        }
                    }
                    WaterSurfaceView(progress: goalMinutes > 0 ? actual / Double(goalMinutes * 60) : 0)
                        .overlay {
                            if !typeSize.isAccessibilitySize {
                                VStack(spacing: 6) {
                                    Text(StudyTime.duration(actual)).font(.system(.largeTitle, design: .rounded, weight: .medium))
                                    Text("actual focus time").font(.caption)
                                }.foregroundStyle(Water.ink).padding(20).background(Water.surface.opacity(0.92), in: Capsule())
                            }
                        }
                    WaterCard {
                        VStack(alignment: .leading, spacing: 16) {
                            if typeSize.isAccessibilitySize {
                                SectionHeading(title: "Your progress is taking shape")
                                DropletBadge(count: store.tasks.filter { $0.firstCompletedAt != nil }.count)
                            } else {
                                HStack { SectionHeading(title: "Your progress is taking shape"); DropletBadge(count: store.tasks.filter { $0.firstCompletedAt != nil }.count) }
                            }
                            let newDrops = store.tasks.filter { $0.firstCompletedAt.map { $0 >= start && $0 <= now } ?? false }.count
                            Text("\(newDrops) first task completions this period").font(.subheadline)
                            Text("Lifetime · \(StudyTime.duration(store.sessions.filter { $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds })) focused").font(.subheadline).foregroundStyle(Water.secondary)
                            LiquidProgressBar(progress: goalMinutes > 0 ? actual / Double(goalMinutes * 60) : 0)
                            Text("\(goalMinutes) min available this period. Water level shows actual time relative to availability. Drops count each task's first completion once, including archived history.").font(.caption).foregroundStyle(Water.secondary)
                        }
                    }
                    WaterCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(title: "A steady rhythm", subtitle: "\(ProgressCalculator.consistency(store.sessions.map(\.snapshot), now: now))/7 days with at least 10 active minutes")
                            Chart {
                                ForEach(0..<7, id: \.self) { offset in
                                    let day = cal.date(byAdding: .day, value: offset - 6, to: now)!
                                    let seconds = store.sessions.filter { $0.status == "finished" && cal.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
                                    BarMark(x: .value("Day", cal.startOfDay(for: day), unit: .day), y: .value("Active minutes", seconds / 60)).foregroundStyle(Water.glass).cornerRadius(4)
                                }
                            }.chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }.frame(height: 130)
                            Text("Session time is attributed to the local day it ends. Pauses and unfinished sessions are excluded.").font(.caption).foregroundStyle(Water.secondary)
                        }
                    }
                    if sessions.isEmpty { EmptyStateView(title: "Your first drop starts here", message: "Saved focus sessions and completed tasks will make this ocean yours.") }
                    else {
                        SectionHeading(title: "By subject")
                        WaterCard {
                            VStack(spacing: 16) {
                                let grouped = Dictionary(grouping: sessions, by: { $0.subjectID })
                                ForEach(grouped.keys.sorted { store.subjectName($0) < store.subjectName($1) }, id: \.self) { id in
                                    let seconds = grouped[id, default: []].reduce(0) { $0 + $1.accumulatedActiveSeconds }
                                    VStack(spacing: 8) {
                                        HStack { Text(store.subjectName(id)); Spacer(); Text(StudyTime.duration(seconds)).monospacedDigit() }.font(.subheadline)
                                        LiquidProgressBar(progress: actual > 0 ? seconds / actual : 0)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(store.goals.filter { !$0.isArchived }) { GoalProgressCard(goal: $0) }
                    let coaching = CoachingEngine.notes(tasks: store.tasks.map(\.snapshot), goals: store.goals.map(\.snapshot), blocks: store.blocks.map(\.snapshot), sessions: store.sessions.map(\.snapshot), preferences: store.preferences.snapshot, now: now)
                    if !coaching.isEmpty {
                        SectionHeading(title: "A little perspective", subtitle: "Rule-based suggestions from your saved plan and records.")
                        ForEach(coaching, id: \.self) { note in WaterCard { Text(note).font(.subheadline) } }
                    }
                    NavigationLink("Session history") { SessionHistoryView() }.frame(minHeight: 44)
                }.padding(20)
            }.waterPage().navigationTitle("Ocean")
        }
    }
    private func monthlyCapacity(_ now: Date) -> Int {
        let cal = Calendar.current, interval = cal.dateInterval(of: .month, for: now)!
        var day = interval.start, minutes = 0
        while day < interval.end {
            minutes += min(store.preferences.maxDailyMinutes, store.preferences.availability[cal.component(.weekday, from: day) - 1])
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return minutes
    }
}
struct GoalProgressCard: View {
    @Environment(StudyStore.self) private var store
    var goal: StudyGoal
    var showOpenButton = true
    @State private var editing = false
    var body: some View {
        let tasks = store.tasks.filter { $0.goalID == goal.id && (!$0.isArchived || $0.completedAt != nil) && $0.skippedAt == nil }
        let done = tasks.filter { $0.completedAt != nil }.count
        WaterCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(goal.title).font(.headline)
                        Text(store.subjectName(goal.subjectID)).font(.caption).foregroundStyle(Water.secondary)
                    }
                    Spacer(); Button { editing = true } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Edit \(goal.title)")
                }
                if let due = goal.dueAt { DeadlineChip(date: due) }
                LiquidProgressBar(progress: ProgressCalculator.completion(done: done, total: tasks.count) ?? 0)
                Text(tasks.isEmpty ? "No linked tasks yet" : "\(done)/\(tasks.count) tasks complete · item count").font(.caption).foregroundStyle(Water.secondary)
                if showOpenButton { NavigationLink("View tasks or add work") { GoalDetailView(goal: goal) }.font(.subheadline).frame(minHeight: 44) }
                if !tasks.isEmpty && done == tasks.count && goal.completedAt == nil {
                    Button("Mark goal complete") { store.completeGoal(goal) }.font(.subheadline).frame(minHeight: 44)
                }
                if goal.completedAt != nil { Label("Goal completed", systemImage: "checkmark.seal").font(.caption) }
                if goal.targetMinutes > 0 {
                    let ids = Set(store.tasks.filter { $0.goalID == goal.id }.map(\.id))
                    let seconds = store.sessions.filter { ids.contains($0.taskID) && $0.status == "finished" }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
                    Text("\(StudyTime.duration(seconds)) actual · \(goal.targetMinutes) min target").font(.caption).foregroundStyle(Water.secondary)
                }
            }
        }.sheet(isPresented: $editing) { GoalEditor(goal: goal) }
    }
}
struct SessionHistoryView: View {
    @Environment(StudyStore.self) private var store
    var body: some View {
        List {
            ForEach(store.sessions.filter { $0.status == "finished" }.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }) { session in
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.task(session.taskID)?.title ?? "Archived study").font(.headline)
                    Text("\(StudyTime.duration(session.accumulatedActiveSeconds)) · \((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Water.secondary)
                    Text(session.understandingRating.map { "Understanding: \($0)/5 · self-rated" } ?? "Understanding: not rated").font(.caption)
                    if !session.sessionNote.isEmpty { Text(session.sessionNote).font(.subheadline) }
                }.padding(.vertical, 8)
            }
            if !store.sessions.contains(where: { $0.status == "finished" }) { EmptyStateView(title: "No saved sessions yet", message: "Start a focus session from a task.") }
        }.navigationTitle("Session history")
    }
}

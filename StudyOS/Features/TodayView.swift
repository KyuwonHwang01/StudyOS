import SwiftUI

struct TodayView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var adding = false
    @State private var review = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let tasks = store.dayTasks(now)
            let done = tasks.filter { $0.completedAt != nil }.count
            let plan = store.blocks.filter { $0.status != "canceled" && Calendar.current.isDate($0.day, inSameDayAs: now) }
            let carried = store.carriedOverTasks(now: now)
            let todayIDs = Set(tasks.map(\.id)).union(carried.map(\.id))
            let ready = store.tasks.filter { t in
                !t.isArchived && t.completedAt == nil && t.skippedAt == nil && !todayIDs.contains(t.id) && (t.recurrenceID == nil || t.deadline != nil) &&
                (t.scheduledDay.map { $0 <= now } ?? true) && !store.blocks.contains { $0.taskID == t.id && $0.status == "confirmed" && $0.day >= Calendar.current.startOfDay(for: now) }
            }
            let next = nextTask(tasks, blocks: plan, now: now) ?? ready.sorted { $0.priority > $1.priority }.first
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.subheadline).foregroundStyle(Water.secondary)
                    WaterCard {
                        VStack(alignment: .leading, spacing: 18) {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Today's flow").font(.title2.weight(.medium))
                                    DropletBadge(count: dailyDrops(now))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tasks.isEmpty ? "—" : "\(done)/\(tasks.count)").font(.system(.largeTitle, design: .rounded, weight: .medium))
                                    Text("tasks complete").font(.subheadline).foregroundStyle(Water.secondary)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Today's flow").font(.title2.weight(.medium)); Spacer()
                                    DropletBadge(count: dailyDrops(now))
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(tasks.isEmpty ? "—" : "\(done)/\(tasks.count)").font(.system(.largeTitle, design: .rounded, weight: .medium))
                                    Text("tasks complete").font(.subheadline).foregroundStyle(Water.secondary)
                                }
                            }
                            LiquidProgressBar(progress: ProgressCalculator.completion(done: done, total: tasks.count) ?? 0)
                            let actual = store.sessions.filter { $0.status == "finished" && Calendar.current.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: now) }.reduce(0) { $0 + $1.accumulatedActiveSeconds }
                            Text("\(StudyTime.duration(actual)) focused · \(plan.reduce(0) { $0 + $1.durationMinutes }) min planned").font(.subheadline).foregroundStyle(Water.secondary)
                        }
                    }
                    if !carried.isEmpty { CarryOverCard(tasks: carried) }
                    if let active = store.activeSession, let current = store.task(active.taskID) {
                        Button { store.presentFocus(current, sourceID:current.id) } label: {
                            WaterCard { Label("\(active.status == "paused" ? "Resume" : "Return to") · \(current.title)", systemImage: "timer").font(.headline) }.modifier(FocusSource(id:current.id))
                        }.buttonStyle(.plain)
                    } else if let next {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: "Next up", subtitle: "One thing. Your full attention.")
                            WaterCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(store.subjectName(next.subjectID).uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Water.accent)
                                    Text(next.title).font(.title2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                    let block = plan.filter { $0.taskID == next.id && $0.status == "confirmed" }.sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }.first
                                    Text("\(block.map { store.remainingMinutes($0) } ?? store.remainingTaskMinutes(next)) min remaining · \(block?.startAt?.formatted(date: .omitted, time: .shortened) ?? "Flexible")").font(.subheadline).foregroundStyle(Water.secondary)
                                    ForEach(next.steps.filter { !$0.isDone }.prefix(2)) { Text("○  \($0.title)").font(.subheadline).foregroundStyle(Water.secondary) }
                                    Button { store.presentFocus(next, blockID: block?.id, sourceID:next.id) } label: { Label("Start focus", systemImage: "play.fill") }.buttonStyle(FlowButton()).accessibilityIdentifier("startFocus")
                                }
                            }.modifier(FocusSource(id:next.id))
                        }
                    }
                    if tasks.isEmpty {
                        WaterCard {
                            EmptyStateView(title: "No tasks planned", message: "Add a task or shape the next seven days with a plan.")
                            Button("Add task", systemImage: "plus") { adding = true }.buttonStyle(FlowButton())
                            NavigationLink("Generate plan") { PlanReviewView() }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else {
                        SectionHeading(title: done == tasks.count ? "Your drops are collected" : "Today's tasks")
                        ForEach(tasks.filter { $0.completedAt == nil }) { TaskRow(task: $0) }
                        if done > 0 { DisclosureGroup("Completed · \(done)") { ForEach(tasks.filter { $0.completedAt != nil }) { TaskRow(task: $0) } } }

                    }
                    if !ready.isEmpty {
                        DisclosureGroup("Ready when you are · \(ready.count)") { ForEach(ready) { TaskRow(task: $0) } }
                    }
                    let deadlines = store.goals.filter { !$0.isArchived && $0.completedAt == nil && $0.dueAt != nil }.sorted { $0.dueAt! < $1.dueAt! }
                    if !deadlines.isEmpty {
                        SectionHeading(title: "On the horizon")
                        ForEach(deadlines.prefix(2)) { GoalProgressCard(goal: $0) }
                    }
                    Button { review = true } label: {
                        WaterCard { HStack { Label("Evening reflection", systemImage: "moon"); Spacer(); Image(systemName: "arrow.up.right") } }
                    }.buttonStyle(.plain)
                }.padding(20)
            }.waterPage().navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { NavigationLink { LibraryView() } label: { Image(systemName: "books.vertical").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Manage your studies") }
                    ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Add task").accessibilityIdentifier("addTask") }
                }
                .sheet(isPresented: $adding) { TaskEditor(day: now) }
                .sheet(isPresented: $review) { DailyReviewView() }
        }
    }
    private func dailyDrops(_ now: Date) -> Int {
        store.tasks.filter { $0.firstCompletedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false }.count
    }
    private func nextTask(_ tasks: [StudyTask], blocks: [StudyPlanBlock], now: Date) -> StudyTask? {
        let pending = tasks.filter { $0.completedAt == nil }
        let nextBlock = blocks.filter { $0.status == "confirmed" && ($0.startAt ?? .distantFuture) >= now }.sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }.first
        return pending.first { $0.id == nextBlock?.taskID } ?? pending.sorted { $0.priority > $1.priority }.first
    }
}
/// Unfinished one-off work from earlier days. One tap brings it into today; nothing moves without that tap.
struct CarryOverCard: View {
    @Environment(StudyStore.self) private var store
    var tasks: [StudyTask]
    var body: some View {
        WaterCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Not finished earlier · \(tasks.count)", subtitle: "Bring them into today, or keep them for later.")
                ForEach(tasks.prefix(5)) { task in
                    HStack(spacing: 8) {
                        NavigationLink { TaskDetailView(task: task) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.subheadline.weight(.medium))
                                Text("\(store.subjectName(task.subjectID)) · \(task.scheduledDay?.formatted(.dateTime.month(.abbreviated).day()) ?? "")").font(.caption).foregroundStyle(Water.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { store.carryOver([task], toToday: true) } label: { Image(systemName: "arrow.down.to.line").frame(width: 44, height: 44) }
                            .accessibilityLabel("Move \(task.title) to today")
                        Button { store.carryOver([task], toToday: false) } label: { Image(systemName: "clock").frame(width: 44, height: 44) }
                            .accessibilityLabel("Keep \(task.title) for later")
                    }
                }
                if tasks.count > 5 { Text("+\(tasks.count - 5) more").font(.caption).foregroundStyle(Water.secondary) }
                Button("Move \(tasks.count == 1 ? "it" : "all") to today", systemImage: "arrow.down.to.line") { store.carryOver(tasks, toToday: true) }
                    .buttonStyle(FlowButton()).accessibilityIdentifier("carryOverAll")
            }
        }
    }
}
struct TaskRow: View {
    @Environment(StudyStore.self) private var store
    var task: StudyTask
    var body: some View {
        WaterCard {
            HStack(alignment: .top, spacing: 12) {
                Button { store.toggleCompletion(task) } label: {
                    Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.title2).frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(Water.accent)
                    .accessibilityLabel(task.completedAt == nil ? "Complete \(task.title)" : "Reopen \(task.title)")
                    .modifier(RippleCompletionEffect(trigger: task.completedAt != nil))
                NavigationLink { TaskDetailView(task: task) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title).font(.headline).strikethrough(task.completedAt != nil)
                        Text("\(store.subjectName(task.subjectID)) · \(task.estimatedMinutes) min").font(.caption).foregroundStyle(Water.secondary)
                        if let due = task.deadline { DeadlineChip(date: due) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }.contextMenu {
            Button("Start focus", systemImage: "play.fill") { store.presentFocus(task) }.disabled(task.completedAt != nil || task.skippedAt != nil)
            Button("Archive", systemImage: "archivebox") { store.requestArchive(task) }
        }
    }
}
struct TaskDetailView: View {
    @Environment(StudyStore.self) private var store
    var task: StudyTask
    var initialBlockID: UUID? = nil
    @State private var focusSourceID = UUID()
    @State private var editing = false
    @State private var scheduling = false
    @State private var resources = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(store.subjectName(task.subjectID)).font(.subheadline).foregroundStyle(Water.secondary)
                Text(task.title).font(.largeTitle.weight(.medium))
                HStack { PriorityChip(priority: task.priority); Text("\(task.estimatedMinutes) min").font(.caption); if let d = task.deadline { DeadlineChip(date: d) } }
                if task.isArchived {
                    Button("Restore task", systemImage:"arrow.uturn.backward") { store.restoreTask(task) }.buttonStyle(FlowButton())
                } else if task.skippedAt != nil {
                    Text("This habit occurrence is kept as skipped history. Your current habit is available in Today.").foregroundStyle(Water.secondary)
                } else if task.completedAt == nil {
                    Button { store.presentFocus(task, blockID:initialBlockID, sourceID:focusSourceID) } label: { Label("Start focus", systemImage: "play.fill") }.buttonStyle(FlowButton()).modifier(FocusSource(id:focusSourceID))
                }
                if !task.isArchived && task.skippedAt == nil {
                    Button(task.completedAt == nil ? "Mark complete" : "Reopen task") { store.toggleCompletion(task) }.frame(minHeight: 44)
                }
                if !task.notes.isEmpty { WaterCard { Text(task.notes) } }
                if !task.steps.isEmpty { WaterCard { ChecklistView(task: task) } }
                WaterCard { ResourceList(task: task); Button("Add or edit resources") { resources = true }.frame(minHeight: 44) }
                if !task.isArchived && task.completedAt == nil && task.skippedAt == nil {
                    Button("Schedule or move task", systemImage: "calendar") { scheduling = true }.frame(minHeight: 44).accessibilityIdentifier("moveTaskBlock")
                }
                if !task.isArchived { Button("Archive task", systemImage: "archivebox") { store.requestArchive(task) }.frame(minHeight: 44).accessibilityIdentifier("archiveTask") }
            }.padding(20)
        }.waterPage().navigationTitle("Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Edit") { editing = true } }
                ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        if !task.isArchived && task.skippedAt == nil && task.completedAt == nil { Button("Move study block", systemImage:"calendar") { scheduling = true } }
                        Button("Resources", systemImage:"link") { resources = true }
                        if !task.isArchived { Button("Archive task",systemImage:"archivebox") { store.requestArchive(task) } }
                    } label: { Image(systemName:"ellipsis.circle").frame(width:44,height:44) }.accessibilityLabel("Task actions")
                }
            }
            .sheet(isPresented: $editing) { TaskEditor(task: task) }
            .sheet(isPresented: $scheduling) { TaskScheduleSheet(task: task) }
            .sheet(isPresented: $resources) { ResourceEditor(task: task) }
            .onChange(of: task.isArchived) { _, archived in if archived { dismiss() } }
            .onChange(of: store.focusRoute?.id) { _, route in if route == nil && task.completedAt != nil { dismiss() } }
    }
}
struct ReflectionDraft: Codable, Equatable { var text = "" }
struct DailyReviewView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var form = ReflectionDraft()
    @State private var baseline = ReflectionDraft()
    @State private var finished = false
    @State private var loaded = false
    private let reviewDayKey: String
    init(day: Date = Date()) { reviewDayKey = StudyTime.dayKey(day) }
    private var key: String { "reflection:\(reviewDayKey)" }
    var body: some View {
        NavigationStack {
            Form {
                Section("What moved forward? What will you carry into tomorrow?") { TextEditor(text: $form.text).frame(minHeight: 200).accessibilityLabel("Daily reflection") }
            }.navigationTitle("A moment to reflect").navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    if store.drafts.value(ReflectionDraft.self, for: key) != nil { return }
                    form.text = store.reviews.first { $0.dayKey == reviewDayKey }?.reflection ?? ""; baseline = form
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        store.saveReview(form.text, dayKey: reviewDayKey)
                        if store.error == nil { finished = true; store.drafts.consume(key); store.showToast("Reflection saved · today's reminder cleared"); dismiss() }
                    }.disabled(form.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.modifier(PersistedForm(value: $form, key: key, initial: baseline, finished: finished))
        }
    }
}

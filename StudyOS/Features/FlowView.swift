import SwiftUI

private enum FlowCalendarScope: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

struct FlowView: View {
    @Environment(StudyStore.self) private var store
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addingTask = false
    @State private var addingBlock = false
    @State private var editingBlock: StudyPlanBlock?
    @State private var calendarScope = FlowCalendarScope.month
    private var week: [Date] {
        CalendarLayout.weekDays(containing: day)
    }
    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Calendar view", selection: $calendarScope) {
                    ForEach(FlowCalendarScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("calendarScope")
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel(calendarScope == .month ? "Previous month" : "Previous week").accessibilityIdentifier("previousCalendarPeriod")
                    Text(day.formatted(.dateTime.month(.wide).year())).font(.headline).frame(maxWidth: .infinity).accessibilityIdentifier("flowPeriodTitle")
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel(calendarScope == .month ? "Next month" : "Next week").accessibilityIdentifier("nextCalendarPeriod")
                }
                if calendarScope == .month {
                    MonthCalendarView(selectedDay: $day)
                } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(week, id: \.self) { date in
                            let selected = Calendar.current.isDate(date, inSameDayAs: day)
                            Button { day = date } label: {
                                VStack(spacing: 8) {
                                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                    Text(date.formatted(.dateTime.day())).font(.title3.weight(.medium))
                                    Circle().fill(store.dayTasks(date).isEmpty ? .clear : selected ? Water.background : Water.accent).frame(width: 4, height: 4)
                                }.padding(.vertical, 12).frame(minWidth: 44).padding(.horizontal, 3)
                                    .foregroundStyle(selected ? Water.background : Water.ink)
                                    .background(selected ? Water.accent : Water.surface, in: Capsule())
                            }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                }
                NavigationLink { PlanReviewView() } label: {
                    WaterCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Shape your next seven days").font(.headline)
                                Text("Review a plan built around your time and deadlines.").font(.subheadline).foregroundStyle(Water.secondary)
                            }
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("generatePlan")
                SectionHeading(title: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), subtitle: "Confirmed blocks & flexible tasks")
                    .accessibilityIdentifier("selectedDayHeading")
                let blocks = store.blocks.filter { $0.status != "canceled" && Calendar.current.isDate($0.day, inSameDayAs: day) }.sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }
                if blocks.isEmpty && store.dayTasks(day).isEmpty {
                    EmptyStateView(title: "Room to make progress", message: "Add a task or review a suggested plan.", symbol: "calendar")
                }
                ForEach(blocks.filter { $0.status == "confirmed" }) { block in
                    if let task = store.task(block.taskID) {
                        WaterCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(block.startAt?.formatted(date: .omitted, time: .shortened) ?? "Flexible").font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if block.isLocked { Label("Locked", systemImage: "lock.fill").font(.caption) }
                                    Text("\(block.durationMinutes) min").font(.caption)
                                }.foregroundStyle(Water.accent)
                                NavigationLink { TaskDetailView(task: task) } label: { Text(task.title).font(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
                                Text(store.subjectName(task.subjectID)).font(.caption).foregroundStyle(Water.secondary)
                                HStack {
                                    let missed = block.status == "confirmed" && StudyTime.endOfDay(block.day) < Date() && task.completedAt == nil
                                    Label(missed ? "Missed · review a new plan" : block.status.capitalized, systemImage: missed ? "arrow.uturn.right" : "checkmark.seal").font(.caption).foregroundStyle(missed ? Water.warning : Water.secondary)
                                    Spacer()
                                    Button("Focus") { store.presentFocus(task, blockID: block.id, sourceID:block.id) }.frame(minHeight: 44)
                                    Button("Edit block") { editingBlock = block }.font(.subheadline).frame(minHeight: 44)
                                }
                            }
                        }.modifier(FocusSource(id:block.id))
                    }
                }
                let flexible = store.dayTasks(day).filter { task in !blocks.contains { $0.taskID == task.id && ($0.status == "confirmed" || day < Calendar.current.startOfDay(for:store.clock.now)) } }
                ForEach(flexible.filter { $0.completedAt == nil }) { TaskRow(task: $0) }
                let completed = store.dayTasks(day).filter { $0.completedAt.map { $0 <= StudyTime.endOfDay(day) } ?? false }
                if !completed.isEmpty { DisclosureGroup("Completed · \(completed.count)") { ForEach(completed) { TaskRow(task: $0) } } }
                let history = blocks.filter { $0.status == "completed" || $0.status == "missed" }
                if !history.isEmpty {
                    DisclosureGroup("Block history · \(history.count)") {
                        ForEach(history) { b in
                            VStack(alignment:.leading,spacing:6) {
                                Text(store.task(b.taskID)?.title ?? "Archived study").font(.subheadline)
                                Text("\(b.status.capitalized) · \(b.durationMinutes) min planned").font(.caption).foregroundStyle(Water.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,8)
                        }
                    }
                }
                let skipped = store.tasks.filter { $0.skippedAt != nil && $0.scheduledDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
                if !skipped.isEmpty { DisclosureGroup("Skipped habits · \(skipped.count)") { ForEach(skipped) { Text($0.title).foregroundStyle(Water.secondary) } } }
                HStack(spacing: 16) {
                    Button("Add task", systemImage: "plus") { addingTask = true }.frame(minHeight: 44)
                    Spacer()
                    Button("Add block", systemImage: "calendar.badge.plus") { addingBlock = true }.frame(minHeight: 44)
                }
                NavigationLink { LibraryView() } label: { Label("Subjects, goals & recurring habits", systemImage: "books.vertical").frame(minHeight: 44) }
                ForEach(store.goals.filter { !$0.isArchived && $0.completedAt == nil }) { GoalProgressCard(goal: $0) }
            }.padding(20)
        }.waterPage().navigationTitle("Flow")
            .navigationDestination(item: $store.goalDestination) { GoalDetailView(goal: $0) }
            .navigationDestination(item: $store.taskDestination) { route in
                if let task = store.task(route.taskID) { TaskDetailView(task: task, initialBlockID: route.blockID) }
            }
            .toolbar { Button("Today") { day = Calendar.current.startOfDay(for: Date()) } }
            .sheet(isPresented: $addingTask) { TaskEditor(day: day) }
            .sheet(isPresented: $addingBlock) { BlockEditor(initialDay: day) }
            .sheet(item: $editingBlock) { BlockEditor(block: $0) }
    }
    private func shift(_ direction: Int) {
        let component: Calendar.Component = calendarScope == .month ? .month : .weekOfYear
        if let date = Calendar.current.date(byAdding: component, value: direction, to: day) { day = Calendar.current.startOfDay(for: date) }
    }
}

struct PlanReviewView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [PlanSuggestion] = []
    @State private var warnings: [String] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var editingID: String?
    var body: some View {
        List {
            Section {
                Text("A suggestion, until you say yes.").font(.title2.weight(.medium))
                Text("Rules balance priorities, deadlines, recurring habits, and your availability. Existing confirmed and locked blocks stay in place. Missed work is proposed again; its history remains.").font(.subheadline).foregroundStyle(Water.secondary)
            }
            if !loaded { ProgressView("Finding room for your studies…") }
            ForEach(warnings, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Water.warning) }
            if loaded && proposals.isEmpty { EmptyStateView(title: "No new blocks", message: "Add pending tasks, expand your availability, or review the warnings.") }
            ForEach($proposals) { $s in
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.task(s.taskID)?.title ?? "Task").font(.headline)
                    Text(s.reason).font(.caption).foregroundStyle(Water.secondary)
                    DatePicker("Start", selection: Binding(get: { s.startAt ?? s.day }, set: { s.startAt = $0; s.day = Calendar.current.startOfDay(for: $0) }), in: Date()...)
                    Stepper("\(s.minutes) min", value: $s.minutes, in: 15...240, step: 15)
                }.padding(.vertical, 8)
            }.onDelete { proposals.remove(atOffsets: $0) }
            if !proposals.isEmpty {
                Section {
                    Text("\(proposals.count) blocks · \(proposals.reduce(0) { $0 + $1.minutes }) min. Swipe a block to remove it; edit its time or duration above. All edits are validated before saving.").font(.footnote).foregroundStyle(Water.secondary)
                    Button("Confirm plan") {
                        guard !saving else { return }; saving = true
                        if store.approve(proposals) { dismiss() } else { saving = false }
                    }.buttonStyle(FlowButton()).disabled(saving).accessibilityIdentifier("confirmPlan")
                }
            }
        }.navigationTitle("Review your flow").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Discard") { dismiss() } } }
            .task {
                guard !loaded else { return }
                let result = await store.proposeAsync()
                guard !Task.isCancelled else { return }
                proposals = result.suggestions; warnings = result.warnings; loaded = true
            }
    }
}

struct BlockFormDraft: Codable, Equatable {
    var taskID: UUID?; var day: Date; var start: Date; var timed = true; var minutes = 30; var locked = false
}
struct BlockEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var block: StudyPlanBlock?
    var taskID: UUID?
    var initialDay: Date?
    var onAddAnother: (() -> Void)?
    @State private var form: BlockFormDraft
    @State private var baseline: BlockFormDraft
    @State private var finished = false
    @State private var loaded = false
    @State private var canceling = false
    init(block: StudyPlanBlock? = nil, taskID: UUID? = nil, initialDay: Date? = nil, onAddAnother: (() -> Void)? = nil) {
        self.block = block; self.taskID = taskID; self.initialDay = initialDay; self.onAddAnother = onAddAnother
        let day = block?.day ?? initialDay ?? Date()
        let f = BlockFormDraft(taskID: block?.taskID ?? taskID, day: day, start: block?.startAt ?? day, timed: block == nil || block?.startAt != nil, minutes: block?.durationMinutes ?? 30, locked: block?.isLocked ?? false)
        _form = State(initialValue: f); _baseline = State(initialValue: f)
    }
    private var key: String { block.map { "block:\($0.id)" } ?? "block:new:\(taskID?.uuidString ?? "any")" }
    private var proposal: PlanSuggestion? {
        guard let id = form.taskID else { return nil }
        let cal = Calendar.current
        let start = form.timed ? cal.date(bySettingHour: cal.component(.hour, from: form.start), minute: cal.component(.minute, from: form.start), second: 0, of: form.day) : nil
        return PlanSuggestion(taskID: id, day: cal.startOfDay(for: form.day), startAt: start, minutes: form.minutes, reason: "Manual")
    }
    private var lockOnly: Bool {
        guard let b = block, let p = proposal else { return false }
        return Calendar.current.isDate(p.day, inSameDayAs: b.day) && p.startAt == b.startAt && p.minutes == b.durationMinutes
    }
    private var validation: String? {
        if lockOnly { return nil }
        guard let p = proposal else { return "Choose a task to schedule." }
        if let b = block, store.activeSession?.planBlockID == b.id { return "Save your open session's time before moving this block." }
        do { try store.validate([p], excluding: block?.id); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Task", selection: Binding(get: { form.taskID }, set: { pick($0) })) {
                    Text("Choose a task").tag(UUID?.none)
                    ForEach(store.tasks.filter { !$0.isArchived && $0.skippedAt == nil && ($0.completedAt == nil || $0.id == block?.taskID) }) { Text($0.title).tag(Optional($0.id)) }
                }.disabled(block != nil)
                Toggle("Locked", isOn: $form.locked)
                Section {
                    DatePicker("Day", selection: $form.day, displayedComponents: .date).accessibilityIdentifier("blockDay")
                    Toggle("Set a start time", isOn: $form.timed)
                    if form.timed { DatePicker("Start", selection: $form.start, displayedComponents: .hourAndMinute) }
                    Stepper("\(form.minutes) min", value: $form.minutes, in: 1...1440, step: 15).accessibilityIdentifier("blockDuration")
                }.disabled(form.locked)
                if form.locked { Text("Unlock to change the time. The planner never moves a confirmed block.").font(.footnote) }
                if let message = validation { Text(message).font(.subheadline).foregroundStyle(Water.warning).accessibilityIdentifier("blockValidation") }
                if let b = block, let active = store.activeSession, active.planBlockID == b.id {
                    Button("Save focus time before moving") {
                        if store.elapsed(active) >= 1 { _ = store.finish(active, rating: active.understandingRating, note: active.sessionNote, markComplete: false) }
                        else { store.discard(active) }
                        form.minutes = max(1, store.remainingMinutes(b))
                    }
                }
                Button("Use next available time", systemImage: "clock.arrow.circlepath") { findSlot() }.disabled(form.taskID == nil || form.locked).accessibilityIdentifier("findAvailableSlot")
                if let onAddAnother { Button("Add another block for this task", systemImage: "plus", action: onAddAnother) }
                if let block, block.status == "confirmed" { Button("Remove block", role: .destructive) { canceling = true }.disabled(form.locked) }
            }.navigationTitle(block == nil ? "Schedule a block" : "Move study block").navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    if store.drafts.value(BlockFormDraft.self, for: key) != nil { return }
                    if let b = block { form.minutes = max(1, store.remainingMinutes(b)) }
                    else {
                        form.minutes = suggestedMinutes(form.taskID)
                        form.start = StudyTime.atMinute(store.preferences.windowStart, on: form.day)
                        if Calendar.current.isDate(form.day, inSameDayAs: store.clock.now) { findSlot() }
                    }
                    baseline = form
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(validation != nil).accessibilityIdentifier("saveBlock") }
                }
                .modifier(PersistedForm(value: $form, key: key, initial: baseline, finished: finished))
                .confirmationDialog("Remove the reservation? Your task and study history stay.", isPresented: $canceling, titleVisibility: .visible) {
                    Button("Remove block", role: .destructive) { if let block { store.cancelBlock(block); finished = true; store.drafts.consume(key); dismiss() } }
                }
        }
    }
    /// What is still unreserved for the task, in quarter hours (15...240).
    private func suggestedMinutes(_ id: UUID?) -> Int {
        guard let id, let task = store.task(id) else { return 30 }
        let reserved = store.blocks.filter { $0.taskID == id && $0.status == "confirmed" && $0.day >= Calendar.current.startOfDay(for: store.clock.now) }
            .reduce(0) { $0 + store.remainingMinutes($1) }
        let open = store.remainingTaskMinutes(task) - reserved
        return min(240, max(15, (open + 14) / 15 * 15))
    }
    /// Choosing the task for a new block fills its length and, for today, the next free time — the same as opening from a task.
    private func pick(_ id: UUID?) {
        form.taskID = id
        guard block == nil, id != nil else { return }
        form.minutes = suggestedMinutes(id)
        if Calendar.current.isDate(form.day, inSameDayAs: store.clock.now) { findSlot() }
    }
    private func findSlot() {
        guard let id = form.taskID, let slot = store.nextAvailableSlot(taskID: id, minutes: form.minutes, from: form.day, excluding: block?.id) else { return }
        form.day = slot.day; form.start = slot.startAt!; form.timed = true
    }
    private func save() {
        if lockOnly, let block {
            if store.commit({ block.isLocked = form.locked }) { finished = true; store.drafts.consume(key); dismiss() }; return
        }
        guard let p = proposal else { return }
        if store.saveBlock(block, suggestion: p, locked: form.locked) { finished = true; store.drafts.consume(key); dismiss() }
    }
}

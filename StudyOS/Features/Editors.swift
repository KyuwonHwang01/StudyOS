import SwiftUI

struct TaskFormDraft: Codable, Equatable {
    var base: StudyTaskSnapshot
    var task: StudyTaskSnapshot
    var hasDue: Bool
    var hasDay: Bool
    var newStep = ""
    var linkTitle = ""
    var linkURL = ""
    init(task: StudyTaskSnapshot) { self.base = task; self.task = task; hasDue = task.deadline != nil; hasDay = task.scheduledDay != nil }
    func merged(over current: StudyTaskSnapshot) -> TaskFormDraft {
        var result = self, value = current
        if hasDue == (base.deadline != nil) { result.hasDue = current.deadline != nil }
        if hasDay == (base.scheduledDay != nil) { result.hasDay = current.scheduledDay != nil }
        if task.title != base.title { value.title = task.title }
        if task.notes != base.notes { value.notes = task.notes }
        if task.subjectID != base.subjectID { value.subjectID = task.subjectID }
        if task.goalID != base.goalID { value.goalID = task.goalID }
        if task.estimatedMinutes != base.estimatedMinutes { value.estimatedMinutes = task.estimatedMinutes }
        if task.priority != base.priority { value.priority = task.priority }
        if task.deadline != base.deadline { value.deadline = task.deadline }
        if task.deadlineDateOnly != base.deadlineDateOnly { value.deadlineDateOnly = task.deadlineDateOnly }
        if task.scheduledDay != base.scheduledDay { value.scheduledDay = task.scheduledDay }
        if task.resources != base.resources {
            let removed = Set(base.resources.map(\.id)).subtracting(task.resources.map(\.id))
            value.resources.removeAll { removed.contains($0.id) }
            for resource in task.resources where !base.resources.contains(where: { $0.id == resource.id }) && !value.resources.contains(where: { StudyTime.resourceKey($0.url) == StudyTime.resourceKey(resource.url) }) { value.resources.append(resource) }
        }
        if task.steps != base.steps {
            let removed = Set(base.steps.map(\.id)).subtracting(task.steps.map(\.id))
            value.steps.removeAll { removed.contains($0.id) }
            for step in task.steps {
                if let old = base.steps.first(where: { $0.id == step.id }) {
                    if let i = value.steps.firstIndex(where: { $0.id == step.id }) {
                        if step.title != old.title { value.steps[i].title = step.title }
                        if step.isDone != old.isDone { value.steps[i].isDone = step.isDone }
                    } else if step != old { value.steps.append(step) }
                } else if !value.steps.contains(where: { $0.id == step.id }) { value.steps.append(step) }
            }
        }
        result.base = current; result.task = value
        return result
    }
}
private enum TaskLinkChange { case goal(UUID), subject(UUID?) }

struct TaskEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var original: StudyTask?
    private let initial: TaskFormDraft
    @State private var form: TaskFormDraft
    @State private var finished = false
    @State private var saving = false
    @State private var addingGoal = false
    @State private var addingSubject = false
    @State private var createdGoal: StudyGoal?
    @State private var createdSubject: Subject?
    @State private var moving = false
    @State private var pendingLink: TaskLinkChange?
    @State private var message: String?
    @State private var conflictCount = 0
    @FocusState private var focusedInput: TaskInput?
    private enum TaskInput { case step, linkTitle, linkURL }
    private var key: String { original.map { "task:\($0.id)" } ?? "task:new" }
    private var selectableGoals: [StudyGoal] { store.goals.filter { (!$0.isArchived && $0.completedAt == nil) || $0.id == form.task.goalID } }
    private var scheduledBlocks: [StudyPlanBlock] { store.blocks.filter { $0.taskID == original?.id && $0.status == "confirmed" } }

    init(task: StudyTask? = nil, day: Date? = nil, goal: StudyGoal? = nil) {
        original = task
        let value = task?.snapshot ?? StudyTask(subjectID: goal?.subjectID, goalID: goal?.id, scheduledDay: day).snapshot
        initial = TaskFormDraft(task: value); _form = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let message { Section {
                    Text(message).foregroundStyle(Water.warning).accessibilityIdentifier("taskValidation")
                    if let goal = store.goals.first(where: { $0.id == form.task.goalID }), let owner = goal.subjectID, owner != form.task.subjectID {
                        Button("Use goal's subject") { form.task.subjectID = owner; clearMessage() }
                    }
                    if conflictCount > 0 {
                        Button("Move \(conflictCount == 1 ? "it" : "them") to free time before the deadline & save", systemImage: "clock.arrow.circlepath") { save(resolve: .move) }
                            .accessibilityIdentifier("moveConflictingBlocks")
                        Button("Remove \(conflictCount == 1 ? "the block" : "\(conflictCount) blocks") & save", role: .destructive) { save(resolve: .remove) }
                    }
                } }
                Section("Task") {
                    TextField("What will you work on?", text: $form.task.title).accessibilityIdentifier("taskTitle")
                    HStack {
                        if store.subjects.filter({ !$0.isArchived || $0.id == form.task.subjectID }).isEmpty { LabeledContent("Subject", value: "Independent study") }
                        else {
                            StudyRecordPicker(title: "Subject", emptyTitle: "Independent study", selection: form.task.subjectID,
                                            options: store.subjects.filter { !$0.isArchived || $0.id == form.task.subjectID }.map { StudyRecordOption(id: $0.id, title: $0.name) },
                                            onSelect: selectSubject).accessibilityIdentifier("taskSubjectPicker")
                        }
                        Button { addingSubject = true } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }.accessibilityLabel("Add subject").accessibilityIdentifier("addTaskSubject")
                    }
                }
                Section {
                    if selectableGoals.isEmpty { Text(store.goals.isEmpty ? "No goals yet" : "No active goals").foregroundStyle(Water.secondary).accessibilityIdentifier("noGoalsMessage") }
                    else {
                        StudyRecordPicker(title: "Goal", emptyTitle: "No goal", selection: form.task.goalID,
                                        options: selectableGoals.map { StudyRecordOption(id: $0.id, title: $0.title) },
                                        onSelect: selectGoal).accessibilityIdentifier("taskGoalPicker")
                    }
                    if let selected = store.goals.first(where: { $0.id == form.task.goalID }), (selected.completedAt != nil || selected.isArchived), original == nil {
                        Text("Saving a new task here reopens this goal. Existing paused habits stay paused.").font(.caption).foregroundStyle(Water.secondary)
                    }
                    Button("Add goal", systemImage: "plus") { addingGoal = true }.accessibilityIdentifier("addTaskGoal")
                } header: { Text("Goal · optional") } footer: { Text("A goal groups work around an exam or project. Selecting one fills an empty subject automatically.") }
                Section("Effort") {
                    Stepper("Estimate: \(form.task.estimatedMinutes) min", value: $form.task.estimatedMinutes, in: 15...14400, step: 15).accessibilityIdentifier("taskEstimate")
                    Picker("Priority", selection: $form.task.priority) { Text("Low").tag(1); Text("Normal").tag(2); Text("High").tag(3) }
                }
                Section {
                    if !scheduledBlocks.isEmpty {
                        Text("\(scheduledBlocks.count) confirmed study blocks")
                        Button("Move a study block", systemImage: "calendar") { moving = true }.accessibilityIdentifier("moveTaskBlock")
                    } else {
                        Toggle("Plan on a day", isOn: $form.hasDay)
                        if form.hasDay { DatePicker("Day", selection: Binding(get: { form.task.scheduledDay ?? Date() }, set: { form.task.scheduledDay = $0 }), displayedComponents: .date) }
                    }
                    Toggle("Deadline", isOn: $form.hasDue)
                    if form.hasDue {
                        Toggle("Date only", isOn: $form.task.deadlineDateOnly)
                        DatePicker("Due", selection: Binding(get: { form.task.deadline ?? Date() }, set: { form.task.deadline = $0 }), displayedComponents: form.task.deadlineDateOnly ? [.date] : [.date, .hourAndMinute])
                    }
                } footer: { Text("Date-only deadlines end at the end of your local day. Confirmed blocks are edited directly so moving work never creates duplicate reservations.") }
                Section("Learning checklist") {
                    ForEach($form.task.steps) { $step in
                        HStack { Toggle("Done", isOn: $step.isDone).labelsHidden().accessibilityLabel("Complete \(step.title)"); TextField("Step", text: $step.title) }
                    }.onDelete { form.task.steps.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a step", text: $form.newStep).focused($focusedInput, equals: .step).submitLabel(.next)
                            .onSubmit { appendStep(); focusedInput = .step }  // stay in the field for the next step
                        Button { appendStep() } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }.disabled(form.newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Add learning step")
                    }
                }
                Section("Resources") {
                    ForEach(form.task.resources) { r in VStack(alignment: .leading) { Text(r.title); Text(r.url).font(.caption).foregroundStyle(Water.secondary) } }
                        .onDelete { form.task.resources.remove(atOffsets: $0) }
                    TextField("Link title · optional", text: $form.linkTitle).focused($focusedInput, equals: .linkTitle).submitLabel(.next)
                        .onSubmit { focusedInput = .linkURL }
                    TextField("https://…", text: $form.linkURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("taskResourceURL")
                        .focused($focusedInput, equals: .linkURL).submitLabel(.done)
                        .onSubmit { do { try appendLink(); focusedInput = .linkTitle } catch { message = error.localizedDescription } }
                    Button("Add another link") { do { try appendLink() } catch { message = error.localizedDescription } }.disabled(form.linkURL.isEmpty)
                    Text("A link or step still in its input field is included when you save the task.").font(.caption).foregroundStyle(Water.secondary)
                }
                Section("Notes") { TextEditor(text: $form.task.notes).frame(minHeight: 100).accessibilityLabel("Task notes") }
            }.safeAreaInset(edge: .top, spacing: 0) { relationshipResolution }
                .navigationTitle(original == nil ? "New task" : "Edit task").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || pendingLink != nil || form.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveTask") }
                }
                .modifier(PersistedForm(value: $form, key: key, initial: initial, finished: finished, transform: { old in original.map { old.merged(over: $0.snapshot) } ?? old }))
        }.tint(Water.accent)
            .sheet(isPresented: $addingGoal, onDismiss: {
                if let createdGoal { selectGoal(createdGoal.id); self.createdGoal = nil }
            }) { GoalEditor(initialSubjectID: form.task.subjectID) { createdGoal = $0 } }
            .sheet(isPresented: $addingSubject, onDismiss: {
                if let createdSubject { selectSubject(createdSubject.id); self.createdSubject = nil }
            }) { SubjectEditor { createdSubject = $0 } }
            .sheet(isPresented: $moving) { if let original { TaskScheduleSheet(task: original) } }
    }

    @ViewBuilder private var relationshipResolution: some View {
        if let change = pendingLink {
            VStack(alignment: .leading, spacing: 8) {
                Text("Update task links?").font(.headline)
                switch change {
                case .goal(let id):
                    Text("This goal belongs to another subject. Use its subject to keep this task linked to it.").font(.subheadline)
                    Button("Use goal's subject") {
                        if let goal = store.goals.first(where: { $0.id == id }) { form.task.subjectID = goal.subjectID; form.task.goalID = goal.id }
                        pendingLink = nil
                    }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                case .subject(let id):
                    Text("Changing the subject removes the current goal link. Your task and goal are kept.").font(.subheadline)
                    Button("Change subject & unlink goal") { form.task.subjectID = id; form.task.goalID = nil; pendingLink = nil }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                }
                Button("Keep current selection") { pendingLink = nil }.frame(maxWidth: .infinity, minHeight: 44)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(Water.soft)
        }
    }
    private func clearMessage() { message = nil; conflictCount = 0 }
    private enum ConflictResolution { case move, remove }
    private func selectGoal(_ id: UUID?) {
        pendingLink = nil
        guard let id, let goal = store.goals.first(where: { $0.id == id }) else { form.task.goalID = nil; return }
        if let subject = goal.subjectID {
            if let current = form.task.subjectID, current != subject { pendingLink = .goal(id); return }
            form.task.subjectID = subject
        }
        form.task.goalID = id
    }
    private func selectSubject(_ id: UUID?) {
        pendingLink = nil
        if let goal = store.goals.first(where: { $0.id == form.task.goalID }), let owner = goal.subjectID, owner != id {
            pendingLink = .subject(id); return
        }
        form.task.subjectID = id
    }
    private func appendStep() {
        let title = form.newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { form.task.steps.append(ChecklistItem(title: title)); form.newStep = "" }
    }
    private func appendLink() throws {
        guard !form.linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let r = try StudyTime.resource(title: form.linkTitle, url: form.linkURL)
        if !form.task.resources.contains(where: { StudyTime.resourceKey($0.url) == StudyTime.resourceKey(r.url) }) { form.task.resources.append(r) }
        form.linkTitle = ""; form.linkURL = ""
    }
    private func save(resolve: ConflictResolution? = nil) {
        guard !saving else { return }
        conflictCount = 0
        do { try appendLink() } catch { message = error.localizedDescription; return }
        appendStep()
        form.task.title = form.task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        form.task.deadline = form.hasDue ? (form.task.deadline ?? Date()) : nil
        if scheduledBlocks.isEmpty { form.task.scheduledDay = form.hasDay ? Calendar.current.startOfDay(for: form.task.scheduledDay ?? Date()) : nil }
        let snapshot = original.map { form.merged(over: $0.snapshot).task } ?? form.task
        let goal = store.goals.first { $0.id == snapshot.goalID }
        if let owner = goal?.subjectID, owner != snapshot.subjectID { message = "This goal belongs to a different subject. Use its subject below or choose another goal."; return }
        let deadlines = [snapshot.deadline.map { snapshot.deadlineDateOnly ? StudyTime.endOfDay($0) : $0 }, goal?.dueAt.map { goal!.isDateOnly ? StudyTime.endOfDay($0) : $0 }].compactMap { $0 }
        let due = deadlines.min()
        let conflicts = due.map { due in scheduledBlocks.filter { ($0.startAt?.addingTimeInterval(Double($0.durationMinutes * 60)) ?? StudyTime.endOfDay($0.day)) > due } } ?? []
        if !conflicts.isEmpty && resolve == nil {
            conflictCount = conflicts.count
            message = conflicts.count == 1 ? "A confirmed block ends after this deadline." : "\(conflicts.count) confirmed blocks end after this deadline."; return
        }
        saving = true
        if store.commit({
            if let due, !conflicts.isEmpty { try store.resolveDeadlineConflicts(conflicts, due: due, move: resolve == .move) }
            if let t = original {
                t.title = snapshot.title; t.subjectID = snapshot.subjectID; t.goalID = snapshot.goalID; t.notes = snapshot.notes
                t.estimatedMinutes = snapshot.estimatedMinutes; t.priority = snapshot.priority; t.deadline = snapshot.deadline
                t.deadlineDateOnly = snapshot.deadlineDateOnly; t.scheduledDay = snapshot.scheduledDay; t.steps = snapshot.steps; t.resources = snapshot.resources
            } else {
                store.context.insert(snapshot.model())
                if let goal = store.goals.first(where: { $0.id == snapshot.goalID }) { goal.completedAt = nil; goal.isArchived = false }
            }
        }) {
            if !conflicts.isEmpty { store.showToast(resolve == .move ? "Saved · \(conflicts.count == 1 ? "block" : "blocks") moved before the deadline" : "Saved · \(conflicts.count == 1 ? "block" : "blocks") removed") }
            finished = true; store.drafts.consume(key); dismiss()
        } else {
            saving = false
            if let error = store.error, resolve == .move { store.error = nil; message = error.replacingOccurrences(of: "Changes could not be saved. Your last saved data is preserved. ", with: ""); conflictCount = conflicts.count }
        }
    }
}

struct SubjectFormDraft: Codable, Equatable { var name = ""; var symbol = "book.closed" }
struct SubjectEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var subject: Subject?
    var onSaved: ((Subject) -> Void)?
    private let initial: SubjectFormDraft
    @State private var form: SubjectFormDraft
    @State private var finished = false
    init(subject: Subject? = nil, onSaved: ((Subject) -> Void)? = nil) {
        self.subject = subject; self.onSaved = onSaved
        initial = SubjectFormDraft(name: subject?.name ?? "", symbol: subject?.symbol ?? "book.closed"); _form = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject name", text: $form.name).accessibilityIdentifier("subjectName")
                Picker("Symbol", selection: $form.symbol) { ForEach(["book.closed", "cpu", "function", "chevron.left.forwardslash.chevron.right", "globe", "camera", "pencil"], id: \.self) { Label($0, systemImage: $0).tag($0) } }
            }.navigationTitle(subject == nil ? "New subject" : "Edit subject").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let s = subject ?? Subject()
                            if store.commit({ s.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines); s.symbol = form.symbol; if subject == nil { store.context.insert(s) } }) {
                                finished = true; store.drafts.consume(key); onSaved?(s); dismiss()
                            }
                        }.disabled(form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveSubject")
                    }
                }.modifier(PersistedForm(value: $form, key: key, initial: initial, finished: finished))
        }
    }
    private var key: String { subject.map { "subject:\($0.id)" } ?? "subject:new" }
}

struct GoalEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var goal: StudyGoal?
    var onSaved: ((StudyGoal) -> Void)?
    private let initial: GoalFormDraft
    @State private var form: GoalFormDraft
    @State private var finished = false
    @State private var addingSubject = false
    @State private var closingGoal = false
    init(goal: StudyGoal? = nil, initialSubjectID: UUID? = nil, onSaved: ((StudyGoal) -> Void)? = nil) {
        self.goal = goal; self.onSaved = onSaved
        let f = GoalDefinition(goal: goal, subjectID: initialSubjectID)
        initial = GoalFormDraft(base:f,value:f); _form = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Goal title", text: $form.value.title).accessibilityIdentifier("goalTitle")
                    StudyRecordPicker(title: "Subject", emptyTitle: "Independent study", selection: form.value.subjectID,
                                    options: store.subjects.filter { !$0.isArchived || $0.id == form.value.subjectID }.map { StudyRecordOption(id: $0.id, title: $0.name) },
                                    onSelect: { form.value.subjectID = $0 })
                    Button("Add subject", systemImage: "plus") { addingSubject = true }
                    TextField("Details", text: $form.value.details, axis: .vertical)
                    Picker("Priority", selection: $form.value.priority) { Text("Low").tag(1); Text("Normal").tag(2); Text("High").tag(3) }
                    Stepper("Target: \(form.value.target) min", value: $form.value.target, in: 0...100000, step: 30)
                    Toggle("Completed", isOn: $form.value.complete)
                }
                Section {
                    Toggle("Deadline", isOn: $form.value.hasDue)
                    if form.value.hasDue { Toggle("Date only", isOn: $form.value.dateOnly); DatePicker("Due", selection: $form.value.due, displayedComponents: form.value.dateOnly ? [.date] : [.date, .hourAndMinute]) }
                } footer: { Text("Date-only deadlines mean the end of that local day. Completing a goal keeps its study history. Changing its subject updates unfinished linked work; past session history is kept.") }
            }.navigationTitle(goal == nil ? "New goal" : "Edit goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if form.value.complete && goal?.completedAt == nil && !unfinished.isEmpty { closingGoal = true } else { save() } }.disabled(form.value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveGoal") }
                }.modifier(PersistedForm(value: $form, key: key, initial: initial, finished: finished, transform: { old in goal.map { old.merged(over: GoalDefinition(goal:$0)) } ?? old }))
        }.sheet(isPresented: $addingSubject) { SubjectEditor { form.value.subjectID = $0.id } }
            .confirmationDialog("Complete this goal with \(unfinished.count) unfinished tasks?", isPresented: $closingGoal, titleVisibility: .visible) {
                Button("Complete & archive remaining work") { save(remaining: .archive) }
                Button("Complete & keep tasks independently") { save(remaining: .detach) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Related habits will pause. Archiving saves any open focus time and keeps its history. Keeping tasks removes their link to this completed goal.") }
    }
    private var key: String { goal.map { "goal:\($0.id)" } ?? "goal:new" }
    private var unfinished: [StudyTask] {
        guard let goal else { return [] }
        return store.tasks.filter { $0.goalID == goal.id && $0.completedAt == nil && !$0.isArchived && $0.skippedAt == nil }
    }
    private func save(remaining: RemainingGoalWork = .keep) {
        if let g = store.updateGoal(goal, definition: form.value, remaining: remaining) {
            finished = true; store.drafts.consume(key); onSaved?(g); dismiss()
        }
    }
}

struct HabitEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var rule: RecurrenceRule?
    private let initial: HabitFormDraft
    @State private var form: HabitFormDraft
    @State private var finished = false
    @State private var pauseOptions = false
    init(rule: RecurrenceRule? = nil) {
        self.rule = rule
        let f = HabitDefinition(rule:rule)
        initial = HabitFormDraft(base:f,value:f); _form = State(initialValue:initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Habit title", text: $form.value.title)
                StudyRecordPicker(title: "Subject", emptyTitle: "Independent study", selection: form.value.subjectID,
                                options: store.subjects.filter { !$0.isArchived || $0.id == form.value.subjectID }.map { StudyRecordOption(id: $0.id, title: $0.name) },
                                onSelect: { form.value.subjectID = $0 })
                Stepper("Duration: \(form.value.minutes) min", value: $form.value.minutes, in: 15...240, step: 15)
                Section("Days each week") { WeekdayPicker(selected: $form.value.weekdays) }
                DatePicker("Start", selection: $form.value.start, displayedComponents: .date)
                Toggle("End date", isOn: $form.value.hasEnd)
                if form.value.hasEnd { DatePicker("End", selection: $form.value.end, in: form.value.start..., displayedComponents: .date) }
                Toggle("Enabled", isOn: $form.value.enabled)
                Text("Missed, unplanned occurrences stay in history without becoming catch-up debt. Explicit future plans are kept unless you choose to remove them when pausing.").font(.footnote).foregroundStyle(Water.secondary)
            }.navigationTitle(rule == nil ? "New habit" : "Edit habit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if rule?.isEnabled == true && !form.value.enabled && !futureBlocks.isEmpty { pauseOptions = true } else { save(removeFuture: false) }
                    }.disabled(form.value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.value.weekdays.isEmpty) }
                }.modifier(PersistedForm(value: $form, key: key, initial: initial, finished: finished, transform: { old in rule.map { old.merged(over: HabitDefinition(rule:$0)) } ?? old }))
        }.confirmationDialog("Pause this habit", isPresented: $pauseOptions, titleVisibility: .visible) {
            Button("Pause & keep confirmed blocks") { save(removeFuture: false) }
            Button("Pause & remove \(futureBlocks.count) future blocks") { save(removeFuture: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removing future blocks includes locked blocks. Any open session for this habit is saved first; past study records are kept.") }
    }
    private var key: String { rule.map { "habit:\($0.id)" } ?? "habit:new" }
    private var futureBlocks: [StudyPlanBlock] {
        guard let rule else { return [] }
        let ids = Set(store.tasks.filter { $0.recurrenceID == rule.id && $0.completedAt == nil }.map(\.id))
        return store.blocks.filter { ids.contains($0.taskID) && $0.status == "confirmed" && $0.day >= Calendar.current.startOfDay(for: store.clock.now) }
    }
    private func save(removeFuture: Bool) {
        let before = StudyUndo.capture(store)
        if store.updateHabit(rule, definition: form.value, removeFuture: removeFuture) {
            finished = true; store.drafts.consume(key); store.expandRecurrences()
            store.showToast(form.value.enabled ? "Habit saved" : "Habit paused", undo: !form.value.enabled && rule != nil ? before : nil); dismiss()
        }
    }
}
struct WeekdayPicker: View {
    @Binding var selected: Set<Int>
    var body: some View {
        ForEach(1...7, id: \.self) { day in
            Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { selected.contains(day) }, set: { if $0 { selected.insert(day) } else { selected.remove(day) } }))
        }
    }
}

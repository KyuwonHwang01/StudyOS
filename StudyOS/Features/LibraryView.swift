import SwiftUI

struct LibraryView: View {
    @Environment(StudyStore.self) private var store
    @State private var subject: Subject?
    @State private var goal: StudyGoal?
    @State private var rule: RecurrenceRule?
    @State private var adding: String?
    @State private var archived = false
    @State private var search = ""
    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }
    var body: some View {
        List {
            Toggle("Show archived records", isOn: $archived)
            Section("Subjects") {
                ForEach(store.subjects.filter { (archived || !$0.isArchived) && matches($0.name) }) { item in
                    Button { subject = item } label: {
                        HStack { Label(item.name, systemImage: item.symbol); Spacer(); if item.isSample { Text("Sample").font(.caption) }; if item.isArchived { Text("Archived").font(.caption) } }
                    }.swipeActions {
                        Button(item.isArchived ? "Restore" : "Archive") {
                            if item.isArchived { store.commit { item.isArchived = false } }
                            else { store.archiveRequest = ArchiveRequest(kind: .subject, recordID: item.id) }
                        }.tint(Water.accent)
                    }
                }
                Button("Add subject", systemImage: "plus") { adding = "subject" }
            }
            Section("Goals") {
                ForEach(store.goals.filter { (archived || !$0.isArchived) && matches($0.title) }) { item in
                    NavigationLink { GoalDetailView(goal: item) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title); Text(store.subjectName(item.subjectID)).font(.caption).foregroundStyle(Water.secondary)
                            if item.completedAt != nil { Text("Completed").font(.caption) }
                            if item.isArchived { Text("Archived").font(.caption) }
                        }
                    }.swipeActions {
                        Button(item.isArchived ? "Restore" : "Archive") {
                            if item.isArchived { store.commit { item.isArchived = false } }
                            else { store.archiveRequest = ArchiveRequest(kind: .goal, recordID: item.id) }
                        }.tint(Water.accent)
                    }.contextMenu { Button("Edit goal") { goal = item } }
                }
                Button("Add goal", systemImage: "plus") { adding = "goal" }
            }
            Section("Recurring habits") {
                ForEach(store.rules.filter { matches($0.title) }) { item in
                    Button { rule = item } label: {
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text("\(item.weekdays.count) days/week · \(item.duration) min · \(item.isEnabled ? "Enabled" : "Paused")").font(.caption).foregroundStyle(Water.secondary)
                        }
                    }
                }
                Button("Add habit", systemImage: "plus") { adding = "habit" }
            }
            let all = store.tasks.filter { (archived || !$0.isArchived) && matches($0.title) }
            Section("Pending tasks") {
                ForEach(all.filter { $0.completedAt == nil && $0.skippedAt == nil }) { taskLink($0) }
                Button("Add task", systemImage: "plus") { adding = "task" }
            }
            let completed = all.filter { $0.completedAt != nil }
            if !completed.isEmpty {
                Section { DisclosureGroup("Completed · \(completed.count)") { ForEach(completed) { taskLink($0) } } }
            }
            let skipped = all.filter { $0.skippedAt != nil && $0.completedAt == nil }
            if !skipped.isEmpty {
                Section { DisclosureGroup("Skipped / paused habits · \(skipped.count)") { ForEach(skipped) { t in Text(t.title).foregroundStyle(Water.secondary) } } }
            }
            Section { Text("Archive directly from a task or swipe here. Past study records are kept. Restoring a parent does not silently restart its paused habits; enable the habit when you are ready.").font(.footnote).foregroundStyle(Water.secondary) }
        }.navigationTitle("Your studies").searchable(text: $search, prompt: "Find a subject, goal, task or habit")
            .sheet(item: $subject) { SubjectEditor(subject: $0) }.sheet(item: $goal) { GoalEditor(goal: $0) }.sheet(item: $rule) { HabitEditor(rule: $0) }
            .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
                switch adding { case "subject": SubjectEditor(); case "goal": GoalEditor(); case "habit": HabitEditor(); default: TaskEditor() }
            }
    }
    private func taskLink(_ item: StudyTask) -> some View {
        NavigationLink { TaskDetailView(task: item) } label: {
            VStack(alignment: .leading) {
                Text(item.title).strikethrough(item.completedAt != nil)
                Text(item.isArchived ? "Archived" : "\(item.estimatedMinutes) min · \(store.subjectName(item.subjectID))").font(.caption).foregroundStyle(Water.secondary)
            }
        }.swipeActions {
            Button(item.isArchived ? "Restore" : "Archive") {
                if item.isArchived { store.restoreTask(item) } else { store.requestArchive(item) }
            }.tint(Water.accent)
        }
    }
}

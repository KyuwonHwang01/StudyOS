import SwiftUI

struct TaskScheduleSheet: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var task: StudyTask
    @State private var selected: StudyPlanBlock?
    @State private var adding = false
    private var future: [StudyPlanBlock] {
        store.blocks.filter { $0.taskID == task.id && $0.status == "confirmed" && $0.day >= Calendar.current.startOfDay(for: store.clock.now) }
            .sorted { ($0.startAt ?? $0.day) < ($1.startAt ?? $1.day) }
    }
    var body: some View {
        if adding {
            BlockEditor(taskID:task.id).id("additional")
        } else if future.count <= 1 {
            BlockEditor(block: future.first, taskID: task.id, initialDay: task.scheduledDay ?? store.clock.now, onAddAnother: future.isEmpty ? nil : { adding = true }).id(future.first?.id ?? task.id)
        } else {
            NavigationStack {
                List {
                    Section("Choose the block to move") {
                        ForEach(future) { b in
                            Button { selected = b } label: {
                                VStack(alignment: .leading) {
                                    Text(b.day.formatted(date: .abbreviated, time: .omitted))
                                    Text("\(b.startAt?.formatted(date: .omitted, time: .shortened) ?? "Flexible") · \(b.durationMinutes) min\(b.isLocked ? " · Locked" : "")").font(.caption).foregroundStyle(Water.secondary)
                                }
                            }
                        }
                    }
                    Section { Button("Add another block", systemImage: "plus") { adding = true } }
                }.onChange(of:store.navigationEpoch) { _, _ in dismiss() }.navigationTitle("Study blocks").navigationBarTitleDisplayMode(.inline)
                    .sheet(item: $selected) { BlockEditor(block: $0) }
            }
        }
    }
}

import SwiftUI

struct GoalDetailView: View {
    @Environment(StudyStore.self) private var store
    var goal: StudyGoal
    @State private var editing = false
    @State private var adding = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GoalProgressCard(goal: goal, showOpenButton: false)
                if !goal.details.isEmpty { Text(goal.details).foregroundStyle(Water.secondary) }
                let linked = store.tasks.filter { $0.goalID == goal.id && !$0.isArchived && $0.skippedAt == nil }
                ForEach(linked.filter { $0.completedAt == nil }) { TaskRow(task: $0) }
                let done = linked.filter { $0.completedAt != nil }
                if !done.isEmpty { DisclosureGroup("Completed · \(done.count)") { ForEach(done) { TaskRow(task: $0) } } }
                Button(goal.isArchived ? "Restore goal & add task" : goal.completedAt == nil ? "Add task to this goal" : "Reopen goal & add task", systemImage: "plus") { adding = true }.buttonStyle(FlowButton()).accessibilityIdentifier("addGoalTask")
                if goal.isArchived {
                    Button("Restore goal", systemImage:"arrow.uturn.backward") { store.commit { goal.isArchived = false } }.frame(minHeight:44)
                } else { Button("Archive goal", systemImage: "archivebox") { store.archiveRequest = ArchiveRequest(kind: .goal, recordID: goal.id) }.frame(minHeight: 44) }
            }.padding(20)
        }.waterPage().navigationTitle("Goal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button { adding = true } label: { Image(systemName:"plus").frame(width:44,height:44) }.accessibilityLabel("Add task to goal") }
                ToolbarItem(placement:.topBarTrailing) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { GoalEditor(goal: goal) }
            .sheet(isPresented: $adding) { TaskEditor(goal: goal) }
    }
}

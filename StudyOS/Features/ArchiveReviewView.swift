import SwiftUI

struct ArchiveReviewView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var request: ArchiveRequest
    @State private var includeRelated = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title).font(.title2.weight(.medium))
                    Text("Study sessions and first-completion history are kept. You can undo this action immediately or restore records later.").foregroundStyle(Water.secondary)
                }
                let members = store.archiveMembers(request)
                if request.kind != .task {
                    Section {
                        Toggle("Include related unfinished work", isOn: $includeRelated)
                        Text("\(members.count) unfinished tasks. Related habits will be paused so they do not create more tasks.").font(.subheadline)
                    }
                }
                let ids = Set(members.map(\.id))
                if let active = store.activeSession, ids.contains(active.taskID), includeRelated || request.kind == .task {
                    Section { Label("Your open session's active time and notes will be saved before archiving.", systemImage: "timer").foregroundStyle(Water.accent) }
                }
                Section {
                    Button("Archive & keep history") { store.applyArchive(request, includeRelated: includeRelated); if store.error == nil { dismiss() } }
                        .buttonStyle(FlowButton()).accessibilityIdentifier("confirmArchive")
                }
            }.navigationTitle("Archive").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private var title: String {
        switch request.kind {
        case .task: store.task(request.recordID)?.title ?? "Task"
        case .subject: store.subjects.first { $0.id == request.recordID }?.name ?? "Subject"
        case .goal: store.goals.first { $0.id == request.recordID }?.title ?? "Goal"
        }
    }
}

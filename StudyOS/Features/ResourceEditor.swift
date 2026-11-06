import SwiftUI

struct ResourceDraft: Codable, Equatable { var title = ""; var url = ""; var editingID: UUID? }
struct ResourceEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var task: StudyTask
    @State private var form = ResourceDraft()
    @State private var finished = false
    @State private var message: String?
    @FocusState private var urlFocused: Bool?
    private func saveLink() {
        guard !form.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            var r = try StudyTime.resource(title: form.title, url: form.url)
            if let editing = form.editingID, task.resources.contains(where: { $0.id != editing && StudyTime.resourceKey($0.url) == StudyTime.resourceKey(r.url) }) {
                message = "This link already exists. Choose a different URL to edit this resource."; return
            }
            if store.commit({
                if let editing = form.editingID, let i = task.resources.firstIndex(where: { $0.id == editing }) { r.id = editing; task.resources[i] = r }
                else if !task.resources.contains(where: { StudyTime.resourceKey($0.url) == StudyTime.resourceKey(r.url) }) { task.resources.append(r) }
            }) { finished = true; dismiss() }
        } catch { message = error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Saved resources") {
                    ForEach(task.resources) { r in
                        Button { form = ResourceDraft(title: r.title, url: r.url, editingID: r.id) } label: {
                            VStack(alignment: .leading) { Text(r.title); Text(r.url).font(.caption).foregroundStyle(Water.secondary) }
                        }.accessibilityLabel("Edit \(r.title)")
                    }.onDelete { offsets in store.commit { task.resources.remove(atOffsets: offsets) } }
                    if task.resources.isEmpty { Text("Add a lesson, problem, or reading link below.").foregroundStyle(Water.secondary) }
                }
                Section("Add link") {
                    TextField("Title · optional", text: $form.title).focused($urlFocused, equals: false).submitLabel(.next).onSubmit { urlFocused = true }
                    TextField("https://…", text: $form.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("resourceURL")
                        .focused($urlFocused, equals: true).submitLabel(.done).onSubmit { saveLink() }
                    if let message { Text(message).font(.caption).foregroundStyle(Water.warning) }
                    Button(form.editingID == nil ? "Save link" : "Save changes") { saveLink() }.disabled(form.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveResource")
                }
            }.navigationTitle("Resources").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .modifier(PersistedForm(value: $form, key: "resource:\(task.id)", initial: ResourceDraft(), finished: finished))
        }
    }
}

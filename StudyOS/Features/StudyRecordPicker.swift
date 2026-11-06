import SwiftUI

struct StudyRecordOption: Identifiable {
    var id: UUID
    var title: String
}

/// A searchable choice list selects and returns in one tap, including at large text sizes.
struct StudyRecordPicker: View {
    var title: String
    var emptyTitle: String
    var selection: UUID?
    var options: [StudyRecordOption]
    var onSelect: (UUID?) -> Void
    @State private var choosing = false
    @State private var query = ""
    @State private var chosenID: UUID?
    @State private var didChoose = false
    private var selectedTitle: String { options.first { $0.id == selection }?.title ?? emptyTitle }
    private var filtered: [StudyRecordOption] { query.isEmpty ? options : options.filter { $0.title.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        Button { query = ""; didChoose = false; choosing = true } label: {
            HStack {
                Text(title).foregroundStyle(Water.ink)
                Spacer(minLength: 12)
                Text(selectedTitle).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(selectedTitle)")
            .sheet(isPresented: $choosing, onDismiss: {
                if didChoose { didChoose = false; onSelect(chosenID) }
            }) {
                NavigationStack {
                    List {
                        Button { choose(nil) } label: { choiceLabel(emptyTitle, selected: selection == nil) }
                        ForEach(filtered) { option in
                            Button { choose(option.id) } label: { choiceLabel(option.title, selected: selection == option.id) }
                        }
                        if filtered.isEmpty && !query.isEmpty { Text("No matches").foregroundStyle(Water.secondary) }
                    }.searchable(text: $query, prompt: "Search \(title.lowercased())")
                        .navigationTitle("Choose \(title.lowercased())").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { choosing = false } } }
                }.tint(Water.accent).presentationDetents([.medium, .large])
            }
    }
    private func choiceLabel(_ text: String, selected: Bool) -> some View {
        HStack { Text(text); Spacer(); if selected { Image(systemName: "checkmark").accessibilityLabel("Selected") } }
            .frame(minHeight: 44).contentShape(Rectangle())
    }
    private func choose(_ id: UUID?) { chosenID = id; didChoose = true; choosing = false }
}

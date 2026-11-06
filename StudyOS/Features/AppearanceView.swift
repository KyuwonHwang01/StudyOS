import SwiftUI

enum StudyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Follow system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct AppearanceView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            ForEach(StudyAppearance.allCases) { choice in
                Button {
                    if store.commit({ store.preferences.appearance = choice.rawValue }) { dismiss() }
                } label: {
                    HStack {
                        Text(choice.title).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if store.preferences.appearance == choice.rawValue { Image(systemName: "checkmark").foregroundStyle(Water.accent) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(choice.title)
                    .accessibilityValue(store.preferences.appearance == choice.rawValue ? "Selected" : "")
            }
        }.navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct PersistedForm<Value: Codable & Equatable>: ViewModifier {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var value: Value
    var key: String
    var initial: Value
    var finished: Bool
    var transform: (Value) -> Value = { $0 }
    @State private var loaded = false
    @State private var lease = UUID()
    @State private var restored = false

    func body(content: Content) -> some View {
        content.modifier(FormKeyboard()).safeAreaInset(edge: .top, spacing: 0) {
            if restored && !finished {
                HStack {
                    Label("Draft restored", systemImage: "arrow.counterclockwise").font(.caption)
                    Spacer()
                    Button("Start fresh") { value = initial; store.drafts.remove(key); restored = false }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }.padding(.horizontal, 20).background(Water.soft)
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            store.drafts.begin(key, lease: lease)
            if let old = store.drafts.value(Value.self, for: key) { value = transform(old); restored = true }
        }
        .onChange(of: store.navigationEpoch) { _, _ in store.drafts.stage(value,for:key,lease:lease); store.drafts.flush(); dismiss() }
        .onChange(of: value) { _, new in
            guard loaded, !finished else { return }
            if new == initial { store.drafts.remove(key) } else { store.drafts.stage(new, for: key, lease: lease) }
        }
        .onChange(of: finished) { _, done in if done { store.drafts.consume(key) } }
        .onDisappear {
            guard !finished else { store.drafts.consume(key); return }
            if value != initial { store.drafts.stage(value, for: key, lease: lease) }
            store.drafts.flush()
        }
    }
}

struct FormKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("dismissKeyboard")
                }
            }
    }
}

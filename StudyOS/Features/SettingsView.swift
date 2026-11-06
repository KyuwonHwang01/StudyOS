import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(StudyStore.self) private var store
    @State private var exporting = false
    @State private var importing = false
    @State private var reading = false
    @State private var document = BackupDocument()
    @State private var preview: StudyBackup?
    @State private var merging = false
    var body: some View {
        Form {
            Section("Make it yours") {
                NavigationLink { AppearanceView() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Appearance")
                        Text(StudyAppearance(rawValue: store.preferences.appearance)?.title ?? "Follow system")
                            .font(.subheadline).foregroundStyle(Water.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityIdentifier("appearanceSettings")
                NavigationLink { AvailabilityView() } label: { Label("Study availability", systemImage: "clock") }
                NavigationLink { NotificationPreferencesView() } label: { Label("Notifications", systemImage: "bell") }
            }
            Section("Your studies") { NavigationLink { LibraryView() } label: { Label("Subjects, goals, tasks & habits", systemImage: "books.vertical") } }
            Section {
                Button("Export JSON backup", systemImage: "square.and.arrow.up") {
                    do { document = BackupDocument(data: try StudyBackup(store: store).encoded()); exporting = true }
                    catch { store.error = error.localizedDescription }
                }
                Button("Import JSON backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(reading)
                if reading { ProgressView("Validating backup…") }
            } header: { Text("Keep a copy") } footer: { Text("Backups contain your study notes and history. Import adds new IDs and keeps existing records and device settings. Export to Files regularly; uninstalling the app can erase local data.") }
            Section("Private by design") {
                Label("Stored only on this device", systemImage: "iphone")
                Label("No login. No analytics tracking.", systemImage: "hand.raised")
                Text("StudyOS works offline. Resource links open externally. There is no automatic cloud sync.").font(.subheadline).foregroundStyle(Water.secondary)
            }
            Section { Text("StudyOS 1.0\nOne drop at a time.").font(.footnote).foregroundStyle(Water.secondary) }
        }.navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "StudyOS-\(StudyTime.dayKey(Date()))") { result in
                if case let .failure(error) = result { store.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .failure(let error): store.error = error.localizedDescription
                case .success(let url):
                    reading = true
                    Task {
                        do {
                            let decoded = try await Task.detached(priority: .userInitiated) {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                                guard (values.fileSize ?? 0) <= 20_000_000 else { throw StudyError.invalid("Backup exceeds 20 MB.") }
                                return try StudyBackup.decode(Data(contentsOf: url))
                            }.value
                            preview = decoded
                        } catch { store.error = "Backup was not imported. \(error.localizedDescription)" }
                        reading = false
                    }
                }
            }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                NavigationStack {
                    Form {
                        if let backup = preview {
                            Section("Import preview") {
                                Text(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))
                                Text(backup.summary)
                                Text("Schema \(backup.schemaVersion) · \(backup.recordCount) records").font(.caption)
                            }
                            Section {
                                Button("Import new records") {
                                    guard !merging else { return }; merging = true
                                    if backup.merge(into: store) { preview = nil; store.showToast("Backup imported") }
                                    merging = false
                                }.disabled(merging)
                            } footer: { Text("A failed import rolls back the complete transaction. Existing IDs always win; importing the same backup again does not duplicate records. Notification consent and this device's preferences are retained.") }
                        }
                    }.navigationTitle("Review backup").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { preview = nil } } }
                }
            }
    }
}

struct AvailabilityFormDraft: Codable, Equatable {
    var availability = Array(repeating: 180, count: 7); var maximum = 240
    var start = Date(); var end = Date()
}
struct AvailabilityView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var form = AvailabilityFormDraft()
    @State private var baseline = AvailabilityFormDraft()
    @State private var finished = false
    @State private var loaded = false
    private func minute(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
    var body: some View {
        Form {
            Section("Weekly availability") {
                ForEach(0..<7, id: \.self) { i in
                    Stepper("\(Calendar.current.weekdaySymbols[i]): \(form.availability[i]) min", value: Binding(get: { form.availability[i] }, set: {
                        form.availability[i] = $0; form.maximum = max(form.maximum, form.availability.max() ?? 0)
                    }), in: 0...1440, step: 15).accessibilityIdentifier("weekdayAvailability-\(i)")
                }
            }
            Section("Study window") {
                Stepper("Daily maximum: \(form.maximum) min", value: Binding(get: { form.maximum }, set: { form.maximum = max($0, form.availability.max() ?? 0) }), in: (form.availability.max() ?? 0)...1440, step: 15).accessibilityIdentifier("dailyMaximum")
                DatePicker("From", selection: $form.start, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $form.end, displayedComponents: .hourAndMinute)
                if minute(form.start) >= minute(form.end) { Text("Choose an end time after the start on the same day.").foregroundStyle(Water.warning) }
                Text("The maximum rises to cover your highest available day. Zero minutes means a rest day. Existing confirmed blocks are kept.").font(.footnote).foregroundStyle(Water.secondary)
            }
        }.navigationTitle("Study availability").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded else { return }; loaded = true
                if store.drafts.value(AvailabilityFormDraft.self, for: "availability") != nil { return }
                form.availability = store.preferences.availability; form.maximum = max(store.preferences.maxDailyMinutes, form.availability.max() ?? 0)
                form.start = StudyTime.atMinute(store.preferences.windowStart, on: Date()); form.end = StudyTime.atMinute(store.preferences.windowEnd, on: Date()); baseline = form
            }
            .toolbar {
                Button("Save") {
                    if store.commit({
                        store.preferences.availability = form.availability; store.preferences.dailyMinutes = form.availability.max() ?? 0
                        store.preferences.maxDailyMinutes = max(form.maximum, form.availability.max() ?? 0)
                        store.preferences.windowStart = minute(form.start); store.preferences.windowEnd = minute(form.end)
                    }) { finished = true; store.drafts.consume("availability"); dismiss() }
                }.disabled(minute(form.start) >= minute(form.end))
            }.modifier(PersistedForm(value: $form, key: "availability", initial: baseline, finished: finished))
    }
}

struct NotificationPreferencesView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scene
    @State private var authorization = "Checking…"
    @State private var requesting = false
    var body: some View {
        Form {
            Section {
                Toggle("Enable reminders", isOn: Binding(get: { store.preferences.notificationsEnabled }, set: { enabled in
                    if !enabled { store.commit { store.preferences.notificationsEnabled = false } }
                    else {
                        requesting = true
                        Task {
                            do {
                                let granted = try await store.notificationService.request()
                                store.commit { store.preferences.notificationsEnabled = granted }
                            } catch { store.error = error.localizedDescription }
                            await updateStatus(); requesting = false
                        }
                    }
                })).disabled(requesting)
                Text("Permission: \(authorization)").font(.subheadline)
                Button("Open iOS notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            } header: { Text("Gentle, on your terms") } footer: { Text("Allow StudyOS to remind you about approved timed blocks, upcoming goals, and an evening reflection. Denying permission leaves the rest of the app fully usable.") }
            Section("Reminders") {
                Toggle("Approved study start", isOn: bool(\.startReminders))
                Toggle("Deadline · 3 days before", isOn: bool(\.deadlineThreeDays))
                Toggle("Deadline · 1 day before", isOn: bool(\.deadlineOneDay))
                Toggle("Evening reflection", isOn: bool(\.eveningReview))
                DatePicker("Reflection time", selection: minute(\.reviewMinute), displayedComponents: .hourAndMinute)
            }
            Section {
                DatePicker("Quiet hours start", selection: minute(\.quietStart), displayedComponents: .hourAndMinute)
                DatePicker("Quiet hours end", selection: minute(\.quietEnd), displayedComponents: .hourAndMinute)
            } header: { Text("Quiet hours") } footer: { Text("Reminders falling inside quiet hours are skipped. Equal times turn quiet hours off. Date-only deadline reminders use 9 AM. iOS controls delivery; it is not guaranteed. The app refreshes up to 60 upcoming reminders whenever data changes or it becomes active.") }
        }.navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .task { await updateStatus() }
            .onChange(of: scene) { _, phase in if phase == .active { Task { await updateStatus(); store.refreshNotifications() } } }
    }
    private func bool(_ key: ReferenceWritableKeyPath<UserPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in store.commit { store.preferences[keyPath: key] = value } })
    }
    private func minute(_ key: ReferenceWritableKeyPath<UserPreferences, Int>) -> Binding<Date> {
        Binding(get: { StudyTime.atMinute(store.preferences[keyPath: key], on: Date()) }, set: { date in
            store.commit { store.preferences[keyPath: key] = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
        })
    }
    private func updateStatus() async {
        switch await store.notificationService.authorization() {
        case .authorized: authorization = "Allowed"
        case .denied: authorization = "Denied · change in iOS Settings"
        case .notDetermined: authorization = "Not requested"
        case .provisional: authorization = "Quiet delivery"
        case .ephemeral: authorization = "Temporary"
        @unknown default: authorization = "Unknown"
        }
    }
}

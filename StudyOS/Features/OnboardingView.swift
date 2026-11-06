import SwiftUI

struct OnboardingView: View {
    @Environment(StudyStore.self) private var store
    @State private var minutes = 180
    @State private var maximum = 240
    @State private var days = Set(1...7)
    @State private var window = 1
    @State private var subject = ""
    @State private var goal = ""
    @State private var templates: Set<String> = []
    @State private var samples = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "drop").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Water.accent)
                        Text("Every drop\nbecomes an ocean.").font(.largeTitle.weight(.medium))
                        Text("A calm place for your studies. Shape your week, focus on one thing, and see your effort accumulate.").foregroundStyle(Water.secondary)
                    }.padding(.vertical, 20)
                }.listRowBackground(Color.clear)
                Section("Make room for your flow") {
                    Stepper("Daily availability: \(minutes) min", value: Binding(get: { minutes }, set: {
                        minutes = $0
                        maximum = max(maximum, $0)
                    }), in: 0...720, step: 15).accessibilityIdentifier("dailyAvailability")
                    Stepper("Daily maximum: \(maximum) min", value: Binding(get: { maximum }, set: {
                        maximum = max($0, minutes)
                    }), in: minutes...720, step: 15)
                        .accessibilityIdentifier("dailyMaximum")
                    Picker("Preferred window", selection: $window) { Text("Morning · 7–12").tag(0); Text("Afternoon · 12–18").tag(1); Text("Evening · 17–22").tag(2) }
                    DisclosureGroup("Study days · \(days.count) selected") { WeekdayPicker(selected: $days) }
                }
                Section("Your first goal · optional") {
                    TextField("Subject", text: $subject)
                    TextField("A goal you want to work toward", text: $goal)
                }
                Section("Optional subject templates") {
                    ForEach(["ECE 2280", "ECE 2285", "ECE 4710", "CS 4400", "NeetCode", "English"], id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { templates.contains(name) }, set: { if $0 { templates.insert(name) } else { templates.remove(name) } }))
                    }
                    Toggle("Include editable sample goals & habits", isOn: $samples)
                    Text("Samples are labeled. No completed work or focus time is invented. Only future example deadlines are included. English daily, NeetCode Mon/Tue/Thu/Sat, and capstone Mon/Wed/Fri habits are created only when you opt in.").font(.footnote).foregroundStyle(Water.secondary)
                }
                Section {
                    Button("Begin your flow") { finish() }.buttonStyle(FlowButton()).listRowBackground(Color.clear).accessibilityIdentifier("beginFlow")
                    Text("Stored only on this device. No account, no tracking.").font(.caption).foregroundStyle(Water.secondary).frame(maxWidth: .infinity)
                }
            }.scrollContentBackground(.hidden).waterPage().navigationTitle("StudyOS").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func finish() {
        if store.commit({
            let p = store.preferences
            p.dailyMinutes = minutes; p.maxDailyMinutes = max(maximum, minutes)
            p.availability = (1...7).map { days.contains($0) ? minutes : 0 }
            p.windowStart = [420, 720, 1020][window]; p.windowEnd = [720, 1080, 1320][window]
            p.hasAcceptedSampleData = samples
            var names = templates
            if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names.insert(subject.trimmingCharacters(in: .whitespacesAndNewlines)) }
            var subjectIDs: [String: UUID] = [:]
            for name in names.sorted() {
                let item = Subject(name: name, isSample: samples && name != subject)
                store.context.insert(item); subjectIDs[name] = item.id
            }
            if !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.context.insert(StudyGoal(subjectID: subjectIDs[subject], title: goal))
            }
            if samples {
                for (name, title, dateString) in [("ECE 2280", "[Sample] MOSFET DC/AC exam", "2026-12-03"), ("ECE 2285", "[Sample] Final Project Proposal", "2026-11-24")] where names.contains(name) {
                    let parts = dateString.split(separator: "-").compactMap { Int($0) }
                    let due = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
                    if StudyTime.endOfDay(due) >= store.clock.now {
                        let g = StudyGoal(subjectID: subjectIDs[name], title: title, dueAt: due)
                        store.context.insert(g)
                        store.context.insert(StudyTask(subjectID: subjectIDs[name], goalID: g.id, title: name == "ECE 2280" ? "[Sample] Review operating regions" : "[Sample] Draft sensor / amplifier / output outline", estimatedMinutes: 60))
                    }
                }
                for (name, title, weekdays, duration) in [("English", "[Sample] Listening, shadowing & speaking", Array(1...7), 30), ("NeetCode", "[Sample] C++ problem practice", [2,3,5,7], 45), ("ECE 4710", "[Sample] SLAM calibration & tests", [2,4,6], 60)] where names.contains(name) {
                    store.context.insert(RecurrenceRule(subjectID: subjectIDs[name], title: title, weekdays: weekdays, duration: duration))
                }
            }
            p.onboardingCompleted = true
        }) { store.expandRecurrences() }
    }
}

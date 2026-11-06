import SwiftUI

struct FocusSessionView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var task: StudyTask
    var route: FocusRoute
    @State private var finishing = false
    @State private var resumeAfterBack = false
    @State private var canceling = false
    @State private var resources = false
    @State private var loaded = false
    @State private var requestedCompletionConsumed = false
    @State private var showingRecovery = false
    @State private var finishAfterRecovery = false
    @State private var recoveryError: String?

    var body: some View {
        Group {
            if let session = store.activeSession, session.taskID == task.id {
                if finishing {
                    FinishSessionView(session: session, task: task, requestedCompletion: route.finishRequested && !requestedCompletionConsumed,
                                      onBack: { requestedCompletionConsumed = true; if resumeAfterBack { store.resume(session) }; finishing = false },
                                      onSaved: { store.focusRoute = nil })
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if let gap = store.recoveredGap, gap.sessionID == session.id {
                                WaterCard {
                                    VStack(alignment: .leading, spacing: 12) {
                                        SectionHeading(title: "Time waiting for your review", subtitle: "\(StudyTime.duration(gap.seconds)) is not counted until you choose to add it.")
                                        if let recoveryError { Text(recoveryError).foregroundStyle(Water.warning).font(.subheadline) }
                                        Button("Review recovered time") { showingRecovery = true }.buttonStyle(FlowButton()).accessibilityIdentifier("reviewRecoveredTime")
                                    }
                                }
                            }
                            Text(store.subjectName(task.subjectID).uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Water.accent)
                            Text(task.title).font(.title.weight(.medium)).multilineTextAlignment(.center)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                VStack(spacing: 12) {
                                    Text(StudyTime.timer(store.elapsed(session))).font(.system(.largeTitle, design: .rounded, weight: .light)).monospacedDigit()
                                        .accessibilityLabel("Active focus time").accessibilityValue(StudyTime.duration(store.elapsed(session))).accessibilityIdentifier("focusTimer")
                                    Text("\(session.status.capitalized) · this session \(session.targetMinutes ?? task.estimatedMinutes) min").font(.subheadline).foregroundStyle(Water.secondary).accessibilityIdentifier("focusTarget")
                                    LiquidProgressBar(progress: min(1, store.elapsed(session) / Double(max(1, session.targetMinutes ?? task.estimatedMinutes) * 60)))
                                }.padding(.vertical, 24)
                            }
                            HStack(spacing: 12) {
                                Button(session.status == "running" ? "Pause" : "Resume", systemImage: session.status == "running" ? "pause.fill" : "play.fill") {
                                    if session.status == "running" { store.pause(session) } else { store.resume(session) }
                                }.buttonStyle(FlowButton()).disabled(store.recoveredGap?.sessionID == session.id).accessibilityIdentifier("pauseResume")
                                Button("Finish") {
                                    if store.recoveredGap?.sessionID == session.id { finishAfterRecovery = true; showingRecovery = true }
                                    else { beginFinishing(session) }
                                }
                                    .buttonStyle(FlowButton()).accessibilityIdentifier("finishFocus")
                            }
                            WaterCard {
                                @Bindable var session = session
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeading(title: "Quick notes", subtitle: "Saved automatically.")
                                    TextField("Capture a thought…", text: $session.sessionNote, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("quickNotes")
                                        .task(id: session.sessionNote) {
                                            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                                            store.persistEdits()
                                        }
                                }
                            }
                            WaterCard { ChecklistView(task: task) }
                            WaterCard { ResourceList(task: task); Button("Add or edit resources") { resources = true }.frame(minHeight: 44) }
                            if !task.notes.isEmpty { WaterCard { SectionHeading(title: "Task notes"); Text(task.notes).padding(.top, 8) } }
                            Button("Discard session", role: .destructive) { canceling = true }.frame(minHeight: 44)
                        }.padding(24)
                    }.modifier(FormKeyboard()).waterPage().navigationTitle("Focus").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { store.persistEdits(); store.focusRoute = nil }.accessibilityIdentifier("closeFocus") } }
                }
            } else { ContentUnavailableView("No active session", systemImage: "timer").onAppear { store.focusRoute = nil } }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let gap = store.recoveredGap, gap.sessionID == store.activeSession?.id {
                finishAfterRecovery = route.finishRequested; showingRecovery = true
            } else if route.finishRequested, let session = store.activeSession { beginFinishing(session) }
        }
        .onDisappear { store.persistEdits() }
        .sheet(isPresented: $resources) { ResourceEditor(task: task) }
        .alert("Add time from before the app closed?", isPresented: $showingRecovery, presenting: store.recoveredGap) { gap in
            Button("Add \(StudyTime.duration(gap.seconds))") { resolveRecovery(include: true) }.accessibilityIdentifier("addRecoveredTime")
            Button("Don't add", role: .cancel) { resolveRecovery(include: false) }
        } message: { gap in
            Text("Last saved: \(gap.start.formatted(date: .abbreviated, time: .shortened)). Reopened: \(gap.end.formatted(date: .abbreviated, time: .shortened)). Add this time only if you were studying.")
        }
        .onChange(of: store.recoveredGap) { _, gap in if gap == nil { showingRecovery = false } }
        .confirmationDialog("Discard this session? Its time will not count toward your Ocean.", isPresented: $canceling, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) { if let s = store.activeSession, store.discard(s) { store.focusRoute = nil } }
        }
    }
    private func beginFinishing(_ session: FocusSession) {
        resumeAfterBack = session.status == "running"
        if store.pause(session) { finishing = true }
    }
    private func resolveRecovery(include: Bool) {
        if store.resolveRecoveredGap(include: include) {
            recoveryError = nil
            if finishAfterRecovery, let session = store.activeSession { finishAfterRecovery = false; beginFinishing(session) }
        } else {
            recoveryError = store.error ?? "Your choice could not be saved. Review the time again to retry."
            store.error = nil
        }
    }
}
struct ChecklistView: View {
    @Environment(StudyStore.self) private var store
    var task: StudyTask
    @State private var newStep = ""
    @State private var renaming: ChecklistItem?
    @State private var renameText = ""
    @FocusState private var adding: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Learning steps")
            if task.steps.isEmpty { Text("Break the work into a few small steps.").font(.subheadline).foregroundStyle(Water.secondary) }
            ForEach(task.steps) { step in
                Button {
                    store.commit { if let i = task.steps.firstIndex(where: { $0.id == step.id }) { task.steps[i].isDone.toggle() } }
                } label: {
                    Label(step.title, systemImage: step.isDone ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityValue(step.isDone ? "Completed" : "Incomplete")
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { renameText = step.title; renaming = step }
                        Button("Delete", systemImage: "trash", role: .destructive) { store.commit { task.steps.removeAll { $0.id == step.id } } }
                    }
                    .accessibilityActions {
                        Button("Rename") { renameText = step.title; renaming = step }
                        Button("Delete") { store.commit { task.steps.removeAll { $0.id == step.id } } }
                    }
            }
            HStack {
                TextField("Add a learning step", text: $newStep).focused($adding).submitLabel(.next)
                    .onSubmit { add(); adding = true }  // keep the keyboard up for the next step
                Button { add() } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }.disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Add learning step")
            }
            if !task.steps.isEmpty { Text("Touch and hold a step to rename or delete it.").font(.caption2).foregroundStyle(Water.secondary) }
        }
        .alert("Rename step", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Step", text: $renameText)
            Button("Save") {
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renaming?.id, !title.isEmpty { store.commit { if let i = task.steps.firstIndex(where: { $0.id == id }) { task.steps[i].title = title } } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
    private func add() {
        let title = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if store.commit({ task.steps.append(ChecklistItem(title: title)) }) { newStep = "" }
    }
}
struct ResourceList: View {
    @Environment(\.openURL) private var openURL
    @Environment(StudyStore.self) private var store
    var task: StudyTask
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Resources")
            if task.resources.isEmpty { Text("Keep your lesson, problem, or reading links here.").font(.subheadline).foregroundStyle(Water.secondary) }
            ForEach(task.resources) { resource in
                Button {
                    guard let url = StudyTime.validURL(resource.url) else { store.error = "This resource URL is invalid."; return }
                    openURL(url) { accepted in if !accepted { store.error = "This link could not be opened." } }
                } label: { Label(resource.title, systemImage: "arrow.up.right.square").frame(minHeight: 44) }
            }
        }
    }
}

struct FinishPreferences: Codable, Equatable { var markComplete: Bool?; var createReview = false }
struct FinishSessionView: View {
    @Environment(StudyStore.self) private var store
    var session: FocusSession
    var task: StudyTask
    var requestedCompletion = false
    var onBack: () -> Void
    var onSaved: () -> Void
    @State private var rating = 0
    @State private var note = ""
    @State private var complete = false
    @State private var review = false
    @State private var saving = false
    @State private var initialized = false
    @State private var preferences = FinishPreferences()
    private var preferenceKey: String { "finish:\(session.id)" }
    private func savePreferences() {
        if preferences.markComplete != nil || preferences.createReview { store.drafts.stage(preferences,for:preferenceKey) }
        else { store.drafts.remove(preferenceKey) }
    }
    var body: some View {
        Form {
            Section {
                Text(StudyTime.duration(store.elapsed(session))).font(.largeTitle.monospacedDigit())
                Text("Active time · pauses excluded").font(.subheadline).foregroundStyle(Water.secondary)
                Text("\(task.steps.filter(\.isDone).count)/\(task.steps.count) learning steps completed")
            }
            Section {
                Toggle("Mark task complete", isOn: Binding(get:{complete},set:{complete=$0;preferences.markComplete=$0;savePreferences()})).accessibilityIdentifier("finishTaskComplete")
                if !task.steps.isEmpty && task.steps.allSatisfy(\.isDone) { Text("All your learning steps are checked. You can still keep the task open.").font(.caption).foregroundStyle(Water.secondary) }
                Picker("Understanding · optional", selection: $rating) {
                    Text("Not rated").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
                if (1...2).contains(rating) {
                    Toggle("Add a 15-minute review task", isOn: Binding(get:{review},set:{review=$0;preferences.createReview=$0;savePreferences()}))
                    Text("Optional. You can also continue this task later. Nothing is added to your calendar automatically.").font(.caption).foregroundStyle(Water.secondary)
                }
            } footer: { Text("Self-ratings do not decide completion. A task earns one drop on its first completion.") }
            Section("Session notes · what remains?") {
                TextEditor(text: $note).frame(minHeight: 100).accessibilityLabel("Session notes")
                    .onChange(of: note) { _, value in session.sessionNote = value; store.persistEdits() }
            }
            if store.elapsed(session) < 1 {
                Section {
                    Text("No active time was recorded. You can continue focusing or discard this empty session.").foregroundStyle(Water.secondary)
                    Button("Discard empty session") { if store.discard(session) { store.showToast("Empty session discarded"); onSaved() } }
                }
            }
            Section {
                Button("Save session") {
                    guard !saving else { return }; saving = true
                    if store.finish(session, rating: rating == 0 ? nil : rating, note: note, markComplete: complete, createReview: review && (1...2).contains(rating)) {
                        onSaved()
                    } else { saving = false }
                }.buttonStyle(FlowButton()).disabled(saving || store.elapsed(session) < 1).accessibilityIdentifier("saveSession")
            }
        }.modifier(FormKeyboard()).navigationTitle("Save your progress").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back to focus", action: onBack).accessibilityIdentifier("backToFocus") } }
            .onAppear {
                guard !initialized else { return }; initialized = true
                note = session.sessionNote; rating = session.understandingRating ?? 0
                preferences = store.drafts.value(FinishPreferences.self,for:preferenceKey) ?? FinishPreferences()
                complete = requestedCompletion || (preferences.markComplete ?? (!task.steps.isEmpty && task.steps.allSatisfy(\.isDone)))
                review = (1...2).contains(rating) && preferences.createReview
            }
            .onChange(of: rating) { _, value in session.understandingRating = value == 0 ? nil : value; store.persistEdits(); if value > 2 || value == 0 { review = false; preferences.createReview = false; savePreferences() } }
    }
}

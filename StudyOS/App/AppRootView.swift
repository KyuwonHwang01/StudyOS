import SwiftUI

struct AppRootView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.scenePhase) private var scene
    @Namespace private var focusNamespace
    @State private var selected = 0
    @State private var dayKey = StudyTime.dayKey(Date())
    var body: some View {
        @Bindable var store = store
        Group {
            if !store.preferences.onboardingCompleted { OnboardingView() }
            else {
                TabView(selection: $selected) {
                    NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "house") }.tag(0)
                    NavigationStack { FlowView() }.tabItem { Label("Flow", systemImage: "calendar") }.tag(1)
                    NavigationStack { OceanView() }.tabItem { Label("Ocean", systemImage: "water.waves") }.tag(2)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                }
            }
        }.environment(\.focusNamespace,focusNamespace).preferredColorScheme(store.preferences.appearance == "system" ? nil : store.preferences.appearance == "dark" ? .dark : .light)
            .alert("Could not complete that change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .overlay(alignment: .bottom) {
                if let notice = store.toast {
                    HStack(spacing: 12) {
                        Text(notice.message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        if notice.canUndo { Button("Undo") { store.undoLastAction() }.font(.headline).frame(minHeight: 44).accessibilityIdentifier("undoAction") }
                    }.padding(.horizontal, 20).padding(.vertical, 8).background(Water.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Water.mist.opacity(0.4)))
                        .padding(.horizontal, 20).padding(.bottom, 90)
                        .task(id: notice.id) {
                            do { try await Task.sleep(for: .seconds(notice.canUndo ? 8 : 3)) } catch { return }
                            store.clearToast(notice.id)
                        }
                }
            }
            .fullScreenCover(item: $store.focusRoute) { route in
                NavigationStack {
                    if let task = store.task(route.taskID) { FocusSessionView(task: task, route: route) }
                }.modifier(FocusPresentation(id:route.transitionID,namespace:focusNamespace))
            }
            .sheet(isPresented: $store.reviewDestination) { DailyReviewView() }
            .sheet(item: $store.archiveRequest) { ArchiveReviewView(request: $0) }
            .confirmationDialog("Another focus session is open", isPresented: Binding(get: { store.pendingFocusSwitch != nil }, set: { if !$0 { store.pendingFocusSwitch = nil } }), titleVisibility: .visible) {
                Button("Save current time & switch") { store.saveAndSwitchFocus() }
                Button("Return to current session") {
                    store.pendingFocusSwitch = nil
                    if let s = store.activeSession, let t = store.task(s.taskID) { store.presentFocus(t) }
                }
                Button("Cancel", role: .cancel) { store.pendingFocusSwitch = nil }
            } message: { Text("Your current notes and active time will be kept. Switching does not mark its task complete.") }
            .task {
                store.notificationService.onError = { [weak owner = store] message in owner?.error = message }
                store.notificationService.route = { [weak owner = store] taskID, goalID, blockID in
                    guard let owner else { return }
                    selected = owner.openNotification(taskID:taskID,goalID:goalID,blockID:blockID)
                }
                store.notificationService.openFocus = { [weak owner = store] in
                    guard let owner, owner.focusRoute == nil, let s = owner.activeSession, let t = owner.task(s.taskID) else { return }
                    owner.presentFocus(t, resume: false)
                }
                if store.preferences.onboardingCompleted {
                    store.expandRecurrences()
                    if !store.notificationService.receivedNotification, let session = store.activeSession { store.focusRoute = FocusRoute(taskID: session.taskID, blockID: session.planBlockID, resumeOnOpen: false) }
                }
                store.refreshNotifications()
                if let error = store.drafts.error { store.error = error }
            }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                    if scene == .active {
                        checkpoint()
                        let key = StudyTime.dayKey(store.clock.now)
                        if key != dayKey { dayKey = key; store.expandRecurrences() }
                    }
                }
            }
            .onChange(of: store.drafts.error) { _, value in if let value { store.error = value } }
            .onChange(of: scene) { _, phase in
                if phase == .background { checkpoint(); store.persistEdits(); store.drafts.flush() }
                if phase == .active { store.expandRecurrences(); store.refreshNotifications() }
            }
    }
    private func checkpoint() {
        guard let s = store.activeSession, s.status == "running" else { return }
        store.commit { s.accumulatedActiveSeconds = store.elapsed(s); s.activeIntervalStartedAt = store.clock.now }
    }
}

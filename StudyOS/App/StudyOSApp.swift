import SwiftUI
import SwiftData

@main struct StudyOSApp: App {
    @State private var store: StudyStore?
    @State private var launchError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store { AppRootView().environment(store) }
                else if let launchError {
                    ContentUnavailableView { Label("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark") }
                    description: { Text(launchError + "\nThe existing store has not been erased.") }
                    actions: { Button("Try again") { openStore() } }
                } else { ProgressView("Opening your flow…").task { openStore() } }
            }.tint(Water.accent)
        }
    }
    @MainActor private func openStore() {
        do {
            var testURL: URL?
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-studyos-ui-testing") {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let url = folder.appendingPathComponent("StudyOS-UITests.store")
                if ProcessInfo.processInfo.arguments.contains("-studyos-ui-reset") {
                    for suffix in ["", "-wal", "-shm"] {
                        let file = URL(fileURLWithPath: url.path + suffix)
                        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                    }
                }
                testURL = url
            }
            #endif
            let container = try Persistence.container(url: testURL)
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let draftName = testURL == nil ? "StudyOS-Drafts.json" : "StudyOS-UITest-Drafts.json"
            let draftURL = folder.appendingPathComponent(draftName)
            #if DEBUG
            if testURL != nil, ProcessInfo.processInfo.arguments.contains("-studyos-ui-reset"), FileManager.default.fileExists(atPath: draftURL.path) { try FileManager.default.removeItem(at: draftURL) }
            #endif
            store = try StudyStore(context: container.mainContext, draftURL: draftURL)
            launchError = nil
        } catch { launchError = error.localizedDescription }
    }
}

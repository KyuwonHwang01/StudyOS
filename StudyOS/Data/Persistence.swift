import SwiftData
import Foundation

enum Persistence {
    static let schema = Schema([Subject.self, StudyGoal.self, StudyTask.self, RecurrenceRule.self,
                                StudyPlanBlock.self, FocusSession.self, DailyReview.self, UserPreferences.self])
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        if !inMemory {
            let folder = url?.deletingLastPathComponent() ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

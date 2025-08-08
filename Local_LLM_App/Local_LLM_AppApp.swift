import SwiftUI
import SwiftData

@main
struct Local_LLM_AppApp: App {
    @StateObject private var config = AppConfig()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ChatThread.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ThreadListView()
                .environmentObject(config)
        }
        .modelContainer(sharedModelContainer)
    }
}

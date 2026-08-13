import SwiftData
import SwiftUI

@main
struct DocumentScannerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DocumentModel.self,
            PageModel.self,
            CommentModel.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .withThemeProvider()
        }
        .modelContainer(sharedModelContainer)
    }
}

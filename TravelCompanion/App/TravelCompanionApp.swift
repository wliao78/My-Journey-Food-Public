import SwiftData
import SwiftUI

@main
struct TravelCompanionApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([PlaceFeedback.self])
        let configuration = ModelConfiguration(
            "TravelCompanion",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        if let cloudContainer = try? ModelContainer(for: schema, configurations: [configuration]) {
            return cloudContainer
        }

        let localFallback = ModelConfiguration(
            "TravelCompanionLocal",
            schema: schema,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [localFallback])
        } catch {
            fatalError("Unable to create local storage: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if let preview = PublicLocalizationQA.screen { preview } else { ContentView() }
#else
                ContentView()
#endif
            }.environment(\.locale, PublicLanguage.locale)
        }
        .modelContainer(modelContainer)
    }
}

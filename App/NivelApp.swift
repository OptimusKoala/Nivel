// App/NivelApp.swift
import SwiftUI
import SwiftData

@main
struct NivelApp: App {
    private let container: ModelContainer
    /// Instance UNIQUE partagée par toute l'app (la file des célébrations vit dedans).
    @State private var gameService: GameService

    init() {
        #if DEBUG
        // Captures App Store (scripts/screenshots.sh) : store en mémoire garni d'un
        // profil de démo et pas simulés. Absent du binaire de release.
        if ScreenshotMode.isEnabled {
            let container = ScreenshotMode.makeContainer()
            ScreenshotMode.seed(into: container.mainContext)
            self.container = container
            _gameService = State(initialValue: GameService(
                modelContext: container.mainContext,
                stepsService: ScreenshotMode.makeStepsService(),
                widgetDefaults: nil
            ))
            return
        }
        #endif

        let container = try! ModelContainer(for: UserProfile.self, MealEntry.self, WeightEntry.self,
                                            DayLog.self, GamificationState.self, ActivityEntry.self)
        self.container = container
        _gameService = State(initialValue: GameService(
            modelContext: container.mainContext,
            stepsService: HealthKitService()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .modelContainer(container)
                .environment(gameService)
        }
    }
}

// App/NivelApp.swift
import SwiftUI
import SwiftData

@main
struct NivelApp: App {
    private let container: ModelContainer
    /// Instance UNIQUE partagée par toute l'app (la file des célébrations vit dedans).
    @State private var gameService: GameService

    init() {
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

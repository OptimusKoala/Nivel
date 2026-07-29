// App/NivelApp.swift
import SwiftUI
import SwiftData

@main
struct NivelApp: App {
    let container: ModelContainer = {
        try! ModelContainer(for: UserProfile.self, MealEntry.self, WeightEntry.self,
                            DayLog.self, GamificationState.self)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .modelContainer(container)
        }
    }
}

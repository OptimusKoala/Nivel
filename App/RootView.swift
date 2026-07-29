// App/RootView.swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if profiles.isEmpty {
            OnboardingFlow()
        } else {
            MainTabView()
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }

            PlaceholderScreen(title: "Repas")
                .tabItem { Label("Repas", systemImage: "fork.knife") }

            PlaceholderScreen(title: "Progrès")
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }

            PlaceholderScreen(title: "Quêtes")
                .tabItem { Label("Quêtes", systemImage: "trophy.fill") }

            PlaceholderScreen(title: "Réglages")
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
        .tint(Theme.orange)
    }
}

private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text(title)
                .foregroundStyle(Theme.text)
        }
    }
}

#Preview {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return RootView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}

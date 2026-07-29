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
    @Environment(\.scenePhase) private var scenePhase

    /// Jour courant (minuit local). HomeView fige ses bornes "aujourd'hui" à sa création :
    /// `.id(dayKey)` la recrée quand le jour change — rafraîchi au retour au premier plan.
    @State private var dayKey = Self.currentDayKey()

    var body: some View {
        TabView {
            HomeView()
                .id(dayKey)
                .tabItem { Label("Accueil", systemImage: "house.fill") }

            // .id(dayKey) : comme l'accueil, le journal repart sur "aujourd'hui"
            // quand le jour change (retour au premier plan après minuit).
            MealsJournalView()
                .id(dayKey)
                .tabItem { Label("Repas", systemImage: "fork.knife") }

            PlaceholderScreen(title: "Progrès")
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }

            PlaceholderScreen(title: "Quêtes")
                .tabItem { Label("Quêtes", systemImage: "trophy.fill") }

            PlaceholderScreen(title: "Réglages")
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
        .tint(Theme.orange)
        .onAppear { dayKey = Self.currentDayKey() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { dayKey = Self.currentDayKey() }
        }
    }

    private static func currentDayKey() -> Date {
        GameService.calendar.startOfDay(for: .now)
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

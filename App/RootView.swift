// App/RootView.swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    /// Splash à chaque lancement à froid (spec §5) — AVANT l'onboarding aussi :
    /// c'est l'ouverture de l'app. ~1,5 s, skippable d'un tap.
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if profiles.isEmpty {
                OnboardingFlow()
            } else {
                MainTabView()
            }

            if showSplash {
                SplashView()
                    .zIndex(1)
                    .transition(.opacity)
                    .onTapGesture { dismissSplash() }
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        dismissSplash()
                    }
            }
        }
        // Thème clair unique (spec §12) : le chrome système (tab bar, alertes,
        // clavier) ne doit pas passer en sombre la nuit sur notre fond crème.
        .preferredColorScheme(.light)
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.4)) {
            showSplash = false
        }
    }
}

private struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(GameService.self) private var gameService
    @Query private var profiles: [UserProfile]

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

            // .id(dayKey) : les bornes "aujourd'hui" (pas, pesée) suivent le changement de jour.
            ProgressScreen()
                .id(dayKey)
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }

            // .id(dayKey) : le refresh des quêtes (.task) repart au changement de jour
            // (retour au premier plan après minuit — dont le lundi de renouvellement).
            QuestsView()
                .id(dayKey)
                .tabItem { Label("Quêtes", systemImage: "trophy.fill") }

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
        }
        .tint(Theme.orange)
        // Présentation des célébrations (level-up plein écran, bannières badge/quête)
        // au niveau du TabView : visibles depuis n'importe quel onglet.
        .celebrationsHost()
        .onAppear {
            // Lancement à froid directement en .active : onChange ne se déclenche
            // pas — on exécute aussi le rattrapage ici.
            onForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                onForeground()
            }
        }
    }

    /// Rattrapage au premier plan (spec §9) — ORDRE contractuel :
    /// 1. clôture des journées passées (XP, DayLogs, renouvellement des quêtes),
    /// 2. re-planification des rappels (les textes de la banque se renouvellent, spec §10).
    private func onForeground() {
        dayKey = Self.currentDayKey()
        Task {
            await gameService.closeOpenDays()
            rescheduleReminders()
        }
    }

    private func rescheduleReminders() {
        if let profile = profiles.first {
            NotificationService.reschedule(for: profile)
        }
    }

    private static func currentDayKey() -> Date {
        GameService.dayKey(for: .now)
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

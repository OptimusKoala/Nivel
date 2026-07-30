// App/RootView.swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    /// Splash à chaque lancement à froid (spec §5) — AVANT l'onboarding aussi :
    /// c'est l'ouverture de l'app. Chorégraphie "scène vivante" ~2,4 s
    /// (~1,2 s en Reduce Motion : simple fondu), skippable d'un tap à tout moment.
    @State private var showSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 2.4))
                        dismissSplash()
                    }
            }
        }
        // Le chrome système (tab bar, alertes, clavier) suit l'ambiance de la
        // palette choisie (v1.1) : clair pour Crème/Menthe/Océan, sombre pour
        // Nuit douce — jamais le réglage système, qui casserait le thème.
        .preferredColorScheme(ThemeStore.shared.palette.isDark ? .dark : .light)
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.4)) {
            showSplash = false
        }
    }
}

private struct MainTabView: View {
    /// Onglets — tags STABLES pour le binding `selection` du TabView. Sans binding
    /// explicite, un re-rendu du parent (déclenché ici par le `save()` SwiftData du
    /// `.task` d'un onglet, ex. `refreshQuestProgress`) fait retomber la sélection
    /// implicite sur le premier onglet : on tapait "Quêtes" et on revenait à l'accueil.
    private enum Tab: Hashable { case home, meals, sport, progress, quests }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(GameService.self) private var gameService
    @Query private var profiles: [UserProfile]

    /// Onglet sélectionné — persiste à travers les re-rendus (contrairement à la
    /// sélection implicite d'un TabView sans binding).
    @State private var selectedTab: Tab = .home

    /// Jour courant (minuit local). HomeView fige ses bornes "aujourd'hui" à sa création :
    /// `.id(dayKey)` la recrée quand le jour change — rafraîchi au retour au premier plan.
    @State private var dayKey = Self.currentDayKey()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .id(dayKey)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(Tab.home)

            // .id(dayKey) : comme l'accueil, le journal repart sur "aujourd'hui"
            // quand le jour change (retour au premier plan après minuit).
            MealsJournalView()
                .id(dayKey)
                .tabItem { Label("Repas", systemImage: "fork.knife") }
                .tag(Tab.meals)

            // .id(dayKey) : la séance du jour et « Fait aujourd'hui » repartent
            // sur le bon jour au retour au premier plan après minuit.
            SportView()
                .id(dayKey)
                .tabItem { Label("Sport", systemImage: "figure.walk") }
                .tag(Tab.sport)

            // .id(dayKey) : les bornes "aujourd'hui" (pas, pesée) suivent le changement de jour.
            ProgressScreen()
                .id(dayKey)
                .tabItem { Label("Progrès", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)

            // .id(dayKey) : le refresh des quêtes (.task) repart au changement de jour
            // (retour au premier plan après minuit — dont le lundi de renouvellement).
            QuestsView()
                .id(dayKey)
                .tabItem { Label("Quêtes", systemImage: "trophy.fill") }
                .tag(Tab.quests)
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
                         DayLog.self, GamificationState.self, ActivityEntry.self])
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

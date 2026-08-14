// App/RootView.swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    /// Splash à chaque lancement à froid (spec §5) — AVANT l'onboarding aussi :
    /// c'est l'ouverture de l'app. Chorégraphie "scène vivante" ~2,4 s
    /// (~1,2 s en Reduce Motion : simple fondu), skippable d'un tap à tout moment.
    @State private var showSplash = Self.splashAtLaunch
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

    /// Splash affiché au lancement — sauté seulement en mode captures (DEBUG).
    private static var splashAtLaunch: Bool {
        #if DEBUG
        return !ScreenshotMode.skipsSplash
        #else
        return true
        #endif
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
    private enum Tab: Hashable {
        case home, meals, sport, progress, quests

        /// Onglet au lancement : l'accueil, sauf en mode captures (DEBUG) où le
        /// script demande l'écran à photographier.
        static var atLaunch: Tab {
            #if DEBUG
            guard ScreenshotMode.isEnabled else { return .home }
            switch ScreenshotMode.screen {
            // Les deux feuilles d'action se présentent depuis l'accueil.
            case .home, .meallog, .activitylog: return .home
            // La bande d'idées et sa fiche vivent dans l'onglet Repas (spec §6.4).
            case .meals, .idees, .recette: return .meals
            case .sport, .session, .step: return .sport
            case .progress: return .progress
            case .quests: return .quests
            }
            #else
            return .home
            #endif
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(GameService.self) private var gameService
    @Query private var profiles: [UserProfile]

    /// Onglet sélectionné — persiste à travers les re-rendus (contrairement à la
    /// sélection implicite d'un TabView sans binding).
    @State private var selectedTab: Tab = .atLaunch

    /// Jour courant (minuit local). HomeView fige ses bornes "aujourd'hui" à sa création :
    /// `.id(dayKey)` la recrée quand le jour change — rafraîchi au retour au premier plan.
    @State private var dayKey = Self.currentDayKey()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .id(dayKey)
                .themedTabBar()
                .tabItem { Label("Accueil", image: selectedTab == .home ? "Icons/tab_home_fill" : "Icons/tab_home") }
                .tag(Tab.home)

            // .id(dayKey) : comme l'accueil, le journal repart sur "aujourd'hui"
            // quand le jour change (retour au premier plan après minuit).
            MealsJournalView()
                .id(dayKey)
                .themedTabBar()
                .tabItem { Label("Repas", image: selectedTab == .meals ? "Icons/tab_meals_fill" : "Icons/tab_meals") }
                .tag(Tab.meals)

            // .id(dayKey) : la séance du jour et « Fait aujourd'hui » repartent
            // sur le bon jour au retour au premier plan après minuit.
            SportView()
                .id(dayKey)
                .themedTabBar()
                .tabItem { Label("Sport", image: selectedTab == .sport ? "Icons/tab_sport_fill" : "Icons/tab_sport") }
                .tag(Tab.sport)

            // .id(dayKey) : les bornes "aujourd'hui" (pas, pesée) suivent le changement de jour.
            ProgressScreen()
                .id(dayKey)
                .themedTabBar()
                .tabItem { Label("Progrès", image: selectedTab == .progress ? "Icons/tab_progress_fill" : "Icons/tab_progress") }
                .tag(Tab.progress)

            // .id(dayKey) : le refresh des quêtes (.task) repart au changement de jour
            // (retour au premier plan après minuit — dont le lundi de renouvellement).
            QuestsView()
                .id(dayKey)
                .themedTabBar()
                .tabItem { Label("Quêtes", image: selectedTab == .quests ? "Icons/tab_quests_fill" : "Icons/tab_quests") }
                .tag(Tab.quests)
        }
        .tint(Theme.orange)
        // Présentation des célébrations (level-up plein écran, bannières badge/quête)
        // au niveau du TabView : visibles depuis n'importe quel onglet.
        .celebrationsHost()
        // Deep link du widget (spec widgets §7). MainTabView n'existe pas tant
        // que l'onboarding n'est pas fini : le lien est alors ignoré.
        .onOpenURL { url in
            guard DeepLink.parse(url) == .logMeal else { return }
            // Rafraîchit le jour AVANT de poser le signal : sinon le rattrapage
            // minuit d'onForeground() recrée HomeView (.id(dayKey)) après coup et
            // emporte le showMealLog qui vient d'être posé.
            dayKey = Self.currentDayKey()
            selectedTab = .home
            gameService.pendingMealLogDeepLink = true
        }
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
    /// 2. synchronisation du widget (après la clôture : le snapshot part à jour),
    /// 3. re-planification des rappels (les textes de la banque se renouvellent, spec §10).
    private func onForeground() {
        dayKey = Self.currentDayKey()
        Task {
            await gameService.closeOpenDays()
            // Rattrape minuit passé app fermée : aucune sauvegarde n'a lieu s'il
            // n'y avait rien à clôturer, donc le hook de saveOrAssert ne suffit pas.
            gameService.syncWidget()
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

private extension View {
    /// Tab bar alignée sur le thème (v1.2) : fond `Theme.card` opaque — le même
    /// que les cartes — au lieu du matériau système, qui ignorerait la palette.
    /// À appliquer sur CHAQUE onglet (le réglage est porté par le contenu).
    func themedTabBar() -> some View {
        self
            .toolbarBackground(Theme.card, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
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
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}

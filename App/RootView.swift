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
    /// Le duo, pour le rattrapage au premier plan (§3.7). Injecté par `NivelApp`, comme
    /// `GameService` : c'est la même instance que celle des écrans.
    @Environment(DuoService.self) private var duoService
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
        // Le délégué UIKit reçoit le toucher d'une notification locale. La route est aussi
        // stockée dans UserDefaults pour le lancement à froid ; cet abonnement couvre le
        // tap quand l'interface est déjà affichée.
        .onReceive(NotificationCenter.default.publisher(for: NotificationNavigation.didReceiveRoute)) { note in
            guard let route = note.object as? SportSessionRoute else { return }
            // Dans ce chemin l'événement vient d'être livré immédiatement : on efface la
            // copie de lancement à froid pour qu'un futur onAppear ne rouvre pas la séance.
            _ = NotificationNavigation.consumePendingRoute()
            openSportSession(route)
        }
        .onAppear {
            consumePendingNotificationRoute()
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
            gameService.publishDuo()
            // 4. RATTRAPAGE DU DUO (spec 1.15 §3.7). Sans lui, la promesse la plus explicite
            // du duo tombe : « aucun réveil n'est envoyé si l'app a été tuée depuis le
            // sélecteur, le rattrapage se fait alors à l'ouverture ». C'est ici que ce
            // rattrapage a lieu, et nulle part ailleurs — la bulle bordée de Nivelito ne se
            // levait jamais dans le cas précis pour lequel elle a été dessinée.
            //
            // C'est aussi ce passage qui retente les cœurs envoyés hors ligne, que le §3.10
            // place « au prochain passage au premier plan ». Sans duo appairé, l'appel sort
            // à sa première ligne et n'émet rien.
            await duoService.refresh()
            rescheduleReminders()
        }
    }

    private func rescheduleReminders() {
        if let profile = profiles.first {
            NotificationService.reschedule(for: profile)
        }
    }

    /// Route le rappel AVANT que SportView soit créé : sa valeur en attente survit au
    /// changement d'onglet, puis la vue consomme et présente la séance ciblée.
    private func openSportSession(_ route: SportSessionRoute) {
        dayKey = Self.currentDayKey()
        selectedTab = .sport
        gameService.pendingSportSessionRoute = route
    }

    private func consumePendingNotificationRoute() {
        if let route = NotificationNavigation.consumePendingRoute() {
            openSportSession(route)
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
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    return RootView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
        // La section Duo des réglages en a besoin. Domaine dédié et zone jamais résolue :
        // une prévisualisation n'appaire rien et n'émet aucune requête.
        .environment(DuoService(
            identity: DuoIdentity(defaults: UserDefaults(suiteName: "nivel.preview.duo")
                ?? .standard),
            resolveTarget: { _ in nil }))
}

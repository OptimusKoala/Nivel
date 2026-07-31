// App/Views/Home/HomeView.swift
// Accueil (spec §4.1, maquette design-home.html) : en-tête (date, salut, niveau),
// Nivelito + bulle contextuelle, anneau calories + colonne pas/XP, quête la plus
// avancée, bouton "+ Logger un repas", carte « Séance du jour » (spec sport §8.2).

import SwiftUI
import SwiftData
import NivelCore

struct HomeView: View {
    @Environment(GameService.self) private var game
    @Query private var profiles: [UserProfile]
    @Query private var states: [GamificationState]
    @Query private var todayMeals: [MealEntry]

    /// Pas du jour — nil tant que non chargé OU si HealthKit est refusé/indisponible
    /// (dans les deux cas la carte est masquée et l'XP prend la colonne, spec §10).
    @State private var steps: Int?
    @State private var bubbleText = ""
    @State private var lastBubbleContext: MessageContext?
    /// Vrai tant qu'une bulle de récompense (repas/activité) est affichée : protège
    /// contre le `refresh()` asynchrone de la MÊME apparition qui l'écraserait sinon.
    @State private var rewardBubbleActive = false
    @State private var showMealLog = false
    @State private var showSettings = false
    @State private var sessionStatus: (session: ActivitySession, done: Bool)?
    @State private var showSessionPlayer = false

    init() {
        // Bornes du jour figées à la création de la vue. Le passage de minuit est géré
        // par le PARENT (MainTabView) qui applique `.id(dayKey)` et recrée HomeView
        // quand le jour change (au retour au premier plan) — pas par cette vue.
        let calendar = GameService.calendar
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _todayMeals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
    }

    // MARK: - Données dérivées

    private var profile: UserProfile? { profiles.first }
    private var totalXP: Int { states.first?.totalXP ?? 0 }
    private var kcalEaten: Int { todayMeals.reduce(0) { $0 + $1.estimatedKcal } }

    /// "Mardi 29 juillet" — date longue française, première lettre en capitale.
    private var frenchDate: String {
        let raw = Date.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: "fr_FR"))
        )
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Quête active la plus avancée non complétée — nil si aucune (carte masquée).
    static func featuredQuest(from statuses: [ActiveQuestStatus]) -> ActiveQuestStatus? {
        statuses.filter { !$0.isCompleted }.max { $0.fraction < $1.fraction }
    }

    /// Décision de bulle — logique PURE, testable (HomeDashboardTests) :
    /// récompense repas prioritaire, sinon activité, sinon contexte normal
    /// (gardé anti-churn par l'appelant).
    enum BubbleDecision: Equatable {
        case reward(MessageContext, Int)
        case context(MessageContext, Int?)
    }

    static func bubbleDecision(
        mealXP: Int?, activityXP: Int?,
        fallback: MessageContext, fallbackValue: Int?
    ) -> BubbleDecision {
        if let mealXP, mealXP > 0 { return .reward(.afterMealLog, mealXP) }
        if let activityXP, activityXP > 0 { return .reward(.afterActivity, activityXP) }
        return .context(fallback, fallbackValue)
    }

    /// Expression de Nivelito sur l'accueil — logique PURE, testable (HomeDashboardTests).
    /// Les événements transitoires priment sur l'humeur horaire : une célébration
    /// en attente (.joy) puis une bulle de récompense (.encouraging) l'emportent
    /// sur la fatigue nocturne (.sleepy après 22 h ou avant 7 h) — Nivelito ne
    /// bâille pas en criant « +20 XP ». Sinon : .happy.
    static func nivelitoExpression(
        hour: Int, celebrationPending: Bool, rewardBubbleActive: Bool
    ) -> NivelitoExpression {
        if celebrationPending { return .joy }
        if rewardBubbleActive { return .encouraging }
        if hour >= 22 || hour < 7 { return .sleepy }
        return .happy
    }

    // MARK: - Corps

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    nivelitoRow
                    statsRow
                    if let featured = Self.featuredQuest(from: game.activeQuestStatuses()) {
                        QuestCard(status: featured)
                    }
                    logMealButton
                    if let status = sessionStatus {
                        Button {
                            showSessionPlayer = true
                        } label: {
                            DailySessionCard(session: status.session,
                                             kcal: game.sessionKcal(status.session),
                                             done: status.done)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await refresh() }
        }
        .onAppear {
            // Nouvelle apparition = nouvelle chance d'écraser une bulle de récompense
            // (celle de l'apparition précédente n'a plus lieu d'être protégée).
            rewardBubbleActive = false
            sessionStatus = game.dailySessionStatus()
            updateBubble()
            consumeDeepLink()
        }
        .task { await refresh() }
        .onChange(of: game.pendingMealLogDeepLink) { _, pending in
            if pending { consumeDeepLink() }
        }
        .sheet(isPresented: $showMealLog, onDismiss: updateBubble) {
            MealLogSheet()
        }
        .sheet(isPresented: $showSettings, onDismiss: updateBubble) {
            SettingsView()
        }
        .sheet(isPresented: $showSessionPlayer, onDismiss: refreshSessionStatus) {
            if let status = sessionStatus {
                SessionPlayerSheet(session: status.session, done: status.done)
            }
        }
    }

    private func refresh() async {
        await game.refreshQuestProgress()
        steps = await game.todaySteps()
        sessionStatus = game.dailySessionStatus()
        // Le refresh peut lever une célébration → le contexte du message peut changer.
        updateBubble()
    }

    /// Deep link « + Repas » du widget : consomme le signal et ouvre la sheet
    /// (l'app peut être à froid — onAppear — ou déjà ouverte — onChange).
    /// Collision connue et acceptée : si Réglages ou le player de séance est déjà
    /// présenté au moment du lien, UIKit abandonne la présentation de la sheet
    /// repas (cas rare) — le tap se contente alors de ramener sur l'app.
    private func consumeDeepLink() {
        guard game.pendingMealLogDeepLink else { return }
        game.pendingMealLogDeepLink = false
        showMealLog = true
    }

    /// Rafraîchit l'encart séance ET la bulle (une validation dans la sheet peut
    /// avoir attribué de l'XP d'activité, cf. `lastActivityXPAwarded`).
    private func refreshSessionStatus() {
        sessionStatus = game.dailySessionStatus()
        updateBubble()
    }

    /// Bulle de récompense (repas/activité) prioritaire, sinon contexte normal —
    /// recalculé uniquement quand celui-ci change (nouvelle célébration, nouvelle
    /// tranche horaire…) pour ne pas churner le message à chaque retour sur l'onglet.
    /// Décision déléguée à `Self.bubbleDecision` (pure, testée dans HomeDashboardTests).
    private func updateBubble() {
        // Consomme les DEUX signaux à chaque passage : si le repas gagne la priorité,
        // le signal d'activité ne doit pas survivre et ressortir en bulle périmée.
        let mealXP = game.lastMealXPAwarded
        let activityXP = game.lastActivityXPAwarded
        game.lastMealXPAwarded = nil
        game.lastActivityXPAwarded = nil

        let (context, value) = game.homeMessageContext()

        switch Self.bubbleDecision(mealXP: mealXP, activityXP: activityXP,
                                   fallback: context, fallbackValue: value) {
        case .reward(let rewardContext, let rewardValue):
            // Bulle "après log" prioritaire (spec §4.2) : repas d'abord (cas rarissime
            // où les deux sont en attente), sinon activité.
            lastBubbleContext = rewardContext
            bubbleText = game.nivelitoSays(context: rewardContext, value: rewardValue)
            rewardBubbleActive = true
        case .context(let context, let value):
            // Une bulle de récompense ne cède la place qu'à une célébration : sinon le
            // refresh() asynchrone de la MÊME apparition l'écraserait aussitôt.
            if rewardBubbleActive, context != .levelUp, context != .badge { return }
            rewardBubbleActive = false
            // Recalcule uniquement quand le CONTEXTE change (nouvelle célébration,
            // nouvelle tranche horaire…) : les retours sur l'onglet ne font pas churner
            // le message, mais un événement survenu entre-temps est bien reflété.
            guard context != lastBubbleContext else { return }
            lastBubbleContext = context
            bubbleText = game.nivelitoSays(context: context, value: value)
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(frenchDate)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.subtext)
                Text("Salut \(profile?.name ?? "") 👋")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            levelPill
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(CircleIconButtonStyle())
            .accessibilityLabel("Réglages")
        }
    }

    private var levelPill: some View {
        VStack(spacing: 0) {
            // Même micro sur-titre que « SÉANCE DU JOUR » (DailySessionCard).
            Text("NIVEAU")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.subtext)
            Text("\(LevelSystem.level(forXP: totalXP))")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.shadow, radius: 8, y: 4)
    }

    // MARK: - Nivelito

    private var nivelitoRow: some View {
        HStack(alignment: .top, spacing: 10) {
            NivelitoView(
                // Expression contextuelle (v1.2-B) : célébration → joy, bulle de
                // récompense → encouraging, nuit → sleepy, sinon happy. Le corps est
                // réévalué quand `pendingCelebrations` (GameService observable) ou
                // `rewardBubbleActive` changent ; l'heure suit via la recréation de
                // la vue (`.id(dayKey)` du parent) et les retours au premier plan.
                expression: Self.nivelitoExpression(
                    hour: GameService.calendar.component(.hour, from: .now),
                    celebrationPending: !game.pendingCelebrations.isEmpty,
                    rewardBubbleActive: rewardBubbleActive
                ),
                size: 86,
                // Compteur MONOTONE : une célébration levée pendant que l'accueil est
                // visible fait rebondir Nivelito, mais le dépilage de la file (Task 19)
                // ne re-déclenchera rien.
                celebrationTrigger: game.celebrationsRaised
            )
            if !bubbleText.isEmpty {
                SpeechBubble(text: bubbleText)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Cartes de stats

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            CalorieRingCard(eaten: kcalEaten, target: profile?.dailyCalorieTarget ?? 0)
            VStack(spacing: 12) {
                if let steps {
                    StepsCard(steps: steps, goal: profile?.dailyStepGoal ?? 8000)
                }
                XPCard(totalXP: totalXP)
            }
            .frame(width: 136)
        }
        // minHeight (pas height) : les cartes peuvent grandir avec le Dynamic Type.
        .frame(minHeight: 210)
    }

    // MARK: - CTA

    private var logMealButton: some View {
        Button("+ Logger un repas") {
            showMealLog = true
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: - Carte quête

private struct QuestCard: View {
    let status: ActiveQuestStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(status.quest.emoji)
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(status.quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Spacer()
                    Text("\(status.progress)/\(status.quest.target)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.orange)
                }
                ThemedProgressBar(fraction: status.fraction, fill: Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Previews

@MainActor
private func homePreviewFixture(
    kcalEaten: Int,
    totalXP: Int,
    stepsAuthorized: Bool,
    steps: Int = 5400,
    sessionDone: Bool = false
) -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = container.mainContext

    context.insert(UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 180, initialWeightKg: 90, activity: .moderate,
        dailyCalorieTarget: 2000
    ))
    context.insert(MealEntry(slot: .lunch, dishID: "pasta", portion: .normal,
                             estimatedKcal: kcalEaten))

    // Même session que la rotation du jour, spec sport §3.3 (mirroir de SportView).
    if sessionDone {
        let sessions = (try? Catalogs.sessions()) ?? []
        if let todaySession = DailySessionPicker.session(for: .now, sessions: sessions,
                                                         calendar: GameService.calendar) {
            context.insert(ActivityEntry(kind: .dailySession, refID: todaySession.id,
                                         durationMinutes: todaySession.totalMinutes,
                                         estimatedKcal: 120, xpAwarded: 40))
        }
    }

    let quests = (try? Catalogs.quests()) ?? []
    let weekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
    let active = QuestEngine.weeklyDraw(pool: quests, weekID: weekID, stepsAvailable: stepsAuthorized)
    context.insert(GamificationState(
        totalXP: totalXP,
        activeQuestIDs: active.map(\.id),
        questWeekID: weekID,
        questProgress: Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.target / 2) })
    ))
    try? context.save()

    let today = GameService.calendar.startOfDay(for: .now)
    let fake = FakeStepsService(stepsByDay: [today: steps], authorized: stepsAuthorized)
    return (container, GameService(modelContext: context, stepsService: fake, widgetDefaults: nil))
}

#Preview("Accueil") {
    let (container, game) = homePreviewFixture(kcalEaten: 1240, totalXP: 780, stepsAuthorized: true)
    return HomeView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Séance faite") {
    let (container, game) = homePreviewFixture(kcalEaten: 1240, totalXP: 780,
                                               stepsAuthorized: true, sessionDone: true)
    return HomeView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Dépassé, sans HealthKit") {
    let (container, game) = homePreviewFixture(kcalEaten: 2350, totalXP: 120, stepsAuthorized: false)
    return HomeView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

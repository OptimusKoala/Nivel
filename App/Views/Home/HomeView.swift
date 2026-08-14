// App/Views/Home/HomeView.swift
// Accueil (spec §4.1, maquette design-home.html) : en-tête (date, salut, niveau),
// Nivelito + bulle contextuelle, anneau calories + colonne pas/XP, quête la plus
// avancée, les deux boutons illustrés « Noter un repas » / « Noter une activité »
// (spec v1.13 §6), carte « Séance du jour » (spec sport §8.2).

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
    /// Dépense du jour et sa cible (spec v1.14 §5.5), recalculées ENSEMBLE dans
    /// `refreshBurn()`. Deux `@State` et non deux lectures directes au niveau du
    /// `body` : la cible dépend de la dernière pesée, or cette vue n'observe aucun
    /// `WeightEntry` — la lire dans le `body` ne se rafraîchirait que par accident,
    /// via le `GamificationState` que `@Query states` observe (et pas du tout à la
    /// deuxième pesée du jour, l'XP de pesée étant plafonnée à 1/jour). Les porter
    /// tous les deux garde surtout les deux nombres COHÉRENTS : `burned` dépend lui
    /// aussi du poids courant, et un anneau dont seule la cible se rafraîchirait
    /// afficherait « dépensé » et « cible » calculés sur deux poids différents.
    ///
    /// La cohérence vaut APRÈS le premier calcul complet : `primeBurnTarget()` avance
    /// délibérément la cible seule à l'apparition, donc entre elle et la fin de
    /// `refresh()` la dépense reste sur le poids précédent. L'écart est faible et va
    /// dans le bon sens (la cible avance, la dépense rattrape) ; l'alternative, ne
    /// rien amorcer, affichait « / 0 » à chaque lancement.
    @State private var burned = 0
    @State private var burnTarget = 0
    @State private var bubbleText = ""
    @State private var lastBubbleContext: MessageContext?
    /// Vrai tant qu'une bulle de récompense (repas/activité) est affichée : protège
    /// contre le `refresh()` asynchrone de la MÊME apparition qui l'écraserait sinon.
    @State private var rewardBubbleActive = false
    @State private var showMealLog = false
    @State private var showActivityPicker = false
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

    /// Les pas tels que `burnKcal` doit les recevoir — logique PURE, testée
    /// (HomeDashboardTests). `steps == nil` recouvre ici DEUX situations que rien ne
    /// distingue (HealthKit refusé, ou lecture pas encore revenue), et les deux
    /// donnent `.unavailable` : `.measured(0)` en attendant la réponse ferait
    /// clignoter l'anneau vers le bas au lancement, `.measured` excluant les
    /// activités marchées alors que `.unavailable` les compte (spec §5.4).
    static func dailySteps(from steps: Int?) -> DailySteps {
        steps.map(DailySteps.measured) ?? .unavailable
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
                // 14 et non 16, et 16 de marge basse et non 24 (v1.13) : ces 18 pt sont
                // ce qui permet à l'accueil de tenir sans défilement même quand la bulle
                // de Nivelito prend ses TROIS lignes (SpeechBubble les plafonne là).
                // Sans eux ça tient au cas courant de deux lignes et déborde au premier
                // message long — c'est-à-dire que ça ne tient pas.
                VStack(spacing: 14) {
                    header
                    nivelitoRow
                    statsRow
                    if let featured = Self.featuredQuest(from: game.activeQuestStatuses()) {
                        QuestCard(status: featured)
                    }
                    actionButtons
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
                .padding(.bottom, 16)
            }
            .refreshable { await refresh() }
        }
        .onAppear {
            // Nouvelle apparition = nouvelle chance d'écraser une bulle de récompense
            // (celle de l'apparition précédente n'a plus lieu d'être protégée).
            rewardBubbleActive = false
            sessionStatus = game.dailySessionStatus()
            primeBurnTarget()
            updateBubble()
            consumeDeepLink()
            #if DEBUG
            // Captures (scripts/screenshots.sh) : absentes en release.
            if ScreenshotMode.autoOpensMealLog { showMealLog = true }
            if ScreenshotMode.autoOpensActivityPicker { showActivityPicker = true }
            #endif
        }
        .task { await refresh() }
        .onChange(of: game.pendingMealLogDeepLink) { _, pending in
            if pending { consumeDeepLink() }
        }
        .sheet(isPresented: $showMealLog, onDismiss: updateBubble) {
            MealLogSheet()
        }
        // Bulle rafraîchie à la fermeture, comme pour le repas : `logActivity` publie
        // `lastActivityXPAwarded`, et c'est ce signal qui fait féliciter Nivelito.
        // Plus la dépense : l'activité qui vient d'être validée compte dans l'anneau.
        .sheet(isPresented: $showActivityPicker, onDismiss: refreshBurnAndBubble) {
            ActivityPickerSheet()
        }
        .sheet(isPresented: $showSettings, onDismiss: refreshBurnAndBubble) {
            SettingsView()
        }
        .sheet(isPresented: $showSessionPlayer, onDismiss: refreshSessionStatus) {
            if let status = sessionStatus {
                SessionPlayerSheet(session: status.session, done: status.done, kind: .dailySession)
            }
        }
    }

    private func refresh() async {
        await game.refreshQuestProgress()
        steps = await game.todaySteps()
        sessionStatus = game.dailySessionStatus()
        refreshBurn()
        // Le refresh peut lever une célébration → le contexte du message peut changer.
        updateBubble()
    }

    /// Dépense du jour et cible de dépense, recalculées au même instant et donc sur le
    /// même poids courant (spec v1.14 §5.5).
    ///
    /// ⚠️ La dépense vient de `game.burnKcal`, JAMAIS de `DayLog.kcalBurned` : ce champ
    /// n'est écrit qu'à la CLÔTURE, c'est-à-dire le lendemain. L'anneau montre
    /// AUJOURD'HUI, journée non close, où il vaut 0 par construction — le lire donnerait
    /// un anneau figé à zéro toute la journée qui sauterait d'un coup à minuit.
    private func refreshBurn() {
        burned = game.burnKcal(on: .now, steps: Self.dailySteps(from: steps))
        burnTarget = game.burnTarget()
    }

    /// Cible de dépense amorcée dès l'apparition, AVANT les deux allers-retours
    /// HealthKit de `refresh()` (dont `todaySteps`, et `refreshQuestProgress` quand une
    /// quête de pas est active). Sans elle
    /// la légende lirait « Dépensé ~0 / 0 » à chaque lancement à froid, et VoiceOver
    /// « environ 0 sur 0 » : la cible ne dépend que du profil et du poids courant, rien
    /// ne justifie de la faire attendre les pas.
    ///
    /// ⚠️ `burned` n'est délibérément PAS amorcé ici, et « symétriser » les deux serait
    /// une faute : sans les pas il se calculerait en `.unavailable`, donc activités
    /// MARCHÉES COMPRISES, puis redescendrait à l'arrivée de la lecture — le
    /// clignotement vers le bas que `DailySteps` existe précisément pour empêcher. Il
    /// reste à 0 jusqu'au premier calcul complet : l'anneau part vide et se remplit.
    private func primeBurnTarget() {
        burnTarget = game.burnTarget()
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

    /// Rafraîchit l'encart séance, LA DÉPENSE DU JOUR et la bulle. Les trois, pas
    /// deux : une séance jouée dans la sheet compte dans l'anneau intérieur, et
    /// c'est par ici que l'accueil l'apprend. La bulle, elle, parce que la
    /// validation peut avoir attribué de l'XP d'activité (cf. `lastActivityXPAwarded`).
    private func refreshSessionStatus() {
        sessionStatus = game.dailySessionStatus()
        refreshBurnAndBubble()
    }

    /// Fermeture d'une sheet qui a pu changer la dépense du jour (activité validée,
    /// séance jouée) ou sa cible (objectif de dépense des Réglages) : présenter une
    /// sheet ne fait pas disparaître l'accueil, donc ni `.task` ni `onAppear` ne
    /// rejouent au retour — sans ce rappel, l'anneau intérieur resterait sur la valeur
    /// d'avant jusqu'au prochain changement d'onglet.
    private func refreshBurnAndBubble() {
        refreshBurn()
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
                CozyIcon(name: "icon_settings", size: 24)
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
            CalorieRingCard(eaten: kcalEaten, target: profile?.dailyCalorieTarget ?? 0,
                            burned: burned, burnTarget: burnTarget)
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

    /// Les deux appels à l'action (spec v1.13 §6.1) : noter ce qu'on vient de manger,
    /// noter ce qu'on vient de faire. Même poids visuel — ce sont les deux gestes
    /// quotidiens de l'app.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            ActionCardButton.meal { showMealLog = true }
            ActionCardButton.activity { showActivityPicker = true }
        }
    }
}

// MARK: - Carte quête

private struct QuestCard: View {
    let status: ActiveQuestStatus

    var body: some View {
        HStack(spacing: 12) {
            CatalogGlyph(icon: status.quest.icon, size: 37)
                .foregroundStyle(Theme.orange)
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
    // Seuls `slot` et `estimatedKcal` comptent pour ce fixture (anneau, total du
    // jour) : pas besoin de lignes réelles, comme un repas d'avant la migration.
    context.insert(MealEntry(slot: .lunch, estimatedKcal: kcalEaten))

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
    // postureAvailable: false — fixture de preview Xcode, sans effet en dehors du
    // canvas ; ce n'est pas un des deux appelants réels (DayCloser, OnboardingFlow).
    let active = QuestEngine.weeklyDraw(pool: quests, weekID: weekID, stepsAvailable: stepsAuthorized, postureAvailable: false)
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

#Preview("Dépense atteinte") {
    // 8 000 pas à 90 kg ≈ 411 kcal, au-dessus de la cible (90 × 4 arrondie à 350) :
    // la légende doit dire « Objectif de dépense atteint 🎉 » et l'anneau intérieur
    // être plein — jamais de reproche au-delà (spec §5.5).
    let (container, game) = homePreviewFixture(kcalEaten: 1240, totalXP: 780,
                                               stepsAuthorized: true, steps: 8000)
    return HomeView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Dépassé, sans HealthKit") {
    // `sessionDone: true` n'est pas décoratif : sans pas ET sans activité, la dépense
    // vaudrait 0 et l'anneau intérieur serait invisible — or c'est précisément la
    // preview qui sert à vérifier que les deux anneaux ne se confondent pas quand
    // l'extérieur passe à `Theme.accent` (spec §5.5). Sans HealthKit, la séance compte
    // en entier, marche comprise (spec §5.4).
    let (container, game) = homePreviewFixture(kcalEaten: 2350, totalXP: 120,
                                               stepsAuthorized: false, sessionDone: true)
    return HomeView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

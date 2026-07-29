// App/Views/Home/HomeView.swift
// Accueil (spec §4.1, maquette design-home.html) : en-tête (date, salut, niveau),
// Nivelito + bulle contextuelle, anneau calories + colonne pas/XP, quête la plus
// avancée, bouton "+ Logger un repas".

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
    @State private var showMealLog = false

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
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await refresh() }
        }
        .onAppear(perform: updateBubble)
        .task { await refresh() }
        .sheet(isPresented: $showMealLog, onDismiss: updateBubble) {
            MealLogSheet()
        }
    }

    private func refresh() async {
        await game.refreshQuestProgress()
        steps = await game.todaySteps()
        // Le refresh peut lever une célébration → le contexte du message peut changer.
        updateBubble()
    }

    /// Recalcule la bulle uniquement quand le CONTEXTE change (nouvelle célébration,
    /// nouvelle tranche horaire…) : les retours sur l'onglet ne font pas churner le
    /// message, mais un événement survenu entre-temps est bien reflété.
    private func updateBubble() {
        // Bulle "après log" prioritaire (spec §4.2) : signal consommé une seule fois,
        // quel que soit l'onglet d'origine du log (sheet de l'accueil OU journal Repas —
        // le retour sur l'accueil repasse par onAppear).
        if game.mealJustLogged {
            game.mealJustLogged = false
            lastBubbleContext = .afterMealLog
            bubbleText = game.nivelitoSays(context: .afterMealLog)
            return
        }
        let (context, value) = game.homeMessageContext()
        guard context != lastBubbleContext else { return }
        lastBubbleContext = context
        bubbleText = game.nivelitoSays(context: context, value: value)
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
        }
    }

    private var levelPill: some View {
        VStack(spacing: 0) {
            Text("NIVEAU")
                .font(.system(size: 9, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.subtext)
            Text("\(LevelSystem.level(forXP: totalXP))")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Nivelito

    private var nivelitoRow: some View {
        HStack(alignment: .top, spacing: 10) {
            NivelitoView(
                expression: .happy,
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
        Button {
            showMealLog = true
        } label: {
            Text("+ Logger un repas")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.orange],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
        }
        .buttonStyle(.plain)
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

// MARK: - Formatage

extension Int {
    /// "8000" → "8 000" (groupement français, espace fine insécable).
    var frFormatted: String {
        formatted(.number.locale(Locale(identifier: "fr_FR")))
    }
}

// MARK: - Previews

@MainActor
private func homePreviewFixture(
    kcalEaten: Int,
    totalXP: Int,
    stepsAuthorized: Bool,
    steps: Int = 5400
) -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self])
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
    return (container, GameService(modelContext: context, stepsService: fake))
}

#Preview("Accueil") {
    let (container, game) = homePreviewFixture(kcalEaten: 1240, totalXP: 780, stepsAuthorized: true)
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

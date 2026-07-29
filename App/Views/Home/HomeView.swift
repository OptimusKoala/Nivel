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
    @State private var showMealLog = false

    init() {
        // Bornes du jour figées à la création de la vue : après minuit, le pull-to-refresh
        // ou une réouverture de l'app recrée la vue — acceptable pour la v1.
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
        .task {
            // Message calculé une fois par apparition de l'écran (nivelitoSays persiste
            // l'anti-répétition) ; pas recalculé à chaque changement d'onglet.
            if bubbleText.isEmpty {
                let (context, value) = game.homeMessageContext()
                bubbleText = game.nivelitoSays(context: context, value: value)
            }
            await refresh()
        }
        .sheet(isPresented: $showMealLog) {
            // Task 14 : remplacé par MealLogSheet.
            ZStack {
                Theme.background.ignoresSafeArea()
                Text("Log de repas — Task 14")
                    .foregroundStyle(Theme.text)
            }
            .presentationDetents([.medium])
        }
    }

    private func refresh() async {
        await game.refreshQuestProgress()
        steps = await game.todaySteps()
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
                // Une célébration mise en file pendant que l'accueil est visible fait
                // rebondir Nivelito (l'overlay plein écran arrive en Task 19).
                celebrationTrigger: game.pendingCelebrations.count
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
        .frame(height: 210)
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

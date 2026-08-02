// NivelTests/DayCloserTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

/// Tests de la clôture des journées passées (DayCloser.swift, spec §9).
/// Les dates sont CONTRÔLÉES : `today` est figé au début du test et passé
/// explicitement à `closeOpenDays(today:)` — la logique ne lit jamais `.now`.
@MainActor
final class DayCloserTests: XCTestCase {
    private var context: ModelContext!
    private var profile: UserProfile!
    private var state: GamificationState!

    /// Jour J figé (les journées à clôturer en sont dérivées).
    private var today: Date!
    private var day1: Date!      // J-3
    private var day2: Date!      // J-2
    private var day3: Date!      // J-1 = hier
    private var yesterday: Date! // = day3

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        today = Date.now
        let todayKey = GameService.dayKey(for: today)
        day1 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -3, to: todayKey))
        day2 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -2, to: todayKey))
        day3 = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -1, to: todayKey))
        yesterday = day3

        profile = UserProfile(
            name: "Michaël",
            sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            initialWeightKg: 90,
            activity: .moderate,
            dailyCalorieTarget: 2000,
            dailyStepGoal: 8000,
            createdAt: day1 // 3 journées ouvertes : J-3, J-2, J-1
        )
        context.insert(profile)

        // Semaine courante + aucune quête active : les tests de clôture ne sont
        // pas parasités par le tirage (le rollover a son test dédié).
        state = GamificationState(
            questWeekID: QuestEngine.weekID(for: today, calendar: GameService.calendar)
        )
        context.insert(state)
        try context.save()
    }

    private func makeService(steps: FakeStepsService) -> GameService {
        GameService(modelContext: context, stepsService: steps, widgetDefaults: nil)
    }

    /// Repas inséré directement (sans XP) à midi du jour donné : la clôture doit
    /// recalculer les kcal depuis les MealEntry, source de vérité.
    private func insertMeal(on day: Date, kcal: Int, slot: MealSlot = .lunch) {
        context.insert(MealEntry(
            date: day.addingTimeInterval(12 * 3600),
            slot: slot,
            lines: [.simple(MealComponent(itemID: "pasta", grams: 500))],
            estimatedKcal: kcal
        ))
    }

    private func fetchDayLogs() throws -> [DayLog] {
        try context.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.day)]))
    }

    // MARK: - Clôture d'un trou de 3 jours

    func testClosesThreeDayGapWithCorrectXPAndSnapshots() async throws {
        // J-3 : 2 repas SOUS l'objectif (1300 ≤ 2000) + 9000 pas ≥ 8000 → +50 +40.
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        // J-2 : 2 repas AU-DESSUS (2100 > 2000) → +0.
        insertMeal(on: day2, kcal: 1450, slot: .lunch)
        insertMeal(on: day2, kcal: 650, slot: .dinner)
        // J-1 : aucun repas → sans journal, pas de jugement (withinTarget false, pas de +50).
        try context.save()

        let service = makeService(steps: FakeStepsService(
            stepsByDay: [day1: 9000, day2: 2000] // J-1 absent → 0 pas
        ))
        await service.closeOpenDays(today: today)

        let logs = try fetchDayLogs()
        XCTAssertEqual(logs.count, 3)
        XCTAssertTrue(logs.allSatisfy(\.closed))
        XCTAssertEqual(logs.map(\.day), [day1, day2, day3])

        // J-3 : dans l'objectif + objectif de pas atteint.
        XCTAssertEqual(logs[0].kcalEaten, 1300)
        XCTAssertEqual(logs[0].kcalTarget, 2000)
        XCTAssertEqual(logs[0].steps, 9000)
        XCTAssertTrue(logs[0].withinTarget)
        XCTAssertEqual(logs[0].xpEarned, 90) // +50 dayWithinTarget, +40 stepGoalReached

        // J-2 : au-dessus de l'objectif.
        XCTAssertEqual(logs[1].kcalEaten, 2100)
        XCTAssertEqual(logs[1].steps, 2000)
        XCTAssertFalse(logs[1].withinTarget)
        XCTAssertEqual(logs[1].xpEarned, 0)

        // J-1 : aucun log → pas de jugement.
        XCTAssertEqual(logs[2].kcalEaten, 0)
        XCTAssertEqual(logs[2].steps, 0)
        XCTAssertFalse(logs[2].withinTarget)
        XCTAssertEqual(logs[2].xpEarned, 0)

        // XP total = 90 (clôtures) + 50 (badge "Premier repas", 4 repas au journal).
        XCTAssertEqual(state.totalXP, 140)
        XCTAssertNotNil(state.badgeUnlocks["first_meal"])
        XCTAssertEqual(state.lastClosedDay, yesterday)
    }

    // MARK: - Renouvellement hebdo

    func testWeekRolloverRedrawsQuestsAndPreservesHistory() async throws {
        let lastWeek = try XCTUnwrap(
            GameService.calendar.date(byAdding: .day, value: -7, to: today)
        )
        state.questWeekID = QuestEngine.weekID(for: lastWeek, calendar: GameService.calendar)
        state.activeQuestIDs = ["weigh_in_1", "log_meals_10", "no_alcohol_2"]
        state.completedThisWeekQuestIDs = ["weigh_in_1"]
        state.questProgress = ["weigh_in_1": 1, "log_meals_10": 4]
        state.completedQuestIDs = ["weigh_in_1"] // historique all-time, déjà alimenté à la complétion
        state.lastClosedDay = yesterday          // rien à clôturer : on isole le rollover
        // Badge "Première quête" déjà débloqué : l'XP total doit rester STRICTEMENT inchangé.
        state.badgeUnlocks = ["quest_first": .now]
        try context.save()

        let service = makeService(steps: FakeStepsService(authorized: false))
        await service.closeOpenDays(today: today)

        let currentWeekID = QuestEngine.weekID(for: today, calendar: GameService.calendar)
        XCTAssertEqual(state.questWeekID, currentWeekID)

        // Nouveau tirage : 3 quêtes valides du catalogue, sans quête de pas (HealthKit refusé).
        let catalog = try Catalogs.quests()
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        XCTAssertEqual(state.activeQuestIDs.count, 3)
        for id in state.activeQuestIDs {
            let quest = try XCTUnwrap(catalogByID[id], "id de quête inconnu : \(id)")
            XCTAssertFalse(quest.requiresSteps)
        }

        // Garde hebdo remis à zéro ; l'HISTORIQUE all-time n'est PAS retouché
        // (les complétées y sont déjà — pas de ré-archivage, contrat GameService).
        XCTAssertTrue(state.completedThisWeekQuestIDs.isEmpty)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1"])

        // Progression repartie de zéro : uniquement les nouvelles quêtes, toutes à 0
        // (aucune donnée cette semaine).
        XCTAssertTrue(Set(state.questProgress.keys).isSubset(of: Set(state.activeQuestIDs)))
        XCTAssertTrue(state.questProgress.values.allSatisfy { $0 == 0 })

        XCTAssertEqual(state.totalXP, 0)
    }

    // MARK: - Erreur HealthKit

    func testStepsQueryErrorSkipsWholeClosingRun() async throws {
        // Journée qui AURAIT été récompensée si la requête de pas avait réussi.
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        try context.save()

        // HealthKit "disponible" mais la requête échoue (nil ≠ [:]) : rien ne doit
        // être figé à 0 pas — toute la passe est abandonnée et sera retentée.
        let service = makeService(steps: FakeStepsService(
            stepsByDay: [day1: 9000],
            failing: true
        ))
        await service.closeOpenDays(today: today)

        XCTAssertNil(state.lastClosedDay)
        XCTAssertTrue(try fetchDayLogs().isEmpty)
        XCTAssertEqual(state.totalXP, 0)

        // La requête redevient saine → le rattrapage complet passe.
        (service.stepsService as? FakeStepsService)?.failing = false
        await service.closeOpenDays(today: today)
        XCTAssertEqual(state.lastClosedDay, yesterday)
        XCTAssertEqual(try fetchDayLogs().first?.xpEarned, 90)
    }

    // MARK: - Idempotence

    func testRunningTwiceDoesNotDoubleAward() async throws {
        insertMeal(on: day1, kcal: 650, slot: .lunch)
        insertMeal(on: day1, kcal: 650, slot: .dinner)
        try context.save()

        let service = makeService(steps: FakeStepsService(stepsByDay: [day1: 9000]))
        await service.closeOpenDays(today: today)

        let xpAfterFirstRun = state.totalXP
        let lastClosedAfterFirstRun = state.lastClosedDay

        await service.closeOpenDays(today: today)

        XCTAssertEqual(state.totalXP, xpAfterFirstRun)
        XCTAssertEqual(state.lastClosedDay, lastClosedAfterFirstRun)

        let logs = try fetchDayLogs()
        XCTAssertEqual(logs.count, 3) // pas de DayLog dupliqué
        XCTAssertEqual(logs[0].xpEarned, 90) // pas de double attribution sur J-3
    }
}

// NivelTests/GameServiceTests.swift
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class GameServiceTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!

    private var pasta: Dish!
    private var beer: Extra!
    private var richDessert: Extra!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        let profile = UserProfile(
            name: "Michaël",
            sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            initialWeightKg: 90,
            activity: .moderate,
            dailyCalorieTarget: 2000
        )
        context.insert(profile)
        context.insert(GamificationState())
        try context.save()

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: nil)

        let dishes = try Catalogs.dishes()
        let extras = try Catalogs.extras()
        pasta = try XCTUnwrap(dishes.first { $0.id == "pasta" })
        beer = try XCTUnwrap(extras.first { $0.id == "beer" })
        richDessert = try XCTUnwrap(extras.first { $0.id == "dessert_rich" })
    }

    func testLogMealEstimatesKcalAwardsXPAndUpdatesDayLog() async throws {
        // Pâtes copieux (650 × 1,3 = 845) + 2 bières (300) + dessert gourmand (300) = 1445.
        let first = await service.logMeal(
            slot: .dinner, dish: pasta, portion: .hearty,
            extras: [(beer, 2), (richDessert, 1)]
        )
        XCTAssertEqual(first.estimatedKcal, 1445)
        XCTAssertEqual(first.xpAwarded, 20)

        let second = await service.logMeal(slot: .lunch, dish: pasta, portion: .normal)
        XCTAssertEqual(second.estimatedKcal, 650)
        XCTAssertEqual(second.xpAwarded, 20)

        let dayLogs = try context.fetch(FetchDescriptor<DayLog>())
        XCTAssertEqual(dayLogs.count, 1)
        XCTAssertEqual(dayLogs.first?.kcalEaten, 1445 + 650)
        XCTAssertEqual(dayLogs.first?.kcalTarget, 2000)

        // XP total = 2 × 20 (repas) + 50 (badge "Premier repas").
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertEqual(state.totalXP, 90)
        XCTAssertNotNil(state.badgeUnlocks["first_meal"])
        XCTAssertTrue(service.pendingCelebrations.contains {
            if case .badge(let badge) = $0 { badge.id == "first_meal" } else { false }
        })
    }

    func testFifthMealOfTheDayGetsNoXP() async throws {
        var awarded: [Int] = []
        for _ in 1...5 {
            let entry = await service.logMeal(slot: .snack, dish: pasta, portion: .normal)
            awarded.append(entry.xpAwarded)
        }
        XCTAssertEqual(awarded, [20, 20, 20, 20, 0])

        // Le plafond est dérivé des MealEntry persistés → il tient aussi après "relance"
        // (nouvelle instance de service sur le même store).
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                                    widgetDefaults: nil)
        let sixth = await restarted.logMeal(slot: .snack, dish: pasta, portion: .normal)
        XCTAssertEqual(sixth.xpAwarded, 0)
    }

    func testRedrawnQuestReawardsXPInALaterWeek() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["weigh_in_1"] // "Pèse-toi une fois" (target 1)
        try context.save()

        // Semaine 1 : la pesée complète la quête → +150 XP, une seule fois.
        await service.logWeight(kg: 90.0)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1"])
        XCTAssertEqual(state.completedThisWeekQuestIDs, ["weigh_in_1"])
        let xpAfterFirstCompletion = state.totalXP
        XCTAssertEqual(service.pendingCelebrations.count(where: { $0.id == "quest-weigh_in_1" }), 1)

        // Re-refresh dans la même semaine : pas de re-récompense.
        await service.refreshQuestProgress()
        XCTAssertEqual(state.totalXP, xpAfterFirstCompletion)

        // Simule le renouvellement du lundi (Task 18) qui retire la MÊME quête :
        // reset du garde hebdo + progression ; l'historique all-time est conservé.
        state.completedThisWeekQuestIDs = []
        state.questProgress = [:]
        try context.save()
        // L'utilisateur a vu la célébration de la semaine 1 (la file anti-doublon
        // de raise() ignorerait sinon une célébration identique encore en attente).
        service.pendingCelebrations = []

        // "Semaine 2" : la quête déjà dans l'historique doit re-récompenser.
        await service.refreshQuestProgress()
        XCTAssertEqual(state.totalXP, xpAfterFirstCompletion + 150)
        XCTAssertEqual(state.completedQuestIDs, ["weigh_in_1", "weigh_in_1"])
        XCTAssertEqual(state.completedThisWeekQuestIDs, ["weigh_in_1"])
        XCTAssertEqual(service.pendingCelebrations.count(where: { $0.id == "quest-weigh_in_1" }), 1)

        // L'historique (doublons compris) alimente le compteur de badges.
        XCTAssertEqual(service.badgeStats().questsCompleted, 2)
    }

    func testUpdateMealRecomputesKcalWithoutAwardingXP() async throws {
        // Log initial : pâtes normal = 650 kcal, +20 XP (+50 badge "Premier repas").
        let entry = await service.logMeal(slot: .dinner, dish: pasta, portion: .normal)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpAfterLog = state.totalXP

        // Édition : copieux + 2 bières + dessert gourmand = 845 + 300 + 300 = 1445.
        await service.updateMeal(
            entry: entry, slot: .dinner, dish: pasta, portion: .hearty,
            extras: [(beer, 2), (richDessert, 1)]
        )

        XCTAssertEqual(entry.estimatedKcal, 1445)
        XCTAssertEqual(entry.extras, ["beer": 2, "dessert_rich": 1])
        // PAS de nouvel XP : ni sur l'entrée, ni au total.
        XCTAssertEqual(entry.xpAwarded, 20)
        XCTAssertEqual(state.totalXP, xpAfterLog)

        // Le DayLog reflète le delta (650 → 1445), pas un cumul.
        let dayLog = try XCTUnwrap(try context.fetch(FetchDescriptor<DayLog>()).first)
        XCTAssertEqual(dayLog.kcalEaten, 1445)

        // Une seule entrée : l'édition ne duplique pas.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealEntry>()), 1)
    }

    func testDeleteMealSubtractsKcalAndKeepsXP() async throws {
        // Deux repas : 650 (déjeuner) + 455 (dîner léger : 650 × 0,7 = 455).
        let lunch = await service.logMeal(slot: .lunch, dish: pasta, portion: .normal)
        await service.logMeal(slot: .dinner, dish: pasta, portion: .light)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpBefore = state.totalXP

        await service.deleteMeal(entry: lunch)

        // Le DayLog perd les kcal du repas supprimé…
        let dayLog = try XCTUnwrap(try context.fetch(FetchDescriptor<DayLog>()).first)
        XCTAssertEqual(dayLog.kcalEaten, 455)
        // …mais l'XP est conservé (jamais de retrait, spec §7.1).
        XCTAssertEqual(state.totalXP, xpBefore)

        let remaining = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.slot, .dinner)
    }

    func testConsumeNextCelebrationDequeuesInOrderThenEmpties() async throws {
        let badge = try XCTUnwrap(try Catalogs.badges().first)
        let quest = try XCTUnwrap(service.questCatalog.first)

        // File vide → nil (et pas de crash).
        XCTAssertNil(service.consumeNextCelebration())

        service.pendingCelebrations = [.levelUp(2), .badge(badge), .quest(quest)]

        // Dépilage FIFO : l'ordre de levée est l'ordre d'affichage.
        XCTAssertEqual(service.consumeNextCelebration(), .levelUp(2))
        XCTAssertEqual(service.consumeNextCelebration(), .badge(badge))
        XCTAssertEqual(service.pendingCelebrations, [.quest(quest)])
        XCTAssertEqual(service.consumeNextCelebration(), .quest(quest))

        // File vidée → nil à nouveau.
        XCTAssertTrue(service.pendingCelebrations.isEmpty)
        XCTAssertNil(service.consumeNextCelebration())
    }

    func testWeighInXPIsCappedOncePerDay() async throws {
        let firstXP = await service.logWeight(kg: 90.5)
        XCTAssertEqual(firstXP, 30)

        let secondXP = await service.logWeight(kg: 90.3)
        XCTAssertEqual(secondXP, 0)

        let entries = try context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(entries.count, 2)

        // XP total = 30 (pesée) + 50 (badge "Première pesée").
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertEqual(state.totalXP, 80)
        XCTAssertNotNil(state.badgeUnlocks["first_weigh"])
    }
}

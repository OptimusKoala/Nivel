// NivelTests/HomeDashboardTests.swift
// Logique (pure) de l'accueil : contexte du message de Nivelito, statuts de quêtes,
// choix de la quête mise en avant.

import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class HomeDashboardTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.insert(GamificationState())
        try context.save()
        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
    }

    private func date(hour: Int) throws -> Date {
        try XCTUnwrap(GameService.calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: .now
        ))
    }

    // MARK: - homeMessageContext

    func testHomeMessageContextFollowsTimeOfDay() throws {
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .morning)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 12)).context, .midday)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 17)).context, .midday)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 18)).context, .evening)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 23)).context, .evening)
    }

    func testHomeMessageContextPrefersPendingLevelUpWithItsValue() throws {
        let badge = try XCTUnwrap(try Catalogs.badges().first)
        service.pendingCelebrations = [.badge(badge), .levelUp(3)]

        let result = service.homeMessageContext(now: try date(hour: 9))
        XCTAssertEqual(result.context, .levelUp)
        XCTAssertEqual(result.value, 3)
    }

    func testHomeMessageContextUsesBadgeWhenPendingOrUnlockedToday() throws {
        let badge = try XCTUnwrap(try Catalogs.badges().first)
        service.pendingCelebrations = [.badge(badge)]
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .badge)

        // File vidée (célébration affichée) mais badge débloqué AUJOURD'HUI → contexte badge.
        service.pendingCelebrations = []
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.badgeUnlocks = [badge.id: .now]
        try context.save()
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .badge)

        // Badge d'HIER → retour à la salutation horaire.
        state.badgeUnlocks = [badge.id: .now.addingTimeInterval(-86_400)]
        try context.save()
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .morning)
    }

    func testHomeMessageContextComebackAfterThreeDaysWithoutMeal() throws {
        // Dernier repas il y a 4 jours → comeback, quelle que soit l'heure.
        let fourDaysAgo = try XCTUnwrap(GameService.calendar.date(byAdding: .day, value: -4, to: .now))
        context.insert(MealEntry(date: fourDaysAgo, slot: .lunch, dishID: "pasta",
                                 portion: .normal, estimatedKcal: 650))
        try context.save()
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .comeback)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 20)).context, .comeback)

        // Un repas AUJOURD'HUI → retour à la salutation horaire.
        context.insert(MealEntry(date: try date(hour: 8), slot: .breakfast, dishID: "cereal",
                                 portion: .normal, estimatedKcal: 300))
        try context.save()
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 9)).context, .morning)
    }

    func testHomeMessageContextOverTargetOnlyInTheEvening() throws {
        context.insert(UserProfile(
            name: "Michaël", sex: .male,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180, initialWeightKg: 90, activity: .moderate,
            dailyCalorieTarget: 2000
        ))
        context.insert(MealEntry(date: try date(hour: 13), slot: .lunch, dishID: "pasta",
                                 portion: .hearty, estimatedKcal: 2500))
        try context.save()

        // Dépassé + soirée → overTarget ; en journée, salutation horaire normale.
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 20)).context, .overTarget)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 10)).context, .morning)
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 14)).context, .midday)

        // Sous l'objectif le soir → evening.
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        meals.forEach { $0.estimatedKcal = 500 }
        try context.save()
        XCTAssertEqual(try service.homeMessageContext(now: date(hour: 20)).context, .evening)
    }

    // MARK: - Bulle après log de repas

    func testLogMealPublishesAwardedXPForTheBubble() async throws {
        let dish = try XCTUnwrap(try Catalogs.dishes().first)
        await service.logMeal(slot: .lunch, dish: dish, portion: .normal)
        // 1er repas du jour → 20 XP, publiés pour la bulle "+{value} XP" de l'accueil.
        XCTAssertEqual(service.lastMealXPAwarded, 20)

        // 5ᵉ repas : XP plafonné → 0 publié (l'accueil n'affiche pas de bulle de récompense).
        for _ in 1...4 {
            await service.logMeal(slot: .snack, dish: dish, portion: .normal)
        }
        XCTAssertEqual(service.lastMealXPAwarded, 0)
    }

    // MARK: - Quêtes

    func testActiveQuestStatusesReflectStateAndCompletion() throws {
        let quests = try Catalogs.quests()
        let first = try XCTUnwrap(quests.first)
        let second = try XCTUnwrap(quests.dropFirst().first)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.activeQuestIDs = [first.id, second.id, "unknown_quest"]
        state.questProgress = [first.id: 2]
        state.completedThisWeekQuestIDs = [second.id]
        try context.save()

        let statuses = service.activeQuestStatuses()
        // L'id inconnu est ignoré, l'ordre du tirage est conservé.
        XCTAssertEqual(statuses.map(\.id), [first.id, second.id])
        XCTAssertEqual(statuses[0].progress, 2)
        XCTAssertFalse(statuses[0].isCompleted)
        XCTAssertEqual(statuses[1].progress, 0)
        XCTAssertTrue(statuses[1].isCompleted)
    }

    func testFeaturedQuestPicksMostAdvancedNonCompleted() throws {
        let quests = try Catalogs.quests()
        let a = try XCTUnwrap(quests.first)          // fraction 0,25
        let b = try XCTUnwrap(quests.dropFirst().first)  // fraction 0,75 → mise en avant
        let c = try XCTUnwrap(quests.dropFirst(2).first) // complétée → exclue

        let statuses = [
            ActiveQuestStatus(quest: a, progress: a.target / 4, isCompleted: false),
            ActiveQuestStatus(quest: b, progress: b.target * 3 / 4, isCompleted: false),
            ActiveQuestStatus(quest: c, progress: c.target, isCompleted: true),
        ]
        XCTAssertEqual(HomeView.featuredQuest(from: statuses)?.id, b.id)

        // Toutes complétées → carte masquée.
        let allDone = statuses.map {
            ActiveQuestStatus(quest: $0.quest, progress: $0.quest.target, isCompleted: true)
        }
        XCTAssertNil(HomeView.featuredQuest(from: allDone))
    }
}

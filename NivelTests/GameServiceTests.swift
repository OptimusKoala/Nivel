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
            DayLog.self, GamificationState.self
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

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))

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
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
        let sixth = await restarted.logMeal(slot: .snack, dish: pasta, portion: .normal)
        XCTAssertEqual(sixth.xpAwarded, 0)
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

import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class SportServiceTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!
    private var walk: Activity!
    private var session: ActivitySession!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.insert(UserProfile(
            name: "Michaël", sex: .male, birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 180, initialWeightKg: 90, activity: .moderate, dailyCalorieTarget: 2000
        ))
        context.insert(GamificationState())
        try context.save()

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
        walk = try XCTUnwrap(service.activityCatalog.first { $0.id == "walk" })
        session = try XCTUnwrap(service.sessionCatalog.first { $0.id == "wake_up" })
    }

    func testLogActivityAwardsCappedXPAndSurvivesRestart() async throws {
        var awarded: [Int] = []
        for _ in 1...3 {
            let entry = await service.logActivity(activity: walk, durationMinutes: 20)
            awarded.append(entry.xpAwarded)
        }
        XCTAssertEqual(awarded, [30, 30, 0])
        XCTAssertEqual(service.lastActivityXPAwarded, 0)

        // Le plafond est dérivé des ActivityEntry persistées → tient à la "relance".
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
        let fourth = await restarted.logActivity(activity: walk, durationMinutes: 10)
        XCTAssertEqual(fourth.xpAwarded, 0)

        // kcal estimées : 20 min × 4,0 = 80 ; PAS de DayLog créé (jamais crédité au budget).
        let first = try XCTUnwrap(try context.fetch(FetchDescriptor<ActivityEntry>(
            sortBy: [SortDescriptor(\.date)])).first)
        XCTAssertEqual(first.estimatedKcal, 80)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DayLog>()).isEmpty)
    }

    func testDailySessionXPCappedAtOnePerDayIndependentlyOfActivities() async throws {
        _ = await service.logActivity(activity: walk, durationMinutes: 10)     // n'entame pas le plafond séance
        let first = await service.logDailySession(session: session)
        let second = await service.logDailySession(session: session)
        XCTAssertEqual(first.xpAwarded, 40)
        XCTAssertEqual(first.estimatedKcal, 40)   // 4×2,5 + 4×5,5 + 3×4,0 = 44 → 40
        XCTAssertEqual(first.durationMinutes, session.totalMinutes)
        XCTAssertEqual(second.xpAwarded, 0)
    }

    func testSportQuestsProgressAndComplete() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["activities_3", "daily_sessions_2"]
        try context.save()

        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        XCTAssertEqual(state.questProgress["activities_3"], 2)

        // La séance du jour compte pour LES DEUX métriques (c'est une activité aussi).
        _ = await service.logDailySession(session: session)
        XCTAssertEqual(state.questProgress["activities_3"], 3)
        XCTAssertEqual(state.questProgress["daily_sessions_2"], 1)
        XCTAssertTrue(state.completedThisWeekQuestIDs.contains("activities_3"))
        XCTAssertTrue(service.pendingCelebrations.contains { $0.id == "quest-activities_3" })
    }

    func testFirstActivityUnlocksSportBadge() async throws {
        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        XCTAssertNotNil(state.badgeUnlocks["sport_first"])
        XCTAssertTrue(service.pendingCelebrations.contains {
            if case .badge(let badge) = $0 { badge.id == "sport_first" } else { false }
        })
    }

    func testDeleteActivityKeepsXPAndRemovesEntry() async throws {
        let entry = await service.logActivity(activity: walk, durationMinutes: 10)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        let xpBefore = state.totalXP
        await service.deleteActivity(entry: entry)
        XCTAssertEqual(state.totalXP, xpBefore)   // jamais de retrait d'XP
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivityEntry>()).isEmpty)
    }

    func testDailySessionStatusFlipsToDone() async throws {
        let before = try XCTUnwrap(service.dailySessionStatus())
        XCTAssertFalse(before.done)
        _ = await service.logDailySession(session: before.session)
        let after = try XCTUnwrap(service.dailySessionStatus())
        XCTAssertEqual(after.session.id, before.session.id)
        XCTAssertTrue(after.done)
    }
}

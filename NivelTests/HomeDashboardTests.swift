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

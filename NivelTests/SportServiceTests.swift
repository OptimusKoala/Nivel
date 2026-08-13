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

        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: nil)
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
        let restarted = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                                    widgetDefaults: nil)
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

    func testDoubleDailySessionSameDayCountsOnceForQuestsAndBadges() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["daily_sessions_2"]
        try context.save()

        _ = await service.logDailySession(session: session)
        _ = await service.logDailySession(session: session)
        XCTAssertEqual(state.questProgress["daily_sessions_2"], 1)
        XCTAssertEqual(service.badgeStats().dailySessionsDone, 1)
        XCTAssertFalse(state.completedThisWeekQuestIDs.contains("daily_sessions_2"))
    }

    func testDeleteActivityLowersQuestProgressAndSessionDone() async throws {
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["activities_3"]
        try context.save()

        _ = await service.logActivity(activity: walk, durationMinutes: 10)
        let second = await service.logActivity(activity: walk, durationMinutes: 10)
        XCTAssertEqual(state.questProgress["activities_3"], 2)

        await service.deleteActivity(entry: second)
        XCTAssertEqual(state.questProgress["activities_3"], 1)

        let sessionEntry = await service.logDailySession(session: session)
        XCTAssertTrue(try XCTUnwrap(service.dailySessionStatus()).done)
        await service.deleteActivity(entry: sessionEntry)
        XCTAssertFalse(try XCTUnwrap(service.dailySessionStatus()).done)
    }

    /// Épingle le contrat d'ordre de `logSport` (insert AVANT le premier await) :
    /// trois validations concurrentes (tap-tap-tap) ne doivent jamais dépasser le
    /// plafond de 2 activités récompensées/jour, même en vol simultané. On force
    /// `refreshQuestProgress` à suspendre sur une quête de pas (`steps_25k`) pour
    /// que les trois tâches s'entrelacent réellement sur le MainActor.
    func testConcurrentLogActivityRespectsCapEvenWhileSuspended() async throws {
        let slowSteps = SlowStepsService()
        let concurrentService = GameService(modelContext: context, stepsService: slowSteps,
                                            widgetDefaults: nil)
        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<GamificationState>()).first)
        state.questWeekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        state.activeQuestIDs = ["steps_25k"]
        try context.save()

        async let a = concurrentService.logActivity(activity: walk, durationMinutes: 10)
        async let b = concurrentService.logActivity(activity: walk, durationMinutes: 10)
        async let c = concurrentService.logActivity(activity: walk, durationMinutes: 10)
        let entries = await [a, b, c]
        let awarded = entries.map(\.xpAwarded).sorted()
        XCTAssertEqual(awarded, [0, 30, 30])   // le plafond tient même en vol simultané
    }

    /// Une entrée muscu porte un id de SÉANCE (comme `.dailySession` et `.posture`),
    /// résoluble via le catalogue muscu du service — et par LUI SEUL : aucun id
    /// `muscu_*` n'existe dans `activitiesByID`, c'est pourquoi `doneRow` n'y a pas
    /// de repli intermédiaire. Sans cette résolution, la liste du jour afficherait
    /// « muscu_core » en dur, ce qu'aucune compilation ne signalerait.
    func testEntreeMuscuResolubleParSonTitre() async throws {
        let muscu = try XCTUnwrap(service.muscuCatalog.sessions.first { $0.id == "muscu_core" })
        let entry = await service.logMuscuSession(session: muscu)

        XCTAssertEqual(entry.refID, "muscu_core")
        XCTAssertEqual(service.muscuCatalog.sessions.first { $0.id == entry.refID }?.title,
                       muscu.title)
        XCTAssertNotEqual(muscu.title, "muscu_core")
        XCTAssertNil(service.activitiesByID[entry.refID])
        XCTAssertTrue(service.todayActivities().contains { $0.id == entry.id })
        XCTAssertTrue(try XCTUnwrap(service.muscuSessionStatus()).done)
    }
}

/// StepsProviding disponible mais lent (simule l'attente HealthKit) — force
/// `refreshQuestProgress` à suspendre sur `await dailySteps(...)`, condition
/// nécessaire pour que les tâches concurrentes s'entrelacent réellement.
private final class SlowStepsService: StepsProviding {
    var isAvailable: Bool { true }
    func requestAuthorization() async -> Bool { true }
    func steps(on day: Date) async -> Int? { 0 }
    func dailySteps(from: Date, to: Date) async -> [Date: Int]? {
        try? await Task.sleep(nanoseconds: 50_000_000)
        return [:]
    }
}

// NivelTests/WidgetSyncTests.swift
// WidgetBridge (spec widgets §3.2) : le snapshot circule par les UserDefaults
// partagés. Suite dédiée par test, comme ThemeStoreTests.

import XCTest
import SwiftData
import NivelCore
@testable import Nivel

final class WidgetBridgeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.widget.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        let snapshot = WidgetSnapshot(dayKey: Date(timeIntervalSinceReferenceDate: 0),
                                      kcalEaten: 500, kcalTarget: 1800, totalXP: 42,
                                      userName: "Marion", themeID: "ocean",
                                      generatedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        WidgetBridge.save(snapshot, to: defaults)
        XCTAssertEqual(WidgetBridge.load(from: defaults), snapshot)
    }

    func testLoadReturnsNilWhenNothingStored() {
        XCTAssertNil(WidgetBridge.load(from: defaults))
    }

    /// Charge utile illisible (format d'une version antérieure, écriture
    /// tronquée) : le widget retombe sur son état d'accueil, jamais de crash.
    func testLoadReturnsNilWhenPayloadIsCorrupted() {
        defaults.set(Data("pas du json".utf8), forKey: WidgetBridge.snapshotKey)
        XCTAssertNil(WidgetBridge.load(from: defaults))
    }
}

/// Construction du snapshot depuis l'état SwiftData (spec widgets §5) : conteneur
/// en mémoire, comme GameServiceTests.
@MainActor
final class WidgetSnapshotBuildingTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false))
    }

    func testNilWhileOnboardingNotDone() {
        // Pas de profil inséré : pas de snapshot (spec widgets §5).
        XCTAssertNil(service.makeWidgetSnapshot(themeID: "creme"))
    }

    func testSnapshotReflectsMealAndProfile() async throws {
        let profile = UserProfile(name: "Michaël", sex: .male,
                                  birthDate: Date(timeIntervalSince1970: 0),
                                  heightCm: 180, initialWeightKg: 90,
                                  activity: .moderate, dailyCalorieTarget: 2000)
        context.insert(profile)
        context.insert(GamificationState())
        try context.save()

        let dishes = try Catalogs.dishes()
        let pasta = try XCTUnwrap(dishes.first { $0.id == "pasta" })
        await service.logMeal(slot: .lunch, dish: pasta, portion: .normal, extras: [])

        let snapshot = try XCTUnwrap(service.makeWidgetSnapshot(themeID: "nuit-douce"))
        XCTAssertEqual(snapshot.dayKey, GameService.dayKey(for: .now))
        XCTAssertGreaterThan(snapshot.kcalEaten, 0)
        XCTAssertEqual(snapshot.kcalTarget, 2000)
        XCTAssertGreaterThan(snapshot.totalXP, 0)
        XCTAssertEqual(snapshot.userName, "Michaël")
        XCTAssertEqual(snapshot.themeID, "nuit-douce")
    }
}

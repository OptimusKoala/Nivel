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
/// en mémoire comme GameServiceTests, et suite UserDefaults dédiée par test
/// (`widgetDefaults` injecté) pour ne jamais écrire dans le vrai App Group.
@MainActor
final class WidgetSnapshotBuildingTests: XCTestCase {
    private var context: ModelContext!
    private var service: GameService!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        let schema = Schema([
            UserProfile.self, MealEntry.self, WeightEntry.self,
            DayLog.self, GamificationState.self, ActivityEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        suiteName = "nivel.tests.widgetsync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = GameService(modelContext: context, stepsService: FakeStepsService(authorized: false),
                              widgetDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNilWhileOnboardingNotDone() {
        // Pas de profil inséré : pas de snapshot (spec widgets §5).
        XCTAssertNil(service.makeWidgetSnapshot(themeID: "creme"))
    }

    func testSnapshotReflectsMealAndProfile() async throws {
        try insertProfileAndState()

        // Journée FIXE (pas de `.now` : aucun flake au passage de minuit) : le repas
        // est loggé à midi, le snapshot construit à 23 h 30 le même jour.
        let day = try XCTUnwrap(GameService.calendar.date(from: DateComponents(year: 2026, month: 3, day: 14)))
        let noon = try XCTUnwrap(GameService.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
        let evening = try XCTUnwrap(GameService.calendar.date(bySettingHour: 23, minute: 30, second: 0, of: day))
        let pasta = try pastaDish()
        await service.logMeal(slot: .lunch, dish: pasta, portion: .normal, extras: [], date: noon)

        let snapshot = try XCTUnwrap(service.makeWidgetSnapshot(themeID: "nuit-douce", now: evening))
        // 23 h 30 normalisé en minuit local : c'est la clé du jour, pas l'instant.
        XCTAssertEqual(snapshot.dayKey, day)
        XCTAssertGreaterThan(snapshot.kcalEaten, 0)
        XCTAssertEqual(snapshot.kcalTarget, 2000)
        XCTAssertGreaterThan(snapshot.totalXP, 0)
        XCTAssertEqual(snapshot.userName, "Michaël")
        XCTAssertEqual(snapshot.themeID, "nuit-douce")
    }

    /// Le crochet saveOrAssert écrit un snapshot cohérent dans la suite injectée
    /// (spec §10) : logMeal → syncWidget → WidgetBridge.load. Repas daté du jour
    /// courant, sinon `kcalEaten` (calculé sur aujourd'hui) serait nul.
    /// `themeID` n'est PAS asserté : il vient du ThemeStore de l'app hôte des
    /// tests, donc du device.
    func testLogMealWritesSnapshotThroughSaveHook() async throws {
        try insertProfileAndState()
        XCTAssertNil(WidgetBridge.load(from: defaults))

        let pasta = try pastaDish()
        await service.logMeal(slot: .lunch, dish: pasta, portion: .normal, extras: [])

        let written = try XCTUnwrap(WidgetBridge.load(from: defaults))
        XCTAssertEqual(written.dayKey, GameService.dayKey(for: .now))
        XCTAssertGreaterThan(written.kcalEaten, 0)
        XCTAssertEqual(written.kcalTarget, 2000)
        XCTAssertEqual(written.userName, "Michaël")
    }

    /// Onboarding terminé : profil + état, sauvegardés SANS passer par
    /// `saveOrAssert` (aucun snapshot écrit avant l'action testée).
    private func insertProfileAndState() throws {
        let profile = UserProfile(name: "Michaël", sex: .male,
                                  birthDate: Date(timeIntervalSince1970: 0),
                                  heightCm: 180, initialWeightKg: 90,
                                  activity: .moderate, dailyCalorieTarget: 2000)
        context.insert(profile)
        context.insert(GamificationState())
        try context.save()
    }

    private func pastaDish() throws -> Dish {
        let dishes = try Catalogs.dishes()
        return try XCTUnwrap(dishes.first { $0.id == "pasta" })
    }
}

// NivelTests/MuscuPlanSettingsTests.swift
// Interrupteur du programme muscu, par appareil (spec v1.14 §4.4). Miroir de
// PosturePlanTests : mêmes garanties, second programme. Pas de test d'extinction en
// cours de semaine ici — aucune quête ne dépend du programme muscu.

import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class MuscuPlanSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        // Suite dédiée par cas de test : jamais les vrais réglages de l'appareil.
        suiteName = "nivel.tests.muscu.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        super.tearDown()
    }

    private func makeProfile() -> UserProfile {
        let profile = UserProfile(name: "Test", sex: .male,
                                  birthDate: Date(timeIntervalSince1970: 0),
                                  heightCm: 180, initialWeightKg: 90,
                                  activity: .moderate, dailyCalorieTarget: 2000)
        container.mainContext.insert(profile)
        return profile
    }

    private func makeSettings() -> MuscuPlanSettings {
        MuscuPlanSettings(defaults: defaults)
    }

    // MARK: - Persistance de base (miroir de PosturePlanTests)

    /// Éteint par défaut, comme la posture : un programme n'existe que sur le
    /// téléphone qui l'allume.
    func testEteintParDefaut() {
        XCTAssertFalse(makeSettings().isEnabled)
    }

    func testLeChoixEstPersiste() {
        makeSettings().isEnabled = true
        XCTAssertTrue(makeSettings().isEnabled)
    }

    /// `false` persisté doit survivre : `object(forKey:)` et non `bool(forKey:)`,
    /// sinon on ne peut pas distinguer "jamais réglé" de "réglé à false" (ici les
    /// deux valent faux, donc le test bascule d'abord à vrai pour les distinguer).
    func testFauxPersisteNEstPasConfonduAvecLAbsence() {
        defaults.set(true, forKey: MuscuPlanSettings.defaultsKey)
        XCTAssertTrue(makeSettings().isEnabled)
        defaults.set(false, forKey: MuscuPlanSettings.defaultsKey)
        XCTAssertFalse(makeSettings().isEnabled)
        defaults.removeObject(forKey: MuscuPlanSettings.defaultsKey)
        XCTAssertFalse(makeSettings().isEnabled)
    }

    // MARK: - Le piège du rappel muet (spec v1.9 : clé absente = désactivé)

    /// Le piège de la v1.9 : une clé absente de `remindersEnabled` vaut
    /// désactivée, donc allumer le programme sans toucher le rappel le laisserait
    /// éteint.
    func testAllumerActiveAussiLeRappel() {
        let settings = makeSettings()
        let profile = makeProfile()
        settings.setEnabled(true, on: profile)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(profile.remindersEnabled["muscu"], true)
        settings.setEnabled(false, on: profile)
        XCTAssertEqual(profile.remindersEnabled["muscu"], false)
    }

    /// Les deux programmes ne se marchent pas dessus : allumer la muscu ne touche
    /// pas au rappel posture.
    func testNeTouchePasAuRappelPosture() {
        let settings = makeSettings()
        let profile = makeProfile()
        settings.setEnabled(true, on: profile)
        XCTAssertNil(profile.remindersEnabled["posture"])
    }
}

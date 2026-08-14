// NivelTests/MuscuPlanSettingsTests.swift
// Interrupteur du programme muscu, par appareil (spec v1.14 §4.4). Miroir de
// PosturePlanTests : mêmes garanties, second programme — y compris l'extinction en
// cours de semaine, depuis que trois quêtes dépendent du programme (spec §5.7).

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

    // MARK: - Extinction en cours de semaine (spec v1.14 §5.7 : aucune purge de quête)

    /// Miroir du test posture, depuis que les trois quêtes muscu existent : éteindre le
    /// programme alors qu'une quête muscu est active pour la semaine ne doit RIEN faire
    /// de plus que le rappel et l'affichage. La quête reste à sa progression, ne se
    /// complète pas, et le lundi suivant en tire une autre — la retirer de force serait
    /// la seule fois où l'app reprendrait quelque chose.
    func testEteindreEnCoursDeSemaineNePurgePasLesQuetes() throws {
        let settings = makeSettings()
        let profile = makeProfile()
        let state = GamificationState(
            totalXP: 200,
            activeQuestIDs: ["muscu_sessions_3"],
            questWeekID: "2026-W32",
            questProgress: ["muscu_sessions_3": 2]
        )
        container.mainContext.insert(state)
        try container.mainContext.save()

        settings.setEnabled(true, on: profile)
        settings.setEnabled(false, on: profile)

        XCTAssertEqual(state.activeQuestIDs, ["muscu_sessions_3"])
        XCTAssertEqual(state.questProgress["muscu_sessions_3"], 2)
    }
}

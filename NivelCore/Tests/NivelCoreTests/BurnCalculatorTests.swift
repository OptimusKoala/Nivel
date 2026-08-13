// NivelCore/Tests/NivelCoreTests/BurnCalculatorTests.swift
// Dépense du jour (spec §5.4) : pas + activités NON marchées. Le double comptage
// est silencieux — c'est cette suite, et elle seule, qui l'empêche.
import XCTest
@testable import NivelCore

final class BurnCalculatorTests: XCTestCase {
    private let weight = 90.0

    private func activities() throws -> [String: Activity] {
        Dictionary(uniqueKeysWithValues: try Catalogs.activities().map { ($0.id, $0) })
    }
    private func sessions() throws -> [String: ActivitySession] {
        Dictionary(uniqueKeysWithValues: try Catalogs.sessions().map { ($0.id, $0) })
    }

    func testPasSeuls() throws {
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411)   // 8000 x 0,04 x 90/70
    }

    func testActiviteMaisonSAjoute() throws {
        let entry = BurnEntry(kind: .activity, refID: "pushups", estimatedKcal: 35)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411 + 35)
    }

    /// LE cas qui motive tout : une marche validée est déjà dans les pas.
    func testMarcheNonCompteeDeuxFois() throws {
        let entry = BurnEntry(kind: .activity, refID: "walk", estimatedKcal: 160)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411, "la marche entre par les pas, pas deux fois")
    }

    /// `.measured(0)` (pas mesurés, et il n'y en a eu aucun) n'est PAS `.unavailable`
    /// (pas indisponibles) : la marche reste exclue, contrairement au cas sans HealthKit.
    func testPasAZeroExcluQuandMemeLaMarche() throws {
        let entry = BurnEntry(kind: .activity, refID: "walk", estimatedKcal: 160)
        let kcal = BurnCalculator.kcal(steps: .measured(0), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 0)
    }

    /// `fresh_air` est une marche de 15 min : la séance ne doit RIEN ajouter.
    func testSeanceEntierementMarcheeNAjouteRien() throws {
        let entry = BurnEntry(kind: .dailySession, refID: "fresh_air", estimatedKcal: 60)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411)
    }

    /// `home_cardio` mélange escaliers (marchés) et squats + étirements (non).
    /// 6x8 = 48 marchés, exclus ; 3x5,5 + 4x2,5 = 26,5 gardés.
    func testSeanceMixteEstDecomposee() throws {
        let entry = BurnEntry(kind: .dailySession, refID: "home_cardio", estimatedKcal: 74)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411 + 27, "26,5 arrondi une seule fois, a la fin")
    }

    /// Deux `home_cardio` le même jour : chaque séance vaut 26,5 kcal gardés, soit 53
    /// exactement une fois sommées. Arrondir séance par séance donnerait 27 + 27 = 54 :
    /// ce test tue la dérive d'un arrondi déplacé dans la boucle.
    func testArrondiUniqueSurPlusieursSeances() throws {
        let entries = [BurnEntry(kind: .dailySession, refID: "home_cardio", estimatedKcal: 74),
                       BurnEntry(kind: .dailySession, refID: "home_cardio", estimatedKcal: 74)]
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: entries,
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411 + 53, "26,5 + 26,5 = 53 pile, pas 27 + 27 = 54")
    }

    /// Séance retirée du catalogue depuis : repli sur le total stocké plutôt que
    /// de faire disparaître une dépense réelle.
    func testSeanceInconnueSeReplieSurLeTotalStocke() throws {
        let entry = BurnEntry(kind: .muscu, refID: "disparue", estimatedKcal: 120)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411 + 120)
    }

    /// Séance CONNUE, mais dont AUCUNE étape ne se résout dans `activitiesByID` :
    /// même repli que l'id de séance inconnu. Raisonnement complet dans la source,
    /// à côté du `guard resolvedSteps == session.steps.count`.
    func testSeanceConnueMaisActivitesIntrouvablesSeReplie() throws {
        let ghost = ActivitySession(id: "spectre", title: "Spectre",
                                     steps: [SessionStep(activityID: "inconnue1", minutes: 10, tempo: "x"),
                                             SessionStep(activityID: "inconnue2", minutes: 5, tempo: "y")])
        var sessionsByID = try sessions()
        sessionsByID[ghost.id] = ghost
        let entry = BurnEntry(kind: .dailySession, refID: ghost.id, estimatedKcal: 80)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: sessionsByID)
        XCTAssertEqual(kcal, 411 + 80)
    }

    /// Séance CONNUE dont une SEULE étape sur deux se résout (l'autre introuvable) :
    /// décomposition PARTIELLE, donc repli — pas un décompte à moitié qui rendrait 0
    /// en silence parce que la seule étape résolue est justement marchée. Même
    /// raisonnement que le test précédent, version incomplète plutôt que totale.
    func testSeancePartiellementResolueSeReplie() throws {
        let partial = ActivitySession(id: "partielle", title: "Partielle",
                                       steps: [SessionStep(activityID: "stairs", minutes: 6, tempo: "x"),
                                               SessionStep(activityID: "inconnue", minutes: 5, tempo: "y")])
        var sessionsByID = try sessions()
        sessionsByID[partial.id] = partial
        let entry = BurnEntry(kind: .dailySession, refID: partial.id, estimatedKcal: 90)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: sessionsByID)
        XCTAssertEqual(kcal, 411 + 90, "l'unique etape resolue est marchee : pas de 0 par defaut")
    }

    /// Activité (et non séance) inconnue du catalogue : compte pour son total stocké,
    /// symétrique au repli de séance. Verrouille le `?? false` de `isWalking` contre
    /// un `?? true` qui effacerait en silence toute activité dont l'id a disparu.
    func testActiviteInconnueCompteQuandMemePourSonTotal() throws {
        let entry = BurnEntry(kind: .activity, refID: "disparue", estimatedKcal: 90)
        let kcal = BurnCalculator.kcal(steps: .measured(8000), weightKg: weight, entries: [entry],
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 411 + 90)
    }

    /// HealthKit refusé : plus de doublon possible, donc TOUT compte — une
    /// dépense amputée serait un mensonge par omission.
    func testSansPasToutCompte() throws {
        let entries = [BurnEntry(kind: .activity, refID: "walk", estimatedKcal: 160),
                       BurnEntry(kind: .dailySession, refID: "fresh_air", estimatedKcal: 60)]
        let kcal = BurnCalculator.kcal(steps: .unavailable, weightKg: weight, entries: entries,
                                      activitiesByID: try activities(),
                                      sessionsByID: try sessions())
        XCTAssertEqual(kcal, 220)
    }

    func testRienDuTout() throws {
        let kcal = BurnCalculator.kcal(steps: .unavailable, weightKg: weight, entries: [],
                                       activitiesByID: try activities(),
                                       sessionsByID: try sessions())
        XCTAssertEqual(kcal, 0)
    }
}

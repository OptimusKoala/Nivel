// NivelTests/LevelMigrationTests.swift
// Recharge d'XP au premier lancement de la 1.14 (spec §5.2). Un bug ici fait
// perdre un niveau sans moyen de le retrouver : cette suite passe AVANT le code.

import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class LevelMigrationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try Self.makeContainer()
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// Monte un état COMME LE FERAIT UN STORE D'AVANT LA 1.14 : `levelCurveVersion`
    /// est forcé après coup, puisque l'init de la 1.14 fait naître les états en
    /// version 2.
    ///
    /// ⚠️ ORDRE VOLONTAIRE : le service est construit AVANT que l'état existe. L'init
    /// migre déjà (c'est tout l'intérêt), donc l'insérer d'abord ferait sortir la
    /// migration sur `version == 2` à chaque appel explicite des tests, qui
    /// deviendraient inertes — prouvé par mutation : commentés, ils laissaient la
    /// cible verte. Sans état en base, l'init ne fait rien, et le
    /// `migrateLevelCurveIfNeeded()` du test redevient le PREMIER appel réel.
    /// Le chemin de l'init reste couvert, une fois, par
    /// `testLInitDuServiceMigreDejaSansAppelExplicite`.
    private func makeService(totalXP: Int, curveVersion: Int) -> (GameService, GamificationState) {
        let context = container.mainContext
        let service = GameService(modelContext: context,
                                  stepsService: FakeStepsService(authorized: false),
                                  widgetDefaults: nil)
        let state = GamificationState(totalXP: totalXP)
        state.levelCurveVersion = curveVersion
        context.insert(state)
        try? context.save()
        return (service, state)
    }

    // MARK: - Le cas nominal : personne ne descend

    /// Le cas de Michaël : niveau 13 sous l'ancienne courbe (3 000 XP).
    /// Sans recharge il retomberait au niveau 6.
    func testUnJoueurExistantGardeSonNiveau() {
        let (service, state) = makeService(totalXP: 3000, curveVersion: 1)
        XCTAssertEqual(LevelSystem.legacyLevel(forXP: 3000), 13)
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(LevelSystem.level(forXP: state.totalXP), 13)
        XCTAssertEqual(state.totalXP, LevelSystem.xpRequired(forLevel: 13))  // 16 569
        XCTAssertEqual(state.levelCurveVersion, 2)
    }

    /// Une deuxième exécution ne doit RIEN recharger : sinon chaque lancement
    /// offrirait un niveau.
    ///
    /// La première recharge est assertée en VALEUR et pas seulement comparée à la
    /// seconde : deux appels qui ne feraient rien du tout se vaudraient aussi, et le
    /// test passerait sur une migration morte.
    func testLaMigrationNeSexecuteQuUneFois() {
        let (service, state) = makeService(totalXP: 3000, curveVersion: 1)
        service.migrateLevelCurveIfNeeded()
        let apresLaPremiere = state.totalXP
        XCTAssertEqual(apresLaPremiere, LevelSystem.xpRequired(forLevel: 13))
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(state.totalXP, apresLaPremiere)
    }

    /// Un profil neuf n'est pas touché : 0 XP reste 0 XP, pas de cadeau. La version
    /// est quand même tamponnée — c'est ce qui prouve que la migration a bien tourné
    /// ici, et pas seulement qu'elle n'a rien cassé.
    func testUnProfilNeufNEstPasTouche() {
        let (service, state) = makeService(totalXP: 0, curveVersion: 1)
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(state.totalXP, 0)
        XCTAssertEqual(LevelSystem.level(forXP: state.totalXP), 1)
        XCTAssertEqual(state.levelCurveVersion, 2)
    }

    // MARK: - Le trou de l'installation neuve

    /// LE test qui ferme le trou le plus vicieux du lot. `GameService` se construit
    /// au lancement, AVANT l'onboarding : l'état de gamification n'existe pas
    /// encore. S'il naissait ensuite en version 1, le lancement suivant
    /// « rechargerait » une XP déjà gagnée sous la NOUVELLE courbe — 3 000 XP
    /// deviendraient 16 569, sept niveaux offerts sans rien faire.
    func testUnEtatNeufNaitSurLaNouvelleCourbe() {
        let state = GamificationState()
        XCTAssertEqual(state.levelCurveVersion, 2,
                       "un état créé par le code de la 1.14 n'est jamais candidat à la recharge")
    }

    /// Le scénario complet d'une installation neuve : état créé par l'onboarding,
    /// XP gagnée normalement, relance. Rien ne bouge.
    func testUneInstallationNeuveQuiGagneDeLXPNEstJamaisMigree() {
        let context = container.mainContext
        // Service d'abord, comme au vrai lancement : il se construit AVANT
        // l'onboarding, donc avant que l'état existe (même ordre que `makeService`).
        let service = GameService(modelContext: context,
                                  stepsService: FakeStepsService(authorized: false),
                                  widgetDefaults: nil)
        let state = GamificationState()          // comme l'onboarding le crée
        context.insert(state)
        state.totalXP = 3000                     // trois semaines de jeu, nouvelle courbe
        try? context.save()
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(state.totalXP, 3000, "aucun niveau offert")
        XCTAssertEqual(LevelSystem.level(forXP: state.totalXP), 6)
    }

    /// Aucun état en base (avant l'onboarding) : construire le service ne doit rien
    /// insérer — `fetchState` et non `fetchOrCreateState` (invariant du snapshot
    /// widget). La migration ne fait simplement rien.
    func testSansEtatEnBaseLaMigrationNInsereRien() {
        let context = container.mainContext
        let service = GameService(modelContext: context,
                                  stepsService: FakeStepsService(authorized: false),
                                  widgetDefaults: nil)
        service.migrateLevelCurveIfNeeded()
        let etats = (try? context.fetch(FetchDescriptor<GamificationState>())) ?? []
        XCTAssertTrue(etats.isEmpty, "la migration ne crée jamais d'état de gamification")
    }

    // MARK: - La recharge ne retire jamais rien

    /// La recharge ne RETIRE jamais d'XP, même là où la nouvelle courbe est plus
    /// GÉNÉREUSE (niveaux 2 à 4) : `max` et non affectation sèche. À 500 XP par
    /// exemple — ancien niveau 3, seuil neuf de 322 — une affectation ferait perdre
    /// 178 XP sans changer le niveau affiché : une perte invisible, donc jamais
    /// signalée par personne.
    ///
    /// Oracle EXACT (`max(xp, xpRequired(legacyLevel(xp)))`) et non deux inégalités :
    /// une borne se satisfait par accident, une égalité non.
    func testUneXPDejaAuDessusDuSeuilNeufNeBougePas() throws {
        for xp in [70, 100, 300, 322, 500, 784] {
            // Un conteneur NEUF par cas : `fetchState()` rend le PREMIER état trouvé,
            // et deux états dans le même store feraient migrer le mauvais — le test
            // passerait alors sans rien avoir vérifié.
            container = try Self.makeContainer()
            let (service, state) = makeService(totalXP: xp, curveVersion: 1)
            let attendu = max(xp, LevelSystem.xpRequired(forLevel: LevelSystem.legacyLevel(forXP: xp)))
            service.migrateLevelCurveIfNeeded()
            XCTAssertEqual(state.totalXP, attendu, "XP fausse après migration à \(xp) XP")
            XCTAssertGreaterThanOrEqual(LevelSystem.level(forXP: state.totalXP),
                                        LevelSystem.legacyLevel(forXP: xp),
                                        "descente de niveau à \(xp) XP")
        }
    }

    /// Un joueur déjà migré (version 2) n'est jamais retouché, quel que soit son XP.
    func testUnJoueurDejaMigreEstIgnore() {
        let (service, state) = makeService(totalXP: 500, curveVersion: 2)
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(state.totalXP, 500)
    }

    // MARK: - Ce que la migration ne touche pas (spec §5.2)

    /// Badges déjà obtenus, quêtes en cours, historique : la recharge ne recalcule
    /// rien de tout ça. Un badge Niveau 10 obtenu sous l'ancienne courbe le reste.
    func testLaMigrationNeToucheNiAuxBadgesNiAuxQuetes() {
        let context = container.mainContext
        let service = GameService(modelContext: context,
                                  stepsService: FakeStepsService(authorized: false),
                                  widgetDefaults: nil)
        let obtenuLe = Date(timeIntervalSince1970: 1_700_000_000)
        let state = GamificationState(totalXP: 3000,
                                      badgeUnlocks: ["level_10": obtenuLe],
                                      activeQuestIDs: ["q1", "q2"],
                                      questWeekID: "2026-W33",
                                      questProgress: ["q1": 2],
                                      completedQuestIDs: ["q0"],
                                      completedThisWeekQuestIDs: ["q0"])
        state.levelCurveVersion = 1
        context.insert(state)
        try? context.save()
        service.migrateLevelCurveIfNeeded()
        // La recharge a bien EU LIEU (sans quoi ce test passerait sur une migration
        // morte) — et n'a pourtant touché à rien de ce qui suit.
        XCTAssertEqual(state.totalXP, LevelSystem.xpRequired(forLevel: 13))
        XCTAssertEqual(state.badgeUnlocks, ["level_10": obtenuLe])
        XCTAssertEqual(state.activeQuestIDs, ["q1", "q2"])
        XCTAssertEqual(state.questWeekID, "2026-W33")
        XCTAssertEqual(state.questProgress, ["q1": 2])
        XCTAssertEqual(state.completedQuestIDs, ["q0"])
        XCTAssertEqual(state.completedThisWeekQuestIDs, ["q0"])
    }

    /// La migration tourne à la CONSTRUCTION du service, avant tout affichage :
    /// personne ne doit pouvoir voir un niveau faux, fût-ce une fraction de seconde.
    func testLInitDuServiceMigreDejaSansAppelExplicite() {
        let context = container.mainContext
        let state = GamificationState(totalXP: 3000)
        state.levelCurveVersion = 1
        context.insert(state)
        try? context.save()
        _ = GameService(modelContext: context,
                        stepsService: FakeStepsService(authorized: false),
                        widgetDefaults: nil)
        XCTAssertEqual(state.totalXP, LevelSystem.xpRequired(forLevel: 13))
        XCTAssertEqual(state.levelCurveVersion, 2)
    }

    /// Le garde est `< 2` et non `== 1`, et la nuance n'est pas cosmétique : si
    /// SwiftData remplissait un jour la colonne absente avec 0 plutôt qu'avec le
    /// défaut déclaré, `== 1` sauterait la migration en silence et ferait tomber le
    /// joueur de sept niveaux. Vérifié par mutation : sans ce test, remplacer `< 2`
    /// par `== 1` ne fait rougir aucun autre test de la cible.
    func testUneVersionInferieureAUnEstMigreeAussi() {
        let (service, state) = makeService(totalXP: 3000, curveVersion: 0)
        service.migrateLevelCurveIfNeeded()
        XCTAssertEqual(state.totalXP, LevelSystem.xpRequired(forLevel: 13))
        XCTAssertEqual(state.levelCurveVersion, 2)
    }
}

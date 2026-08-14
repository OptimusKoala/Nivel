import XCTest
@testable import NivelCore

final class QuestEngineTests: XCTestCase {
    func testDrawsThreeDistinctQuests() throws {
        let pool = try Catalogs.quests()
        let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
        XCTAssertEqual(drawn.count, 3)
        XCTAssertEqual(Set(drawn.map(\.id)).count, 3)
    }

    func testDrawIsDeterministicForSameWeek() throws {
        let pool = try Catalogs.quests()
        let a = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
        let b = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        let c = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W32", stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
        XCTAssertNotEqual(a.map(\.id), c.map(\.id)) // très probable ; pool de 19
    }

    func testExcludesStepQuestsWhenHealthKitDenied() throws {
        let pool = try Catalogs.quests()
        for week in 1...20 {
            let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W\(week)", stepsAvailable: false, postureAvailable: false, muscuAvailable: false)
            XCTAssertTrue(drawn.allSatisfy { !$0.requiresSteps })
        }
    }

    func testWeeklyDrawIsPinnedForKnownWeek() throws {
        // Pins the exact ids produced by `Array.shuffled(using:)` for this seed today.
        // `shuffled(using:)`'s algorithm is a stdlib implementation detail, not a stable contract —
        // if it ever changes, this regression test will catch the silent change in weekly draws.
        //
        // postureAvailable: false ici : c'est le tirage de Michaël (programme éteint), qui doit
        // rester identique à celui de la v1.10 malgré les 3 quêtes posture ajoutées au pool
        // (spec v1.11 §7.2 — voir le commentaire au-dessus du filtre dans QuestEngine.weeklyDraw).
        //
        // 1.14 : cette stabilité ne valait que pour les quêtes À DRAPEAU, filtrées hors du pool
        // avant le mélange. `burn_target_3` est la première quête sans drapeau ajoutée depuis :
        // le pool éligible passe de 18 à 19 entrées, donc le mélange change et les ids épinglés
        // avec lui (`steps_25k` → `activities_3`). Ce n'est PAS une régression — une quête pour
        // tout le monde n'a d'intérêt que si elle peut sortir. Les ids ci-dessous sont relevés
        // sur l'échec du test, jamais recopiés depuis le code : les re-dériver viderait
        // l'épinglage de son sens.
        let pool = try Catalogs.quests()
        let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
        XCTAssertEqual(drawn.map(\.id), ["log_meals_10", "activities_3", "log_meals_14"])
    }

    /// Le drapeau doit filtrer, sinon la quête posture tomberait chez quelqu'un qui
    /// n'a pas le programme et resterait à zéro toute la semaine.
    func testQuetePostureNestTireeQueSiLeProgrammeEstActif() throws {
        let pool = try Catalogs.quests()
        XCTAssertTrue(pool.contains { $0.requiresPosture }, "aucune quête posture au catalogue")

        for week in ["2026-W32", "2026-W33", "2026-W34", "2026-W35"] {
            let sans = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                              stepsAvailable: true, postureAvailable: false, muscuAvailable: false)
            XCTAssertFalse(sans.contains { $0.requiresPosture }, week)
        }
        // Et elle doit pouvoir sortir quand le programme est actif, sur au moins une
        // semaine parmi plusieurs : sinon le test ne prouverait que la moitié du contrat.
        let semaines = (30...45).map { "2026-W\($0)" }
        XCTAssertTrue(semaines.contains { week in
            QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                   stepsAvailable: true, postureAvailable: true,
                                   muscuAvailable: false)
                .contains { $0.requiresPosture }
        })
    }

    /// Miroir exact du test posture, second programme (spec v1.14 §5.7) : sans
    /// l'interrupteur, la quête muscu tomberait chez quelqu'un qui n'a pas le
    /// programme et resterait à zéro toute la semaine.
    func testLaQueteMuscuNestTireeQueSiLeProgrammeEstActif() throws {
        let pool = try Catalogs.quests()
        XCTAssertTrue(pool.contains { $0.requiresMuscu }, "aucune quête muscu au catalogue")

        for week in ["2026-W32", "2026-W33", "2026-W34", "2026-W35"] {
            let sans = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                              stepsAvailable: true, postureAvailable: false,
                                              muscuAvailable: false)
            XCTAssertFalse(sans.contains { $0.requiresMuscu }, week)
            // Le tirage garde sa taille quand le programme s'allume : le drapeau
            // ajoute des candidates, il n'enlève jamais de place.
            let avec = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                              stepsAvailable: true, postureAvailable: false,
                                              muscuAvailable: true)
            XCTAssertEqual(avec.count, sans.count, week)
        }
        // Et elle doit pouvoir sortir quand le programme est actif, sur au moins une
        // semaine parmi plusieurs : sinon le test ne prouverait que la moitié du contrat.
        let semaines = (30...45).map { "2026-W\($0)" }
        XCTAssertTrue(semaines.contains { week in
            QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                   stepsAvailable: true, postureAvailable: false,
                                   muscuAvailable: true)
                .contains { $0.requiresMuscu }
        })
    }

    /// Les deux drapeaux sont indépendants : allumer la muscu ne fait pas sortir de
    /// quête posture, et réciproquement.
    ///
    /// Le mutant qu'il tue SEUL est celui du copier-coller, le plus plausible des deux :
    /// `(postureAvailable || muscuAvailable || !$0.requiresMuscu)` — une clause muscu
    /// dupliquée depuis la posture sans en changer le premier terme. Le `||` global à la
    /// place du `&&`, lui, meurt déjà sous le test muscu et sous le tirage épinglé ; ce
    /// n'est pas ce qui justifie ce test.
    func testLesDeuxDrapeauxNeSeDeclenchentPasLunLautre() throws {
        let pool = try Catalogs.quests()
        for week in (30...45).map({ "2026-W\($0)" }) {
            let muscuSeule = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                                    stepsAvailable: true, postureAvailable: false,
                                                    muscuAvailable: true)
            XCTAssertFalse(muscuSeule.contains { $0.requiresPosture }, week)
            let postureSeule = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                                      stepsAvailable: true, postureAvailable: true,
                                                      muscuAvailable: false)
            XCTAssertFalse(postureSeule.contains { $0.requiresMuscu }, week)
        }
    }

    /// Les entrées existantes de quests.json ne portent ni l'un ni l'autre champ : un
    /// Bool non optionnel ferait échouer le décodage de TOUT le catalogue.
    func testLesQuetesExistantesSeDecodentSansLeChamp() throws {
        let pool = try Catalogs.quests()
        XCTAssertGreaterThan(pool.count, 3)
        XCTAssertFalse(pool.first { $0.id == "log_meals_10" }?.requiresPosture ?? true)
        XCTAssertFalse(pool.first { $0.id == "log_meals_10" }?.requiresMuscu ?? true)
        // Et la quête muscu, elle, ne porte PAS le drapeau posture : les deux champs
        // ne sont pas le même booléen sous deux noms.
        XCTAssertFalse(pool.first { $0.id == "muscu_sessions_2" }?.requiresPosture ?? true)
    }

    func testWeekID() {
        // Mercredi 29 juillet 2026 → semaine ISO 31
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 29))!
        XCTAssertEqual(QuestEngine.weekID(for: date, calendar: cal), "2026-W31")
    }
}

import XCTest
@testable import NivelCore

final class QuestEngineTests: XCTestCase {
    func testDrawsThreeDistinctQuests() throws {
        let pool = try Catalogs.quests()
        let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false)
        XCTAssertEqual(drawn.count, 3)
        XCTAssertEqual(Set(drawn.map(\.id)).count, 3)
    }

    func testDrawIsDeterministicForSameWeek() throws {
        let pool = try Catalogs.quests()
        let a = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false)
        let b = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        let c = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W32", stepsAvailable: true, postureAvailable: false)
        XCTAssertNotEqual(a.map(\.id), c.map(\.id)) // très probable ; pool de 18
    }

    func testExcludesStepQuestsWhenHealthKitDenied() throws {
        let pool = try Catalogs.quests()
        for week in 1...20 {
            let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W\(week)", stepsAvailable: false, postureAvailable: false)
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
        let pool = try Catalogs.quests()
        let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true, postureAvailable: false)
        XCTAssertEqual(drawn.map(\.id), ["log_meals_10", "steps_25k", "log_meals_14"])
    }

    /// Le drapeau doit filtrer, sinon la quête posture tomberait chez quelqu'un qui
    /// n'a pas le programme et resterait à zéro toute la semaine.
    func testQuetePostureNestTireeQueSiLeProgrammeEstActif() throws {
        let pool = try Catalogs.quests()
        XCTAssertTrue(pool.contains { $0.requiresPosture }, "aucune quête posture au catalogue")

        for week in ["2026-W32", "2026-W33", "2026-W34", "2026-W35"] {
            let sans = QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                              stepsAvailable: true, postureAvailable: false)
            XCTAssertFalse(sans.contains { $0.requiresPosture }, week)
        }
        // Et elle doit pouvoir sortir quand le programme est actif, sur au moins une
        // semaine parmi plusieurs : sinon le test ne prouverait que la moitié du contrat.
        let semaines = (30...45).map { "2026-W\($0)" }
        XCTAssertTrue(semaines.contains { week in
            QuestEngine.weeklyDraw(pool: pool, weekID: week,
                                   stepsAvailable: true, postureAvailable: true)
                .contains { $0.requiresPosture }
        })
    }

    /// Les entrées existantes de quests.json ne portent pas le champ : un Bool non
    /// optionnel ferait échouer le décodage de TOUT le catalogue.
    func testLesQuetesExistantesSeDecodentSansLeChamp() throws {
        let pool = try Catalogs.quests()
        XCTAssertGreaterThan(pool.count, 3)
        XCTAssertFalse(pool.first { $0.id == "log_meals_10" }?.requiresPosture ?? true)
    }

    func testWeekID() {
        // Mercredi 29 juillet 2026 → semaine ISO 31
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 29))!
        XCTAssertEqual(QuestEngine.weekID(for: date, calendar: cal), "2026-W31")
    }
}

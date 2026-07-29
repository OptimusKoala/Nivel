import XCTest
@testable import NivelCore

final class QuestEngineTests: XCTestCase {
    func testDrawsThreeDistinctQuests() throws {
        let pool = try Catalogs.quests()
        let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true)
        XCTAssertEqual(drawn.count, 3)
        XCTAssertEqual(Set(drawn.map(\.id)).count, 3)
    }

    func testDrawIsDeterministicForSameWeek() throws {
        let pool = try Catalogs.quests()
        let a = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true)
        let b = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W31", stepsAvailable: true)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        let c = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W32", stepsAvailable: true)
        XCTAssertNotEqual(a.map(\.id), c.map(\.id)) // très probable ; pool de 15
    }

    func testExcludesStepQuestsWhenHealthKitDenied() throws {
        let pool = try Catalogs.quests()
        for week in 1...20 {
            let drawn = QuestEngine.weeklyDraw(pool: pool, weekID: "2026-W\(week)", stepsAvailable: false)
            XCTAssertTrue(drawn.allSatisfy { !$0.requiresSteps })
        }
    }

    func testWeekID() {
        // Mercredi 29 juillet 2026 → semaine ISO 31
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 29))!
        XCTAssertEqual(QuestEngine.weekID(for: date, calendar: cal), "2026-W31")
    }
}

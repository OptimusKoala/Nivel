import XCTest
@testable import NivelCore

final class CatalogsTests: XCTestCase {
    func testDishesLoadAndIdsAreUnique() throws {
        let dishes = try Catalogs.dishes()
        XCTAssertGreaterThanOrEqual(dishes.count, 16)
        XCTAssertEqual(Set(dishes.map(\.id)).count, dishes.count)
        XCTAssertTrue(dishes.contains { $0.id == "toast" && $0.slots.contains(.breakfast) })
    }

    func testExtrasLoad() throws {
        let extras = try Catalogs.extras()
        XCTAssertTrue(extras.contains { $0.id == "water" && $0.kcal == 0 })
    }

    func testQuestsLoadAndIdsAreUnique() throws {
        let quests = try Catalogs.quests()
        XCTAssertEqual(quests.count, 15)
        XCTAssertEqual(Set(quests.map(\.id)).count, 15)
        // Guards the eligible-pool invariant: steps-denied users must still have at least
        // 3 quests to draw from, so a future catalog edit can't silently break weeklyDraw.
        XCTAssertGreaterThanOrEqual(quests.filter { !$0.requiresSteps }.count, 3)
    }

    func testBadgesLoadAndIdsAreUnique() throws {
        let badges = try Catalogs.badges()
        XCTAssertEqual(badges.count, 20)
        XCTAssertEqual(Set(badges.map(\.id)).count, 20)
    }
}

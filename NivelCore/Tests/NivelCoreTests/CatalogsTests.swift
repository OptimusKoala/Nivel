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
}

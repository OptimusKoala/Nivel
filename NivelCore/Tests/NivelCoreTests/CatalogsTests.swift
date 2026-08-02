import XCTest
@testable import NivelCore

final class CatalogsTests: XCTestCase {
    // testDishesLoadAndIdsAreUnique et testExtrasLoad ont disparu avec Dish/Extra
    // (spec v1.10 §4) : leur contenu est repris par FoodCatalogTests, sur foods.json.

    func testQuestsLoadAndIdsAreUnique() throws {
        let quests = try Catalogs.quests()
        XCTAssertEqual(quests.count, 18)
        XCTAssertEqual(Set(quests.map(\.id)).count, 18)
        // Guards the eligible-pool invariant: steps-denied users must still have at least
        // 3 quests to draw from, so a future catalog edit can't silently break weeklyDraw.
        XCTAssertGreaterThanOrEqual(quests.filter { !$0.requiresSteps }.count, 3)
        XCTAssertTrue(quests.contains { $0.id == "activities_3" && $0.metric == .activitiesDone })
        XCTAssertTrue(quests.contains { $0.id == "daily_sessions_2" && $0.metric == .dailySessionsDone })
    }

    func testBadgesLoadAndIdsAreUnique() throws {
        let badges = try Catalogs.badges()
        XCTAssertEqual(badges.count, 24)
        XCTAssertEqual(Set(badges.map(\.id)).count, 24)
        // Chaque badge a une icône distincte : la grille des badges s'affiche d'un bloc et
        // s'en sert comme identité visuelle. C'est ce qui interdit de mutualiser un glyphe
        // entre deux paliers du même objectif (spec icônes catalogues §3.1).
        XCTAssertEqual(Set(badges.map(\.icon)).count, badges.count)
    }
}

import XCTest
@testable import NivelCore

final class CatalogsTests: XCTestCase {
    // testDishesLoadAndIdsAreUnique et testExtrasLoad ont disparu avec Dish/Extra
    // (spec v1.10 §4) : leur contenu est repris par FoodCatalogTests, sur foods.json.

    func testQuestsLoadAndIdsAreUnique() throws {
        let quests = try Catalogs.quests()
        // 18 + 3 quêtes posture (spec v1.11 §7.2).
        XCTAssertEqual(quests.count, 21)
        XCTAssertEqual(Set(quests.map(\.id)).count, 21)
        // Guards the eligible-pool invariant: steps-denied users must still have at least
        // 3 quests to draw from, so a future catalog edit can't silently break weeklyDraw.
        XCTAssertGreaterThanOrEqual(quests.filter { !$0.requiresSteps }.count, 3)
        XCTAssertTrue(quests.contains { $0.id == "activities_3" && $0.metric == .activitiesDone })
        XCTAssertTrue(quests.contains { $0.id == "daily_sessions_2" && $0.metric == .dailySessionsDone })
        // Idem pour le pool posture-désactivé : sans quoi weeklyDraw manquerait de quêtes
        // à tirer chez Michaël si un futur ajout gonflait trop la part `requiresPosture`.
        XCTAssertGreaterThanOrEqual(quests.filter { !$0.requiresPosture }.count, 3)
        XCTAssertEqual(quests.filter(\.requiresPosture).count, 3, "3 quêtes posture attendues (cibles 3, 4, 5)")
    }

    func testBadgesLoadAndIdsAreUnique() throws {
        let badges = try Catalogs.badges()
        // 24 + les 14 badges de la 1.14 (spec §5.6).
        XCTAssertEqual(badges.count, 38)
        XCTAssertEqual(Set(badges.map(\.id)).count, 38)
        XCTAssertEqual(Set(badges.map(\.title)).count, badges.count, "titres en doublon")
        // Chaque badge a une icône distincte : la grille des badges s'affiche d'un bloc et
        // s'en sert comme identité visuelle. C'est ce qui interdit de mutualiser un glyphe
        // entre deux paliers du même objectif (spec icônes catalogues §3.1).
        XCTAssertEqual(Set(badges.map(\.icon)).count, badges.count)
    }
}

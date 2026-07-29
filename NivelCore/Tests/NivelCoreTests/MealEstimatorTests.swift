import XCTest
@testable import NivelCore

final class MealEstimatorTests: XCTestCase {
    let pasta = Dish(id: "pasta", name: "Pâtes", emoji: "🍝", kcal: 650, slots: [.lunch, .dinner])
    let beer = Extra(id: "beer", name: "Bière", emoji: "🍺", kcal: 150, category: .drink)
    let dessert = Extra(id: "dessert_rich", name: "Dessert gourmand", emoji: "🍰", kcal: 300, category: .dessert)

    func testPortionMultiplierAppliesToDishOnly() {
        // pâtes copieux + 2 bières + dessert : 650×1.3 + 300 + 150×2 = 845 + 600 = 1445
        let kcal = MealEstimator.estimate(dish: pasta, portion: .hearty,
                                          extras: [(dessert, 1), (beer, 2)])
        XCTAssertEqual(kcal, 1445)
    }

    func testLightPortionRounds() {
        // 650×0.7 = 455
        XCTAssertEqual(MealEstimator.estimate(dish: pasta, portion: .light, extras: []), 455)
    }
}

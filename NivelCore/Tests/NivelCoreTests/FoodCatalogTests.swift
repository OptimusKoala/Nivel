import XCTest
@testable import NivelCore

final class FoodCatalogTests: XCTestCase {
    private var catalog: FoodCatalog!

    override func setUpWithError() throws {
        catalog = try FoodCatalog.load()
    }

    func testLeCatalogueSeChargeEtEstComplet() throws {
        XCTAssertEqual(catalog.items(category: .drink, slot: nil).count, 15)
        XCTAssertEqual(catalog.items(category: .snack, slot: nil).count, 12)
        XCTAssertEqual(catalog.items(category: .dish, slot: nil).count, 16)
        XCTAssertGreaterThanOrEqual(catalog.items(category: .side, slot: nil).count, 40)
    }

    func testPasDeDoublonDId() {
        XCTAssertEqual(Set(catalog.items.map(\.id)).count, catalog.items.count)
    }

    func testUniteEtPoidsVontEnsemble() {
        for item in catalog.items {
            XCTAssertEqual(item.unitLabel != nil, item.unitGrams != nil,
                           "\(item.id) : unité et poids doivent aller par paire")
            if let grams = item.unitGrams { XCTAssertGreaterThan(grams, 0, item.id) }
            XCTAssertGreaterThan(item.defaultGrams, 0, item.id)
            XCTAssertGreaterThanOrEqual(item.kcalPer100g, 0, item.id)
        }
    }

    /// Garde-fou de transcription : les kcal par unité des tables de la spec doivent
    /// se retrouver à partir de kcalPer100g et du poids d'une unité.
    func testKcalParUniteRetombentSurLaSpec() {
        let expected: [String: Int] = [
            "beer_half": 108, "beer_pint": 215, "wine": 106, "soda": 139,
            "coffee_milk": 90, "chips": 153, "candy": 105, "nuts": 180,
            "choco_bar": 230, "yogurt": 75, "fruit": 80,
        ]
        for (id, kcal) in expected {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "item manquant : \(id)")
            guard let item, let grams = item.unitGrams else { continue }
            let computed = Int((item.kcalPer100g * Double(grams) / 100).rounded())
            XCTAssertEqual(computed, kcal, accuracy: 1, "\(id) : conversion incohérente")
        }
    }

    func testLibelleDeQuantite() {
        let egg = catalog.byID["egg"]
        XCTAssertEqual(egg?.frQuantity(grams: 60), "1 œuf")
        XCTAssertEqual(egg?.frQuantity(grams: 120), "2 œufs")
        XCTAssertEqual(egg?.frQuantity(grams: 30), "0,5 œuf")
        XCTAssertEqual(catalog.byID["chicken"]?.frQuantity(grams: 150), "150 g")
    }

    /// Les unités invariables doivent porter leur pluriel explicite, sinon on lit
    /// « 2 c. à soupes ».
    func testUnitesInvariables() {
        for item in catalog.items where item.unitLabel?.contains("c. à") == true {
            XCTAssertEqual(item.unitLabelPlural, item.unitLabel,
                           "\(item.id) : pluriel explicite attendu")
        }
    }

    /// LE test de contenu de ce lot. Si la composition par défaut d'un plat s'éloigne
    /// de plus de 10 % du forfait qu'il avait en v1, c'est qu'un ingrédient est mal
    /// dosé. Mieux vaut l'apprendre ici qu'au dîner.
    func testChaqueCompositionRetombeSurLeForfaitV1() {
        let forfaits: [String: Int] = [
            "pasta": 650, "rice": 550, "salad": 350, "veggies": 450,
            "red_meat": 700, "fish": 500, "pizza": 900, "soup": 300,
            "sandwich": 550, "stew": 600, "fast_food": 950, "toast": 350,
            "cereal": 400, "pastry": 300, "yogurt_fruit": 200,
        ]
        for (dishID, forfait) in forfaits {
            let composition = catalog.compositions[dishID]
            XCTAssertNotNil(composition, "composition manquante : \(dishID)")
            guard let composition else { continue }
            let sum = MealEstimator.kcal(
                lines: [.composed(itemID: dishID, components: composition)],
                kcalPer100g: catalog.kcalPer100g
            )
            let tolerance = Double(forfait) * 0.10
            XCTAssertEqual(Double(sum), Double(forfait), accuracy: tolerance,
                           "\(dishID) : composition à \(sum) kcal pour un forfait de \(forfait)")
        }
    }

    func testAutreNAPasDeComposition() {
        XCTAssertNil(catalog.compositions["other"])
    }

    func testToutIngredientCiteExiste() {
        for (dishID, composition) in catalog.compositions {
            for component in composition {
                XCTAssertNotNil(catalog.byID[component.itemID],
                                "\(dishID) cite un item inconnu : \(component.itemID)")
                XCTAssertGreaterThan(component.grams, 0, "\(dishID)/\(component.itemID)")
            }
        }
    }
}

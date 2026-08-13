import XCTest
@testable import NivelCore

final class FoodCatalogTests: XCTestCase {
    private var catalog: FoodCatalog!

    /// Les forfaits kcal des plats en v1. Deux gardes s'en servent : la composition
    /// par défaut et la valeur de repli de l'item. Une seule table, donc pas de
    /// risque qu'elles divergent.
    private static let forfaitsV1: [String: Int] = [
        "pasta": 650, "rice": 550, "salad": 350, "veggies": 450,
        "red_meat": 700, "fish": 500, "pizza": 900, "soup": 300,
        "sandwich": 550, "stew": 600, "fast_food": 950, "toast": 350,
        "cereal": 400, "pastry": 300, "yogurt_fruit": 200,
    ]

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
            // Les 15 boissons et les 12 encas de la spec, pas un échantillon : une
            // erreur de conversion sur une seule ligne du JSON doit tomber ici.
            "water": 0, "tea": 0, "coffee": 2, "soda_zero": 1, "coffee_milk": 90,
            "milk": 128, "juice": 110, "soda": 139, "beer_half": 108, "beer_pint": 215,
            "wine": 106, "spirit": 100, "cocktail": 250, "hot_chocolate": 200,
            "smoothie": 180,
            "fruit": 80, "yogurt": 75, "choco_square": 55, "biscuit": 50, "candy": 105,
            "compote": 90, "cheese_snack": 105, "chips": 153, "nuts": 180,
            "choco_bar": 230, "croissant": 301, "ice_cream": 200,
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
        for (dishID, forfait) in Self.forfaitsV1 {
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

    /// Les valeurs par item des plats composés NE SONT PAS mortes : `line(for:)` s'en
    /// sert en repli quand une composition manque, et la grille du catalogue les
    /// affiche. Elles méritent donc le même garde-fou que les compositions.
    func testLeRepliDesPlatsRetombeSurLeForfaitV1() {
        for (dishID, forfait) in Self.forfaitsV1 {
            let item = catalog.byID[dishID]
            XCTAssertNotNil(item, "plat manquant : \(dishID)")
            guard let item else { continue }
            let repli = item.kcalPer100g * Double(item.defaultGrams) / 100
            XCTAssertEqual(repli, Double(forfait), accuracy: Double(forfait) * 0.10,
                           "\(dishID) : repli à \(Int(repli)) kcal pour un forfait de \(forfait)")
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

    // MARK: Catégories (spec v1.14 §3.4)

    func testLaCategorieDessertExiste() {
        XCTAssertEqual(FoodItem.Category.dessert.frLabel, "Desserts")
    }

    /// « Accompagnements » est devenu « Ingrédients » (spec v1.14 §3.5). Le libellé est
    /// épinglé parce qu'un renommage, contrairement à une chaîne neuve, se défait sans
    /// bruit à la première relecture qui croit corriger une étourderie.
    func testLeLibelleDesIngredients() {
        XCTAssertEqual(FoodItem.Category.side.frLabel, "Ingrédients")
    }

    /// Garde-fou : une catégorie ajoutée à l'enum sans être rangée dans `tabOrder`
    /// disparaîtrait de l'écran en silence.
    func testChaqueCategorieEstDansLOrdreDAffichage() {
        XCTAssertEqual(Set(FoodItem.Category.tabOrder), Set(FoodItem.Category.allCases))
        XCTAssertEqual(FoodItem.Category.tabOrder.count, FoodItem.Category.allCases.count,
                       "pas de doublon")
        // La position, elle, est prescrite ; le reste de l'ordre ne l'est pas, donc on
        // n'épingle pas le tableau entier : un réagencement voulu doit rester libre.
        XCTAssertEqual(FoodItem.Category.tabOrder.last, .dessert,
                       "spec §3.4 : les desserts en dernier")
    }

    // MARK: Tags des quêtes (spec §7.1)

    /// Épingle EXACTEMENT les deux listes de tags que lisent les quêtes "jours sans
    /// alcool" et "jours en dessert léger" (GameService). Un item ajouté un jour sans
    /// son tag ne doit pas passer inaperçu : c'est le bug qui aurait rendu les deux
    /// quêtes toujours satisfaites en portant les vieux ids `beer`/`dessert_rich`.
    func testTagsAlcoolEtDessertGourmandSontExactementCesItems() {
        let alcohol = Set(catalog.items.filter { $0.tags.contains("alcohol") }.map(\.id))
        XCTAssertEqual(alcohol, ["beer_half", "beer_pint", "wine", "spirit", "cocktail"])

        let richDessert = Set(catalog.items.filter { $0.tags.contains("richDessert") }.map(\.id))
        XCTAssertEqual(richDessert, ["choco_bar", "ice_cream", "croissant"])
    }
}

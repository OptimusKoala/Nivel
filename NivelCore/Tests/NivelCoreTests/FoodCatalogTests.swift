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

    // MARK: Invariants du catalogue

    func testPasDeDoublonDId() {
        XCTAssertEqual(Set(catalog.items.map(\.id)).count, catalog.items.count)
    }

    /// Garde-fou de rangement : `foods.json` est groupé par catégorie et la grille de
    /// taps s'affiche dans l'ordre du fichier. Une entrée dont la catégorie change
    /// mais qui reste à sa place hors du bloc de sa nouvelle catégorie apparaîtrait
    /// donc au mauvais endroit de son onglet — sans qu'aucun autre test ne s'en
    /// aperçoive. C'est ce qui s'était produit au premier jet de ce lot, avant que les
    /// trois desserts déménagés ne soient physiquement déplacés hors du bloc snack.
    /// Ici, on vérifie qu'aucune catégorie ne revient après avoir été quittée.
    func testLesCategoriesSontContiguesDansLeFichier() {
        var categoriesVues: Set<FoodItem.Category> = []
        var categorieCourante: FoodItem.Category?
        for item in catalog.items {
            if item.category != categorieCourante {
                XCTAssertFalse(categoriesVues.contains(item.category),
                               "\(item.category) réapparaît après avoir été quittée, autour de \(item.id)")
                categoriesVues.insert(item.category)
                categorieCourante = item.category
            }
        }
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

    /// Les unités invariables doivent porter leur pluriel explicite, sinon on lit
    /// « 2 c. à soupes ».
    func testUnitesInvariables() {
        for item in catalog.items where item.unitLabel?.contains("c. à") == true {
            XCTAssertEqual(item.unitLabelPlural, item.unitLabel,
                           "\(item.id) : pluriel explicite attendu")
        }
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

    /// Deux entrées homonymes DANS LE MÊME ONGLET sont un piège : on tape l'une en
    /// croyant taper l'autre. D'un onglet à l'autre, en revanche, l'homonymie est
    /// légitime et voulue — « Fromage » existe en ingrédient (350 kcal/100 g, pour
    /// une composition) ET en encas, « Céréales » en plat ET en ingrédient. C'est
    /// donc l'unicité PAR CATÉGORIE qu'il faut exiger, pas l'unicité globale.
    func testLesNomsSontUniquesParCategorie() {
        for category in FoodItem.Category.allCases {
            let names = catalog.items.filter { $0.category == category }.map(\.name)
            XCTAssertEqual(Set(names).count, names.count,
                           "\(category) : \(Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys)")
        }
    }

    /// Deux données, pas des règles de calcul, et elles ne bougent PAS ensemble —
    /// c'est tout l'intérêt d'en avoir deux depuis la 1.14 :
    /// - un aliment ordinaire ajouté fait monter les DEUX, et avec elles le compte
    ///   par catégorie concerné dans `testChaqueOngletAfficheSonNombreDItems` ;
    /// - une recette ajoutée (§6.1) ne fait monter que la première : elle n'est ni
    ///   dans un onglet ni parmi les aliments ordinaires, et les 49 plats restent 49.
    ///
    /// C'est la seconde ligne qui tient le lien avec `testChaqueOngletAfficheSonNombreDItems` :
    /// les onglets ne montrant pas les recettes, la somme des cinq catégories doit
    /// faire le compte des aliments ORDINAIRES, pas la taille du fichier.
    func testLaTailleDuCatalogue() {
        XCTAssertEqual(catalog.items.count, 188, "le catalogue ne compte plus 188 entrées")
        XCTAssertEqual(catalog.items.filter { !$0.isRecipe }.count, 153,
                       "les aliments ordinaires ne sont plus 153")
    }

    // MARK: Catalogue v1 (spec v1.10)

    /// Renommé en 1.14 : ce test comptait le catalogue, il compte maintenant les
    /// ONGLETS. `items(category:slot:)` écarte les recettes (§6.1) : une recette ajoutée
    /// à `foods.json` ne fait pas bouger le compte des plats ci-dessous, contrairement
    /// aux dix-neuf plats de brasserie de la 1.15, qui l'ont porté de 30 à 49.
    /// Le garde-fou de transcription est devenu un détecteur de recette qui
    /// fuit dans la grille de taps ; la dernière assertion rétablit le lien avec la
    /// taille réelle du fichier.
    func testChaqueOngletAfficheSonNombreDItems() throws {
        XCTAssertEqual(catalog.items(category: .drink, slot: nil).count, 15)
        XCTAssertEqual(catalog.items(category: .snack, slot: nil).count, 9)     // 12 − 3 déménagés
        XCTAssertEqual(catalog.items(category: .dish, slot: nil).count, 49)  // 30 + 19 brasserie
        // Épinglé et non borné par un `>=` : la borne à 40 datait d'un onglet à 42 items
        // et ne gardait plus rien une fois passé à 58. C'est le dernier compte de
        // catégorie du fichier qui n'était pas exact.
        XCTAssertEqual(catalog.items(category: .side, slot: nil).count, 65)  // 58 + 7 brasserie
        XCTAssertEqual(catalog.items(category: .dessert, slot: nil).count, 15)  // 10 + 5 brasserie
        // Le lien avec `testLaTailleDuCatalogue` : ces cinq comptes couvrent tous les
        // aliments ordinaires, et rien d'autre. Un item qui disparaîtrait de son onglet
        // sans être une recette tomberait ici plutôt que nulle part.
        XCTAssertEqual(15 + 9 + 49 + 65 + 15, catalog.items.filter { !$0.isRecipe }.count)
    }

    /// Garde-fou de transcription : les kcal par unité des tables de la spec doivent
    /// se retrouver à partir de kcalPer100g et du poids d'une unité.
    func testKcalParUniteRetombentSurLaSpec() {
        let expected: [String: Int] = [
            // Les 15 boissons, les 9 encas et les 3 desserts (anciens encas) de la
            // spec, pas un échantillon : une erreur de conversion sur une seule ligne
            // du JSON doit tomber ici.
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
        // LE cran qui manquait, et le seul où le pluriel se décide vraiment : en
        // français il commence à deux, donc un décimal en dessous reste au singulier.
        // Écrit « 1,5 œufs » de la v1.10 à la 1.14, sur trois écrans, sans qu'aucune
        // des trois autres bornes ci-dessus puisse s'en apercevoir.
        XCTAssertEqual(egg?.frQuantity(grams: 90), "1,5 œuf")
        XCTAssertEqual(catalog.byID["bread"]?.frQuantity(grams: 60), "1,5 tranche")
        XCTAssertEqual(catalog.byID["chicken"]?.frQuantity(grams: 150), "150 g")
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

    // MARK: La cinquième catégorie (spec v1.14 §3.4)

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
        // Quatre des cinq desserts de la 1.15 §6.4 s'y ajoutent. `ile_flottante` en est
        // ABSENTE et doit le rester : à 130 kcal aux 100 g elle est plus légère que la
        // compote, elle-même non taguée.
        XCTAssertEqual(richDessert, ["choco_bar", "ice_cream", "croissant",
                                     "cake", "fruit_tart", "choco_mousse", "crepe_sugar",
                                     "creme_brulee", "tarte_tatin", "profiteroles",
                                     "fondant_chocolat"])
    }

    // MARK: Seize ingrédients (spec v1.14 §3.2)

    func testLesSeizeNouveauxIngredientsSontPresents() throws {
        for id in ["wrap", "pita", "kebab_meat", "cheese_sauce", "white_sauce",
                   "nuggets", "fried_chicken", "burrata", "dry_sausage", "olives",
                   "crackers", "oats", "noodles_cooked", "soy_sauce", "sausage", "bechamel"] {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "ingrédient manquant : \(id)")
            XCTAssertEqual(item?.category, .side, "\(id) doit être un ingrédient")
        }
    }

    /// Garde-fou de transcription : les seize kcal/100 g du tableau de la spec, pas un
    /// échantillon : une erreur de recopie sur une seule ligne du JSON doit tomber ici.
    func testKcalDesSeizeIngredientsRetombentSurLaSpec() {
        let expected: [String: Int] = [
            "wrap": 300, "pita": 270, "kebab_meat": 250, "cheese_sauce": 300,
            "white_sauce": 350, "nuggets": 290, "fried_chicken": 280, "burrata": 290,
            "dry_sausage": 450, "olives": 150, "crackers": 450, "oats": 380,
            "noodles_cooked": 140, "soy_sauce": 60, "sausage": 300, "bechamel": 130,
        ]
        for (id, kcal) in expected {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "ingrédient manquant : \(id)")
            XCTAssertEqual(item?.kcalPer100g, Double(kcal), "\(id) : kcal/100 g incohérent avec la spec")
        }
    }

    // MARK: Quatorze plats (spec v1.14 §3.3)

    /// Les ≈ kcal de la dernière colonne du tableau §3.3. Trois gardes s'en servent :
    /// la composition par défaut et le repli par item, comme `forfaitsV1`, plus la
    /// liste des quatorze ids elle-même. Une seule table, donc pas de risque qu'elles
    /// divergent.
    private static let platsV114: [String: Int] = [
        "tacos": 1050, "kebab": 790, "burrata_tomato": 600, "apero_platter": 710,
        "fried_chicken_salad": 535, "nuggets_meal": 675, "omelette": 280,
        "omelette_garnie": 440, "gratin_dauphinois": 520, "gratin_veg": 320,
        "gratin_pasta": 610, "asian_noodles": 615, "oatmeal_fruit": 395,
        "breakfast_eggs": 505,
    ]

    /// Même garde-fou que `testChaqueCompositionRetombeSurLeForfaitV1`, tolérance élargie
    /// à 5 % (les sommes réelles sont toutes à moins de 1 % de la spec) : elle attrape un
    /// dosage grossièrement faux sans être si stricte qu'un demi-gramme la fasse échouer.
    func testChaqueCompositionRetombeSurLaSpec114() {
        for (dishID, kcal) in Self.platsV114 {
            let composition = catalog.compositions[dishID]
            XCTAssertNotNil(composition, "composition manquante : \(dishID)")
            guard let composition else { continue }
            let sum = MealEstimator.kcal(
                lines: [.composed(itemID: dishID, components: composition)],
                kcalPer100g: catalog.kcalPer100g
            )
            let tolerance = Double(kcal) * 0.05
            XCTAssertEqual(Double(sum), Double(kcal), accuracy: tolerance,
                           "\(dishID) : composition à \(sum) kcal pour ~\(kcal) kcal en spec")
        }
    }

    /// Même garde-fou que `testLeRepliDesPlatsRetombeSurLeForfaitV1` : `kcalPer100g` et
    /// `defaultGrams` ne sont jamais lus par l'estimation tant qu'une composition existe,
    /// mais ils s'affichent dans la grille du catalogue et doivent rester honnêtes.
    func testLeRepliDesQuatorzePlatsRetombeSurLaSpec114() {
        for (dishID, kcal) in Self.platsV114 {
            let item = catalog.byID[dishID]
            XCTAssertNotNil(item, "plat manquant : \(dishID)")
            guard let item else { continue }
            let repli = item.kcalPer100g * Double(item.defaultGrams) / 100
            XCTAssertEqual(repli, Double(kcal), accuracy: Double(kcal) * 0.05,
                           "\(dishID) : repli à \(Int(repli)) kcal pour ~\(kcal) kcal en spec")
        }
    }

    func testLesQuatorzeNouveauxPlatsOntUneCompositionResoluble() throws {
        for id in Self.platsV114.keys {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "plat manquant : \(id)")
            guard let item else { continue }
            XCTAssertEqual(item.category, .dish, "\(id)")
            XCTAssertTrue(catalog.line(for: item).isComposed, "\(id) doit avoir une composition")
        }
    }

    /// Deux valeurs témoins, en plus du garde-fou à 5 % ci-dessus : ce sont les sommes
    /// EXACTES des compositions du tableau §3.3 (que la spec arrondit à ~280 et ~1 050),
    /// pas des nombres choisis a posteriori. Si un barème d'ingrédient bouge de quelques
    /// kcal, c'est ici que ça se voit ; un écart se corrige dans la composition, jamais
    /// en recopiant la nouvelle somme dans ce test.
    func testEstimationsTemoinsDesPlats() throws {
        let omeletteItem = catalog.byID["omelette"]
        XCTAssertNotNil(omeletteItem, "plat manquant : omelette")
        if let omeletteItem {
            let omelette = catalog.line(for: omeletteItem)
            XCTAssertEqual(MealEstimator.kcal(lines: [omelette], kcalPer100g: catalog.kcalPer100g), 278)
        }
        let tacosItem = catalog.byID["tacos"]
        XCTAssertNotNil(tacosItem, "plat manquant : tacos")
        if let tacosItem {
            let tacos = catalog.line(for: tacosItem)
            XCTAssertEqual(MealEstimator.kcal(lines: [tacos], kcalPer100g: catalog.kcalPer100g), 1053)
        }
    }

    func testLesPlatsDePetitDejSontCantonnesAuCreneau() throws {
        for id in ["oatmeal_fruit", "breakfast_eggs"] {
            XCTAssertEqual(catalog.byID[id]?.slots, [.breakfast], "\(id)")
        }
    }

    /// La planche apéro n'est ni un déjeuner ni un dîner : slots vide = proposée partout.
    /// Équivalent aujourd'hui à lister les quatre créneaux en clair (`Foods.swift:107-109`
    /// résout les deux formes de la même façon) ; le vide est un choix éditorial ici, pas
    /// la seule forme possible.
    func testLaPlancheAperoNAPasDeCreneau() throws {
        XCTAssertEqual(catalog.byID["apero_platter"]?.slots, [])
    }

    // MARK: Quinze desserts (spec v1.14 §3.4, cinq de plus en 1.15 §6.4)

    /// Renommé en 1.15 : il s'appelait `testLesDixDesserts…` et comptait dix. Le nom
    /// d'un test qui compte doit suivre le compte, sinon l'échec parle d'un chiffre
    /// qui n'est plus dans le fichier et on cherche longtemps.
    func testLesQuinzeDessertsSontComplets() {
        let desserts = catalog.items.filter { $0.category == .dessert }
        XCTAssertEqual(desserts.count, 15, "dix + les cinq de brasserie")
        for id in ["fruit_salad", "cake", "fruit_tart", "choco_mousse",
                   "crepe_sugar", "skyr", "greek_yogurt",
                   "choco_square", "ice_cream", "compote",
                   "creme_brulee", "tarte_tatin", "profiteroles",
                   "ile_flottante", "fondant_chocolat"] {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "dessert manquant : \(id)")
            XCTAssertEqual(item?.category, .dessert, "\(id)")
        }
    }

    /// Garde-fou de transcription : les sept kcal/100 g du tableau §3.4, pas un
    /// échantillon : une erreur de recopie sur une seule ligne du JSON doit tomber ici.
    func testKcalDesSeptNouveauxDessertsRetombentSurLaSpec() {
        let expected: [String: Int] = [
            "fruit_salad": 60, "cake": 380, "fruit_tart": 250, "choco_mousse": 210,
            "crepe_sugar": 220,
            // Skyr et yaourt grec sont deux entrées et non une : 35 kcal d'écart aux
            // 100 g, soit 50 kcal sur un pot. Les confondre ferait mentir une
            // estimation qui porte un tilde précisément pour ne pas mentir.
            "skyr": 85, "greek_yogurt": 120,
        ]
        for (id, kcal) in expected {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "dessert manquant : \(id)")
            XCTAssertEqual(item?.kcalPer100g, Double(kcal), "\(id) : kcal/100 g incohérent avec la spec")
        }
    }

    /// Garde-fou de transcription : les cinq unités ajoutées après le premier jet, quand
    /// les dix desserts se saisissaient tous au gramme et que l'onglet était le seul du
    /// catalogue à présentation mixte. Pas un échantillon : une erreur de recopie sur une
    /// seule ligne du JSON doit tomber ici. `testUniteEtPoidsVontEnsemble` épingle déjà
    /// l'invariant libellé/grammage par paire ; celui-ci épingle les valeurs, pas la règle.
    func testLesUnitesDesCinqDessertsRetombentSurLaSpec() {
        let expected: [String: (label: String, grams: Int)] = [
            "skyr": ("pot", 150),
            "greek_yogurt": ("pot", 150),
            "cake": ("part", 100),
            "fruit_tart": ("part", 120),
            "crepe_sugar": ("crêpe", 90),
        ]
        for (id, unite) in expected {
            let item = catalog.byID[id]
            XCTAssertNotNil(item, "dessert manquant : \(id)")
            guard let item else { continue }
            XCTAssertEqual(item.unitLabel, unite.label, "\(id) : unité incohérente avec la spec")
            XCTAssertEqual(item.unitGrams, unite.grams, "\(id) : grammage d'unité incohérent avec la spec")
        }
    }

    /// « Viennoiserie » à 300 kcal/100 g (`pastry`, un plat) et « Viennoiserie » à
    /// 430 kcal/100 g (`croissant`, un encas) : c'était deux barèmes
    /// sous un seul nom. L'unicité par catégorie (`testLesNomsSontUniquesParCategorie`)
    /// ne peut pas le protéger, puisque les deux entrées sont dans deux onglets
    /// différents. Comme `testLeLibelleDesIngredients`, un renommage se défait sans
    /// bruit à la première relecture qui croit corriger une étourderie.
    func testLeRenommageDuCroissantEstEpingle() {
        XCTAssertEqual(catalog.byID["croissant"]?.name, "Croissant ou pain au chocolat")
        XCTAssertEqual(catalog.byID["pastry"]?.name, "Viennoiserie")
    }

    // MARK: Recettes (spec v1.14 §6.1)

    /// Les recettes sont des plats pour le calcul et le journal, mais PAS pour la
    /// grille de taps : l'onglet Plats passerait du simple au double, et le chemin de
    /// quinze secondes de la 1.10 en souffrirait.
    func testLesRecettesSontMasqueesDesOngletsDuCatalogue() {
        let shown = catalog.items(category: .dish, slot: nil)
        XCTAssertFalse(shown.contains { $0.isRecipe }, "une recette ne s'affiche pas dans l'onglet Plats")
        XCTAssertEqual(shown.count, 49, "les quarante-neuf plats ordinaires, ni plus ni moins")
    }

    /// Le test ci-dessus ne prouve rien tant que `foods.json` ne porte aucune recette :
    /// retirer le filtre de `items(category:slot:)` le laisse vert. Un catalogue de
    /// laboratoire n'attend pas la Task 2 pour épingler le comportement.
    func testLeFiltreEcarteUneRecetteDeSaCategorie() {
        let ordinaire = FoodItem(id: "a", name: "A", emoji: "🍝", kcalPer100g: 100,
                                 category: .dish, defaultGrams: 100)
        let recette = FoodItem(id: "b", name: "B", emoji: "🐟", kcalPer100g: 95,
                               category: .dish, defaultGrams: 430, isRecipe: true)
        let labo = FoodCatalog(items: [ordinaire, recette],
                               byID: ["a": ordinaire, "b": recette], compositions: [:])
        XCTAssertEqual(labo.items(category: .dish, slot: nil).map(\.id), ["a"])
    }

    /// Et rien non plus ne garantit qu'un `"isRecipe": true` posé dans le JSON arrive
    /// jusqu'à la propriété : `CodingKeys` est écrit à la main, une clé mal orthographiée
    /// y décoderait faux en silence. Décodage direct, sans passer par le bundle.
    func testLaCleIsRecipeSeDecodeDepuisLeJSON() throws {
        let json = Data("""
        [{"id":"r","name":"R","emoji":"🐟","kcalPer100g":95,"category":"dish",
          "tags":[],"slots":[],"defaultGrams":430,"isRecipe":true}]
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode([FoodItem].self, from: json).first?.isRecipe, true)
    }

    /// Mais elles restent atteignables par id : c'est ainsi que la bande d'idées et
    /// le journal les retrouvent.
    func testLesRecettesRestentAtteignablesParId() throws {
        // `XCTUnwrap` et NON le `XCTSkipIf` d'avant : celui-ci attendait les recettes de
        // la Task 2 du lot D, qui sont là depuis — il ne se déclenchait donc plus jamais
        // et masquait le `!` de la ligne suivante. Un catalogue qui perdrait ses recettes
        // doit rendre ce test ROUGE, pas l'escamoter.
        let recipe = try XCTUnwrap(catalog.items.first { $0.isRecipe },
                                   "aucune recette dans foods.json")
        XCTAssertNotNil(catalog.byID[recipe.id])
        XCTAssertTrue(catalog.line(for: recipe).isComposed)
    }

    func testLesAlimentsOrdinairesNeSontPasDesRecettes() {
        for id in ["pasta", "tacos", "skyr", "lettuce", "water"] {
            XCTAssertEqual(catalog.byID[id]?.isRecipe, false, id)
        }
    }

    /// Seul test du fichier qui passe par `hasTag(_:itemID:)`, le chemin qu'emprunte
    /// réellement `GameService` (`GameService.swift:372,382`) pour la quête « jours en
    /// dessert léger ». `testTagsAlcoolEtDessertGourmandSontExactementCesItems` lit
    /// `item.tags` en direct et épingle déjà la liste exacte des deux volets ; celui-ci
    /// exerce l'API plutôt que la donnée.
    func testLesNouveauxDessertsGourmandsSontTagues() {
        for id in ["cake", "fruit_tart", "choco_mousse", "crepe_sugar"] {
            XCTAssertTrue(catalog.hasTag("richDessert", itemID: id), "\(id) doit être gourmand")
        }
        // Et les légers ne le portent pas, sinon la quête devient impossible.
        for id in ["fruit_salad", "skyr", "greek_yogurt", "compote"] {
            XCTAssertFalse(catalog.hasTag("richDessert", itemID: id), "\(id) n'est pas gourmand")
        }
    }

    // MARK: Brasserie (spec 1.15 §6)

    /// Une ligne de la table de la spec §6.2, ses six colonnes. Une structure et non
    /// six dictionnaires parallèles : une ligne de la spec reste une ligne ici, et se
    /// relit en regard du document sans compter les colonnes.
    private struct PlatDeSpec {
        let id: String
        let name: String
        let emoji: String
        let kcal: Double
        let portion: Int
        let slots: [MealSlot]
    }

    /// La table de la spec §6.2 recopiée à la main DEPUIS LA SPEC, jamais depuis
    /// `foods.json` : une référence tirée de la sortie qu'elle contrôle ne contrôle
    /// plus rien. Partagée par les deux tests qui suivent pour qu'aucun ne couvre un
    /// sous-ensemble des dix-neuf.
    private static let brasserie: [PlatDeSpec] = {
        let midiEtSoir: [MealSlot] = [.lunch, .dinner]
        let soir: [MealSlot] = [.dinner]
        return [
            .init(id: "escargots", name: "Escargots de Bourgogne", emoji: "🐌",
                  kcal: 220, portion: 90, slots: midiEtSoir),
            .init(id: "frog_legs", name: "Cuisses de grenouilles", emoji: "🐸",
                  kcal: 155, portion: 200, slots: midiEtSoir),
            .init(id: "steak_tartare", name: "Steak tartare", emoji: "🥩",
                  kcal: 180, portion: 200, slots: midiEtSoir),
            .init(id: "andouillette", name: "Andouillette", emoji: "🌭",
                  kcal: 290, portion: 200, slots: midiEtSoir),
            .init(id: "duck_confit", name: "Confit de canard", emoji: "🦆",
                  kcal: 250, portion: 220, slots: midiEtSoir),
            .init(id: "duck_breast", name: "Magret de canard", emoji: "🦆",
                  kcal: 230, portion: 200, slots: midiEtSoir),
            .init(id: "veal_blanquette", name: "Blanquette de veau", emoji: "🍲",
                  kcal: 130, portion: 320, slots: midiEtSoir),
            .init(id: "beef_bourguignon", name: "Bœuf bourguignon", emoji: "🍲",
                  kcal: 140, portion: 320, slots: midiEtSoir),
            .init(id: "cassoulet", name: "Cassoulet", emoji: "🫘",
                  kcal: 165, portion: 400, slots: midiEtSoir),
            .init(id: "choucroute", name: "Choucroute garnie", emoji: "🥬",
                  kcal: 130, portion: 400, slots: midiEtSoir),
            .init(id: "tartiflette", name: "Tartiflette", emoji: "🧀",
                  kcal: 180, portion: 350, slots: midiEtSoir),
            .init(id: "raclette", name: "Raclette", emoji: "🧀",
                  kcal: 260, portion: 300, slots: soir),
            .init(id: "fondue_savoyarde", name: "Fondue savoyarde", emoji: "🫕",
                  kcal: 270, portion: 250, slots: soir),
            .init(id: "moules_frites", name: "Moules-frites", emoji: "🦪",
                  kcal: 150, portion: 400, slots: midiEtSoir),
            .init(id: "entrecote_poivre", name: "Entrecôte sauce au poivre", emoji: "🥩",
                  kcal: 230, portion: 250, slots: midiEtSoir),
            .init(id: "onion_soup", name: "Soupe à l'oignon gratinée", emoji: "🧅",
                  kcal: 110, portion: 300, slots: soir),
            .init(id: "quiche_lorraine", name: "Quiche lorraine", emoji: "🥧",
                  kcal: 280, portion: 180, slots: midiEtSoir),
            .init(id: "sole_meuniere", name: "Sole meunière", emoji: "🐟",
                  kcal: 165, portion: 220, slots: midiEtSoir),
            .init(id: "coq_au_vin", name: "Coq au vin", emoji: "🍗",
                  kcal: 150, portion: 300, slots: midiEtSoir),
        ]
    }()

    /// Les dix-neuf plats de la spec §6.2, transcrits depuis la table. Garde-fou de
    /// transcription : ces valeurs viennent d'un tableau, et un tableau se recopie mal.
    /// Les SIX colonnes sont tenues, pas seulement les kcal — un premier jet n'assertait
    /// que les kcal et la catégorie, et laissait passer une portion à 999 ou un nom
    /// cassé. Chaque message d'échec nomme l'id ET la colonne : sans quoi on relit
    /// dix-neuf lignes pour trouver celle qui a bougé.
    func testLesDixNeufPlatsDeBrasserieRetombentSurLaSpec() {
        XCTAssertEqual(Self.brasserie.count, 19, "la table de référence n'a plus dix-neuf lignes")
        for spec in Self.brasserie {
            guard let item = catalog.items.first(where: { $0.id == spec.id }) else {
                XCTFail("plat manquant du catalogue : \(spec.id)")
                continue
            }
            XCTAssertEqual(item.name, spec.name, "\(spec.id) : nom")
            XCTAssertEqual(item.emoji, spec.emoji, "\(spec.id) : emoji")
            XCTAssertEqual(item.kcalPer100g, spec.kcal, "\(spec.id) : kcal/100 g")
            XCTAssertEqual(item.defaultGrams, spec.portion, "\(spec.id) : portion")
            XCTAssertEqual(item.slots, spec.slots, "\(spec.id) : créneaux")
            XCTAssertEqual(item.category, .dish, "\(spec.id) : catégorie")
            XCTAssertFalse(item.isRecipe, "\(spec.id) : ce n'est pas une recette")
        }
    }

    /// Spec §6.1 : au restaurant on ne pèse rien, et le catalogue n'a ni escargot ni
    /// grenouille à ranger sous une ligne générique. Ces plats fonctionnent au forfait,
    /// comme « Autre ». Ce test existe pour que le choix reste un choix : quelqu'un qui
    /// leur ajouterait une composition « par cohérence » le verrait ici. Les dix-neuf,
    /// et pas un échantillon de cinq : la composition de trop se poserait précisément
    /// sur le plat que l'échantillon ne couvre pas.
    ///
    /// On interroge le catalogue chargé plutôt que `Catalogs.compositions()`, qui existe
    /// et conviendrait : c'est la donnée telle que l'app la voit qui décide.
    func testLesPlatsDeBrasserieNOntPasDeComposition() {
        for spec in Self.brasserie {
            XCTAssertNil(catalog.compositions[spec.id],
                         "\(spec.id) ne doit pas avoir de composition")
        }
    }

    /// Trois plats du soir seulement. Le catalogue cantonne déjà des plats à un créneau
    /// dans l'autre sens (petit-déjeuner) : même mécanique.
    func testLesPlatsDuSoirSontCantonnes() throws {
        for id in ["raclette", "fondue_savoyarde", "onion_soup"] {
            let item = try XCTUnwrap(catalog.items.first { $0.id == id })
            XCTAssertEqual(item.slots, [.dinner], id)
        }
    }

    /// Une ligne de la table de la spec §6.3, ses cinq colonnes. Pas de colonne créneau :
    /// un accompagnement se sert à toute heure, et le test l'exige explicitement plutôt
    /// que de porter un `[]` de façade dans chaque ligne.
    private struct AccompagnementDeSpec {
        let id: String
        let name: String
        let emoji: String
        let kcal: Double
        let portion: Int
    }

    /// La table de la spec §6.3, recopiée DEPUIS LA SPEC comme celle des plats.
    private static let accompagnementsDeBrasserie: [AccompagnementDeSpec] = [
        .init(id: "green_beans", name: "Haricots verts", emoji: "🫛", kcal: 35, portion: 150),
        .init(id: "mushrooms_pan", name: "Poêlée de champignons", emoji: "🍄", kcal: 70, portion: 120),
        .init(id: "potatoes_sauteed", name: "Pommes sautées", emoji: "🥔", kcal: 165, portion: 150),
        .init(id: "ratatouille", name: "Ratatouille", emoji: "🍆", kcal: 60, portion: 180),
        .init(id: "spinach_cream", name: "Épinards à la crème", emoji: "🥬", kcal: 90, portion: 150),
        .init(id: "rice_pilaf", name: "Riz pilaf", emoji: "🍚", kcal: 145, portion: 150),
        .init(id: "gratin_dauphinois_side", name: "Gratin dauphinois", emoji: "🥔", kcal: 149, portion: 150),
    ]

    /// Même garde-fou que pour les plats, sur toutes les colonnes de la table §6.3.
    /// Les accompagnements n'ont volontairement PAS de test d'absence de composition :
    /// aucun n'en a jamais eu, ce sont eux les composants, et un tel test serait vrai
    /// par construction sans rien garder.
    func testLesSeptAccompagnementsRetombentSurLaSpec() {
        XCTAssertEqual(Self.accompagnementsDeBrasserie.count, 7,
                       "la table de référence n'a plus sept lignes")
        for spec in Self.accompagnementsDeBrasserie {
            guard let item = catalog.items.first(where: { $0.id == spec.id }) else {
                XCTFail("accompagnement manquant du catalogue : \(spec.id)")
                continue
            }
            XCTAssertEqual(item.name, spec.name, "\(spec.id) : nom")
            XCTAssertEqual(item.emoji, spec.emoji, "\(spec.id) : emoji")
            XCTAssertEqual(item.kcalPer100g, spec.kcal, "\(spec.id) : kcal/100 g")
            XCTAssertEqual(item.defaultGrams, spec.portion, "\(spec.id) : portion")
            XCTAssertEqual(item.category, .side, "\(spec.id) : catégorie")
            XCTAssertEqual(item.slots, [], "\(spec.id) : créneaux, un accompagnement se sert partout")
            XCTAssertFalse(item.isRecipe, "\(spec.id) : ce n'est pas une recette")
        }
    }

    /// Une ligne de la table de la spec §6.4, ses sept colonnes. Ces desserts-ci portent
    /// une UNITÉ (« une part », « un ramequin »), contrairement aux plats et aux
    /// accompagnements du lot : deux colonnes de plus à tenir, et c'est là que se logent
    /// les erreurs de recopie.
    private struct DessertDeSpec {
        let id: String
        let name: String
        let emoji: String
        let kcal: Double
        let unite: String
        let poidsUnite: Int
        let gourmand: Bool
    }

    /// La table de la spec §6.4, recopiée DEPUIS LA SPEC comme les deux précédentes.
    private static let dessertsDeBrasserie: [DessertDeSpec] = [
        .init(id: "creme_brulee", name: "Crème brûlée", emoji: "🍮",
              kcal: 250, unite: "ramequin", poidsUnite: 120, gourmand: true),
        .init(id: "tarte_tatin", name: "Tarte Tatin", emoji: "🥧",
              kcal: 250, unite: "part", poidsUnite: 120, gourmand: true),
        .init(id: "profiteroles", name: "Profiteroles", emoji: "🍫",
              kcal: 300, unite: "part", poidsUnite: 130, gourmand: true),
        .init(id: "ile_flottante", name: "Île flottante", emoji: "🍮",
              kcal: 130, unite: "part", poidsUnite: 130, gourmand: false),
        .init(id: "fondant_chocolat", name: "Fondant au chocolat", emoji: "🍫",
              kcal: 400, unite: "part", poidsUnite: 100, gourmand: true),
    ]

    /// Même garde-fou que pour les plats et les accompagnements, sur toutes les colonnes
    /// de la table §6.4, unité et poids d'unité compris. Le `defaultGrams` vaut le poids
    /// d'une unité : on tape une part, pas 137 grammes de tarte.
    func testLesCinqDessertsDeBrasserieRetombentSurLaSpec() {
        XCTAssertEqual(Self.dessertsDeBrasserie.count, 5,
                       "la table de référence n'a plus cinq lignes")
        for spec in Self.dessertsDeBrasserie {
            guard let item = catalog.items.first(where: { $0.id == spec.id }) else {
                XCTFail("dessert manquant du catalogue : \(spec.id)")
                continue
            }
            XCTAssertEqual(item.name, spec.name, "\(spec.id) : nom")
            XCTAssertEqual(item.emoji, spec.emoji, "\(spec.id) : emoji")
            XCTAssertEqual(item.kcalPer100g, spec.kcal, "\(spec.id) : kcal/100 g")
            XCTAssertEqual(item.unitLabel, spec.unite, "\(spec.id) : unité")
            XCTAssertEqual(item.unitGrams, spec.poidsUnite, "\(spec.id) : poids d'une unité")
            XCTAssertEqual(item.defaultGrams, spec.poidsUnite, "\(spec.id) : portion")
            // « ramequins » et « parts » prennent un s : le pluriel explicite ne sert
            // qu'aux invariables, et l'écrire ici ferait lire « 2 parts » deux fois.
            XCTAssertNil(item.unitLabelPlural, "\(spec.id) : pluriel régulier, donc nil")
            XCTAssertEqual(item.category, .dessert, "\(spec.id) : catégorie")
            XCTAssertEqual(item.slots, [], "\(spec.id) : créneaux")
            XCTAssertFalse(item.isRecipe, "\(spec.id) : ce n'est pas une recette")
            XCTAssertEqual(catalog.hasTag("richDessert", itemID: spec.id), spec.gourmand,
                           "\(spec.id) : tag richDessert")
        }
    }

    /// L'île flottante est la seule ligne de la table §6.4 qui dit « non » au tag, donc
    /// la seule qu'une transcription distraite alignerait sur ses voisines. Le test
    /// ci-dessus la couvre déjà par sa colonne ; celui-ci l'énonce en clair, avec sa
    /// raison, pour que le « non » ne passe pas pour un oubli à la relecture.
    func testLIleFlottanteNEstPasUnDessertGourmand() {
        XCTAssertFalse(catalog.hasTag("richDessert", itemID: "ile_flottante"),
                       "130 kcal/100 g : plus légère que la compote, qui n'est pas taguée")
        XCTAssertFalse(catalog.hasTag("richDessert", itemID: "compote"))
    }

    /// Doublon VOULU (spec §6.3) : le même gratin existe en plat et en accompagnement,
    /// pour qu'il puisse accompagner une viande. Les deux kcal sont épinglées ENSEMBLE :
    /// deux valeurs différentes pour le même gratin seraient un défaut, pas une nuance.
    /// `testLesNomsSontUniquesParCategorie` autorise ce doublon, l'unicité étant par
    /// catégorie ; ce test-ci empêche qu'on le « corrige » un jour par mégarde.
    func testLeGratinDauphinoisExisteDansLesDeuxCategories() throws {
        let plat = try XCTUnwrap(catalog.items.first { $0.id == "gratin_dauphinois" })
        let accompagnement = try XCTUnwrap(catalog.items.first { $0.id == "gratin_dauphinois_side" })
        XCTAssertEqual(plat.category, .dish)
        XCTAssertEqual(accompagnement.category, .side)
        XCTAssertEqual(plat.name, accompagnement.name)
        XCTAssertEqual(plat.kcalPer100g, accompagnement.kcalPer100g)
    }
}

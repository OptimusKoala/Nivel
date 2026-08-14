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
    ///   dans un onglet ni parmi les aliments ordinaires, et les 30 plats restent 30.
    ///
    /// C'est la seconde ligne qui tient le lien avec `testChaqueOngletAfficheSonNombreDItems` :
    /// les onglets ne montrant pas les recettes, la somme des cinq catégories doit
    /// faire le compte des aliments ORDINAIRES, pas la taille du fichier.
    func testLaTailleDuCatalogue() {
        XCTAssertEqual(catalog.items.count, 157, "le catalogue ne compte plus 157 entrées")
        XCTAssertEqual(catalog.items.filter { !$0.isRecipe }.count, 122,
                       "les aliments ordinaires ne sont plus 122")
    }

    // MARK: Catalogue v1 (spec v1.10)

    /// Renommé en 1.14 : ce test comptait le catalogue, il compte maintenant les
    /// ONGLETS. `items(category:slot:)` écarte les recettes (§6.1) — aux tâches
    /// suivantes du lot D, `foods.json` gagnera des plats sans que le 30 ci-dessous
    /// bouge. Le garde-fou de transcription est devenu un détecteur de recette qui
    /// fuit dans la grille de taps ; la dernière assertion rétablit le lien avec la
    /// taille réelle du fichier.
    func testChaqueOngletAfficheSonNombreDItems() throws {
        XCTAssertEqual(catalog.items(category: .drink, slot: nil).count, 15)
        XCTAssertEqual(catalog.items(category: .snack, slot: nil).count, 9)     // 12 − 3 déménagés
        XCTAssertEqual(catalog.items(category: .dish, slot: nil).count, 30)
        // Épinglé et non borné par un `>=` : la borne à 40 datait d'un onglet à 42 items
        // et ne gardait plus rien une fois passé à 58. C'est le dernier compte de
        // catégorie du fichier qui n'était pas exact.
        XCTAssertEqual(catalog.items(category: .side, slot: nil).count, 58)
        XCTAssertEqual(catalog.items(category: .dessert, slot: nil).count, 10)
        // Le lien avec `testLaTailleDuCatalogue` : ces cinq comptes couvrent tous les
        // aliments ordinaires, et rien d'autre. Un item qui disparaîtrait de son onglet
        // sans être une recette tomberait ici plutôt que nulle part.
        XCTAssertEqual(15 + 9 + 30 + 58 + 10, catalog.items.filter { !$0.isRecipe }.count)
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
        XCTAssertEqual(richDessert, ["choco_bar", "ice_cream", "croissant",
                                     "cake", "fruit_tart", "choco_mousse", "crepe_sugar"])
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

    // MARK: Dix desserts (spec v1.14 §3.4)

    func testLesDixDessertsSontComplets() {
        let desserts = catalog.items.filter { $0.category == .dessert }
        XCTAssertEqual(desserts.count, 10, "sept nouveaux + trois déménagés")
        for id in ["fruit_salad", "cake", "fruit_tart", "choco_mousse",
                   "crepe_sugar", "skyr", "greek_yogurt",
                   "choco_square", "ice_cream", "compote"] {
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
        XCTAssertEqual(shown.count, 30, "les trente plats ordinaires, ni plus ni moins")
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
        // Ignoré tant que la Task 2 du lot D n'a pas ajouté les deux premières
        // recettes à `foods.json` : elle rétablira ce test en même temps.
        try XCTSkipIf(!catalog.items.contains { $0.isRecipe },
                      "aucune recette dans foods.json avant la Task 2 du lot D")
        let recipe = catalog.items.first { $0.isRecipe }!
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
}

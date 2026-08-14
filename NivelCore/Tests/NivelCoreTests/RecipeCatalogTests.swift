// Recettes de saison (spec v1.14 §6.2) : le catalogue ne porte que la saison et la
// préparation — tout le reste vient de l'aliment correspondant.
import XCTest
@testable import NivelCore

final class RecipeCatalogTests: XCTestCase {
    /// Les deux bornes de ce fichier sont écrites ICI, une fois, et lues par les tests
    /// de données comme par la fixture qui les exerce (`testLesDeuxBornesSontTenuesParUneFixture`).
    /// Recopiées en littéral dans chaque test, elles se desserreraient sans qu'aucun
    /// autre ne bronche ; partagées, toucher à l'une fait rougir la fixture.
    private static let toleranceDuRepli = 0.1
    private static let etapesAttendues = 3...4

    func testLesRecettesSeChargentEtPointentVersDeVraisAliments() throws {
        let recipes = try Catalogs.recipes()
        let catalog = try FoodCatalog.load()
        XCTAssertFalse(recipes.isEmpty)
        for recipe in recipes {
            guard let item = catalog.byID[recipe.itemID] else {
                // `continue` et non le `return` du plan, qui sortirait de la BOUCLE :
                // sur trois recettes orphelines on veut les trois dans le rapport,
                // pas la première puis un arrêt. Règle écrite à
                // `BadgeEngineTests.swift:104`, et qui coûte sinon un aller-retour
                // complet par faute — la Task 3 en écrit trente-trois d'un coup.
                XCTFail("recette sans aliment : \(recipe.itemID)")
                continue
            }
            XCTAssertTrue(item.isRecipe, "\(recipe.itemID) doit porter isRecipe")
            XCTAssertTrue(catalog.line(for: item).isComposed, "\(recipe.itemID) sans composition")
        }
    }

    /// `RecipeCatalog.init` avale un `itemID` en double sans un mot
    /// (`uniquingKeysWith: { a, _ in a }`), et c'est voulu : mieux vaut une recette
    /// perdue qu'une app qui ne démarre pas, règle des six autres catalogues. Mais
    /// alors PLUS RIEN ne signale un id écrit deux fois dans `recipes.json` — c'est
    /// ici, et nulle part ailleurs, que ça se voit. Même garde que
    /// `FoodCatalogTests.testPasDeDoublonDId`.
    func testPasDeDoublonDItemID() throws {
        let recipes = try Catalogs.recipes()
        XCTAssertEqual(Set(recipes.map(\.itemID)).count, recipes.count)
        // Redondante par construction : `byItemID.count` VAUT le nombre d'ids
        // distincts, donc cette ligne réaffirme le prédicat de celle du dessus et
        // tombe avec elle. Elle n'ajoute aucun pouvoir de détection ; ce qu'elle
        // fait de son propre chef, c'est exercer `RecipeCatalog.load()`.
        XCTAssertEqual(try RecipeCatalog.load().byItemID.count, recipes.count)
    }

    func testLesMoisSontValides() throws {
        for recipe in try Catalogs.recipes() {
            XCTAssertFalse(recipe.months.isEmpty, recipe.itemID)
            for month in recipe.months {
                XCTAssertTrue((1...12).contains(month), "\(recipe.itemID) : mois \(month)")
            }
            XCTAssertEqual(Set(recipe.months).count, recipe.months.count,
                           "\(recipe.itemID) : mois en doublon")
        }
    }

    func testLaPreparationFaitTroisOuQuatreLignes() throws {
        for recipe in try Catalogs.recipes() {
            XCTAssertTrue(Self.etapesAttendues.contains(recipe.steps.count),
                          "\(recipe.itemID) : \(recipe.steps.count) lignes")
            for step in recipe.steps {
                // Trimé, comme `ActivityCatalogTests.testEveryActivityHasInstructions` :
                // `isEmpty` seul laisse passer une ligne d'espaces, qui donnerait une
                // puce vide dans la fiche recette sans qu'un test ne bronche. La
                // Task 3 écrit ~132 de ces chaînes à la main.
                XCTAssertFalse(step.trimmingCharacters(in: .whitespaces).isEmpty, recipe.itemID)
            }
        }
    }

    /// Une recette DOIT porter un créneau : la bande d'idées propose « pour ce
    /// midi » ou « pour ce soir », jamais « à un moment ».
    func testChaqueRecetteAUnCreneau() throws {
        let catalog = try FoodCatalog.load()
        for recipe in try Catalogs.recipes() {
            let slots = catalog.byID[recipe.itemID]?.slots ?? []
            XCTAssertFalse(slots.isEmpty, "\(recipe.itemID) sans créneau")
            XCTAssertTrue(slots.allSatisfy { $0 == .lunch || $0 == .dinner }, "\(recipe.itemID)")
        }
    }

    /// Les deux recettes de la Task 2 valident la chaîne de bout en bout, et
    /// `isInSeason(month:)` dans les DEUX sens : l'une est d'été, l'autre d'hiver.
    ///
    /// Les sondes sont posées sur les BORDS des plages, jamais au milieu. Une sonde
    /// intérieure (le mois 8 dans `[5,6,7,8,9]`) ne prouve rien : la plage décalée
    /// d'un mois contient toujours 8. Or la faute plausible ici n'est pas
    /// d'inverser `contains` — personne ne le fera — mais d'écrire une plage
    /// décalée d'un mois dans `recipes.json`, ou un `month ± 1` dans `isInSeason`.
    /// Seuls les quatre mois de bordure de chaque plage l'attrapent.
    func testLesDeuxPremieresRecettesCouvrentDeuxSaisons() throws {
        // `first(where:)` et non un dictionnaire construit à la volée : sur un
        // `recipes.json` en doublon, `Dictionary(uniqueKeysWithValues:)` PLANTE le
        // processus de test entier — et fait donc disparaître le rouge de
        // `testPasDeDoublonDItemID`, seul test capable de nommer le vrai défaut.
        let recipes = try Catalogs.recipes()
        // Été, mai à septembre : les deux bords dedans, les deux mois qui les
        // encadrent dehors.
        let ete = try XCTUnwrap(recipes.first { $0.itemID == "cod_papillote" })
        XCTAssertTrue(ete.isInSeason(month: 5), "mai est le premier mois de la plage")
        XCTAssertTrue(ete.isInSeason(month: 9), "septembre est le dernier")
        XCTAssertFalse(ete.isInSeason(month: 4))
        XCTAssertFalse(ete.isInSeason(month: 10))

        // Hiver, novembre à mars : la plage passe par le nouvel an, ses bords sont
        // donc 11 et 3, et ce sont bien 10 et 4 qui l'encadrent.
        let hiver = try XCTUnwrap(recipes.first { $0.itemID == "leek_potato_soup" })
        XCTAssertTrue(hiver.isInSeason(month: 11), "novembre est le premier mois de la plage")
        XCTAssertTrue(hiver.isInSeason(month: 3), "mars est le dernier")
        XCTAssertFalse(hiver.isInSeason(month: 10))
        XCTAssertFalse(hiver.isInSeason(month: 4))

        // Et les deux saisons sont bien opposées : chacune est hors saison au cœur
        // de l'autre.
        XCTAssertFalse(ete.isInSeason(month: 1))
        XCTAssertFalse(hiver.isInSeason(month: 8))
    }

    func testLeCatalogueVideEstLeRepli() {
        XCTAssertTrue(RecipeCatalog.empty.recipes.isEmpty)
    }

    // MARK: Couverture des trente-cinq recettes (Task 3)

    func testLeCatalogueCompteTrenteCinqRecettes() throws {
        XCTAssertEqual(try Catalogs.recipes().count, 35)
    }

    /// Aucun mois sans idée, ni pour le midi ni pour le soir. Le seuil est QUATRE et
    /// non trois : la bande en montre trois, et il faut au moins une candidate de
    /// rab pour que la rotation du jour ait de quoi tourner (spec §6.4 règle 7).
    func testChaqueMoisAQuatreIdeesParCreneau() throws {
        let recipes = try Catalogs.recipes()
        let catalog = try FoodCatalog.load()
        for month in 1...12 {
            for slot in [MealSlot.lunch, .dinner] {
                let count = recipes.filter { recipe in
                    recipe.months.contains(month)
                        && (catalog.byID[recipe.itemID]?.slots.contains(slot) ?? false)
                }.count
                XCTAssertGreaterThanOrEqual(count, 4, "mois \(month), créneau \(slot)")
            }
        }
    }

    /// Chaque ingrédient d'une recette doit être un `.side` : `PantryView` ne liste
    /// que ceux-là, donc une recette citant un plat ou un encas ne pourrait JAMAIS
    /// atteindre la couverture complète dans l'app réelle — la carte afficherait
    /// « il manque 1 » à vie, sans que rien ne l'explique.
    func testChaqueIngredientDeRecetteEnEstUn() throws {
        let catalog = try FoodCatalog.load()
        for recipe in try Catalogs.recipes() {
            // `guard … continue` et non `byID[...]!` : XCTest joue les tests d'une
            // classe par ordre alphabétique, et celui-ci passe AVANT
            // `testLesRecettesSeChargentEtPointentVersDeVraisAliments`, le seul qui
            // sache nommer une recette sans aliment. Un déballage forcé tuerait le
            // processus sur un `signal 5` muet avant que le diagnostic ait la parole.
            guard let item = catalog.byID[recipe.itemID] else { continue }
            for component in catalog.line(for: item).components {
                XCTAssertEqual(catalog.byID[component.itemID]?.category, .side,
                               "\(recipe.itemID) → \(component.itemID) n'est pas un ingrédient")
            }
        }
    }

    /// Le repli tel que l'APP le calculera, et non sa formule recopiée à la main :
    /// `line(for:)` rend un `.simple` dès que la composition manque, et c'est
    /// `MealEstimator` — son arrondi compris — qui en fait des kcal. Un test qui
    /// refait le calcul de son côté tient l'arithmétique ; celui-ci tient le code.
    private func repli(of item: FoodItem, in catalog: FoodCatalog) -> Int {
        MealEstimator.kcal(
            lines: [.simple(MealComponent(itemID: item.id, grams: item.defaultGrams))],
            kcalPer100g: catalog.kcalPer100g)
    }

    /// Le repli du plat composé (spec §3.1) : `kcalPer100g × defaultGrams` doit rester
    /// à ~10 % du total de la composition. Rien ne le vérifiait pour des entrées
    /// écrites à la main, et un repli faux ne se voit que le jour où il sert.
    func testLeRepliDeChaqueRecetteSuitSaComposition() throws {
        let catalog = try FoodCatalog.load()
        for recipe in try Catalogs.recipes() {
            guard let item = catalog.byID[recipe.itemID] else { continue }
            let composed = MealEstimator.kcal(lines: [catalog.line(for: item)],
                                              kcalPer100g: catalog.kcalPer100g)
            let fallback = repli(of: item, in: catalog)
            XCTAssertEqual(Double(fallback), Double(composed),
                           accuracy: Double(composed) * Self.toleranceDuRepli,
                           "\(recipe.itemID) : repli \(fallback) vs composition \(composed)")
        }
    }

    /// Les deux bornes que les DONNÉES ne tiennent pas, épinglées ici par deux moyens
    /// différents : `toleranceDuRepli` sur un catalogue de laboratoire — même procédé
    /// que `FoodCatalogTests.testLeFiltreEcarteUneRecetteDeSaCategorie` —, et
    /// `etapesAttendues` par quatre assertions directes sur la constante, sans recette
    /// ni catalogue. La seconde n'a pas besoin de plus, la première ne peut pas s'en
    /// contenter : c'est tout le chemin du repli qu'il faut exercer.
    ///
    /// Ce que les trente-cinq recettes tiennent réellement du `toleranceDuRepli` :
    /// presque rien. Leur pire écart est de 0,89 % (`leek_potato_soup`), donc le test de
    /// données passe encore à 0.05 et ne rougit qu'en dessous de 0.009 ; le desserrer à
    /// 0.5 ne rougirait nulle part. C'est donc la fixture qui tient les DEUX bords : le
    /// `dedans` à +9 % rougit dès qu'on passe sous 0.09, le `dehors` à +11 % dès qu'on
    /// atteint 0.11. Fenêtre silencieuse restante : [0.09, 0.11).
    ///
    /// Et ces deux-là ne peuvent pas être de vraies recettes : un repli hors bande, c'est
    /// une donnée fausse livrée à l'utilisateur, qui se verrait débiter quinze kcal de
    /// trop le jour où elle sert. C'est le métier de l'app.
    func testLesDeuxBornesSontTenuesParUneFixture() {
        XCTAssertTrue(Self.etapesAttendues.contains(3), "trois lignes suffisent")
        XCTAssertTrue(Self.etapesAttendues.contains(4))
        XCTAssertFalse(Self.etapesAttendues.contains(2), "deux lignes ne sont pas une préparation")
        XCTAssertFalse(Self.etapesAttendues.contains(5), "cinq lignes ne tiennent pas dans la fiche")

        let ingredient = FoodItem(id: "ing", name: "Ingrédient", emoji: "🥦",
                                  kcalPer100g: 100, category: .side, defaultGrams: 100)
        // Deux recettes de laboratoire à 100 kcal de composition PILE : seul leur repli
        // diffère, +9 % pour l'une et +11 % pour l'autre, au plus près du seuil de part
        // et d'autre. Un `dehors` plus loin — 125, par exemple — laisserait la tolérance
        // monter jusqu'à 0.249 sans une rougeur.
        let dedans = FoodItem(id: "dedans", name: "Dedans", emoji: "🍽", kcalPer100g: 109,
                              category: .dish, defaultGrams: 100, isRecipe: true)
        // 111 et non 110 : `100.0 * 0.1` vaut 10.000000000000002 en `Double`, et un écart
        // de 10 pile retomberait DEDANS — la fixture serait rouge sans rien prouver.
        let dehors = FoodItem(id: "dehors", name: "Dehors", emoji: "🍽", kcalPer100g: 111,
                              category: .dish, defaultGrams: 100, isRecipe: true)
        let composition = [MealComponent(itemID: "ing", grams: 100)]
        let labo = FoodCatalog(items: [ingredient, dedans, dehors],
                               byID: ["ing": ingredient, "dedans": dedans, "dehors": dehors],
                               compositions: ["dedans": composition, "dehors": composition])

        for (item, attendu) in [(dedans, true), (dehors, false)] {
            let composed = MealEstimator.kcal(lines: [labo.line(for: item)],
                                              kcalPer100g: labo.kcalPer100g)
            let fallback = repli(of: item, in: labo)
            XCTAssertEqual(abs(Double(fallback) - Double(composed)) <= Double(composed) * Self.toleranceDuRepli,
                           attendu, "\(item.id) : repli \(fallback) pour \(composed) kcal")
        }
    }

    /// Une suggestion « légère » qui dépasse son plafond n'est pas une suggestion légère.
    /// La spec §6.2 écrit « sous ~500 kcal » : les vingt kcal ci-dessous SONT ce tilde,
    /// écrits une fois pour toutes plutôt que laissés à l'appréciation du rédacteur. Le
    /// seuil lui-même n'est tenu par aucune donnée — la plus lourde des trente-cinq est
    /// à 511 (`veg_flatbread`) — et c'est bien un plafond, pas une cible.
    func testAucuneRecetteNeDepasseCinqCentVingtKcal() throws {
        let catalog = try FoodCatalog.load()
        for recipe in try Catalogs.recipes() {
            guard let item = catalog.byID[recipe.itemID] else { continue }
            let kcal = MealEstimator.kcal(lines: [catalog.line(for: item)],
                                          kcalPer100g: catalog.kcalPer100g)
            XCTAssertLessThanOrEqual(kcal, 520, "\(recipe.itemID) : \(kcal) kcal")
        }
    }
}

// Recettes de saison (spec v1.14 §6.2) : le catalogue ne porte que la saison et la
// préparation — tout le reste vient de l'aliment correspondant.
import XCTest
@testable import NivelCore

final class RecipeCatalogTests: XCTestCase {
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
            XCTAssertTrue((3...4).contains(recipe.steps.count),
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
}

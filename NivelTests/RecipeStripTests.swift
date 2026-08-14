// NivelTests/RecipeStripTests.swift
// La bande d'idées de saison (spec v1.14 §6.4 et §6.5).
//
// ⚠️ CE QUE CETTE SUITE NE COUVRE PAS, et il faut le lire avant de s'y fier.
//
// Les décisions de la bande sont descendues dans des fonctions pures — le cadrage
// (`framing`), le titre, l'état du frigo, le libellé d'accessibilité, les lignes du
// titre, la ligne du panier. Ce qui les appelle, en revanche, échappe presque
// entièrement à cette suite : rien ici ne rend une vue.
//
//   remplacer `RecipeStrip.framing(...)` par autre chose dans `MealsJournalView`
//   laisse cette suite ENTIÈREMENT VERTE.
//
// Concrètement : rendre le créneau par `MealSlot.suggested(forHour:)`, ou supprimer
// le `guard isToday` en le remplaçant par un `if true` dans la vue, ne fait rougir
// aucune assertion écrite ici — `testChaqueHeureDeChaqueMoisDonneUneBandePleine`
// appelle `RecipeSuggester` directement, donc il tient le CATALOGUE, pas le câblage.
// Même limite qu'à `CalorieRingLegendTests` (lot C, `showsBurnLegend`).
//
// Deux exceptions, dans ce fichier et à côté :
//
// - `testLaFeuilleSOuvreSurUnPanierDejaGarni` INSTANCIE `MealLogSheet` et lit ses
//   `@State` au `Mirror`. C'est laid, et c'est la seule façon d'éprouver un init de
//   vue ici ;
// - le câblage du journal — le créneau annoncé par la bande, celui que la feuille de
//   saisie pré-sélectionne, et l'absence de bande un jour passé — est tenu par
//   `NivelUITests/IdeasJourneyTests`, qui pilote la vraie app. Cette cible existe
//   depuis la 1.13 (`BasketSwipeTests`) et vit dans le schéma NivelPreview, hors des
//   tests de tous les jours : elle se lance à la main, et l'en-tête d'IdeasJourney
//   dit comment.

import XCTest
import SwiftUI
import NivelCore
@testable import Nivel

final class RecipeStripTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }

    private func date(month: Int, day: Int = 15, hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month,
                                                         day: day, hour: hour)))
    }

    // MARK: Le cadrage : afficher ou non, quel créneau, quel mois

    /// Les trois décisions d'un coup, sur un instant donné.
    func testLeCadrageDonneLeCreneauEtLeMoisDuJour() throws {
        let midi = RecipeStrip.framing(at: try date(month: 8, hour: 12), isToday: true,
                                       calendar: calendar)
        XCTAssertEqual(midi, RecipeStrip.Framing(slot: .lunch, month: 8))

        let soir = RecipeStrip.framing(at: try date(month: 1, hour: 20), isToday: true,
                                       calendar: calendar)
        XCTAssertEqual(soir, RecipeStrip.Framing(slot: .dinner, month: 1))
    }

    /// Un jour passé n'a pas de bande : les jours antérieurs sont en lecture seule
    /// depuis la v1, une idée de dîner pour mardi dernier serait un mensonge. Le
    /// `nil` porte la décision — la vue n'a plus qu'à ne rien afficher.
    func testUnJourPasseNAPasDeBande() throws {
        XCTAssertNil(RecipeStrip.framing(at: try date(month: 8, hour: 12), isToday: false,
                                         calendar: calendar))
        XCTAssertNil(RecipeStrip.framing(at: try date(month: 8, hour: 20), isToday: false,
                                         calendar: calendar))
    }

    // MARK: Le créneau visé

    /// Déjeuner jusqu'à 15 h, dîner ensuite (spec §6.4 règle 2). La bascule est à
    /// QUINZE heures, et les deux bords en sont éprouvés : 14 h donne encore midi,
    /// 15 h donne déjà le soir.
    func testLeCreneauSuitLHeure() {
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 0), .lunch)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 9), .lunch)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 14), .lunch)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 15), .dinner)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 21), .dinner)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 23), .dinner)
    }

    /// LE piège de cette tâche, épinglé par son heure exacte. `MealSlot.suggested`
    /// répond à « quel repas l'utilisateur est-il en train de noter » et rend `.snack`
    /// en milieu d'après-midi — un créneau qu'AUCUNE recette ne porte. Réutilisée pour
    /// la bande, elle la viderait tous les jours entre 16 h et 18 h, sans rien casser
    /// d'autre. Ce test rougit à la première tentative de mutualiser les deux — dans
    /// `RecipeStrip`, et là seulement (voir l'en-tête du fichier).
    func testLaBandeNeReprendPasLeCreneauDeLaSaisie() {
        XCTAssertEqual(MealSlot.suggested(forHour: 16), .snack)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 16), .dinner)
        XCTAssertEqual(MealSlot.suggested(forHour: 9), .breakfast)
        XCTAssertEqual(RecipeStrip.targetSlot(forHour: 9), .lunch)
    }

    /// La conséquence, sur les VRAIS catalogues et par le cadrage complet : à
    /// n'importe quelle heure de n'importe quel mois, la bande est pleine. C'est
    /// l'assertion qui crie si le créneau est emprunté à la saisie — `.snack` et
    /// `.breakfast` ne ramènent aucune recette, et la bande serait vide.
    func testChaqueHeureDeChaqueMoisDonneUneBandePleine() throws {
        let foods = try FoodCatalog.load()
        let recipes = try RecipeCatalog.load()

        for month in 1...12 {
            for hour in 0...23 {
                let day = try date(month: month, hour: hour)
                let framing = try XCTUnwrap(RecipeStrip.framing(at: day, isToday: true,
                                                                calendar: calendar))
                let suggestions = RecipeSuggester.suggestions(
                    date: day, slot: framing.slot, pantry: [], recipes: recipes,
                    foods: foods, calendar: calendar
                )
                XCTAssertEqual(suggestions.count, 3, "mois \(month), \(hour) h")
            }
        }
    }

    // MARK: Le titre

    func testLeTitreNommeLeCreneauEtLeMois() {
        XCTAssertEqual(RecipeStrip.title(slot: .dinner, month: 8), "Idées pour ce soir · août")
        XCTAssertEqual(RecipeStrip.title(slot: .lunch, month: 1), "Idées pour ce midi · janvier")
        XCTAssertEqual(RecipeStrip.title(slot: .lunch, month: 12), "Idées pour ce midi · décembre")
    }

    /// Mois hors bornes : le titre perd son mois plutôt que son texte. Sans ce repli,
    /// l'indexation du tableau des mois plante ; avec un repli muet, le titre
    /// afficherait « Idées pour ce soir ·  » et son point médian orphelin.
    func testUnMoisHorsBornesNeLaissePasDeSeparateurOrphelin() {
        XCTAssertEqual(RecipeStrip.title(slot: .dinner, month: 0), "Idées pour ce soir")
        XCTAssertEqual(RecipeStrip.title(slot: .lunch, month: 13), "Idées pour ce midi")
    }

    // MARK: Le titre d'une carte

    /// Le titre gagne des lignes aux tailles d'accessibilité. Deux lignes y suffisaient
    /// à « Omelette » mais coupaient « Gaspacho et pain grillé » en « Gaspa-cho e… »,
    /// alors même que la carte y est plus large — les mots grossissent plus vite que
    /// la carte. Même forme que `CalorieRing.showsBurnLegend(at:)` : la décision est
    /// statique, donc éprouvable ; sa pose ne l'est pas, et se relève à l'image.
    func testLeTitreGagneDesLignesAuxTaillesDAccessibilite() {
        XCTAssertEqual(RecipeStrip.titleLineLimit(at: .large), 2)
        XCTAssertEqual(RecipeStrip.titleLineLimit(at: .xxxLarge), 2)
        XCTAssertEqual(RecipeStrip.titleLineLimit(at: .accessibility1), 4)
        XCTAssertEqual(RecipeStrip.titleLineLimit(at: .accessibility5), 4)
    }

    // MARK: L'état du frigo

    /// Un constat, jamais un reproche (règle v1 §7.4) : « Il manque 2 » ne dit pas
    /// quoi faire. Le singulier est là aussi, parce que « Il manque 1 » est la seule
    /// des trois branches qu'on oublie d'écrire.
    func testLEtatDuFrigoSeDitEnDeuxPhrases() {
        XCTAssertEqual(RecipeStrip.frPantryState(missingCount: 0, pantryIsEmpty: false),
                       "Tu as tout ✓")
        XCTAssertEqual(RecipeStrip.frPantryState(missingCount: 1, pantryIsEmpty: false),
                       "Il manque 1")
        XCTAssertEqual(RecipeStrip.frPantryState(missingCount: 4, pantryIsEmpty: false),
                       "Il manque 4")
    }

    /// Frigo vide, la carte SE TAIT. « Il manque 4 » compterait alors ce qu'on ignore
    /// et non ce qui manque, et contredirait la fiche recette, qui n'affiche aucune
    /// marque dans ce cas et invite à cocher.
    func testFrigoVideLaCarteNeCompteRien() {
        XCTAssertNil(RecipeStrip.frPantryState(missingCount: 4, pantryIsEmpty: true))
        // Y compris quand rien ne manque : sans coche, « Tu as tout ✓ » serait un
        // hasard, pas un constat.
        XCTAssertNil(RecipeStrip.frPantryState(missingCount: 0, pantryIsEmpty: true))
    }

    /// Ce que VoiceOver lit — la même règle, donc pas de contradiction possible entre
    /// ce qui est écrit sur la carte et ce qui en est annoncé.
    func testLeLibelleDAccessibiliteSuitLaMemeRegle() {
        XCTAssertEqual(
            RecipeStrip.frCardLabel(name: "Gaspacho", kcal: 352, missingCount: 2,
                                    pantryIsEmpty: false),
            "Gaspacho, environ 352 kcal, Il manque 2"
        )
        XCTAssertEqual(
            RecipeStrip.frCardLabel(name: "Gaspacho", kcal: 352, missingCount: 4,
                                    pantryIsEmpty: true),
            "Gaspacho, environ 352 kcal"
        )
    }

    // MARK: De la fiche au journal

    /// La ligne que « Noter ce repas » rend au journal, prise à la fonction que la
    /// fiche appelle vraiment. Composer les mêmes composants à la main passerait le
    /// panier et mentirait au journal : l'id de la ligne serait celui du premier
    /// ingrédient, donc « Légumes de soupe +3 » au lieu du nom de la recette.
    func testLaFicheRendLaLigneDeLaRecetteEtNonSesIngredients() throws {
        let foods = try FoodCatalog.load()
        let recipes = try RecipeCatalog.load()
        let recipe = try XCTUnwrap(recipes.byItemID["leek_potato_soup"])

        let line = try XCTUnwrap(RecipeDetailSheet.basketLine(for: recipe, foods: foods))
        XCTAssertTrue(line.isComposed)
        XCTAssertEqual(line.itemID, "leek_potato_soup")
        XCTAssertGreaterThan(line.components.count, 1)
        // Le bout de la chaîne : ce que le journal affichera.
        XCTAssertEqual(MealFormatting.frSummary(lines: [line], catalog: foods),
                       "Soupe poireaux-pommes de terre")
    }

    /// Recette absente du catalogue d'aliments (JSON corrompu) : rien à noter, et le
    /// bouton se désactive. Pas de ligne bricolée sur un id fantôme.
    func testUneRecetteInconnueDuCatalogueNeDonneAucuneLigne() throws {
        // Décodée et non construite : le mémberwise init de `Recipe` est interne à
        // NivelCore, et une recette de laboratoire se fabrique donc par son JSON —
        // exactement le chemin que prend le catalogue livré.
        let json = #"{ "itemID": "plat_fantome", "months": [1], "steps": ["Rien"] }"#
        let orpheline = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        XCTAssertNil(RecipeDetailSheet.basketLine(for: orpheline, foods: .empty))
    }

    /// L'init de la feuille de saisie ouverte depuis une suggestion : le panier arrive
    /// GARNI de la ligne, sur le créneau visé par la bande. Lu par réflexion sur les
    /// `@State` — c'est laid, mais c'est la seule façon d'éprouver un init de vue dans
    /// ce dépôt, et sans cela la fonctionnalité entière peut disparaître (`[line]`
    /// devenant `[]`) sans qu'une seule assertion bronche.
    @MainActor
    func testLaFeuilleSOuvreSurUnPanierDejaGarni() throws {
        let foods = try FoodCatalog.load()
        let item = try XCTUnwrap(foods.byID["lentil_salad"])
        let line = foods.line(for: item)

        let sheet = MealLogSheet(prefilled: line, slot: .dinner)
        let children = Mirror(reflecting: sheet).children

        let lines = try XCTUnwrap(children.first { $0.label == "_lines" }?.value as? State<[MealLine]>)
        XCTAssertEqual(lines.wrappedValue, [line])
        let slot = try XCTUnwrap(children.first { $0.label == "_slot" }?.value as? State<MealSlot>)
        XCTAssertEqual(slot.wrappedValue, .dinner)
        // Aucune saisie manuelle héritée : la feuille estime, comme un repas neuf.
        let manual = try XCTUnwrap(children.first { $0.label == "_manualKcal" }?.value as? State<Int?>)
        XCTAssertNil(manual.wrappedValue)
    }

    /// Un panier pré-rempli n'est pas vide : le garde de fermeture du lot A s'arme
    /// d'office sur la feuille ouverte depuis une suggestion, et la recette ne se
    /// jette pas d'un glissement distrait. (Ce test-ci tient la RÈGLE, écrite en
    /// 1.13 ; c'est celui du dessus qui tient le pré-remplissage.)
    func testLePanierPreRempliArmeLeGardeDeFermeture() throws {
        let foods = try FoodCatalog.load()
        let item = try XCTUnwrap(foods.byID["lentil_salad"])
        XCTAssertTrue(MealLogSheet.guardsDismissal(lines: [foods.line(for: item)]))
    }
}

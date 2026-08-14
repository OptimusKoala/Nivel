// NivelTests/ScreenshotIdeasTests.swift
// Le jeu de démonstration de la capture App Store des idées de saison (lot F, §7).
//
// Ce que cette suite tient, et qu'aucune autre ne voit :
//
// - le frigo de démonstration reste VIDE hors des écrans d'idées. C'est l'état de
//   départ de `NivelUITests/IdeasJourneyTests`, qui coûte deux minutes et vit hors du
//   schéma quotidien : le jour où quelqu'un garnira `seed` sans condition, la rougeur
//   doit arriver ici, en une seconde, et non deux semaines plus tard ;
// - à la date épinglée, ce frigo-là rend une bande ÉLOQUENTE : une gradation de
//   « Tu as tout ✓ » à « Il manque 2 », trois emoji distincts, et une fiche ouverte
//   toute cochée. Un poids déplacé dans `compositions.json` ou une saison retouchée
//   dans `recipes.json` suffirait à rendre la capture muette (trois cartes complètes,
//   ou trois cartes incomplètes) ou bancale (deux fois la même tomate), et rien
//   d'autre ne le dirait : la capture, elle, ne se relit qu'à l'œil, une fois par
//   version ;
// - l'heure épinglée est celle de la barre d'état que fige `scripts/screenshots.sh`.
//   Les deux sont écrites dans deux fichiers différents, l'une en Swift et l'autre en
//   Bash, et une image qui annonce « ce soir » sous une barre d'état à 9 h 41 se
//   contredit toute seule sur l'App Store.
import XCTest
import SwiftData
import NivelCore
@testable import Nivel

@MainActor
final class ScreenshotIdeasTests: XCTestCase {
    private static let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                                        DayLog.self, GamificationState.self, ActivityEntry.self])

    // MARK: Le frigo du profil de démonstration

    /// Le processus de test n'a pas l'argument `--nivel-screenshots` : `seed` y prend
    /// donc la branche « pas d'écran d'idées », celle de tous les autres écrans, et
    /// c'est exactement celle dont dépendent les trois tests d'interface.
    func testLeFrigoDeDemonstrationResteVideHorsDesEcransDIdees() throws {
        let container = try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)]
        )
        ScreenshotMode.seed(into: container.mainContext)

        let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
        let profile = try XCTUnwrap(profiles.first, "le jeu de démonstration n'a posé aucun profil")
        XCTAssertEqual(profile.pantryItemIDs, [],
                       "le frigo de démonstration est garni hors des écrans d'idées : "
                       + "IdeasJourneyTests part du frigo vide")
    }

    /// Les sept ids sont bien des ingrédients du frigo, et non des plats : le frigo ne
    /// liste que la catégorie `.side`, et un id qui n'en est pas ne serait coché nulle
    /// part — il compterait pourtant dans le classement de la bande.
    func testLesIngredientsDuFrigoDeDemonstrationSontCochablesDansLeFrigo() throws {
        let catalog = try FoodCatalog.load()
        let cochables = Set(PantryContent.ingredients(in: catalog).map(\.id))
        for id in ScreenshotMode.demoPantry {
            XCTAssertTrue(cochables.contains(id),
                          "« \(id) » n'est pas un ingrédient du frigo")
        }
    }

    // MARK: La date épinglée

    /// 9 h 41 pile, comme la barre d'état de `scripts/screenshots.sh` — et donc un
    /// titre au DÉJEUNER, puisque la bande bascule sur le dîner à 15 h.
    func testLaDateEpingleeDitLaMemeHeureQueLaBarreDetat() {
        let calendar = GameService.calendar
        let reference = ScreenshotMode.ideasReferenceDate
        XCTAssertEqual(calendar.component(.hour, from: reference), 9)
        XCTAssertEqual(calendar.component(.minute, from: reference), 41)

        let slot = RecipeStrip.targetSlot(forHour: calendar.component(.hour, from: reference))
        XCTAssertEqual(RecipeStrip.title(slot: slot,
                                         month: calendar.component(.month, from: reference)),
                       "Idées pour ce midi · août")
    }

    /// LE test de la capture : à cette date et avec ce frigo, les trois cartes vont de
    /// « Tu as tout ✓ » à « Il manque 2 ». C'est la GRADATION qui montre que le
    /// classement fait quelque chose — deux cartes complètes côte à côte ne prouvent
    /// que l'arrangement de l'exemple.
    ///
    /// L'assertion ne nomme aucune recette : c'est le contenu du catalogue qui a le
    /// droit de bouger, pas l'éloquence de l'image.
    func testLaBandeEpingleeVaDeTuAsToutAIlManqueDeux() throws {
        let suggestions = try pinnedSuggestions()
        XCTAssertEqual(suggestions.map(\.missingCount), [0, 1, 2],
                       "la bande de la capture ne montre plus la gradation du frigo")
    }

    /// Trois emoji distincts. Deux fois la même tomate côte à côte se lit, sur une
    /// capture App Store, comme un défaut de rendu — et le catalogue en donne
    /// facilement deux, « Tomates et mozzarella » et « Gaspacho » partageant 🍅.
    func testLesTroisCartesDeLaCapturePortentTroisEmojiDistincts() throws {
        let foods = try FoodCatalog.load()
        let emojis = try pinnedSuggestions().map {
            try XCTUnwrap(foods.byID[$0.recipe.itemID]?.emoji)
        }
        XCTAssertEqual(Set(emojis).count, emojis.count,
                       "deux cartes de la capture portent le même emoji : \(emojis)")
    }

    /// La même règle DANS la fiche, dont les ingrédients sont des lignes voisines :
    /// « Olives » et « Huile d'olive » partagent 🫒, et le lecteur d'une capture n'a
    /// aucun moyen de savoir que c'est le catalogue qui le veut. Passe par la fonction
    /// même dont la fiche se sert, `RecipeDetailSheet.basketLine`.
    func testLesIngredientsDeLaFicheOuvertePortentDesEmojiDistincts() throws {
        let foods = try FoodCatalog.load()
        let first = try XCTUnwrap(pinnedSuggestions().first)
        let line = try XCTUnwrap(RecipeDetailSheet.basketLine(for: first.recipe, foods: foods))
        let emojis = try line.components.map {
            try XCTUnwrap(foods.byID[$0.itemID]?.emoji)
        }
        XCTAssertEqual(Set(emojis).count, emojis.count,
                       "deux ingrédients de la fiche portent le même emoji : \(emojis)")
    }

    /// La fiche que le mode captures ouvre d'office est celle de la PREMIÈRE idée : sur
    /// la capture, ses ingrédients doivent être cochés, tous — une fiche à moitié verte
    /// montrerait la fonctionnalité en train d'échouer.
    func testLaFicheOuverteParLeModeCapturesEstUneRecetteComplete() throws {
        let first = try XCTUnwrap(pinnedSuggestions().first)
        XCTAssertEqual(first.missingCount, 0,
                       "la fiche ouverte sur la capture (« \(first.recipe.itemID) ») "
                       + "montrerait des ingrédients manquants")
    }

    // MARK: Outillage

    /// Ce que la bande calculera pendant le tournage : la date et le frigo du mode
    /// captures, passés au vrai moteur et aux vrais catalogues.
    private func pinnedSuggestions() throws -> [RecipeSuggestion] {
        let calendar = GameService.calendar
        let reference = ScreenshotMode.ideasReferenceDate
        return RecipeSuggester.suggestions(
            date: reference,
            slot: RecipeStrip.targetSlot(forHour: calendar.component(.hour, from: reference)),
            pantry: Set(ScreenshotMode.demoPantry),
            recipes: try RecipeCatalog.load(),
            foods: try FoodCatalog.load(),
            calendar: calendar
        )
    }
}
